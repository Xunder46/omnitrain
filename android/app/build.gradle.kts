plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // The `io.sentry.android.gradle` plugin is injected automatically by
    // the `sentry_dart_plugin` build hook (see pubspec.yaml and
    // `.github/agents/plans/crash-reporting-plan.md`) on release
    // builds. It is responsible for uploading the ProGuard/R8
    // `mapping.txt` to Sentry so JVM stack traces symbolicate.
}

android {
    namespace = "dev.sasha.omnitrain"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "dev.sasha.omnitrain"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // ProGuard is required so the Sentry Android plugin can
            // upload the resulting `mapping.txt` to Sentry for
            // symbolication of JVM stack traces. The contract is
            // enforced by `scripts/pre_release_check.sh` — a release
            // without mapping upload fails the pre-release gate.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
