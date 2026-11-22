package dev.sasha.omnitrain

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

/** The wrist's sensors and platform workout (plans 298 to 300) over Health Services. */
fun registerSensors(activity: Activity, engine: FlutterEngine): SensorBridge? {
    val messenger = engine.dartExecutor.binaryMessenger
    val sensors = WearSensors(activity, messenger)
    WearWorkout(activity, messenger) { sensors.heartRateGranted() }
    return sensors
}
