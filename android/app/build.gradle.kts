import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.speakcards"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.speakcards"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Plain semver in pubspec (e.g. 0.1.1); derive a versionCode
        // that rises with every patch bump.
        val semver = flutter.versionName.split(".").map { it.toInt() }
        versionCode = semver[0] * 1000000 + semver[1] * 1000 + semver[2]
        versionName = flutter.versionName
    }

    // Release keystore credentials live in android/key.properties (gitignored).
    // CI restores it from SPEAKCARDS_* secrets; locally it points at
    // android/speakcards-release.jks. Without it, release falls back to
    // debug keys so `flutter run` still works.
    val keyProps = Properties()
    val keyPropsFile = rootProject.file("key.properties")
    if (keyPropsFile.exists()) {
        FileInputStream(keyPropsFile).use { keyProps.load(it) }
    }

    signingConfigs {
        create("release") {
            if (keyPropsFile.exists()) {
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropsFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
