package com.vanta.speech.ui.navigation

sealed class Screen(val route: String) {
    data object Login : Screen("login")
    data object Recording : Screen("recording")
    data object Library : Screen("library")
    data object Settings : Screen("settings")
    data object OutlookSettings : Screen("settings/outlook")
    data object EASSettings : Screen("settings/eas")
    data object PresetSettings : Screen("settings/presets")
    data object RealtimeSettings : Screen("settings/realtime")
    data object RecordingDetail : Screen("recording/{recordingId}") {
        fun createRoute(recordingId: String) = "recording/$recordingId"
    }
}
