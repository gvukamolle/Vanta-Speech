package com.vanta.speech.core.di

import android.content.Context
import com.vanta.speech.core.audio.AudioPlayer
import com.vanta.speech.core.audio.AudioRecorder
import com.vanta.speech.core.audio.RealtimeTranscriptionManager
import com.vanta.speech.core.audio.VoiceActivityDetector
import com.vanta.speech.core.data.remote.api.TranscriptionApi
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AudioModule {

    @Provides
    @Singleton
    fun provideAudioRecorder(
        @ApplicationContext context: Context
    ): AudioRecorder = AudioRecorder(context)

    @Provides
    @Singleton
    fun provideAudioPlayer(
        @ApplicationContext context: Context
    ): AudioPlayer = AudioPlayer(context)

    @Provides
    @Singleton
    fun provideVoiceActivityDetector(): VoiceActivityDetector = VoiceActivityDetector()

    @Provides
    @Singleton
    fun provideRealtimeTranscriptionManager(
        @ApplicationContext context: Context,
        transcriptionApi: TranscriptionApi,
        voiceActivityDetector: VoiceActivityDetector
    ): RealtimeTranscriptionManager = RealtimeTranscriptionManager(
        context = context,
        transcriptionApi = transcriptionApi,
        voiceActivityDetector = voiceActivityDetector
    )
}
