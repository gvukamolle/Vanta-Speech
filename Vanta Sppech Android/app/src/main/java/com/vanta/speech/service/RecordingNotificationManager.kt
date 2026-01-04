package com.vanta.speech.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.vanta.speech.MainActivity
import com.vanta.speech.R
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Duration
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RecordingNotificationManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        const val CHANNEL_ID = "recording_channel"
        const val NOTIFICATION_ID = 1001

        private const val REQUEST_CONTENT = 0
        private const val REQUEST_PAUSE = 1
        private const val REQUEST_RESUME = 2
        private const val REQUEST_STOP = 3
    }

    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Запись",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Уведомление о записи"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    fun createRecordingNotification(
        presetName: String,
        duration: Duration,
        isPaused: Boolean
    ): Notification {
        val contentIntent = PendingIntent.getActivity(
            context,
            REQUEST_CONTENT,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pauseResumeIntent = PendingIntent.getService(
            context,
            if (isPaused) REQUEST_RESUME else REQUEST_PAUSE,
            Intent(context, RecordingService::class.java).apply {
                action = if (isPaused) RecordingService.ACTION_RESUME else RecordingService.ACTION_PAUSE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = PendingIntent.getService(
            context,
            REQUEST_STOP,
            Intent(context, RecordingService::class.java).apply {
                action = RecordingService.ACTION_STOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val durationText = formatDuration(duration)
        val statusText = if (isPaused) "Пауза" else "Запись"

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(presetName)
            .setContentText("$statusText • $durationText")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .addAction(
                if (isPaused) R.drawable.ic_play else R.drawable.ic_pause,
                if (isPaused) "Продолжить" else "Пауза",
                pauseResumeIntent
            )
            .addAction(
                R.drawable.ic_stop,
                "Стоп",
                stopIntent
            )
            .setUsesChronometer(!isPaused)
            .setWhen(
                if (isPaused) {
                    System.currentTimeMillis()
                } else {
                    System.currentTimeMillis() - duration.toMillis()
                }
            )
            .setShowWhen(!isPaused)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    fun updateNotification(
        presetName: String,
        duration: Duration,
        isPaused: Boolean
    ) {
        val notification = createRecordingNotification(presetName, duration, isPaused)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    fun cancelNotification() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun formatDuration(duration: Duration): String {
        val hours = duration.toHours()
        val minutes = duration.toMinutes() % 60
        val seconds = duration.seconds % 60

        return if (hours > 0) {
            String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%02d:%02d", minutes, seconds)
        }
    }
}
