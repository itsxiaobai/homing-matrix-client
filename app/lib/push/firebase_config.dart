// Firebase 設定來源——第四十二批（人類指示用手機上的 microG 測 FCM）。
//
// 三種來源，依序嘗試：
// 1. **dart-define**（建置參數，不進版控）：
//    `flutter build apk --dart-define=FCM_PROJECT_ID=… --dart-define=FCM_API_KEY=…
//     --dart-define=FCM_APP_ID=… --dart-define=FCM_SENDER_ID=…`
//    → 不需要把 `google-services.json` 放進版控庫，也方便 CI／多環境切換。
// 2. **`android/app/google-services.json`**（Firebase 官方外掛自動產生的設定；
//    外掛僅在該檔存在時套用 → 兩者互補）。
// 3. 都沒有 → **FCM 停用**，App 照常以 UnifiedPush／本機通知運作（不崩潰）。
//
// ⚠️ 隱私：API key／sender id 屬 Firebase 專案識別資訊，**不是機密金鑰**
// （真正的機密在服務端金鑰）；但仍不建議提交到版本庫 → 以 dart-define 帶入。
import 'package:firebase_core/firebase_core.dart';

/// 從 dart-define 讀出的 Firebase 設定（皆為空字串＝未提供）。
class FirebaseDefines {
  const FirebaseDefines({
    required this.projectId,
    required this.apiKey,
    required this.appId,
    required this.senderId,
  });

  /// 建置參數讀取（`--dart-define=KEY=value`）。
  factory FirebaseDefines.fromEnvironment() {
    return const FirebaseDefines(
      projectId: String.fromEnvironment('FCM_PROJECT_ID'),
      apiKey: String.fromEnvironment('FCM_API_KEY'),
      appId: String.fromEnvironment('FCM_APP_ID'),
      senderId: String.fromEnvironment('FCM_SENDER_ID'),
    );
  }

  final String projectId;
  final String apiKey;
  final String appId;
  final String senderId;

  /// 四項齊全才算可用。
  bool get isComplete =>
      projectId.isNotEmpty &&
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty;

  /// 轉成官方 `FirebaseOptions`；不完整時回 null。
  FirebaseOptions? toOptions() {
    if (!isComplete) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }
}
