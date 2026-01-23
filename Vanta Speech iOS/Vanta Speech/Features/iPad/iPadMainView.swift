import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// iPad объединённый главный экран: Календарь слева, Запись справа
struct iPadMainView: View {
    @Binding var selectedRecording: Recording?
    var onOpenInNewWindow: ((Recording) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recorder: AudioRecorder
    @EnvironmentObject var coordinator: RecordingCoordinator

    @Query(sort: \Recording.createdAt, order: .reverse) private var allRecordings: [Recording]

    // Calendar state
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?

    // Recording state
    @State private var currentRecordingMode = "standard"
    @State private var showRecordingSheet = false
    @State private var showRealtimeRecordingSheet = false
    @State private var showRealtimeWarning = false
    @State private var pendingRealtimePreset: RecordingPreset?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showRecordingOptionsSheet = false
    @State private var showFileImporter = false
    @State private var showPresetPickerForImport = false
    @State private var importedAudioData: AudioImporter.ImportedAudio?
    @State private var isImporting = false

    @StateObject private var presetSettings = PresetSettings.shared
    @StateObject private var calendarManager = EASCalendarManager.shared

    private let calendar = Calendar.current

    // MARK: - Computed Properties

    private var recordingDates: Set<DateComponents> {
        Set(allRecordings.map { recording in
            calendar.dateComponents([.year, .month, .day], from: recording.createdAt)
        })
    }

    private var recordingsCountForMonth: Int {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? displayedMonth

        return allRecordings.filter { recording in
            recording.createdAt >= startOfMonth && recording.createdAt < endOfMonth
        }.count
    }

    private var displayedRecordings: [Recording] {
        if let date = selectedDate {
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return allRecordings.filter { $0.createdAt >= startOfDay && $0.createdAt < endOfDay }
        } else {
            return Array(allRecordings.prefix(20))
        }
    }

    private var todayRecordings: [Recording] {
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return allRecordings.filter { $0.createdAt >= startOfDay && $0.createdAt < endOfDay }
    }

    private var listTitle: String {
        if let date = selectedDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateStyle = .long
            return formatter.string(from: date)
        } else {
            return "Последние записи"
        }
    }

    private var isImportMode: Bool { currentRecordingMode == "import" }
    private var isRealtimeMode: Bool { currentRecordingMode == "realtime" }

    private var currentModeDisplayName: String {
        switch currentRecordingMode {
        case "realtime": return "Real-time"
        case "import": return "Импорт"
        default: return "Записать"
        }
    }

    private var currentModeIcon: String {
        switch currentRecordingMode {
        case "realtime": return "text.badge.plus"
        case "import": return "square.and.arrow.down"
        default: return "mic.fill"
        }
    }

