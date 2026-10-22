plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val keystorePath = (project.findProperty("pdfcraftStoreFile") as String?)
    ?: System.getenv("PDFCRAFT_KEYSTORE")

android {
    namespace = "ai.storyteller.pdfcraft"
    compileSdk = 35

    defaultConfig {
        applicationId = "ai.storyteller.pdfcraft"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
        ndk { abiFilters += "arm64-v8a" }
    }

    signingConfigs {
        if (keystorePath != null) {
            create("ci") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("PDFCRAFT_KEYSTORE_PASSWORD") ?: "pdfcraft-ci"
                keyAlias = System.getenv("PDFCRAFT_KEY_ALIAS") ?: "pdfcraft-ci"
                keyPassword = System.getenv("PDFCRAFT_KEY_PASSWORD") ?: "pdfcraft-ci"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystorePath != null) {
                signingConfigs.getByName("ci")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs.useLegacyPackaging = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}
