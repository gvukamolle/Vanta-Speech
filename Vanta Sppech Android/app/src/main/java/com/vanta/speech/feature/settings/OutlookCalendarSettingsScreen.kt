package com.vanta.speech.feature.settings

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.vanta.speech.core.calendar.OutlookCalendarManager
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.theme.VantaColors
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*
import javax.inject.Inject

@HiltViewModel
class OutlookCalendarSettingsViewModel @Inject constructor(
    private val outlookManager: OutlookCalendarManager
) : ViewModel() {

    val isConnected = outlookManager.isConnected
    val isSyncing = outlookManager.isSyncing
    val userName = outlookManager.userName
    val userEmail = outlookManager.userEmail
    val lastSyncDate = outlookManager.lastSyncDate
    val error = outlookManager.error
    val eventsCount = outlookManager.cachedEvents

    fun connect(activity: Activity) {
        viewModelScope.launch {
            outlookManager.connect(activity)
        }
    }

    fun disconnect() {
        viewModelScope.launch {
            outlookManager.disconnect()
        }
    }

    fun sync() {
        viewModelScope.launch {
            outlookManager.performSync()
        }
    }

    fun clearError() {
        outlookManager.clearError()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OutlookCalendarSettingsScreen(
    onNavigateBack: () -> Unit,
    viewModel: OutlookCalendarSettingsViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val activity = context as? Activity

    val isConnected by viewModel.isConnected.collectAsStateWithLifecycle()
    val isSyncing by viewModel.isSyncing.collectAsStateWithLifecycle()
    val userName by viewModel.userName.collectAsStateWithLifecycle()
    val userEmail by viewModel.userEmail.collectAsStateWithLifecycle()
    val lastSyncDate by viewModel.lastSyncDate.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val events by viewModel.eventsCount.collectAsStateWithLifecycle()

    VantaBackground {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top Bar
            TopAppBar(
                title = {
                    Text(
                        "Outlook Calendar",
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
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Microsoft Logo Card
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(
                            Brush.horizontalGradient(
                                colors = listOf(
                                    Color(0xFF0078D4), // Microsoft Blue
                                    Color(0xFF00A4EF)
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
                            Icons.Default.CalendarMonth,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(48.dp)
                        )
                        Text(
                            "Microsoft Outlook",
                            color = Color.White,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            "Связывайте записи с событиями календаря",
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
                            .background(Color(0xFFFFA500).copy(alpha = 0.1f))
                            .padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            tint = Color(0xFFFFA500)
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
                                        userEmail ?: userName ?: "Unknown",
                                        color = VantaColors.DarkTextSecondary,
                                        fontSize = 14.sp
                                    )
                                }
                            }

                            Divider(color = VantaColors.DarkSurface)

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
                                        "${events.size}",
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
                                    onClick = { viewModel.sync() },
                                    enabled = !isSyncing,
                                    modifier = Modifier.weight(1f),
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        contentColor = VantaColors.BlueVibrant
                                    )
                                ) {
                                    if (isSyncing) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(16.dp),
                                            strokeWidth = 2.dp,
                                            color = VantaColors.BlueVibrant
                                        )
                                    } else {
                                        Icon(Icons.Default.Sync, contentDescription = null)
                                    }
                                    Spacer(Modifier.width(8.dp))
                                    Text("Синхронизировать")
                                }

                                OutlinedButton(
                                    onClick = { viewModel.disconnect() },
                                    colors = ButtonDefaults.outlinedButtonColors(
                                        contentColor = Color(0xFFFF3B30)
                                    )
                                ) {
                                    Text("Отключить")
                                }
                            }
                        }
                    } else {
                        // Disconnected State
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            Icon(
                                Icons.Default.CloudOff,
                                contentDescription = null,
                                tint = VantaColors.DarkTextSecondary,
                                modifier = Modifier.size(48.dp)
                            )

                            Text(
                                "Не подключено",
                                color = VantaColors.White,
                                fontWeight = FontWeight.SemiBold
                            )

                            Text(
                                "Подключите Outlook для автоматического связывания записей с событиями календаря",
                                color = VantaColors.DarkTextSecondary,
                                fontSize = 14.sp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )

                            Button(
                                onClick = {
                                    activity?.let { viewModel.connect(it) }
                                },
                                modifier = Modifier.fillMaxWidth(),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(0xFF0078D4)
                                )
                            ) {
                                Icon(Icons.Default.Login, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text("Войти через Microsoft")
                            }
                        }
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
                            text = "Автоматическое связывание записей со встречами"
                        )
                        FeatureRow(
                            icon = Icons.Default.People,
                            text = "Просмотр участников встречи"
                        )
                        FeatureRow(
                            icon = Icons.Default.Notifications,
                            text = "Напоминания о предстоящих встречах"
                        )
                    }
                }
            }
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
            tint = VantaColors.BlueVibrant,
            modifier = Modifier.size(20.dp)
        )
        Text(
            text,
            color = VantaColors.DarkTextSecondary,
            fontSize = 14.sp
        )
    }
}
