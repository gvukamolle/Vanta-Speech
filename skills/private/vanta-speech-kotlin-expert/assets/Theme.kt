package com.vanta.speech.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val LightColorScheme = lightColorScheme(
    primary = VantaColors.PinkVibrant,
    secondary = VantaColors.BlueVibrant,
    tertiary = VantaColors.PinkLight,
    background = VantaColors.White,
    surface = VantaColors.White,
    surfaceVariant = VantaColors.PinkLight.copy(alpha = 0.3f),
    onBackground = VantaColors.Charcoal,
    onSurface = VantaColors.Charcoal,
    onPrimary = VantaColors.White,
    onSecondary = VantaColors.White,
    outline = VantaColors.Gray
)

private val DarkColorScheme = darkColorScheme(
    primary = VantaColors.PinkVibrant,
    secondary = VantaColors.BlueVibrant,
    tertiary = VantaColors.PinkLight,
    background = VantaColors.DarkBackground,
    surface = VantaColors.DarkSurface,
    surfaceVariant = VantaColors.DarkSurfaceElevated,
    onBackground = VantaColors.White,
    onSurface = VantaColors.White,
    onPrimary = VantaColors.White,
    onSecondary = VantaColors.White,
    outline = VantaColors.DarkTextSecondary
)

@Composable
fun VantaSpeechTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.background.toArgb()
            window.navigationBarColor = colorScheme.background.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = VantaTypography,
        content = content
    )
}
