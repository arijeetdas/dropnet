import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Android only installs an update when it is signed with the
// same key as the installed app; otherwise it fails with "App not installed as
// package conflicts with an existing package". Release builds used to be signed
// with the *debug* key, and every CI runner generates a brand-new debug key, so
// no two published releases shared a signature.
//
// Provide the key either through android/key.properties (local builds; the
// file is git-ignored) with storeFile, storePassword, keyAlias, keyPassword,
// or through the DROPNET_KEYSTORE_PATH, DROPNET_KEYSTORE_PASSWORD,
// DROPNET_KEY_ALIAS and DROPNET_KEY_PASSWORD environment variables (CI).
val keystoreProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        FileInputStream(propertiesFile).use { load(it) }
    }
}

fun signingValue(propertyKey: String, environmentKey: String): String? =
    (keystoreProperties.getProperty(propertyKey) ?: System.getenv(environmentKey))
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

val releaseStorePath = signingValue("storeFile", "DROPNET_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "DROPNET_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "DROPNET_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "DROPNET_KEY_PASSWORD") ?: releaseStorePassword
val hasReleaseSigning =
    releaseStorePath != null && releaseStorePassword != null && releaseKeyAlias != null

android {
    namespace = "com.dropnet"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dropnet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // Relative paths are resolved from the android/ directory.
                val store = File(releaseStorePath!!)
                storeFile = if (store.isAbsolute) store else rootProject.file(releaseStorePath)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Keeps `flutter run --release` working on a machine without
                // the release key. Such an APK cannot update, or be updated
                // by, an officially released build.
                logger.warn(
                    "DropNet: no release signing key configured; release build is signed " +
                        "with the debug key and will not install over official releases."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
}

flutter {
    source = "../.."
}
