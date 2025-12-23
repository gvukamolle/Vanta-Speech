package com.vantaspeech.data.repository

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.vantaspeech.data.model.Recording

@Database(
    entities = [Recording::class],
    version = 1,
    exportSchema = true
)
abstract class RecordingDatabase : RoomDatabase() {
    abstract fun recordingDao(): RecordingDao

    companion object {
        private const val DATABASE_NAME = "vanta_speech.db"

        @Volatile
        private var INSTANCE: RecordingDatabase? = null

        fun getInstance(context: Context): RecordingDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: buildDatabase(context).also { INSTANCE = it }
            }
        }

        private fun buildDatabase(context: Context): RecordingDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                RecordingDatabase::class.java,
                DATABASE_NAME
            )
                .fallbackToDestructiveMigration()
                .build()
        }
    }
}
