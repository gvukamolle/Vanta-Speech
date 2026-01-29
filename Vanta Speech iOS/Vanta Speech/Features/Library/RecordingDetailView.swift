import SwiftUI
import SwiftData

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    /// Available events for linking (optional, for DayRecordingsSheet context)
    var availableEventsForLinking: [EASCalendarEvent] = []
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var coordinator: RecordingCoordinator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @StateObject private var calendarManager = EASCalendarManager.shared
    @State private var isTranscribing = false
    @State private var isGeneratingSummary = false
    @State private var summaryError: String? = nil
    @State private var transcriptionTask: Task<Void, Never>? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTranscriptionSheet = false
    @State private var showSummarySheet = false
    @State private var audioLoadFailed = false
    @State private var showContinueRecordingSheet = false
    @State private var showContinueConfirmation = false
    @State private var showEventPicker = false
    @State private var showMeetingDetail = false
    @State private var showMeetingActions = false
    
    // Meeting linking warning
    @State private var showMeetingLinkWarning = false
    @State private var pendingTranscriptionAction: (() -> Void)?

    // Title editing
    @State private var showTitleEditor = false
    @State private var editedTitle = ""

    // Summary email
    @StateObject private var summaryEmailManager = SummaryEmailManager.shared
    @State private var showSendSummarySuccess = false
    @State private var showSendSummaryError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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

                // Meeting Link Section (after Transcription/Summary buttons)
                if calendarManager.isConnected {
                    meetingLinkSection
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
        .tint(.primary)
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
        .alert("Название записи", isPresented: $showTitleEditor) {
            TextField("Название", text: $editedTitle)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                if !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recording.title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } message: {
            Text("Введите новое название для записи")
        }
        .sheet(isPresented: $showContinueRecordingSheet) {
            if let preset = coordinator.currentPreset {
                ActiveRecordingSheet(preset: preset, onStop: stopContinueRecording)
                    .environmentObject(coordinator)
                    .environmentObject(coordinator.audioRecorder)
            }
        }
        .meetingLinkingAlert(
            isPresented: $showMeetingLinkWarning,
            for: recording,
            onSend: {
                // User chose to send without linking
                if let action = pendingTranscriptionAction {
                    action()
                }
                pendingTranscriptionAction = nil
            },
            onLink: {
                // User chose to link - show event picker
                showEventPicker = true
            }
        )
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            Button {
                editedTitle = recording.title
                showTitleEditor = true
            } label: {
                HStack(spacing: 8) {
                    Text(recording.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                Label(recording.formattedDate, systemImage: "calendar")
                Label(recording.formattedDuration, systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .vantaGlassCard(cornerRadius: 20, shadowRadius: 0, tintOpacity: 0.15)
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
                    .buttonStyle(VantaIconButtonStyle(size: 56, isPrimary: true))

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
        .padding(16)
        .vantaGlassCard(cornerRadius: 20, shadowRadius: 0, tintOpacity: 0.15)
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
            HStack(spacing: 8) {
                Image(systemName: "mic.badge.plus")
                Text("Продолжить запись")
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(coordinator.audioRecorder.isRecording)
    }

    // MARK: - Transcribe Button

    private var transcribeButton: some View {
        VStack(spacing: 12) {
            Button {
                checkAndStartTranscription()
            } label: {
                HStack(spacing: 8) {
                    if isAnyTranscribing {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isAnyTranscribing ? "Получаем саммари..." : "Получить саммари")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .vantaGlassProminent(cornerRadius: 16, tintOpacity: 0.15)
            }
            .buttonStyle(.plain)
            .disabled(isAnyTranscribing)

            if canCancelTranscription {
                Button {
                    cancelTranscription()
                } label: {
                    Label("Отменить транскрипцию", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Transcription Button - StatCard style
                Button {
                    showTranscriptionSheet = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                            Circle()
                                .fill(Color.pinkVibrant.opacity(0.15))
                            Image(systemName: "text.bubble")
                                .font(.callout)
                                .foregroundStyle(Color.pinkVibrant)
                        }
                        .frame(width: 36, height: 36)

                        Text("Расшифровка")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
                }
                .buttonStyle(.plain)
                .disabled(recording.transcriptionText == nil)
                .opacity(recording.transcriptionText == nil ? 0.5 : 1.0)

                // Summary Button - StatCard style
                Button {
                    showSummarySheet = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                            Circle()
                                .fill(Color.pinkVibrant.opacity(0.15))
                            if isGeneratingSummary || recording.isSummaryGenerating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "doc.text")
                                    .font(.callout)
                                    .foregroundStyle(Color.pinkVibrant)
                            }
                        }
                        .frame(width: 36, height: 36)

                        Text(isGeneratingSummary || recording.isSummaryGenerating ? "Генерируем..." : "Саммари")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
                }
                .buttonStyle(.plain)
                .disabled(recording.summaryText == nil && !isGeneratingSummary && !recording.isSummaryGenerating)
                .opacity((recording.summaryText == nil && !isGeneratingSummary && !recording.isSummaryGenerating) ? 0.5 : 1.0)
            }

            // Retry button if summary failed
            if summaryError != nil && recording.summaryText == nil && !isGeneratingSummary {
                Button {
                    regenerateSummary()
                } label: {
                    HStack(spacing: 6) {
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
                title: "Расшифровка",
                icon: "text.bubble",
                content: recording.transcriptionText ?? "",
                recording: recording
            )
        }
        .sheet(isPresented: $showSummarySheet) {
            ContentSheetView(
                title: "Саммари",
                icon: "doc.text",
                content: recording.summaryText ?? "",
                recording: recording,
                onCheckboxToggle: { lineIndex in
                    guard let currentText = recording.summaryText else { return }
                    recording.summaryText = MarkdownCheckboxToggler.toggleCheckbox(in: currentText, at: lineIndex)
                },
                isEditable: true,
                onContentChange: { newContent in
                    recording.summaryText = newContent
                },
                onRegenerateSummary: regenerateSummaryCallback
            )
        }
    }

    // MARK: - Summary Regeneration

    /// Callback for regenerating summary from transcription
    private var regenerateSummaryCallback: (() async -> Void)? {
        guard recording.transcriptionText != nil else { return nil }
        return { [self] in
            // Проверяем привязку перед регенерацией саммари
            if !self.recording.hasLinkedMeeting && !self.eventsForLinking.isEmpty {
                // Сохраняем действие и показываем предупреждение
                self.pendingTranscriptionAction = { [self] in
                    self.performRegenerateSummaryInternal()
                }
                self.showMeetingLinkWarning = true
                return
            }
            
            await self.performRegenerateSummary()
        }
    }
    
    private func performRegenerateSummary() async {
        guard let transcription = self.recording.transcriptionText else { return }
        let preset = self.recording.preset ?? .projectMeeting

        debugLog("Starting summary regeneration (preset: \(preset.rawValue))", module: "RecordingDetail", level: .info)

        // Устанавливаем флаг генерации (чтобы кнопка "Саммари" показывала состояние)
        await MainActor.run {
            self.recording.isSummaryGenerating = true
        }

        defer {
            Task { @MainActor in
                self.recording.isSummaryGenerating = false
                debugLog("Summary regeneration finished", module: "RecordingDetail", level: .info)
            }
        }

        do {
            let service = TranscriptionService()
            debugLog("Calling TranscriptionService.summarize...", module: "RecordingDetail", level: .info)

            let (newSummary, _) = try await service.summarize(
                text: transcription,
                preset: preset
            )

            debugLog("Summary regenerated successfully (\(newSummary.count) chars)", module: "RecordingDetail", level: .info)

            await MainActor.run {
                self.recording.summaryText = newSummary
            }
        } catch {
            debugLog("Failed to regenerate summary: \(error)", module: "RecordingDetail", level: .error)
        }
    }

    // MARK: - Meeting Link Section

    /// Linked event from calendar (if recording is linked)
    private var linkedEvent: EASCalendarEvent? {
        guard let linkedId = recording.linkedMeetingId else { return nil }
        return calendarManager.cachedEvents.first { $0.id == linkedId }
    }

    /// Events available for linking (excluding already linked ones)
    private var eventsForLinking: [EASCalendarEvent] {
        // Use provided events if available (from DayRecordingsSheet context)
        if !availableEventsForLinking.isEmpty {
            return availableEventsForLinking
        }
        // Otherwise, get events for the same day as the recording
        let calendar = Calendar.current
        return calendarManager.cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: recording.createdAt)
        }
    }

    private var meetingLinkSection: some View {
        VStack(spacing: 12) {
            if recording.hasLinkedMeeting {
                // Linked meeting card - со стеклянным синим стилем
                VStack(alignment: .leading, spacing: 12) {
                    // Карточка события - открывает action sheet
                    Button {
                        showMeetingActions = true
                    } label: {
                        HStack(spacing: 12) {
                            // Иконка календаря
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "calendar")
                                    .font(.title3)
                                    .foregroundStyle(Color.blueVibrant)
                            }
                            
                            // Информация о встрече
                            VStack(alignment: .leading, spacing: 4) {
                                Text(linkedEvent?.subject ?? recording.linkedMeetingSubject ?? "Встреча")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                
                                if let event = linkedEvent {
                                    HStack(spacing: 12) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(formatMeetingTime(event.startTime)) - \(formatMeetingTime(event.endTime))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        if !event.humanAttendees.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "person.2")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text("\(event.humanAttendees.count)")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    
                                    if let location = event.location, !location.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "mappin")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                            Text(location)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .vantaBlueGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
                    
                    // Send Summary Button - в стиле других кнопок
                    if recording.canSendSummary {
                        Button {
                            sendSummary()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                    Circle()
                                        .fill(Color.green.opacity(0.15))
                                    if summaryEmailManager.isSending {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: recording.hasSentSummary ? "envelope.badge.fill" : "envelope")
                                            .font(.callout)
                                            .foregroundStyle(.green)
                                    }
                                }
                                .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recording.hasSentSummary ? "Отправить повторно" : "Отправить саммари")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    
                                    if recording.hasSentSummary, let sentAt = recording.summarySentAt {
                                        Text("Отправлено \(formattedSentDate(sentAt))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(recording.linkedMeetingAttendeeEmails.count) участников")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "paperplane")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.10)
                        }
                        .buttonStyle(.plain)
                        .disabled(summaryEmailManager.isSending)
                    }
                }

            } else if !eventsForLinking.isEmpty {
                // Not linked - show "Link to Event" button
                Button {
                    showEventPicker = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                            Image(systemName: "link")
                                .font(.body)
                                .foregroundStyle(.blue)
                        }
                        .frame(width: 40, height: 40)

                        Text("Связать с событием")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.10)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showEventPicker) {
            EventPickerSheetForRecording(
                recording: recording,
                events: eventsForLinking
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMeetingDetail) {
            if let event = linkedEvent {
                EventDetailSheet(event: event)
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showMeetingActions) {
            MeetingActionsSheet(
                eventName: linkedEvent?.subject ?? recording.linkedMeetingSubject ?? "Встреча",
                onShowDetails: {
                    showMeetingActions = false
                    showMeetingDetail = true
                },
                onSelectOther: {
                    showMeetingActions = false
                    showEventPicker = true
                },
                onUnlink: {
                    recording.unlinkFromMeeting()
                    try? modelContext.save()
                    showMeetingActions = false
                }
            )
            .presentationDetents([.fraction(0.35)])
            .presentationDragIndicator(.visible)
        }
        .alert("Саммари отправлено", isPresented: $showSendSummarySuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            let count = recording.linkedMeetingAttendeeEmails.count - 1 // excluding current user
            Text("Саммари успешно отправлено \(max(count, 1)) участникам встречи")
        }
        .alert("Ошибка отправки", isPresented: $showSendSummaryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(summaryEmailManager.lastError?.localizedDescription ?? "Не удалось отправить саммари")
        }
    }

    private func sendSummary() {
        Task {
            let success = await summaryEmailManager.sendSummary(for: recording)
            if success {
                showSendSummarySuccess = true
            } else {
                showSendSummaryError = true
            }
        }
    }

    private func formattedSentDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatMeetingTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Share Menu

    @ViewBuilder
    private var shareMenuContent: some View {
        if recording.isTranscribed {
            Button {
                copyTranscription()
            } label: {
                Label {
                    Text("Копировать расшифровку")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.primary)
                }
            }

            Button {
                copySummary()
            } label: {
                Label {
                    Text("Копировать саммари")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.primary)
                }
            }

            Divider()
        }

        Button {
            shareAudio()
        } label: {
            Label {
                Text("Поделиться аудио")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.primary)
            }
        }

        Button {
            exportToFiles()
        } label: {
            Label {
                Text("Сохранить в Файлы")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "folder")
                    .foregroundStyle(.primary)
            }
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

    // MARK: - Meeting Linking Check
    
    /// Проверяет привязку к встрече перед транскрибацией
    private func checkAndStartTranscription() {
        // Если запись уже привязана или нет событий для привязки - сразу транскрибируем
        if recording.hasLinkedMeeting || eventsForLinking.isEmpty {
            transcribeRecording()
            return
        }
        
        // Сохраняем действие для выполнения после алерта
        pendingTranscriptionAction = { [self] in
            self.transcribeRecording()
        }
        
        // Показываем предупреждение
        showMeetingLinkWarning = true
    }
    
    private func transcribeRecording() {
        if isAnyTranscribing {
            return
        }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        isTranscribing = true
        recording.isUploading = true
        saveRecordingState()
        summaryError = nil

        let task = Task {
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
                            saveRecordingState()

                        case .generatingSummary:
                            isGeneratingSummary = true
                            recording.isSummaryGenerating = true
                            saveRecordingState()

                        case .summaryCompleted(let summary):
                            recording.summaryText = summary
                            isGeneratingSummary = false
                            recording.isSummaryGenerating = false
                            saveRecordingState()

                            // Auto-send summary to meeting participants if linked
                            Task {
                                await SummaryEmailManager.shared.checkAndAutoSend(recording: recording)
                            }

                        case .completed(let result):
                            // Update title with AI-generated one if available
                            if let generatedTitle = result.generatedTitle {
                                recording.title = generatedTitle
                            }
                            recording.isUploading = false
                            isTranscribing = false
                            saveRecordingState()

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
                await MainActor.run {
                    transcriptionTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    recording.isUploading = false
                    isTranscribing = false
                    isGeneratingSummary = false
                    recording.isSummaryGenerating = false
                    saveRecordingState()
                    transcriptionTask = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    recording.isUploading = false
                    isTranscribing = false
                    isGeneratingSummary = false
                    recording.isSummaryGenerating = false
                    saveRecordingState()
                    transcriptionTask = nil
                    debugCaptureError(error, context: "Transcription in RecordingDetailView")
                }
            }
        }
        transcriptionTask = task
    }

    private func cancelTranscription() {
        if isCoordinatorTranscribing {
            Task {
                await coordinator.cancelTranscription()
            }
            return
        }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        recording.isUploading = false
        isTranscribing = false
        isGeneratingSummary = false
        recording.isSummaryGenerating = false
        summaryError = nil
        saveRecordingState()
    }

    private var isCoordinatorTranscribing: Bool {
        coordinator.isTranscribing && coordinator.pendingTranscription?.recordingId == recording.id
    }

    private var isAnyTranscribing: Bool {
        recording.isUploading || transcriptionTask != nil || isCoordinatorTranscribing
    }

    private var canCancelTranscription: Bool {
        transcriptionTask != nil || isCoordinatorTranscribing
    }

    private func saveRecordingState() {
        do {
            try modelContext.save()
        } catch {
            debugCaptureError(error, context: "Saving recording state in RecordingDetailView")
        }
    }

    private func regenerateSummary() {
        guard let transcription = recording.transcriptionText else { return }
        
        // Проверяем привязку перед регенерацией
        if !recording.hasLinkedMeeting && !eventsForLinking.isEmpty {
            pendingTranscriptionAction = { [self] in
                self.performRegenerateSummaryInternal()
            }
            showMeetingLinkWarning = true
            return
        }
        
        performRegenerateSummaryInternal()
    }
    
    private func performRegenerateSummaryInternal() {
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

                    // Auto-send summary to meeting participants if linked
                    Task {
                        await SummaryEmailManager.shared.checkAndAutoSend(recording: recording)
                    }
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
        #if os(iOS)
        let url = URL(fileURLWithPath: recording.audioFileURL)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

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

    private func exportToFiles() {
        #if os(iOS)
        let url = URL(fileURLWithPath: recording.audioFileURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Аудиофайл не найден"
            showError = true
            return
        }

        let picker = UIDocumentPickerViewController(forExporting: [url])

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            var topController = rootVC
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(picker, animated: true)
        }
        #endif
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

                // Автоматическая транскрипция если включена в настройках
                if UserDefaults.standard.bool(forKey: "autoTranscribe") {
                    await coordinator.startTranscription()
                }
            }
        }
    }
}

