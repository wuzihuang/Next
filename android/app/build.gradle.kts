plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.nextbody.hoop"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.nextbody.hoop"
        minSdk = 28
        targetSdk = 35
        versionCode = 9
        versionName = "1.0"
        // The Google web client the Supabase project trusts for id-token sign-in. Empty means
        // the Google button falls back to the browser OAuth flow.
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"${project.findProperty("nb.googleWebClientId") ?: ""}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
    val bom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(bom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    implementation("androidx.health.connect:connect-client:1.1.0")
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
    implementation("androidx.browser:browser:1.8.0")

    // Veepoo (HBand) band SDK — the Android twin of iOS_Ble_SDK. Binaries from
    // github.com/HBandSDK/Android_Ble_SDK (android_sdk_source/jar_core, jar_base).
    implementation(fileTree("libs") { include("*.aar", "*.jar") })
    implementation("no.nordicsemi.android:mcumgr-core:2.7.4")
    implementation("no.nordicsemi.android:mcumgr-ble:2.7.4")
    implementation("no.nordicsemi.android.support.v18:scanner:1.4.2")
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}
