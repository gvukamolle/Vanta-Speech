package com.vanta.speech.feature.realtime

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vanta.speech.R
import com.vanta.speech.core.audio.RealtimeState
import com.vanta.speech.core.audio.VADState
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.ui.components.CircularAudioVisualizer
import com.vanta.speech.ui.components.PresetPicker
import com.vanta.speech.ui.components.PresetPickerBottomSheet
import com.vanta.speech.ui.components.RecordButton
import com.vanta.speech.ui.components.TimerDisplay
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.components.VantaGlassIconButton
import com.vanta.speech.ui.theme.VantaColors
import kotlinx.coroutines.flow.collectLatest

@Composable
fun RealtimeRecordingScreen(
    viewModel: RealtimeViewModel = hiltViewModel(),
    onRecordingCompleted: (String) -> Unit = {}
) {
    val realtimeState by viewModel.realtimeState.collectAsStateWithLifecycle()
    val selectedPreset by viewModel.selectedPreset.collectAsStateWithLifecycle()
    val currentTranscription by viewModel.currentTranscription.collectAsStateWithLifecycle()
    val audioLevel by viewModel.audioLevel.collectAsStateWithLifecycle()
    val totalDuration by viewModel.totalDuration.collectAsStateWithLifecycle()
    val vadState by viewModel.vadState.collectAsStateWithLifecycle()
    val currentChunkDuration by viewModel.currentChunkDuration.collectAsStateWithLifecycle()

    var showPresetPicker by remember { mutableStateOf(false) }

    val isRecording = realtimeState is RealtimeState.Recording
    val isProcessing = realtimeState is RealtimeState.Processing
    val isMerging = realtimeState is RealtimeState.Merging

    // Handle UI events
    LaunchedEffect(Unit) {
        viewModel.uiEvents.collectLatest { event ->
            when (event) {
                is RealtimeUiEvent.RecordingCompleted -> {
                    onRecordingCompleted(event.recordingId)
                }
                else -> { /* Handled elsewhere */ }
            }
        }
    }

    VantaBackground {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 24.dp)
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Real-time",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = VantaColors.White
                )

                Spacer(modifier = Modifier.width(12.dp))

                // Live indicator
                AnimatedVisibility(
                    visible = isRecording,
                    enter = fadeIn(),
                    exit = fadeOut()
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(VantaColors.RecordingActive.copy(alpha = 0.2f))
                            .padding(horizontal = 10.dp, vertical = 4.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(VantaColors.RecordingActive)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "LIVE",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = VantaColors.RecordingActive
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Show preset picker only when not recording
            if (!isRecording && !isProcessing && !isMerging) {
                PresetPicker(
                    presets = RecordingPreset.entries,
                    selectedPreset = selectedPreset,
                    onPresetSelected = { viewModel.selectPreset(it) }
                )

                Spacer(modifier = Modifier.height(16.dp))
            }

            // Main content area
            when {
                isRecording -> {
                    RecordingContent(
                        selectedPreset = selectedPreset,
                        currentTranscription = currentTranscription,
                        totalDuration = totalDuration,
                        currentChunkDuration = currentChunkDuration,
                        vadState = vadState,
                        modifier = Modifier.weight(1f)
                    )
                }
                isProcessing -> {
                    val processingState = realtimeState as RealtimeState.Processing
                    ProcessingContent(
                        progress = processingState.progress,
                        chunksCompleted = processingState.chunksCompleted,
                        totalChunks = processingState.totalChunks,
                        currentTranscription = currentTranscription,
                        modifier = Modifier.weight(1f)
                    )
                }
                isMerging -> {
                    MergingContent(
                        currentTranscription = currentTranscription,
                        modifier = Modifier.weight(1f)
                    )
                }
                else -> {
                    IdleContent(
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        // Floating controls
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(bottom = 32.dp),
            contentAlignment = Alignment.BottomCenter
        ) {
            // Audio visualizer behind button
            CircularAudioVisualizer(
                audioLevel = audioLevel,
                isActive = isRecording,
                modifier = Modifier.height(200.dp)
            )

            when {
                isRecording -> {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(24.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // VAD indicator
                        VantaGlassIconButton(
                            icon = if (vadState == VADState.SPEECH_DETECTED) Icons.Default.Mic else Icons.Default.MicOff,
                            onClick = { viewModel.forceChunkSplit() },
                            size = 56.dp
                        )

                        // Stop button
                        RecordButton(
                            isRecording = true,
                            isPaused = false,
                            onClick = { viewModel.stopRecording() }
                        )

                        // Spacer for symmetry
                        Spacer(modifier = Modifier.size(56.dp))
                    }
                }
                isProcessing || isMerging -> {
                    // Show stop indicator
                    Box(
                        modifier = Modifier
                            .size(80.dp)
                            .clip(CircleShape)
                            .background(VantaColors.DarkSurfaceElevated),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(48.dp),
                            color = VantaColors.PinkVibrant,
                            strokeWidth = 4.dp
                        )
                    }
                }
                else -> {
                    RecordButton(
                        isRecording = false,
                        isPaused = false,
                        onClick = {
                            if (selectedPreset != null) {
                                viewModel.startRecording()
                            } else {
                                showPresetPicker = true
                            }
                        }
                    )
                }
            }
        }
    }

    // Preset picker bottom sheet
    if (showPresetPicker) {
        PresetPickerBottomSheet(
            presets = RecordingPreset.entries,
            onPresetSelected = { preset ->
                viewModel.selectPreset(preset)
                viewModel.startRecording()
            },
            onDismiss = { showPresetPicker = false }
        )
    }
}

@Composable
private fun RecordingContent(
    selectedPreset: RecordingPreset?,
    currentTranscription: String,
    totalDuration: java.time.Duration,
    currentChunkDuration: java.time.Duration,
    vadState: VADState,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
    ) {
        // Preset and timer
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            selectedPreset?.let { preset ->
                Icon(
                    imageVector = preset.icon,
                    contentDescription = null,
                    tint = VantaColors.PinkVibrant,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = preset.displayName,
                    style = MaterialTheme.typography.titleSmall,
                    color = VantaColors.White
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            TimerDisplay(
                duration = totalDuration,
                color = VantaColors.White
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // VAD status bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(VantaColors.DarkSurfaceElevated)
                .padding(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(
                        when (vadState) {
                            VADState.SPEECH_DETECTED -> VantaColors.RecordingActive
                            VADState.SILENCE_DETECTED -> VantaColors.RecordingPaused
                            else -> VantaColors.DarkTextSecondary
                        }
                    )
            )

            Spacer(modifier = Modifier.width(10.dp))

            Text(
                text = when (vadState) {
                    VADState.SPEECH_DETECTED -> "Речь обнаружена"
                    VADState.SILENCE_DETECTED -> "Тишина..."
                    VADState.LISTENING -> "Слушаю..."
                    VADState.IDLE -> "Ожидание"
                },
                style = MaterialTheme.typography.bodySmall,
                color = VantaColors.DarkTextSecondary
            )

            Spacer(modifier = Modifier.weight(1f))

            // Chunk timer
            Text(
                text = formatDuration(currentChunkDuration),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                color = VantaColors.BlueVibrant
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Live transcription
        Text(
            text = "Транскрипция:",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = VantaColors.DarkTextSecondary
        )

        Spacer(modifier = Modifier.height(8.dp))

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(VantaColors.DarkSurfaceElevated.copy(alpha = 0.5f))
                .padding(16.dp)
        ) {
            val scrollState = rememberScrollState()

            LaunchedEffect(currentTranscription) {
                scrollState.animateScrollTo(scrollState.maxValue)
            }

            if (currentTranscription.isNotEmpty()) {
                Text(
                    text = currentTranscription,
                    style = MaterialTheme.typography.bodyLarge,
                    color = VantaColors.White,
                    lineHeight = 24.sp,
                    modifier = Modifier.verticalScroll(scrollState)
                )
            } else {
                Text(
                    text = "Начните говорить...",
                    style = MaterialTheme.typography.bodyLarge,
                    color = VantaColors.DarkTextSecondary
                )
            }
        }

        Spacer(modifier = Modifier.height(160.dp))
    }
}

@Composable
private fun ProcessingContent(
    progress: Float,
    chunksCompleted: Int,
    totalChunks: Int,
    currentTranscription: String,
    modifier: Modifier = Modifier
) {
    val animatedProgress by animateFloatAsState(
        targetValue = progress,
        animationSpec = tween(300),
        label = "progress"
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = "Обработка записи",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = VantaColors.White
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Транскрибация фрагментов: $chunksCompleted / $totalChunks",
            style = MaterialTheme.typography.bodyMedium,
            color = VantaColors.DarkTextSecondary
        )

        Spacer(modifier = Modifier.height(24.dp))

        LinearProgressIndicator(
            progress = { animatedProgress },
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp)),
            color = VantaColors.PinkVibrant,
            trackColor = VantaColors.DarkSurfaceElevated
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Show current transcription
        if (currentTranscription.isNotEmpty()) {
            Text(
                text = "Текущий результат:",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = VantaColors.DarkTextSecondary
            )

            Spacer(modifier = Modifier.height(8.dp))

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(VantaColors.DarkSurfaceElevated.copy(alpha = 0.5f))
                    .padding(16.dp)
            ) {
                Text(
                    text = currentTranscription,
                    style = MaterialTheme.typography.bodyMedium,
                    color = VantaColors.White,
                    lineHeight = 22.sp,
                    modifier = Modifier.verticalScroll(rememberScrollState())
                )
            }
        } else {
            Spacer(modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(160.dp))
    }
}

@Composable
private fun MergingContent(
    currentTranscription: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(48.dp))

        CircularProgressIndicator(
            modifier = Modifier.size(64.dp),
            color = VantaColors.PinkVibrant,
            strokeWidth = 4.dp
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Объединение записи",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = VantaColors.White
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Подождите, идёт финализация...",
            style = MaterialTheme.typography.bodyMedium,
            color = VantaColors.DarkTextSecondary
        )

        Spacer(modifier = Modifier.weight(1f))
        Spacer(modifier = Modifier.height(160.dp))
    }
}

@Composable
private fun IdleContent(
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.Mic,
                contentDescription = null,
                tint = VantaColors.DarkTextSecondary,
                modifier = Modifier.size(48.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Real-time режим",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = VantaColors.White
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Транскрипция в реальном времени\nпо мере вашей речи",
                style = MaterialTheme.typography.bodyMedium,
                color = VantaColors.DarkTextSecondary,
                textAlign = TextAlign.Center
            )
        }
    }
}

private fun formatDuration(duration: java.time.Duration): String {
    val minutes = duration.toMinutes() % 60
    val seconds = duration.seconds % 60
    return String.format(java.util.Locale.US, "%02d:%02d", minutes, seconds)
}
