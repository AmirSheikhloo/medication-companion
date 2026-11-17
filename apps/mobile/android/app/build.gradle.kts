plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ir.example.medication_companion"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ir.example.medication_companion"
        manifestPlaceholders["appLabel"] = "همراه دارو (آزمایش)"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            // GitHub Actions uses an ephemeral Android debug signing key.
            // A CI-built APK cannot update a locally signed APK with the same
            // applicationId. Keep the owner's existing emulator data intact
            // by installing the CI preview as a separate, isolated app.
            if (System.getenv("GITHUB_ACTIONS") == "true") {
                applicationIdSuffix = ".m401preview"
                versionNameSuffix = "-ci-preview"
                manifestPlaceholders["appLabel"] = "همراه دارو (تست M4)"
            }
        }
        release {
            // Only an M0 debug experiment. Never publish with the debug signing key.
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Lightweight, incremental GCM engine and Argon2id; never use Conscrypt's
    // buffer-accumulating AES/GCM Cipher.update for 64 MiB backups.
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
}

flutter {
    source = "../.."
}
