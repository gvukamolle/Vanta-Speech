# EAS Calendar Sync — Technical Documentation

**Version:** 1.0  
**Last Updated:** January 30, 2026  
**Author:** Vanta Speech Team  

---

## Table of Contents

1. [Overview](#overview)
2. [Exchange ActiveSync Behavior](#exchange-activesync-behavior)
3. [Core Concepts](#core-concepts)
4. [Implementation Details](#implementation-details)
5. [Event Processing Pipeline](#event-processing-pipeline)
6. [Series Grouping Algorithm](#series-grouping-algorithm)
7. [Exception Handling](#exception-handling)
8. [Virtual Master Creation](#virtual-master-creation)
9. [Occurrence Expansion](#occurrence-expansion)
10. [Edge Cases](#edge-cases)
11. [Debugging](#debugging)

---

## Overview

The EAS (Exchange ActiveSync) calendar synchronization system handles complex recurring event scenarios that differ from standard iCal/RRULE behavior. This document explains the architecture and algorithms used to properly sync recurring events from Microsoft Exchange servers.

### Key Challenges Addressed

1. **Content-Based Master Creation**: Exchange creates new master events (with new UIDs) when event content changes (description, attendees, etc.)
2. **Multiple Masters per Series**: A single recurring series may have multiple master events in the sync window
3. **Exception Merging**: Exceptions (modified/deleted occurrences) are scattered across multiple masters
4. **Time Preservation**: Regular occurrences use base time from exceptions, not from master's potentially modified time
5. **Until Date Handling**: Old masters may have restrictive `until` dates that shouldn't limit new occurrences

---

## Exchange ActiveSync Behavior

### How Exchange Handles Recurring Events

Unlike standard calendar systems, Exchange has unique behaviors:

#### 1. Content Change = New Master

When you modify a recurring event's **content** (not just time):
- Exchange creates a **new master** with a **new UID** and **new ServerId**
- Old master remains with its exceptions
- New master starts "fresh" with its own exception list

**Example:**
```
Original: PMO Daily (uid:abc123) from 2025-07-28
After description change: PMO Daily (uid:def456) from 2026-01-27
```

Both masters represent the **same logical series**, but Exchange treats them as separate.

#### 2. Exception Storage

Exceptions are stored **inside** the master event they belong to:

```xml
<ApplicationData>
  <StartTime>20250728T093000Z</StartTime>
  <Recurrence>
    <Type>1</Type>  <!-- Weekly -->
    <DayOfWeek>62</DayOfWeek>  <!-- Mon-Fri -->
  </Recurrence>
  <Exceptions>
    <Exception>
      <Deleted>0</Deleted>
      <StartTime>20251110T140000Z</StartTime>  <!-- Modified time: 14:00 -->
      <OriginalStartTime>20251110T093000Z</OriginalStartTime>  <!-- Original: 09:30 -->
    </Exception>
  </Exceptions>
</ApplicationData>
```

#### 3. Until Date Limitations

Each master has its own `until` date based on when it was created:
- Old master: `until=20260112` (when it was replaced)
- New master: `until=20260407` (current recurrence end)

If we naively use the old master's until date, we'd miss all events after 2026-01-12.

---

## Core Concepts

### Series Key

Instead of grouping by UID (which changes when content changes), we group by **content signature**:

```
Series Key = "{Subject}|{BaseHour}:{BaseMinute}|{RecurrenceType}_{Interval}_{DayOfWeek}"

Example: "PMO Daily|9:30|1_1_62"
```

Components:
- **Subject**: Event title (normalized)
- **BaseTime**: Most common start time from exceptions (hour:minute)
- **Recurrence signature**: Type, interval, and day-of-week mask

### Base Time Detection

For recurring events, we need to know the "standard" time for regular occurrences:

```swift
// Extract time from all exceptions
let timeComponents = exceptions.map { 
    (hour: calendar.component(.hour, from: $0.originalStartTime),
     minute: calendar.component(.minute, from: $0.originalStartTime))
}

// Find most common time (majority vote)
let grouped = Dictionary(grouping: timeComponents) { "\($0.hour):\($0.minute)" }
let baseTime = grouped.max(by: { $0.value.count < $1.value.count })?.key
```

**Why this matters:**
- Master start time might be 15:00 (modified time)
- But regular occurrences should be at 09:30 (original time)
- Exceptions store `originalStartTime` which preserves the base time

### Exception Types

1. **Deleted Exception**: `isDeleted = true`
   - Occurrence was cancelled
   - Should not appear in the calendar

2. **Modified Exception**: `isDeleted = false` + modified fields
   - Time changed (different `startTime` vs `originalStartTime`)
   - Or subject/location changed
   - Uses exception's data instead of master's data

---

## Implementation Details

### File Structure

```
EAS/
├── EASCalendarManager.swift      # Main sync logic
├── EASCalendarEvent.swift        # Event models
├── EASXMLParser.swift            # WBXML parsing
└── API/
    └── EASClient.swift           # Network layer
```

### Key Classes

#### EASCalendarManager

Main actor responsible for:
- Coordinating sync operations
- Processing raw events into expanded occurrences
- Managing cache

#### EASCalendarEvent

Core model representing a calendar event:

```swift
struct EASCalendarEvent: Codable, Equatable, Sendable {
    let id: String                    // ServerId (7:64)
    let uid: String                   // UID from Exchange
    let subject: String
    let startTime: Date
    let endTime: Date
    let recurrence: EASRecurrence?    // nil for single events
    let exceptions: [EASException]?   // Modified/deleted occurrences
    let isException: Bool             // This event is an exception instance
    // ... other fields
}
```

#### EASException

Represents a modified or deleted occurrence:

```swift
struct EASException: Codable, Equatable, Sendable {
    let originalStartTime: Date       // When this occurrence should have been
    let startTime: Date?              // Modified time (nil if deleted)
    let endTime: Date?                // Modified end time
    let isDeleted: Bool               // true = cancelled occurrence
    let subject: String?              // Modified subject (if any)
    let location: String?             // Modified location (if any)
}
```

---

## Event Processing Pipeline

### 1. Fetch Phase

```
┌─────────────────┐
│   EAS Server    │
└────────┬────────┘
         │ Sync Response (WBXML)
         ▼
┌─────────────────┐
│  EASXMLParser   │  → Parse XML into EASCalendarEvent objects
└────────┬────────┘
         │ Array of events
         ▼
┌─────────────────┐
│  processEvents  │  → Group, merge, expand
└─────────────────┘
```

### 2. Processing Phase

```swift
func processEvents(_ events: [EASCalendarEvent]) -> [EASCalendarEvent] {
    // 1. Separate into categories
    let masters = events.filter { $0.isRecurring && !$0.isException }
    let exceptions = events.filter { $0.isException }
    let singles = events.filter { !$0.isRecurring }
    
    // 2. Group masters by series key
    let mastersBySeries = Dictionary(grouping: masters) { makeSeriesKey($0) }
    
    // 3. Process each series
    for (seriesKey, masters) in mastersBySeries {
        let virtualMaster = createVirtualMaster(from: masters)
        let occurrences = expandOccurrences(virtualMaster)
        result.append(contentsOf: occurrences)
    }
    
    return result
}
```

### 3. Output

- Single events: passed through as-is
- Orphan exceptions: passed through as-is (standalone modified occurrences)
- Recurring series: expanded into individual occurrences

---

## Series Grouping Algorithm

### Step 1: Create Series Key

```swift
private func makeSeriesKey(for master: EASCalendarEvent) -> String {
    guard let recurrence = master.recurrence else { 
        return master.id  // Single events are their own series
    }
    
    // Get base time from exceptions (not from master.startTime!)
    let baseTime: String
    if let exceptions = master.exceptions, !exceptions.isEmpty {
        // Count occurrences of each time
        let timeCounts = exceptions
            .filter { !$0.isDeleted }
            .map { "\(hour(from: $0.originalStartTime)):\(minute(from: $0.originalStartTime))" }
            .countByElement()
        
        baseTime = timeCounts.max(by: { $0.value < $1.value })?.key 
            ?? "\(hour(from: master.startTime)):\(minute(from: master.startTime))"
    } else {
        baseTime = "\(hour(from: master.startTime)):\(minute(from: master.startTime))"
    }
    
    // Recurrence signature
    let dayOfWeek = recurrence.dayOfWeek ?? 0
    let recSignature = "\(recurrence.type.rawValue)_\(recurrence.interval)_\(dayOfWeek)"
    
    return "\(master.subject)|\(baseTime)|\(recSignature)"
}
```

**Example keys:**
- `"PMO Daily|9:30|1_1_62"` (Weekly, Mon-Fri, 09:30)
- `"AI Daily|11:40|1_1_62"` (Weekly, Mon-Fri, 11:40)
- `"Standup|10:0|1_1_2"` (Weekly, Monday only, 10:00)

### Step 2: Merge Masters in Same Series

Multiple masters with the same key are merged:

```swift
let masters = [master1, master2, master3]  // All PMO Daily variants

// Collect all exceptions from all masters
let allExceptions = masters.flatMap { $0.exceptions ?? [] }

// Use best master as template (one with most exceptions)
let bestMaster = masters.max { ($0.exceptions?.count ?? 0) < ($1.exceptions?.count ?? 0) }
```

### Step 3: Determine Series Time Range

```swift
// Series start: earliest of (exception dates, master start dates)
let exceptionDates = allExceptions.map(\.originalStartTime)
let masterStartDates = masters.map(\.startTime)
let seriesStart = min(exceptionDates.min(), masterStartDates.min())

// Series end: latest exception OR sync range end
let seriesEnd = if let maxException = exceptionDates.max() {
    max(syncRangeEnd, maxException)
} else {
    syncRangeEnd
}
```

**Important:** Series can start before the earliest master (exceptions from older masters).

---

## Exception Handling

### Exception Map

For fast lookup during expansion, build a map keyed by date:

```swift
let exceptionMap = exceptions.reduce(into: [Date: EASException]()) { map, ex in
    let key = calendar.startOfDay(for: ex.originalStartTime)
    map[key] = ex
}
```

### Handling During Expansion

For each potential occurrence date:

```swift
if let exception = exceptionMap[date] {
    if exception.isDeleted {
        // Skip this occurrence
        continue
    } else {
        // Use exception's data
        occurrenceStart = exception.startTime ?? baseTimeOnDate
        occurrenceEnd = exception.endTime ?? occurrenceStart.addingTimeInterval(duration)
        subject = exception.subject ?? master.subject
        location = exception.location ?? master.location
    }
} else {
    // Regular occurrence - use base time
    occurrenceStart = calendar.date(
        bySettingHour: baseHour, minute: baseMinute, second: 0, of: date
    )!
    occurrenceEnd = occurrenceStart.addingTimeInterval(duration)
}
```

### Date Moves (Exception with Different Date)

When an exception moves an occurrence to a **different date** (not just time), special handling is required.

**Example:**
- Regular schedule: Thursdays at 10:00
- Exception: "2026-01-15 (Thu) moved to 2026-01-13 (Tue) at 14:00"

**The Problem:**
If we naively use `exception.startTime` during iteration, the event would appear on Thursday with Tuesday's time, which is wrong.

**The Solution:**

```swift
// 1. Identify moved exceptions (date changed, not just time)
let movedExceptions = exceptions.filter { ex in
    guard let startTime = ex.startTime, !ex.isDeleted else { return false }
    let originalDay = calendar.startOfDay(for: ex.originalStartTime)
    let newDay = calendar.startOfDay(for: startTime)
    return originalDay != newDay  // Date actually moved
}

// 2. During iteration, handle three cases:
//    a) Regular occurrence - create normally
//    b) Same-day exception (time change) - modify time, keep date
//    c) Moved exception - skip at original date, create at new date

// When we encounter the original date:
if let exception = exceptionMap[occurrenceDay] {
    if isMovedToDifferentDate(exception) {
        // Skip - this occurrence will be created at the target date
        continue
    } else {
        // Same-day modification - create occurrence here with modified time
        createOccurrence(on: occurrenceDay, time: exception.startTime)
    }
}

// When we encounter the target date (during normal iteration):
for movedEx in movedExceptions {
    if calendar.startOfDay(for: movedEx.startTime!) == occurrenceDay {
        // Create the moved occurrence here
        createOccurrence(on: occurrenceDay, time: movedEx.startTime)
    }
}
```

**Result:**
- Thursday 2026-01-15: No event (original occurrence moved)
- Tuesday 2026-01-13: Event at 14:00 (moved occurrence)
- All other Thursdays: Events at 10:00 (regular schedule)

---

## Virtual Master Creation

### Purpose

Create a "clean" master event that combines data from all masters in the series without legacy limitations.

### Process

```swift
// 1. Create recurrence WITHOUT until date
let virtualRecurrence = EASRecurrence(
    type: recurrence.type,
    interval: recurrence.interval,
    dayOfWeek: recurrence.dayOfWeek,
    dayOfMonth: recurrence.dayOfMonth,
    until: nil  // Don't limit by old master's until
)

// 2. Create virtual master
let virtualMaster = EASCalendarEvent(
    id: bestMaster.id,
    uid: bestMaster.uid,
    subject: bestMaster.subject,
    startTime: seriesStart,  // Earliest date in series
    endTime: seriesStart.addingTimeInterval(duration),
    recurrence: virtualRecurrence,
    exceptions: allExceptions,  // Merged from all masters
    // ... other fields from bestMaster
)
```

**Why remove `until`:**
- Old master (7:64) might have `until=20260112`
- New master (7:62) has `until=20260407`
- If we use old master's until, we miss events after 2026-01-12

---

## Occurrence Expansion

### Algorithm

```swift
func expandOccurrences(
    for master: EASCalendarEvent,
    from rangeStart: Date,
    to rangeEnd: Date,
    baseTime: Date,
    duration: TimeInterval
) -> [EASCalendarEvent] {
    
    var occurrences: [EASCalendarEvent] = []
    var currentDate = rangeStart
    var occurrenceIndex = 0
    
    while currentDate <= rangeEnd && occurrenceIndex < maxOccurrences {
        // Check if this date matches recurrence pattern
        let shouldInclude = checkRecurrencePattern(currentDate, master.recurrence)
        
        if shouldInclude {
            let occurrenceDay = calendar.startOfDay(for: currentDate)
            
            if let exception = exceptionMap[occurrenceDay] {
                // Handle exception (modified or deleted)
                handleException(exception, into: &occurrences)
            } else {
                // Create regular occurrence
                let occurrence = createRegularOccurrence(
                    for: master,
                    on: occurrenceDay,
                    baseTime: baseTime,
                    duration: duration,
                    index: occurrenceIndex
                )
                occurrences.append(occurrence)
                occurrenceIndex += 1
            }
        }
        
        // Advance to next potential occurrence
        currentDate = nextDate(currentDate, recurrence: master.recurrence)
    }
    
    return occurrences
}
```

### Weekly Recurrence Pattern Check

```swift
func checkWeeklyRecurrence(_ date: Date, dayOfWeekMask: Int) -> Bool {
    let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday, 7 = Saturday
    let bit = 1 << (weekday - 1)
    return (dayOfWeekMask & bit) != 0
}
```

**Example:** `DayOfWeek = 62` (binary `111110`) = Mon(2) + Tue(4) + Wed(8) + Thu(16) + Fri(32)

---

## Edge Cases

### 1. Orphan Exceptions

Exceptions without a master in the sync window:

```swift
// These are standalone modified occurrences
// Example: Meeting moved to different time, but we don't have the master
processedEvents.append(contentsOf: orphanExceptions)
```

### 2. Empty Exception Lists

If a master has no exceptions:
- Use master's start time as base time
- Expand from master.startTime to sync range end

### 3. All Deleted Exceptions

If all exceptions are deleted:
- Base time calculation falls back to master.startTime
- Expansion proceeds with deleted dates skipped

### 4. Date Moves (Different Day)

When an exception moves an occurrence to a different day:
- Original date: No event (occurrence moved away)
- Target date: Event at the new time
- The event ID tracks the original start time for reference

```swift
// Example: Thursday moved to Tuesday
originalStartTime: 2026-01-15 (Thu) 10:00
startTime: 2026-01-13 (Tue) 14:00

// Result:
// - 2026-01-15: Nothing (moved)
// - 2026-01-13: Event at 14:00
```

### 5. Timezone Handling

All times from Exchange are in UTC:
```swift
// Parser converts to Date (UTC)
let startTime = parseDate("20260113T093000Z")  // UTC

// Display layer converts to local timezone
let localTime = startTime.formatted(timezone: .current)
```

### 6. Very Long Series

Protection against infinite loops:
```swift
maxOccurrences = 200  // Hard limit per series
```

---

## Debugging

### Log Output

The system provides detailed logs for troubleshooting:

```
[EAS] Processing series 'PMO Daily' with 2 master(s), key: PMO Daily|12:30|1_1_62
[EAS]   Masters: 7:62@2026-01-27, 7:64@2025-12-25
[EAS]   Exceptions: 53 total
[EAS]   Base time: 12:30 (from 53 exceptions)
[EAS]   Series range: 2025-08-01 to 2026-04-30
[EAS] Expanded 'PMO Daily' into 127 occurrences (Series: PMO Daily|12:30|1_1_62)
```

### Key Metrics to Check

1. **Masters count**: Should match expected number of content versions
2. **Exceptions count**: Should be sum of all exceptions across masters
3. **Base time**: Should match the "standard" meeting time (e.g., 09:30)
4. **Series range**: Should cover from first occurrence to sync range end
5. **Expanded count**: Should be reasonable for the date range (e.g., ~20/week for daily meetings)

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Missing future events | Old master's until date | Remove until from virtual recurrence |
| Wrong time for regular occurrences | Using master.startTime | Use base time from exceptions |
| Duplicate events | Grouping by UID | Group by series key (subject+time+pattern) |
| Missing deleted occurrences | Not checking exception.isDeleted | Skip occurrences where isDeleted=true |
| Gap in series | Not merging all masters | Ensure all masters with same key are grouped |

---

## Example Scenarios

### Scenario 1: PMO Daily with Content Changes

**Timeline:**
1. 2025-07-28: Series created with description "Daily sync"
2. 2025-11-10: Time changed to 14:00 (exception created)
3. 2025-12-25: Description changed to "PMO Daily" → New master (7:64)
4. 2026-01-13: Description changed to "" → New master (7:62)
5. 2026-01-27: Description changed to "PMO Daily" → New master (7:62 modified)

**Sync Data:**
```
Master 7:64 (old): start=2025-07-28 09:30, until=2026-01-12, exceptions=49
Master 7:62 (new): start=2026-01-27 14:30, until=2026-04-07, exceptions=4
```

**Processing:**
```
Series Key: "PMO Daily|9:30|1_1_62"
Base Time: 9:30 (majority from 49 exceptions)
Series Range: 2025-07-28 to 2026-04-30
Merged Exceptions: 53 total
Result: 127 occurrences from 2025-07-28 to 2026-04-30
```

### Scenario 2: AI Daily (New Attendee)

**Timeline:**
1. 2026-01-12: Series created
2. 2026-01-13: User added to meeting
3. 2026-01-19: First occurrence visible to user

**Sync Data:**
```
Master 7:61: start=2026-01-19 08:40, until=2026-04-06, exceptions=1
```

**Processing:**
```
Series Key: "AI Daily|11:40|1_1_62"
Base Time: 11:40 (from 1 exception)
Series Range: 2026-01-19 to 2026-04-30
Result: 74 occurrences from 2026-01-19 onwards
```

### Scenario 3: Deleted Occurrence

**Input:**
```
Master: Weekly Standup (Monday)
Exceptions: [
    {originalStartTime: 2026-01-13 10:00, isDeleted: true}  // Cancelled
]
```

**Output:**
```
2026-01-06: Standup at 10:00 ✓
2026-01-13: (no event - cancelled) ✗
2026-01-20: Standup at 10:00 ✓
```

### Scenario 4: Moved to Different Date

**Input:**
```
Master: Weekly Team Sync (Thursday 10:00)
Exceptions: [
    {
        originalStartTime: 2026-01-15 10:00,  // Thursday
        startTime: 2026-01-13 14:00,          // Tuesday (moved!)
        isDeleted: false
    }
]
```

**Processing:**
```
Iteration over 2026-01-15 (Thursday):
- Found exception with originalStartTime = 2026-01-15
- Check: startTime day (2026-01-13) != originalStartTime day (2026-01-15)
- This is a DATE MOVE - skip creating occurrence on Thursday

Iteration over 2026-01-13 (Tuesday):
- Check movedExceptions list
- Found: exception with startTime = 2026-01-13
- Create occurrence on Tuesday at 14:00
```

**Output:**
```
2026-01-08 (Thu): Team Sync at 10:00 ✓
2026-01-13 (Tue): Team Sync at 14:00 ✓  (moved from Thu)
2026-01-15 (Thu): (no event - moved to Tue) ✗
2026-01-22 (Thu): Team Sync at 10:00 ✓
```

**Key Point:** The event appears on the NEW date (Tuesday), not the original date (Thursday).

---

## Future Improvements

1. **Incremental Sync**: Currently full sync re-expands all series. Could cache series state.
2. **Exception History**: Track how exceptions change over time for audit purposes.
3. **Performance**: Optimize expansion for series with 1000+ occurrences.
4. **Timezone Edge Cases**: Handle daylight saving time transitions more gracefully.
5. **Conflict Resolution**: Handle cases where exceptions overlap with single events.

---

## References

- [MS-ASCAL]: Exchange ActiveSync Calendar Protocol
- [MS-OXCICAL]: iCalendar to EAS mapping
- Apple Calendar.app behavior analysis (reverse engineered)

---

**End of Document**
