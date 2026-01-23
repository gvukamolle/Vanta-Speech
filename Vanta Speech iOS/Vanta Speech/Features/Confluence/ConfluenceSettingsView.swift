import SwiftUI

/// Настройки Confluence интеграции
struct ConfluenceSettingsView: View {

    @StateObject private var manager = ConfluenceManager.shared

    @State private var showLocationPicker = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            statusSection

            if manager.isAvailable {
                exportSettingsSection
            }
        }
        .navigationTitle("Confluence")
        .task {
            if manager.isAvailable && manager.spaces.isEmpty {
                await manager.loadSpaces()
            }
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showLocationPicker) {
            ConfluenceLocationPickerView { spaceKey, pageId, pageTitle in
                manager.saveDefaultExportLocation(
                    spaceKey: spaceKey,
                    pageId: pageId,
                    pageTitle: pageTitle
                )
            }
        }
        .onChange(of: manager.lastError) { _, error in
            if let error = error {
                errorMessage = error.errorDescription ?? "Неизвестная ошибка"
                showError = true
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            if manager.isAvailable {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Доступно")
                }

                if !manager.spaces.isEmpty {
                    HStack {
                        Text("Пространств")
                        Spacer()
                        Text("\(manager.spaces.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Требуется авторизация")
                }

                Text("Войдите в систему для доступа к Confluence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Статус")
        } footer: {
            if manager.isAvailable {
                Text("Используются учётные данные Active Directory")
            }
        }
    }

    // MARK: - Export Settings Section

    private var exportSettingsSection: some View {
        Section {
            Button {
                showLocationPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Папка для экспорта")
                        locationDescription
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Настройки экспорта")
        } footer: {
            Text("Выберите пространство и родительскую страницу, куда будут экспортироваться саммари.")
        }
    }

    private var locationDescription: some View {
        Group {
            if let spaceKey = manager.defaultSpaceKey {
                if let title = manager.defaultParentPageTitle {
                    Text("\(spaceKey) / \(title)")
                } else {
                    Text("\(spaceKey) (корень пространства)")
                }
            } else {
                Text("Не выбрано")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ConfluenceSettingsView()
    }
}
