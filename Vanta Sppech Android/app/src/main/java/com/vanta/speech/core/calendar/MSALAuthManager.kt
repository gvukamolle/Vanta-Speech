package com.vanta.speech.core.calendar

import android.app.Activity
import android.content.Context
import android.util.Log
import com.microsoft.identity.client.AcquireTokenParameters
import com.microsoft.identity.client.AcquireTokenSilentParameters
import com.microsoft.identity.client.AuthenticationCallback
import com.microsoft.identity.client.IAccount
import com.microsoft.identity.client.IAuthenticationResult
import com.microsoft.identity.client.IPublicClientApplication
import com.microsoft.identity.client.ISingleAccountPublicClientApplication
import com.microsoft.identity.client.PublicClientApplication
import com.microsoft.identity.client.exception.MsalClientException
import com.microsoft.identity.client.exception.MsalException
import com.microsoft.identity.client.exception.MsalUiRequiredException
import com.vanta.speech.R
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Manager for Microsoft Authentication using MSAL SDK
 * Android equivalent of iOS MSALAuthManager
 */
@Singleton
class MSALAuthManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "MSALAuthManager"

        // Authority URL for authentication
        // "common" supports personal + work/school accounts
        private const val AUTHORITY = "https://login.microsoftonline.com/common"

        // Requested scopes
        private val SCOPES = arrayOf(
            "Calendars.ReadWrite",  // Read and write calendar events
            "User.Read",            // User profile
            "offline_access"        // Refresh token
        )
    }

    // MSAL application instance
    private var msalApp: ISingleAccountPublicClientApplication? = null

    // State
    private val _isSignedIn = MutableStateFlow(false)
    val isSignedIn: StateFlow<Boolean> = _isSignedIn.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _currentAccount = MutableStateFlow<IAccount?>(null)
    val currentAccount: StateFlow<IAccount?> = _currentAccount.asStateFlow()

    private val _userName = MutableStateFlow<String?>(null)
    val userName: StateFlow<String?> = _userName.asStateFlow()

    private val _userEmail = MutableStateFlow<String?>(null)
    val userEmail: StateFlow<String?> = _userEmail.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        initializeMSAL()
    }

    private fun initializeMSAL() {
        try {
            // Create MSAL configuration from resource file
            PublicClientApplication.createSingleAccountPublicClientApplication(
                context,
                R.raw.msal_config,
                object : IPublicClientApplication.ISingleAccountApplicationCreatedListener {
                    override fun onCreated(application: ISingleAccountPublicClientApplication) {
                        msalApp = application
                        Log.d(TAG, "MSAL configured successfully")
                        loadCachedAccount()
                    }

                    override fun onError(exception: MsalException) {
                        Log.e(TAG, "MSAL setup failed: ${exception.message}")
                        _error.value = "Ошибка настройки MSAL: ${exception.message}"
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "MSAL initialization error: ${e.message}")
            _error.value = "Ошибка инициализации MSAL: ${e.message}"
        }
    }

    private fun loadCachedAccount() {
        msalApp?.getCurrentAccountAsync(object : ISingleAccountPublicClientApplication.CurrentAccountCallback {
            override fun onAccountLoaded(activeAccount: IAccount?) {
                if (activeAccount != null) {
                    _currentAccount.value = activeAccount
                    _isSignedIn.value = true
                    _userName.value = activeAccount.username
                    _userEmail.value = activeAccount.username
                    Log.d(TAG, "Loaded cached account: ${activeAccount.username}")
                }
            }

            override fun onAccountChanged(priorAccount: IAccount?, currentAccount: IAccount?) {
                if (currentAccount == null) {
                    _currentAccount.value = null
                    _isSignedIn.value = false
                    _userName.value = null
                    _userEmail.value = null
                }
            }

            override fun onError(exception: MsalException) {
                Log.e(TAG, "Error loading cached account: ${exception.message}")
            }
        })
    }

    /**
     * Interactive sign in
     * @param activity Activity for presenting the sign-in UI
     * @return Access token for Microsoft Graph API
     */
    suspend fun signIn(activity: Activity): String = suspendCancellableCoroutine { continuation ->
        val app = msalApp
        if (app == null) {
            continuation.resumeWithException(MSALAuthError.NotConfigured)
            return@suspendCancellableCoroutine
        }

        _isLoading.value = true
        _error.value = null

        val parameters = AcquireTokenParameters.Builder()
            .startAuthorizationFromActivity(activity)
            .withScopes(SCOPES.toList())
            .withCallback(object : AuthenticationCallback {
                override fun onSuccess(authenticationResult: IAuthenticationResult) {
                    _isLoading.value = false
                    _currentAccount.value = authenticationResult.account
                    _isSignedIn.value = true
                    _userName.value = authenticationResult.account.username
                    _userEmail.value = authenticationResult.account.username

                    Log.d(TAG, "Sign in successful: ${authenticationResult.account.username}")
                    continuation.resume(authenticationResult.accessToken)
                }

                override fun onError(exception: MsalException) {
                    _isLoading.value = false

                    when (exception) {
                        is MsalClientException -> {
                            if (exception.errorCode == "user_cancel") {
                                continuation.resumeWithException(MSALAuthError.UserCanceled)
                                return
                            }
                        }
                    }

                    _error.value = exception.message
                    Log.e(TAG, "Sign in failed: ${exception.message}")
                    continuation.resumeWithException(MSALAuthError.SignInFailed(exception))
                }

                override fun onCancel() {
                    _isLoading.value = false
                    Log.d(TAG, "Sign in canceled by user")
                    continuation.resumeWithException(MSALAuthError.UserCanceled)
                }
            })
            .build()

        app.acquireToken(parameters)
    }

    /**
     * Acquire token silently (for background operations)
     * @return Access token for Microsoft Graph API
     */
    suspend fun acquireTokenSilently(): String = suspendCancellableCoroutine { continuation ->
        val app = msalApp
        val account = _currentAccount.value

        if (app == null) {
            continuation.resumeWithException(MSALAuthError.NotConfigured)
            return@suspendCancellableCoroutine
        }

        if (account == null) {
            continuation.resumeWithException(MSALAuthError.NoAccount)
            return@suspendCancellableCoroutine
        }

        val parameters = AcquireTokenSilentParameters.Builder()
            .forAccount(account)
            .fromAuthority(AUTHORITY)
            .withScopes(SCOPES.toList())
            .withCallback(object : AuthenticationCallback {
                override fun onSuccess(authenticationResult: IAuthenticationResult) {
                    continuation.resume(authenticationResult.accessToken)
                }

                override fun onError(exception: MsalException) {
                    when (exception) {
                        is MsalUiRequiredException -> {
                            continuation.resumeWithException(MSALAuthError.InteractionRequired)
                        }
                        else -> {
                            continuation.resumeWithException(MSALAuthError.TokenAcquisitionFailed(exception))
                        }
                    }
                }

                override fun onCancel() {
                    continuation.resumeWithException(MSALAuthError.UserCanceled)
                }
            })
            .build()

        app.acquireTokenSilentAsync(parameters)
    }

    /**
     * Sign out from the account
     */
    suspend fun signOut(): Unit = suspendCancellableCoroutine { continuation ->
        val app = msalApp

        if (app == null) {
            continuation.resume(Unit)
            return@suspendCancellableCoroutine
        }

        _isLoading.value = true

        app.signOut(object : ISingleAccountPublicClientApplication.SignOutCallback {
            override fun onSignOut() {
                _isLoading.value = false
                _currentAccount.value = null
                _isSignedIn.value = false
                _userName.value = null
                _userEmail.value = null

                Log.d(TAG, "Sign out successful")
                continuation.resume(Unit)
            }

            override fun onError(exception: MsalException) {
                _isLoading.value = false
                Log.e(TAG, "Sign out error: ${exception.message}")
                // Continue anyway - local state is cleared
                _currentAccount.value = null
                _isSignedIn.value = false
                _userName.value = null
                _userEmail.value = null
                continuation.resume(Unit)
            }
        })
    }

    fun clearError() {
        _error.value = null
    }
}

/**
 * MSAL Authentication Errors
 */
sealed class MSALAuthError : Exception() {
    data object NotConfigured : MSALAuthError() {
        private fun readResolve(): Any = NotConfigured
        override val message = "MSAL не настроен"
    }

    data object NoAccount : MSALAuthError() {
        private fun readResolve(): Any = NoAccount
        override val message = "Нет авторизованного аккаунта"
    }

    data object UserCanceled : MSALAuthError() {
        private fun readResolve(): Any = UserCanceled
        override val message = "Вход отменён пользователем"
    }

    data object InteractionRequired : MSALAuthError() {
        private fun readResolve(): Any = InteractionRequired
        override val message = "Требуется повторный вход"
    }

    data class SignInFailed(val originalCause: Exception) : MSALAuthError() {
        override val message = "Ошибка входа: ${originalCause.message}"
    }

    data class TokenAcquisitionFailed(val originalCause: Exception) : MSALAuthError() {
        override val message = "Ошибка получения токена: ${originalCause.message}"
    }
}
