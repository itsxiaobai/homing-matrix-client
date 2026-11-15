// FCM（Firebase Cloud Messaging）推播通道——第四十一批（人類指示「FCM ＋
// UnifiedPush 通知加入」）。
//
// 設計要點（與藍圖／既有 `push_runtime.dart` 一致）：
// 1. **通道優先序**：UnifiedPush（使用者自選 distributor，如 ntfy）優先；
//    **沒有 UP distributor 時才用 FCM**（`push_runtime.dart` 檔頭的批次 B 計畫）。
// 2. **不送內文**：Matrix pusher 一律 `format = event_id_only`
//    → homeserver 只把 event_id 送進來，內文由 App 端 sync 後自行解密顯示。
//    （出處：藍圖 §二之一「推播通知 ⚠️ 第三方可見」＋ §十五 L619 對策；
//    Matrix spec v1.19 Push Gateway API。）
// 3. **無 Firebase 專案也能用**：沒有 `android/app/google-services.json` 時，
//    `Firebase.initializeApp()` 會丟例外 → 本模組靜默停用（`isAvailable=false`），
//    App 端照常以 UnifiedPush／本機通知運作；**不崩潰、不阻塞登入**。
// 4. **冷喚醒**：背景訊息（App 被殺）由 `firebaseMessagingBackgroundHandler`
//    以背景 isolate 喚醒 → 重建持久化 Client（官方 session／DB）→ 觸發一次
//    `oneShotSync()`（官方 API），讓本地通知與來電 UI 能浮現。
//
// App 端**零自寫加密邏輯**：只呼叫 firebase_messaging 官方 API 與 SDK 官方
// `postPusher`／`deletePusher`／`oneShotSync`。
import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../client_factory.dart';
import 'firebase_config.dart';
import 'push_constants.dart';

/// FCM 通道執行器。
class FcmRuntime {
  FcmRuntime._();

  static Client? _client;

  /// FCM 是否可用（已成功初始化 Firebase 且拿到 token）。
  static bool _available = false;

  /// 已註冊的 FCM token（避免重複註冊）。
  static String? _registeredToken;

  /// Firebase 初始化失敗的原因（供設定頁顯示，不含機敏資訊）。
  static String? _lastError;

  static bool get isAvailable => _available;

  static String? get lastError => _lastError;

  /// 登入後呼叫；非 Android、Firebase 未配置或初始化失敗 → 靜默停用。
  ///
  /// 回傳 `true`＝FCM 可用（已取得 token 並註冊 pusher）；`false`＝不可用
  /// （呼叫端據此落到下一層通道）。
  static Future<bool> init(Client client) async {
    if (!Platform.isAndroid) {
      return false;
    }
    _client = client;
    try {
      // 來源 1：Firebase 官方外掛（需 android/app/google-services.json）。
      await Firebase.initializeApp();
    } catch (_) {
      // 來源 2：dart-define 帶入的 Firebase 設定（不需放檔案進版控）。
      final defines = FirebaseDefines.fromEnvironment();
      final options = defines.toOptions();
      if (options == null) {
        // 兩者皆無 → FCM 停用（不崩潰；退回 UnifiedPush／本機通知）。
        _available = false;
        _lastError = 'Firebase 未設定（缺少 android/app/google-services.json，'
            '或未以 --dart-define 提供 FCM_* 參數）';
        return false;
      }
      try {
        await Firebase.initializeApp(options: options);
      } catch (e) {
        _available = false;
        _lastError = 'Firebase 初始化失敗（dart-define 設定）：$e';
        return false;
      }
    }

    // 背景訊息處理（App 被殺時的冷喚醒）。
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    try {
      // firebase_messaging 17.x：改用 `register()` ＋ `onRegistered`
      // （`getToken`／`onTokenRefresh` 已棄用）。
      await FirebaseMessaging.instance.register();
      // 註冊完成 → 以 FID（Installation ID）作 pushkey 註冊 Matrix pusher。
      FirebaseMessaging.instance.onRegistered.listen((token) {
        unawaited(_registerPusher(token));
      });
      // 先取一次既有註冊結果（stream 為廣播，先監聽再取值才不會漏）。
      final existing = FirebaseMessaging.instance.onRegistered;
      unawaited(
        existing.first
            .timeout(const Duration(seconds: 3), onTimeout: () => '')
            .then((token) {
              if (token.isNotEmpty) unawaited(_registerPusher(token));
            })
            .catchError((_) {}),
      );
      // App 在前景時收到推播 → 喚醒一次 sync（既有通知／來電 UI 隨之浮現）。
      FirebaseMessaging.onMessage.listen((_) {
        unawaited(_wakeSync());
      });
      _available = true;
      _lastError = null;
    } catch (e) {
      _available = false;
      _lastError = 'FCM 啟動失敗：$e';
    }
    return _available;
  }

  /// 向 homeserver 註冊 FCM 的 Matrix pusher（官方 `postPusher`）。
  static Future<void> _registerPusher(String token) async {
    final client = _client;
    if (client == null || client.userID == null) {
      return;
    }
    if (_registeredToken == token) {
      return;
    }
    final previous = _registeredToken;
    _registeredToken = token;
    try {
      await client.postPusher(
        Pusher(
          appId: kPushAppId,
          // FCM token 作為 pushkey（與 UnifiedPush 的 deviceID 區隔，
          // 兩種通道可並存）。
          pushkey: token,
          appDisplayName: 'Homing',
          deviceDisplayName: 'Homing (${client.deviceID ?? 'unknown device'})',
          kind: 'http',
          lang: 'zh',
          profileTag: client.deviceID,
          data: PusherData(
            url: Uri.parse(kFcmPusherUrl),
            format: 'event_id_only', // 內文不離伺服器（見檔頭第 2 點）。
          ),
        ),
        append: false,
      );
    } catch (_) {
      _registeredToken = previous; // 失敗回退，允許下次重試。
    }
  }

  /// 喚醒一次 sync（官方 API；進行中則等待）。
  static Future<void> _wakeSync() async {
    final client = _client;
    if (client == null || !client.isLogged()) {
      return;
    }
    if (client.syncPending) {
      return;
    }
    try {
      await client.oneShotSync(timeout: const Duration(seconds: 10));
    } catch (_) {
      // 靜默：推播只是加速同步，失敗不影響使用者。
    }
  }

  /// 登出時清除 FCM pusher（官方 `deletePusher`）。
  static Future<void> teardown() async {
    final client = _client;
    if (client != null && client.userID != null && client.deviceID != null) {
      try {
        await client.deletePusher(
          PusherId(appId: kPushAppId, pushkey: client.deviceID!),
        );
      } catch (_) {
        // 伺服器端清不掉時，token 失效即成孤兒 pusher（見 push_runtime 說明）。
      }
    }
    _registeredToken = null;
    _client = null;
    _available = false;
  }
}

/// 背景訊息處理（App 被殺時的冷喚醒）。
///
/// 流程：重建持久化 Client（session／DB 由 SDK 官方保存）→ 若已登入則觸發
/// 一次 `oneShotSync()` → 通知與來電 UI 由既有流程顯示。
///
/// 注意：此 isolate 需 Flutter bindings（`WidgetsFlutterBinding.ensureInitialized()`）。
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final client = await createPersistentClient();
    if (!client.isLogged()) {
      return;
    }
    await client.oneShotSync(timeout: const Duration(seconds: 10));
  } catch (_) {
    // 冷喚醒失敗（無 session／網路）＝靜默；App 開啟後會自行 sync。
  }
}
