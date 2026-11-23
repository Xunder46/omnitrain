package dev.sasha.omnitrain

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status

/**
 * Keeps the app's process alive while a workout runs (plan 300, D-30004): a
 * foreground service of type `health` with an ongoing notification that opens
 * the app. Started when the Health Services exercise started, stopped when it
 * ends; never restarted by the system.
 *
 * Plan 309: the notification also carries an Ongoing Activity, so the watch
 * face shows a tappable chip with the workout's icon, its name and a running
 * stopwatch. The chip is the platform's: nothing here updates it after the
 * first post.
 */
class WorkoutService : Service() {

    companion object {
        private const val CHANNEL_ID = "omnitrain_workout"
        private const val NOTIFICATION_ID = 30001

        /** The intent extra `WearWorkout` puts the Health Connect type name in. */
        const val EXTRA_ACTIVITY = "activityType"

        private const val NAME_PREFIX = "exercise_type_"
        private const val FALLBACK_LABEL = "Workout"

        /**
         * The words on the chip for a Health Connect type name:
         * `exercise_type_strength_training` reads `Strength training`. A missing,
         * empty or unfamiliar name reads `Workout`.
         */
        fun labelFor(name: String?): String {
            if (name == null || !name.startsWith(NAME_PREFIX)) return FALLBACK_LABEL
            val words = name.removePrefix(NAME_PREFIX).replace('_', ' ').trim()
            if (words.isEmpty()) return FALLBACK_LABEL
            return words.replaceFirstChar { it.uppercase() }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Workout", NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val label = labelFor(intent?.getStringExtra(EXTRA_ACTIVITY))
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_workout)
            .setContentTitle("OmniTrain")
            .setContentText("$label in progress")
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setOngoing(true)
            .setContentIntent(open)

        val status = Status.Builder()
            .addTemplate("#type# #time#")
            .addPart("type", Status.TextPart(label))
            .addPart("time", Status.StopwatchPart(SystemClock.elapsedRealtime()))
            .build()
        OngoingActivity.Builder(applicationContext, NOTIFICATION_ID, builder)
            .setStaticIcon(R.drawable.ic_workout)
            .setTouchIntent(open)
            .setStatus(status)
            .build()
            .apply(applicationContext)

        startForeground(NOTIFICATION_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        return START_NOT_STICKY
    }
}
