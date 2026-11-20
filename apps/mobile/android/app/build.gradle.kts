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
        manifestPlaceholders["appLabel"] = "همراه دارو"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            // Hosted CI runners use ephemeral debug signing keys. Give each
            // CI build its own applicationId: even the previous CI preview
            // cannot be upgraded with a differently signed key. Never remove
            // a user's installed test data merely to install the next build.
            if (System.getenv("GITHUB_ACTIONS") == "true") {
                val runNumber = System.getenv("GITHUB_RUN_NUMBER")
                    ?.filter { it.isDigit() }
                    ?.take(10)
                    ?.takeIf { it.isNotEmpty() }
                    ?: error("GITHUB_RUN_NUMBER is required for isolated CI preview")
                applicationIdSuffix = ".m4r$runNumber"
                versionNameSuffix = "-ci-preview"
                manifestPlaceholders["appLabel"] = "همراه دارو (بتا $runNumber)"
            }
        }
        release {
            // Internal preview only. Do not distribute a release signed by the debug key.
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
