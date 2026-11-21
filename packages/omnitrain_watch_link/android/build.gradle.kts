// The Android half of `omnitrain_watch_link`: the Wear OS data layer.
//
// One plugin, two devices. The phone app and the wear app ship the same Flutter
// project, so this module is compiled into both, and the native side decides
// which role it is playing from the device's own feature set (`FEATURE_WATCH`).
// Everything it does is symmetrical: it finds the *peer* node and carries frames
// to and from it.
//
// `play-services-wearable` is the only dependency. There is deliberately no
// `androidx.wear` dependency: the wrist's UI is Flutter, and the only thing this
// module adds to the app is the radio.

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "dev.sasha.omnitrain.watch_link"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The app's own floor. The wear flavor raises the *app* floor to Wear OS
        // 3 (API 30); a library below that is fine.
        minSdk = 26
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
}
