package com.vanta.speech.core.di

import android.content.Context
import com.vanta.speech.core.auth.AuthenticationManager
import com.vanta.speech.core.auth.LDAPAuthService
import com.vanta.speech.core.auth.SecurePreferencesManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AuthModule {

    @Provides
    @Singleton
    fun provideLDAPAuthService(): LDAPAuthService {
        return LDAPAuthService()
    }

    @Provides
    @Singleton
    fun provideSecurePreferencesManager(
        @ApplicationContext context: Context
    ): SecurePreferencesManager {
        return SecurePreferencesManager(context)
    }

    @Provides
    @Singleton
    fun provideAuthenticationManager(
        ldapAuthService: LDAPAuthService,
        securePreferencesManager: SecurePreferencesManager
    ): AuthenticationManager {
        return AuthenticationManager(ldapAuthService, securePreferencesManager)
    }
}
