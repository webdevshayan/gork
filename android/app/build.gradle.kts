plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.shayan.gork"
    compileSdk = flutter.compileSdkVersion

    // The Flutter plugin forces an NDK download via a synthetic empty CMake
    // build. Nothing in this app compiles native code, so this runs after
    // the plugin's own finalizeDsl and clears that path. The NDK is still
    // needed by AGP's strip step (packaging): the Flutter engine .so ships
    // unstripped upstream and StripNativeLibraries is what slims it into
    // the APK. Keeping debug symbols here instead shipped a 169 MB engine
    // in v1.5.0 — the blanket is gone on purpose.
    androidComponents {
        finalizeDsl { extension ->
            extension.externalNativeBuild.cmake.path = null
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.shayan.gork"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_secure_storage requires API 23+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        // The 4 GB build box OOMs lint-vital in metaspace while analyzing
        // plugin Kotlin (image_picker_android) — it killed the v1.6.0 build
        // after the whole compile had succeeded. The gradle JVM is capped
        // at 1 GB (see gradle.properties); lint-vital needs more than that.
        // The app's quality gates are the flutter test suite and the
        // release size gate (scripts/check_release_apk.sh), not lint.
        checkReleaseBuilds = false
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
