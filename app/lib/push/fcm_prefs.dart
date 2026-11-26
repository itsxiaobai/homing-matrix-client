// 第七十八批（人類 2026-11-19 指示）：FCM **預設不開啟**，由使用者主動啟用。
//
// 設計：偏好存本機 kv（AppSettings），讀取失敗（測試／無 DB）一律當「未啟用」
// → 一般使用者（含初次安裝）完全不會連到 Google，也不會註冊 FCM pusher。
// 與既有的 `push_enabled`（推播總開關）不同：此開關只控制「是否啟用 FCM
// 作為通道」；關閉時仍可用 UnifiedPush／App 直接收。
import 'package:flutter/foundation.dart';

import '../app_settings.dart';

const String kFcmEnabledKey = 'fcm_enabled';

/// FCM 是否已由使用者明確啟用（預設 false）。
final ValueNotifier<bool> ringFcmEnabled = ValueNotifier<bool>(false);

/// 讀回偏好（ Failure → 關）。
Future<void> loadFcmEnabledPref() async {
  try {
    ringFcmEnabled.value = (await AppSettings.get(kFcmEnabledKey)) == '1';
  } on Object {
    ringFcmEnabled.value = false;
  }
}

/// 持久化＋更新 notifier。
Future<void> setFcmEnabled(bool enabled) async {
  ringFcmEnabled.value = enabled;
  try {
    await AppSettings.set(kFcmEnabledKey, enabled ? '1' : '0');
  } on Object {
    // 寫入失敗：記憶體仍生效（下次重開回復預設關），不中斷使用者操作。
  }
}
