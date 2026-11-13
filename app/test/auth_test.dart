// 任務：Phase 1 / 1.3 — auth.dart 單元測試（不涉網路）
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/auth.dart';

void main() {
  group('normalizeUserId', () {
    final homeserver = Uri.parse('https://matrix.org');

    test('本地部分補上 @ 與伺服器網域', () {
      expect(normalizeUserId('alice', homeserver), '@alice:matrix.org');
    });

    test('已是完整 Matrix ID 時原樣保留', () {
      expect(
        normalizeUserId('@bob:example.org', homeserver),
        '@bob:example.org',
      );
    });

    test('含網域但缺 @ 時補上 @', () {
      expect(normalizeUserId('carol:example.org', homeserver), '@carol:example.org');
    });

    test('去除前後空白', () {
      expect(normalizeUserId('  dave  ', homeserver), '@dave:matrix.org');
    });

    test('自訂 homeserver 的網域取自 host', () {
      expect(
        normalizeUserId('erin', Uri.parse('https://chat.example.net')),
        '@erin:chat.example.net',
      );
    });
  });

  group('registrationPageFromIssuer', () {
    test('matrix.org 的 MAS issuer → account.matrix.org/register', () {
      expect(
        registrationPageFromIssuer(Uri.parse('https://account.matrix.org/'))
            .toString(),
        'https://account.matrix.org/register',
      );
    });

    test('issuer 帶路徑時附在其後', () {
      expect(
        registrationPageFromIssuer(Uri.parse('https://auth.example.org/mas/'))
            .toString(),
        'https://auth.example.org/mas/register',
      );
    });

    test('issuer 無 host 時回傳 null', () {
      expect(registrationPageFromIssuer(Uri.parse('/register')), isNull);
    });
  });
}
