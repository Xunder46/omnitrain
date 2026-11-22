// The Wear wrist's heart rate: Health Services' MeasureClient behind the channels
// the Dart side (`lib/watch/sensors/wear_sensor_source.dart`, plan 297) listens
// to.
//
// Plan: `docs/plans/2026-11-22-298-wear-heart-rate-plan/2026-11-22-298-wear-heart-rate-plan.md`
// (D-29802..D-29804). Logging never depends on a sensor, so nothing here throws
// into Dart: a failure answers `unavailable` or ends the stream.

package dev.sasha.omnitrain

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WearSensors(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : SensorBridge, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHODS = "omnitrain/wear_sensors/methods"
        const val HEART_RATE = "omnitrain/wear_sensors/heart_rate"

        private const val REQUEST_HEART_RATE = 29801
    }

    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var callback: MeasureCallback? = null

    /** Permission questions in flight: they all wait on one system prompt. */
    private val waiting = mutableListOf<MethodChannel.Result>()

    init {
        MethodChannel(messenger, METHODS).setMethodCallHandler(this)
        EventChannel(messenger, HEART_RATE).setStreamHandler(this)
    }

    private fun measureClient() = HealthServices.getClient(activity).measureClient

    /** Heart rate moved to the health permission group on Wear OS 6 (API 36). */
    private fun heartRatePermissionName(): String =
        if (Build.VERSION.SDK_INT >= 36) {
            "android.permission.health.READ_HEART_RATE"
        } else {
            android.Manifest.permission.BODY_SENSORS
        }

    private fun heartRateGranted(): Boolean =
        activity.checkSelfPermission(heartRatePermissionName()) ==
            PackageManager.PERMISSION_GRANTED

    // MARK: - Permission

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "heartRatePermission" -> heartRatePermission(result)
            // Distance is plan 299.
            "locationPermission" -> result.success("unavailable")
            else -> result.notImplemented()
        }
    }

    private fun heartRatePermission(result: MethodChannel.Result) {
        val future = try {
            measureClient().getCapabilitiesAsync()
        } catch (error: Exception) {
            result.success("unavailable")
            return
        }
        future.addListener(
            {
                val supported = try {
                    future.get().supportedDataTypesMeasure.contains(DataType.HEART_RATE_BPM)
                } catch (error: Exception) {
                    false
                }
                when {
                    !supported -> result.success("unavailable")
                    heartRateGranted() -> result.success("granted")
                    else -> askHeartRate(result)
                }
            },
            activity.mainExecutor,
        )
    }

    private fun askHeartRate(result: MethodChannel.Result) {
        waiting.add(result)
        if (waiting.size == 1) {
            activity.requestPermissions(arrayOf(heartRatePermissionName()), REQUEST_HEART_RATE)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_HEART_RATE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val answer = if (granted) "granted" else "denied"
        val pending = waiting.toList()
        waiting.clear()
        for (result in pending) result.success(answer)
        return true
    }

    // MARK: - Readings

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (!heartRateGranted()) {
            events?.endOfStream()
            return
        }
        stopMeasuring()
        val measuring = object : MeasureCallback {
            override fun onAvailabilityChanged(
                dataType: DeltaDataType<*, *>,
                availability: Availability,
            ) {
                // Acquiring or off-wrist: no reading is sent until there is one.
            }

            override fun onDataReceived(data: DataPointContainer) {
                val reading = data.getData(DataType.HEART_RATE_BPM).lastOrNull() ?: return
                main.post { sink?.success(reading.value) }
            }
        }
        callback = measuring
        try {
            measureClient().registerMeasureCallback(DataType.HEART_RATE_BPM, measuring)
        } catch (error: Exception) {
            callback = null
            events?.endOfStream()
        }
    }

    override fun onCancel(arguments: Any?) {
        stopMeasuring()
        sink = null
    }

    private fun stopMeasuring() {
        val measuring = callback ?: return
        callback = null
        try {
            measureClient().unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, measuring)
        } catch (error: Exception) {
            // The platform already dropped it (the permission was revoked).
        }
    }
}
