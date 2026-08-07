plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dailyvalo.dailyvalo"
    // Pinned rather than tracking `flutter.compileSdkVersion`: the
    // flutter_secure_storage 11 Android module declares compileSdk 37, and
    // Gradle requires the app to compile against at least the highest SDK any
    // of its plugins uses. Install "Android SDK Platform 37" via the SDK
    // Manager if a build fails to resolve it.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications 10+, which uses java.time on
        // API levels that predate it. The plugin fails to build without this
        // even when scheduled notifications are unused.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.dailyvalo.app"

        // API 24 is the floor imposed by our plugins:
        // flutter_local_notifications (24) and flutter_secure_storage, whose
        // Keystore-backed AES-GCM path needs 23+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The notification plugin pulls in enough of androidx to cross the
        // 64k method limit on older toolchains.
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Replace with a real signing config before publishing.
            // Debug keys keep `flutter run --release` working in the meantime.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
