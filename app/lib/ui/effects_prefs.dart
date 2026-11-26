// 第八十六批（人類指示）：音效／視覺效果偏好（本機 kv）。
// 皆「使用者可控、預設尊重系統」；不影響訊息內容、不送伺服器。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';

/// 訊息通知音效（預設開；實際發聲由原生 notification channel 控制）。
final ValueNotifier<bool> ringSoundEnabled = ValueNotifier<bool>(true);

/// 應用程式內視覺動效（預設開；a11yReduceMotion 時無論此值都停用）。
final ValueNotifier<bool> ringVisualEffects = ValueNotifier<bool>(true);

/// 震動（預設開）。
final ValueNotifier<bool> ringVibration = ValueNotifier<bool>(true);

/// 高對比模式（預設關；提升文字／邊界對比，照顧低視能）。
final ValueNotifier<bool> ringHighContrast = ValueNotifier<bool>(false);

Future<void> loadEffectsPrefs() async {
  ringSoundEnabled.value = await _read('effect_sound', true);
  ringVisualEffects.value = await _read('effect_visual', true);
  ringVibration.value = await _read('effect_vibration', true);
  ringHighContrast.value = await _read('high_contrast', false);
  // 第八十六批：啟動時把已存音效／震動偏好套用到原生 notification channel。
  try {
    await const MethodChannel('homing/local_notifications')
        .invokeMethod<bool>('set_effects', <String, Object?>{
      'sound': ringSoundEnabled.value,
      'vibration': ringVibration.value,
    });
  } on Object {
    // 非 Android／channel 未就緒 → 忽略。
  }
}

Future<bool> _read(String key, bool fallback) async {
  try {
    return (await AppSettings.get(key)) != '0';
  } on Object {
    return fallback;
  }
}

Future<void> setEffect(String key, bool value, ValueNotifier<bool> notifier) async {
  notifier.value = value;
  try {
    await AppSettings.set(key, value ? '1' : '0');
  } on Object {
    // 寫入失敗：本 session 仍生效。
  }
  // 第八十六批：通知音效／震動 → 同步到原生 notification channel。
  if (key == 'effect_sound' || key == 'effect_vibration') {
    try {
      await const MethodChannel('homing/local_notifications')
          .invokeMethod<bool>('set_effects', <String, Object?>{
        'sound': ringSoundEnabled.value,
        'vibration': ringVibration.value,
      });
    } on Object {
      // 非 Android／channel 未就緒 → 忽略。
    }
  }
}
