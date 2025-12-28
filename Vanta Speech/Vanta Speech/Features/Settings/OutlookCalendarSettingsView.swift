import SwiftUI

/// View настроек интеграции с Outlook Calendar
struct OutlookCalendarSettingsView: View {
    @StateObject private var manager = OutlookCalendarManager.shared
    @State private var showDisconnectConfirmation = false
    @State private var isLoading = false

    var body: some View {
        Form {
            // Статус подключения
            connectionSection

            if manager.isConnected {
                // Информация о синхронизации
                syncSection

                // Действия
                actionsSection
            }
        }
        .navigationTitle("Outlook Calendar")
        .alert("Отключить Outlook?", isPresented: $showDisconnectConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Отключить", role: .destructive) {
                Task { await disconnect() }
            }
        } message: {
            Text("Связь с календарём Outlook будет удалена. Существующие записи сохранятся.")
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            if manager.isConnected {
                // Подключено
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Подключено")
                            .font(.headline)

                        if let email = manager.userEmail {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

            } else {
                // Не подключено
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(.orange)
                            .font(.title2)

                        Text("Не подключено")
                            .font(.headline)
                    }

                    Text("Подключите Outlook для автоматической привязки записей к встречам календаря.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "link")
                            }
                            Text("Подключить Outlook")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isLoading)
                }
                .padding(.vertical, 8)
            }

            // Ошибка
            if let error = manager.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Подключение")
        } footer: {
            if !manager.isConnected {
                Text("Vanta Speech получит доступ к чтению и редактированию событий вашего календаря Outlook.")
            }
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            // Последняя синхронизация
            HStack {
                Label("Последняя синхронизация", systemImage: "arrow.triangle.2.circlepath")

                Spacer()

                if manager.isSyncing {
                    ProgressView()
                } else if let date = manager.lastSyncDate {
                    Text(formatRelativeDate(date))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Никогда")
                        .foregroundStyle(.secondary)
                }
            }

            // Количество событий
            HStack {
                Label("Событий в кэше", systemImage: "calendar")

                Spacer()

                Text("\(manager.cachedEvents.count)")
                    .foregroundStyle(.secondary)
            }

            // Кнопка синхронизации
            Button {
                Task { await syncNow() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Синхронизировать")
                }
            }
            .disabled(manager.isSyncing)

        } header: {
            Text("Синхронизация")
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            // Сброс синхронизации
            Button {
                Task { await resetSync() }
            } label: {
                Label("Сбросить и синхронизировать", systemImage: "arrow.counterclockwise")
            }
            .disabled(manager.isSyncing)

            // Отключить
            Button(role: .destructive) {
                showDisconnectConfirmation = true
            } label: {
                Label("Отключить Outlook", systemImage: "link.badge.minus")
            }
        } header: {
            Text("Действия")
        }
    }

    // MARK: - Actions

    private func connect() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        await manager.connect(from: viewController)
    }

    private func disconnect() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            return
        }

        await manager.disconnect(from: viewController)
    }

    private func syncNow() async {
        await manager.performSync()
    }

    private func resetSync() async {
        await manager.resetAndSync()
    }

    // MARK: - Helpers

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OutlookCalendarSettingsView()
    }
}
