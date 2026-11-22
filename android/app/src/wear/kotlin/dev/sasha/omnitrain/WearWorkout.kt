// The Wear wrist's platform workout: a Health Services exercise behind the
// channel the Dart side (`WearPlatformWorkoutStore`, plan 300) calls.
//
// Plan: `docs/plans/2026-11-22-300-wear-platform-workout-plan/2026-11-22-300-wear-platform-workout-plan.md`
// (D-30003, D-30004). Logging never depends on a platform workout, so nothing
// here throws into Dart: a failure leaves `begin` a no-op and `end` safe.

package dev.sasha.omnitrain

import android.app.Activity
import android.content.Intent
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WearWorkout(
    private val activity: Activity,
    messenger: BinaryMessenger,
    /** Whether the body-sensor permission is held: an exercise needs it. */
    private val holdsBodySensors: () -> Boolean,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHODS = "omnitrain/wear_workout/methods"
    }

    private fun client(): ExerciseClient = HealthServices.getClient(activity).exerciseClient

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "begin" -> begin(call.arguments as? String, result)
            "end" -> end(result)
            "inProgress" -> inProgress(result)
            else -> result.notImplemented()
        }
    }

    private fun begin(name: String?, result: MethodChannel.Result) {
        if (name == null || !holdsBodySensors()) {
            result.success(null)
            return
        }
        val future = try {
            val config = ExerciseConfig.builder(exerciseTypeFor(name))
                .setDataTypes(setOf(DataType.HEART_RATE_BPM))
                .setIsAutoPauseAndResumeEnabled(false)
                .setIsGpsEnabled(false)
                .build()
            client().startExerciseAsync(config)
        } catch (error: Exception) {
            result.success(null)
            return
        }
        future.addListener(
            {
                val started = try {
                    future.get()
                    true
                } catch (error: Exception) {
                    false
                }
                if (started) startService()
                result.success(null)
            },
            activity.mainExecutor,
        )
    }

    private fun end(result: MethodChannel.Result) {
        val future = try {
            client().endExerciseAsync()
        } catch (error: Exception) {
            stopService()
            result.success(null)
            return
        }
        future.addListener(
            {
                stopService()
                result.success(null)
            },
            activity.mainExecutor,
        )
    }

    private fun inProgress(result: MethodChannel.Result) {
        val future = try {
            client().getCurrentExerciseInfoAsync()
        } catch (error: Exception) {
            result.success(emptyList<String>())
            return
        }
        future.addListener(
            {
                val owned = try {
                    future.get().exerciseTrackedStatus ==
                        ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS
                } catch (error: Exception) {
                    false
                }
                result.success(if (owned) listOf("exercise_in_progress") else emptyList<String>())
            },
            activity.mainExecutor,
        )
    }

    /** The service keeps the process alive while the exercise runs. */
    private fun startService() {
        try {
            activity.startForegroundService(Intent(activity, WorkoutService::class.java))
        } catch (error: Exception) {
            // The exercise still runs; only the process priority is lost.
        }
    }

    private fun stopService() {
        activity.stopService(Intent(activity, WorkoutService::class.java))
    }

    /** The Health Connect names the Dart table produces; anything else is a generic workout. */
    private fun exerciseTypeFor(name: String): ExerciseType = when (name) {
        "exercise_type_running" -> ExerciseType.RUNNING
        "exercise_type_walking" -> ExerciseType.WALKING
        "exercise_type_biking" -> ExerciseType.BIKING
        "exercise_type_swimming" -> ExerciseType.SWIMMING_POOL
        "exercise_type_rowing" -> ExerciseType.ROWING
        "exercise_type_hiking" -> ExerciseType.HIKING
        "exercise_type_strength_training" -> ExerciseType.STRENGTH_TRAINING
        "exercise_type_calisthenics" -> ExerciseType.CALISTHENICS
        "exercise_type_flexibility", "exercise_type_stretching" -> ExerciseType.STRETCHING
        "exercise_type_yoga" -> ExerciseType.YOGA
        "exercise_type_boxing" -> ExerciseType.BOXING
        "exercise_type_martial_arts" -> ExerciseType.MARTIAL_ARTS
        "exercise_type_tennis" -> ExerciseType.TENNIS
        "exercise_type_badminton" -> ExerciseType.BADMINTON
        "exercise_type_table_tennis" -> ExerciseType.TABLE_TENNIS
        "exercise_type_cricket" -> ExerciseType.CRICKET
        "exercise_type_basketball" -> ExerciseType.BASKETBALL
        "exercise_type_baseball" -> ExerciseType.BASEBALL
        "exercise_type_golf" -> ExerciseType.GOLF
        "exercise_type_volleyball" -> ExerciseType.VOLLEYBALL
        "exercise_type_squash" -> ExerciseType.SQUASH
        "exercise_type_rugby" -> ExerciseType.RUGBY
        "exercise_type_rock_climbing" -> ExerciseType.ROCK_CLIMBING
        else -> ExerciseType.WORKOUT
    }

    init {
        MethodChannel(messenger, METHODS).setMethodCallHandler(this)
    }
}
