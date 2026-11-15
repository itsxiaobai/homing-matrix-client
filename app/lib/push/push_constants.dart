// 推播共用常數——第四十一批（FCM ＋ UnifiedPush）。
//
// `kPushAppId` 是 Matrix pusher 的 **app_id**，規格要求為**反向域名**，
// 且必須與 Android `applicationId` 一致，否則 homeserver 的推播設定會指向
// 錯誤的 App（批次 33 改名為 Homing 時 `applicationId` 已改為
// `io.github.itsxiaobai`，但本常數仍殘留舊值 `com.example.ring`——第四十一批修正）。
library;

/// Matrix pusher app_id（與 `android/app/build.gradle.kts` 的 applicationId 同步）。
const String kPushAppId = 'io.github.itsxiaobai';

/// FCM 的 Matrix pusher endpoint（FCM legacy HTTP；出處：Matrix spec v1.19
/// Push Gateway API 與 Element 客戶端慣例）。
const String kFcmPusherUrl = 'https://fcm.googleapis.com/fcm/send';
