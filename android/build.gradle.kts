// Force-raise the Kotlin language/api version for every sub-project.
//
// The current Android Sentry Gradle plugin (used by `sentry_dart_plugin`
// in `pubspec.yaml` for crash-reporting symbolication) prescribes
// `languageVersion = "1.6"` in its own `build.gradle`. With Kotlin 2.x
// in `settings.gradle.kts` the compiler now refuses that with the
// message "Language version 1.6 is no longer supported". The override
// below promotes every sub-project's Kotlin compile to 1.9 so Sentry's
// own builds complete under our pin. See
// `docs/plans/crash-reporting-plan.md` for the ADR.
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion as KVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                languageVersion.set(KVersion.KOTLIN_1_9)
                apiVersion.set(KVersion.KOTLIN_1_9)
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
