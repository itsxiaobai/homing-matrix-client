pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // FCM（第四十一批）：google-services plugin。**僅在 app/google-services.json
    // 存在時才套用**（見 app/build.gradle.kts 的條件式 apply）——沒有 Firebase
    // 專案時仍可建置，App 端以 UnifiedPush／本機通知運作。
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
