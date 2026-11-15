// 推播通道的三層規則——第四十二批（人類指示：「規則為 UnifiedPush → FCM →
// app 直接送」）。
//
// 規則含義：
// 1. **UnifiedPush**：使用者自選的接收端（例如 ntfy）→ 不經 Google，優先。
// 2. **FCM**（Firebase Cloud Messaging）：**需要 Firebase 專案**
//    （`android/app/google-services.json`；Homing 不代管憑證）。
//    沒有 Firebase 專案 → FCM 不可用。
// 3. **App 直接送**：沒有任何推播通道時的**最終手段**——App 在前景時由 SDK 的
//    長輪詢 sync 直接取得訊息（官方機制）；App 完全結束時**收不到**通知。
//
// ⚠️ 「FCM 需要 Firebase 嗎？」——**是**：FCM 即 Firebase Cloud Messaging，
// 服務端在 Google Firebase 上；Android 端需對應的 Firebase 專案設定檔
// （google-services.json）。Homing 只在**有**該檔時啟用 FCM；
// 沒有時自動落到第 3 層，不影響其他功能。
import 'package:flutter/material.dart';

/// Homing 的推播通道種類（依優先序）。
enum PushChannelKind {
  /// 使用者自選的 UnifiedPush 接收端（不經 Google）。
  unifiedPush,

  /// Google Firebase Cloud Messaging（需 Firebase 專案）。
  fcm,

  /// App 直接送：無推播通道，App 前景時由 SDK 長輪詢直接收訊息。
  inApp,
}

/// 推播通道狀態（供設定頁顯示；純資料，便於測試）。
class PushChannelStatus {
  const PushChannelStatus({
    required this.kind,
    required this.label,
    required this.detail,
  });

  final PushChannelKind kind;

  /// 顯示名稱（設定頁用；草案文案，待人類定稿）。
  final String label;

  /// 說明（設定頁用；草案文案，待人類定稿）。
  final String detail;

  /// 是否為「可喚醒 App」的推播通道（`inApp` 不是）。
  bool get canWakeApp => kind != PushChannelKind.inApp;
}

/// 依通道可用性算出狀態（純函式；便於單元測試）。
///
/// [unifiedPushReady]＝已取得 UP distributor／endpoint；[fcmAvailable]＝FCM 初始化成功。
PushChannelStatus describePushChannel({
  required bool unifiedPushReady,
  required bool fcmAvailable,
}) {
  if (unifiedPushReady) {
    return const PushChannelStatus(
      kind: PushChannelKind.unifiedPush,
      label: 'UnifiedPush',
      detail: '推播由你自選的接收端（例如 ntfy）轉送，不經 Google。',
    );
  }
  if (fcmAvailable) {
    return const PushChannelStatus(
      kind: PushChannelKind.fcm,
      label: 'FCM（Firebase）',
      detail: '推播經 Google Firebase 轉送；訊息內容不進推播（只帶 event_id）。',
    );
  }
  return const PushChannelStatus(
    kind: PushChannelKind.inApp,
    label: 'App 直接收（無推播通道）',
    detail: '沒有可用的推播通道（未安裝 UnifiedPush 接收端且未設定 Firebase）。'
        'App 開啟時仍會即時收到訊息；App 完全結束時不會收到通知。',
  );
}

/// 設定頁的說明文字（含圖示；草案樣式，待人類定稿）。
class PushChannelStatusTile extends StatelessWidget {
  const PushChannelStatusTile({super.key, required this.status});

  final PushChannelStatus status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status.kind) {
      PushChannelKind.unifiedPush => Icons.notifications_active_outlined,
      PushChannelKind.fcm => Icons.cloud_outlined,
      PushChannelKind.inApp => Icons.smartphone_outlined,
    };
    return ListTile(
      leading: Icon(icon),
      title: Text('推播通道：${status.label}'),
      subtitle: Text(status.detail),
      isThreeLine: status.detail.length > 40,
    );
  }
}
