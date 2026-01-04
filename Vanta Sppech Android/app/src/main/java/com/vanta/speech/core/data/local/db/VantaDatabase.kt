package com.vanta.speech.core.data.local.db

import androidx.room.Database
import androidx.room.RoomDatabase
import com.vanta.speech.core.data.local.entity.RecordingEntity

@Database(
    entities = [RecordingEntity::class],
    version = 1,
    exportSchema = false
)
abstract class VantaDatabase : RoomDatabase() {
    abstract fun recordingDao(): RecordingDao
}
