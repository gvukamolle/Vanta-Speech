import Foundation
import AVFoundation

// MARK: - Audio Quality

/// Audio quality settings for OGG/Opus encoding
enum AudioQuality: String, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var bitrate: String {
        switch self {
        case .low: return "64k"
        case .medium: return "96k"
        case .high: return "128k"
        }
    }

    var displayName: String {
        switch self {
        case .low: return "Низкое"
        case .medium: return "Среднее"
        case .high: return "Высокое"
        }
    }

    var description: String {
        switch self {
        case .low: return "64 кбит/с — Меньший размер"
        case .medium: return "96 кбит/с — Баланс"
        case .high: return "128 кбит/с — Лучшее качество"
        }
    }
}

// MARK: - Audio Converter

/// Converts audio files to OGG/Opus format
/// NOTE: FFmpegKit временно отключен из-за несовместимости с iOS 26 Simulator.
/// Whisper поддерживает M4A напрямую, поэтому конвертация пока не критична.
/// TODO: Включить FFmpegKit когда появится совместимая версия для iOS 26.
actor AudioConverter {

    enum ConversionError: LocalizedError {
        case inputFileNotFound
        case conversionFailed(String)
        case ffmpegNotAvailable
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .inputFileNotFound:
                return "Входной аудио файл не найден"
            case .conversionFailed(let reason):
                return "Ошибка конвертации: \(reason)"
            case .ffmpegNotAvailable:
                return "FFmpeg недоступен"
            case .invalidOutput:
                return "Конвертация создала некорректный файл"
            }
        }
    }

    private let fileManager = FileManager.default
    private let quality: AudioQuality

    init(quality: AudioQuality = .low) {
        self.quality = quality
    }

    /// Convert M4A/AAC audio file to OGG/Opus format
    /// - Parameter inputURL: URL of the source audio file (M4A, WAV, MP3, etc.)
    /// - Returns: URL of the converted file (currently returns input as-is)
    func convertToOGG(inputURL: URL) async throws -> URL {
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw ConversionError.inputFileNotFound
        }

        // TODO: FFmpegKit временно отключен — возвращаем исходный файл
        // Whisper поддерживает M4A, так что это работает
        debugLog("FFmpeg disabled — using original M4A file", module: "AudioConverter")
        debugLog("File: \(inputURL.lastPathComponent)", module: "AudioConverter")

        return inputURL

        /* FFmpegKit код для будущего использования:
        let outputURL = inputURL
            .deletingPathExtension()
            .appendingPathExtension("ogg")

        // Remove existing output file if exists
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        // FFmpeg command for OGG/Opus conversion
        let command = buildFFmpegCommand(input: inputURL.path, output: outputURL.path)

        print("[AudioConverter] Starting conversion: \(inputURL.lastPathComponent) → OGG")
        print("[AudioConverter] Command: ffmpeg \(command)")

        let success = await executeFFmpegCommand(command)

        guard success else {
            throw ConversionError.conversionFailed("FFmpeg command failed")
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw ConversionError.invalidOutput
        }

        // Verify output file has content
        let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
            throw ConversionError.invalidOutput
        }

        print("[AudioConverter] Conversion successful: \(Self.formatFileSize(fileSize))")

        return outputURL
        */
    }

    /// Convert and optionally delete the source file
    func convertToOGG(inputURL: URL, deleteSource: Bool) async throws -> URL {
        let outputURL = try await convertToOGG(inputURL: inputURL)

        // Don't delete source when FFmpeg is disabled
        // if deleteSource {
        //     try? fileManager.removeItem(at: inputURL)
        //     print("[AudioConverter] Source file deleted: \(inputURL.lastPathComponent)")
        // }

        return outputURL
    }

    private func buildFFmpegCommand(input: String, output: String) -> String {
        // FFmpeg command optimized for voice/meeting recordings
        // -i: input file
        // -c:a libopus: use Opus codec
        // -b:a: bitrate
        // -vbr on: variable bitrate for better quality
        // -compression_level 10: max compression efficiency
        // -application voip: optimized for voice (meetings)
        // -ar 48000: sample rate (required for Opus)
        // -ac 1: mono (voice doesn't need stereo)
        // -y: overwrite output
        return "-i \"\(input)\" -c:a libopus -b:a \(quality.bitrate) -vbr on -compression_level 10 -application voip -ar 48000 -ac 1 -y \"\(output)\""
    }

    /* FFmpegKit execute — disabled
    private func executeFFmpegCommand(_ command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            FFmpegKit.executeAsync(command) { session in
                guard let session = session else {
                    print("[AudioConverter] FFmpeg session is nil")
                    continuation.resume(returning: false)
                    return
                }

                let returnCode = session.getReturnCode()

                if ReturnCode.isSuccess(returnCode) {
                    print("[AudioConverter] FFmpeg completed successfully")
                    continuation.resume(returning: true)
                } else if ReturnCode.isCancel(returnCode) {
                    print("[AudioConverter] FFmpeg was cancelled")
                    continuation.resume(returning: false)
                } else {
                    let output = session.getOutput() ?? "No output"
                    print("[AudioConverter] FFmpeg failed with code \(returnCode?.getValue() ?? -1)")
                    print("[AudioConverter] Output: \(output)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    */
}

// MARK: - Convenience Extensions

extension AudioConverter {

    /// Get estimated output file size for a given duration
    func estimatedFileSize(durationSeconds: TimeInterval) -> Int64 {
        let bitrateKbps: Double
        switch quality {
        case .low: bitrateKbps = 64
        case .medium: bitrateKbps = 96
        case .high: bitrateKbps = 128
        }

        // Size in bytes = (bitrate in kbps * duration in seconds * 1000) / 8
        return Int64((bitrateKbps * durationSeconds * 1000) / 8)
    }

    /// Format file size for display
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
