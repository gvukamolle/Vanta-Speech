package com.vanta.speech.feature.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vanta.speech.ui.theme.VantaColors

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    viewModel: LoginViewModel = hiltViewModel()
) {
    val username by viewModel.username.collectAsStateWithLifecycle()
    val password by viewModel.password.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val isAuthenticated by viewModel.isAuthenticated.collectAsStateWithLifecycle()

    val focusManager = LocalFocusManager.current

    // Navigate when authenticated
    LaunchedEffect(isAuthenticated) {
        if (isAuthenticated) {
            onLoginSuccess()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        VantaColors.DarkBackground,
                        VantaColors.PinkLight.copy(alpha = 0.05f),
                        VantaColors.BlueVibrant.copy(alpha = 0.05f)
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 32.dp)
                .imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(120.dp))

            // Title Section
            TitleSection()

            Spacer(modifier = Modifier.height(48.dp))

            // Form Section
            FormSection(
                username = username,
                password = password,
                isLoading = isLoading,
                onUsernameChange = viewModel::onUsernameChange,
                onPasswordChange = viewModel::onPasswordChange,
                onLoginClick = viewModel::login,
                onNextField = { focusManager.moveFocus(FocusDirection.Down) },
                onDone = { focusManager.clearFocus() }
            )

            // Error Banner
            if (error != null) {
                Spacer(modifier = Modifier.height(16.dp))
                ErrorBanner(message = error!!)
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Skip Auth Button (for testing)
            TextButton(onClick = viewModel::skipAuthentication) {
                Text(
                    text = "Пропустить авторизацию (тест)",
                    color = VantaColors.DarkTextSecondary,
                    fontSize = 12.sp
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

@Composable
private fun TitleSection() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = buildAnnotatedString {
                withStyle(
                    SpanStyle(
                        brush = Brush.horizontalGradient(
                            colors = listOf(VantaColors.PinkVibrant, VantaColors.BlueVibrant)
                        ),
                        fontWeight = FontWeight.Bold,
                        fontSize = 36.sp
                    )
                ) {
                    append("Vanta ")
                }
                withStyle(
                    SpanStyle(
                        brush = Brush.horizontalGradient(
                            colors = listOf(VantaColors.PinkVibrant, VantaColors.BlueVibrant)
                        ),
                        fontWeight = FontWeight.Bold,
                        fontSize = 36.sp,
                        fontStyle = FontStyle.Italic
                    )
                ) {
                    append("Speech")
                }
            }
        )

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "Войдите в свой аккаунт",
            color = VantaColors.DarkTextSecondary,
            fontSize = 14.sp
        )
    }
}

@Composable
private fun FormSection(
    username: String,
    password: String,
    isLoading: Boolean,
    onUsernameChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onLoginClick: () -> Unit,
    onNextField: () -> Unit,
    onDone: () -> Unit
) {
    val textFieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = VantaColors.PinkVibrant,
        unfocusedBorderColor = VantaColors.DarkSurface,
        focusedLabelColor = VantaColors.PinkVibrant,
        unfocusedLabelColor = VantaColors.DarkTextSecondary,
        cursorColor = VantaColors.PinkVibrant,
        focusedTextColor = Color.White,
        unfocusedTextColor = Color.White,
        focusedContainerColor = VantaColors.DarkSurface,
        unfocusedContainerColor = VantaColors.DarkSurface
    )

    Column(modifier = Modifier.fillMaxWidth()) {
        // Username Field
        Text(
            text = "Логин",
            color = VantaColors.DarkTextSecondary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium
        )
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(
            value = username,
            onValueChange = onUsernameChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Введите логин", color = VantaColors.DarkTextSecondary) },
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
            colors = textFieldColors,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Text,
                imeAction = ImeAction.Next
            ),
            keyboardActions = KeyboardActions(onNext = { onNextField() })
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Password Field
        Text(
            text = "Пароль",
            color = VantaColors.DarkTextSecondary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium
        )
        Spacer(modifier = Modifier.height(8.dp))
        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Введите пароль", color = VantaColors.DarkTextSecondary) },
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
            colors = textFieldColors,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Go
            ),
            keyboardActions = KeyboardActions(
                onGo = {
                    onDone()
                    onLoginClick()
                }
            )
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Login Button
        Button(
            onClick = onLoginClick,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            enabled = !isLoading && username.isNotBlank() && password.isNotBlank(),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent
            )
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        brush = Brush.horizontalGradient(
                            colors = listOf(VantaColors.PinkVibrant, VantaColors.BlueVibrant)
                        ),
                        shape = RoundedCornerShape(12.dp),
                        alpha = if (username.isBlank() || password.isBlank()) 0.6f else 1f
                    ),
                contentAlignment = Alignment.Center
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        text = "Войти",
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        }
    }
}

@Composable
private fun ErrorBanner(message: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = Color(0xFFFFA500).copy(alpha = 0.1f),
                shape = RoundedCornerShape(12.dp)
            )
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = Color(0xFFFFA500),
            modifier = Modifier.size(20.dp)
        )
        Text(
            text = message,
            color = Color.White,
            fontSize = 14.sp,
            modifier = Modifier.weight(1f)
        )
    }
}
