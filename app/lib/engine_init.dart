// 第二十七批（人類拍板 2026-11-10）：Rust 加密引擎初始化防禦＋診斷記錄。
//
// 背景（實機回饋 2026-11-10）：`flutter_rust_bridge`（vodozemac 官方綁定
// 層）的主 isolate 狀態只在 main() 開頭初始化一次；舊實作失敗僅 print
// （靜默），之後任何加密呼叫只見
// 「Bad state: flutter_rust_bridge has not been initialized…」而無跡可尋。
//
// 本檔：①失敗自動重試一次（官方 `vod.init()` 同參數）；②兩次失敗把原因
// 記入 AppSettings kv（MainShell 提示＋設定→進階診斷可見；成功則清旗
// 標）。初始化本體仍是官方 engine init；**本檔不接觸任何加密演算法／金
// 鑰內容**（僅初始化與狀態記錄）。
import 'dart:async';

import 'package:homing/app_settings.dart';

/// kv key：最後一次引擎初始化失敗訊息（成功時移除；MainShell 提示與
/// 設定診斷共用此鍵，勿隨意改名）。
const String kRustEngineErrorKey = 'rust_engine_error';

/// 官方引擎初始化封裝：失敗重試＋失敗原因落 kv。
/// [init]＝官方 `vod.init()` tearoff；[recordFailure]／[recordRecovered]＝
/// 記錄端（預設 AppSettings kv，測試注入假件即可不觸資料庫）。
Future<bool> initRustEngine({
  required Future<void> Function() init,
  int attempts = 2,
  Duration retryDelay = const Duration(seconds: 2),
  Future<void> Function(Duration) delay = Future<void>.delayed,
  Future<void> Function(String error)? recordFailure,
  FutureOr<void> Function()? recordRecovered,
}) async {
  final fail = recordFailure ??
      (String error) => AppSettings.set(kRustEngineErrorKey, error);
  final recovered = recordRecovered ??
      () => AppSettings.remove(kRustEngineErrorKey);
  Object? lastError;
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      await init();
    } catch (e, s) {
      lastError = e;
      // ignore: avoid_print
      print('vodozemac init failed (attempt ${attempt + 1}/$attempts): $e\n$s');
      if (attempt + 1 < attempts) {
        await delay(retryDelay);
      }
      continue;
    }
    // 成功即判定成功：清歷史失敗旗標（提示／診斷只反映當前 session 狀態）。
    // kv 清除失敗≠引擎失敗——不得因此重試 init 或落錯誤旗標（誤報）。
    try {
      await recovered();
    } catch (_) {}
    return true;
  }
  try {
    await fail('$lastError');
  } catch (_) {
    // kv 記錄失敗不吞掉引擎失敗事實（print 已留痕於 logcat）。
  }
  return false;
}
