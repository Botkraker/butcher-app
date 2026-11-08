import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
}

val props = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun prop(key: String): String =
    props.getProperty(key, "").replace("\\", "\\\\").replace("\"", "\\\"")

android {
    namespace = "tn.butcher.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "tn.butcher.app"
        minSdk = 24
        targetSdk = 34
        versionCode = 2
        versionName = "0.2"
        buildConfigField("String", "NEON_SQL_URL", "\"${prop("neon.sql.url")}\"")
        buildConfigField("String", "NEON_CONNECTION_STRING", "\"${prop("neon.connection.string")}\"")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
