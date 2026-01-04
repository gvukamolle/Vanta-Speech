package com.vanta.speech.core.ews.api

import android.util.Log
import com.vanta.speech.core.ews.model.EWSConfig
import com.vanta.speech.core.ews.model.EWSCredentials
import com.vanta.speech.core.ews.model.EWSError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Authenticator
import okhttp3.Credentials
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Low-level EWS SOAP client with NTLM/Basic authentication
 */
class EWSClient(
    private val serverURL: String,
    private val ntlmUsername: String,
    private val password: String
) {
    companion object {
        private const val TAG = "EWSClient"

        /**
         * Create EWSClient from stored credentials
         */
        fun fromCredentials(credentials: EWSCredentials): EWSClient {
            return EWSClient(
                serverURL = credentials.ewsEndpoint,
                ntlmUsername = credentials.ntlmUsername,
                password = credentials.password
            )
        }
    }

    private val client: OkHttpClient by lazy {
        createHttpClient()
    }

    private fun createHttpClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(EWSConfig.REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            .readTimeout(EWSConfig.REQUEST_TIMEOUT_MS * 2, TimeUnit.MILLISECONDS)
            .writeTimeout(EWSConfig.REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)

        // Add NTLM/Basic authenticator
        builder.authenticator(object : Authenticator {
            private var authAttempts = 0

            override fun authenticate(route: Route?, response: Response): Request? {
                // Prevent infinite auth loops
                if (authAttempts >= 3) {
                    Log.e(TAG, "Authentication failed after 3 attempts")
                    authAttempts = 0
                    return null
                }
                authAttempts++

                val challenges = response.challenges()
                Log.d(TAG, "Auth challenge received: ${challenges.map { it.scheme }}")

                // Check for NTLM challenge
                val ntlmChallenge = challenges.find {
                    it.scheme.equals("NTLM", ignoreCase = true)
                }

                // Check for Basic challenge
                val basicChallenge = challenges.find {
                    it.scheme.equals("Basic", ignoreCase = true)
                }

                // Check for Negotiate (Kerberos/NTLM) challenge
                val negotiateChallenge = challenges.find {
                    it.scheme.equals("Negotiate", ignoreCase = true)
                }

                return when {
                    ntlmChallenge != null || negotiateChallenge != null -> {
                        // For NTLM, OkHttp needs NTLMEngineImpl or similar
                        // Fallback to Basic auth as most Exchange servers support both
                        Log.d(TAG, "NTLM/Negotiate detected, using Basic auth fallback")
                        response.request.newBuilder()
                            .header("Authorization", Credentials.basic(ntlmUsername, password))
                            .build()
                    }
                    basicChallenge != null -> {
                        Log.d(TAG, "Using Basic authentication")
                        response.request.newBuilder()
                            .header("Authorization", Credentials.basic(ntlmUsername, password))
                            .build()
                    }
                    else -> {
                        Log.w(TAG, "Unknown authentication challenge")
                        null
                    }
                }
            }
        })

        // Trust self-signed certs in dev (consider cert pinning for production)
        try {
            val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
            })

            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, trustAllCerts, SecureRandom())

            builder.sslSocketFactory(sslContext.socketFactory, trustAllCerts[0] as X509TrustManager)
            builder.hostnameVerifier { _, _ -> true }
        } catch (e: Exception) {
            Log.w(TAG, "Could not configure SSL trust: ${e.message}")
        }

        return builder.build()
    }

    /**
     * Send a SOAP request to EWS
     * @param soapAction The SOAPAction header value
     * @param body The complete SOAP envelope XML
     * @return Response data
     */
    suspend fun sendRequest(soapAction: String, body: String): ByteArray = withContext(Dispatchers.IO) {
        val mediaType = "text/xml; charset=utf-8".toMediaType()
        val requestBody = body.toRequestBody(mediaType)

        val request = Request.Builder()
            .url(serverURL)
            .post(requestBody)
            .header("Content-Type", "text/xml; charset=utf-8")
            .header("SOAPAction", soapAction)
            .build()

        val response = try {
            client.newCall(request).execute()
        } catch (e: Exception) {
            throw EWSError.NetworkError(e)
        }

        response.use { resp ->
            val responseBody = resp.body?.bytes() ?: ByteArray(0)

            when (resp.code) {
                in 200..299 -> responseBody
                401 -> throw EWSError.AuthenticationFailed
                403 -> throw EWSError.AccessDenied
                429 -> throw EWSError.Throttled
                in 500..599 -> {
                    // Try to extract SOAP fault
                    val fault = extractSOAPFault(responseBody)
                    if (fault != null) {
                        throw EWSError.SOAPFault(fault)
                    }
                    throw EWSError.ServerError("HTTP ${resp.code}")
                }
                else -> throw EWSError.ServerError("HTTP ${resp.code}")
            }
        }
    }

    private fun extractSOAPFault(data: ByteArray): String? {
        val xmlString = String(data, Charsets.UTF_8)

        // Simple regex extraction of faultstring
        val startTag = "<faultstring>"
        val endTag = "</faultstring>"

        val startIndex = xmlString.indexOf(startTag)
        val endIndex = xmlString.indexOf(endTag)

        return if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
            xmlString.substring(startIndex + startTag.length, endIndex)
        } else {
            null
        }
    }
}
