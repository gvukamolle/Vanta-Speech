package com.vanta.speech.feature.recording

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import com.vanta.speech.core.domain.model.RecordingPreset
import com.vanta.speech.core.domain.model.RecordingState
import com.vanta.speech.ui.components.CircularAudioVisualizer
import com.vanta.speech.ui.components.PresetPicker
import com.vanta.speech.ui.components.PresetPickerBottomSheet
import com.vanta.speech.ui.components.RecordButton
import com.vanta.speech.ui.components.RecordingCard
import com.vanta.speech.ui.components.TimerDisplay
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.components.VantaGlassIconButton
import com.vanta.speech.ui.theme.VantaColors
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingScreen(
    viewModel: RecordingViewModel = hiltViewModel()
) {
    val recordingState by viewModel.recordingState.collectAsStateWithLifecycle()
    val selectedPreset by viewModel.selectedPreset.collectAsStateWithLifecycle()
    val duration by viewModel.duration.collectAsStateWithLifecycle()
    val audioLevel by viewModel.audioLevel.collectAsStateWithLifecycle()
    val todayRecordings by viewModel.todayRecordings.collectAsStateWithLifecycle()

    // Import state
    val isImporting by viewModel.isImporting.collectAsStateWithLifecycle()
    val importError by viewModel.importError.collectAsStateWithLifecycle()
    val importedAudioData by viewModel.importedAudioData.collectAsStateWithLifecycle()

    var showPresetPicker by remember { mutableStateOf(false) }
    var showImportPresetPicker by remember { mutableStateOf(false) }

    val isRecording = recordingState is RecordingState.Recording
    val isPaused = (recordingState as? RecordingState.Recording)?.isPaused == true

    // File picker launcher
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let { viewModel.importAudio(it) }
    }

    // Show preset picker when import is complete
    if (importedAudioData != null && !showImportPresetPicker) {
        showImportPresetPicker = true
    }

    VantaBackground {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 24.dp)
        ) {
            // Header
            Text(
                text = stringResource(R.string.nav_recording),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = VantaColors.White,
                modifier = Modifier.padding(horizontal = 24.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Show preset picker only when not recording
            if (!isRecording) {
                PresetPicker(
                    presets = RecordingPreset.entries,
                    selectedPreset = selectedPreset,
                    onPresetSelected = { viewModel.selectPreset(it) }
                )

                Spacer(modifier = Modifier.height(24.dp))
            }

            // Recording UI or today's recordings
            if (isRecording) {
                // Active recording UI
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        // Preset name
                        selectedPreset?.let { preset ->
                            Row(
                                verticalAlignment = Alignment.CenterVertically
                            ) {
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

                        // Timer
                        TimerDisplay(
                            duration = duration,
                            color = if (isPaused) VantaColors.RecordingPaused else VantaColors.White
                        )

                        Spacer(modifier = Modifier.height(16.dp))

                        // Status
                        Text(
                            text = if (isPaused) "Пауза" else "Запись...",
                            style = MaterialTheme.typography.bodyLarge,
                            color = if (isPaused) VantaColors.RecordingPaused else VantaColors.RecordingActive
                        )
                    }
                }
            } else {
                // Today's recordings list
                if (todayRecordings.isNotEmpty()) {
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
                                onClick = { /* TODO: Navigate to detail */ }
                            )
                        }

                        item {
                            Spacer(modifier = Modifier.height(160.dp))
                        }
                    }
                } else {
                    // Empty state
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(
                                imageVector = Icons.Default.Mic,
                                contentDescription = null,
                                tint = VantaColors.DarkTextSecondary,
                                modifier = Modifier.height(48.dp)
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Text(
                                text = "Выберите пресет и нажмите для записи",
                                style = MaterialTheme.typography.bodyLarge,
                                color = VantaColors.DarkTextSecondary
                            )
                        }
                    }
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
                isActive = isRecording && !isPaused,
                modifier = Modifier.height(200.dp)
            )

            if (isRecording) {
                // Recording controls
                Row(
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Pause/Resume button
                    VantaGlassIconButton(
                        icon = if (isPaused) Icons.Default.PlayArrow else Icons.Default.Pause,
                        onClick = { viewModel.toggleRecording() },
                        size = 56.dp
                    )

                    // Stop button
                    RecordButton(
                        isRecording = true,
                        isPaused = isPaused,
                        onClick = { viewModel.stopRecording() }
                    )

                    // Spacer for symmetry
                    Spacer(modifier = Modifier.size(56.dp))
                }
            } else {
                // Start recording button and import button
                Row(
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Import button
                    VantaGlassIconButton(
                        icon = Icons.Default.FileOpen,
                        onClick = {
                            filePickerLauncher.launch(AudioImporter.AUDIO_MIME_TYPES)
                        },
                        size = 56.dp
                    )

                    // Start recording button
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

                    // Spacer for symmetry
                    Spacer(modifier = Modifier.size(56.dp))
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

    // Import preset picker bottom sheet
    if (showImportPresetPicker && importedAudioData != null) {
        ImportPresetPickerSheet(
            audioData = importedAudioData!!,
            presets = RecordingPreset.entries.toList(),
            onPresetSelected = { preset ->
                viewModel.finalizeImport(preset)
                showImportPresetPicker = false
            },
            onCancel = {
                viewModel.cancelImport()
                showImportPresetPicker = false
            }
        )
    }

    // Import error dialog
    importError?.let { error ->
        AlertDialog(
            onDismissRequest = { viewModel.clearImportError() },
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
                TextButton(onClick = { viewModel.clearImportError() }) {
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
            // Header
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

            // File info
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
                        formatDuration(audioData.duration.toMillis()),
                        style = MaterialTheme.typography.bodySmall,
                        color = VantaColors.DarkTextSecondary
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Presets list
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

private fun formatDuration(durationMs: Long): String {
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
