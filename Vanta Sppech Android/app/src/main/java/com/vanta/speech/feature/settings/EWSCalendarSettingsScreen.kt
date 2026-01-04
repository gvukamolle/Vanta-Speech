package com.vanta.speech.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.ews.EWSCalendarManager
import com.vanta.speech.core.ews.model.EWSEvent
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.theme.VantaColors
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*
import javax.inject.Inject

@HiltViewModel
class EWSCalendarSettingsViewModel @Inject constructor(
    private val ewsManager: EWSCalendarManager
) : ViewModel() {

    val isConnected = ewsManager.isConnected
    val isSyncing = ewsManager.isSyncing
    val serverURL = ewsManager.serverURL
    val userEmail = ewsManager.userEmail
    val lastSyncDate = ewsManager.lastSyncDate
    val cachedEvents = ewsManager.cachedEvents
    val error = ewsManager.lastError

    fun connect(
        serverURL: String,
        domain: String,
        username: String,
        password: String,
        onComplete: (Boolean) -> Unit
    ) {
        viewModelScope.launch {
            val success = ewsManager.connect(
                serverURL = serverURL,
                domain = domain,
                username = username,
                password = password
            )
            onComplete(success)
        }
    }

    fun disconnect() {
        ewsManager.disconnect()
    }

    fun sync() {
        viewModelScope.launch {
            ewsManager.syncEvents()
        }
    }

    fun clearError() {
        ewsManager.clearError()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EWSCalendarSettingsScreen(
    onNavigateBack: () -> Unit,
    viewModel: EWSCalendarSettingsViewModel = hiltViewModel()
) {
    val isConnected by viewModel.isConnected.collectAsStateWithLifecycle()
    val isSyncing by viewModel.isSyncing.collectAsStateWithLifecycle()
    val serverURL by viewModel.serverURL.collectAsStateWithLifecycle()
    val userEmail by viewModel.userEmail.collectAsStateWithLifecycle()
    val lastSyncDate by viewModel.lastSyncDate.collectAsStateWithLifecycle()
    val cachedEvents by viewModel.cachedEvents.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()

    // Form state
    var formServerURL by remember { mutableStateOf("") }
    var formDomain by remember { mutableStateOf("") }
    var formUsername by remember { mutableStateOf("") }
    var formPassword by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(false) }
    var showDisconnectDialog by remember { mutableStateOf(false) }

    VantaBackground {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top Bar
            TopAppBar(
                title = {
                    Text(
                        "Exchange Calendar",
                        color = VantaColors.White,
                        fontWeight = FontWeight.Bold
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Назад",
                            tint = VantaColors.White
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent
                )
            )

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Exchange Logo Card
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(
                            Brush.horizontalGradient(
                                colors = listOf(
                                    Color(0xFFFF6D00), // Orange
                                    Color(0xFFFF8F00)
                                )
                            )
                        )
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            Icons.Default.Business,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(48.dp)
                        )
                        Text(
                            "Exchange Server",
                            color = Color.White,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            "On-Premises корпоративный календарь",
                            color = Color.White.copy(alpha = 0.8f),
                            fontSize = 14.sp
                        )
                    }
                }

                // Error Banner
                error?.let { errorMessage ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color(0xFFFF3B30).copy(alpha = 0.1f))
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            tint = Color(0xFFFF3B30)
                        )
                        Text(
                            errorMessage,
                            color = VantaColors.White,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = { viewModel.clearError() }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Закрыть",
                                tint = VantaColors.DarkTextSecondary
                            )
                        }
                    }
                }

                // Connection Status Card
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(VantaColors.DarkSurfaceElevated)
                        .padding(20.dp)
                ) {
                    if (isConnected) {
                        // Connected State
                        ConnectedContent(
                            serverURL = serverURL,
                            userEmail = userEmail,
                            lastSyncDate = lastSyncDate,
                            cachedEvents = cachedEvents,
                            isSyncing = isSyncing,
                            onSync = { viewModel.sync() },
                            onDisconnect = { showDisconnectDialog = true }
                        )
                    } else {
                        // Connection Form
                        ConnectionForm(
                            serverURL = formServerURL,
                            onServerURLChange = { formServerURL = it },
                            domain = formDomain,
                            onDomainChange = { formDomain = it },
                            username = formUsername,
                            onUsernameChange = { formUsername = it },
                            password = formPassword,
                            onPasswordChange = { formPassword = it },
                            showPassword = showPassword,
                            onTogglePassword = { showPassword = !showPassword },
                            isLoading = isLoading,
                            onConnect = {
                                isLoading = true
                                val normalizedURL = formServerURL.trim()
                                    .lowercase()
                                    .trimEnd('/')

                                viewModel.connect(
                                    serverURL = normalizedURL,
                                    domain = formDomain.trim().uppercase(),
                                    username = formUsername.trim(),
                                    password = formPassword
                                ) { success ->
                                    isLoading = false
                                    if (success) {
                                        formPassword = ""
                                    }
                                }
                            }
                        )
                    }
                }

                // Info section
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(VantaColors.DarkSurfaceElevated)
                        .padding(16.dp)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            "Возможности интеграции",
                            color = VantaColors.White,
                            fontWeight = FontWeight.SemiBold
                        )

                        FeatureRow(
                            icon = Icons.Default.Link,
                            text = "Синхронизация с корпоративным Exchange"
                        )
                        FeatureRow(
                            icon = Icons.Default.People,
                            text = "Просмотр участников встреч"
                        )
                        FeatureRow(
                            icon = Icons.Default.Email,
                            text = "Отправка саммари участникам"
                        )
                        FeatureRow(
                            icon = Icons.Default.Edit,
                            text = "Добавление заметок в события"
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }

    // Disconnect Confirmation Dialog
    if (showDisconnectDialog) {
        AlertDialog(
            onDismissRequest = { showDisconnectDialog = false },
            title = { Text("Отключить Exchange?") },
            text = { Text("Связь с календарём Exchange будет удалена. Существующие записи сохранятся.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.disconnect()
                        formServerURL = ""
                        formDomain = ""
                        formUsername = ""
                        formPassword = ""
                        showDisconnectDialog = false
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = Color(0xFFFF3B30)
                    )
                ) {
                    Text("Отключить")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDisconnectDialog = false }) {
                    Text("Отмена")
                }
            },
            containerColor = VantaColors.DarkSurfaceElevated,
            titleContentColor = VantaColors.White,
            textContentColor = VantaColors.DarkTextSecondary
        )
    }
}

