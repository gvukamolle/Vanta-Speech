package com.vanta.speech.feature.library

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.components.VantaPrimaryButton
import com.vanta.speech.ui.theme.VantaColors
import dev.jeziellago.compose.markdowntext.MarkdownText
import java.time.Duration
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingDetailScreen(
    recordingId: String,
    viewModel: RecordingDetailViewModel = hiltViewModel(),
    onNavigateBack: () -> Unit
) {
    val recording by viewModel.recording.collectAsStateWithLifecycle()
    val playbackState by viewModel.playbackState.collectAsStateWithLifecycle()
    val currentPosition by viewModel.currentPosition.collectAsStateWithLifecycle()
    val totalDuration by viewModel.totalDuration.collectAsStateWithLifecycle()
    val isPlaying by viewModel.isPlaying.collectAsStateWithLifecycle()
    val playbackSpeed by viewModel.playbackSpeed.collectAsStateWithLifecycle()
    val transcriptionState by viewModel.transcriptionState.collectAsStateWithLifecycle()
    val continuationState by viewModel.continuationState.collectAsStateWithLifecycle()

    var showDeleteDialog by remember { mutableStateOf(false) }
    var showSpeedSelector by remember { mutableStateOf(false) }
    var showContinueConfirmDialog by remember { mutableStateOf(false) }

    VantaBackground {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            // Top app bar
            TopAppBar(
                title = { },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Назад",
                            tint = VantaColors.White
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { showDeleteDialog = true }) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Удалить",
                            tint = VantaColors.DarkTextSecondary
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = VantaColors.DarkBackground.copy(alpha = 0f)
                )
            )

            recording?.let { rec ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 24.dp)
                        .verticalScroll(rememberScrollState())
                ) {
                    // Title
                    Text(
                        text = rec.title,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = VantaColors.White
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    // Metadata
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        rec.preset?.let { preset ->
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(VantaColors.PinkVibrant.copy(alpha = 0.2f))
                                    .padding(horizontal = 10.dp, vertical = 4.dp)
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = preset.icon,
                                        contentDescription = null,
                                        tint = VantaColors.PinkVibrant,
                                        modifier = Modifier.size(14.dp)
                                    )
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(
                                        text = preset.displayName,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = VantaColors.PinkVibrant
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.width(12.dp))
                        }

                        Text(
                            text = rec.formattedDate,
                            style = MaterialTheme.typography.bodySmall,
                            color = VantaColors.DarkTextSecondary
                        )

                        Spacer(modifier = Modifier.width(12.dp))

                        Text(
                            text = rec.formattedDuration,
                            style = MaterialTheme.typography.bodySmall,
                            color = VantaColors.DarkTextSecondary
                        )
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    // Audio player card
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(20.dp))
                            .background(VantaColors.DarkSurfaceElevated)
                            .padding(20.dp)
                    ) {
                        Column {
                            // Progress slider
                            Slider(
                                value = if (totalDuration.toMillis() > 0) {
                                    currentPosition.toMillis().toFloat() / totalDuration.toMillis()
                                } else 0f,
                                onValueChange = { fraction ->
                                    val newPosition = Duration.ofMillis(
                                        (fraction * totalDuration.toMillis()).toLong()
                                    )
                                    viewModel.seekTo(newPosition)
                                },
                                colors = SliderDefaults.colors(
                                    thumbColor = VantaColors.PinkVibrant,
                                    activeTrackColor = VantaColors.PinkVibrant,
                                    inactiveTrackColor = VantaColors.DarkSurface
                                ),
                                modifier = Modifier.fillMaxWidth()
                            )

                            // Time labels
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = formatDuration(currentPosition),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = VantaColors.DarkTextSecondary
                                )
                                Text(
                                    text = formatDuration(totalDuration),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = VantaColors.DarkTextSecondary
                                )
                            }

                            Spacer(modifier = Modifier.height(16.dp))

                            // Playback controls
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                // Speed button
                                IconButton(onClick = { showSpeedSelector = !showSpeedSelector }) {
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Speed,
                                            contentDescription = "Скорость",
                                            tint = VantaColors.DarkTextSecondary,
                                            modifier = Modifier.size(20.dp)
                                        )
                                        Text(
                                            text = "${playbackSpeed}x",
                                            fontSize = 10.sp,
                                            color = VantaColors.DarkTextSecondary
                                        )
                                    }
                                }

                                Spacer(modifier = Modifier.width(16.dp))

                                // Rewind
                                IconButton(onClick = { viewModel.seekBackward() }) {
                                    Icon(
                                        imageVector = Icons.Default.FastRewind,
                                        contentDescription = "-10с",
                                        tint = VantaColors.White,
                                        modifier = Modifier.size(32.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.width(16.dp))

                                // Play/Pause
                                IconButton(
                                    onClick = { viewModel.togglePlayPause() },
                                    modifier = Modifier
                                        .size(64.dp)
                                        .clip(CircleShape)
                                        .background(VantaColors.PinkVibrant)
                                ) {
                                    Icon(
                                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                        contentDescription = if (isPlaying) "Пауза" else "Воспроизвести",
                                        tint = VantaColors.White,
                                        modifier = Modifier.size(32.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.width(16.dp))

                                // Forward
                                IconButton(onClick = { viewModel.seekForward() }) {
                                    Icon(
                                        imageVector = Icons.Default.FastForward,
                                        contentDescription = "+10с",
                                        tint = VantaColors.White,
                                        modifier = Modifier.size(32.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.width(32.dp))
                            }

                            // Speed selector
                            AnimatedVisibility(
                                visible = showSpeedSelector,
                                enter = fadeIn(),
                                exit = fadeOut()
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 12.dp),
                                    horizontalArrangement = Arrangement.SpaceEvenly
                                ) {
                                    listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f).forEach { speed ->
                                        TextButton(
                                            onClick = {
                                                viewModel.setPlaybackSpeed(speed)
                                                showSpeedSelector = false
                                            }
                                        ) {
                                            Text(
                                                text = "${speed}x",
                                                color = if (playbackSpeed == speed) VantaColors.PinkVibrant else VantaColors.White,
                                                fontWeight = if (playbackSpeed == speed) FontWeight.Bold else FontWeight.Normal
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Continue Recording Button
                    if (continuationState !is ContinuationState.Recording) {
                        OutlinedButton(
                            onClick = {
                                if (rec.isTranscribed) {
                                    showContinueConfirmDialog = true
                                } else {
                                    viewModel.startContinuationRecording()
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.outlinedButtonColors(
                                contentColor = VantaColors.DarkTextSecondary
                            )
                        ) {
                            Icon(
                                Icons.Default.Mic,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Продолжить запись")
                        }
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    // Transcription section - show if we have transcription text
                    if (rec.transcriptionText != null) {
                        // Summary section with loading indicator
                        Column {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = "Саммари",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = VantaColors.White
                                )

                                // Show spinner if generating summary
                                val isGenerating = rec.isSummaryGenerating ||
                                    transcriptionState is TranscriptionState.GeneratingSummary
                                if (isGenerating) {
                                    Spacer(modifier = Modifier.width(12.dp))
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        color = VantaColors.PinkVibrant,
                                        strokeWidth = 2.dp
                                    )
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = "Генерируем...",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = VantaColors.DarkTextSecondary
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.height(12.dp))

                            if (rec.summaryText != null) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(VantaColors.DarkSurfaceElevated)
                                        .padding(16.dp)
                                ) {
                                    MarkdownText(
                                        markdown = rec.summaryText,
                                        color = VantaColors.White,
                                        style = MaterialTheme.typography.bodyMedium
                                    )
                                }
                            } else if (!rec.isSummaryGenerating && transcriptionState !is TranscriptionState.GeneratingSummary) {
                                // Summary failed or not available - show retry button
                                val errorState = transcriptionState as? TranscriptionState.Error
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(VantaColors.DarkSurfaceElevated)
                                        .padding(16.dp)
                                ) {
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        if (errorState?.hasTranscription == true) {
                                            Text(
                                                text = errorState.message,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = VantaColors.RecordingActive,
                                                textAlign = TextAlign.Center
                                            )
                                            Spacer(modifier = Modifier.height(12.dp))
                                        }
                                        OutlinedButton(
                                            onClick = { viewModel.regenerateSummary() },
                                            colors = ButtonDefaults.outlinedButtonColors(
                                                contentColor = VantaColors.PinkVibrant
                                            )
                                        ) {
                                            Text("Сгенерировать саммари")
                                        }
                                    }
                                }
                            }

                            Spacer(modifier = Modifier.height(24.dp))
                        }

                        // Transcription
                        rec.transcriptionText?.let { transcription ->
                            Text(
                                text = "Транскрипция",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = VantaColors.White
                            )

                            Spacer(modifier = Modifier.height(12.dp))

                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(VantaColors.DarkSurfaceElevated)
                                    .padding(16.dp)
                            ) {
                                Text(
                                    text = transcription,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = VantaColors.White,
                                    lineHeight = 24.sp
                                )
                            }
                        }
                    } else {
                        // Not transcribed - show transcribe button
                        when (transcriptionState) {
                            is TranscriptionState.Idle -> {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(VantaColors.DarkSurfaceElevated)
                                        .padding(24.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        Text(
                                            text = "Запись ещё не обработана",
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = VantaColors.DarkTextSecondary,
                                            textAlign = TextAlign.Center
                                        )
                                        Spacer(modifier = Modifier.height(16.dp))
                                        VantaPrimaryButton(
                                            text = "Транскрибировать",
                                            onClick = { viewModel.transcribeRecording() }
                                        )
                                    }
                                }
                            }
                            is TranscriptionState.Transcribing -> {
                                TranscriptionProgressCard(
                                    title = "Транскрибация...",
                                    progress = (transcriptionState as TranscriptionState.Transcribing).progress
                                )
                            }
                            is TranscriptionState.TranscriptionCompleted,
                            is TranscriptionState.GeneratingSummary -> {
                                TranscriptionProgressCard(
                                    title = "Генерация саммари...",
                                    progress = null
                                )
                            }
                            is TranscriptionState.Error -> {
                                val error = transcriptionState as TranscriptionState.Error
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(16.dp))
                                        .background(VantaColors.DarkSurfaceElevated)
                                        .padding(24.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        Text(
                                            text = error.message,
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = VantaColors.RecordingActive,
                                            textAlign = TextAlign.Center
                                        )
                                        Spacer(modifier = Modifier.height(16.dp))
                                        VantaPrimaryButton(
                                            text = "Попробовать снова",
                                            onClick = { viewModel.transcribeRecording() }
                                        )
                                    }
                                }
                            }
                            else -> {}
                        }
                    }

                    Spacer(modifier = Modifier.height(32.dp))
                }
            } ?: run {
                // Loading state
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = VantaColors.PinkVibrant)
                }
            }
        }
    }

    // Delete confirmation dialog
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Удалить запись?") },
            text = { Text("Это действие нельзя отменить.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteDialog = false
                        viewModel.deleteRecording { onNavigateBack() }
                    }
                ) {
                    Text("Удалить", color = VantaColors.RecordingActive)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Отмена")
                }
            },
            containerColor = VantaColors.DarkSurface,
            titleContentColor = VantaColors.White,
            textContentColor = VantaColors.DarkTextSecondary
        )
    }

    // Continue recording confirmation dialog (when transcription exists)
    if (showContinueConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showContinueConfirmDialog = false },
            title = { Text("Продолжить запись?") },
            text = {
                Text("Транскрипция и саммари будут удалены. После остановки записи аудио будет склеено в один файл и потребуется новая транскрипция.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showContinueConfirmDialog = false
                        viewModel.startContinuationRecording()
                    }
                ) {
                    Text("Продолжить", color = VantaColors.RecordingActive)
                }
            },
            dismissButton = {
                TextButton(onClick = { showContinueConfirmDialog = false }) {
                    Text("Отмена")
                }
            },
            containerColor = VantaColors.DarkSurface,
            titleContentColor = VantaColors.White,
            textContentColor = VantaColors.DarkTextSecondary
        )
    }

    // Continuation error dialog
    if (continuationState is ContinuationState.Error) {
        AlertDialog(
            onDismissRequest = { viewModel.clearContinuationError() },
            title = { Text("Ошибка") },
            text = { Text((continuationState as ContinuationState.Error).message) },
            confirmButton = {
                TextButton(onClick = { viewModel.clearContinuationError() }) {
                    Text("OK")
                }
            },
            containerColor = VantaColors.DarkSurface,
            titleContentColor = VantaColors.White,
            textContentColor = VantaColors.DarkTextSecondary
        )
    }

    // Merging overlay
    if (continuationState is ContinuationState.Merging) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(VantaColors.DarkBackground.copy(alpha = 0.8f)),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                CircularProgressIndicator(color = VantaColors.PinkVibrant)
                Text(
                    "Склеиваем аудио...",
                    color = VantaColors.White,
                    style = MaterialTheme.typography.bodyLarge
                )
            }
        }
    }

    // Recording state overlay
    if (continuationState is ContinuationState.Recording) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(VantaColors.DarkBackground.copy(alpha = 0.8f)),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(VantaColors.RecordingActive),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Default.Mic,
                        contentDescription = null,
                        tint = VantaColors.White,
                        modifier = Modifier.size(40.dp)
                    )
                }
                Text(
                    "Запись продолжается...",
                    color = VantaColors.White,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    "Откройте приложение для остановки записи",
                    color = VantaColors.DarkTextSecondary,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun TranscriptionProgressCard(
    title: String,
    progress: Float?
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(VantaColors.DarkSurfaceElevated)
            .padding(24.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (progress != null) {
                CircularProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.size(48.dp),
                    color = VantaColors.PinkVibrant,
                    strokeWidth = 4.dp
                )
            } else {
                CircularProgressIndicator(
                    modifier = Modifier.size(48.dp),
                    color = VantaColors.PinkVibrant,
                    strokeWidth = 4.dp
                )
            }
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = VantaColors.White
            )
        }
    }
}

private fun formatDuration(duration: Duration): String {
    val hours = duration.toHours()
    val minutes = duration.toMinutes() % 60
    val seconds = duration.seconds % 60

    return if (hours > 0) {
        String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.US, "%d:%02d", minutes, seconds)
    }
}
