plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Firebase configuration of the test app is not committed; without it the app builds without push.
val firebase = file("google-services.json").exists()
if (firebase) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "sh.reception.receptionFlutterExample"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "sh.reception.receptionFlutterExample"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with the debug keys, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Firebase Messaging without the firebase_messaging Dart package: the SDK fetches the FCM token and the plugin's
    // receiver shows replies. With firebase_messaging in pubspec.yaml this line is redundant but harmless.
    if (firebase) {
        implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
        implementation("com.google.firebase:firebase-messaging")
    }
}

flutter {
    source = "../.."
}
