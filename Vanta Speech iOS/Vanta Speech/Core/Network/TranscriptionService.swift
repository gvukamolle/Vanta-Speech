import Foundation

/// Service for transcription and summarization using OpenAI-compatible API
actor TranscriptionService {
    // MARK: - Configuration (from Env)

    private static var baseURL: String { Env.transcriptionBaseURL }
    private static var apiKey: String { Env.transcriptionAPIKey }

    // Models
    private static var transcriptionModel: String { Env.transcriptionModel }
    private static var summaryModel: String { Env.summaryModel }

    private let session: URLSession

    struct TranscriptionResult: Sendable {
        let transcription: String
        let summary: String?
        let generatedTitle: String?
    }

    /// Progress stages for transcription with callbacks
    enum TranscriptionStage: Sendable {
        case transcribing
        case transcriptionCompleted(String)
        case generatingSummary
        case summaryCompleted(String)
        case generatingTitle
        case completed(TranscriptionResult)
        case error(Error)
    }

    enum TranscriptionError: LocalizedError {
        case invalidURL
        case uploadFailed
        case invalidResponse
        case serverError(String)
        case transcriptionFailed
        case summaryFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Неверный URL сервера"
            case .uploadFailed:
                return "Не удалось загрузить аудио файл"
            case .invalidResponse:
                return "Неверный ответ от сервера"
            case .serverError(let message):
                return "Ошибка сервера: \(message)"
            case .transcriptionFailed:
                return "Не удалось транскрибировать аудио"
            case .summaryFailed:
                return "Не удалось создать саммари"
            case .cancelled:
                return "Операция отменена"
            }
        }
    }

    /// Общая структура для парсинга ответов ChatCompletion API
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 1800 // 30 minutes for large files
        config.timeoutIntervalForResource = 3600 // 60 minutes total
        self.session = URLSession(configuration: config)
    }

    // Legacy init for compatibility
    init(baseURL: URL) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 1800
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config)
    }

    // MARK: - Main API

    /// Transcribe audio and generate summary with preset-specific system prompt
    /// - Parameters:
    ///   - audioFileURL: URL of the audio file to transcribe
    ///   - preset: The meeting type preset to use for summarization (defaults to projectMeeting)
    /// - Returns: TranscriptionResult with transcription, summary, and generated title
    func transcribe(audioFileURL: URL, preset: RecordingPreset = .projectMeeting) async throws -> TranscriptionResult {
        // Check for debug mode with fake transcriptions
        let useFake = await MainActor.run {
            DebugManager.shared.isDebugModeEnabled &&
            DebugManager.shared.isFakeTranscriptionEnabled
        }

        if useFake {
            // Simulate network delay for realism
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            return TranscriptionResult(
                transcription: DebugManager.fakeTranscription,
                summary: DebugManager.fakeSummary,
                generatedTitle: DebugManager.fakeTitle
            )
        }

        try Task.checkCancellation()

        // Step 1: Transcribe audio using Whisper
        let transcription = try await transcribeAudio(fileURL: audioFileURL)

        try Task.checkCancellation()

        // Step 2: Generate summary using LLM with preset-specific prompt
        let summary = try? await generateSummary(text: transcription, preset: preset)

        try Task.checkCancellation()

        // Step 3: Generate title from summary (if summary exists)
        var generatedTitle: String? = nil
        if let summaryText = summary {
            generatedTitle = try? await generateTitle(from: summaryText)
        }

        try Task.checkCancellation()

        return TranscriptionResult(transcription: transcription, summary: summary, generatedTitle: generatedTitle)
    }

    /// Transcribe audio with progress callbacks for incremental UI updates
    /// - Parameters:
    ///   - audioFileURL: URL of the audio file to transcribe
    ///   - preset: The meeting type preset to use for summarization
    ///   - onProgress: Callback for each stage of the process
    /// - Returns: TranscriptionResult with transcription, summary, and generated title
    func transcribeWithProgress(
        audioFileURL: URL,
        preset: RecordingPreset = .projectMeeting,
        onProgress: @escaping @Sendable (TranscriptionStage) async -> Void
    ) async throws -> TranscriptionResult {
        // Check for debug mode with fake transcriptions
        let useFake = await MainActor.run {
            DebugManager.shared.isDebugModeEnabled &&
            DebugManager.shared.isFakeTranscriptionEnabled
        }

        if useFake {
            // Simulate the full flow with fake data
            await onProgress(.transcribing)
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await onProgress(.transcriptionCompleted(DebugManager.fakeTranscription))

            await onProgress(.generatingSummary)
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await onProgress(.summaryCompleted(DebugManager.fakeSummary))

            await onProgress(.generatingTitle)
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            let result = TranscriptionResult(
                transcription: DebugManager.fakeTranscription,
                summary: DebugManager.fakeSummary,
                generatedTitle: DebugManager.fakeTitle
            )
            await onProgress(.completed(result))
            return result
        }

        // Step 1: Notify transcription starting
        await onProgress(.transcribing)
        try Task.checkCancellation()

        // Step 2: Transcribe audio using Whisper
        let transcription: String
        do {
            transcription = try await transcribeAudio(fileURL: audioFileURL)
            try Task.checkCancellation()
            await onProgress(.transcriptionCompleted(transcription))
        } catch {
            if !(error is CancellationError) {
                await onProgress(.error(error))
            }
            throw error
        }

        // Step 3: Generate summary using LLM with preset-specific prompt
        await onProgress(.generatingSummary)
        try Task.checkCancellation()
        var summary: String? = nil
        do {
            summary = try await generateSummary(text: transcription, preset: preset)
            try Task.checkCancellation()
            if let summaryText = summary {
                await onProgress(.summaryCompleted(summaryText))
            }
        } catch {
            // Summary failed but transcription succeeded - don't throw, just continue
            if error is CancellationError {
                throw error
            }
            await onProgress(.error(error))
        }

        // Step 4: Generate title from summary (if summary exists)
        var generatedTitle: String? = nil
        if let summaryText = summary {
            await onProgress(.generatingTitle)
            try Task.checkCancellation()
            generatedTitle = try? await generateTitle(from: summaryText)
        }

        try Task.checkCancellation()

        let result = TranscriptionResult(transcription: transcription, summary: summary, generatedTitle: generatedTitle)
        await onProgress(.completed(result))

        return result
    }

    // MARK: - Realtime Transcription API

    /// Транскрибировать аудио без генерации саммари
    /// Используется для real-time режима, где саммари генерируется в конце
    func transcribeOnly(audioFileURL: URL) async throws -> String {
        return try await transcribeAudio(fileURL: audioFileURL)
    }

    /// Сгенерировать саммари и заголовок для готового текста
    /// Используется в конце real-time сессии
    func summarize(text: String, preset: RecordingPreset) async throws -> (summary: String, title: String?) {
        let summary = try await generateSummary(text: text, preset: preset)
        let title = try? await generateTitle(from: summary)
        return (summary, title)
    }

    // MARK: - Whisper Transcription

    private func transcribeAudio(fileURL: URL) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/audio/transcriptions") else {
            throw TranscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1800 // 30 minutes for large audio files
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.doubleValue ?? 0
        let fileSizeMB = fileSizeBytes / (1024 * 1024)
        debugLog("Uploading audio: \(fileURL.lastPathComponent), size: \(String(format: "%.2f", fileSizeMB)) MB", module: "TranscriptionService", level: .info)

        let bodyFileURL = try createTranscriptionBodyFile(
            audioFileURL: fileURL,
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        if let bodySize = (try? FileManager.default.attributesOfItem(atPath: bodyFileURL.path)[.size] as? NSNumber)?.intValue {
            request.setValue(String(bodySize), forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await session.upload(for: request, fromFile: bodyFileURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError(errorMessage)
        }

        // Parse response - OpenAI returns {"text": "..."}
        struct WhisperResponse: Decodable {
            let text: String
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }

    private func createTranscriptionBodyFile(audioFileURL: URL, boundary: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription_upload_\(UUID().uuidString)")

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: tempURL)
        defer { try? output.close() }

        let fileName = audioFileURL.lastPathComponent
        let mimeType = getMimeType(for: fileName)

        try writeString("--\(boundary)\r\n", to: output)
        try writeString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n", to: output)
        try writeString("Content-Type: \(mimeType)\r\n\r\n", to: output)

        let input = try FileHandle(forReadingFrom: audioFileURL)
        defer { try? input.close() }

        while true {
            let data = try input.read(upToCount: 1_048_576)
            guard let data, !data.isEmpty else { break }
            try output.write(contentsOf: data)
        }

        try writeString("\r\n", to: output)

        // Add model
        try writeString("--\(boundary)\r\n", to: output)
        try writeString("Content-Disposition: form-data; name=\"model\"\r\n\r\n", to: output)
        try writeString("\(Self.transcriptionModel)\r\n", to: output)

        // Add language hint (Russian)
        try writeString("--\(boundary)\r\n", to: output)
        try writeString("Content-Disposition: form-data; name=\"language\"\r\n\r\n", to: output)
        try writeString("ru\r\n", to: output)

        // Close boundary
        try writeString("--\(boundary)--\r\n", to: output)

        return tempURL
    }

    private func writeString(_ string: String, to handle: FileHandle) throws {
        if let data = string.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    // MARK: - Summary Generation

    private func generateSummary(text: String, preset: RecordingPreset) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/chat/completions") else {
            throw TranscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1800 // 30 minutes for large summaries
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": Self.summaryModel,
            "messages": [
                ["role": "system", "content": preset.systemPrompt],
                ["role": "user", "content": "Транскрипция:\n\(text)"]
            ],
            "temperature": 0.3,
            "max_tokens": 4000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError(errorMessage)
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = result.choices.first?.message.content else {
            throw TranscriptionError.summaryFailed
        }

        return content
    }

    // MARK: - Title Generation

    /// Generate a short title from the summary text
    /// - Parameter summary: The summary text to generate a title from
    /// - Returns: A short title (5-7 words)
    private func generateTitle(from summary: String) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/chat/completions") else {
            throw TranscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // 2 minutes for title generation
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        На основе саммари встречи создай короткий заголовок (максимум 5-7 слов).
        Заголовок должен отражать главную тему или цель встречи.
        Отвечай ТОЛЬКО заголовком, без кавычек и дополнительного текста.

        Саммари:
        \(String(summary.prefix(1500)))
        """

        let requestBody: [String: Any] = [
            "model": Self.summaryModel,
            "messages": [
                ["role": "system", "content": "Ты создаёшь краткие заголовки для записей встреч. Отвечай только заголовком на русском языке."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 50
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.serverError(errorMessage)
        }

        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let title = result.choices.first?.message.content else {
            throw TranscriptionError.summaryFailed
        }

        // Clean up the title
        return title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: - Helpers

    private func getMimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "m4a":
            return "audio/m4a"
        case "ogg":
            return "audio/ogg"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        case "flac":
            return "audio/flac"
        default:
            return "application/octet-stream"
        }
    }
}
