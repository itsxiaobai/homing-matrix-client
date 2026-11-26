// 任務 3 批次 A（人類批准 2026-11-07）：UnifiedPush 通道註冊（Android）。
//
// 職責（本批僅三件事）：
// 1. 偵測裝置上的 UnifiedPush distributor（使用者自選的 ntfy 等）；
// 2. 向 distributor 註冊（UnifiedPush.register，每次啟動都要呼叫——
//    是 UnifiedPush 套件文件要求，非我們的策略）；
// 3. 拿到 endpoint 後向 homeserver 註冊 Matrix `http` pusher：
//    `data.url`＝UP endpoint、`data.format = event_id_only`——
//    內文**不**送往第三方（藍圖 §十五 L619 對策；來源：Matrix spec
//    v1.19 Push Gateway API「only event_id/room_id/counts/devices」。
//    ⚠️注意：event_id_only 對**加密房**最安全；未加密房房名／寄件者
//    metadata 仍可由 event id 反查——已列 PRIVACY.md 揭露範圍）。
//
// 明確不做（等待人類批准的後續批次）：
// * 批次 B：FCM（有 Google services 且無 UP 時）。
// * 批次 C：皆無時的本地輪詢 fallback ── 目前無 distributor＝安靜無
//   推播，維持現況（本地通知 v0，main_shell Suggestion #5）。
// * 通知內容揭露設定（人類決定 2026-11-07，歸設定批次）。
//
// App 端**零自寫加密邏輯**：只呼叫 SDK 官方 postPusher／UP 套件官方 API。
// 任何失敗皆靜默回退（無 distributor＝不打擾使用者；批次 C 兜底）。
import 'dart:async';
import 'dart:io' show Platform;

import 'package:matrix/matrix.dart';
import 'package:unifiedpush/unifiedpush.dart';

import 'fcm_prefs.dart' as fcm_prefs;
import 'fcm_runtime.dart';
import 'push_channel.dart';
import 'push_constants.dart';

/// Homing 的 pusher app id（Matrix 規格：須反向域名；來源 spec v1.19）。
///
/// 第四十一批：原值 `com.example.ring` 於批次 33 改名後已失效（applicationId
/// 已改為 `io.github.itsxiaobai`）→ 改用共用常數 `kPushAppId`
/// （`push_constants.dart`），避免兩處不同步。
@Deprecated('改用 push_constants.dart 的 kPushAppId')
const String kRingPushAppId = kPushAppId;

/// UnifiedPush 通道執行器（批次 A）。
class RingPushRuntime {
  RingPushRuntime._();

  static Client? _client;

  /// 已註冊 pusher 的 endpoint（避免 sync 重入重複註冊）。
  static String? _registeredUrl;

  /// 目前生效的推播通道（第七十七批人類指示「一般人不會裝 UP，預設 FCM」：
  /// **FCM（需有效閘道）→ UnifiedPush → App 直接送**）。
  static PushChannelKind _channelKind = PushChannelKind.inApp;

  /// 目前通道狀態（設定頁顯示；純資料）。
  static PushChannelStatus get channelStatus => describePushChannel(
        unifiedPushReady: _channelKind == PushChannelKind.unifiedPush,
        fcmAvailable: _channelKind == PushChannelKind.fcm,
      );

  /// 登入後呼叫（MainShell initState）；非 Android／無 distributor 時
  /// 全部靜默 no-op（批次 C 的本地輪詢兜底）。
  static Future<void> init(Client client) async {
    if (!Platform.isAndroid) {
      return;
    }
    _client = client;
    // 第七十八批（人類指示）：FCM **預設不開啟**，必須使用者明確啟用。
    // 先讀偏好（讀取失敗＝關）；只有 ringFcmEnabled.value == true 且
    // 有有效閘道時才初始化 FCM，避免初次安裝就連到 Google／註冊 pusher。
    await fcm_prefs.loadFcmEnabledPref();
    if (fcm_prefs.ringFcmEnabled.value && !kFcmUsesLegacyEndpoint) {
      final fcmOk = await FcmRuntime.init(client);
      if (fcmOk) {
        _channelKind = PushChannelKind.fcm;
        return;
      }
    }
    await _initUnifiedPushFallback();
  }