    private var upcomingMeeting: EASCalendarEvent? {
        let now = Date()
        let twoHoursLater = now.addingTimeInterval(2 * 60 * 60)

        return calendarManager.cachedEvents
            .filter { event in
                let isOngoing = event.startTime <= now && event.endTime > now
                let isUpcoming = event.startTime > now && event.startTime <= twoHoursLater
                return isOngoing || isUpcoming
            }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private var todayMeetings: [EASCalendarEvent] {
        calendarManager.cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: Date())
        }
    }

    private var weekMeetings: [EASCalendarEvent] {
        let now = Date()
        let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        return calendarManager.cachedEvents.filter { event in
            event.startTime >= now && event.startTime <= weekFromNow
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                // ЛЕВАЯ КОЛОНКА - Календарь и записи
                leftColumn
                    .frame(width: geometry.size.width * 0.5, alignment: .top)

                Divider()

                // ПРАВАЯ КОЛОНКА - Встречи и запись
                rightColumn
                    .frame(width: geometry.size.width * 0.5, alignment: .top)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            let defaultMode = UserDefaults.standard.string(forKey: "defaultRecordingMode") ?? "standard"
            currentRecordingMode = defaultMode
        }
        .sheet(isPresented: $showRecordingSheet) {
            if let preset = coordinator.currentPreset {
                ActiveRecordingSheet(preset: preset, onStop: stopRecording)
                    .environmentObject(recorder)
                    .environmentObject(coordinator)
            }
        }
        .sheet(isPresented: $showRealtimeRecordingSheet) {
            if let preset = coordinator.currentPreset {
                RealtimeRecordingSheet(preset: preset, onStop: stopRealtimeRecording)
                    .environmentObject(coordinator)
            }
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Real-time транскрипция", isPresented: $showRealtimeWarning) {
            Button("Начать запись") {
                if let preset = pendingRealtimePreset {
                    startRealtimeRecording(preset: preset)
                }
                pendingRealtimePreset = nil
            }
            Button("Отмена", role: .cancel) {
                pendingRealtimePreset = nil
            }
        } message: {
            Text("В этом режиме не сворачивайте приложение. При сворачивании запись будет приостановлена.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AudioImporter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result: result)
        }
        .sheet(isPresented: $showPresetPickerForImport) {
            if let audioData = importedAudioData {
                ImportPresetPickerSheet(
                    audioData: audioData,
                    presets: presetSettings.enabledPresets,
                    onSelect: { preset in
                        finalizeImport(audioData: audioData, preset: preset)
                        showPresetPickerForImport = false
                    },
                    onCancel: {
                        try? FileManager.default.removeItem(at: audioData.url)
                        importedAudioData = nil
                        showPresetPickerForImport = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showRecordingOptionsSheet) {
            RecordingOptionsSheet(
                upcomingMeeting: upcomingMeeting,
                presets: presetSettings.enabledPresets,
                isRealtimeMode: isRealtimeMode,
                onSelectPreset: { preset, linkToMeeting in
                    showRecordingOptionsSheet = false
                    if linkToMeeting, let meeting = upcomingMeeting {
                        MeetingRecordingLink.shared.pendingMeetingEvent = meeting
                    }
                    startRecordingWithPreset(preset, realtime: isRealtimeMode)
                },
                onCancel: {
                    showRecordingOptionsSheet = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if isImporting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView("Импорт...")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
            }
        }
    }

    // MARK: - Left Column (Calendar + Stats + Recordings)

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Календарь
            VStack(spacing: 0) {
                CalendarView(
                    selectedDate: $selectedDate,
                    displayedMonth: $displayedMonth,
                    recordingDates: recordingDates
                )
                .padding()
            }
            .vantaGlassCard(cornerRadius: 20, shadowRadius: 0, tintOpacity: 0.15)
            .padding()

            // Статистика (2x2 сетка)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatCard(
                        title: "Всего",
                        value: "\(allRecordings.count)",
                        icon: "waveform",
                        color: .pinkVibrant
                    )

                    StatCard(
                        title: "За месяц",
                        value: "\(recordingsCountForMonth)",
                        icon: "calendar",
                        color: .blueVibrant
                    )
                }

                HStack(spacing: 12) {
                    StatCard(
                        title: "Сегодня",
                        value: "\(todayMeetings.count)",
                        icon: "calendar.badge.clock",
                        color: .green
                    )

                    StatCard(
                        title: "На неделе",
                        value: "\(weekMeetings.count)",
                        icon: "calendar",
                        color: .blue
                    )
                }
            }
            .padding(.horizontal)

            Divider()
                .padding(.top, 16)

            // Заголовок списка
            HStack {
                Text(listTitle)
                    .font(.headline)

                Spacer()

                if selectedDate != nil {
                    Button("Сбросить") {
                        selectedDate = nil
                    }
                    .font(.subheadline)
                }

                Text("\(displayedRecordings.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .padding()

            // Записи
            if displayedRecordings.isEmpty {
                emptyRecordingsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(displayedRecordings) { recording in
                            RecordingCard(recording: recording) {
                                selectedRecording = recording
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(selectedRecording?.id == recording.id ? Color.pinkVibrant.opacity(0.1) : Color.clear)
                            )
                            .contextMenu {
                                Button {
                                    selectedRecording = recording
                                } label: {
                                    Label("Открыть", systemImage: "arrow.right.circle")
                                }

                                if onOpenInNewWindow != nil {
                                    Button {
                                        onOpenInNewWindow?(recording)
                                    } label: {
                                        Label("Открыть в новом окне", systemImage: "macwindow.badge.plus")
                                    }
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deleteRecording(recording)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var emptyRecordingsView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: selectedDate != nil ? "calendar.badge.exclamationmark" : "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(selectedDate != nil ? "Нет записей за эту дату" : "Нет записей")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(selectedDate != nil ? "Выберите другую дату" : "Начните запись справа")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Right Column (Meetings + Recording)

    private var rightColumn: some View {
        ZStack {
            VStack(spacing: 0) {
                // Picker режима
                Picker("Режим", selection: $currentRecordingMode) {
                    Text("Обычная").tag("standard")
                    Text("Real-time").tag("realtime")
                    Text("Импорт").tag("import")
                }
                .pickerStyle(.segmented)
                .padding()

                // Контент (scrollable)
                ScrollView {
                    VStack(spacing: 16) {
                        // Active recording indicator
                        if recorder.isRecording || coordinator.isRealtimeMode {
                            activeRecordingView
                        }

                        // Встречи из календаря
                        UpcomingMeetingsSection()
                            .environment(\.currentRecordingMode, currentRecordingMode)

                        // Записи за сегодня
                        if !todayRecordings.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Сегодня")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text("\(todayRecordings.count)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5))
                                        .clipShape(Capsule())
                                }

                                ForEach(todayRecordings) { recording in
                                    RecordingCard(recording: recording) {
                                        selectedRecording = recording
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 100) // Место для floating кнопки
                }
                .refreshable {
                    if calendarManager.isConnected {
                        await calendarManager.forceFullSync()
                    }
                }
            }

            // Floating кнопка записи
            VStack {
                Spacer()
                microphoneButton
                    .padding(.bottom, 24)
            }
        }
    }

    private var activeRecordingView: some View {
        VStack(spacing: 24) {
            FrequencyVisualizerView(level: coordinator.isRealtimeMode
                ? coordinator.realtimeSpeechRecognizer.audioLevel
                : recorder.audioLevel)
                .frame(height: 100)
                .padding(.horizontal)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant)
                        .frame(width: 12, height: 12)
                        .modifier(PulseAnimation())

                    Text("Идёт запись")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                if coordinator.isRealtimeMode {
                    Text("Real-time транскрипция")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(formatTime(coordinator.isRealtimeMode
                    ? coordinator.realtimeSpeechRecognizer.recordingDuration
                    : recorder.recordingDuration))
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)

                if let preset = coordinator.currentPreset {
                    Label(preset.displayName, systemImage: preset.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .vantaGlassCard(cornerRadius: 24, shadowRadius: 0, tintOpacity: 0.15)
    }

    @ViewBuilder
    private var microphoneButton: some View {
        if recorder.isRecording || coordinator.isRealtimeMode {
            Button {
                if coordinator.isRealtimeMode {
                    showRealtimeRecordingSheet = true
                } else {
                    showRecordingSheet = true
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(coordinator.isRealtimeMode ? Color.green : Color.pinkVibrant)
                        .frame(width: 10, height: 10)
                        .modifier(PulseAnimation())

                    Image(systemName: coordinator.isRealtimeMode ? "text.badge.plus" : "waveform")
                        .font(.title2)

                    Text(formatTime(coordinator.isRealtimeMode
                        ? coordinator.realtimeSpeechRecognizer.recordingDuration
                        : recorder.recordingDuration))
                        .font(.title3)
                        .monospacedDigit()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .vantaGlassProminent(cornerRadius: 32)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                handleButtonTap()
            } label: {
                HStack(spacing: 12) {
                    if recorder.isConverting {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Image(systemName: currentModeIcon)
                            .font(.title2)
                            .frame(width: 24, height: 24)
                    }

                    Text(currentModeDisplayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 40)
                .padding(.vertical, 18)
                .vantaGlassProminent(cornerRadius: 32)
            }
            .buttonStyle(.plain)
            .disabled(recorder.isConverting)
        }
    }

    // MARK: - Actions

    private func handleButtonTap() {
        if isImportMode {
            showFileImporter = true
        } else {
            showRecordingOptionsSheet = true
        }
    }

    private func startRecordingWithPreset(_ preset: RecordingPreset, realtime: Bool = false) {
        if realtime {
            pendingRealtimePreset = preset
            showRealtimeWarning = true
        } else {
            Task {
                do {
                    try await coordinator.startRecording(preset: preset)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                    debugCaptureError(error, context: "Starting recording (iPad)")
                }
            }
        }
    }

    private func startRealtimeRecording(preset: RecordingPreset) {
        Task {
            do {
                try await coordinator.startRealtimeRecording(preset: preset)
                showRealtimeRecordingSheet = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                debugCaptureError(error, context: "Starting realtime recording (iPad)")
            }
        }
    }

    private func stopRecording() {
        showRecordingSheet = false
        Task {
            _ = await coordinator.stopRecording()
            if UserDefaults.standard.bool(forKey: "autoTranscribe") {
                await coordinator.startTranscription()
            }
        }
    }

    private func stopRealtimeRecording() {
        showRealtimeRecordingSheet = false
        Task {
            _ = await coordinator.stopRealtimeRecording()
            await coordinator.startRealtimeSummarization()
        }
    }

    private func deleteRecording(_ recording: Recording) {
        if recording.id == selectedRecording?.id {
            selectedRecording = nil
        }
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Import Handling

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true

            Task {
                do {
                    let importer = AudioImporter()
                    let audioData = try await importer.importAudio(from: url)
                    importedAudioData = audioData
                    isImporting = false
                    showPresetPickerForImport = true
                } catch {
                    isImporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                    debugCaptureError(error, context: "Importing audio file (iPad)")
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
            debugCaptureError(error, context: "File picker error (iPad)")
        }
    }

    private func finalizeImport(audioData: AudioImporter.ImportedAudio, preset: RecordingPreset) {
        let recording = Recording(
            id: UUID(),
            title: "\(preset.displayName) - \(audioData.originalFileName)",
            duration: audioData.duration,
            audioFileURL: audioData.url.path,
            preset: preset
        )

        modelContext.insert(recording)
        try? modelContext.save()
        importedAudioData = nil

        debugLog("Import completed (iPad): \(audioData.originalFileName), duration: \(audioData.duration)s", module: "iPadMainView")
    }
}

// MARK: - Stat Card (compact for horizontal layout)

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(color.opacity(0.15))
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
            }
            .frame(width: 36, height: 36)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .vantaGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.15)
    }
}

#Preview {
    iPadMainView(selectedRecording: .constant(nil))
        .environmentObject(AudioRecorder())
        .environmentObject(RecordingCoordinator.shared)
        .modelContainer(for: Recording.self, inMemory: true)
}
