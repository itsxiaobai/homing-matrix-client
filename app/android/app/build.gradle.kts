import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 本機正式簽章（人類 2026-11-23 指示「金鑰放本機」）：
// 路徑／密碼寫在 android/key.properties（已被 app/android/.gitignore 忽略），
// 不進版控、不放 CI。檔案不存在 → 退回 debug 簽章（CI 仍可建置，但每次
// runner 的 debug keystore 不同，故 CI APK 只能視為測試包，需先解除安裝）。
val keystorePropsFile = file("key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}
val releaseStorePath = keystoreProps.getProperty("storeFile").orEmpty()
val hasLocalReleaseKey = releaseStorePath.isNotEmpty() &&
    file(releaseStorePath.replaceFirst("~", System.getProperty("user.home"))).isFile

// FCM（第四十一批）：google-services plugin **僅在提供 google-services.json
// 時**套用——未配置 Firebase 專案的建置（CI、fork 使用者）不應因此失敗。
// 缺少該檔時 App 端會自動退回 UnifiedPush／本機通知（見 lib/push/fcm_runtime.dart）。
// （Kotlin DSL 的 `plugins {}` 區塊內無 `file()`，故於腳本層用 `apply(plugin=…)`。）
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "io.github.itsxiaobai"
    compileSdk = flutter.compileSdkVersion
    // 第九十四批：whisper_ggml 需 NDK 29；原先 flutter.ndkVersion(28.2) 與
    // 之不一致 → Gradle 同時安裝 28+29（吃光磁碟）。統一用 29（向下相容）。
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.itsxiaobai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ⚠️ 最低版本**明確釘住 API 24（Android 7.0）**（人類 2026-11-17 指示：
        // 「SDK 要能支援 Android 7 或更低版本」）。原本寫 `flutter.minSdkVersion`
        // ＝跟著 Flutter 版本漂移（Flutter 哪天提高預設就會靜默失去舊機支援）
        // → 改為明確常數並加註來源。
        // 相容性查證（2026-11-17）：matrix 14.2.0 → 16.0.4 **無新增／移除依賴**
        // （僅 sdp_transform 上限放寬、vodozemac 提升至 0.9.1），且 matrix 為
        // **純 Dart 套件（無 android/ 目錄）** → 升級**不會**提高 minSdk。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 僅在本機有 keystore 時建立正式 signingConfig；CI 沒有 key.properties
    // → 不成立，buildTypes.release 退回 debug（不影響 CI 出包）。
    signingConfigs {
        if (hasLocalReleaseKey) {
            create("release") {
                storeFile = file(
                    releaseStorePath.replaceFirst("~", System.getProperty("user.home"))
                )
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 本機正式簽章 → 可覆蓋更新、保留資料；CI 無金鑰 → debug 測試包。
            signingConfig = if (hasLocalReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Note: keep R8 minify/shrink disabled to avoid breaking E2EE payloads
            // (matrix / mobile_scanner may depend on JVM reflection/vendor classes)
            // 2026-11-20：明確關閉——AGP 9 在 release 仍會跑 R8，導致
            // google_mlkit_text_recognition 缺少語言模組 class 而建置失敗。
            isMinifyEnabled = false
            isShrinkResources = false
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

// FCM（第四十一批）：App 模組需直接引用 Firebase Android SDK
// （HomingFcmService 繼承 FirebaseMessagingService；firebase_messaging 套件
// 以 `implementation` 帶入，故不會暴露給 App 模組的編譯 classpath）。
// BoM 版本與 firebase_core 5.1.0 一致（35.1.0）。
dependencies {
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")
}
