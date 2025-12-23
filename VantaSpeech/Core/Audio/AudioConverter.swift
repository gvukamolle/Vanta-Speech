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
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var description: String {
        switch self {
        case .low: return "64 kbps - Smaller files"
        case .medium: return "96 kbps - Balanced"
        case .high: return "128 kbps - Best quality"
        }
    }
}

// MARK: - Audio Converter

/// Converts audio files to OGG/Opus format using FFmpegKit
/// iOS does not natively support OGG recording, so we record in M4A and convert
actor AudioConverter {

    enum ConversionError: LocalizedError {
        case inputFileNotFound
        case conversionFailed(String)
        case ffmpegNotAvailable
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .inputFileNotFound:
                return "Input audio file not found"
            case .conversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            case .ffmpegNotAvailable:
                return "FFmpeg is not available"
            case .invalidOutput:
                return "Conversion produced invalid output"
            }
        }
    }

    private let fileManager = FileManager.default
    private let quality: AudioQuality

    init(quality: AudioQuality = .high) {
        self.quality = quality
    }

    /// Convert M4A/AAC audio file to OGG/Opus format
    /// - Parameter inputURL: URL of the source audio file (M4A, WAV, MP3, etc.)
    /// - Returns: URL of the converted OGG file
    func convertToOGG(inputURL: URL) async throws -> URL {
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw ConversionError.inputFileNotFound
        }

        let outputURL = inputURL
            .deletingPathExtension()
            .appendingPathExtension("ogg")

        // Remove existing output file if exists
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        // FFmpeg command for OGG/Opus conversion
        // -i: input file
        // -c:a libopus: use Opus codec
        // -b:a: bitrate
        // -vbr on: variable bitrate for better quality
        // -compression_level 10: max compression efficiency
        // -application voip: optimized for voice (meetings)
        let command = buildFFmpegCommand(input: inputURL.path, output: outputURL.path)

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

        return outputURL
    }

    /// Convert and optionally delete the source file
    func convertToOGG(inputURL: URL, deleteSource: Bool) async throws -> URL {
        let outputURL = try await convertToOGG(inputURL: inputURL)

        if deleteSource {
            try? fileManager.removeItem(at: inputURL)
        }

        return outputURL
    }

    private func buildFFmpegCommand(input: String, output: String) -> String {
        // FFmpeg command optimized for voice/meeting recordings
        return """
        -i "\(input)" \
        -c:a libopus \
        -b:a \(quality.bitrate) \
        -vbr on \
        -compression_level 10 \
        -application voip \
        -ar 48000 \
        -ac 1 \
        -y \
        "\(output)"
        """
    }

    private func executeFFmpegCommand(_ command: String) async -> Bool {
        // This will be implemented with FFmpegKit
        // For now, using a bridge to FFmpegKit
        return await FFmpegBridge.execute(command: command)
    }
}

// MARK: - FFmpeg Bridge

/// Bridge to FFmpegKit library
/// FFmpegKit must be added as a dependency via SPM or CocoaPods
enum FFmpegBridge {

    /// Execute FFmpeg command
    /// Returns true if successful, false otherwise
    static func execute(command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            // FFmpegKit execution
            // Import: import ffmpegkit
            //
            // FFmpegKit.executeAsync(command) { session in
            //     guard let session = session else {
            //         continuation.resume(returning: false)
            //         return
            //     }
            //     let returnCode = session.getReturnCode()
            //     continuation.resume(returning: ReturnCode.isSuccess(returnCode))
            // }

            // Placeholder implementation - replace with actual FFmpegKit call
            #if canImport(ffmpegkit)
            FFmpegKit.executeAsync(command) { session in
                guard let session = session else {
                    continuation.resume(returning: false)
                    return
                }
                let returnCode = session.getReturnCode()
                continuation.resume(returning: ReturnCode.isSuccess(returnCode))
            }
            #else
            // Fallback for development/testing without FFmpegKit
            print("[AudioConverter] FFmpegKit not available. Command: \(command)")
            continuation.resume(returning: false)
            #endif
        }
    }

    /// Check if FFmpegKit is available
    static var isAvailable: Bool {
        #if canImport(ffmpegkit)
        return true
        #else
        return false
        #endif
    }
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
