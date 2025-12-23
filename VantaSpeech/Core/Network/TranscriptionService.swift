import Foundation

actor TranscriptionService {
    private let baseURL: URL
    private let session: URLSession

    struct TranscriptionResult: Codable, Sendable {
        let transcription: String
        let summary: String
    }

    enum TranscriptionError: LocalizedError {
        case invalidURL
        case uploadFailed
        case invalidResponse
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid server URL"
            case .uploadFailed:
                return "Failed to upload audio file"
            case .invalidResponse:
                return "Invalid response from server"
            case .serverError(let message):
                return "Server error: \(message)"
            }
        }
    }

    init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for large files
        config.timeoutIntervalForResource = 600 // 10 minutes total
        self.session = URLSession(configuration: config)
    }

    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        let endpoint = baseURL.appendingPathComponent("transcribe")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioFileURL)
        let body = createMultipartBody(
            audioData: audioData,
            fileName: audioFileURL.lastPathComponent,
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

        let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        return result
    }

    private func createMultipartBody(audioData: Data, fileName: String, boundary: String) -> Data {
        var body = Data()

        let mimeType = getMimeType(for: fileName)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

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
        default:
            return "application/octet-stream"
        }
    }
}
