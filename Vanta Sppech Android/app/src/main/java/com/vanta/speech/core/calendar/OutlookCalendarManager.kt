package com.vanta.speech.core.calendar

import android.app.Activity
import android.util.Log
import com.vanta.speech.core.calendar.model.GraphEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Date
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Main coordinator for Outlook Calendar integration
 * Android equivalent of iOS OutlookCalendarManager
 */
@Singleton
class OutlookCalendarManager @Inject constructor(
    val authManager: MSALAuthManager,
    private val calendarService: GraphCalendarService
) {
    companion object {
        private const val TAG = "OutlookCalendarManager"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // State
    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _lastSyncDate = MutableStateFlow<Date?>(null)
    val lastSyncDate: StateFlow<Date?> = _lastSyncDate.asStateFlow()

    private val _cachedEvents = MutableStateFlow<List<GraphEvent>>(emptyList())
    val cachedEvents: StateFlow<List<GraphEvent>> = _cachedEvents.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    // User info from auth manager
    val userName: StateFlow<String?> = authManager.userName
    val userEmail: StateFlow<String?> = authManager.userEmail

    init {
        // Observe auth state
        scope.launch {
            authManager.isSignedIn.collect { signedIn ->
                _isConnected.value = signedIn

                if (signedIn) {
                    // Auto-sync on connection
                    performSync()
                } else {
                    // Clear on disconnect
                    _cachedEvents.value = emptyList()
                    _lastSyncDate.value = null
                }
            }
        }

        // Forward auth errors
        scope.launch {
            authManager.error.collect { authError ->
                _error.value = authError
            }
        }
    }

    /**
     * Connect to Outlook Calendar
     * @param activity Activity for presenting OAuth UI
     */
    suspend fun connect(activity: Activity) {
        try {
            authManager.signIn(activity)
            Log.d(TAG, "Connected successfully")
        } catch (e: MSALAuthError.UserCanceled) {
            Log.d(TAG, "User canceled sign in")
            // Don't show error for user cancel
        } catch (e: Exception) {
            _error.value = e.message
            Log.e(TAG, "Connection failed: ${e.message}")
        }
    }

    /**
     * Disconnect from Outlook Calendar
     */
    suspend fun disconnect() {
        try {
            authManager.signOut()
            Log.d(TAG, "Disconnected successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error: ${e.message}")
            // State is already cleared by signOut
        }
    }

    /**
     * Perform calendar sync
     * @return true if sync was successful
     */
    suspend fun performSync(): Boolean {
        if (!_isConnected.value) {
            Log.w(TAG, "Cannot sync: not connected")
            return false
        }

        if (_isSyncing.value) {
            Log.w(TAG, "Sync already in progress")
            return false
        }

        _isSyncing.value = true
        _error.value = null

        return try {
            // Fetch events for next 7 days
            val calendar = java.util.Calendar.getInstance()
            val startDate = calendar.time
            calendar.add(java.util.Calendar.DAY_OF_MONTH, 7)
            val endDate = calendar.time

            val events = calendarService.fetchEvents(startDate, endDate)

            _cachedEvents.value = events.sortedBy { it.startDate }
            _lastSyncDate.value = Date()

            Log.d(TAG, "Sync completed: ${events.size} events cached")
            true
        } catch (e: MSALAuthError.InteractionRequired) {
            _error.value = "Требуется повторный вход в Outlook"
            Log.w(TAG, "Sync failed: interaction required")
            false
        } catch (e: Exception) {
            _error.value = e.message
            Log.e(TAG, "Sync failed: ${e.message}")
            false
        } finally {
            _isSyncing.value = false
        }
    }

    /**
     * Get today's events
     */
    suspend fun getTodayEvents(): List<GraphEvent> {
        return try {
            calendarService.fetchTodayEvents()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to fetch today's events: ${e.message}")
            emptyList()
        }
    }

    /**
     * Get events for a date range
     */
    suspend fun getEvents(from: Date, to: Date): List<GraphEvent> {
        return try {
            calendarService.fetchEvents(from, to)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to fetch events: ${e.message}")
            emptyList()
        }
    }

    /**
     * Find event overlapping with the specified time
     * Useful for auto-linking recordings to meetings
     */
    fun findOverlappingEvent(at: Date, duration: Long): GraphEvent? {
        val endDate = Date(at.time + duration)

        return _cachedEvents.value.firstOrNull { event ->
            val eventStart = event.startDate ?: return@firstOrNull false
            val eventEnd = event.endDate ?: return@firstOrNull false

            // Check time interval overlap
            eventStart.time <= endDate.time && eventEnd.time >= at.time
        }
    }

    /**
     * Get the next upcoming event
     */
    fun getNextEvent(): GraphEvent? {
        val now = Date()
        return _cachedEvents.value.firstOrNull { event ->
            val eventStart = event.startDate ?: return@firstOrNull false
            eventStart.time > now.time
        }
    }

    /**
     * Get current ongoing event
     */
    fun getCurrentEvent(): GraphEvent? {
        val now = Date()
        return _cachedEvents.value.firstOrNull { event ->
            val eventStart = event.startDate ?: return@firstOrNull false
            val eventEnd = event.endDate ?: return@firstOrNull false
            eventStart.time <= now.time && eventEnd.time >= now.time
        }
    }

    /**
     * Clear any errors
     */
    fun clearError() {
        _error.value = null
        authManager.clearError()
    }
}

/**
 * Outlook integration errors
 */
sealed class OutlookError : Exception() {
    data object NotConnected : OutlookError() {
        private fun readResolve(): Any = NotConnected
        override val message = "Outlook Calendar не подключён"
    }

    data class SyncFailed(override val cause: Throwable) : OutlookError() {
        override val message = "Ошибка синхронизации: ${cause.message}"
    }
}
