import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

// Load local.properties for secrets
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(localPropertiesFile.inputStream())
}

android {
    namespace = "com.vanta.speech"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.vanta.speech"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // API Configuration from local.properties or environment
        buildConfigField(
            "String",
            "API_BASE_URL",
            "\"${localProperties.getProperty("API_BASE_URL", "http://10.10.40.9:8000/v1/")}\""
        )
        buildConfigField(
            "String",
            "API_KEY",
            "\"${localProperties.getProperty("API_KEY", "")}\""
        )
        buildConfigField(
            "String",
            "AZURE_CLIENT_ID",
            "\"${localProperties.getProperty("AZURE_CLIENT_ID", "")}\""
        )
    }

    buildTypes {
        debug {
            // Debug can use default local values
        }
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    // Core Android
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)

    // Compose BOM
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)

    // Navigation
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.hilt.navigation.compose)

    // Hilt DI
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // Room Database
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    // Retrofit + OkHttp
    implementation(libs.retrofit)
    implementation(libs.retrofit.converter.gson)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)

    // Coroutines
    implementation(libs.kotlinx.coroutines.android)

    // Media3 for audio playback
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)

    // DataStore for preferences
    implementation(libs.androidx.datastore.preferences)

    // Security (EncryptedSharedPreferences)
    implementation(libs.androidx.security.crypto)

    // Kotlinx Serialization
    implementation(libs.kotlinx.serialization.json)

    // Microsoft Authentication Library (MSAL)
    implementation(libs.msal) {
        exclude(group = "io.opentelemetry")
    }

    // Markdown rendering
    implementation(libs.compose.markdown)

    // Testing
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
