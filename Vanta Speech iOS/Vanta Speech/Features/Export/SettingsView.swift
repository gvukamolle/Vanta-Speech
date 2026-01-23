import SwiftUI

struct SettingsView: View {
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("defaultRecordingMode") private var defaultRecordingMode = "standard"

    // Preset settings
    @StateObject private var presetSettings = PresetSettings.shared

    // Confluence manager
    @StateObject private var confluenceManager = ConfluenceManager.shared

    // Auth manager
    @StateObject private var authManager = AuthenticationManager.shared

    // Calendar manager
    @StateObject private var calendarManager = EASCalendarManager.shared

    // Debug manager
    @StateObject private var debugManager = DebugManager.shared

    var body: some View {
        NavigationStack {
            Form {
                // Account section
                Section("Аккаунт") {
                    if let session = authManager.currentSession {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayName ?? session.username)
                                    .font(.body)
                                if let email = session.email, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button("Выйти", role: .destructive) {
                        authManager.logout()
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Тип записи по умолчанию", systemImage: "waveform")
                            .foregroundStyle(.secondary)

                        Picker("Тип записи", selection: $defaultRecordingMode) {
                            Text("Обычная").tag("standard")
                            Text("Real-time").tag("realtime")
                            Text("Импорт").tag("import")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    NavigationLink {
                        PresetSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text("Типы встреч")
                            Spacer()
                            Text("\(presetSettings.enabledPresets.count) из \(RecordingPreset.allCases.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        RealtimeModeSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text("Настройки Real-time")
                        }
                    }
                } header: {
                    Text("Запись")
                } footer: {
                    Text("Выберите режим записи по умолчанию для главного экрана. Настройки для режима Real-time доступны в соответствующем разделе.")
                }

                Section("Оформление") {
                    Picker("Тема", selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                }

                Section("Расшифровка") {
                    Toggle("Авто-расшифровка после записи", isOn: $autoTranscribe)

                    HStack {
                        Text("Сервер")
                        Spacer()
                        Text("Внутренний")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Интеграции") {
                    // Exchange ActiveSync (On-Premises)
                    NavigationLink {
                        EASCalendarSettingsView()
                    } label: {
                        IntegrationRow(
                            name: "Календарь",
                            icon: "building.2",
                            isConnected: calendarManager.isConnected
                        )
                    }

                    // Confluence
                    NavigationLink {
                        ConfluenceSettingsView()
                    } label: {
                        IntegrationRow(
                            name: "Confluence",
                            icon: "doc.text",
                            isConnected: confluenceManager.isAvailable
                        )
                    }
                }

                Section("О приложении") {
                    VersionTapView()
                }

                // Debug section - visible only when debug mode is enabled
                if debugManager.isDebugModeEnabled {
                    Section {
                        Toggle("Фейковые транскрипции", isOn: $debugManager.isFakeTranscriptionEnabled)

                        Text("При включении вместо реальных запросов к серверу будут использоваться тестовые данные")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Выключить Debug Mode", role: .destructive) {
                            debugManager.disableDebugMode()
                        }
                    } header: {
                        Label("Debug Mode", systemImage: "ladybug")
                    } footer: {
                        Text("Режим отладки активен. Используйте фейковые транскрипции для тестирования без доступа к серверу.")
                    }
                }

                Section {
                    Button("Удалить все записи", role: .destructive) {
                        // TODO: Implement clear all
                    }
                }
            }
            .refreshable {
                if calendarManager.isConnected {
                    await calendarManager.forceFullSync()
                }
            }
            .navigationTitle("Настройки")
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Integration Row

private struct IntegrationRow: View {
    let name: String
    let icon: String
    let isConnected: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(name)

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Integration Settings View

struct IntegrationSettingsView: View {
    let service: String
    @Binding var isConnected: Bool
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section {
                if isConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Подключено")
                    }

                    Button("Отключить", role: .destructive) {
                        isConnected = false
                        apiKey = ""
                    }
                } else {
                    SecureField("API ключ", text: $apiKey)

                    Button("Подключить") {
                        if !apiKey.isEmpty {
                            isConnected = true
                        }
                    }
                    .disabled(apiKey.isEmpty)
                }
            } header: {
                Text("Интеграция \(service)")
            } footer: {
                Text("Подключите аккаунт \(service) для экспорта транскрипций и саммари.")
            }
        }
        .navigationTitle(service)
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Preset Settings View

struct PresetSettingsView: View {
    @StateObject private var settings = PresetSettings.shared
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                ForEach(settings.orderedPresets, id: \.rawValue) { preset in
                    PresetRow(
                        preset: preset,
                        isEnabled: settings.isEnabled(preset),
                        canDisable: settings.enabledPresets.count > 1,
                        onToggle: {
                            settings.togglePreset(preset)
                        }
                    )
                }
                .onMove { source, destination in
                    settings.movePreset(from: source, to: destination)
                }
            } header: {
                Text("Типы встреч")
            } footer: {
                Text("Перетащите для изменения порядка. Минимум один тип должен быть включён.")
            }

            Section {
                Button("Сбросить настройки") {
                    settings.resetToDefaults()
                }
            }
        }
        .navigationTitle("Типы встреч")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Готово" : "Изменить") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
            }
        }
    }
}

private struct PresetRow: View {
    let preset: RecordingPreset
    let isEnabled: Bool
    let canDisable: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.icon)
                .foregroundStyle(isEnabled ? Color.pinkVibrant : .secondary)
                .frame(width: 24)

            Text(preset.displayName)
                .foregroundStyle(isEnabled ? .primary : .secondary)

            Spacer()

            Button {
                onToggle()
            } label: {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!canDisable && isEnabled)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    SettingsView()
}
