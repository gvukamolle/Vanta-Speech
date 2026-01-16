# iOS Live Activities and Dynamic Island: The complete developer reference

Apple's Live Activities framework enables persistent, real-time updates on the iPhone Lock Screen and Dynamic Island, fundamentally changing how apps deliver time-sensitive information. Introduced in iOS 16.1 with major enhancements through iOS 18, this system requires mastery of ActivityKit APIs, SwiftUI presentation layers, and APNs push infrastructure. **Maximum active duration is 8 hours**, with activities persisting on the Lock Screen up to 4 additional hours after ending, and all content state data limited to **4KB**.

## ActivityKit framework architecture and complete API reference

The ActivityKit framework centers on three core types: `Activity<Attributes>`, `ActivityAttributes` protocol, and `ActivityContent`. The Activity class manages the entire lifecycle while exposing critical properties including `id: String`, `activityState: ActivityState`, `content: ActivityContent`, `pushToken: Data?`, and the iOS 17.2+ addition `pushToStartToken: Data?`.

**ActivityAttributes protocol** defines both static data (unchanging throughout the activity) and dynamic ContentState:

```swift
protocol ActivityAttributes: Decodable, Encodable {
    associatedtype ContentState: Codable & Hashable
}

struct DeliveryAttributes: ActivityAttributes {
    let orderId: String           // Static - doesn't change
    let restaurant: String
    
    struct ContentState: Codable, Hashable {
        var status: String        // Dynamic - updates during lifecycle
        var estimatedDelivery: Date
    }
}
```

**ActivityState enum** tracks four distinct states: `.active` (running and visible), `.ended` (terminated but may still display), `.dismissed` (removed from UI), and `.stale` (content outdated past staleDate). The **ActivityUIDismissalPolicy** controls Lock Screen persistence after ending: `.default` (4 hours), `.immediate`, or `.after(_ date: Date)`.

### Lifecycle management methods

Starting a Live Activity requires foreground execution and user authorization:

```swift
static func request(
    attributes: Attributes,
    content: ActivityContent<Attributes.ContentState>,
    pushType: PushType? = nil  // .token for push updates
) throws -> Activity<Attributes>
```

Updates use async methods supporting optional alert configurations:

```swift
func update(_ content: ActivityContent<Attributes.ContentState>) async
func update(_:alertConfiguration:) async  // AlertConfiguration for sounds/alerts
```

Ending activities accepts optional final content and dismissal policy:

```swift
func end(_: ActivityContent?, dismissalPolicy: ActivityUIDismissalPolicy) async
```

**Async sequences** enable reactive observation: `activityStateUpdates`, `contentUpdates`, `pushTokenUpdates`, and the static `Activity<T>.pushToStartTokenUpdates` (iOS 17.2+) for remote activity starting.

### Authorization and Info.plist configuration

