package com.vanta.speech.core.di

import com.vanta.speech.core.auth.SecurePreferencesManager
import com.vanta.speech.core.eas.EASCalendarManager
import com.vanta.speech.core.eas.api.EASClient
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt module for EAS (Exchange ActiveSync) dependencies
 */
@Module
@InstallIn(SingletonComponent::class)
object EASModule {

    @Provides
    @Singleton
    fun provideEASClient(
        securePreferencesManager: SecurePreferencesManager
    ): EASClient {
        return EASClient(securePreferencesManager)
    }

    @Provides
    @Singleton
    fun provideEASCalendarManager(
        client: EASClient,
        securePreferencesManager: SecurePreferencesManager
    ): EASCalendarManager {
        return EASCalendarManager(client, securePreferencesManager)
    }
}
