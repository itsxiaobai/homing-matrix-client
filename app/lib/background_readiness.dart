// 第八十二批（人類指示）：背景準備度——電源使用限制／網路。
// 預約訊息到期時若離線 → **保留原筆，等連上才送**（不計入失敗次數）。
// 不新增 Dart 依賴（MethodChannel 走原生；網路檢查用 dart:io socket）。
import 'dart:async';
import 'dart:io' show Platform, InternetAddress;

import 'package:flutter/services.dart';

const MethodChannel _powerChannel = MethodChannel('homing/power');

/// 是否已忽略電池最佳化（Android 6+；其他平台回 true）。
Future<bool> isIgnoringBatteryOptimizations() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _powerChannel.invokeMethod<bool>('is_ignoring_battery') ?? false;
  } on Object {
    return false;
  }
}

/// 導向系統「忽略電池最佳化」要求的對話框（使用者主動點擊才呼叫）。
Future<bool> requestIgnoreBatteryOptimizations() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _powerChannel.invokeMethod<bool>('request_ignore_battery') ?? false;
  } on Object {
    return false;
  }
}

/// 導向系統網路設定。
Future<bool> openNetworkSettings() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _powerChannel.invokeMethod<bool>('open_network_settings') ?? false;
  } on Object {
    return false;
  }
}

/// 是否有網路（DNS 查詢；3 秒逾時）。失敗＝視為離線。
Future<bool> hasNetwork() async {
  try {
    final result = await InternetAddress.lookup('example.com')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on Object {
    return false;
  }
}
