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
            }
        }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for large files
        config.timeoutIntervalForResource = 600 // 10 minutes total
        self.session = URLSession(configuration: config)
    }

    // Legacy init for compatibility
    init(baseURL: URL) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
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

        // Step 1: Transcribe audio using Whisper
        let transcription = try await transcribeAudio(fileURL: audioFileURL)

        // Step 2: Generate summary using LLM with preset-specific prompt
        let summary = try? await generateSummary(text: transcription, preset: preset)

        // Step 3: Generate title from summary (if summary exists)
        var generatedTitle: String? = nil
        if let summaryText = summary {
            generatedTitle = try? await generateTitle(from: summaryText)
        }

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

        // Step 2: Transcribe audio using Whisper
        let transcription: String
        do {
            transcription = try await transcribeAudio(fileURL: audioFileURL)
            await onProgress(.transcriptionCompleted(transcription))
        } catch {
            await onProgress(.error(error))
            throw error
        }

        // Step 3: Generate summary using LLM with preset-specific prompt
        await onProgress(.generatingSummary)
        var summary: String? = nil
        do {
            summary = try await generateSummary(text: transcription, preset: preset)
            if let summaryText = summary {
                await onProgress(.summaryCompleted(summaryText))
            }
        } catch {
            // Summary failed but transcription succeeded - don't throw, just continue
            await onProgress(.error(error))
        }

        // Step 4: Generate title from summary (if summary exists)
        var generatedTitle: String? = nil
        if let summaryText = summary {
            await onProgress(.generatingTitle)
            generatedTitle = try? await generateTitle(from: summaryText)
        }

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
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let body = createTranscriptionBody(
            audioData: audioData,
            fileName: fileURL.lastPathComponent,
            boundary: boundary
        )
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

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

    private func createTranscriptionBody(audioData: Data, fileName: String, boundary: String) -> Data {
        var body = Data()

        // Add file
        let mimeType = getMimeType(for: fileName)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Self.transcriptionModel)\r\n".data(using: .utf8)!)

        // Add language hint (Russian)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("ru\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    // MARK: - Summary Generation

    private func generateSummary(text: String, preset: RecordingPreset) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/chat/completions") else {
            throw TranscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": Self.summaryModel,
            "messages": [
                ["role": "system", "content": preset.systemPrompt],
                ["role": "user", "content": "Транскрипция:\n\(text)"]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
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

        // Parse ChatCompletion response
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
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

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
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
