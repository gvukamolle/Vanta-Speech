import Foundation
import Combine

/// Менеджер для real-time транскрипции чанков
/// Управляет очередью чанков, показывает предпревью от локальной диктовки,
/// и заменяет на серверную транскрипцию после получения ответа
@MainActor
final class RealtimeTranscriptionManager: ObservableObject {

    // MARK: - Published Properties

    /// Массив параграфов (каждый чанк = один параграф)
    @Published private(set) var paragraphs: [Paragraph] = []

    /// Текущий промежуточный текст (от локальной диктовки, ещё не отправлен)
    @Published var currentInterimText: String = ""

    /// Количество чанков в очереди на обработку
    @Published private(set) var pendingChunksCount: Int = 0

    /// Текущий статус менеджера
    @Published private(set) var status: Status = .idle

    // MARK: - Types

    struct Paragraph: Identifiable {
        let id: UUID
        var text: String
        var previewText: String  // Предпревью от локальной диктовки
        let timestamp: Date
        let duration: TimeInterval
        var status: ParagraphStatus

        enum ParagraphStatus {
            case transcribing  // Отправлено на сервер, ждём ответ
            case completed     // Получен ответ от сервера
            case failed        // Ошибка транскрипции
        }

        /// Текст для отображения: серверный если готов, иначе предпревью
        var displayText: String {
            switch status {
            case .transcribing:
                return previewText.isEmpty ? "..." : previewText
            case .completed:
                return text
            case .failed:
                return "[Ошибка транскрипции]"
            }
        }
    }

    enum Status {
        case idle
        case processing
        case error(String)
    }

    // MARK: - Private Properties

    private let transcriptionService = TranscriptionService()
    private var chunkQueue: [ChunkItem] = []
    private var isProcessing = false
    private var currentTask: Task<Void, Never>?

    /// URL всех обработанных чанков (для последующего мержа в один файл)
    private var processedChunkURLs: [URL] = []

    /// Continuation для ожидания завершения всех чанков
    private var completionContinuations: [CheckedContinuation<Void, Never>] = []

    init() {
        cleanupOrphanedChunks()
    }

    private struct ChunkItem: Identifiable {
        let id: UUID
        let url: URL
        let duration: TimeInterval
        let timestamp: Date
        let previewText: String  // Текст от локальной диктовки
    }

    // MARK: - Public API

    /// Добавить чанк в очередь на транскрипцию
    /// - Parameters:
    ///   - url: URL аудиофайла
    ///   - duration: Длительность аудио
    ///   - previewText: Предварительный текст от локальной диктовки
    func enqueueChunk(url: URL, duration: TimeInterval, previewText: String) {
        let chunkId = UUID()
        let item = ChunkItem(
            id: chunkId,
            url: url,
            duration: duration,
            timestamp: Date(),
            previewText: previewText
        )
        chunkQueue.append(item)
        pendingChunksCount = chunkQueue.count

        // Добавляем параграф с предпревью
        let paragraph = Paragraph(
            id: chunkId,
            text: "",
            previewText: formatPreviewText(previewText),
            timestamp: item.timestamp,
            duration: duration,
            status: .transcribing
        )
        paragraphs.append(paragraph)

        // Очищаем текущий interim текст
        currentInterimText = ""

        debugLog("Chunk enqueued with preview: '\(previewText.prefix(30))...'", module: "RealtimeTranscriptionManager")

        processNextChunkIfNeeded()
    }

    /// Получить финальный накопленный текст (только успешные параграфы)
    func getFinalTranscription() -> String {
        return paragraphs
            .filter { $0.status == .completed }
            .map { formatFinalText($0.text) }
            .joined(separator: "\n\n")
    }

    /// Сброс состояния
    func reset() {
        currentTask?.cancel()
        chunkQueue.removeAll()
        paragraphs.removeAll()
        currentInterimText = ""
        status = .idle
        pendingChunksCount = 0
        isProcessing = false

        // Resume all continuations при reset чтобы избежать deadlock
        resumeAllContinuations()

        cleanupChunks()  // Очищаем временные файлы чанков
        debugLog("Reset", module: "RealtimeTranscriptionManager")
    }

