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
//
// 第五十一批（2026-11-16）：新增 `initRustEngineInIsolate()`——**背景
// isolate 內**的引擎初始化。理由（SDK 原始碼查證，見 PROGRESS 第五十一批）：
// * `flutter_rust_bridge` 2.13.0 `RustLib.instance` 未初始化時**拋**
//   StateError('flutter_rust_bridge has not been initialized. Did you
//   forget to call `await RustLib.init();`? …')；`RustLib.init()` 在**同一
//   isolate 內第二次呼叫會拋** StateError('Should not initialize
//   flutter_rust_bridge twice')。
// * matrix SDK 14.2.0 `encryptFile` → `CryptoUtils.aesCtr`／`sha256` 走
//   **vodozemac（rust）**（vodozemac-0.9.1 `lib/src/api.dart` L631-652），
//   非純 Dart → 在未 init 的 isolate 內呼叫必然炸上面那則錯誤。
// * 官方 SDK 既有同一模式：`NativeImplementationsIsolate(compute,
//   vodozemacInit: …)` 會在 isolate 內 `await vodozemacInit?.call()`
//   後才做 rust 操作（matrix-14.2.0
//   `lib/src/utils/native_implementations.dart` L198-281）。
import 'dart:async';

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

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
    // 同時標記「本 isolate 引擎已就緒」→ `initRustEngineInIsolate()` 不會
    // 重複 init（`RustLib.init()` 同 isolate 第二次會拋）。
    _isolateEngineReady = true;
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

/// 背景 isolate 內的引擎就緒旗標（**每個 isolate 各自一份**）。
///
/// ⚠️ 不可用 `vod.isInitialized()` 當「是否已初始化」的判斷：①`flutter_
/// vodozemac` 只匯出 `init()`（`isInitialized` 僅存在於 `vodozemac` 套件，
/// 而該套件目前為**傳遞依賴**，直接 import 會觸發
/// `depend_on_referenced_packages` 警告）；②更根本的是 vodozemac 的
/// `isInitialized()` 內部取 `RustLib.instance`，而該 getter 在未初始化時
/// **拋 StateError**（flutter_rust_bridge 2.13.0
/// `lib/src/main_components/entrypoint.dart` L29-38）→ 判斷本身就會炸。
/// 故本專案改以 **per-isolate 旗標**追蹤就緒狀態。
bool _isolateEngineReady = false;

/// 在**當前 isolate**（主 isolate 或背景 isolate）內初始化 vodozemac 引擎。
///
/// 背景 isolate 的 rust 狀態與主 isolate **互不相通**（flutter_rust_bridge
/// 的狀態是 isolate 區域的）→ 任何會走 rust 的 SDK 呼叫（矩陣檔案加密
/// `encryptFile`、金鑰備份 `generateUploadKeys`、Client 初始化後的
/// Olm/Megolm）在背景 isolate 都必須先呼叫本函式。
///
/// 行為：
/// * 已就緒（含主 isolate 走 `initRustEngine` 成功路徑）→ 直接回 true
///   （**不重複 init**：`RustLib.init()` 同一 isolate 第二次會拋
///   'Should not initialize flutter_rust_bridge twice'）。
/// * 初始化失敗 → 記錄原因並回 false（**不拋**，讓呼叫端決定如何回報）。
///
/// **本函式不接觸加密演算法／金鑰內容**，只做官方引擎初始化。
Future<bool> initRustEngineInIsolate() async {
  if (_isolateEngineReady) {
    return true;
  }
  try {
    await vod.init();
    _isolateEngineReady = true;
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('vodozemac init failed in isolate: $e');
    return false;
  }
}
