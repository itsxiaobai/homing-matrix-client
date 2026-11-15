// 金鑰恢復錯誤分流與就緒等待——第三十八批（實機根因）的單元測試。
// 不碰加密演算法：僅驗證「錯誤訊息分流」與「等待條件」兩個純邏輯。
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart' show InvalidPassphraseException;
import 'package:homing/crypto_recovery.dart';

void main() {
  group('describeRecoveryError', () {
    test('①本裝置 device key 未就緒 → 提示可稍候重試（非 key 不正確）', () {
      final msg = describeRecoveryError(
        Exception('Exception: Master or user keys not found'),
      );
      expect(msg, contains('尚未同步完成'));
      expect(msg, isNot(contains('不正確')));
    });

    test('②InvalidPassphraseException → 明確指出 key／密語不正確', () {
      final msg = describeRecoveryError(
        InvalidPassphraseException('Incorrect parity'),
      );
      expect(msg, contains('不正確'));
      expect(msg, contains('Incorrect parity'));
    });

    test('③Bad MAC / Incorrect → key 不正確', () {
      expect(describeRecoveryError(Exception('Bad MAC')), contains('不正確'));
      expect(
        describeRecoveryError(Exception('Wrong / unknown key: m.cross_signing.master')),
        contains('不正確'),
      );
    });

    test('④加密身份未初始化 / 已連上 / 加密未啟用 → 各自文案', () {
      expect(
        describeRecoveryError(Exception('Crypto identity is not initalized. Please check…')),
        contains('尚未初始化'),
      );
      expect(
        describeRecoveryError(Exception('Crypto identity is already connected. …')),
        contains('已連上'),
      );
      expect(
        describeRecoveryError(Exception('End to end encryption not available!')),
        contains('未啟用端對端加密'),
      );
    });

    test('⑤其他例外 → 原樣帶出（不吞細節）', () {
      expect(
        describeRecoveryError(Exception('Some other failure')),
        contains('Some other failure'),
      );
    });
  });

  group('waitUntil', () {
    test('①條件立即成立 → true', () async {
      expect(await waitUntil(() => true), isTrue);
    });

    test('②條件稍後成立 → true（輪詢）', () async {
      var n = 0;
      final ok = await waitUntil(
        () {
          n++;
          return n >= 3;
        },
        timeout: const Duration(seconds: 5),
        interval: const Duration(milliseconds: 10),
      );
      expect(ok, isTrue);
      expect(n, greaterThanOrEqualTo(3));
    });

    test('③逾時未成立 → false', () async {
      final ok = await waitUntil(
        () => false,
        timeout: const Duration(milliseconds: 120),
        interval: const Duration(milliseconds: 40),
      );
      expect(ok, isFalse);
    });
  });
}