// MARK: - Meeting Actions Sheet (в стиле ImportPresetPickerSheet)

private struct MeetingActionsSheet: View {
    let eventName: String
    let onShowDetails: () -> Void
    let onSelectOther: () -> Void
    let onUnlink: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Кнопка деталей встречи
                Button {
                    dismiss()
                    onShowDetails()
                } label: {
                    Label {
                        Text("Детали встречи")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)
                
                // Кнопка выбора другой встречи
                Button {
                    dismiss()
                    onSelectOther()
                } label: {
                    Label {
                        Text("Выбрать другую встречу")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)
                
                // Кнопка отвязки - с красным стилем и иконкой крестика
                Button {
                    dismiss()
                    onUnlink()
                } label: {
                    Label {
                        Text("Отвязать от встречи")
                            .foregroundStyle(.red)
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                .tint(.red)
            }
            .navigationTitle(eventName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Content Sheet View

struct ContentSheetView: View {
    let title: String
    let icon: String
    let content: String
    /// Optional recording for export features (e.g., Confluence)
    var recording: Recording?
    /// Optional callback when a checkbox is toggled. Parameter is the line number (0-indexed).
    var onCheckboxToggle: ((Int) -> Void)?
    /// Whether the content is editable (shows edit button)
    var isEditable: Bool = false
    /// Callback when content is changed (for editable mode)
    var onContentChange: ((String) -> Void)?
    /// Callback for regenerating summary from transcription
    var onRegenerateSummary: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var editedContent = ""
    @State private var showConfluenceExport = false
    @State private var isRegenerating = false

    // Confluence manager
    @StateObject private var confluenceManager = ConfluenceManager.shared

    /// Confluence export available when manager is available and we have a recording with summary
    private var canExportToConfluence: Bool {
        confluenceManager.isAvailable && recording != nil && recording?.summaryText != nil
    }

    private var hasAnyIntegration: Bool {
        canExportToConfluence
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    // Edit mode - Plain text editor (markdown stripped)
                    TextEditor(text: $editedContent)
                        .font(.body)
                        .padding(.horizontal)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemGroupedBackground))
                } else {
                    // View mode - MarkdownContentView
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
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button {
                            editedContent = content
                            isEditing = false
                        } label: {
                            Text("Отмена")
                                .foregroundStyle(.primary)
                        }
                    } else if !content.isEmpty {
                        Menu {
                            // Show connected integrations
                            if canExportToConfluence {
                                Button {
                                    showConfluenceExport = true
                                } label: {
                                    Label {
                                        Text("Confluence")
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }

                            if hasAnyIntegration {
                                Divider()
                            }

                            // Copy option
                            Button {
                                copyToClipboard()
                            } label: {
                                Label {
                                    Text("Копировать")
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundStyle(.primary)
                                }
                            }

                            // Share option
                            Button {
                                shareContent()
                            } label: {
                                Label {
                                    Text("Поделиться")
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(.primary)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Экспорт")
                                    .foregroundStyle(.primary)
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button {
                            // Convert plain text back to markdown before saving
                            onContentChange?(restoreMarkdown(editedContent))
                            isEditing = false
                        } label: {
                            Text("Сохранить")
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                        }
                    } else if !content.isEmpty && isEditable {
                        Menu {
                            Button {
                                // Strip markdown for cleaner editing experience
                                editedContent = stripMarkdown(content)
                                isEditing = true
                            } label: {
                                Label {
                                    Text("Редактировать")
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.primary)
                                }
                            }

                            if onRegenerateSummary != nil {
                                Button {
                                    Task {
                                        isRegenerating = true
                                        await onRegenerateSummary?()
                                        isRegenerating = false
                                    }
                                } label: {
                                    Label {
                                        Text("Сгенерировать заново")
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .disabled(isRegenerating)
                            }
                        } label: {
                            if isRegenerating {
                                ProgressView()
                            } else {
                                Text("Изменить")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .disabled(isRegenerating)
                    }
                }
            }
        }
        .tint(.primary)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            editedContent = content
        }
        .sheet(isPresented: $showConfluenceExport) {
            if let recording = recording {
                ConfluenceExportSheet(recording: recording) { url in
                    if let url = url {
                        debugLog("Exported to Confluence: \(url)", module: "ContentSheetView")
                    }
                }
                .presentationDragIndicator(.visible)
            }
        }
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

    /// Convert checkboxes to symbols for easier editing
    /// Keeps all other markdown (headers, bold, italic) intact
    private func stripMarkdown(_ text: String) -> String {
        var result = text

        // Only convert checkboxes to symbols - leave everything else as-is
        // - [ ] Task -> ☐ Task
        // - [x] Task -> ☑ Task
        result = result.replacingOccurrences(of: "- [ ] ", with: "☐ ")
        result = result.replacingOccurrences(of: "- [x] ", with: "☑ ")
        result = result.replacingOccurrences(of: "- [X] ", with: "☑ ")
        result = result.replacingOccurrences(of: "* [ ] ", with: "☐ ")
        result = result.replacingOccurrences(of: "* [x] ", with: "☑ ")
        result = result.replacingOccurrences(of: "* [X] ", with: "☑ ")
        // Without bullet prefix
        result = result.replacingOccurrences(of: "[ ] ", with: "☐ ")
        result = result.replacingOccurrences(of: "[x] ", with: "☑ ")
        result = result.replacingOccurrences(of: "[X] ", with: "☑ ")

        return result
    }

    /// Restore markdown formatting from plain text before saving
    private func restoreMarkdown(_ text: String) -> String {
        var result = text

        // Convert checkbox symbols back to markdown
        // ☐ → - [ ]
        // ☑ → - [x]
        result = result.replacingOccurrences(of: "☐ ", with: "- [ ] ")
        result = result.replacingOccurrences(of: "☑ ", with: "- [x] ")

        // Handle checkboxes at line start without space after
        result = result.replacingOccurrences(of: "^☐", with: "- [ ]", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n☐", with: "\n- [ ]", options: .regularExpression)
        result = result.replacingOccurrences(of: "^☑", with: "- [x]", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n☑", with: "\n- [x]", options: .regularExpression)

        return result
    }
}

// MARK: - Event Picker Sheet for Recording

private struct EventPickerSheetForRecording: View {
    let recording: Recording
    let events: [EASCalendarEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Кнопка "Отвязать" если есть связь
                    if recording.hasLinkedMeeting {
                        Button(role: .destructive) {
                            recording.unlinkFromMeeting()
                            dismiss()
                        } label: {
                            Label {
                                Text("Отвязать от встречи")
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "link.badge.minus")
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }

                    // Список событий
                    ForEach(events) { event in
                        Button {
                            recording.linkToMeeting(event)
                            dismiss()
                        } label: {
                            EventPickerRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Выберите событие")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.primary)
        .presentationDragIndicator(.visible)
    }

    private func formattedTime(_ event: EASCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startTime)
    }
}

// MARK: - Event Picker Row (синий стиль)

private struct EventPickerRow: View {
    let event: EASCalendarEvent
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка календаря
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Color.blueVibrant)
            }
            
            // Информация о встрече
            VStack(alignment: .leading, spacing: 4) {
                Text(event.subject)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label(formattedTime(event.startTime), systemImage: "clock")
                        .font(.caption)
                    
                    if !event.humanAttendees.isEmpty {
                        Label("\(event.humanAttendees.count)", systemImage: "person.2")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .vantaBlueGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
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
