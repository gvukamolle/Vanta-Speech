package com.vanta.speech.core.di

import com.vanta.speech.core.data.repository.RecordingRepositoryImpl
import com.vanta.speech.core.data.repository.TranscriptionRepositoryImpl
import com.vanta.speech.core.domain.repository.RecordingRepository
import com.vanta.speech.core.domain.repository.TranscriptionRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindRecordingRepository(
        impl: RecordingRepositoryImpl
    ): RecordingRepository

    @Binds
    @Singleton
    abstract fun bindTranscriptionRepository(
        impl: TranscriptionRepositoryImpl
    ): TranscriptionRepository
}