    /// Ожидание завершения всех pending транскрипций
    func waitForCompletion() async {
        // Если очередь пуста и ничего не обрабатывается - сразу возвращаемся
        guard !chunkQueue.isEmpty || isProcessing else {
            debugLog("All chunks already processed", module: "RealtimeTranscriptionManager")
            return
        }

        // Ожидаем через continuation (без busy-wait)
        await withCheckedContinuation { continuation in
            self.completionContinuations.append(continuation)
        }
        debugLog("All chunks processed", module: "RealtimeTranscriptionManager")
    }

    /// Проверить есть ли еще чанки в обработке
    var hasProcessingChunks: Bool {
        !chunkQueue.isEmpty || isProcessing
    }

    /// Количество успешно обработанных параграфов
    var completedParagraphsCount: Int {
        paragraphs.filter { $0.status == .completed }.count
    }

    /// Получить URL всех обработанных чанков (для мержа в один файл)
    func getProcessedChunkURLs() -> [URL] {
        return processedChunkURLs
    }

    /// Очистить все временные файлы чанков
    func cleanupChunks() {
        let count = processedChunkURLs.count
        for url in processedChunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
        processedChunkURLs.removeAll()
        debugLog("Cleaned up \(count) chunk files", module: "RealtimeTranscriptionManager")
    }

    // MARK: - Private Methods

    private func processNextChunkIfNeeded() {
        guard !isProcessing, !chunkQueue.isEmpty else { return }

        isProcessing = true
        status = .processing

        let chunk = chunkQueue.removeFirst()
        pendingChunksCount = chunkQueue.count

        currentTask = Task {
            await processChunk(chunk)
            isProcessing = false

            // Продолжаем обработку если есть ещё чанки
            if !chunkQueue.isEmpty {
                processNextChunkIfNeeded()
            } else {
                status = .idle

                // Resume continuations если кто-то ожидает завершения
                resumeAllContinuations()
            }
        }
    }

    private func resumeAllContinuations() {
        guard !completionContinuations.isEmpty else { return }
        let continuations = completionContinuations
        completionContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func processChunk(_ chunk: ChunkItem) async {
        debugLog("Processing chunk: \(chunk.url.lastPathComponent)", module: "RealtimeTranscriptionManager")

        do {
            // Транскрибируем аудио через Whisper
            let result = try await transcriptionService.transcribeOnly(audioFileURL: chunk.url)

            // Форматируем результат: заглавная буква + точка
            let formattedResult = formatFinalText(result)

            // Обновляем параграф с серверным ответом
            if let index = paragraphs.firstIndex(where: { $0.id == chunk.id }) {
                paragraphs[index].text = formattedResult
                paragraphs[index].status = .completed
                debugLog("Chunk transcribed: '\(formattedResult.prefix(50))...'", module: "RealtimeTranscriptionManager")
            }

            // Сохраняем URL чанка для последующего мержа (НЕ удаляем файл!)
            processedChunkURLs.append(chunk.url)

        } catch {
            debugLog("Failed to transcribe chunk: \(error)", module: "RealtimeTranscriptionManager", level: .error)
            debugCaptureError(error, context: "Realtime chunk transcription")

            // Помечаем параграф как failed
            if let index = paragraphs.firstIndex(where: { $0.id == chunk.id }) {
                paragraphs[index].status = .failed
            }

            status = .error(error.localizedDescription)

            // Сохраняем URL даже при ошибке транскрипции (аудио всё равно валидное)
            processedChunkURLs.append(chunk.url)
        }
    }

    // MARK: - Text Formatting

    /// Форматирует предпревью текст (заглавная буква в начале)
    private func formatPreviewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return capitalizeFirstLetter(trimmed)
    }

    /// Форматирует финальный текст (заглавная буква + точка в конце)
    private func formatFinalText(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Заглавная буква в начале
        trimmed = capitalizeFirstLetter(trimmed)

        // Точка в конце если нет знака препинания
        if !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") && !trimmed.hasSuffix("?") {
            trimmed += "."
        }

        return trimmed
    }

    /// Делает первую букву заглавной
    private func capitalizeFirstLetter(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func cleanupOrphanedChunks() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let chunksPath = documentsPath
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("Chunks", isDirectory: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: chunksPath,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-3600)
        var removedCount = 0

        for file in contents {
            guard let values = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let creationDate = values.creationDate else { continue }
            guard creationDate < cutoffDate else { continue }

            if (try? FileManager.default.removeItem(at: file)) != nil {
                removedCount += 1
            }
        }

        if removedCount > 0 {
            debugLog("Cleaned up \(removedCount) orphaned chunk files", module: "RealtimeTranscriptionManager")
        }
    }
}
