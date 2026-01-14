package com.vanta.speech.feature.recording

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vanta.speech.R
import com.vanta.speech.core.audio.AudioImporter
import com.vanta.speech.core.audio.RealtimeState
import com.vanta.speech.core.audio.VADState
import com.vanta.speech.core.domain.model.RecordingMode
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.model.RecordingState
import com.vanta.speech.feature.realtime.RealtimeUiEvent
import com.vanta.speech.feature.realtime.RealtimeViewModel
import com.vanta.speech.ui.components.CircularAudioVisualizer
import com.vanta.speech.ui.components.FloatingMicButton
import com.vanta.speech.ui.components.ModePicker
import com.vanta.speech.ui.components.PresetPickerBottomSheet
import com.vanta.speech.ui.components.RecordingCard
import com.vanta.speech.ui.components.TimerDisplay
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.components.VantaGlassIconButton
import com.vanta.speech.ui.theme.VantaColors
import kotlinx.coroutines.flow.collectLatest
import java.time.Duration
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingScreen(
    recordingViewModel: RecordingViewModel = hiltViewModel(),
    realtimeViewModel: RealtimeViewModel = hiltViewModel(),
    onRecordingCompleted: (String) -> Unit = {},
    onNavigateToRecording: (String) -> Unit = {}
) {
    // Standard recording state
    val selectedMode by recordingViewModel.selectedMode.collectAsStateWithLifecycle()
    val recordingState by recordingViewModel.recordingState.collectAsStateWithLifecycle()
    val selectedPreset by recordingViewModel.selectedPreset.collectAsStateWithLifecycle()
    val duration by recordingViewModel.duration.collectAsStateWithLifecycle()
    val audioLevel by recordingViewModel.audioLevel.collectAsStateWithLifecycle()
    val todayRecordings by recordingViewModel.todayRecordings.collectAsStateWithLifecycle()

    // Import state
    val isImporting by recordingViewModel.isImporting.collectAsStateWithLifecycle()
    val importError by recordingViewModel.importError.collectAsStateWithLifecycle()
    val importedAudioData by recordingViewModel.importedAudioData.collectAsStateWithLifecycle()

    // Realtime state
    val realtimeState by realtimeViewModel.realtimeState.collectAsStateWithLifecycle()
    val realtimePreset by realtimeViewModel.selectedPreset.collectAsStateWithLifecycle()
    val currentTranscription by realtimeViewModel.currentTranscription.collectAsStateWithLifecycle()
    val realtimeAudioLevel by realtimeViewModel.audioLevel.collectAsStateWithLifecycle()
    val totalDuration by realtimeViewModel.totalDuration.collectAsStateWithLifecycle()
    val vadState by realtimeViewModel.vadState.collectAsStateWithLifecycle()
    val currentChunkDuration by realtimeViewModel.currentChunkDuration.collectAsStateWithLifecycle()

    var showPresetPicker by remember { mutableStateOf(false) }
    var showImportPresetPicker by remember { mutableStateOf(false) }

    val isStandardRecording = recordingState is RecordingState.Recording
    val isPaused = (recordingState as? RecordingState.Recording)?.isPaused == true
    val isRealtimeRecording = realtimeState is RealtimeState.Recording
    val isRealtimeProcessing = realtimeState is RealtimeState.Processing
    val isRealtimeMerging = realtimeState is RealtimeState.Merging

    val isAnyRecordingActive = isStandardRecording || isRealtimeRecording || isRealtimeProcessing || isRealtimeMerging

    // File picker launcher
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let { recordingViewModel.importAudio(it) }
    }

    // Show preset picker when import is complete
    if (importedAudioData != null && !showImportPresetPicker) {
        showImportPresetPicker = true
    }

    // Handle realtime UI events
    LaunchedEffect(Unit) {
        realtimeViewModel.uiEvents.collectLatest { event ->
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
                    text = stringResource(R.string.nav_recording),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = VantaColors.White
                )

                Spacer(modifier = Modifier.width(12.dp))

                // Live indicator for realtime mode
                AnimatedVisibility(
                    visible = isRealtimeRecording,
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

            // Mode picker (disabled when recording)
            ModePicker(
                selectedMode = selectedMode,
                onModeSelected = { recordingViewModel.selectMode(it) },
                enabled = !isAnyRecordingActive
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Content based on mode
            when (selectedMode) {
                RecordingMode.STANDARD -> {
                    StandardModeContent(
                        isRecording = isStandardRecording,
                        isPaused = isPaused,
                        selectedPreset = selectedPreset,
                        duration = duration,
                        todayRecordings = todayRecordings,
                        onRecordingClick = onNavigateToRecording,
                        modifier = Modifier.weight(1f)
                    )
                }
                RecordingMode.REALTIME -> {
                    RealtimeModeContent(
                        realtimeState = realtimeState,
                        selectedPreset = realtimePreset,
                        currentTranscription = currentTranscription,
                        totalDuration = totalDuration,
                        currentChunkDuration = currentChunkDuration,
                        vadState = vadState,
                        modifier = Modifier.weight(1f)
                    )
                }
                RecordingMode.IMPORT -> {
                    ImportModeContent(
                        todayRecordings = todayRecordings,
                        onRecordingClick = onNavigateToRecording,
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
            // Audio visualizer
            val currentAudioLevel = when (selectedMode) {
                RecordingMode.REALTIME -> realtimeAudioLevel
                else -> audioLevel
            }
            val isVisualizerActive = when (selectedMode) {
                RecordingMode.STANDARD -> isStandardRecording && !isPaused
                RecordingMode.REALTIME -> isRealtimeRecording
                RecordingMode.IMPORT -> false
            }

            CircularAudioVisualizer(
                audioLevel = currentAudioLevel,
                isActive = isVisualizerActive,
                modifier = Modifier.height(200.dp)
            )

            // Controls based on mode - using iOS-style FloatingMicButton
            when (selectedMode) {
                RecordingMode.STANDARD -> {
                    StandardModeControls(
                        mode = selectedMode,
                        isRecording = isStandardRecording,
                        isPaused = isPaused,
                        duration = duration,
                        selectedPreset = selectedPreset,
                        onStartRecording = { recordingViewModel.startRecording() },
                        onToggleRecording = { recordingViewModel.toggleRecording() },
                        onStopRecording = { recordingViewModel.stopRecording() },
                        onShowPresetPicker = { showPresetPicker = true }
                    )
                }
                RecordingMode.REALTIME -> {
                    RealtimeModeControls(
                        mode = selectedMode,
                        realtimeState = realtimeState,
                        duration = totalDuration,
                        selectedPreset = realtimePreset,
                        onStartRecording = { realtimeViewModel.startRecording() },
                        onStopRecording = { realtimeViewModel.stopRecording() },
                        onShowPresetPicker = { showPresetPicker = true }
                    )
                }
                RecordingMode.IMPORT -> {
                    ImportModeControls(
                        mode = selectedMode,
                        onImportClick = {
                            filePickerLauncher.launch(AudioImporter.AUDIO_MIME_TYPES)
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
                when (selectedMode) {
                    RecordingMode.STANDARD -> {
                        recordingViewModel.selectPreset(preset)
                        recordingViewModel.startRecording()
                    }
                    RecordingMode.REALTIME -> {
                        realtimeViewModel.selectPreset(preset)
                        realtimeViewModel.startRecording()
                    }
                    RecordingMode.IMPORT -> { /* Not used */ }
                }
            },
            onDismiss = { showPresetPicker = false }
        )
    }

    // Import preset picker bottom sheet
    if (showImportPresetPicker && importedAudioData != null) {
        ImportPresetPickerSheet(
            audioData = importedAudioData!!,
            presets = RecordingPreset.entries.toList(),
            onPresetSelected = { preset ->
                recordingViewModel.finalizeImport(preset)
                showImportPresetPicker = false
            },
            onCancel = {
                recordingViewModel.cancelImport()
                showImportPresetPicker = false
            }
        )
    }

    // Import error dialog
    importError?.let { error ->
        AlertDialog(
            onDismissRequest = { recordingViewModel.clearImportError() },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        tint = Color(0xFFFF3B30)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Ошибка импорта")
                }
            },
            text = { Text(error) },
            confirmButton = {
                TextButton(onClick = { recordingViewModel.clearImportError() }) {
                    Text("OK")
                }
            },
            containerColor = VantaColors.DarkSurfaceElevated,
            titleContentColor = VantaColors.White,
            textContentColor = VantaColors.DarkTextSecondary
        )
    }

    // Import loading overlay
    if (isImporting) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                CircularProgressIndicator(color = VantaColors.PinkVibrant)
                Text(
                    "Импортируем аудио...",
                    color = VantaColors.White,
                    style = MaterialTheme.typography.bodyLarge
                )
            }
        }
    }
}

// MARK: - Standard Mode

@Composable
private fun StandardModeContent(
    isRecording: Boolean,
    isPaused: Boolean,
    selectedPreset: RecordingPreset?,
    duration: Duration,
    todayRecordings: List<com.vanta.speech.core.domain.model.Recording>,
    onRecordingClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    if (isRecording) {
        // Active recording UI
        Box(
            modifier = modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                selectedPreset?.let { preset ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = preset.icon,
                            contentDescription = null,
                            tint = VantaColors.PinkVibrant,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = preset.displayName,
                            style = MaterialTheme.typography.titleMedium,
                            color = VantaColors.White
                        )
                    }
                }

                Spacer(modifier = Modifier.height(32.dp))

                TimerDisplay(
                    duration = duration,
                    color = if (isPaused) VantaColors.RecordingPaused else VantaColors.White
                )

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = if (isPaused) "Пауза" else "Запись...",
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (isPaused) VantaColors.RecordingPaused else VantaColors.RecordingActive
                )
            }
        }
    } else {
        TodayRecordingsContent(
            todayRecordings = todayRecordings,
            onRecordingClick = onRecordingClick,
            modifier = modifier
        )
    }
}

