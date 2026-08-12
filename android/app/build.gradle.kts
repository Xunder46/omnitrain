import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // NOTE: `io.sentry.android.gradle` is NOT applied here, and is NOT
    // injected by `sentry_dart_plugin` — that package is a standalone
    // Dart CLI with no Gradle integration whatsoever. An earlier comment
    // in this file claimed otherwise, which hid the gap.
    //
    // Consequence: the R8 `mapping.txt` this build produces is never
    // uploaded, so JVM stack traces arrive in Sentry obfuscated. Dart
    // stack traces — the large majority of Flutter crashes — are
    // unaffected, and native/dSYM symbols DO upload via the
    // `dart run sentry_dart_plugin` step in the release workflow.
    //
    // To close the gap, apply the plugin here and configure it:
    //     id("io.sentry.android.gradle") version "<latest>"
    // Left unapplied deliberately for now: it changes the Android build
    // graph and must be validated on a machine with the Android SDK
    // before it goes anywhere near a release.
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.sasha.omnitrain"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "dev.sasha.omnitrain"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ProGuard is required so the Sentry Android plugin can
            // upload the resulting `mapping.txt` to Sentry for
            // symbolication of JVM stack traces. The contract is
            // enforced by `scripts/pre_release_check.sh` — a release
            // without mapping upload fails the pre-release gate.
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}