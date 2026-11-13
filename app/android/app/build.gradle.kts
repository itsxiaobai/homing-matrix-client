plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.itsxiaobai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.itsxiaobai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Note: keep R8 minify/shrink disabled to avoid breaking E2EE payloads
            // (matrix / mobile_scanner may depend on JVM reflection/vendor classes)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 任務 3 批次 A（人類批准 2026-11-07）：tink 重複打包修復——
// unifiedpush_android → org.unifiedpush.android:connector → 帶 JVM 版
// com.google.crypto.tink:tink:1.18.0；flutter_secure_storage 帶
// com.google.crypto.tink:tink-android:1.23.0。同名種類重複 →
// checkDebugDuplicateClasses 失敗。此處全域排除 JVM 版	tink，統一走
// tink-android（同一套 com.google.crypto.tink 類、版本較新；
// ⚠️若 UP connector 呼叫到 android 版缺的 API 才會 runtime 失效——
// 1.18→1.23 API 只增不減，來源 tink GitHub changelog，待查證）。
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

flutter {
    source = "../.."
}
