package com.vanta.speech.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.vanta.speech.ui.theme.VantaColors
import java.time.Duration
import java.util.Locale

@Composable
fun TimerDisplay(
    duration: Duration,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 48.sp,
    color: Color = VantaColors.White
) {
    val hours = duration.toHours()
    val minutes = duration.toMinutes() % 60
    val seconds = duration.seconds % 60

    val timeString = if (hours > 0) {
        String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.US, "%02d:%02d", minutes, seconds)
    }

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically
    ) {
        timeString.forEachIndexed { index, char ->
            AnimatedDigit(
                char = char,
                fontSize = fontSize,
                color = color
            )
        }
    }
}

@Composable
private fun AnimatedDigit(
    char: Char,
    fontSize: TextUnit,
    color: Color
) {
    AnimatedContent(
        targetState = char,
        transitionSpec = {
            if (targetState.isDigit() && initialState.isDigit()) {
                (slideInVertically { height -> height } + fadeIn(tween(150)))
                    .togetherWith(slideOutVertically { height -> -height } + fadeOut(tween(150)))
            } else {
                fadeIn(tween(0)) togetherWith fadeOut(tween(0))
            }
        },
        label = "digit"
    ) { digit ->
        Text(
            text = digit.toString(),
            fontSize = fontSize,
            fontWeight = FontWeight.Bold,
            color = color,
            fontFamily = FontFamily.Monospace
        )
    }
}

@Composable
fun CompactTimerDisplay(
    duration: Duration,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 16.sp,
    color: Color = VantaColors.White
) {
    val hours = duration.toHours()
    val minutes = duration.toMinutes() % 60
    val seconds = duration.seconds % 60

    val timeString = if (hours > 0) {
        String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.US, "%d:%02d", minutes, seconds)
    }

    Text(
        text = timeString,
        modifier = modifier,
        fontSize = fontSize,
        fontWeight = FontWeight.Medium,
        color = color,
        fontFamily = FontFamily.Monospace
    )
}
