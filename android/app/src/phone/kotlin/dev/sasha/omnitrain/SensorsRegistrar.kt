package dev.sasha.omnitrain

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine

/** The phone has no wrist sensors (plan 298): nothing to register. */
@Suppress("UNUSED_PARAMETER")
fun registerSensors(activity: Activity, engine: FlutterEngine): SensorBridge? = null
