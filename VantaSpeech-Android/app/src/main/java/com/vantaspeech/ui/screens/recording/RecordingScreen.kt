package com.vantaspeech.ui.screens.recording

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.vantaspeech.R
import com.vantaspeech.audio.RecordingState
import com.vantaspeech.ui.theme.RecordingRed
import com.vantaspeech.ui.theme.RecordingRedLight

@Composable
fun RecordingScreen(
    viewModel: RecordingViewModel = hiltViewModel()
) {
    val recordingState by viewModel.recordingState.collectAsState()
    val duration by viewModel.duration.collectAsState()
    val audioLevel by viewModel.audioLevel.collectAsState()
    val hasPermission by viewModel.hasPermission.collectAsState()

    var showPermissionDenied by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        viewModel.updatePermissionStatus()
        if (isGranted) {
            viewModel.toggleRecording()
        } else {
            showPermissionDenied = true
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Status text
        Text(
            text = when (recordingState) {
                RecordingState.RECORDING -> stringResource(R.string.recording_recording)
                RecordingState.PAUSED -> stringResource(R.string.recording_paused)
                else -> stringResource(R.string.recording_tap_to_record)
            },
            style = MaterialTheme.typography.titleMedium,
            color = when (recordingState) {
                RecordingState.RECORDING -> RecordingRed
                RecordingState.PAUSED -> MaterialTheme.colorScheme.onSurfaceVariant
                else -> MaterialTheme.colorScheme.onSurface
            }
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Duration display
        Text(
            text = formatDuration(duration),
            style = MaterialTheme.typography.displayLarge.copy(
                fontWeight = FontWeight.Light,
                fontSize = 72.sp
            ),
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Audio level visualizer
        if (recordingState == RecordingState.RECORDING || recordingState == RecordingState.PAUSED) {
            AudioLevelVisualizer(
                level = audioLevel,
                isActive = recordingState == RecordingState.RECORDING
            )
            Spacer(modifier = Modifier.height(32.dp))
        }

        // Recording button
        RecordButton(
            isRecording = recordingState == RecordingState.RECORDING || recordingState == RecordingState.PAUSED,
            onClick = {
                if (!hasPermission) {
                    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                } else {
                    viewModel.toggleRecording()
                }
            }
        )

        // Controls for active recording
        if (recordingState == RecordingState.RECORDING || recordingState == RecordingState.PAUSED) {
            Spacer(modifier = Modifier.height(24.dp))

            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Pause/Resume button
                IconButton(
                    onClick = { viewModel.togglePause() },
                    modifier = Modifier
                        .size(56.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant,
                            CircleShape
                        )
                ) {
                    Icon(
                        imageVector = if (recordingState == RecordingState.PAUSED) {
                            Icons.Default.PlayArrow
                        } else {
                            Icons.Default.Pause
                        },
                        contentDescription = if (recordingState == RecordingState.PAUSED) {
                            stringResource(R.string.recording_resume)
                        } else {
                            stringResource(R.string.recording_pause)
                        },
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Stop button
                Button(
                    onClick = { viewModel.stopRecording() },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error
                    ),
                    modifier = Modifier.height(48.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Stop,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(stringResource(R.string.recording_stop))
                }
            }
        }

        // Permission denied message
        if (showPermissionDenied) {
            Spacer(modifier = Modifier.height(24.dp))
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = stringResource(R.string.permission_audio_title),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = stringResource(R.string.permission_audio_message),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
        }
    }
}

@Composable
private fun RecordButton(
    isRecording: Boolean,
    onClick: () -> Unit
) {
    val scale by animateFloatAsState(
        targetValue = if (isRecording) 0.85f else 1f,
        animationSpec = tween(150),
        label = "record_button_scale"
    )

    Box(
        modifier = Modifier
            .size(120.dp)
            .scale(scale)
            .clip(CircleShape)
            .background(
                brush = Brush.radialGradient(
                    colors = listOf(RecordingRedLight, RecordingRed)
                )
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick
            ),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(if (isRecording) 40.dp else 50.dp)
                .clip(if (isRecording) RoundedCornerShape(8.dp) else CircleShape)
                .background(Color.White)
        )
    }
}

@Composable
private fun AudioLevelVisualizer(
    level: Float,
    isActive: Boolean,
    modifier: Modifier = Modifier
) {
    val barCount = 30
    val animatedLevel by animateFloatAsState(
        targetValue = if (isActive) level else 0f,
        animationSpec = tween(100),
        label = "audio_level"
    )

    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(60.dp)
            .padding(horizontal = 32.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        repeat(barCount) { index ->
            val distanceFromCenter = kotlin.math.abs(index - barCount / 2f) / (barCount / 2f)
            val barHeight = ((1f - distanceFromCenter * 0.5f) * animatedLevel * 60).coerceIn(4f, 60f)

            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(barHeight.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(
                        if (isActive) RecordingRed.copy(alpha = 0.3f + animatedLevel * 0.7f)
                        else MaterialTheme.colorScheme.surfaceVariant
                    )
            )
        }
    }
}

private fun formatDuration(seconds: Long): String {
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    val secs = seconds % 60

    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes, secs)
    } else {
        String.format("%02d:%02d", minutes, secs)
    }
}
