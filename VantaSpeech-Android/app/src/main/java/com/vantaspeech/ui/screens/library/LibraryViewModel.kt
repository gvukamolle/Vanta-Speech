package com.vantaspeech.ui.screens.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vantaspeech.data.model.Recording
import com.vantaspeech.data.repository.RecordingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

@HiltViewModel
class LibraryViewModel @Inject constructor(
    private val recordingRepository: RecordingRepository
) : ViewModel() {

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    @OptIn(ExperimentalCoroutinesApi::class)
    val recordings: StateFlow<List<Recording>> = _searchQuery
        .flatMapLatest { query ->
            if (query.isBlank()) {
                recordingRepository.getAllRecordings()
            } else {
                recordingRepository.searchRecordings(query)
            }
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    val recentRecording: StateFlow<Recording?> = recordingRepository
        .getMostRecentRecordingFlow()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = null
        )

    fun onSearchQueryChange(query: String) {
        _searchQuery.value = query
    }

    fun deleteRecording(recording: Recording) {
        viewModelScope.launch {
            // Delete audio file
            try {
                File(recording.audioFilePath).delete()
            } catch (e: Exception) {
                // Ignore file deletion errors
            }

            // Delete from database
            recordingRepository.deleteRecording(recording)
        }
    }

    fun renameRecording(recording: Recording, newTitle: String) {
        viewModelScope.launch {
            recordingRepository.updateRecording(recording.copy(title = newTitle))
        }
    }
}
