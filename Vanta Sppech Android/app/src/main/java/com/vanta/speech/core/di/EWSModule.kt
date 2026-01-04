package com.vanta.speech.core.di

import com.vanta.speech.core.auth.SecurePreferencesManager
import com.vanta.speech.core.ews.EWSAuthManager
import com.vanta.speech.core.ews.EWSCalendarManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object EWSModule {

    @Provides
    @Singleton
    fun provideEWSAuthManager(
        securePrefs: SecurePreferencesManager
    ): EWSAuthManager {
        return EWSAuthManager(securePrefs)
    }

    @Provides
    @Singleton
    fun provideEWSCalendarManager(
        authManager: EWSAuthManager
    ): EWSCalendarManager {
        return EWSCalendarManager(authManager)
    }
}
