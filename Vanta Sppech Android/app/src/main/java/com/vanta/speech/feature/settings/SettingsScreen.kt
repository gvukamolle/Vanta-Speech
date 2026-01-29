package com.vanta.speech.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Stream
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vanta.speech.R
import com.vanta.speech.ui.components.VantaBackground
import com.vanta.speech.ui.theme.VantaColors

@Composable
fun SettingsScreen(
    onNavigateToOutlook: () -> Unit = {},
    onNavigateToEAS: () -> Unit = {},
    onNavigateToPresets: () -> Unit = {},
    onNavigateToRealtime: () -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel()
) {
    var autoTranscribe by remember { mutableStateOf(true) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    val currentSession by viewModel.currentSession.collectAsStateWithLifecycle()
    val appTheme by viewModel.appTheme.collectAsStateWithLifecycle()

    VantaBackground {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 24.dp)
                .verticalScroll(rememberScrollState())
        ) {
            // Header
            Text(
                text = stringResource(R.string.nav_settings),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = VantaColors.White,
                modifier = Modifier.padding(horizontal = 24.dp)
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Account section (first, like iOS)
            SettingsSectionHeader(title = "Аккаунт")

            SettingsCard {
                currentSession?.let { session ->
                    SettingsInfoItem(
                        icon = Icons.Default.Person,
                        title = session.displayName ?: session.username,
                        value = session.username
                    )

                    SettingsDivider()
                }

                SettingsActionItem(
                    icon = Icons.AutoMirrored.Filled.Logout,
                    title = "Выйти из аккаунта",
                    tintColor = Color(0xFFFF3B30),
                    onClick = { viewModel.logout() }
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Recording section
            SettingsSectionHeader(title = "Запись")

            SettingsCard {
                SettingsNavigationItem(
                    icon = Icons.Default.Mic,
                    title = "Типы встреч",
                    value = "Настройка пресетов",
                    onClick = onNavigateToPresets
                )

                SettingsDivider()

                SettingsNavigationItem(
                    icon = Icons.Default.Stream,
                    title = "Настройки Real-time",
                    value = "Параметры live транскрипции",
                    onClick = onNavigateToRealtime
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Appearance section
            SettingsSectionHeader(title = "Оформление")

            SettingsCard {
                SettingsThemeItem(
                    selectedTheme = appTheme,
                    onThemeSelected = { viewModel.setAppTheme(it) }
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Transcription section
            SettingsSectionHeader(title = "Транскрипция")

            SettingsCard {
                SettingsToggleItem(
                    icon = Icons.Default.CloudUpload,
                    title = "Автотранскрипция",
                    subtitle = "Автоматически обрабатывать после записи",
                    isEnabled = autoTranscribe,
                    onToggle = { autoTranscribe = it }
                )

                SettingsDivider()

                SettingsInfoItem(
                    icon = Icons.Default.Cloud,
                    title = "Сервер",
                    value = "api.vanta.speech"
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Integrations section
            SettingsSectionHeader(title = "Интеграции")

            SettingsCard {
                SettingsNavigationItem(
                    icon = Icons.Default.Business,
                    title = "Exchange Calendar",
                    value = "On-Premises корпоративный",
                    onClick = onNavigateToEAS
                )

                SettingsDivider()

                SettingsNavigationItem(
                    icon = Icons.Default.CalendarMonth,
                    title = "Outlook Calendar",
                    value = "Облачный Microsoft 365",
                    onClick = onNavigateToOutlook
                )

                SettingsDivider()

                SettingsNavigationItem(
                    icon = Icons.Default.Description,
                    title = "Confluence",
                    value = "Скоро",
                    onClick = { /* TODO */ },
                    enabled = false
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // About section
            SettingsSectionHeader(title = "О приложении")

            SettingsCard {
                SettingsInfoItem(
                    icon = Icons.Default.Info,
                    title = "Версия",
                    value = "1.0.0"
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Data section (danger zone)
            SettingsSectionHeader(title = "Данные")

            SettingsCard {
                SettingsActionItem(
                    icon = Icons.Default.Delete,
                    title = "Удалить все записи",
                    tintColor = Color(0xFFFF3B30),
                    onClick = { showDeleteDialog = true }
                )
            }

            Spacer(modifier = Modifier.height(32.dp))

            // Footer
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "Vanta Speech",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = VantaColors.PinkVibrant
                )

                Spacer(modifier = Modifier.height(4.dp))

                Text(
                    text = "Записывай. Транскрибируй. Резюмируй.",
                    style = MaterialTheme.typography.bodySmall,
                    color = VantaColors.DarkTextSecondary
                )

                Spacer(modifier = Modifier.height(16.dp))

                Text(
                    text = "© 2024 Vanta",
                    style = MaterialTheme.typography.bodySmall,
                    color = VantaColors.DarkTextSecondary.copy(alpha = 0.6f)
                )
            }

            Spacer(modifier = Modifier.height(100.dp))
        }
    }

    // Delete confirmation dialog
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = {
                Text(
                    "Удалить все записи?",
                    color = VantaColors.White
                )
            },
            text = {
                Text(
                    "Это действие нельзя отменить. Все записи и транскрипции будут удалены.",
                    color = VantaColors.DarkTextSecondary
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteAllRecordings()
                        showDeleteDialog = false
                    }
                ) {
                    Text("Удалить", color = Color(0xFFFF3B30))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Отмена", color = VantaColors.PinkVibrant)
                }
            },
            containerColor = VantaColors.DarkSurfaceElevated
        )
    }
}

@Composable
private fun SettingsSectionHeader(title: String) {
    Text(
        text = title.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = VantaColors.DarkTextSecondary,
        letterSpacing = 1.sp,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp)
    )
}

@Composable
private fun SettingsCard(
    content: @Composable () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(VantaColors.DarkSurfaceElevated)
    ) {
        Column {
            content()
        }
    }
}

@Composable
private fun SettingsToggleItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    isEnabled: Boolean,
    onToggle: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onToggle(!isEnabled) }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(VantaColors.PinkVibrant.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = VantaColors.PinkVibrant,
                modifier = Modifier.size(20.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = VantaColors.White
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = VantaColors.DarkTextSecondary
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Switch(
            checked = isEnabled,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(
                checkedThumbColor = VantaColors.White,
                checkedTrackColor = VantaColors.PinkVibrant,
                uncheckedThumbColor = VantaColors.DarkTextSecondary,
                uncheckedTrackColor = VantaColors.DarkSurface
            )
        )
    }
}

@Composable
private fun SettingsNavigationItem(
    icon: ImageVector,
    title: String,
    value: String,
    onClick: () -> Unit,
    enabled: Boolean = true
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(
                    if (enabled) VantaColors.BlueVibrant.copy(alpha = 0.15f)
                    else VantaColors.DarkSurface
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (enabled) VantaColors.BlueVibrant else VantaColors.DarkTextSecondary,
                modifier = Modifier.size(20.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = if (enabled) VantaColors.White else VantaColors.DarkTextSecondary
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall,
                color = VantaColors.DarkTextSecondary
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = VantaColors.DarkTextSecondary,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
private fun SettingsInfoItem(
    icon: ImageVector,
    title: String,
    value: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(VantaColors.DarkSurface),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = VantaColors.DarkTextSecondary,
                modifier = Modifier.size(20.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            color = VantaColors.White,
            modifier = Modifier.weight(1f)
        )

        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = VantaColors.DarkTextSecondary
        )
    }
}

@Composable
private fun SettingsActionItem(
    icon: ImageVector,
    title: String,
    tintColor: Color = VantaColors.PinkVibrant,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(tintColor.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = tintColor,
                modifier = Modifier.size(20.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            color = tintColor
        )
    }
}

@Composable
private fun SettingsThemeItem(
    selectedTheme: String,
    onThemeSelected: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(VantaColors.PinkVibrant.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.DarkMode,
                    contentDescription = null,
                    tint = VantaColors.PinkVibrant,
                    modifier = Modifier.size(20.dp)
                )
            }

            Spacer(modifier = Modifier.width(16.dp))

            Text(
                text = "Тема",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = VantaColors.White
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ThemeOption(
                title = "Системная",
                isSelected = selectedTheme == "system",
                onClick = { onThemeSelected("system") },
                modifier = Modifier.weight(1f)
            )
            ThemeOption(
                title = "Светлая",
                isSelected = selectedTheme == "light",
                onClick = { onThemeSelected("light") },
                modifier = Modifier.weight(1f)
            )
            ThemeOption(
                title = "Тёмная",
                isSelected = selectedTheme == "dark",
                onClick = { onThemeSelected("dark") },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ThemeOption(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(
                if (isSelected) VantaColors.PinkVibrant
                else VantaColors.DarkSurface
            )
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isSelected) VantaColors.White else VantaColors.DarkTextSecondary
        )
    }
}

@Composable
private fun SettingsDivider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 72.dp)
            .height(1.dp)
            .background(VantaColors.DarkSurface)
    )
}
