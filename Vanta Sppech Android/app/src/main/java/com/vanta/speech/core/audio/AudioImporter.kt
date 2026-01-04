package com.vanta.speech.core.audio

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.time.Duration
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Import audio files from external storage
 * Copies external audio files to app's Recordings directory
 */
@Singleton
class AudioImporter @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "AudioImporter"

        /**
         * Supported audio file extensions (Whisper-compatible)
         */
        val SUPPORTED_EXTENSIONS = listOf(
            "mp3",
            "m4a",
            "wav",
            "aiff",
            "ogg",
            "webm",
            "flac",
            "aac"
        )

        /**
         * MIME types for audio picker
         */
        val AUDIO_MIME_TYPES = arrayOf(
            "audio/mpeg",       // mp3
            "audio/mp4",        // m4a
            "audio/x-m4a",      // m4a alternate
            "audio/wav",        // wav
            "audio/x-wav",      // wav alternate
            "audio/aiff",       // aiff
            "audio/ogg",        // ogg
            "audio/webm",       // webm
            "audio/flac",       // flac
            "audio/aac",        // aac
            "audio/*"           // fallback
        )
    }

    /**
     * Result of audio import
     */
    data class ImportedAudio(
        val filePath: String,
        val duration: Duration,
        val originalFileName: String
    )

    /**
     * Errors that can occur during import
     */
    sealed class ImportError : Exception() {
        data object FileNotFound : ImportError() {
            private fun readResolve(): Any = FileNotFound
            override val message = "Файл не найден"
        }

        data object UnsupportedFormat : ImportError() {
            private fun readResolve(): Any = UnsupportedFormat
            override val message = "Неподдерживаемый формат аудио"
        }

        data object CopyFailed : ImportError() {
            private fun readResolve(): Any = CopyFailed
            override val message = "Не удалось скопировать файл"
        }

        data object CannotReadDuration : ImportError() {
            private fun readResolve(): Any = CannotReadDuration
            override val message = "Не удалось определить длительность аудио"
        }
    }

    private val recordingsDirectory: File
        get() {
            val dir = File(context.filesDir, "Recordings")
            if (!dir.exists()) {
                dir.mkdirs()
            }
            return dir
        }

    /**
     * Import audio file from URI
     * @param uri URI of the audio file (from SAF picker)
     * @return Information about the imported file
     */
    suspend fun importAudio(uri: Uri): ImportedAudio = withContext(Dispatchers.IO) {
        // Get original file name
        val originalFileName = getFileName(uri) ?: "unknown"
        val fileExtension = getFileExtension(originalFileName).lowercase()

        // Check if format is supported
        if (!SUPPORTED_EXTENSIONS.contains(fileExtension)) {
            throw ImportError.UnsupportedFormat
        }

        // Generate unique file name
        val timestamp = System.currentTimeMillis()
        val cleanFileName = originalFileName.substringBeforeLast(".")
        val newFileName = "imported_${timestamp}_$cleanFileName.$fileExtension"
        val destinationFile = File(recordingsDirectory, newFileName)

        // Copy file
        try {
            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                FileOutputStream(destinationFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: throw ImportError.FileNotFound
        } catch (e: ImportError) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy file: ${e.message}")
            throw ImportError.CopyFailed
        }

        // Get duration
        val duration = try {
            getAudioDuration(destinationFile)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read duration: ${e.message}")
            // Delete the copied file if we can't read it
            destinationFile.delete()
            throw ImportError.CannotReadDuration
        }

        Log.d(TAG, "Audio imported: $newFileName, duration: ${duration.seconds}s")

        ImportedAudio(
            filePath = destinationFile.absolutePath,
            duration = duration,
            originalFileName = cleanFileName
        )
    }

    /**
     * Get file name from URI
     */
    private fun getFileName(uri: Uri): String? {
        val cursor = context.contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    return it.getString(nameIndex)
                }
            }
        }
        // Fallback to path
        return uri.lastPathSegment
    }

    /**
     * Get file extension
     */
    private fun getFileExtension(fileName: String): String {
        return fileName.substringAfterLast(".", "")
    }

    /**
     * Get audio duration using MediaMetadataRetriever
     */
    private fun getAudioDuration(file: File): Duration {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?: throw ImportError.CannotReadDuration

            if (durationMs <= 0) {
                throw ImportError.CannotReadDuration
            }

            return Duration.ofMillis(durationMs)
        } finally {
            retriever.release()
        }
    }

    /**
     * Check if a file extension is supported
     */
    fun isFormatSupported(fileName: String): Boolean {
        val extension = getFileExtension(fileName).lowercase()
        return SUPPORTED_EXTENSIONS.contains(extension)
    }

    /**
     * Delete imported file (cleanup on cancel)
     */
    fun deleteImportedFile(filePath: String) {
        try {
            File(filePath).delete()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete file: ${e.message}")
        }
    }
}
