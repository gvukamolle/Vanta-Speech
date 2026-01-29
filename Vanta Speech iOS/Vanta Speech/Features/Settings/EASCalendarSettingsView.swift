import SwiftUI

/// Settings view for Exchange ActiveSync calendar integration
struct EASCalendarSettingsView: View {

    @StateObject private var manager = EASCalendarManager.shared
    @StateObject private var summaryEmailManager = SummaryEmailManager.shared

    // Corporate EAS configuration (from Env)
    private var corporateServerURL: String { Env.exchangeServerURL }
    private var corporateDomain: String { Env.corporateEmailDomain }

    // Login form state (only AD username and password needed)
    @State private var adUsername = ""
    @State private var password = ""

    // UI state
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            if manager.isConnected {
                connectedSection
                eventsSection
                emailSettingsSection
                actionsSection
            } else {
                loginSection
            }
        }
        .navigationTitle("Календарь")
        .scrollDismissesKeyboard(.interactively)
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .tint(.primary)
    }

    // MARK: - Connected State

    private var connectedSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Подключено")
            }
        } header: {
            Text("Статус")
        }
    }

    private var eventsSection: some View {
        Section {
            if manager.cachedEvents.isEmpty {
                Text("Нет событий")
                    .foregroundStyle(.secondary)
            } else {
                // Show upcoming events first, then recent if no upcoming
                let eventsToShow = manager.upcomingEvents.isEmpty
                    ? Array(manager.recentEvents.prefix(5))
                    : Array(manager.upcomingEvents.prefix(5))

                ForEach(eventsToShow) { event in
                    EventRow(event: event)
                }

                let totalCount = manager.cachedEvents.count
                if totalCount > 5 {
                    Text("Всего событий: \(totalCount)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        } header: {
            Text(manager.upcomingEvents.isEmpty ? "Недавние события" : "Ближайшие события")
        } footer: {
            if !manager.cachedEvents.isEmpty {
                Text("Будущих событий: \(manager.upcomingEvents.count), прошедших: \(manager.cachedEvents.count - manager.upcomingEvents.count)")
                    .font(.caption)
            }
        }
    }

    private var emailSettingsSection: some View {
        Section {
            Toggle("Автоматическая отправка", isOn: $summaryEmailManager.autoSendSummaryEnabled)

            Toggle("Отправлять копию себе", isOn: $summaryEmailManager.includeSelfInSummaryEmail)
        } header: {
            Text("Саммари по email")
        } footer: {
            if summaryEmailManager.autoSendSummaryEnabled {
                Text("Саммари будет автоматически отправляться участникам встречи сразу после генерации. Вы также получите копию письма.")
            } else {
                Text("При ручной отправке саммари участникам встречи вы также получите копию письма")
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Отключить", role: .destructive) {
                manager.disconnect()
            }
        }
    }

    // MARK: - Login Form

    private var loginSection: some View {
        Section {
            TextField("Логин", text: $adUsername)
                .textContentType(.username)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            SecureField("Пароль", text: $password)
                .textContentType(.password)

            Button {
                Task {
                    await connect()
                }
            } label: {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Подключить календарь")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canConnect || isConnecting)

        } header: {
            Text("Корпоративный календарь")
        } footer: {
            Text("Используйте учётные данные Active Directory")
                .font(.caption)
        }
    }

    // MARK: - Actions

    private var canConnect: Bool {
        !adUsername.isEmpty && !password.isEmpty
    }

    private func connect() async {
        isConnecting = true

        // Build full username: adUsername@pos-credit.ru
        let fullUsername = adUsername.trimmingCharacters(in: .whitespacesAndNewlines) + corporateDomain

        let success = await manager.connect(
            serverURL: corporateServerURL,
            username: fullUsername,
            password: password
        )

        isConnecting = false

        if !success {
            errorMessage = manager.lastError?.errorDescription ?? "Ошибка подключения"
            showError = true
        } else {
            // Clear form
            adUsername = ""
            password = ""
        }
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: EASCalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.subject)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(formattedTime, systemImage: "clock")

                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Show attendees count and duration
            HStack(spacing: 8) {
                if !event.attendees.isEmpty {
                    Label("\(event.humanAttendees.count) участн.", systemImage: "person.2")
                }
                Label(event.formattedDuration, systemImage: "timer")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: event.startTime)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EASCalendarSettingsView()
    }
}
