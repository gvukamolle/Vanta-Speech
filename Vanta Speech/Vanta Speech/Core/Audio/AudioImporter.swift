import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Импортер аудиофайлов
/// Копирует внешние аудиофайлы в папку Recordings приложения
actor AudioImporter {

    // MARK: - Types

    struct ImportedAudio {
        let url: URL
        let duration: TimeInterval
        let originalFileName: String
    }

    enum ImportError: LocalizedError {
        case fileNotFound
        case unsupportedFormat
        case copyFailed
        case cannotReadDuration

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Файл не найден"
            case .unsupportedFormat:
                return "Неподдерживаемый формат аудио"
            case .copyFailed:
                return "Не удалось скопировать файл"
            case .cannotReadDuration:
                return "Не удалось определить длительность аудио"
            }
        }
    }

    // MARK: - Supported Formats

    /// Поддерживаемые форматы аудио (совместимые с Whisper)
    static let supportedTypes: [UTType] = [
        .mp3,
        .mpeg4Audio,  // m4a
        .wav,
        .aiff,
        UTType(filenameExtension: "ogg") ?? .audio,
        UTType(filenameExtension: "webm") ?? .audio,
        UTType(filenameExtension: "flac") ?? .audio
    ]

    /// Расширения файлов для отображения в picker
    static let supportedExtensions = ["mp3", "m4a", "wav", "aiff", "ogg", "webm", "flac"]

    // MARK: - Private Properties

    private let fileManager = FileManager.default

    private var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)

        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try? fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }

        return recordingsPath
    }

    // MARK: - Public Methods

    /// Импортировать аудиофайл
    /// - Parameter sourceURL: URL исходного файла (из fileImporter)
    /// - Returns: Информация об импортированном файле
    func importAudio(from sourceURL: URL) async throws -> ImportedAudio {
        // Проверяем доступ к файлу (security-scoped resource)
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ImportError.fileNotFound
        }

        // Проверяем расширение файла
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(fileExtension) else {
            throw ImportError.unsupportedFormat
        }

        // Генерируем уникальное имя файла
        let originalFileName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Date().timeIntervalSince1970
        let newFileName = "imported_\(Int(timestamp))_\(originalFileName).\(fileExtension)"
        let destinationURL = recordingsDirectory.appendingPathComponent(newFileName)

        // Копируем файл
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            debugLog("Failed to copy file: \(error)", module: "AudioImporter", level: .error)
            throw ImportError.copyFailed
        }

        // Получаем длительность аудио
        let duration = try await getAudioDuration(url: destinationURL)

        debugLog("Audio imported: \(newFileName), duration: \(duration)s", module: "AudioImporter")

        return ImportedAudio(
            url: destinationURL,
            duration: duration,
            originalFileName: originalFileName
        )
    }

    // MARK: - Private Methods

    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)

            guard seconds.isFinite && seconds > 0 else {
                throw ImportError.cannotReadDuration
            }

            return seconds
        } catch {
            debugLog("Failed to read duration: \(error)", module: "AudioImporter", level: .error)
            throw ImportError.cannotReadDuration
        }
    }
}
