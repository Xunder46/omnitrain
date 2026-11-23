// The Wear wrist's calorie count on its way to Dart: the platform workout's
// cumulative energy, one number per update, on the channel
// `WearSensorSource.energyName` (`lib/watch/sensors/wear_sensor_source.dart`).
//
// Plan: `docs/plans/2026-11-22-306-wear-calories-native-plan/2026-11-22-306-wear-calories-native-plan.md`
// (D-30603). The Dart recorder (plan 305) stores each number, decides what is
// sent to the phone and shows it. Nothing here throws into Dart: with nobody
// listening a number is dropped, and the next update replaces it.

package dev.sasha.omnitrain

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

class EnergyStream(messenger: BinaryMessenger) : EventChannel.StreamHandler {

    companion object {
        const val CHANNEL = "omnitrain/wear_sensors/energy"
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    /** Puts [kilocalories] (cumulative since the workout began) on the stream. */
    fun emit(kilocalories: Double) {
        main.post { sink?.success(kilocalories) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    init {
        EventChannel(messenger, CHANNEL).setStreamHandler(this)
    }
}
