import Foundation

struct TranscriptionResult: Codable {
    let transcription: String
    let summary: String?
    let language: String?
    let duration: Double?
}

actor TranscriptionService {
    private var baseURL: String = ""

    func updateBaseURL(_ url: String) {
        baseURL = url.hasSuffix("/") ? url : url + "/"
    }

    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        guard !baseURL.isEmpty else {
            throw TranscriptionError.noServerConfigured
        }

        guard let url = URL(string: baseURL + "transcribe") else {
            throw TranscriptionError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600 // 10 minutes for large files

        let audioData = try Data(contentsOf: audioFileURL)
        let fileName = audioFileURL.lastPathComponent
        let mimeType = getMimeType(for: audioFileURL.pathExtension)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TranscriptionError.serverError(statusCode: httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        return result
    }

    private func getMimeType(for extension: String) -> String {
        switch `extension`.lowercased() {
        case "m4a": return "audio/mp4"
        case "ogg", "opus": return "audio/ogg"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        default: return "audio/*"
        }
    }
}

enum TranscriptionError: LocalizedError {
    case noServerConfigured
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .noServerConfigured:
            return "No server URL configured. Please set the server URL in Settings."
        case .invalidURL:
            return "Invalid server URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let statusCode):
            return "Server error: HTTP \(statusCode)"
        }
    }
}
