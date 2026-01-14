import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var isTranscribing = false
    @State private var isGeneratingSummary = false
    @State private var summaryError: String? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTranscriptionSheet = false
    @State private var showSummarySheet = false
    @State private var audioLoadFailed = false
    @State private var showContinueRecordingSheet = false
    @State private var showContinueConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Recording Header Card
                headerCard

                // Audio Player Card
                playerCard

                // Continue Recording Button
                if !audioLoadFailed {
                    continueRecordingButton
                }

                // Transcribe Button (if not transcribed)
                if !recording.isTranscribed {
                    transcribeButton
                }

                // Content Tabs (Transcription / Summary)
                // Show if we have transcription (even if summary is still generating)
                if recording.transcriptionText != nil {
                    contentSection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Запись")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    shareMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            player.stop()
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Продолжить запись?", isPresented: $showContinueConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Продолжить", role: .destructive) {
                startContinueRecording()
            }
        } message: {
            Text("Транскрипция и саммари будут удалены. После остановки записи аудио будет склеено в один файл и потребуется новая транскрипция.")
        }
        .sheet(isPresented: $showContinueRecordingSheet) {
            if let preset = coordinator.currentPreset {
                ActiveRecordingSheet(preset: preset, onStop: stopContinueRecording)
                    .environmentObject(coordinator)
                    .environmentObject(coordinator.audioRecorder)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            // Waveform visualization
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.pinkLight.opacity(0.4), .blueLight.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 100)

                HStack(spacing: 3) {
                    ForEach(0..<40, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.pinkVibrant.opacity(0.6))
                            .frame(width: 4, height: CGFloat.random(in: 15...60))
                    }
                }
            }

            VStack(spacing: 8) {
                Text(recording.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                HStack(spacing: 24) {
                    Label(recording.formattedDate, systemImage: "calendar")
                    Label(recording.formattedDuration, systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                // Status badges
                HStack(spacing: 12) {
                    statusBadge(
                        text: "M4A",
                        color: .blueVibrant
                    )

                    if recording.isTranscribed {
                        statusBadge(
                            text: "Транскрибировано",
                            color: .pinkVibrant
                        )
                    }

                    if recording.isUploading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Обработка...")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.blueVibrant)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .vantaGlassCard(cornerRadius: 28, shadowRadius: 0, tintOpacity: 0.15)
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .fill(Color.pinkVibrant.opacity(0.15))
                }
            }
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Player Card

    private var playerCard: some View {
        VStack(spacing: 16) {
            if audioLoadFailed {
                // Audio unavailable state
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    Text("Аудиофайл недоступен")
                        .font(.headline)

                    Text("Файл мог быть удален или поврежден после обновления приложения")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Progress Bar
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { player.progress },
                        set: { player.seekToProgress($0) }
                    ), in: 0...1)
                    .tint(.pinkVibrant)

                    HStack {
                        Text(player.formattedCurrentTime)
                        Spacer()
                        Text(player.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

                // Playback Controls
                HStack(spacing: 32) {
                    Button {
                        player.seek(to: max(0, player.currentTime - 15))
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }
                    .foregroundStyle(.primary)

                    Button {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(VantaIconButtonStyle(size: 64, isPrimary: true))

                    Button {
                        player.seek(to: min(player.duration, player.currentTime + 15))
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding(20)
        .vantaGlassCard(cornerRadius: 28, shadowRadius: 0, tintOpacity: 0.15)
    }

    // MARK: - Continue Recording Button

    private var continueRecordingButton: some View {
        Button {
            // Если есть транскрипция - показываем предупреждение
            if recording.isTranscribed {
                showContinueConfirmation = true
            } else {
                startContinueRecording()
            }
        } label: {
            HStack {
                Image(systemName: "mic.badge.plus")
                Text("Продолжить запись")
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(coordinator.audioRecorder.isRecording)
    }

    // MARK: - Transcribe Button

    private var transcribeButton: some View {
        Button {
            transcribeRecording()
        } label: {
            HStack {
                if isTranscribing {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isTranscribing ? "Транскрибирую..." : "Транскрибировать")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .vantaGlassProminent(cornerRadius: 20, tintOpacity: 0.15)
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showTranscriptionSheet = true
                } label: {
                    Label("Транскрипция", systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(recording.transcriptionText == nil)

                Button {
                    showSummarySheet = true
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingSummary || recording.isSummaryGenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Генерируем...")
                        } else {
                            Label("Саммари", systemImage: "doc.text")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(recording.summaryText == nil && !isGeneratingSummary && !recording.isSummaryGenerating)
            }

            // Retry button if summary failed
            if summaryError != nil && recording.summaryText == nil && !isGeneratingSummary {
                Button {
                    regenerateSummary()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Повторить генерацию саммари")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .sheet(isPresented: $showTranscriptionSheet) {
            ContentSheetView(
                title: "Транскрипция",
                icon: "text.bubble",
                content: recording.transcriptionText ?? ""
            )
        }
        .sheet(isPresented: $showSummarySheet) {
            ContentSheetView(
                title: "Саммари",
                icon: "doc.text",
                content: recording.summaryText ?? "",
                onCheckboxToggle: { lineIndex in
                    guard let currentText = recording.summaryText else { return }
                    recording.summaryText = MarkdownCheckboxToggler.toggleCheckbox(in: currentText, at: lineIndex)
                }
            )
        }
    }

    // MARK: - Share Menu

    @ViewBuilder
    private var shareMenuContent: some View {
        if recording.isTranscribed {
            Button {
                copyTranscription()
            } label: {
                Label("Копировать транскрипцию", systemImage: "doc.on.doc")
            }

            Button {
                copySummary()
            } label: {
                Label("Копировать саммари", systemImage: "doc.on.doc")
            }

            Divider()
        }

        Button {
            shareAudio()
        } label: {
            Label("Поделиться аудио", systemImage: "square.and.arrow.up")
        }

        Button {
            exportToFiles()
        } label: {
            Label("Сохранить в Файлы", systemImage: "folder")
        }
    }

    // MARK: - Actions

    private func loadAudio() {
        let url = URL(fileURLWithPath: recording.audioFileURL)

        // Check if file exists first
        guard FileManager.default.fileExists(atPath: recording.audioFileURL) else {
            audioLoadFailed = true
            return
        }

        do {
            try player.load(url: url)
        } catch {
            // Audio file exists but can't be loaded (corrupted or incompatible format)
            audioLoadFailed = true
        }
    }

    private func transcribeRecording() {
        isTranscribing = true
        recording.isUploading = true
        summaryError = nil

        Task {
            do {
                let service = TranscriptionService()
                let audioURL = URL(fileURLWithPath: recording.audioFileURL)
                let preset = recording.preset ?? .projectMeeting

                _ = try await service.transcribeWithProgress(
                    audioFileURL: audioURL,
                    preset: preset
                ) { stage in
                    await MainActor.run {
                        switch stage {
                        case .transcriptionCompleted(let text):
                            // Show transcription immediately
                            recording.transcriptionText = text
                            recording.isTranscribed = true
                            isTranscribing = false

                        case .generatingSummary:
                            isGeneratingSummary = true
                            recording.isSummaryGenerating = true

                        case .summaryCompleted(let summary):
                            recording.summaryText = summary
                            isGeneratingSummary = false
                            recording.isSummaryGenerating = false

                        case .completed(let result):
                            // Update title with AI-generated one if available
                            if let generatedTitle = result.generatedTitle {
                                recording.title = generatedTitle
                            }
                            recording.isUploading = false

                        case .error(let error):
                            // If transcription already exists, this is a summary error
                            if recording.transcriptionText != nil {
                                summaryError = error.localizedDescription
                                isGeneratingSummary = false
                                recording.isSummaryGenerating = false
                            }

                        default:
                            break
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    recording.isUploading = false
                    isTranscribing = false
                    isGeneratingSummary = false
                    recording.isSummaryGenerating = false
                    debugCaptureError(error, context: "Transcription in RecordingDetailView")
                }
            }
        }
    }

    private func regenerateSummary() {
        guard let transcription = recording.transcriptionText else { return }

        isGeneratingSummary = true
        recording.isSummaryGenerating = true
        summaryError = nil

        Task {
            do {
                let service = TranscriptionService()
                let preset = recording.preset ?? .projectMeeting
                let (summary, title) = try await service.summarize(text: transcription, preset: preset)

                await MainActor.run {
                    recording.summaryText = summary
                    if let generatedTitle = title {
                        recording.title = generatedTitle
                    }
                    isGeneratingSummary = false
                    recording.isSummaryGenerating = false
                }
            } catch {
                await MainActor.run {
                    summaryError = error.localizedDescription
                    isGeneratingSummary = false
                    recording.isSummaryGenerating = false
                    debugCaptureError(error, context: "Regenerate summary in RecordingDetailView")
                }
            }
        }
    }

    private func copyTranscription() {
        guard let text = recording.transcriptionText else { return }
        copyToClipboard(text)
    }

    private func copySummary() {
        guard let text = recording.summaryText else { return }
        copyToClipboard(text)
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func shareAudio() {
        let url = URL(fileURLWithPath: recording.audioFileURL)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func exportToFiles() {
        // TODO: Implement export to Files app
    }

    // MARK: - Continue Recording Actions

    private func startContinueRecording() {
        player.stop()

        Task {
            do {
                try await coordinator.continueRecording(recording: recording)
                showContinueRecordingSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                debugCaptureError(error, context: "Continue recording")
            }
        }
    }

    private func stopContinueRecording() {
        showContinueRecordingSheet = false

        Task {
            if let updatedRecording = await coordinator.stopRecording() {
                // Перезагружаем аудио с новым файлом
                loadAudio()
            }
        }
    }
}

// MARK: - Content Sheet View

struct ContentSheetView: View {
    let title: String
    let icon: String
    let content: String
    /// Optional callback when a checkbox is toggled. Parameter is the line number (0-indexed).
    var onCheckboxToggle: ((Int) -> Void)?
    @Environment(\.dismiss) private var dismiss

    // Integration states from settings
    @AppStorage("confluence_connected") private var confluenceConnected = false
    @AppStorage("notion_connected") private var notionConnected = false
    @AppStorage("googledocs_connected") private var googleDocsConnected = false

    private var hasAnyIntegration: Bool {
        confluenceConnected || notionConnected || googleDocsConnected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if content.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.badge.xmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Недоступно")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    MarkdownContentView(text: content, onCheckboxToggle: onCheckboxToggle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !content.isEmpty {
                        Menu {
                            // Show connected integrations
                            if confluenceConnected {
                                Button {
                                    exportToConfluence()
                                } label: {
                                    Label("Confluence", systemImage: "doc.text")
                                }
                            }

                            if notionConnected {
                                Button {
                                    exportToNotion()
                                } label: {
                                    Label("Notion", systemImage: "doc.richtext")
                                }
                            }

                            if googleDocsConnected {
                                Button {
                                    exportToGoogleDocs()
                                } label: {
                                    Label("Google Docs", systemImage: "doc.text.fill")
                                }
                            }

                            if hasAnyIntegration {
                                Divider()
                            }

                            // Always show Share option
                            Button {
                                shareContent()
                            } label: {
                                Label("Поделиться", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Экспорт")
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !content.isEmpty {
                        Button {
                            copyToClipboard()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Копировать")
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #endif
    }

    private func shareContent() {
        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [content], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            // Find the topmost presented view controller
            var topController = rootVC
            while let presented = topController.presentedViewController {
                topController = presented
            }
            activityVC.popoverPresentationController?.sourceView = topController.view
            topController.present(activityVC, animated: true)
        }
        #endif
    }

    private func exportToConfluence() {
        // TODO: Implement Confluence export
        debugLog("Export to Confluence: \(title)", module: "ContentSheetView")
    }

    private func exportToNotion() {
        // TODO: Implement Notion export
        debugLog("Export to Notion: \(title)", module: "ContentSheetView")
    }

    private func exportToGoogleDocs() {
        // TODO: Implement Google Docs export
        debugLog("Export to Google Docs: \(title)", module: "ContentSheetView")
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recording: Recording(
            title: "Еженедельный созвон команды",
            duration: 1845,
            audioFileURL: "/test/path.ogg",
            transcriptionText: """
            # Заметки со встречи

            ## Участники
            - Иван Иванов
            - Мария Петрова
            - Алексей Сидоров

            ## Обсуждаемые вопросы

            1. **Планирование Q4**
               - Обзор текущего прогресса
               - Обсуждение бюджета

            2. **Обновления продукта**
               - Релиз новой функции запланирован на следующую неделю
               - Исправление багов в процессе

            > Важно: Связаться с дизайн-командой до пятницы

            ## Задачи
            - [ ] Отправить заметки заинтересованным лицам
            - [ ] Назначить следующую встречу
            - [ ] Проверить черновик предложения
            """,
            summaryText: """
            # Саммари

            Команда обсудила **планирование Q4** и **обновления продукта**. Ключевые решения: запланировать релиз новой функции на следующую неделю.

            ## Следующие шаги
            1. Связаться с дизайн-командой
            2. Проверить распределение бюджета
            3. Подготовить презентацию для стейкхолдеров
            """,
            isTranscribed: true
        ))
        .environmentObject(RecordingCoordinator.shared)
    }
}
