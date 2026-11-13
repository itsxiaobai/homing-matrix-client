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

/// Homing 的 pusher app id（Matrix 規格：須反向域名；來源 spec v1.19）。
/// 與 android applicationId 同步（現為 skeleton 預設值；改 package 名時
/// 此處須一併更新）。
const String kRingPushAppId = 'com.example.ring';

/// UnifiedPush 通道執行器（批次 A）。
class RingPushRuntime {
  RingPushRuntime._();

  static Client? _client;

  /// 已註冊 pusher 的 endpoint（避免 sync 重入重複註冊）。
  static String? _registeredUrl;

  /// 登入後呼叫（MainShell initState）；非 Android／無 distributor 時
  /// 全部靜默 no-op（批次 C 的本地輪詢兜底）。
  static Future<void> init(Client client) async {
    if (!Platform.isAndroid) {
      return;
    }
    _client = client;
    bool hasDistributor;
    try {
      hasDistributor = await UnifiedPush.initialize(
        onNewEndpoint: (endpoint, instance) =>
            unawaited(_onNewEndpoint(endpoint)),
        onRegistrationFailed: (reason, instance) {
          // 靜默：批次 C 本地輪詢兜底後才有 UI 提示位置。
        },
        onUnregistered: (instance) {
          // 被系統／使用者解除登記：清掉本端 pusher 記憶，允許重註冊。
          _registeredUrl = null;
        },
        onMessage: (message, instance) {
          // 第二十八批（人類拍板）：event_id_only 的訊息到達＝「有新事件」。
          // 原空實作會讓「近期背景的 App」收到推播卻不補 sync（通知／來電
          // 不響的成因之一；與 untied No.14 同源）。現改：官方
          // `oneShotSync()`（進行中則等待）喚醒一次 sync——既有通知（批十四）
          // 與來電 UI（本批 glare 補位）會隨新事件浮現。
          // ⚠️ 限制：僅「App 行程仍在活執行」時有效；行程已凍結／終止的冷喚
          // 醒需第二十九批（推播檢修併案 No.14）處理。
          final client = _client;
          if (client == null || !client.isLogged()) {
            return;
          }
          if (client.syncPending) {
            return; // 已有進行中 sync → 官方語意即為等待中。
          }
          unawaited(
            client.oneShotSync(timeout: const Duration(seconds: 10)),
          );
        },
        onTempUnavailable: (instance) {},
      );
      if (!hasDistributor) {
        // 使用者尚未選擇 distributor：試系統預設；仍無＝無通道，回現況。
        final ok = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
        if (!ok) {
          return;
        }
      }
      // UnifiedPush 文件：每次啟動都要 register 同一 token；無參數預設
      // 走已儲存 distributor，endpoint 經 onNewEndpoint 回來。
      await UnifiedPush.register();
    } catch (_) {
      // UP 不可用（非 Android runtime 已排除；其餘異常）＝維持現況。
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
          appId: kRingPushAppId,
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
          PusherId(appId: kRingPushAppId, pushkey: client.deviceID!),
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
    _client = null;
  }
}