  /// 執行中切換 FCM（設定頁開／關後立即生效）。
  /// 開啟失敗 → 回報 false 並退回 UP／App 直接收；關閉 → 移除 FCM pusher。
  static Future<bool> setFcmEnabled(bool enabled, Client client) async {
    await fcm_prefs.setFcmEnabled(enabled);
    if (!enabled) {
      await FcmRuntime.teardown();
      _registeredUrl = null; //  allow re-register if UP re-init
      await _initUnifiedPushFallback(client: client);
      return true;
    }
    if (kFcmUsesLegacyEndpoint) {
      await _initUnifiedPushFallback(client: client);
      return false;
    }
    final ok = await FcmRuntime.init(client);
    if (ok) {
      _channelKind = PushChannelKind.fcm;
      return true;
    }
    await _initUnifiedPushFallback(client: client);
    return false;
  }

  /// UP 備援通道（無 FCM 時的路徑；抽出供 init／setFcmEnabled 共用）。
  static Future<void> _initUnifiedPushFallback({Client? client}) async {
    final active = client ?? _client;
    if (active == null) return;
    _client = active;
    var upReady = false;
    try {
      final hasDistributor = await UnifiedPush.initialize(
        onNewEndpoint: (endpoint, instance) =>
            unawaited(_onNewEndpoint(endpoint)),
        onRegistrationFailed: (reason, instance) {},
        onUnregistered: (instance) {
          _registeredUrl = null;
        },
        onMessage: (message, instance) {
          final current = _client;
          if (current == null || !current.isLogged()) return;
          if (current.syncPending) return;
          unawaited(current.oneShotSync(timeout: const Duration(seconds: 10)));
        },
        onTempUnavailable: (instance) {},
      );
      if (!hasDistributor) {
        final ok = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
        if (!ok) {
          upReady = false;
          _channelKind = PushChannelKind.inApp;
          return;
        }
      }
      await UnifiedPush.register();
      upReady = true;
      _channelKind = PushChannelKind.unifiedPush;
    } catch (_) {
      upReady = false;
      _channelKind = PushChannelKind.inApp;
    }
    if (!upReady) {
      _channelKind = PushChannelKind.inApp;
    }
  }

  /// 收到 endpoint（首註冊或更換時）：向 homeserver 註冊 http pusher。
  static Future<void> _onNewEndpoint(PushEndpoint endpoint) async {
    final url = endpoint.url;
    final client = _client;
    if (url.isEmpty || client == null || client.userID == null) {
      return;
    }
    if (_registeredUrl == url) {
      return; // 同一 endpoint 已註冊，不重複（尊重伺服器 pusher 配額）。
    }
    final previous = _registeredUrl;
    _registeredUrl = url;
    try {
      await client.postPusher(
        Pusher(
          appId: kPushAppId,
          // UP 的路由全部由 data.url 決定；pushkey 僅作裝置識別
          // （deviceID 為 client 官方裝置識別，無個資）。
          pushkey: client.deviceID ?? url,
          appDisplayName: 'Homing',
          deviceDisplayName: 'Homing (${client.deviceID ?? 'unknown device'})',
          kind: 'http',
          lang: 'zh',
          profileTag: client.deviceID,
          data: PusherData(
            url: Uri.parse(url),
            format: 'event_id_only', // 內文不離伺服器（見檔頭來源）。
          ),
        ),
        append: false, // 覆寫同 app_id/pushkey 的舊 pusher。
      );
    } catch (_) {
      _registeredUrl = previous; // 註冊失敗回退，允許下次 endpoint 重試。
    }
  }

  /// 登出時呼叫（onLogout 鉤點；批次 A 內僅提供，由 main_shell 接線）：
  /// 1) 註銷 homeserver pusher；2) UP unregister。
  static Future<void> teardown() async {
    _registeredUrl = null;
    final client = _client;
    if (client != null && client.userID != null && client.deviceID != null) {
      try {
        // deletePusher 會自動把 kind 設 null（＝刪除此 pushkey 的 pusher，
        // SDK matrix_api.dart L162 官方實作）；無需構造完整 Pusher。
        await client.deletePusher(
          PusherId(appId: kPushAppId, pushkey: client.deviceID!),
        );
      } catch (_) {
        // 伺服器側清不掉（離線等）：pusher 會因 token 失效變孤兒；
        // 下此裝置登入同一 device 重註冊會覆蓋（append:false）。
      }
    }
    try {
      if (Platform.isAndroid) {
        await UnifiedPush.unregister();
      }
    } catch (_) {}
    // 第四十一批：清除 FCM 通道（官方 deletePusher）。
    await FcmRuntime.teardown();
    _client = null;
  }
}
