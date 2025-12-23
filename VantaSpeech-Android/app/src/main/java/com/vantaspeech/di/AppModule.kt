package com.vantaspeech.di

import android.content.Context
import com.vantaspeech.data.repository.RecordingDao
import com.vantaspeech.data.repository.RecordingDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideRecordingDatabase(
        @ApplicationContext context: Context
    ): RecordingDatabase {
        return RecordingDatabase.getInstance(context)
    }

    @Provides
    @Singleton
    fun provideRecordingDao(database: RecordingDatabase): RecordingDao {
        return database.recordingDao()
    }
}
