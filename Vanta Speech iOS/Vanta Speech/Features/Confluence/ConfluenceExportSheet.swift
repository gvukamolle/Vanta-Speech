import SwiftUI

/// Sheet для экспорта записи в Confluence
struct ConfluenceExportSheet: View {

    @Bindable var recording: Recording
    let onSuccess: (URL?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = ConfluenceManager.shared

    @State private var pageTitle: String = ""
    @State private var selectedSpaceKey: String?
    @State private var selectedParentPageId: String?
    @State private var selectedParentPageTitle: String?
    @State private var isExporting = false
    @State private var showLocationPicker = false
    @State private var showError = false
    @State private var errorMessage = ""

    /// Режим: обновить существующую или создать новую
    @State private var exportMode: ExportMode = .create

    enum ExportMode {
        case create
        case update
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                locationSection

                if recording.isExportedToConfluence {
                    exportModeSection
                }

                actionSection
            }
            .navigationTitle("Экспорт в Confluence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupInitialValues()
            }
            .sheet(isPresented: $showLocationPicker) {
                ConfluenceLocationPickerView { spaceKey, pageId, pageTitle in
                    selectedSpaceKey = spaceKey
                    selectedParentPageId = pageId
                    selectedParentPageTitle = pageTitle
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        Section("Название страницы") {
            TextField("Название", text: $pageTitle)
                .textInputAutocapitalization(.sentences)
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        Section {
            Button {
                showLocationPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Расположение")
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
            .disabled(exportMode == .update)
        } header: {
            Text("Куда экспортировать")
        } footer: {
            if exportMode == .update {
                Text("При обновлении расположение нельзя изменить")
            }
        }
    }

    private var locationDescription: some View {
        Group {
            if let spaceKey = selectedSpaceKey {
                if let title = selectedParentPageTitle {
                    Text("\(spaceKey) / \(title)")
                } else {
                    Text("\(spaceKey) (корень)")
                }
            } else {
                Text("Не выбрано")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Export Mode Section

    private var exportModeSection: some View {
        Section {
            Picker("Действие", selection: $exportMode) {
                Text("Обновить существующую").tag(ExportMode.update)
                Text("Создать новую").tag(ExportMode.create)
            }
            .pickerStyle(.segmented)

            if exportMode == .update, let url = recording.confluencePageURL {
                Link(destination: URL(string: url)!) {
                    HStack {
                        Image(systemName: "link")
                        Text("Открыть текущую страницу")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("Страница уже экспортирована")
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Section {
            Button {
                Task { await exportPage() }
            } label: {
                HStack {
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                    Text(exportMode == .update ? "Обновить" : "Экспортировать")
                    Spacer()
                }
            }
            .disabled(!canExport || isExporting)
        }
    }

    // MARK: - Logic

    private var canExport: Bool {
        if exportMode == .update {
            return !pageTitle.isEmpty && recording.confluencePageId != nil
        } else {
            return !pageTitle.isEmpty && selectedSpaceKey != nil
        }
    }

    private func setupInitialValues() {
        // Название по умолчанию
        pageTitle = recording.linkedMeetingSubject ?? recording.title

        // Добавим дату для уникальности
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "d MMM yyyy"
        let dateString = dateFormatter.string(from: recording.createdAt)
        if !pageTitle.contains(dateString) {
            pageTitle = "\(pageTitle) — \(dateString)"
        }

        // Расположение по умолчанию
        selectedSpaceKey = manager.defaultSpaceKey
        selectedParentPageId = manager.defaultParentPageId
        selectedParentPageTitle = manager.defaultParentPageTitle

        // Режим по умолчанию
        exportMode = recording.isExportedToConfluence ? .update : .create
    }

    private func exportPage() async {
        isExporting = true

        do {
            let page: ConfluencePage

            if exportMode == .update, let existingPageId = recording.confluencePageId {
                // Обновляем существующую страницу
                page = try await manager.updateMeeting(
                    recording: recording,
                    pageId: existingPageId,
                    title: pageTitle
                )
            } else {
                // Создаём новую страницу
                guard let spaceKey = selectedSpaceKey else {
                    throw ConfluenceError.notFound("Не выбрано пространство")
                }

                page = try await manager.exportMeeting(
                    recording: recording,
                    title: pageTitle,
                    spaceKey: spaceKey,
                    parentPageId: selectedParentPageId
                )
            }

            // Сохраняем информацию об экспорте в Recording
            let webURL = page.webURL?.absoluteString ?? page._links?.webui
            recording.markExportedToConfluence(pageId: page.id, pageURL: webURL)

            isExporting = false
            dismiss()
            onSuccess(page.webURL)

        } catch let error as ConfluenceError {
            errorMessage = error.errorDescription ?? "Ошибка экспорта"
            showError = true
            isExporting = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isExporting = false
        }
    }
}

#Preview {
    @Previewable @State var recording = Recording(
        title: "Test Meeting",
        audioFileURL: "/test.m4a",
        transcriptionText: "Test transcription",
        summaryText: "# Summary\n\nThis is a test summary."
    )

    ConfluenceExportSheet(recording: recording) { url in
        print("Success: \(url?.absoluteString ?? "no url")")
    }
}
