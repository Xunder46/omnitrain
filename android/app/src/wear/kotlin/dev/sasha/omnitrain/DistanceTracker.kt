package dev.sasha.omnitrain

import android.location.Location

/**
 * The distance a workout has covered, from the fixes the location provider
 * reports (plan 299, D-29903). A fix with no accuracy, or worse than
 * [MAX_ACCURACY_M], is not used; the first good fix starts the total at 0; each
 * later fix adds the straight-line step from the one before, unless covering it
 * would take more than [MAX_SPEED_MPS]: an impossible jump (a cached fix from
 * somewhere else, a lost lock) is a new starting point, not distance.
 */
class DistanceTracker {

    companion object {
        const val MAX_ACCURACY_M = 50f

        /** About 54 km/h: faster than any run, slower than any glitch. */
        const val MAX_SPEED_MPS = 15.0
    }

    private var lastLatitude: Double? = null
    private var lastLongitude: Double? = null
    private var lastNanos = 0L
    private var total = 0.0

    /**
     * The new total in metres after a fix taken at [elapsedNanos] (the device's
     * elapsed-realtime clock), or null when the fix is not used.
     */
    fun accept(latitude: Double, longitude: Double, accuracy: Float?, elapsedNanos: Long): Double? {
        if (accuracy == null || accuracy > MAX_ACCURACY_M) return null
        val previousLatitude = lastLatitude
        val previousLongitude = lastLongitude
        if (previousLatitude != null && previousLongitude != null) {
            val seconds = (elapsedNanos - lastNanos) / 1e9
            if (seconds <= 0.0) return null
            val step = FloatArray(1)
            Location.distanceBetween(previousLatitude, previousLongitude, latitude, longitude, step)
            if (step[0] / seconds <= MAX_SPEED_MPS) total += step[0]
        }
        lastLatitude = latitude
        lastLongitude = longitude
        lastNanos = elapsedNanos
        return total
    }

    /** Forgets the last fix and the total: the next workout starts from 0. */
    fun reset() {
        lastLatitude = null
        lastLongitude = null
        lastNanos = 0L
        total = 0.0
    }
}