The **ActivityAuthorizationInfo** class provides two critical properties: `areActivitiesEnabled` (user permission status) and `frequentPushesEnabled` (high-frequency update permission). Required Info.plist keys:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>  <!-- Optional -->
<true/>
```

### Update frequency budget system

Apple enforces a **dynamic per-device, per-activity budget** for high-priority (priority 10) push updates—exact numbers remain undocumented and vary based on device conditions. Priority 5 updates have **no limit** and don't count toward the budget. When budget is exhausted, iOS may prompt users to allow additional updates if `NSSupportsLiveActivitiesFrequentUpdates` is enabled. **iOS 18 changed refresh rates** from approximately 1 second in iOS 17 to every 5-15 seconds.

### Error handling patterns

Common failure scenarios include device/platform unsupported, user permission denied, maximum 5 activities exceeded, ContentState encoding failures, and budget exhaustion. Always check `ActivityAuthorizationInfo().areActivitiesEnabled` and `ProcessInfo.processInfo.isiOSAppOnMac` before requesting activities.

## Dynamic Island presentation modes and size specifications

Dynamic Island supports three presentation modes with specific size constraints measured on iPhone 14 Pro/Pro Max:

| Presentation | iPhone 14 Pro | iPhone 14 Pro Max | Trigger |
|-------------|---------------|-------------------|---------|
| **Compact Leading** | 52×37pt | 62×37pt | Single activity |
| **Compact Trailing** | 52×37pt | 62×37pt | Single activity |
| **Minimal (detached)** | 37pt circle | 37pt circle | Multiple activities |
| **Expanded** | 371×160pt max | 371×160pt max | Long press |

The **compact presentation** renders leading and trailing views as a cohesive unit around the TrueDepth camera. **Minimal presentation** activates when multiple activities exist—one attaches to the island, one detaches as a circular bubble (max **45×36.67 points** for images).

### DynamicIslandExpandedRegion layout system

The expanded view uses four regions rendered in specific order: system renders `.center` first (below camera), then `.leading` and `.trailing` (equal width by default), finally `.bottom` for overflow. Priority values control space allocation:

```swift
DynamicIslandExpandedRegion(.leading, priority: 1) {
    // Higher priority = more space
}
```

Content overflow uses `.dynamicIsland(verticalPlacement: .belowIfTooWide)` to merge below when exceeding available width. The **maximum expanded height is 160 points**—content exceeding this is truncated by the system.

### Animation capabilities and limitations

**iOS 17+** introduced automatic text animations with blur-effect transitions, image/SF Symbol fade effects, and view addition/removal animations. Custom transitions support `.opacity`, `.move(edge:)`, `.slide`, `.push(from:)`, and `.contentTransition(.numericText())` for numeric displays. However, **iOS 16 ignores `withAnimation`** and only supports system-defined animations. Always-On Display disables animations automatically to preserve battery.

### System gesture handling

The system manages all interactions: **tap** opens the associated app, **long press (touch and hold)** expands to detailed view, **swipe left/right** switches between activities or dismisses expanded state. Expanded views auto-collapse after several seconds. Users cannot customize these gestures.

## Lock Screen, Always-On Display, and StandBy mode

Lock Screen Live Activities share **14-point margins** with notifications and enforce a **maximum height of 160 points**. The `staleDate` property triggers `.stale` state when passed, allowing apps to display stale UI or refresh content.

### Always-On Display handling

The `@Environment(\.isLuminanceReduced)` property detects Always-On state. **Critical implementation note**: this environment value fails when defined inline in ActivityConfiguration—it must use a separate View struct:

```swift
struct LiveActivityView: View {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    
    var body: some View {
        if isLuminanceReduced {
            // Darker tints, disable custom animations
            // Semantic colors auto-adjust
        }
    }
}
```

### StandBy mode (iOS 17+)

Lock Screen layouts **scale 200%** to fill the StandBy screen, with background colors automatically extending. Activities appear as bubble icons at the top—tapping expands full-screen. Night Mode applies red tinting in low-light conditions. Design with larger, simpler elements that work at 2× scale.

## iOS 17+ interactivity with App Intents

Live Activities now support **Button and Toggle** controls using the App Intents framework:

```swift
Button(intent: PlayPauseIntent()) {
    Label("Play/Pause", systemImage: "playpause")
}
```

**Critical architecture**: intents must conform to `LiveActivityIntent` protocol. When users interact, `perform()` executes in the **app's process**, not the widget extension. Since `Activity.activities` is always empty in extensions, a workaround involves separate protocol conformances for app and extension targets.

### Deep linking: widgetURL versus Link

**widgetURL** sets a single URL for Lock Screen, compact, and minimal presentations—applied to the DynamicIsland configuration. **Link** works only in expanded presentation, enables multiple tap targets, and overrides widgetURL within its region. Without either, the system passes `NSUserActivity` with `activityType` = `NSUserActivityTypeLiveActivity`.

## Push notification architecture for Live Activities

APNs payloads require specific structure with **mandatory fields**: `timestamp` (UNIX seconds, must increment), `event` ("update" or "end"), and `content-state` (matching ContentState type exactly with default JSON encoding).

### Complete payload example

```json
{
  "aps": {
    "timestamp": 1705560370,
    "event": "update",
    "content-state": { "score": 2, "status": "In Progress" },
    "stale-date": 1705567570,
    "relevance-score": 75,
    "alert": {
      "title": "Score Update",
      "body": "Home team scored!",
      "sound": "goal.aiff"
    }
  }
}
```

**Required APNs headers**: `apns-push-type: liveactivity` and `apns-topic: {bundleId}.push-type.liveactivity`. Priority header `apns-priority` defaults to 10 if omitted.

### Push-to-start (iOS 17.2+)

Remote activity starting uses `pushToStartToken` obtained via `Activity<T>.pushToStartTokenUpdates`. The payload requires additional fields:

```json
{
  "aps": {
    "event": "start",
    "attributes-type": "MyActivityAttributes",
    "attributes": { "orderId": "123" },
    "content-state": { "status": "Processing" },
    "timestamp": 1705547770
  }
}
```

**Known limitation**: tokens often generate only on fresh install + device reboot in iOS 17, improving in iOS 18. **Token-based authentication (p8) is required**—certificate-based (p12) does not work.

### iOS 18 broadcast push notifications

Send updates to thousands of activities with a single request using "channels"—eliminates storing individual push tokens. Ideal for sports scores, flight updates, and high-volume scenarios.

## Shared data, images, and styling constraints

### App Groups pattern

Enable App Groups capability in both app and widget extension with identical identifiers:

```swift
let defaults = UserDefaults(suiteName: "group.com.company.app")
defaults?.set(value, forKey: key)
defaults?.synchronize()  // Required for reliability
```

File sharing uses `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.

