package com.vanta.speech.core.di

import android.content.Context
import com.vanta.speech.core.calendar.GraphCalendarService
import com.vanta.speech.core.calendar.MSALAuthManager
import com.vanta.speech.core.calendar.OutlookCalendarManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object CalendarModule {

    @Provides
    @Singleton
    fun provideMSALAuthManager(
        @ApplicationContext context: Context
    ): MSALAuthManager {
        return MSALAuthManager(context)
    }

    @Provides
    @Singleton
    fun provideGraphCalendarService(
        authManager: MSALAuthManager
    ): GraphCalendarService {
        return GraphCalendarService(authManager)
    }

    @Provides
    @Singleton
    fun provideOutlookCalendarManager(
        authManager: MSALAuthManager,
        calendarService: GraphCalendarService
    ): OutlookCalendarManager {
        return OutlookCalendarManager(authManager, calendarService)
    }
}
