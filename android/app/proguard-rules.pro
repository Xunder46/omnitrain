# ProGuard / R8 rules for OmniTrain release builds.
#
# R8 runs automatically because `isMinifyEnabled = true` is set on
# `release` in `android/app/build.gradle.kts`. The mapping file the
# build produces (`app/build/outputs/mapping/release/mapping.txt`)
# is uploaded to Sentry by the Sentry Android Gradle plugin (also
# applied in `build.gradle.kts`) so that JVM stack traces captured
# by `sentry-android` can be symbolicated in the dashboard.
#
# Sentry's AAR ships a `consumer-rules.pro` that supplies the
# `-keep` directives the SDK needs at runtime — no manual keeps are
# required from this app. We only need to suppress a couple of
# R8 warnings that come from reflective access into native code
# paths the app does not use.

# Quiet the "missing class" warnings for native senders/protos that
# are not bundled into the release build. The optional integrations
# (`sentry-android-fragment`, `sentry-android-timber`,
# `sentry-compose-android`) are not on the dependency graph, so R8
# sees their classes as unreachable.
-dontwarn io.sentry.android.fragment.**
-dontwarn io.sentry.android.timber.**
-dontwarn io.sentry.compose.**

# Flutter deferred components (Play Core) — unused, safe to ignore
-dontwarn com.google.android.play.core.**

# Sentry
-dontwarn io.sentry.**
-keep class io.sentry.** { *; }

# flutter_local_notifications uses Gson TypeTokens to deserialize queued
# notification payloads. Keep generic signature metadata and plugin models
# so release shrinking cannot break timer notification schedule/cancel paths.
-keepattributes Signature
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken