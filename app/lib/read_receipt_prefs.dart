// 第六十九批（人類指示「實作所有需移植功能」）— F-2/P2 無痕預覽／稍後標為已讀。
//
// 設計取捨（避免影響一般使用者）：兩項**預設關閉、使用者主動開啟才生效**。
// ①無痕預覽＝進入聊天室不自動送已讀 receipt（手動「標為已讀」仍可送）；
// ②稍後標為已讀＝原本到達底部即送receipt，改為延遲 N 秒後送（仍在前景時）。
// 不新增依賴、不碰加密邏輯；只呼叫 SDK 官方 setReadMarker。

import 'package:flutter/foundation.dart';

import 'app_settings.dart';

/// 無痕預覽開關（預設 false）。
final ValueNotifier<bool> ringIncognitoRead = ValueNotifier<bool>(false);

/// 稍後標為已讀的延遲秒數（0＝立即，預設 0）。
final ValueNotifier<int> ringMarkReadDelaySec = ValueNotifier<int>(0);

const String _kIncognitoRead = 'incognito_read';
const String _kMarkReadDelaySec = 'mark_read_delay_sec';

/// 啟動時讀回偏好（在 ringTheme 等 notifier 載入點旁呼叫）。
Future<void> loadReadReceiptPrefs() async {
  try {
    ringIncognitoRead.value =
        (await AppSettings.get(_kIncognitoRead)) == '1';
  } on Object {
    ringIncognitoRead.value = false;
  }
  try {
    final raw = await AppSettings.get(_kMarkReadDelaySec);
    ringMarkReadDelaySec.value = int.tryParse(raw ?? '') ?? 0;
  } on Object {
    ringMarkReadDelaySec.value = 0;
  }
}

/// 開／關無痕預覽並持久化。
Future<void> setIncognitoRead(bool enabled) async {
  ringIncognitoRead.value = enabled;
  await AppSettings.set(_kIncognitoRead, enabled ? '1' : '0');
}

/// 設定延遲秒數（≤0 視為立即）並持久化。
Future<void> setMarkReadDelaySec(int seconds) async {
  final value = seconds < 0 ? 0 : seconds;
  ringMarkReadDelaySec.value = value;
  await AppSettings.set(_kMarkReadDelaySec, '$value');
}
