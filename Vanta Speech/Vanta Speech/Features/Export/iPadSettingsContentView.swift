import SwiftUI

/// iPad-оптимизированный view для секции Настройки
/// Список настроек слева, детали справа
struct iPadSettingsContentView: View {
    @State private var selectedSetting: SettingItem? = .account

    // Settings states
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("confluence_connected") private var confluenceConnected = false
    @AppStorage("notion_connected") private var notionConnected = false
    @AppStorage("googledocs_connected") private var googleDocsConnected = false

    @StateObject private var presetSettings = PresetSettings.shared
    @StateObject private var authManager = AuthenticationManager.shared

    enum SettingItem: String, CaseIterable, Identifiable {
        case account = "Аккаунт"
        case presets = "Типы встреч"
        case theme = "Оформление"
        case transcription = "Транскрипция"
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
        HStack(spacing: 0) {
            // Левая колонка: Список настроек
            settingsList
                .frame(width: 280)

            Divider()

            // Правая колонка: Детали настройки
            settingDetail
        }
        .navigationTitle("Настройки")
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Settings List

    private var settingsList: some View {
        List(SettingItem.allCases, selection: $selectedSetting) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
                .foregroundStyle(item == .danger ? .red : .primary)
        }
        .listStyle(.sidebar)
    }

    // MARK: - Setting Detail

    @ViewBuilder
    private var settingDetail: some View {
        ScrollView {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            sectionHeader("Транскрипция")

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Авто-транскрипция после записи", isOn: $autoTranscribe)

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
                integrationRow(name: "Confluence", icon: "doc.text", isConnected: $confluenceConnected)
                integrationRow(name: "Notion", icon: "doc.richtext", isConnected: $notionConnected)
                integrationRow(name: "Google Docs", icon: "doc.text.fill", isConnected: $googleDocsConnected)
            }

            Spacer()
        }
    }

    private func integrationRow(name: String, icon: String, isConnected: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(name)

            Spacer()

            if isConnected.wrappedValue {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Отключить") {
                        isConnected.wrappedValue = false
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                Button("Подключить") {
                    isConnected.wrappedValue = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .vantaGlassCard(cornerRadius: 12, shadowRadius: 0, tintOpacity: 0.15)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("О приложении")

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Версия")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

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
