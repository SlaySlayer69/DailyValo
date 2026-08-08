import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from `android/key.properties` locally or from the
// environment in CI. Both are absent on a fresh clone, which is deliberate: the
// build still works, it just falls back to the debug key.
//
// This matters more than it looks. Android identifies an app by its signature,
// so two builds signed with different keys cannot replace one another — the
// install fails and the only way through is to uninstall, which takes the
// wishlist and cached collection with it. The debug keystore is generated per
// machine, so debug-signed releases from a laptop and from a CI runner are
// *different apps* to Android. One real key, used everywhere, is what makes
// upgrades work.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, env: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(env)

val keystorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseKey = keystorePath != null && file(keystorePath).exists()

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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystorePath!!)
                storePassword =
                    signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key when no release keystore is
            // configured, so `flutter build apk --release` keeps working on a
            // fresh clone. A build that falls back is fine for testing and
            // unfit for distribution — see docs/RELEASING.md.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "DailyValo: no release keystore found, signing with the " +
                        "debug key. This APK cannot upgrade an install signed " +
                        "by any other machine.",
                )
                signingConfigs.getByName("debug")
            }

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
