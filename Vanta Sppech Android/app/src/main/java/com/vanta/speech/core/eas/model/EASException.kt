package com.vanta.speech.core.eas.model

import kotlinx.serialization.Serializable
import java.util.Date

/**
 * Exception (modified occurrence) for a recurring event
 */
@Serializable
data class EASException(
    /** The original start time of this occurrence (used to identify which occurrence is modified) */
    val originalStartTimeMillis: Long,

    /** Modified start time (if null, occurrence is deleted) */
    val startTimeMillis: Long? = null,

    /** Modified end time */
    val endTimeMillis: Long? = null,

    /** Modified subject */
    val subject: String? = null,

    /** Modified location */
    val location: String? = null,

    /** Whether this exception is a deletion */
    val isDeleted: Boolean = false
) {
    /** Original start time as Date */
    val originalStartTime: Date
        get() = Date(originalStartTimeMillis)

    /** Modified start time as Date */
    val startTime: Date?
        get() = startTimeMillis?.let { Date(it) }

    /** Modified end time as Date */
    val endTime: Date?
        get() = endTimeMillis?.let { Date(it) }
}
