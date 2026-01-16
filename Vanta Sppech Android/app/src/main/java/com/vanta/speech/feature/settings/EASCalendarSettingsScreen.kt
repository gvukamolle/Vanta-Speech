package com.vanta.speech.feature.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.vanta.speech.core.eas.model.EASCalendarEvent
import java.text.SimpleDateFormat
import java.util.*

/**
 * Settings screen for Exchange ActiveSync calendar integration
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EASCalendarSettingsScreen(
    onNavigateBack: () -> Unit,
    viewModel: EASCalendarSettingsViewModel = hiltViewModel()
) {
    val isConnected by viewModel.isConnected.collectAsState()
    val isSyncing by viewModel.isSyncing.collectAsState()
    val isConnecting by viewModel.isConnecting.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val lastSyncDate by viewModel.lastSyncDate.collectAsState()
    val events by viewModel.cachedEvents.collectAsState()

    var showErrorDialog by remember { mutableStateOf(false) }

    LaunchedEffect(errorMessage) {
        if (errorMessage != null) {
            showErrorDialog = true
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Exchange Calendar") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Назад")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (isConnected) {
                ConnectedContent(
                    isSyncing = isSyncing,
                    lastSyncDate = lastSyncDate,
                    events = viewModel.upcomingEvents,
                    onSync = { viewModel.syncEvents() },
                    onDisconnect = { viewModel.disconnect() }
                )
            } else {
                LoginContent(
                    serverURL = viewModel.serverURL.collectAsState().value,
                    username = viewModel.username.collectAsState().value,
                    password = viewModel.password.collectAsState().value,
                    isConnecting = isConnecting,
                    canConnect = viewModel.canConnect,
                    onServerURLChange = { viewModel.updateServerURL(it) },
                    onUsernameChange = { viewModel.updateUsername(it) },
                    onPasswordChange = { viewModel.updatePassword(it) },
                    onConnect = { viewModel.connect() }
                )
            }
        }
    }

    if (showErrorDialog && errorMessage != null) {
        AlertDialog(
            onDismissRequest = {
                showErrorDialog = false
                viewModel.clearError()
            },
            title = { Text("Ошибка") },
            text = { Text(errorMessage ?: "") },
            confirmButton = {
                TextButton(onClick = {
                    showErrorDialog = false
                    viewModel.clearError()
                }) {
                    Text("OK")
                }
            }
        )
    }
}

@Composable
private fun ConnectedContent(
    isSyncing: Boolean,
    lastSyncDate: Long?,
    events: List<EASCalendarEvent>,
    onSync: () -> Unit,
    onDisconnect: () -> Unit
) {
    // Status Card
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Text("Подключено", style = MaterialTheme.typography.titleMedium)
            }

            lastSyncDate?.let { timestamp ->
                val dateFormat = SimpleDateFormat("d MMM, HH:mm", Locale.getDefault())
                Text(
                    "Последняя синхронизация: ${dateFormat.format(Date(timestamp))}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    // Events Card
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                "Ближайшие события",
                style = MaterialTheme.typography.titleMedium
            )

            if (events.isEmpty()) {
                Text(
                    "Нет событий",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                events.take(5).forEach { event ->
                    EventRow(event = event)
                }

                if (events.size > 5) {
                    Text(
                        "И ещё ${events.size - 5} событий...",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }

    // Actions
    Button(
        onClick = onSync,
        enabled = !isSyncing,
        modifier = Modifier.fillMaxWidth()
    ) {
        if (isSyncing) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp
            )
            Spacer(Modifier.width(8.dp))
        } else {
            Icon(Icons.Default.Refresh, contentDescription = null)
            Spacer(Modifier.width(8.dp))
        }
        Text("Синхронизировать")
    }

    OutlinedButton(
        onClick = onDisconnect,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.error
        )
    ) {
        Text("Отключить")
    }
}

@Composable
private fun LoginContent(
    serverURL: String,
    username: String,
    password: String,
    isConnecting: Boolean,
    canConnect: Boolean,
    onServerURLChange: (String) -> Unit,
    onUsernameChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onConnect: () -> Unit
) {
    var passwordVisible by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                "Подключение к Exchange",
                style = MaterialTheme.typography.titleMedium
            )

            OutlinedTextField(
                value = serverURL,
                onValueChange = onServerURLChange,
                label = { Text("Адрес сервера") },
                placeholder = { Text("https://mail.company.com") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Next
                ),
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedTextField(
                value = username,
                onValueChange = onUsernameChange,
                label = { Text("Имя пользователя") },
                placeholder = { Text("DOMAIN\\username") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Text,
                    imeAction = ImeAction.Next
                ),
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedTextField(
                value = password,
                onValueChange = onPasswordChange,
                label = { Text("Пароль") },
                singleLine = true,
                visualTransformation = if (passwordVisible) {
                    VisualTransformation.None
                } else {
                    PasswordVisualTransformation()
                },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done
                ),
                trailingIcon = {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (passwordVisible) "Скрыть пароль" else "Показать пароль"
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth()
            )

            Button(
                onClick = onConnect,
                enabled = canConnect && !isConnecting,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (isConnecting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text("Подключить")
            }
        }
    }

    Text(
        "Введите адрес вашего Exchange сервера и учётные данные.\n\n" +
                "Формат имени пользователя: DOMAIN\\username или user@domain.com\n\n" +
                "Пример сервера: https://mail.company.com",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun EventRow(event: EASCalendarEvent) {
    val dateFormat = SimpleDateFormat("d MMM, HH:mm", Locale.getDefault())

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                event.subject,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    dateFormat.format(event.startTime),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                event.location?.let { location ->
                    Text(
                        location,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                }
            }
        }
    }
}
