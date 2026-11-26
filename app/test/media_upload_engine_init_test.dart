// 第五十一批（2026-11-16）：背景 isolate 內的加密引擎初始化。
//
// 根因（人類 2026-11-16 實機回報：圖片上傳「已送出 0 個附件，1 個失敗
//（最後原因： Bad state: flutter_rust_bridge has not been initialized. Did
// you forget to call `await RustLib.init();`? …）」）：
// * matrix SDK 14.2.0 的 `encryptFile` → `CryptoUtils.aesCtr`／`sha256`
//   走 **vodozemac（rust）**（vodozemac-0.9.1 `lib/src/api.dart` L631-652），
//   而 rust 狀態是 **isolate 區域**的：未在該 isolate 內 `RustLib.init()`
//   就呼叫 → flutter_rust_bridge 拈 StateError。
// * 本批修法：背景 isolate 內先 `initRustEngineInIsolate()`（官方 SDK 的
//   `NativeImplementationsIsolate(vodozemacInit:)` 同款做法）。
//
// 本檔**不觸碰**任何加密演算法／金鑰內容，只驗證「引擎初始化失敗時的
// 錯誤路徑」與「冪等」。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homing/engine_init.dart';
import 'package:homing/media_upload.dart';

/// 假的引擎初始化（**頂層函式**：Isolate.run 的閉包只允許傳送可傳送的物件，
/// 頂層函式保證可傳送）。
Future<bool> fakeInitEngineFailure() async => false;

void main() {
  group('背景 isolate 的加密引擎初始化（第五十一批）', () {
    test('引擎未就緒時，encryptFileInBackground 拋明確錯誤（而非 rust 原文）',
        () async {
      await expectLater(
        encryptFileInBackground(
          Uint8List.fromList([1, 2, 3, 4]),
          initEngine: fakeInitEngineFailure,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('加密引擎未就緒'),
          ),
        ),
      );
    });

    test('initRustEngineInIsolate 不拋例外，且重複呼叫結果一致（冪等）', () async {
      // 測試環境（主機 VM）通常沒有 vodozemac 原生庫 → 應回 false 而非拋錯。
      final first = await initRustEngineInIsolate();
      final second = await initRustEngineInIsolate();
      expect(first, isA<bool>());
      expect(second, first, reason: '第二次呼叫不得重複 init（RustLib.init 同 isolate 二次會拋）');
    });
  });
}
