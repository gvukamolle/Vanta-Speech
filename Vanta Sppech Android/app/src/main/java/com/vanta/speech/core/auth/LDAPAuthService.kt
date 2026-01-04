package com.vanta.speech.core.auth

import com.vanta.speech.core.auth.model.UserSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for authenticating against Active Directory via LDAP
 * Direct port from iOS LDAPAuthService
 */
@Singleton
class LDAPAuthService @Inject constructor() {

    companion object {
        // LDAP Configuration - same as iOS
        private const val LDAP_HOST = "10.64.248.19"
        private const val LDAP_PORT = 389
        private const val LDAP_DOMAIN = "b2pos.local"
        private const val CONNECTION_TIMEOUT = 30_000
        private const val READ_TIMEOUT = 30_000
    }

    sealed class AuthError : Exception() {
        data object InvalidCredentials : AuthError() {
            private fun readResolve(): Any = InvalidCredentials
            override val message = "Неверный логин или пароль"
        }
        data class ConnectionFailed(val details: String) : AuthError() {
            override val message = "Не удалось подключиться к серверу LDAP. $details"
        }
        data class ServerError(val details: String) : AuthError() {
            override val message = "Ошибка сервера: $details"
        }
        data object Timeout : AuthError() {
            private fun readResolve(): Any = Timeout
            override val message = "Превышено время ожидания подключения к LDAP"
        }
        data class StreamError(val details: String) : AuthError() {
            override val message = "Ошибка потока данных: $details"
        }
        data class WriteError(val written: Int, val expected: Int) : AuthError() {
            override val message = "Ошибка отправки запроса: записано $written из $expected байт"
        }
        data object ReadError : AuthError() {
            private fun readResolve(): Any = ReadError
            override val message = "Ошибка чтения ответа от LDAP сервера (0 байт)"
        }
    }

    /**
     * Authenticate user against LDAP/AD
     * @param username sAMAccountName (e.g., "ivanov")
     * @param password User's AD password
     * @return UserSession on success
     */
    suspend fun authenticate(username: String, password: String): Result<UserSession> = withContext(Dispatchers.IO) {
        try {
            // Construct the bind DN from username (same as iOS)
            val bindDN = "$username@$LDAP_DOMAIN"
            performLDAPBind(bindDN, password, username)
        } catch (e: AuthError) {
            Result.failure(e)
        } catch (e: Exception) {
            Result.failure(AuthError.ConnectionFailed(e.message ?: "Unknown error"))
        }
    }

    private fun performLDAPBind(bindDN: String, password: String, username: String): Result<UserSession> {
        var socket: Socket? = null
        var input: InputStream? = null
        var output: OutputStream? = null

        try {
            // Create socket and connect
            socket = Socket()
            socket.connect(InetSocketAddress(LDAP_HOST, LDAP_PORT), CONNECTION_TIMEOUT)
            socket.soTimeout = READ_TIMEOUT

            input = socket.getInputStream()
            output = socket.getOutputStream()

            // Build LDAP Simple Bind Request (ASN.1 BER encoded)
            val bindRequest = buildLDAPBindRequest(bindDN, password)

            // Send request
            output.write(bindRequest)
            output.flush()

            // Read response
            val responseBuffer = ByteArray(1024)
            val bytesRead = input.read(responseBuffer)

            if (bytesRead <= 0) {
                return Result.failure(AuthError.ReadError)
            }

            // Parse LDAP Bind Response
            val responseData = responseBuffer.copyOf(bytesRead)
            val parseResult = parseLDAPBindResponse(responseData)

            return if (parseResult.success) {
                Result.success(
                    UserSession(
                        username = username,
                        displayName = username,
                        email = null
                    )
                )
            } else {
                val errorMsg = "resultCode=${parseResult.resultCode}, ${parseResult.errorMessage}, bytes=$bytesRead"
                if (parseResult.resultCode == 49) {
                    Result.failure(AuthError.InvalidCredentials)
                } else {
                    Result.failure(AuthError.ServerError(errorMsg))
                }
            }
        } catch (e: java.net.SocketTimeoutException) {
            return Result.failure(AuthError.Timeout)
        } catch (e: java.net.ConnectException) {
            return Result.failure(AuthError.ConnectionFailed(e.message ?: "Connection refused"))
        } catch (e: Exception) {
            return Result.failure(AuthError.StreamError(e.message ?: "Unknown stream error"))
        } finally {
            try {
                input?.close()
                output?.close()
                socket?.close()
            } catch (_: Exception) {}
        }
    }

