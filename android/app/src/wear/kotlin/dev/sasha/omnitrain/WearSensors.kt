// The Wear wrist's heart rate: Health Services' MeasureClient behind the channels
// the Dart side (`lib/watch/sensors/wear_sensor_source.dart`, plan 297) listens
// to.
//
// Plan: `docs/plans/2026-11-22-298-wear-heart-rate-plan/2026-11-22-298-wear-heart-rate-plan.md`
// (D-29802..D-29804). Logging never depends on a sensor, so nothing here throws
// into Dart: a failure answers `unavailable` or ends the stream.

package dev.sasha.omnitrain

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
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
        const val LOCATION = "omnitrain/wear_sensors/location"

        private const val REQUEST_HEART_RATE = 29801
        private const val REQUEST_LOCATION = 29802

        /** How often high-accuracy fixes are asked for, and the smallest step worth one (plan 299). */
        private const val LOCATION_INTERVAL_MS = 2000L
        private const val LOCATION_MIN_STEP_M = 3f

        /** A fix older than this is a cached one from earlier, not where the user is (plan 299). */
        private const val MAX_FIX_AGE_NANOS = 10_000_000_000L
    }

    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var callback: MeasureCallback? = null

    /** Permission questions in flight: they all wait on one system prompt. */
    private val waiting = mutableListOf<MethodChannel.Result>()
    private val waitingLocation = mutableListOf<MethodChannel.Result>()

    private val tracker = DistanceTracker()
    private var locationSink: EventChannel.EventSink? = null
    private var locationUpdates: LocationCallback? = null

    private fun measureClient() = HealthServices.getClient(activity).measureClient

    /** Heart rate moved to the health permission group on Wear OS 6 (API 36). */
    private fun heartRatePermissionName(): String =
        if (Build.VERSION.SDK_INT >= 36) {
            "android.permission.health.READ_HEART_RATE"
        } else {
            android.Manifest.permission.BODY_SENSORS
        }

    fun heartRateGranted(): Boolean =
        activity.checkSelfPermission(heartRatePermissionName()) ==
            PackageManager.PERMISSION_GRANTED

    // MARK: - Permission

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "heartRatePermission" -> heartRatePermission(result)
            "locationPermission" -> locationPermission(result)
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
    ): Boolean = when (requestCode) {
        REQUEST_HEART_RATE -> answerHeartRate(grantResults)
        REQUEST_LOCATION -> answerLocation(permissions, grantResults)
        else -> false
    }

    private fun answerHeartRate(grantResults: IntArray): Boolean {
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val answer = if (granted) "granted" else "denied"
        val pending = waiting.toList()
        waiting.clear()
        for (result in pending) result.success(answer)
        return true
    }

    // MARK: - Location permission

    private fun locationGranted(): Boolean =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun locationPermission(result: MethodChannel.Result) {
        when {
            !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS) ->
                result.success("unavailable")
            locationGranted() -> result.success("granted")
            else -> askLocation(result)
        }
    }

    /** Android 12 and later want fine and coarse in one request. */
    private fun askLocation(result: MethodChannel.Result) {
        waitingLocation.add(result)
        if (waitingLocation.size == 1) {
            activity.requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
                REQUEST_LOCATION,
            )
        }
    }

    private fun answerLocation(permissions: Array<out String>, grantResults: IntArray): Boolean {
        val fine = permissions.indexOf(Manifest.permission.ACCESS_FINE_LOCATION)
        val granted = fine >= 0 && grantResults.getOrNull(fine) == PackageManager.PERMISSION_GRANTED
        val answer = if (granted) "granted" else "denied"
        val pending = waitingLocation.toList()
        waitingLocation.clear()
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

    // MARK: - Distance

    private fun fused() = LocationServices.getFusedLocationProviderClient(activity)

    private val locationStream = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            locationSink = events
            if (!locationGranted()) {
                events?.endOfStream()
                return
            }
            stopLocation()
            tracker.reset()
            val updates = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    for (fix in result.locations) {
                        if (SystemClock.elapsedRealtimeNanos() - fix.elapsedRealtimeNanos > MAX_FIX_AGE_NANOS) continue
                        val accuracy = if (fix.hasAccuracy()) fix.accuracy else null
                        val total = tracker.accept(
                            fix.latitude,
                            fix.longitude,
                            accuracy,
                            fix.elapsedRealtimeNanos,
                        ) ?: continue
                        main.post { locationSink?.success(total) }
                    }
                }
            }
            locationUpdates = updates
            val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, LOCATION_INTERVAL_MS)
                .setMinUpdateDistanceMeters(LOCATION_MIN_STEP_M)
                .build()
            try {
                fused().requestLocationUpdates(request, updates, Looper.getMainLooper())
            } catch (error: SecurityException) {
                locationUpdates = null
                events?.endOfStream()
            }
        }

        override fun onCancel(arguments: Any?) {
            stopLocation()
            locationSink = null
            tracker.reset()
        }
    }

    private fun stopLocation() {
        val updates = locationUpdates ?: return
        locationUpdates = null
        fused().removeLocationUpdates(updates)
    }

    // The channels attach last: `locationStream` must exist before they are set up.
    init {
        MethodChannel(messenger, METHODS).setMethodCallHandler(this)
        EventChannel(messenger, HEART_RATE).setStreamHandler(this)
        EventChannel(messenger, LOCATION).setStreamHandler(locationStream)
    }
}