### Image handling constraints

The **4KB content limit** includes images—oversized images cause silent failures. Minimal presentation images cannot exceed **45×36.67 points**. Use PNG format (JPG may fail), pre-resize before saving, and prefer SF Symbols. The total archive size limit is approximately **2.5MB**.

### Custom font limitations

Custom fonts require adding files to widget extension's "Copy Bundle Resources" and `UIAppFonts` in Info.plist. Large fonts trigger "archiveTooLarge" errors. Fonts may work in simulator but fail on devices due to permission issues. **Workaround**: use `.process` scope instead of `.user` for `CTFontManagerRegisterFontsForURL`.

## System integration and edge cases

**Privacy indicators** (green/orange dots for camera/microphone) appear alongside Dynamic Island, not inside it. Live Activities respect Focus mode settings—apps can be silenced per-Focus configuration. Do Not Disturb may suppress alerts while still displaying activities.

### Developer-discovered quirks

The most common failure is activities not appearing due to **widget bundle conflicts**—if other widgets exist alongside ActivityWidget, create a separate Widget Extension target. Other issues include:

- Minimum deployment target mismatches between simulator and device
- Budget exhaustion requiring up to 24 hours for replenishment (device reset doesn't help)
- `#available` checks causing unexpected failures—return EmptyWidgetConfiguration instead
- Core Data initialization in TimelineProvider constructor causing silent failures
- TestFlight using production APNs environment, not sandbox

## Apple's official guidance and resources

WWDC sessions provide authoritative guidance: "Meet ActivityKit" (10184) and "Update Live Activities with push notifications" (10185) from WWDC23, "Bring your Live Activity to Apple Watch" (10068) and "Broadcast updates to your Live Activities" (10069) from WWDC24. The **Emoji Rangers sample project** demonstrates all key patterns including ActivityAttributes definition, Dynamic Island presentations, push token handling, and iOS 17 App Intents integration.

Human Interface Guidelines mandate supporting all four presentations (Lock Screen, compact, minimal, expanded), displaying only essential glanceable information, avoiding ads/promotions, and ending immediately when tasks complete. Activities exceeding 8 hours or lacking discrete start/end points violate guidelines.

## Key specifications summary

| Specification | Value |
|--------------|-------|
| Minimum iOS version | 16.1 (16.2+ recommended) |
| Push-to-start | iOS 17.2+ |
| Maximum active duration | 8 hours |
| Lock Screen persistence after end | Up to 4 hours |
| Maximum height (Lock Screen/Expanded) | 160 points |
| ContentState size limit | 4KB |
| Archive/bundle size limit | ~2.5MB |
| Max concurrent activities per app | 5 |
| APNs topic format | `{bundleId}.push-type.liveactivity` |

## Conclusion

Live Activities represent Apple's most sophisticated real-time notification system, requiring coordinated mastery of ActivityKit lifecycle management, SwiftUI presentation constraints across four distinct modes, and APNs push infrastructure with strict payload formatting. The **4KB data limit** and **8-hour maximum duration** are non-negotiable architectural constraints. iOS 17's App Intents interactivity and iOS 18's broadcast push capabilities significantly expand possibilities, while push-to-start tokens enable truly server-driven experiences. Success depends on understanding the budget system's preference for priority 5 updates, Always-On Display adaptations via `isLuminanceReduced`, and the numerous edge cases around widget bundle configuration and font/image sizing that cause silent failures in production.