    /**
     * Build LDAP Simple Bind Request (ASN.1 BER encoded)
     * Direct port from iOS implementation
     */
    private fun buildLDAPBindRequest(bindDN: String, password: String): ByteArray {
        val bindDNBytes = bindDN.toByteArray(Charsets.UTF_8)
        val passwordBytes = password.toByteArray(Charsets.UTF_8)

        // Build bind request content
        val bindRequestContent = mutableListOf<Byte>()

        // Version (integer, value = 3 for LDAPv3)
        bindRequestContent.addAll(listOf(0x02, 0x01, 0x03).map { it.toByte() })

        // Bind DN (octet string)
        bindRequestContent.add(0x04.toByte()) // Octet string tag
        bindRequestContent.addAll(encodeLength(bindDNBytes.size))
        bindRequestContent.addAll(bindDNBytes.toList())

        // Simple authentication (context-specific 0)
        bindRequestContent.add(0x80.toByte()) // Context-specific primitive tag 0
        bindRequestContent.addAll(encodeLength(passwordBytes.size))
        bindRequestContent.addAll(passwordBytes.toList())

        // Wrap in Bind Request sequence (application 0)
        val bindRequest = mutableListOf<Byte>()
        bindRequest.add(0x60.toByte()) // Application 0 (Bind Request)
        bindRequest.addAll(encodeLength(bindRequestContent.size))
        bindRequest.addAll(bindRequestContent)

        // Message ID (integer, value = 1)
        val messageID = listOf(0x02, 0x01, 0x01).map { it.toByte() }

        // Build complete message content
        val messageContent = mutableListOf<Byte>()
        messageContent.addAll(messageID)
        messageContent.addAll(bindRequest)

        // Wrap in LDAP Message sequence
        val result = mutableListOf<Byte>()
        result.add(0x30.toByte()) // Sequence tag
        result.addAll(encodeLength(messageContent.size))
        result.addAll(messageContent)

        return result.toByteArray()
    }

    /**
     * Encode ASN.1 BER length
     */
    private fun encodeLength(length: Int): List<Byte> {
        return when {
            length < 128 -> listOf(length.toByte())
            length < 256 -> listOf(0x81.toByte(), length.toByte())
            else -> listOf(0x82.toByte(), (length shr 8).toByte(), (length and 0xFF).toByte())
        }
    }

    /**
     * Parse LDAP Bind Response and extract result code
     */
    private fun parseLDAPBindResponse(response: ByteArray): ParseResult {
        if (response.size <= 10) {
            return ParseResult(false, -1, "Response too short (${response.size} bytes)")
        }

        // Look for enumerated tag (0x0A) which contains the result code
        for (i in 0 until response.size - 2) {
            if (response[i] == 0x0A.toByte() && response[i + 1] == 0x01.toByte()) {
                // Found enumerated value (result code)
                val resultCode = response[i + 2].toInt() and 0xFF
                val errorMsg = ldapResultCodeDescription(resultCode)
                return ParseResult(resultCode == 0, resultCode, errorMsg)
            }
        }

        return ParseResult(false, -2, "Could not parse result code from response")
    }

    /**
     * Human-readable LDAP result code descriptions
     */
    private fun ldapResultCodeDescription(code: Int): String = when (code) {
        0 -> "success"
        1 -> "operationsError"
        2 -> "protocolError"
        3 -> "timeLimitExceeded"
        4 -> "sizeLimitExceeded"
        7 -> "authMethodNotSupported"
        8 -> "strongerAuthRequired"
        14 -> "saslBindInProgress"
        16 -> "noSuchAttribute"
        32 -> "noSuchObject"
        34 -> "invalidDNSyntax"
        48 -> "inappropriateAuthentication"
        49 -> "invalidCredentials"
        50 -> "insufficientAccessRights"
        51 -> "busy"
        52 -> "unavailable"
        53 -> "unwillingToPerform"
        80 -> "other"
        else -> "unknownError($code)"
    }

    private data class ParseResult(
        val success: Boolean,
        val resultCode: Int,
        val errorMessage: String
    )
}
