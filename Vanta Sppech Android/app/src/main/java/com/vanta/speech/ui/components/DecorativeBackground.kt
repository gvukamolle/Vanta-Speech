package com.vanta.speech.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.vanta.speech.ui.theme.VantaColors
import kotlin.math.cos
import kotlin.math.sin

data class Sphere(
    val centerX: Float,
    val centerY: Float,
    val radius: Float,
    val color: Color,
    val blur: Float = 100f
)

@Composable
fun DecorativeBackground(
    modifier: Modifier = Modifier
) {
    val infiniteTransition = rememberInfiniteTransition(label = "sphereAnimation")

    val offset1 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(20000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "offset1"
    )

    val offset2 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(25000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "offset2"
    )

    val offset3 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(30000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "offset3"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height

        // Pink sphere (top-right)
        val sphere1X = width * 0.8f + sin(Math.toRadians(offset1.toDouble())).toFloat() * 30f
        val sphere1Y = height * 0.15f + cos(Math.toRadians(offset1.toDouble())).toFloat() * 20f

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    VantaColors.PinkVibrant.copy(alpha = 0.6f),
                    VantaColors.PinkVibrant.copy(alpha = 0.3f),
                    VantaColors.PinkVibrant.copy(alpha = 0f)
                ),
                center = Offset(sphere1X, sphere1Y),
                radius = width * 0.4f
            ),
            radius = width * 0.4f,
            center = Offset(sphere1X, sphere1Y)
        )

        // Blue sphere (bottom-left)
        val sphere2X = width * 0.2f + sin(Math.toRadians(offset2.toDouble())).toFloat() * 25f
        val sphere2Y = height * 0.7f + cos(Math.toRadians(offset2.toDouble())).toFloat() * 25f

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    VantaColors.BlueVibrant.copy(alpha = 0.5f),
                    VantaColors.BlueVibrant.copy(alpha = 0.2f),
                    VantaColors.BlueVibrant.copy(alpha = 0f)
                ),
                center = Offset(sphere2X, sphere2Y),
                radius = width * 0.35f
            ),
            radius = width * 0.35f,
            center = Offset(sphere2X, sphere2Y)
        )

        // Small pink sphere (center-left)
        val sphere3X = width * 0.1f + sin(Math.toRadians(offset3.toDouble())).toFloat() * 15f
        val sphere3Y = height * 0.35f + cos(Math.toRadians(offset3.toDouble())).toFloat() * 15f

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    VantaColors.PinkLight.copy(alpha = 0.4f),
                    VantaColors.PinkLight.copy(alpha = 0.15f),
                    VantaColors.PinkLight.copy(alpha = 0f)
                ),
                center = Offset(sphere3X, sphere3Y),
                radius = width * 0.25f
            ),
            radius = width * 0.25f,
            center = Offset(sphere3X, sphere3Y)
        )
    }
}

@Composable
fun VantaBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(modifier = modifier.fillMaxSize()) {
        // Dark background
        Canvas(modifier = Modifier.fillMaxSize()) {
            drawRect(color = VantaColors.DarkBackground)
        }

        // Decorative spheres
        DecorativeBackground()

        // Content
        content()
    }
}
