// 推播共用常數——第四十一批（FCM ＋ UnifiedPush）。
//
// `kPushAppId` 是 Matrix pusher 的 **app_id**，規格要求為**反向域名**，
// 且必須與 Android `applicationId` 一致，否則 homeserver 的推播設定會指向
// 錯誤的 App（批次 33 改名為 Homing 時 `applicationId` 已改為
// `io.github.itsxiaobai`，但本常數仍殘留舊值 `com.example.ring`——第四十一批修正）。
library;

/// Matrix pusher app_id（與 `android/app/build.gradle.kts` 的 applicationId 同步）。
const String kPushAppId = 'io.github.itsxiaobai';

/// **舊版** FCM HTTP 端點（Google 的 legacy FCM HTTP API）。
///
/// ⚠️ **第五十二批（2026-11-16）實測已停用**：`POST https://fcm.googleapis.com/fcm/send`
/// → **HTTP 404**（回應為 Google GSE 的 "Not Found" 錯誤頁，見本批實測紀錄）。
/// 同義的 `https://fcm.googleapis.com/send` 亦為 **HTTP 404**。
/// 而 FCM HTTP v1（`/v1/projects/{id}/messages:send`）**仍存在**，但回
/// **HTTP 401**「Request is missing required authentication credential. Expected
/// OAuth 2 access token…」→ v1 需要 **service account 的 OAuth2 短效 token**，
/// Matrix `http` pusher 只能帶**靜態** `data.auth`，無法直接使用 v1。
const String kFcmLegacyPusherUrl = 'https://fcm.googleapis.com/fcm/send';

/// FCM 的 Matrix pusher endpoint（可由建置參數覆寫）。
///
/// 覆寫方式（不需改程式）：
/// `flutter build apk --dart-define=FCM_GATEWAY_URL=https://<你的轉送端>/push`
///
/// 用途：舊版 Google 端點已停用（見 [kFcmLegacyPusherUrl]）；若日後自架
/// FCM v1 轉送端（需持有 service account 憑證 → **屬需維運的系統，須人類
/// 決定**），或改用其他 Matrix 相容的推播閘道，只要改這個建置參數即可。
/// 空白時沿用舊版端點（並在設定頁明確標示該端點已停用）。
final String kFcmPusherUrl = _fcmGatewayUrlFromEnv.isEmpty
    ? kFcmLegacyPusherUrl
    : _fcmGatewayUrlFromEnv;

/// 建置參數注入的推播閘道 URL（空白＝未指定）。
const String _fcmGatewayUrlFromEnv = String.fromEnvironment('FCM_GATEWAY_URL');

/// 目前設定的閘道是否為**已停用的舊版 Google 端點**（→ 推播無法投遞）。
bool get kFcmUsesLegacyEndpoint =>
    kFcmPusherUrl == kFcmLegacyPusherUrl;