@Composable
private fun ConnectedContent(
    serverURL: String?,
    userEmail: String?,
    lastSyncDate: Date?,
    cachedEvents: List<EWSEvent>,
    isSyncing: Boolean,
    onSync: () -> Unit,
    onDisconnect: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF4CAF50).copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Check,
                    contentDescription = null,
                    tint = Color(0xFF4CAF50)
                )
            }

            Column {
                Text(
                    "Подключено",
                    color = Color(0xFF4CAF50),
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    userEmail ?: "Unknown",
                    color = VantaColors.DarkTextSecondary,
                    fontSize = 14.sp
                )
            }
        }

        serverURL?.let { url ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.Dns,
                    contentDescription = null,
                    tint = VantaColors.DarkTextSecondary,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    url,
                    color = VantaColors.DarkTextSecondary,
                    fontSize = 12.sp
                )
            }
        }

        HorizontalDivider(color = VantaColors.DarkSurface)

        // Stats
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(
                    "Событий",
                    color = VantaColors.DarkTextSecondary,
                    fontSize = 12.sp
                )
                Text(
                    "${cachedEvents.size}",
                    color = VantaColors.White,
                    fontWeight = FontWeight.Bold
                )
            }

            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "Последняя синхр.",
                    color = VantaColors.DarkTextSecondary,
                    fontSize = 12.sp
                )
                Text(
                    lastSyncDate?.let {
                        SimpleDateFormat("dd.MM HH:mm", Locale.getDefault()).format(it)
                    } ?: "—",
                    color = VantaColors.White,
                    fontWeight = FontWeight.Bold
                )
            }
        }

        // Actions
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onSync,
                enabled = !isSyncing,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = Color(0xFFFF6D00)
                )
            ) {
                if (isSyncing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Color(0xFFFF6D00)
                    )
                } else {
                    Icon(Icons.Default.Sync, contentDescription = null)
                }
                Spacer(Modifier.width(8.dp))
                Text("Синхронизировать")
            }

            OutlinedButton(
                onClick = onDisconnect,
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = Color(0xFFFF3B30)
                )
            ) {
                Text("Отключить")
            }
        }
    }
}

