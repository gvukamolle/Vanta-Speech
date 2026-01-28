import SwiftData
import SwiftUI

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
    @StateObject private var viewModel = RecordingViewModel()
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

    private var isImportMode: Bool { viewModel.isImportMode }
    private var isRealtimeMode: Bool { viewModel.isRealtimeMode }

    private var currentModeDisplayName: String {
        viewModel.currentModeDisplayName
    }

    private var currentModeIcon: String {
        viewModel.currentModeIcon
    }

    private var upcomingMeeting: EASCalendarEvent? {
        viewModel.upcomingMeeting
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
            ZStack(alignment: .bottom) {
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        // ЛЕВАЯ КОЛОНКА - Календарь и записи
                        leftColumn
                            .frame(width: geometry.size.width * 0.5, alignment: .top)

                        Divider()

                        // ПРАВАЯ КОЛОНКА - Встречи и запись
                        rightColumn
                            .frame(width: geometry.size.width * 0.5, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .refreshable {
                    await viewModel.refreshCalendar()
                }

                // Floating кнопка записи (над правой колонкой)
                HStack(spacing: 0) {
                    Spacer()
                    microphoneButton
                        .frame(width: geometry.size.width * 0.5, alignment: .center)
                        .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            viewModel.bind(
                recorder: recorder,
                coordinator: coordinator,
                calendarManager: calendarManager,
                presetSettings: .shared,
                modelContext: modelContext
            )
            viewModel.loadDefaultMode()
        }
        .sheet(isPresented: $viewModel.showRecordingSheet) {
            if let preset = viewModel.currentPreset {
                ActiveRecordingSheet(preset: preset, onStop: viewModel.stopRecording)
                    .environmentObject(recorder)
                    .environmentObject(coordinator)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showRealtimeRecordingSheet) {
            NavigationStack {
                if let preset = viewModel.currentPreset {
                    RealtimeRecordingSheet(preset: preset, onStop: viewModel.stopRealtimeRecording)
                        .environmentObject(coordinator)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    viewModel.showRealtimeRecordingSheet = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                                .disabled(coordinator.realtimeSpeechRecognizer.isRecording)
                            }
                        }
                }
            }
        }
        .alert("Ошибка", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Real-time транскрипция", isPresented: $viewModel.showRealtimeWarning) {
            Button("Начать запись") {
                viewModel.confirmRealtimeRecording()
            }
            Button("Отмена", role: .cancel) {
                viewModel.cancelRealtimeRecording()
            }
        } message: {
            Text("В этом режиме не сворачивайте приложение. При сворачивании запись будет приостановлена.")
        }
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: AudioImporter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleFileImport(result: result)
        }
        .sheet(isPresented: $viewModel.showPresetPickerForImport) {
            if let audioData = viewModel.importedAudioData {
                ImportPresetPickerSheet(
                    audioData: audioData,
                    presets: viewModel.enabledPresets,
                    onSelect: { preset in
                        viewModel.finalizeImport(audioData: audioData, preset: preset)
                        viewModel.showPresetPickerForImport = false
                    },
                    onCancel: {
                        viewModel.cancelImport()
                        viewModel.showPresetPickerForImport = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $viewModel.showRecordingOptionsSheet) {
            RecordingOptionsSheet(
                upcomingMeeting: upcomingMeeting,
                presets: viewModel.enabledPresets,
                isRealtimeMode: isRealtimeMode,
                onSelectPreset: { preset, linkToMeeting in
                    viewModel.showRecordingOptionsSheet = false
                    if linkToMeeting, let meeting = upcomingMeeting {
                        MeetingRecordingLink.shared.pendingMeetingEvent = meeting
                    }
                    viewModel.startRecordingWithPreset(preset, realtime: isRealtimeMode)
                },
                onCancel: {
                    viewModel.showRecordingOptionsSheet = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if viewModel.isImporting {
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
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .vantaGlassCard(cornerRadius: 20, shadowRadius: 0, tintOpacity: 0.15)
            .padding()
            .frame(height: 400) // Ограничиваем высоту календаря

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
            .padding(.top, 8)

            // Записи
            if displayedRecordings.isEmpty {
                emptyRecordingsView
            } else {
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
                .padding(.horizontal)
                .padding(.bottom)
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
        VStack(spacing: 16) {
            // Picker режима
            Picker("Режим", selection: $viewModel.currentRecordingMode) {
                Text("Обычная").tag("standard")
                Text("Real-time").tag("realtime")
                Text("Импорт").tag("import")
            }
            .pickerStyle(.segmented)
            .padding()

            // Active recording indicator
            if viewModel.isRecording || viewModel.isRealtimeActive {
                activeRecordingView
            }

            // Встречи из календаря
            UpcomingMeetingsSection()
                .environment(\.currentRecordingMode, viewModel.currentRecordingMode)

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
                        RecordingCard(
                            recording: recording,
                            onTap: {
                                selectedRecording = recording
                            },
                            onDelete: {
                                deleteRecording(recording)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .padding(.bottom, 100) // Место для floating кнопки
    }

    private var activeRecordingView: some View {
        VStack(spacing: 24) {
            FrequencyVisualizerView(level: viewModel.currentAudioLevel)
                .frame(height: 100)
                .padding(.horizontal)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isRealtimeActive ? Color.green : Color.pinkVibrant)
                        .frame(width: 12, height: 12)
                        .modifier(PulseAnimation())

                    Text("Идёт запись")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                if viewModel.isRealtimeActive {
                    Text("Real-time транскрипция")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(formatTime(viewModel.recordingDuration))
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)

                if let preset = viewModel.currentPreset {
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
        if viewModel.isRecording || viewModel.isRealtimeActive {
            Button {
                if viewModel.isRealtimeActive {
                    viewModel.showRealtimeRecordingSheet = true
                } else {
                    viewModel.showRecordingSheet = true
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.isRealtimeActive ? Color.green : Color.pinkVibrant)
                        .frame(width: 10, height: 10)
                        .modifier(PulseAnimation())

                    Image(systemName: viewModel.isRealtimeActive ? "text.badge.plus" : "waveform")
                        .font(.title2)

                    Text(formatTime(viewModel.recordingDuration))
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
                viewModel.handleButtonTap()
            } label: {
                HStack(spacing: 12) {
                    if viewModel.isConverting {
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
            .disabled(viewModel.isConverting)
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
