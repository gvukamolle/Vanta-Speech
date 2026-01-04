package com.vanta.speech.core.audio

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.time.Duration
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Utility class to merge two audio files into one
 * Used for recording continuation feature
 */
@Singleton
class AudioMerger @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "AudioMerger"
        private const val BUFFER_SIZE = 1024 * 1024 // 1MB buffer
    }

    data class MergeResult(
        val filePath: String,
        val duration: Duration
    )

    /**
     * Merge two audio files into one
     * @param firstFilePath Path to the first (original) audio file
     * @param secondFilePath Path to the second (new) audio file
     * @param outputFilePath Path for the merged output file (optional, will overwrite first if null)
     * @param deleteSecondFile Whether to delete the second file after merging
     * @return MergeResult with the output file path and total duration
     */
    suspend fun mergeAudioFiles(
        firstFilePath: String,
        secondFilePath: String,
        outputFilePath: String? = null,
        deleteSecondFile: Boolean = true
    ): Result<MergeResult> = withContext(Dispatchers.IO) {
        runCatching {
            val firstFile = File(firstFilePath)
            val secondFile = File(secondFilePath)

            if (!firstFile.exists()) {
                throw IllegalArgumentException("First file does not exist: $firstFilePath")
            }
            if (!secondFile.exists()) {
                throw IllegalArgumentException("Second file does not exist: $secondFilePath")
            }

            // Create temp output file
            val tempOutput = File(context.cacheDir, "merged_${System.currentTimeMillis()}.m4a")

            try {
                // Extract and merge audio tracks
                val totalDuration = mergeWithMediaMuxer(firstFile, secondFile, tempOutput)

                // Determine final output path
                val finalPath = outputFilePath ?: firstFilePath

                // Replace original file with merged file
                if (finalPath == firstFilePath) {
                    firstFile.delete()
                }
                tempOutput.copyTo(File(finalPath), overwrite = true)
                tempOutput.delete()

                // Delete second file if requested
                if (deleteSecondFile) {
                    secondFile.delete()
                }

                Log.d(TAG, "Audio files merged successfully, duration: ${totalDuration.seconds}s")

                MergeResult(
                    filePath = finalPath,
                    duration = totalDuration
                )
            } catch (e: Exception) {
                tempOutput.delete()
                throw e
            }
        }
    }

    private fun mergeWithMediaMuxer(
        firstFile: File,
        secondFile: File,
        outputFile: File
    ): Duration {
        var muxer: MediaMuxer? = null
        var extractor1: MediaExtractor? = null
        var extractor2: MediaExtractor? = null

        try {
            // Setup first extractor
            extractor1 = MediaExtractor().apply {
                setDataSource(firstFile.absolutePath)
            }
            val audioTrackIndex1 = findAudioTrack(extractor1)
            if (audioTrackIndex1 < 0) {
                throw IllegalStateException("No audio track found in first file")
            }
            extractor1.selectTrack(audioTrackIndex1)
            val format1 = extractor1.getTrackFormat(audioTrackIndex1)

            // Setup second extractor
            extractor2 = MediaExtractor().apply {
                setDataSource(secondFile.absolutePath)
            }
            val audioTrackIndex2 = findAudioTrack(extractor2)
            if (audioTrackIndex2 < 0) {
                throw IllegalStateException("No audio track found in second file")
            }
            extractor2.selectTrack(audioTrackIndex2)

            // Get durations
            val duration1 = format1.getLong(MediaFormat.KEY_DURATION)

            // Setup muxer
            muxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outputTrackIndex = muxer.addTrack(format1)
            muxer.start()

            val buffer = ByteBuffer.allocate(BUFFER_SIZE)
            val bufferInfo = MediaCodec.BufferInfo()

            // Write first file
            while (true) {
                val sampleSize = extractor1.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                bufferInfo.offset = 0
                bufferInfo.size = sampleSize
                bufferInfo.presentationTimeUs = extractor1.sampleTime
                bufferInfo.flags = extractor1.sampleFlags

                muxer.writeSampleData(outputTrackIndex, buffer, bufferInfo)
                extractor1.advance()
            }

            // Write second file with time offset
            var maxPresentationTime = duration1
            while (true) {
                val sampleSize = extractor2.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                bufferInfo.offset = 0
                bufferInfo.size = sampleSize
                bufferInfo.presentationTimeUs = duration1 + extractor2.sampleTime
                bufferInfo.flags = extractor2.sampleFlags

                if (bufferInfo.presentationTimeUs > maxPresentationTime) {
                    maxPresentationTime = bufferInfo.presentationTimeUs
                }

                muxer.writeSampleData(outputTrackIndex, buffer, bufferInfo)
                extractor2.advance()
            }

            return Duration.ofMillis(maxPresentationTime / 1000)

        } finally {
            try { extractor1?.release() } catch (e: Exception) { /* ignore */ }
            try { extractor2?.release() } catch (e: Exception) { /* ignore */ }
            try {
                muxer?.stop()
                muxer?.release()
            } catch (e: Exception) { /* ignore */ }
        }
    }

    private fun findAudioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith("audio/") == true) {
                return i
            }
        }
        return -1
    }

    /**
     * Get the duration of an audio file
     */
    fun getAudioDuration(filePath: String): Duration {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(filePath)
            val trackIndex = findAudioTrack(extractor)
            if (trackIndex >= 0) {
                val format = extractor.getTrackFormat(trackIndex)
                val durationUs = format.getLong(MediaFormat.KEY_DURATION)
                return Duration.ofMillis(durationUs / 1000)
            }
        } finally {
            extractor.release()
        }
        return Duration.ZERO
    }
}
