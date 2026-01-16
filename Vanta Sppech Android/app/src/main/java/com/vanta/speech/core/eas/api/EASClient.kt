package com.vanta.speech.core.eas.api

import com.vanta.speech.core.auth.SecurePreferencesManager
import com.vanta.speech.core.eas.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.InetAddress
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * HTTP client for Exchange ActiveSync protocol
 */
@Singleton
class EASClient @Inject constructor(
    private val securePreferencesManager: SecurePreferencesManager
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val xmlParser = EASXMLParser()

    /** Use plain XML instead of WBXML (for testing) */
    var usePlainXML = true

    // MARK: - Public API

    /**
     * Test connection with OPTIONS request
     */
    suspend fun testConnection(): Result<EASServerInfo> = withContext(Dispatchers.IO) {
        try {
            if (!isNetworkAvailable()) {
                return@withContext Result.failure(EASError.Offline)
            }

            val credentials = getCredentials()
                ?: return@withContext Result.failure(EASError.NoCredentials)

            val request = Request.Builder()
                .url(credentials.activeSyncURL)
                .method("OPTIONS", null)
                .header("Authorization", credentials.basicAuthHeader)
                .header("MS-ASProtocolVersion", EASCredentials.PROTOCOL_VERSION)
                .header("User-Agent", "VantaSpeech/1.0")
                .build()

            val response = client.newCall(request).execute()

            when (response.code) {
                200 -> {
                    val versions = response.header("MS-ASProtocolVersions") ?: ""
                    val commands = response.header("MS-ASProtocolCommands") ?: ""
                    Result.success(
                        EASServerInfo(
                            protocolVersions = versions.split(",").map { it.trim() },
                            supportedCommands = commands.split(",").map { it.trim() }
                        )
                    )
                }
                401 -> Result.failure(EASError.AuthenticationFailed)
                403 -> Result.failure(EASError.AccessDenied)
                503 -> Result.failure(EASError.ServerUnavailable)
                else -> Result.failure(
                    EASError.ServerError(response.code, response.message)
                )
            }
        } catch (e: IOException) {
            Result.failure(EASError.NetworkError(e.message ?: "Network error"))
        } catch (e: Exception) {
            Result.failure(EASError.Unknown(e.message ?: "Unknown error"))
        }
    }

    /**
     * Execute FolderSync to discover calendar folder
     */
    suspend fun folderSync(syncKey: String): Result<FolderSyncResponse> = withContext(Dispatchers.IO) {
        try {
            if (!isNetworkAvailable()) {
                return@withContext Result.failure(EASError.Offline)
            }

            val credentials = getCredentials()
                ?: return@withContext Result.failure(EASError.NoCredentials)

            val xmlBody = buildFolderSyncXML(syncKey)
            val request = buildRequest("FolderSync", credentials, xmlBody)

            val response = client.newCall(request).execute()

            when (response.code) {
                200 -> {
                    val body = response.body?.string()
                        ?: return@withContext Result.failure(EASError.ParseError("Empty response"))
                    val parsed = xmlParser.parseFolderSync(body)
                    Result.success(parsed)
                }
                401 -> Result.failure(EASError.AuthenticationFailed)
                403 -> Result.failure(EASError.AccessDenied)
                503 -> Result.failure(EASError.ServerUnavailable)
                else -> Result.failure(
                    EASError.ServerError(response.code, response.message)
                )
            }
        } catch (e: IOException) {
            Result.failure(EASError.NetworkError(e.message ?: "Network error"))
        } catch (e: Exception) {
            Result.failure(EASError.Unknown(e.message ?: "Unknown error"))
        }
    }

    /**
     * Execute Sync command to get/create calendar items
     */
    suspend fun sync(
        folderId: String,
        syncKey: String,
        getChanges: Boolean = true,
        addItems: List<EASCalendarEvent>? = null
    ): Result<SyncResponse> = withContext(Dispatchers.IO) {
        try {
            if (!isNetworkAvailable()) {
                return@withContext Result.failure(EASError.Offline)
            }

            val credentials = getCredentials()
                ?: return@withContext Result.failure(EASError.NoCredentials)

            val xmlBody = buildSyncXML(folderId, syncKey, getChanges, addItems)
            val request = buildRequest("Sync", credentials, xmlBody)

            val response = client.newCall(request).execute()

            when (response.code) {
                200 -> {
                    val body = response.body?.string()
                        ?: return@withContext Result.failure(EASError.ParseError("Empty response"))
                    val parsed = xmlParser.parseSync(body)
                    Result.success(parsed)
                }
                401 -> Result.failure(EASError.AuthenticationFailed)
                403 -> Result.failure(EASError.AccessDenied)
                503 -> Result.failure(EASError.ServerUnavailable)
                else -> Result.failure(
                    EASError.ServerError(response.code, response.message)
                )
            }
        } catch (e: IOException) {
            Result.failure(EASError.NetworkError(e.message ?: "Network error"))
        } catch (e: Exception) {
            Result.failure(EASError.Unknown(e.message ?: "Unknown error"))
        }
    }

    // MARK: - Private Methods

    private fun getCredentials(): EASCredentials? {
        return securePreferencesManager.loadEASCredentials()
    }

    private fun buildRequest(command: String, credentials: EASCredentials, body: String): Request {
        val contentType = if (usePlainXML) {
            "text/xml".toMediaType()
        } else {
            "application/vnd.ms-sync.wbxml".toMediaType()
        }

        return Request.Builder()
            .url(credentials.buildURL(command))
            .post(body.toRequestBody(contentType))
            .header("Authorization", credentials.basicAuthHeader)
            .header("MS-ASProtocolVersion", EASCredentials.PROTOCOL_VERSION)
            .header("X-MS-PolicyKey", "0")
            .header("User-Agent", "VantaSpeech/1.0")
            .build()
    }

    private fun buildFolderSyncXML(syncKey: String): String {
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <FolderSync xmlns="FolderHierarchy">
                <SyncKey>$syncKey</SyncKey>
            </FolderSync>
        """.trimIndent()
    }

    private fun buildSyncXML(
        folderId: String,
        syncKey: String,
        getChanges: Boolean,
        addItems: List<EASCalendarEvent>?
    ): String {
        val commandsXml = if (!addItems.isNullOrEmpty()) {
            val adds = addItems.joinToString("") { event ->
                """
                <Add>
                    <ClientId>${event.clientId ?: UUID.randomUUID()}</ClientId>
                    <ApplicationData>
                        ${event.toEASXml()}
                    </ApplicationData>
                </Add>
                """.trimIndent()
            }
            "<Commands>$adds</Commands>"
        } else {
            ""
        }

        return """
            <?xml version="1.0" encoding="utf-8"?>
            <Sync xmlns="AirSync" xmlns:calendar="Calendar">
                <Collections>
                    <Collection>
                        <SyncKey>$syncKey</SyncKey>
                        <CollectionId>$folderId</CollectionId>
                        <GetChanges>${if (getChanges) "1" else "0"}</GetChanges>
                        <WindowSize>100</WindowSize>
                        <Options>
                            <BodyPreference xmlns="AirSyncBase">
                                <Type>2</Type>
                                <TruncationSize>51200</TruncationSize>
                            </BodyPreference>
                        </Options>
                        $commandsXml
                    </Collection>
                </Collections>
            </Sync>
        """.trimIndent()
    }

    private fun isNetworkAvailable(): Boolean {
        return try {
            val address = InetAddress.getByName("8.8.8.8")
            !address.equals("")
        } catch (e: Exception) {
            false
        }
    }
}

// MARK: - Response Types

/**
 * Server info from OPTIONS response
 */
data class EASServerInfo(
    val protocolVersions: List<String>,
    val supportedCommands: List<String>
) {
    val supportsVersion14: Boolean
        get() = protocolVersions.any { it.startsWith("14") }
}

/**
 * Response from FolderSync command
 */
data class FolderSyncResponse(
    val syncKey: String,
    val folders: List<EASFolder>,
    val status: Int
) {
    /** Find the default calendar folder */
    val calendarFolder: EASFolder?
        get() = folders.find { it.type == EASFolderType.DEFAULT_CALENDAR }
}

/**
 * Response from Sync command
 */
data class SyncResponse(
    val syncKey: String,
    val events: List<EASCalendarEvent>,
    val status: Int,
    val moreAvailable: Boolean
)
