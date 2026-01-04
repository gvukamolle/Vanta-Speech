package com.vanta.speech.core.ews

import android.util.Log
import com.vanta.speech.core.ews.model.EWSError
import com.vanta.speech.core.ews.model.EWSEvent
import com.vanta.speech.core.ews.model.EWSContact
import com.vanta.speech.core.ews.model.EWSNewEmail
import com.vanta.speech.core.ews.model.EWSNewEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * High-level coordinator for EWS calendar integration
 */
@Singleton
class EWSCalendarManager @Inject constructor(
    private val authManager: EWSAuthManager
) {
    companion object {
        private const val TAG = "EWSCalendarManager"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // MARK: - State

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _lastSyncDate = MutableStateFlow<Date?>(null)
    val lastSyncDate: StateFlow<Date?> = _lastSyncDate.asStateFlow()

    private val _cachedEvents = MutableStateFlow<List<EWSEvent>>(emptyList())
    val cachedEvents: StateFlow<List<EWSEvent>> = _cachedEvents.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val _serverURL = MutableStateFlow<String?>(null)
    val serverURL: StateFlow<String?> = _serverURL.asStateFlow()

    private val _userEmail = MutableStateFlow<String?>(null)
    val userEmail: StateFlow<String?> = _userEmail.asStateFlow()

    private var service: EWSCalendarService? = null

    init {
        setupBindings()
        restoreConnection()
    }

    // MARK: - Connection

    /**
     * Connect to EWS server with credentials
     */
    suspend fun connect(
        serverURL: String,
        domain: String,
        username: String,
        password: String
    ): Boolean {
        _lastError.value = null

        val success = authManager.authenticate(
            serverURL = serverURL,
            domain = domain,
            username = username,
            password = password
        )

        if (success) {
            setupService()
            syncEvents()
        } else {
            _lastError.value = authManager.lastError.value
        }

        return success
    }

    /**
     * Disconnect and clear all data
     */
    fun disconnect() {
        authManager.signOut()
        service = null
        _cachedEvents.value = emptyList()
        _lastSyncDate.value = null
        _serverURL.value = null
        _userEmail.value = null
        _isConnected.value = false
    }

    // MARK: - Sync

    /**
     * Sync calendar events for today and upcoming week
     */
    suspend fun syncEvents() {
        if (!_isConnected.value || service == null) return

        _isSyncing.value = true
        _lastError.value = null

        try {
            val calendar = Calendar.getInstance()
            calendar.set(Calendar.HOUR_OF_DAY, 0)
            calendar.set(Calendar.MINUTE, 0)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            val startOfDay = calendar.time

            calendar.add(Calendar.DAY_OF_MONTH, 7)
            val endDate = calendar.time

            val events = service!!.findEvents(from = startOfDay, to = endDate)

            _cachedEvents.value = events.sortedBy { it.startDate }
            _lastSyncDate.value = Date()

            Log.d(TAG, "Synced ${events.size} events")
        } catch (e: Exception) {
            _lastError.value = e.message
            Log.e(TAG, "Sync failed: ${e.message}")
        }

        _isSyncing.value = false
    }

    /**
     * Get events for today
     */
    fun getTodayEvents(): List<EWSEvent> {
        val calendar = Calendar.getInstance()
        val today = calendar.get(Calendar.DAY_OF_YEAR)
        val year = calendar.get(Calendar.YEAR)

        return _cachedEvents.value.filter { event ->
            val eventCal = Calendar.getInstance()
            eventCal.time = event.startDate
            eventCal.get(Calendar.DAY_OF_YEAR) == today && eventCal.get(Calendar.YEAR) == year
        }
    }

    /**
     * Get current or next event (within 15 minutes)
     */
    fun getCurrentOrNextEvent(): EWSEvent? {
        val now = Date()
        val threshold = Date(now.time + 15 * 60 * 1000) // 15 minutes ahead

        // First check for ongoing event
        val current = _cachedEvents.value.firstOrNull { event ->
            event.startDate.time <= now.time && event.endDate.time > now.time
        }
        if (current != null) return current

        // Then check for upcoming event
        return _cachedEvents.value.firstOrNull { event ->
            event.startDate.time > now.time && event.startDate.time <= threshold.time
        }
    }

    // MARK: - Event Operations

    /**
     * Update event body with meeting summary
     */
    suspend fun updateEventBody(
        event: EWSEvent,
        htmlContent: String,
        notifyAttendees: Boolean = false
    ) {
        val svc = service ?: throw EWSError.NotConfigured

        // Append to existing body or replace
        val newBody = if (!event.bodyHtml.isNullOrEmpty()) {
            "${event.bodyHtml}<hr/>$htmlContent"
        } else {
            htmlContent
        }

        val newChangeKey = svc.updateEventBody(
            itemId = event.itemId,
            changeKey = event.changeKey,
            bodyHtml = newBody,
            notifyAttendees = notifyAttendees
        )

        // Update cached event with new changeKey
        val index = _cachedEvents.value.indexOfFirst { it.itemId == event.itemId }
        if (index >= 0) {
            val updated = event.copy(
                changeKey = newChangeKey,
                bodyHtml = newBody
            )
            val mutableList = _cachedEvents.value.toMutableList()
            mutableList[index] = updated
            _cachedEvents.value = mutableList
        }

        Log.d(TAG, "Updated event body for: ${event.subject}")
    }

    /**
     * Send email to event attendees
     */
    suspend fun sendSummaryToAttendees(
        event: EWSEvent,
        subject: String,
        htmlContent: String,
        includeOptional: Boolean = false
    ) {
        val svc = service ?: throw EWSError.NotConfigured

        val recipients = event.attendees
            .filter { it.isRequired || includeOptional }
            .map { it.email }
            .toMutableList()

        // Add organizer if not in list
        event.organizerEmail?.let { organizer ->
            if (!recipients.contains(organizer)) {
                recipients.add(organizer)
            }
        }

        if (recipients.isEmpty()) {
            throw EWSError.ServerError("Нет получателей для отправки")
        }

        val email = EWSNewEmail(
            toRecipients = recipients,
            subject = subject,
            bodyHtml = htmlContent
        )

        svc.sendEmail(email)

        Log.d(TAG, "Sent email to ${recipients.size} recipients")
    }

    /**
     * Create a new calendar event
     */
    suspend fun createEvent(event: EWSNewEvent): String {
        val svc = service ?: throw EWSError.NotConfigured

        val itemId = svc.createEvent(event)
        syncEvents() // Refresh cache

        Log.d(TAG, "Created event: ${event.subject}")
        return itemId
    }

    /**
     * Search contacts for autocomplete
     */
    suspend fun searchContacts(query: String): List<EWSContact> {
        val svc = service ?: throw EWSError.NotConfigured
        return svc.resolveNames(query)
    }

    /**
     * Clear any errors
     */
    fun clearError() {
        _lastError.value = null
        authManager.clearError()
    }

    // MARK: - Private

    private fun setupBindings() {
        scope.launch {
            authManager.isAuthenticated.collect { isAuth ->
                _isConnected.value = isAuth
            }
        }

        scope.launch {
            authManager.credentials.collect { creds ->
                _serverURL.value = creds?.serverURL
                _userEmail.value = creds?.email ?: creds?.username
            }
        }
    }

    private fun restoreConnection() {
        if (authManager.isAuthenticated.value) {
            _isConnected.value = true
            _serverURL.value = authManager.credentials.value?.serverURL
            _userEmail.value = authManager.credentials.value?.email
                ?: authManager.credentials.value?.username

            scope.launch {
                setupService()
                syncEvents()
            }
        }
    }

    private fun setupService() {
        try {
            val client = authManager.createClient()
            service = EWSCalendarService(client)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create service: ${e.message}")
            _lastError.value = e.message
        }
    }

    // MARK: - Summary HTML Builder

    /**
     * Build HTML summary for event body
     */
    fun buildSummaryHTML(
        title: String,
        summary: String,
        transcription: String? = null,
        date: Date = Date()
    ): String {
        val formatter = SimpleDateFormat("dd MMMM yyyy, HH:mm", Locale("ru"))

        val transcriptionSection = if (!transcription.isNullOrEmpty()) {
            """
            <details style="margin-top: 24px;">
                <summary style="cursor: pointer; color: #007AFF; font-weight: 600;">
                    Полная транскрипция
                </summary>
                <div style="background: #fafafa; padding: 16px; border-radius: 8px; margin-top: 8px; white-space: pre-wrap; font-size: 13px; color: #444;">
                    ${escapeHTML(transcription)}
                </div>
            </details>
            """
        } else ""

        return """
            <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px;">
                <h2 style="color: #1a1a1a; border-bottom: 2px solid #007AFF; padding-bottom: 8px;">
                    ${escapeHTML(title)}
                </h2>
                <p style="color: #666; font-size: 14px;">
                    Создано: ${formatter.format(date)} • Vanta Speech
                </p>

                <h3 style="color: #333; margin-top: 24px;">Краткое содержание</h3>
                <div style="background: #f5f5f7; padding: 16px; border-radius: 8px; white-space: pre-wrap;">
                    ${escapeHTML(summary)}
                </div>
                $transcriptionSection
                <p style="color: #999; font-size: 12px; margin-top: 24px; border-top: 1px solid #eee; padding-top: 12px;">
                    Автоматически сгенерировано приложением Vanta Speech
                </p>
            </div>
        """.trimIndent()
    }

    /**
     * Build HTML email for attendees
     */
    fun buildEmailHTML(
        meetingTitle: String,
        summary: String,
        transcription: String? = null
    ): String {
        val transcriptionSection = if (!transcription.isNullOrEmpty()) {
            """
            <details style="margin: 20px 0;">
                <summary style="cursor: pointer; color: #007AFF; font-weight: 600; padding: 8px 0;">
                    Показать полную транскрипцию
                </summary>
                <div style="background: #fafafa; padding: 16px; border-radius: 8px; margin-top: 8px; white-space: pre-wrap; font-size: 13px; color: #444; max-height: 400px; overflow-y: auto;">
                    ${escapeHTML(transcription)}
                </div>
            </details>
            """
        } else ""

        return """
            <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto;">
                <p>Коллеги,</p>
                <p>Прикрепляю краткое содержание нашей встречи <strong>${escapeHTML(meetingTitle)}</strong>.</p>

                <div style="background: #f5f5f7; padding: 20px; border-radius: 12px; margin: 20px 0;">
                    <h3 style="color: #333; margin-top: 0;">Краткое содержание</h3>
                    <div style="white-space: pre-wrap; color: #1a1a1a;">
                        ${escapeHTML(summary)}
                    </div>
                </div>
                $transcriptionSection
                <p style="color: #666; margin-top: 24px;">
                    С уважением,<br/>
                    <em>Автоматически сгенерировано приложением Vanta Speech</em>
                </p>
            </div>
        """.trimIndent()
    }

    private fun escapeHTML(string: String): String {
        return string
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
    }
}
