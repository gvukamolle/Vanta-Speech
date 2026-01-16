package com.vanta.speech.core.eas

import com.vanta.speech.core.auth.SecurePreferencesManager
import com.vanta.speech.core.eas.api.EASClient
import com.vanta.speech.core.eas.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.*
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manager for Exchange ActiveSync calendar operations
 */
@Singleton
class EASCalendarManager @Inject constructor(
    private val client: EASClient,
    private val securePreferencesManager: SecurePreferencesManager
) {
    // MARK: - State

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _cachedEvents = MutableStateFlow<List<EASCalendarEvent>>(emptyList())
    val cachedEvents: StateFlow<List<EASCalendarEvent>> = _cachedEvents.asStateFlow()

    private val _lastError = MutableStateFlow<EASError?>(null)
    val lastError: StateFlow<EASError?> = _lastError.asStateFlow()

    private val _lastSyncDate = MutableStateFlow<Long?>(null)
    val lastSyncDate: StateFlow<Long?> = _lastSyncDate.asStateFlow()

    private var syncState: EASSyncState = EASSyncState.INITIAL

    init {
        // Load saved state
        syncState = securePreferencesManager.loadEASSyncState() ?: EASSyncState.INITIAL
        _isConnected.value = securePreferencesManager.hasEASCredentials()
        _lastSyncDate.value = syncState.lastSyncDate
    }

    // MARK: - Public API

    /**
     * Connect with new credentials
     */
    suspend fun connect(serverURL: String, username: String, password: String): Boolean {
        val deviceId = securePreferencesManager.getOrCreateEASDeviceId()
        val credentials = EASCredentials(
            serverURL = serverURL.trim(),
            username = username.trim(),
            password = password,
            deviceId = deviceId
        )

        // Save credentials first
        if (!securePreferencesManager.saveEASCredentials(credentials)) {
            _lastError.value = EASError.Unknown("Failed to save credentials")
            return false
        }

        // Test connection
        val testResult = client.testConnection()
        if (testResult.isFailure) {
            val error = testResult.exceptionOrNull() as? EASError
                ?: EASError.Unknown("Connection failed")
            _lastError.value = error
            if (error.shouldClearCredentials) {
                securePreferencesManager.deleteEASCredentials()
            }
            return false
        }

        val serverInfo = testResult.getOrNull()!!
        if (!serverInfo.supportsVersion14) {
            _lastError.value = EASError.ServerError(0, "Server does not support EAS 14.1")
            securePreferencesManager.deleteEASCredentials()
            return false
        }

        // Discover calendar folder
        val discoverResult = discoverCalendarFolder()
        if (!discoverResult) {
            return false
        }

        _isConnected.value = true
        _lastError.value = null
        return true
    }

    /**
     * Disconnect and clear credentials
     */
    fun disconnect() {
        securePreferencesManager.clearAllEASData()
        _isConnected.value = false
        _cachedEvents.value = emptyList()
        syncState = EASSyncState.INITIAL
        _lastError.value = null
        _lastSyncDate.value = null
    }

    /**
     * Sync calendar events from server
     */
    suspend fun syncEvents() {
        if (!_isConnected.value) {
            _lastError.value = EASError.NoCredentials
            return
        }

        if (_isSyncing.value) return

        _isSyncing.value = true
        _lastError.value = null

        try {
            // Ensure we have calendar folder
            if (!syncState.hasDiscoveredCalendar) {
                if (!discoverCalendarFolder()) {
                    _isSyncing.value = false
                    return
                }
            }

            val folderId = syncState.calendarFolderId
                ?: throw EASError.CalendarFolderNotFound

            // Perform sync
            val result = client.sync(
                folderId = folderId,
                syncKey = syncState.calendarSyncKey,
                getChanges = true
            )

            if (result.isFailure) {
                val error = result.exceptionOrNull() as? EASError
                    ?: EASError.Unknown("Sync failed")
                _lastError.value = error
                if (error.shouldClearCredentials) {
                    disconnect()
                }
                _isSyncing.value = false
                return
            }

            val response = result.getOrNull()!!

            // Update sync state
            val now = System.currentTimeMillis()
            syncState = syncState.copy(
                calendarSyncKey = response.syncKey,
                lastSyncDate = now
            )
            securePreferencesManager.saveEASSyncState(syncState)
            _lastSyncDate.value = now

            // Update events
            if (syncState.isInitialSync) {
                _cachedEvents.value = response.events
            } else {
                mergeEvents(response.events)
            }

            // Handle more available
            if (response.moreAvailable) {
                syncEvents() // Recursively sync more
            }

        } catch (e: EASError) {
            _lastError.value = e
            if (e.shouldClearCredentials) {
                disconnect()
            }
        } catch (e: Exception) {
            _lastError.value = EASError.Unknown(e.message ?: "Unknown error")
        }

        _isSyncing.value = false
    }

    /**
     * Create a calendar event (meeting summary)
     */
    suspend fun createEvent(event: EASCalendarEvent): Result<String> {
        if (!_isConnected.value) {
            return Result.failure(EASError.NoCredentials)
        }

        val folderId = syncState.calendarFolderId
            ?: return Result.failure(EASError.CalendarFolderNotFound)

        val eventToCreate = if (event.clientId == null) {
            event.copy(clientId = UUID.randomUUID().toString())
        } else {
            event
        }

        val result = client.sync(
            folderId = folderId,
            syncKey = syncState.calendarSyncKey,
            getChanges = false,
            addItems = listOf(eventToCreate)
        )

        if (result.isFailure) {
            return Result.failure(
                result.exceptionOrNull() as? EASError
                    ?: EASError.Unknown("Create event failed")
            )
        }

        val response = result.getOrNull()!!
        syncState = syncState.copy(calendarSyncKey = response.syncKey)
        securePreferencesManager.saveEASSyncState(syncState)

        return Result.success(eventToCreate.clientId ?: "")
    }

    /**
     * Create meeting summary from original event
     */
    suspend fun createMeetingSummary(
        originalEvent: EASCalendarEvent,
        summaryHtml: String
    ): Result<String> {
        val summaryEvent = EASCalendarEvent.createMeetingSummary(
            originalEvent = originalEvent,
            summaryHtml = summaryHtml
        )
        return createEvent(summaryEvent)
    }

    // MARK: - Private Methods

    private suspend fun discoverCalendarFolder(): Boolean {
        val result = client.folderSync(syncState.folderSyncKey)

        if (result.isFailure) {
            val error = result.exceptionOrNull() as? EASError
                ?: EASError.Unknown("Folder sync failed")
            _lastError.value = error
            return false
        }

        val response = result.getOrNull()!!

        val calendarFolder = response.calendarFolder
        if (calendarFolder == null) {
            _lastError.value = EASError.CalendarFolderNotFound
            return false
        }

        syncState = syncState.copy(
            folderSyncKey = response.syncKey,
            calendarFolderId = calendarFolder.serverId,
            calendarSyncKey = "0"
        )
        securePreferencesManager.saveEASSyncState(syncState)

        return true
    }

    private fun mergeEvents(newEvents: List<EASCalendarEvent>) {
        val eventMap = _cachedEvents.value.associateBy { it.id }.toMutableMap()
        newEvents.forEach { event ->
            eventMap[event.id] = event
        }
        _cachedEvents.value = eventMap.values.sortedBy { it.startTimeMillis }
    }

    // MARK: - Convenience

    /**
     * Get events for a specific date
     */
    fun eventsForDate(date: Date): List<EASCalendarEvent> {
        val calendar = Calendar.getInstance()
        calendar.time = date
        val year = calendar.get(Calendar.YEAR)
        val dayOfYear = calendar.get(Calendar.DAY_OF_YEAR)

        return _cachedEvents.value.filter { event ->
            val eventCalendar = Calendar.getInstance()
            eventCalendar.time = event.startTime
            eventCalendar.get(Calendar.YEAR) == year &&
                    eventCalendar.get(Calendar.DAY_OF_YEAR) == dayOfYear
        }
    }

    /**
     * Get today's events
     */
    val todayEvents: List<EASCalendarEvent>
        get() = eventsForDate(Date())

    /**
     * Get upcoming events (next 7 days)
     */
    val upcomingEvents: List<EASCalendarEvent>
        get() {
            val now = System.currentTimeMillis()
            val weekFromNow = now + 7 * 24 * 60 * 60 * 1000L
            return _cachedEvents.value.filter { event ->
                event.startTimeMillis in now..weekFromNow
            }
        }
}
