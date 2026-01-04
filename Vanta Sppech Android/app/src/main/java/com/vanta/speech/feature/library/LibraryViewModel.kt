package com.vanta.speech.feature.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.domain.model.Recording
import com.vanta.speech.core.domain.repository.RecordingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

data class RecordingsByDate(
    val date: LocalDate,
    val recordings: List<Recording>
)

@HiltViewModel
class LibraryViewModel @Inject constructor(
    private val recordingRepository: RecordingRepository
) : ViewModel() {

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    val recordingsGroupedByDate: StateFlow<List<RecordingsByDate>> = recordingRepository
        .getAllRecordings()
        .map { recordings ->
            recordings
                .groupBy { recording ->
                    recording.createdAt
                        .atZone(ZoneId.systemDefault())
                        .toLocalDate()
                }
                .map { (date, recordings) ->
                    RecordingsByDate(
                        date = date,
                        recordings = recordings.sortedByDescending { it.createdAt }
                    )
                }
                .sortedByDescending { it.date }
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    val totalRecordingsCount: StateFlow<Int> = recordingRepository
        .getAllRecordings()
        .map { it.size }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = 0
        )

    fun deleteRecording(recordingId: String) {
        viewModelScope.launch {
            recordingRepository.deleteRecording(recordingId)
        }
    }

    fun searchRecordings(query: String): StateFlow<List<Recording>> {
        return recordingRepository
            .searchRecordings(query)
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5000),
                initialValue = emptyList()
            )
    }
}
