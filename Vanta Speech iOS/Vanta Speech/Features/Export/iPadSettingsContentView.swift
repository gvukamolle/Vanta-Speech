import SwiftUI

/// iPad-оптимизированный view для секции Настройки
/// Список настроек слева, детали справа
struct iPadSettingsContentView: View {
    @State private var selectedSetting: SettingItem? = .account

    // Settings states
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("defaultRecordingMode") private var defaultRecordingMode = "standard"

    @StateObject private var presetSettings = PresetSettings.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var calendarManager = EASCalendarManager.shared
    @StateObject private var confluenceManager = ConfluenceManager.shared

    enum SettingItem: String, CaseIterable, Identifiable {
        case account = "Аккаунт"
        case presets = "Типы встреч"
        case theme = "Оформление"
        case transcription = "Расшифровка"
        case integrations = "Интеграции"
        case about = "О приложении"
        case danger = "Данные"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .account: return "person.circle"
            case .presets: return "list.bullet"
            case .theme: return "paintbrush"
            case .transcription: return "text.bubble"
            case .integrations: return "link"
            case .about: return "info.circle"
            case .danger: return "trash"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // Левая колонка: Список настроек (50%)
                    settingsList
                        .frame(width: geometry.size.width * 0.5)

                    Divider()

                    // Правая колонка: Детали настройки (50%)
                    settingDetail
                        .frame(width: geometry.size.width * 0.5)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .refreshable {
                if calendarManager.isConnected {
                    await calendarManager.forceFullSync()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Settings List

    private var settingsList: some View {
        VStack(spacing: 8) {
            ForEach(SettingItem.allCases) { item in
                Button {
                    selectedSetting = item
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .foregroundStyle(item == .danger ? .red : .secondary)
                            .frame(width: 20)

                        Text(item.rawValue)
                            .foregroundStyle(item == .danger ? .red : .primary)

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedSetting == item
                                ? Color.pinkVibrant.opacity(0.12)
                                : Color(.secondarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    // MARK: - Setting Detail

    @ViewBuilder
    private var settingDetail: some View {
        VStack(spacing: 0) {
            switch selectedSetting {
            case .account:
                accountSection
            case .presets:
                presetsSection
            case .theme:
                themeSection
            case .transcription:
                transcriptionSection
            case .integrations:
                integrationsSection
            case .about:
                aboutSection
            case .danger:
                dangerSection
            case .none:
                ContentUnavailableView(
                    "Выберите раздел",
                    systemImage: "gear",
                    description: Text("Выберите раздел настроек слева")
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Аккаунт")

            if let session = authManager.currentSession {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.displayName ?? session.username)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(session.username)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)
            }

            Button("Выйти из аккаунта", role: .destructive) {
                authManager.logout()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Типы встреч")

            Text("Настройте порядок и доступность типов встреч в меню записи")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                Text("Тип записи по умолчанию")
                    .font(.headline)

                Picker("Тип записи", selection: $defaultRecordingMode) {
                    Text("Обычная").tag("standard")
                    Text("Real-time").tag("realtime")
                    Text("Импорт").tag("import")
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)

            VStack(spacing: 12) {
                ForEach(presetSettings.orderedPresets, id: \.rawValue) { preset in
                    HStack(spacing: 12) {
                        Image(systemName: preset.icon)
                            .foregroundStyle(presetSettings.isEnabled(preset) ? Color.pinkVibrant : .secondary)
                            .frame(width: 24)

                        Text(preset.displayName)
                            .foregroundStyle(presetSettings.isEnabled(preset) ? .primary : .secondary)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { presetSettings.isEnabled(preset) },
                            set: { _ in presetSettings.togglePreset(preset) }
                        ))
                        .disabled(!presetSettings.isEnabled(preset) && presetSettings.enabledPresets.count <= 1)
                    }
                    .padding()
                    .vantaGlassCard(cornerRadius: 12, shadowRadius: 0, tintOpacity: 0.15)
                }
            }

            Button("Сбросить настройки") {
                presetSettings.resetToDefaults()
            }
            .buttonStyle(.bordered)

            Divider()
                .padding(.vertical, 8)

            // Настройки Real-time
            VStack(alignment: .leading, spacing: 16) {
                Text("Настройки Real-time")
                    .font(.headline)

                Text("Параметры для режима Real-time транскрипции")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    RealtimeModeSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text("Настроить")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .vantaGlassCard(cornerRadius: 12, shadowRadius: 0, tintOpacity: 0.15)
            }
            .padding()
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)

            Spacer()
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Оформление")

            VStack(alignment: .leading, spacing: 16) {
                Text("Тема приложения")
                    .font(.headline)

                Picker("Тема", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)

            Spacer()
        }
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Расшифровка")

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Авто-расшифровка после записи", isOn: $autoTranscribe)

                Divider()

                HStack {
                    Text("Сервер")
                    Spacer()
                    Text("Внутренний")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)

            Spacer()
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Интеграции")

            Text("Подключите внешние сервисы для экспорта транскрипций и саммари")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                // Exchange Calendar (EAS)
                NavigationLink {
                    EASCalendarSettingsView()
                } label: {
                    exchangeIntegrationRow
                }

                // Confluence
                NavigationLink {
                    ConfluenceSettingsView()
                } label: {
                    confluenceIntegrationRow
                }
            }

            Spacer()
        }
    }

    private var exchangeIntegrationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text("Календарь")

            Spacer()

            if calendarManager.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .vantaGlassCard(cornerRadius: 12, shadowRadius: 0, tintOpacity: 0.15)
    }

    private var confluenceIntegrationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text("Confluence")

            Spacer()

            if confluenceManager.isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .vantaGlassCard(cornerRadius: 12, shadowRadius: 0, tintOpacity: 0.15)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("О приложении")

            VStack(alignment: .leading, spacing: 16) {
                VersionTapView()

                Divider()

                HStack {
                    Text("Разработчик")
                    Spacer()
                    Text("Vanta")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)

            Spacer()
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Данные")

            Text("Внимание: эти действия необратимы")
                .font(.subheadline)
                .foregroundStyle(.red)

            Button("Удалить все записи", role: .destructive) {
                // TODO: Implement clear all
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.largeTitle)
            .fontWeight(.bold)
    }
}

#Preview {
    iPadSettingsContentView()
}
