package com.vantaspeech.audio

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.vantaspeech.MainActivity
import com.vantaspeech.R
import com.vantaspeech.VantaSpeechApplication
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class RecordingService : Service() {

    @Inject
    lateinit var audioRecorder: AudioRecorder

    private val binder = RecordingBinder()
    private val serviceScope = CoroutineScope(Dispatchers.Main + Job())
    private var metricsJob: Job? = null

    inner class RecordingBinder : Binder() {
        fun getService(): RecordingService = this@RecordingService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_RECORDING -> {
                startForegroundRecording()
            }
            ACTION_STOP_RECORDING -> {
                stopRecording()
            }
            ACTION_PAUSE_RECORDING -> {
                audioRecorder.pauseRecording()
                updateNotification()
            }
            ACTION_RESUME_RECORDING -> {
                audioRecorder.resumeRecording()
                updateNotification()
            }
        }
        return START_STICKY
    }

    private fun startForegroundRecording() {
        val notification = createNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        audioRecorder.startRecording()
        startMetricsUpdates()
    }

    private fun stopRecording() {
        metricsJob?.cancel()
        audioRecorder.stopRecording()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startMetricsUpdates() {
        metricsJob?.cancel()
        metricsJob = serviceScope.launch {
            while (isActive) {
                audioRecorder.updateMetrics()
                delay(100) // Update every 100ms
            }
        }
    }

    private fun createNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, RecordingService::class.java).apply {
                action = ACTION_STOP_RECORDING
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val state = audioRecorder.state.value
        val title = when (state) {
            RecordingState.PAUSED -> "Recording paused"
            else -> getString(R.string.notification_recording_title)
        }

        return NotificationCompat.Builder(this, VantaSpeechApplication.RECORDING_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(getString(R.string.notification_recording_text))
            .setSmallIcon(R.drawable.ic_mic)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .addAction(
                R.drawable.ic_stop,
                getString(R.string.recording_stop),
                stopIntent
            )
            .build()
    }

    private fun updateNotification() {
        val notification = createNotification()
        val notificationManager = getSystemService(android.app.NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        metricsJob?.cancel()
    }

    companion object {
        const val ACTION_START_RECORDING = "com.vantaspeech.action.START_RECORDING"
        const val ACTION_STOP_RECORDING = "com.vantaspeech.action.STOP_RECORDING"
        const val ACTION_PAUSE_RECORDING = "com.vantaspeech.action.PAUSE_RECORDING"
        const val ACTION_RESUME_RECORDING = "com.vantaspeech.action.RESUME_RECORDING"
        private const val NOTIFICATION_ID = 1001
    }
}
