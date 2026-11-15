// 任務（人類批准 2026-11-06）— 送出動作 429 退避重試的純邏輯測試。
// 覆蓋：
//   ①重試成功：前兩次拋 M_LIMIT_EXCEEDED、第三次成功 → 回傳成功值
//   ②等待时长照 retry_after_ms 伺服器建議
//   ③缺 retry_after_ms 時指數退避 1s→2s→4s
//   ④非限流錯誤（如 M_FORBIDDEN）不重試、直接回拋
//   ⑤上限用盡（3 次全 M_LIMIT_EXCEEDED）→ 回拋最後錯誤
// 邊界：不碰網路、不碰金鑰；delay 注入為同步完成。
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/ui/chat_screen.dart' show sendWithRateLimitRetry;

MatrixException _limited(int retryAfterMs) => MatrixException.fromJson({
      'errcode': 'M_LIMIT_EXCEEDED',
      'error': 'Too many requests',
      'retry_after_ms': retryAfterMs,
    });

void main() {
  group('sendWithRateLimitRetry（429 退避重試）', () {
    test('①前兩次 429、第三次成功 → 回傳成功值', () async {
      var remainFailures = 2;
      var calls = 0;
      final waits = <Duration>[];
      final result = await sendWithRateLimitRetry<String>(
        () {
          calls++;
          if (remainFailures == 0) {
            return Future.value('ok');
          }
          remainFailures--;
          return Future.error(_limited(500));
        },
        delay: (d) async => waits.add(d),
      );

      expect(result, 'ok');
      expect(calls, 3);
      expect(waits, hasLength(2));
    });

    test('②等待時長優先採用伺服器 retry_after_ms', () async {
      final waits = <Duration>[];
      try {
        await sendWithRateLimitRetry<int>(
          () => Future.error(_limited(2500)),
          delay: (d) async => waits.add(d),
        );
        fail('should rethrow');
      } on MatrixException catch (e) {
        expect(e.error, MatrixError.M_LIMIT_EXCEEDED);
      }
      // attempts=3 → 兩次等待。
      expect(waits, [
        const Duration(milliseconds: 2500),
        const Duration(milliseconds: 2500),
      ]);
    });

    test('③缺 retry_after_ms → 指數退避 1s→2s', () async {
      final waits = <Duration>[];
      var calls = 0;
      await sendWithRateLimitRetry<int>(
        () {
          calls++;
          if (calls == 3) {
            return Future.value(3);
          }
          // 伺服器可能不帶 retry_after_ms（MSC 說 optional）。
          return Future.error(MatrixException.fromJson({
            'errcode': 'M_LIMIT_EXCEEDED',
            'error': 'Too many requests',
          }));
        },
        delay: (d) async => waits.add(d),
      );
      expect(waits, [
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 2000),
      ]);
    });

    test('④非限流錯誤（M_FORBIDDEN）不重試、直接回拋', () async {
      var calls = 0;
      try {
        await sendWithRateLimitRetry<void>(
          () {
            calls++;
            return Future.error(MatrixException.fromJson({
              'errcode': 'M_FORBIDDEN',
              'error': 'denied',
            }));
          },
          delay: (_) async {},
        );
        fail('should rethrow');
      } on MatrixException catch (e) {
        expect(e.error, MatrixError.M_FORBIDDEN);
      }
      expect(calls, 1);
    });

    test('⑤3 次全 429 → 上限用盡回拋（呼叫 3 次為止）', () async {
      var calls = 0;
      try {
        await sendWithRateLimitRetry<void>(
          () {
            calls++;
            return Future.error(_limited(100));
          },
          delay: (_) async {},
        );
        fail('should rethrow');
      } on MatrixException catch (e) {
        expect(e.error, MatrixError.M_LIMIT_EXCEEDED);
      }
      expect(calls, 3);
    });
  });
}