@Composable
private fun StandardModeControls(
    mode: RecordingMode,
    isRecording: Boolean,
    isPaused: Boolean,
    duration: Duration,
    selectedPreset: RecordingPreset?,
    onStartRecording: () -> Unit,
    onToggleRecording: () -> Unit,
    onStopRecording: () -> Unit,
    onShowPresetPicker: () -> Unit
) {
    if (isRecording) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Pause/Resume button
            VantaGlassIconButton(
                icon = if (isPaused) Icons.Default.PlayArrow else Icons.Default.Pause,
                onClick = onToggleRecording,
                size = 48.dp
            )

            // Main pill button with timer
            FloatingMicButton(
                mode = mode,
                isRecording = true,
                isPaused = isPaused,
                duration = duration,
                onClick = onStopRecording
            )

            // Spacer for symmetry
            Spacer(modifier = Modifier.size(48.dp))
        }
    } else {
        FloatingMicButton(
            mode = mode,
            isRecording = false,
            onClick = {
                if (selectedPreset != null) {
                    onStartRecording()
                } else {
                    onShowPresetPicker()
                }
            }
        )
    }
}

// MARK: - Realtime Mode

@Composable
private fun RealtimeModeContent(
    realtimeState: RealtimeState,
    selectedPreset: RecordingPreset?,
    currentTranscription: String,
    totalDuration: Duration,
    currentChunkDuration: Duration,
    vadState: VADState,
    modifier: Modifier = Modifier
) {
    when (realtimeState) {
        is RealtimeState.Recording -> {
            RealtimeRecordingContent(
                selectedPreset = selectedPreset,
                currentTranscription = currentTranscription,
                totalDuration = totalDuration,
                currentChunkDuration = currentChunkDuration,
                vadState = vadState,
                modifier = modifier
            )
        }
        is RealtimeState.Processing -> {
            RealtimeProcessingContent(
                progress = realtimeState.progress,
                chunksCompleted = realtimeState.chunksCompleted,
                totalChunks = realtimeState.totalChunks,
                currentTranscription = currentTranscription,
                modifier = modifier
            )
        }
        is RealtimeState.Merging -> {
            RealtimeMergingContent(modifier = modifier)
        }
        else -> {
            RealtimeIdleContent(modifier = modifier)
        }
    }
}

