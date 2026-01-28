import SwiftUI
import SwiftData

/// Боковая панель с деталями дня для iPad (выезжает справа)
/// Во всю высоту, без скруглений, с кастомным хедером
struct DayDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var coordinator: RecordingCoordinator
    @StateObject private var calendarManager = EASCalendarManager.shared
    
    let date: Date
    var onDismiss: () -> Void
    var onOpenRecording: ((Recording) -> Void)?
    
    @State private var showFileImporter = false
    @State private var showPresetPickerForImport = false
    @State private var importedAudioData: AudioImporter.ImportedAudio?
    @State private var isImporting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedEvent: EASCalendarEvent?
    
    private let calendar = Calendar.current
    private let audioImporter = AudioImporter()
    
    // MARK: - Computed Properties
    
    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private var weekdayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized
    }
    
    private var dayEvents: [EASCalendarEvent] {
        calendarManager.cachedEvents.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: date)
        }.sorted { $0.startTime < $1.startTime }
    }
    
    private var dayRecordings: [Recording] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { recording in
                recording.createdAt >= startOfDay && recording.createdAt < endOfDay
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        let recordings = (try? modelContext.fetch(descriptor)) ?? []
        
        // Deduplicate by ID to prevent display issues
        var seenIds = Set<UUID>()
        return recordings.filter { recording in
            if seenIds.contains(recording.id) {
                return false
            }
            seenIds.insert(recording.id)
            return true
        }
    }
    
    // Recordings linked to events
    private var linkedRecordings: [Recording] {
        dayRecordings.filter { $0.hasLinkedMeeting }
    }
    
    // Recordings without events
    private var unmatchedRecordings: [Recording] {
        dayRecordings.filter { !$0.hasLinkedMeeting }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Кастомный хедер (большой, с датой и кнопками)
                customHeader
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                Divider()
                
                // Контент
                ScrollView {
                    VStack(spacing: 20) {
                        // Секция: Встречи
                        if !dayEvents.isEmpty {
                            eventsSection
                        }
                        
                        // Секция: Связанные записи
                        if !linkedRecordings.isEmpty {
                            linkedRecordingsSection
                        }
                        
                        // Секция: Несвязанные записи
                        if !unmatchedRecordings.isEmpty {
                            unmatchedRecordingsSection
                        }
                        
                        // Пустое состояние
                        if dayEvents.isEmpty && dayRecordings.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
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
                ImportPresetPickerSheetForDay(
                    audioData: audioData,
                    date: date,
                    onSelect: { preset in
                        finalizeImport(audioData: audioData, preset: preset)
                        showPresetPickerForImport = false
                    },
                    onCancel: {
                        cancelImport()
                        showPresetPickerForImport = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailSheet(event: event)
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
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Custom Header
    
    private var customHeader: some View {
        VStack(spacing: 16) {
            // Верхняя строка с кнопками
            HStack {
                // Кнопка импорта (слева)
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(Color.pinkVibrant)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                // Кнопка закрыть (справа)
                Button {
                    onDismiss()
                } label: {
                    Text("Закрыть")
                        .font(.headline)
                        .foregroundStyle(Color.pinkVibrant)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            
            // Дата (большая, по центру)
            VStack(spacing: 4) {
                Text(weekdayTitle)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Text(dateTitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Events Section
    
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Встречи")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            LazyVStack(spacing: 12) {
                ForEach(dayEvents) { event in
                    Button {
                        selectedEvent = event
                    } label: {
                        DayEventRow(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Linked Recordings Section
    
    private var linkedRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Записи")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            LazyVStack(spacing: 12) {
                ForEach(linkedRecordings) { recording in
                    RecordingCard(
                        recording: recording,
                        onTap: {
                            onDismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onOpenRecording?(recording)
                            }
                        },
                        onDelete: {
                            deleteRecording(recording)
                        },
                        onGenerateSummary: recording.isTranscribed && recording.summaryText == nil ? {
                            Task {
                                await coordinator.generateSummary(for: recording)
                            }
                        } : nil
                    )
                }
            }
        }
    }
    
    // MARK: - Unmatched Recordings Section
    
    private var unmatchedRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Без встречи")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            LazyVStack(spacing: 12) {
                ForEach(unmatchedRecordings) { recording in
                    RecordingCard(
                        recording: recording,
                        onTap: {
                            onDismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onOpenRecording?(recording)
                            }
                        },
                        onDelete: {
                            deleteRecording(recording)
                        },
                        onGenerateSummary: recording.isTranscribed && recording.summaryText == nil ? {
                            Task {
                                await coordinator.generateSummary(for: recording)
                            }
                        } : nil
                    )
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            
            Text("Нет событий и записей")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("В этот день нет запланированных встреч и созданных записей")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Actions
    
    private func deleteRecording(_ recording: Recording) {
        if FileManager.default.fileExists(atPath: recording.audioFileURL) {
            try? FileManager.default.removeItem(atPath: recording.audioFileURL)
        }
        modelContext.delete(recording)
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            isImporting = true
            
            Task {
                do {
                    let audioData = try await audioImporter.importAudio(from: url)
                    importedAudioData = audioData
                    isImporting = false
                    showPresetPickerForImport = true
                } catch {
                    isImporting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
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
        
        recording.createdAt = date
        
        if let suggestedMeeting = calendarManager.findMostProbableMeeting(for: recording) {
            recording.linkToMeeting(suggestedMeeting)
        }
        
        modelContext.insert(recording)
        
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        importedAudioData = nil
    }
    
    private func cancelImport() {
        if let audioData = importedAudioData {
            try? FileManager.default.removeItem(at: audioData.url)
        }
        importedAudioData = nil
    }
}

// MARK: - Day Event Row

private struct DayEventRow: View {
    let event: EASCalendarEvent
    
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
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formatTime(event.startTime)) - \(formatTime(event.endTime))")
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
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .vantaBlueGlassCard(cornerRadius: 16, shadowRadius: 0, tintOpacity: 0.12)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}



// MARK: - Import Preset Picker Sheet

private struct ImportPresetPickerSheetForDay: View {
    let audioData: AudioImporter.ImportedAudio
    let date: Date
    let onSelect: (RecordingPreset) -> Void
    let onCancel: () -> Void
    
    @StateObject private var presetSettings = PresetSettings.shared
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(audioData.originalFileName)
                                .font(.headline)
                            Text(formatDuration(audioData.duration))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Импортированный файл")
                }
                
                Section {
                    ForEach(presetSettings.enabledPresets, id: \.rawValue) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            Label {
                                Text(preset.displayName)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: preset.icon)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text("Выберите тип записи")
                } footer: {
                    Text("Тип записи влияет на формат транскрипции и саммари")
                }
            }
            .navigationTitle("Импорт аудио")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onCancel()
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d ч %02d мин", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%d мин %02d сек", minutes, seconds)
        } else {
            return String(format: "%d сек", seconds)
        }
    }
}

// MARK: - Preview

#Preview {
    DayDetailSheet(
        date: Date(),
        onDismiss: {}
    )
    .environmentObject(RecordingCoordinator.shared)
    .modelContainer(for: Recording.self, inMemory: true)
}
