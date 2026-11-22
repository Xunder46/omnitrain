package dev.sasha.omnitrain

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.IBinder

/**
 * Keeps the app's process alive while a workout runs (plan 300, D-30004): a
 * foreground service of type `health` with an ongoing notification that opens
 * the app. Started when the Health Services exercise started, stopped when it
 * ends; never restarted by the system.
 */
class WorkoutService : Service() {

    companion object {
        private const val CHANNEL_ID = "omnitrain_workout"
        private const val NOTIFICATION_ID = 30001
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
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(Icon.createWithResource(this, applicationInfo.icon))
            .setContentTitle("OmniTrain")
            .setContentText("Workout in progress")
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        return START_NOT_STICKY
    }
}
