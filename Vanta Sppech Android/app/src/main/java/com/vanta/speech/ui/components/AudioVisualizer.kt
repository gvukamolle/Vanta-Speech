package com.vanta.speech.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.vanta.speech.ui.theme.VantaColors
import kotlin.math.sin
import kotlin.random.Random

@Composable
fun AudioVisualizer(
    audioLevel: Float,
    modifier: Modifier = Modifier,
    barCount: Int = 40,
    isActive: Boolean = true
) {
    val animatedLevel by animateFloatAsState(
        targetValue = if (isActive) audioLevel.coerceIn(0f, 1f) else 0f,
        animationSpec = spring(stiffness = 300f),
        label = "audioLevel"
    )

    val infiniteTransition = rememberInfiniteTransition(label = "wave")
    val waveOffset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "waveOffset"
    )

    val barHeights = remember { List(barCount) { Random.nextFloat() * 0.3f + 0.1f } }

    Canvas(modifier = modifier.fillMaxWidth()) {
        val barWidth = size.width / (barCount * 2f)
        val maxHeight = size.height * 0.8f
        val centerY = size.height / 2

        for (i in 0 until barCount) {
            val x = i * (size.width / barCount) + barWidth / 2

            // Create wave effect
            val wavePhase = (i.toFloat() / barCount) * 360f + waveOffset
            val waveFactor = (sin(Math.toRadians(wavePhase.toDouble())).toFloat() + 1f) / 2f

            // Combine audio level with wave and base height
            val baseHeight = barHeights[i]
            val targetHeight = if (isActive) {
                (baseHeight + animatedLevel * 0.7f + waveFactor * 0.2f) * maxHeight
            } else {
                baseHeight * maxHeight * 0.3f
            }

            val barHeight = targetHeight.coerceIn(4f, maxHeight)

            // Gradient color based on height
            val color = if (isActive) {
                lerp(VantaColors.BlueVibrant, VantaColors.PinkVibrant, barHeight / maxHeight)
            } else {
                VantaColors.DarkTextSecondary.copy(alpha = 0.5f)
            }

            drawRoundRect(
                color = color,
                topLeft = Offset(x - barWidth / 2, centerY - barHeight / 2),
                size = Size(barWidth * 0.7f, barHeight),
                cornerRadius = CornerRadius(barWidth / 2, barWidth / 2)
            )
        }
    }
}

@Composable
fun CircularAudioVisualizer(
    audioLevel: Float,
    modifier: Modifier = Modifier,
    ringCount: Int = 3,
    isActive: Boolean = true,
    baseColor: Color = VantaColors.PinkVibrant
) {
    val animatedLevel by animateFloatAsState(
        targetValue = if (isActive) audioLevel.coerceIn(0f, 1f) else 0f,
        animationSpec = spring(stiffness = 200f),
        label = "audioLevel"
    )

    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseScale"
    )

    Canvas(modifier = modifier) {
        val center = Offset(size.width / 2, size.height / 2)
        val maxRadius = minOf(size.width, size.height) / 2

        for (i in 0 until ringCount) {
            val ringProgress = (i + 1f) / ringCount
            val baseRadius = maxRadius * ringProgress * 0.6f
            val expandedRadius = baseRadius + (maxRadius * 0.4f * animatedLevel * (1f - ringProgress * 0.5f))

            val radius = if (isActive) {
                expandedRadius * (if (i == 0) pulseScale else 1f)
            } else {
                baseRadius * 0.8f
            }

            val alpha = if (isActive) {
                0.3f - (ringProgress * 0.2f) + (animatedLevel * 0.2f)
            } else {
                0.1f
            }

            drawCircle(
                color = baseColor.copy(alpha = alpha.coerceIn(0.05f, 0.5f)),
                radius = radius,
                center = center
            )
        }
    }
}

private fun lerp(start: Color, end: Color, fraction: Float): Color {
    return Color(
        red = start.red + (end.red - start.red) * fraction,
        green = start.green + (end.green - start.green) * fraction,
        blue = start.blue + (end.blue - start.blue) * fraction,
        alpha = start.alpha + (end.alpha - start.alpha) * fraction
    )
}
