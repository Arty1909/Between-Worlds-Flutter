plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.betweenworlds.between_worlds"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Coexists with the legacy app, preserving its installed saves.
        applicationId = "com.betweenworlds.story.flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Filter native dependencies as well as Flutter's engine binaries.
        // Flutter's --target-platform alone can leave other ABIs in plugin AARs.
        ndk {
            abiFilters += (project.findProperty("target-platform") as String?
                ?: "android-arm64").split(",").map {
                when (it.trim()) {
                    "android-arm64" -> "arm64-v8a"
                    "android-arm" -> "armeabi-v7a"
                    "android-x64" -> "x86_64"
                    else -> throw GradleException("Unsupported Android target: $it")
                }
            }
        }
    }

    // Source archives omit private signing files. Debug builds remain usable
    // on a new machine; release signing is enabled when the owner supplies them.
    val releaseStore = rootProject.file("signing/between-worlds.jks")
    val releasePassword = rootProject.file("signing/store-password.txt")
    val hasReleaseSigning = releaseStore.isFile && releasePassword.isFile
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStore
                storePassword = releasePassword.readText().trim()
                keyAlias = "between-worlds"
                keyPassword = storePassword
            }
        }
    }
    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
