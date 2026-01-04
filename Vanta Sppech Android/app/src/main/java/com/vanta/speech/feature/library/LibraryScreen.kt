package com.vanta.speech.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vanta.speech.R
import com.vanta.speech.ui.components.RecordingCard
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.theme.VantaColors
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun LibraryScreen(
    viewModel: LibraryViewModel = hiltViewModel(),
    onRecordingClick: (String) -> Unit
) {
    val recordingsGrouped by viewModel.recordingsGroupedByDate.collectAsStateWithLifecycle()

    VantaBackground {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 24.dp)
        ) {
            // Header
            Text(
                text = stringResource(R.string.nav_library),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = VantaColors.White,
                modifier = Modifier.padding(horizontal = 24.dp)
            )

            Spacer(modifier = Modifier.height(24.dp))

            if (recordingsGrouped.isEmpty()) {
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
                            imageVector = Icons.Default.Folder,
                            contentDescription = null,
                            tint = VantaColors.DarkTextSecondary,
                            modifier = Modifier.height(48.dp)
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = stringResource(R.string.library_empty),
                            style = MaterialTheme.typography.bodyLarge,
                            color = VantaColors.DarkTextSecondary
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    recordingsGrouped.forEach { group ->
                        item {
                            Text(
                                text = formatDateHeader(group.date),
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = VantaColors.DarkTextSecondary,
                                modifier = Modifier.padding(vertical = 8.dp, horizontal = 8.dp)
                            )
                        }

                        items(group.recordings) { recording ->
                            RecordingCard(
                                recording = recording,
                                onClick = { onRecordingClick(recording.id) }
                            )
                        }
                    }

                    // Bottom spacing
                    item {
                        Spacer(modifier = Modifier.height(16.dp))
                    }
                }
            }
        }
    }
}

private fun formatDateHeader(date: LocalDate): String {
    val today = LocalDate.now()
    val yesterday = today.minusDays(1)

    return when (date) {
        today -> "Сегодня"
        yesterday -> "Вчера"
        else -> {
            val formatter = DateTimeFormatter.ofPattern("d MMMM", Locale("ru"))
            date.format(formatter)
        }
    }
}