@Composable
private fun RealtimeRecordingContent(
    selectedPreset: RecordingPreset?,
    currentTranscription: String,
    totalDuration: Duration,
    currentChunkDuration: Duration,
    vadState: VADState,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
    ) {
        // Preset and timer
        Row(verticalAlignment = Alignment.CenterVertically) {
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

            Text(
                text = formatDuration(currentChunkDuration),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                color = VantaColors.BlueVibrant
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

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
private fun RealtimeProcessingContent(
    progress: Float,
    chunksCompleted: Int,
    totalChunks: Int,
    currentTranscription: String,
    modifier: Modifier = Modifier
) {
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
            progress = { progress },
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp)),
            color = VantaColors.PinkVibrant,
            trackColor = VantaColors.DarkSurfaceElevated
        )

        Spacer(modifier = Modifier.height(32.dp))

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
private fun RealtimeMergingContent(modifier: Modifier = Modifier) {
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
private fun RealtimeIdleContent(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
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

@Composable
private fun RealtimeModeControls(
    mode: RecordingMode,
    realtimeState: RealtimeState,
    duration: Duration,
    selectedPreset: RecordingPreset?,
    onStartRecording: () -> Unit,
    onStopRecording: () -> Unit,
    onShowPresetPicker: () -> Unit
) {
    val isRecording = realtimeState is RealtimeState.Recording
    val isProcessing = realtimeState is RealtimeState.Processing
    val isMerging = realtimeState is RealtimeState.Merging

    when {
        isRecording -> {
            FloatingMicButton(
                mode = mode,
                isRecording = true,
                duration = duration,
                onClick = onStopRecording
            )
        }
        isProcessing || isMerging -> {
            FloatingMicButton(
                mode = mode,
                isRecording = false,
                isProcessing = true,
                onClick = { /* Disabled during processing */ }
            )
        }
        else -> {
            FloatingMicButton(
                mode = mode,
                isRecording = false,
                onClick = {
                    if (selectedPreset != null) {
                        onStartRecording()
                    } else {
                        onShowPresetPicker()
                    }
                }
            )
        }
    }
}

// MARK: - Import Mode

@Composable
private fun ImportModeContent(
    todayRecordings: List<com.vanta.speech.core.domain.model.Recording>,
    onRecordingClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    TodayRecordingsContent(
        todayRecordings = todayRecordings,
        onRecordingClick = onRecordingClick,
        emptyMessage = "Импортируйте аудиофайл для транскрипции",
        modifier = modifier
    )
}

@Composable
private fun ImportModeControls(
    mode: RecordingMode,
    onImportClick: () -> Unit
) {
    FloatingMicButton(
        mode = mode,
        isRecording = false,
        onClick = onImportClick
    )
}

// MARK: - Shared Components

@Composable
private fun TodayRecordingsContent(
    todayRecordings: List<com.vanta.speech.core.domain.model.Recording>,
    onRecordingClick: (String) -> Unit,
    emptyMessage: String = "Выберите пресет и нажмите для записи",
    modifier: Modifier = Modifier
) {
    if (todayRecordings.isNotEmpty()) {
        Column(modifier = modifier) {
            Text(
                text = stringResource(R.string.library_today),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = VantaColors.White,
                modifier = Modifier.padding(horizontal = 24.dp)
            )

            Spacer(modifier = Modifier.height(12.dp))

            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(todayRecordings) { recording ->
                    RecordingCard(
                        recording = recording,
                        onClick = { onRecordingClick(recording.id) }
                    )
                }

                item {
                    Spacer(modifier = Modifier.height(160.dp))
                }
            }
        }
    } else {
        Box(
            modifier = modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = Icons.Default.Mic,
                    contentDescription = null,
                    tint = VantaColors.DarkTextSecondary,
                    modifier = Modifier.height(48.dp)
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = emptyMessage,
                    style = MaterialTheme.typography.bodyLarge,
                    color = VantaColors.DarkTextSecondary,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ImportPresetPickerSheet(
    audioData: AudioImporter.ImportedAudio,
    presets: List<RecordingPreset>,
    onPresetSelected: (RecordingPreset) -> Unit,
    onCancel: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onCancel,
        sheetState = sheetState,
        containerColor = VantaColors.DarkSurfaceElevated,
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Выберите пресет",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = VantaColors.White
                )
                IconButton(onClick = onCancel) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Закрыть",
                        tint = VantaColors.DarkTextSecondary
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(VantaColors.DarkSurface)
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    Icons.Default.AudioFile,
                    contentDescription = null,
                    tint = VantaColors.PinkVibrant,
                    modifier = Modifier.size(32.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        audioData.originalFileName,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                        color = VantaColors.White
                    )
                    Text(
                        formatDurationMs(audioData.duration.toMillis()),
                        style = MaterialTheme.typography.bodySmall,
                        color = VantaColors.DarkTextSecondary
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                presets.forEach { preset ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(VantaColors.DarkSurface)
                            .clickable { onPresetSelected(preset) }
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(VantaColors.PinkVibrant.copy(alpha = 0.15f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                preset.icon,
                                contentDescription = null,
                                tint = VantaColors.PinkVibrant,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                        Text(
                            preset.displayName,
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                            color = VantaColors.White
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

private fun formatDuration(duration: Duration): String {
    val minutes = duration.toMinutes() % 60
    val seconds = duration.seconds % 60
    return String.format(Locale.US, "%02d:%02d", minutes, seconds)
}

private fun formatDurationMs(durationMs: Long): String {
    val totalSeconds = durationMs / 1000
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.US, "%02d:%02d", minutes, seconds)
    }
}
