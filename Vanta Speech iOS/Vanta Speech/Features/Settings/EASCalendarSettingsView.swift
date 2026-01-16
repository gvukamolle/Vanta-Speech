import SwiftUI

/// Settings view for Exchange ActiveSync calendar integration
struct EASCalendarSettingsView: View {

    @StateObject private var manager = EASCalendarManager.shared

    // Login form state
    @State private var serverURL = ""
    @State private var username = ""
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
                actionsSection
            } else {
                loginSection
            }
        }
        .navigationTitle("Exchange Calendar")
        .scrollDismissesKeyboard(.interactively)
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Connected State

    private var connectedSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Подключено")
            }

            if let lastSync = manager.lastSyncDate {
                HStack {
                    Text("Последняя синхронизация")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
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

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    await manager.syncEvents()
                }
            } label: {
                HStack {
                    if manager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Синхронизировать")
                }
            }
            .disabled(manager.isSyncing)

            Button("Отключить", role: .destructive) {
                manager.disconnect()
            }
        }
    }

    // MARK: - Login Form

    private var loginSection: some View {
        Section {
            TextField("Адрес сервера", text: $serverURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            TextField("Имя пользователя", text: $username)
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
                    Text("Подключить")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!canConnect || isConnecting)

        } header: {
            Text("Подключение к Exchange")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Введите адрес вашего Exchange сервера и учётные данные.")

                Text("Формат имени пользователя: DOMAIN\\username или user@domain.com")
                    .font(.caption)

                Text("Пример сервера: https://mail.company.com")
                    .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private var canConnect: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    private func connect() async {
        isConnecting = true

        // Normalize server URL
        var normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
        }

        let success = await manager.connect(
            serverURL: normalizedURL,
            username: username,
            password: password
        )

        isConnecting = false

        if !success {
            errorMessage = manager.lastError?.errorDescription ?? "Ошибка подключения"
            showError = true
        } else {
            // Clear form
            serverURL = ""
            username = ""
            password = ""

            // Start initial sync
            await manager.syncEvents()
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
