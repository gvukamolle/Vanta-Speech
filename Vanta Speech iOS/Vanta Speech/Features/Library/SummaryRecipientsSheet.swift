import SwiftUI
import SwiftData

/// Sheet for selecting which meeting attendees should receive the summary email
struct SummaryRecipientsSheet: View {
    @Bindable var recording: Recording
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Live event for fresh attendee data
    @StateObject private var calendarManager = EASCalendarManager.shared
    
    // State
    @State private var selectedEmails: Set<String> = []
    @State private var additionalEmails: [String] = []
    @State private var showAddEmailSheet = false
    @State private var newEmail = ""
    
    // Get attendees from live event or recording
    private var attendees: [EASAttendee] {
        // Try to get from live event first
        if let event = linkedEvent {
            // Combine human attendees and organizer
            var allAttendees = event.humanAttendees
            if let organizer = event.organizer,
               !allAttendees.contains(where: { $0.email.lowercased() == organizer.email.lowercased() }) {
                allAttendees.insert(organizer, at: 0)
            }
            return allAttendees
        }
        
        // Fallback to stored emails
        return recording.linkedMeetingAttendeeEmails.map { email in
            EASAttendee(email: email, name: "")
        }
    }
    
    private var linkedEvent: EASCalendarEvent? {
        guard let linkedId = recording.linkedMeetingId else { return nil }
        return calendarManager.cachedEvents.first { $0.id == linkedId }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Info card
                    infoCard
                    
                    // Attendees list
                    attendeesSection
                    
                    // Add button
                    addButton
                }
                .padding()
            }
            .navigationTitle("Получатели саммари")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
        .onAppear {
            initializeSelection()
        }
        .onDisappear {
            saveSelection()
        }
        .sheet(isPresented: $showAddEmailSheet) {
            addEmailSheet
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Info Card
    
    private var infoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.title3)
                .foregroundStyle(Color.pinkVibrant)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Выберите получателей")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text("Саммари будет отправлено только выбранным участникам")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.10)
    }
    
    // MARK: - Attendees Section
    
    private var attendeesSection: some View {
        VStack(spacing: 8) {
            // Section header
            HStack {
                Text("УЧАСТНИКИ ВСТРЕЧИ")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            // Attendee cards
            VStack(spacing: 8) {
                ForEach(attendees) { attendee in
                    AttendeeRow(
                        attendee: attendee,
                        isSelected: selectedEmails.contains(attendee.email.lowercased())
                    ) {
                        toggleSelection(for: attendee.email)
                    }
                }
            }
            
            // Additional emails section
            if !additionalEmails.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("ДОБАВЛЕННЫЕ АДРЕСА")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    ForEach(additionalEmails, id: \.self) { email in
                        AdditionalEmailRow(
                            email: email,
                            isSelected: selectedEmails.contains(email.lowercased())
                        ) {
                            toggleSelection(for: email)
                        } onDelete: {
                            deleteAdditionalEmail(email)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button {
            showAddEmailSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.body)
                Text("Добавить участника")
                    .fontWeight(.medium)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Add Email Sheet
    
    private var addEmailSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email адрес", text: $newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                Section {
                    Button {
                        addNewEmail()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Добавить")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isValidEmail(newEmail))
                }
            }
            .navigationTitle("Новый получатель")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
    }
    
    // MARK: - Actions
    
    private func initializeSelection() {
        // If we have previously selected recipients, use them
        let savedRecipients = recording.selectedSummaryRecipients
        if !savedRecipients.isEmpty {
            selectedEmails = Set(savedRecipients.map { $0.lowercased() })
            // Separate additional emails (not in attendees)
            let attendeeEmails = Set(attendees.map { $0.email.lowercased() })
            additionalEmails = savedRecipients.filter { !attendeeEmails.contains($0.lowercased()) }
        } else {
            // Default: select all attendees
            selectedEmails = Set(attendees.map { $0.email.lowercased() })
        }
    }
    
    private func toggleSelection(for email: String) {
        let lowercased = email.lowercased()
        if selectedEmails.contains(lowercased) {
            selectedEmails.remove(lowercased)
        } else {
            selectedEmails.insert(lowercased)
        }
    }
    
    private func deleteAdditionalEmail(_ email: String) {
        additionalEmails.removeAll { $0.lowercased() == email.lowercased() }
        selectedEmails.remove(email.lowercased())
    }
    
    private func addNewEmail() {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(trimmed), !trimmed.isEmpty else { return }
        
        // Check if already exists
        if !additionalEmails.contains(where: { $0.lowercased() == trimmed }) &&
           !attendees.contains(where: { $0.email.lowercased() == trimmed }) {
            additionalEmails.append(trimmed)
            selectedEmails.insert(trimmed)
        }
        
        newEmail = ""
        showAddEmailSheet = false
    }
    
    private func saveSelection() {
        // Combine attendee emails and additional emails that are selected
        var allSelected: [String] = []
        
        // Add selected attendees
        for attendee in attendees {
            if selectedEmails.contains(attendee.email.lowercased()) {
                allSelected.append(attendee.email)
            }
        }
        
        // Add selected additional emails
        for email in additionalEmails {
            if selectedEmails.contains(email.lowercased()) {
                allSelected.append(email)
            }
        }
        
        // Save to recording
        recording.selectedSummaryRecipients = allSelected
        
        try? modelContext.save()
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // Basic email validation
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: trimmed)
    }
}

// MARK: - Attendee Row

private struct AttendeeRow: View {
    let attendee: EASAttendee
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                // Avatar/icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.pinkVibrant.opacity(0.15) : Color.gray.opacity(0.1))
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.pinkVibrant)
                    } else {
                        Image(systemName: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 36)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    if !attendee.name.isEmpty {
                        Text(attendee.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    Text(attendee.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.pinkVibrant : .secondary)
            }
            .padding(12)
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: isSelected ? 0.15 : 0.08)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Additional Email Row

private struct AdditionalEmailRow: View {
    let email: String
    let isSelected: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar/icon
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.blueVibrant)
                } else {
                    Image(systemName: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            
            // Email
            Text(email)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blueVibrant : .secondary)
            }
            .buttonStyle(.plain)
            
            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: isSelected ? 0.12 : 0.08)
    }
}

// MARK: - Preview

#Preview {
    let recording = Recording(
        title: "Тестовая запись",
        audioFileURL: "/test/path.ogg"
    )
    recording.linkedMeetingId = "test-meeting-id"
    recording.linkedMeetingSubject = "Еженедельный созвон"
    recording.linkedMeetingAttendeeEmails = [
        "ivan.ivanov@example.com",
        "maria.petrova@example.com",
        "alexey.sidorov@example.com"
    ]
    
    return SummaryRecipientsSheet(recording: recording)
}