@Composable
private fun ConnectionForm(
    serverURL: String,
    onServerURLChange: (String) -> Unit,
    domain: String,
    onDomainChange: (String) -> Unit,
    username: String,
    onUsernameChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    showPassword: Boolean,
    onTogglePassword: () -> Unit,
    isLoading: Boolean,
    onConnect: () -> Unit
) {
    val isFormValid = serverURL.isNotBlank() &&
            domain.isNotBlank() &&
            username.isNotBlank() &&
            password.isNotBlank()

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Header
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.Business,
                contentDescription = null,
                tint = Color(0xFFFF6D00),
                modifier = Modifier.size(28.dp)
            )
            Text(
                "Exchange Server (On-Premises)",
                color = VantaColors.White,
                fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp
            )
        }

        // Server URL
        OutlinedTextField(
            value = serverURL,
            onValueChange = onServerURLChange,
            label = { Text("URL сервера") },
            placeholder = { Text("https://exchange.company.ru") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Uri,
                imeAction = ImeAction.Next
            ),
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color(0xFFFF6D00),
                unfocusedBorderColor = VantaColors.DarkTextSecondary,
                focusedTextColor = VantaColors.White,
                unfocusedTextColor = VantaColors.White,
                focusedLabelColor = Color(0xFFFF6D00),
                unfocusedLabelColor = VantaColors.DarkTextSecondary,
                cursorColor = Color(0xFFFF6D00)
            )
        )

        // Domain
        OutlinedTextField(
            value = domain,
            onValueChange = onDomainChange,
            label = { Text("Домен") },
            placeholder = { Text("COMPANY") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                imeAction = ImeAction.Next
            ),
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color(0xFFFF6D00),
                unfocusedBorderColor = VantaColors.DarkTextSecondary,
                focusedTextColor = VantaColors.White,
                unfocusedTextColor = VantaColors.White,
                focusedLabelColor = Color(0xFFFF6D00),
                unfocusedLabelColor = VantaColors.DarkTextSecondary,
                cursorColor = Color(0xFFFF6D00)
            )
        )

        // Username
        OutlinedTextField(
            value = username,
            onValueChange = onUsernameChange,
            label = { Text("Имя пользователя") },
            placeholder = { Text("username") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                imeAction = ImeAction.Next
            ),
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color(0xFFFF6D00),
                unfocusedBorderColor = VantaColors.DarkTextSecondary,
                focusedTextColor = VantaColors.White,
                unfocusedTextColor = VantaColors.White,
                focusedLabelColor = Color(0xFFFF6D00),
                unfocusedLabelColor = VantaColors.DarkTextSecondary,
                cursorColor = Color(0xFFFF6D00)
            )
        )

        // Password
        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChange,
            label = { Text("Пароль") },
            singleLine = true,
            visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done
            ),
            trailingIcon = {
                IconButton(onClick = onTogglePassword) {
                    Icon(
                        if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                        contentDescription = if (showPassword) "Скрыть пароль" else "Показать пароль",
                        tint = VantaColors.DarkTextSecondary
                    )
                }
            },
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color(0xFFFF6D00),
                unfocusedBorderColor = VantaColors.DarkTextSecondary,
                focusedTextColor = VantaColors.White,
                unfocusedTextColor = VantaColors.White,
                focusedLabelColor = Color(0xFFFF6D00),
                unfocusedLabelColor = VantaColors.DarkTextSecondary,
                cursorColor = Color(0xFFFF6D00)
            )
        )

        // Connect Button
        Button(
            onClick = onConnect,
            enabled = isFormValid && !isLoading,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color(0xFFFF6D00),
                contentColor = Color.White
            )
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = Color.White
                )
                Spacer(Modifier.width(8.dp))
            } else {
                Icon(Icons.Default.Link, contentDescription = null)
                Spacer(Modifier.width(8.dp))
            }
            Text("Подключить")
        }
    }
}

@Composable
private fun FeatureRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = Color(0xFFFF6D00),
            modifier = Modifier.size(20.dp)
        )
        Text(
            text,
            color = VantaColors.DarkTextSecondary,
            fontSize = 14.sp
        )
    }
}
