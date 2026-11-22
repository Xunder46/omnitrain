package dev.sasha.omnitrain

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

/** The wrist's sensors (plan 298): heart rate over Health Services. */
fun registerSensors(activity: Activity, engine: FlutterEngine): SensorBridge? =
    WearSensors(activity, engine.dartExecutor.binaryMessenger)
