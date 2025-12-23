package com.vantaspeech.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkColorScheme = darkColorScheme(
    primary = VantaSecondary,
    onPrimary = Color.White,
    primaryContainer = VantaPrimaryLight,
    onPrimaryContainer = Color.White,
    secondary = VantaSecondaryVariant,
    onSecondary = Color.White,
    secondaryContainer = VantaPrimary,
    onSecondaryContainer = Color.White,
    tertiary = RecordingGreen,
    onTertiary = Color.White,
    background = DarkBackground,
    onBackground = DarkOnBackground,
    surface = DarkSurface,
    onSurface = DarkOnSurface,
    surfaceVariant = VantaPrimaryLight,
    onSurfaceVariant = DarkOnSurfaceVariant,
    error = RecordingRed,
    onError = Color.White
)

private val LightColorScheme = lightColorScheme(
    primary = VantaSecondary,
    onPrimary = Color.White,
    primaryContainer = VantaSecondaryVariant.copy(alpha = 0.2f),
    onPrimaryContainer = VantaPrimary,
    secondary = VantaPrimary,
    onSecondary = Color.White,
    secondaryContainer = VantaPrimaryLight.copy(alpha = 0.1f),
    onSecondaryContainer = VantaPrimary,
    tertiary = RecordingGreen,
    onTertiary = Color.White,
    background = LightBackground,
    onBackground = LightOnBackground,
    surface = LightSurface,
    onSurface = LightOnSurface,
    surfaceVariant = Color(0xFFF0F0F5),
    onSurfaceVariant = LightOnSurfaceVariant,
    error = RecordingRed,
    onError = Color.White
)

@Composable
fun VantaSpeechTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Color.Transparent.toArgb()
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
