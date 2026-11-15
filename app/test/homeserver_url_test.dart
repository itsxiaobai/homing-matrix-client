// 任務：Phase 0 / 0.10 — homeserver URL 輸入解析單元測試
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/homeserver_url.dart';

void main() {
  group('parseUserHomeserverUrl', () {
    test('接受無 scheme 的 domain 輸入，預補 https', () {
      expect(
        parseUserHomeserverUrl('matrix.org').toString(),
        'https://matrix.org',
      );
    });

    test('接受 https 全網址與大小寫、去頭尾空白', () {
      expect(
        parseUserHomeserverUrl(' https://MATRIX.org/ ').toString(),
        'https://matrix.org',
      );
    });

    test('接受 https 帶 port', () {
      expect(
        parseUserHomeserverUrl('https://matrix.org:8448').toString(),
        'https://matrix.org:8448',
      );
    });

    test('localhost 允許 http（本機測試）', () {
      expect(
        parseUserHomeserverUrl('http://localhost:8008').toString(),
        'http://localhost:8008',
      );
      expect(
        parseUserHomeserverUrl('http://127.0.0.1').toString(),
        'http://127.0.0.1',
      );
    });

    test('非 localhost 的 http 拒絕', () {
      expect(parseUserHomeserverUrl('http://example.org'), isNull);
    });

    test('空白／無效輸入拒絕', () {
      expect(parseUserHomeserverUrl(''), isNull);
      expect(parseUserHomeserverUrl('   '), isNull);
      expect(parseUserHomeserverUrl('not a url'), isNull);
    });

    test('帶路徑或 query 拒絕（homeserver 以 host 為準）', () {
      expect(parseUserHomeserverUrl('https://matrix.org/room'), isNull);
      expect(parseUserHomeserverUrl('https://matrix.org?a=1'), isNull);
    });

    test('可切換到不同 server：輸入任意 domain 均產生對應 Uri', () {
      expect(
        parseUserHomeserverUrl('example.com').toString(),
        'https://example.com',
      );
    });
  });
}
