package com.vanta.speech.core.di

import android.content.Context
import androidx.room.Room
import com.vanta.speech.core.data.local.db.RecordingDao
import com.vanta.speech.core.data.local.db.VantaDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context
    ): VantaDatabase = Room.databaseBuilder(
        context,
        VantaDatabase::class.java,
        "vanta_speech.db"
    ).build()

    @Provides
    @Singleton
    fun provideRecordingDao(database: VantaDatabase): RecordingDao =
        database.recordingDao()
}
