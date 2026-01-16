# Vanta Speech ProGuard Rules
# ============================================================================

# ============================================================================
# RETROFIT & OKHTTP
# ============================================================================
-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*

-keep class retrofit2.** { *; }
-keepclassmembers,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}

-dontwarn okhttp3.**
-dontwarn okio.**

# ============================================================================
# GSON - CRITICAL для десериализации JSON
# ============================================================================
-keep class com.google.gson.** { *; }

# DTO классы - защищаем поля для GSON
-keep class com.vanta.speech.core.data.remote.dto.ChatRequest { *; }
-keep class com.vanta.speech.core.data.remote.dto.ChatMessage { *; }
-keep class com.vanta.speech.core.data.remote.dto.ChatResponse { *; }
-keep class com.vanta.speech.core.data.remote.dto.ChatResponse$* { *; }
-keep class com.vanta.speech.core.data.remote.dto.WhisperResponse { *; }

# Graph/Calendar models
-keep class com.vanta.speech.core.calendar.model.** { *; }

# EWS models
-keep class com.vanta.speech.core.ews.model.** { *; }

# ============================================================================
# ROOM DATABASE - CRITICAL
# ============================================================================
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao interface * { *; }
-dontwarn androidx.room.paging.**

# ============================================================================
# HILT DEPENDENCY INJECTION - CRITICAL
# ============================================================================
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }

# Hilt ViewModels
-keep class * extends androidx.lifecycle.ViewModel { *; }

# ============================================================================
# MICROSOFT IDENTITY / MSAL - CRITICAL для Outlook Calendar
# ============================================================================
-keep class com.microsoft.identity.** { *; }
-keep interface com.microsoft.identity.** { *; }
-dontwarn com.microsoft.identity.**
-dontwarn edu.umd.cs.findbugs.annotations.**

# ============================================================================
# OPENTELEMETRY (MSAL dependency)
# ============================================================================
-dontwarn io.opentelemetry.**

# ============================================================================
# BUILD CONFIG - CRITICAL для API ключей
# ============================================================================
-keep class com.vanta.speech.BuildConfig { *; }

# ============================================================================
# AUTH - UserSession model
# ============================================================================
-keep class com.vanta.speech.core.auth.model.UserSession { *; }

# ============================================================================
# SERVICES
# ============================================================================
-keep class com.vanta.speech.service.RecordingService { *; }

# ============================================================================
# KOTLINX SERIALIZATION
# ============================================================================
-dontwarn kotlinx.serialization.**

# ============================================================================
# COMPOSE
# ============================================================================
-dontwarn androidx.compose.**

# ============================================================================
# KOTLIN
# ============================================================================
-keep class kotlin.Metadata { *; }
