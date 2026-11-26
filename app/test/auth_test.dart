// 任務：Phase 1 / 1.3 — auth.dart 單元測試（不涉網路）
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/auth.dart';
import 'package:homing/accounts_store.dart';
import 'package:homing/oidc_login.dart';

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

  // 第一百零三批：MAS／OIDC deep link 分流（純函式，不進平台層）。
  group('OIDC callback 解析', () {
    test('只認本 App 的 scheme + host', () {
      expect(isOidcCallback(Uri.parse('$kOidcScheme://$kOidcHost?code=a&state=b')), isTrue);
      expect(isOidcCallback(Uri.parse('https://example.com/oidc?code=a')), isFalse);
    });

    test('取出 code 與 state', () {
      final params = oidcCallbackParams(
        Uri.parse('$kOidcScheme://$kOidcHost?code=abc&state=xyz'),
      );
      expect(params, isNotNull);
      expect(params!.code, 'abc');
      expect(params.state, 'xyz');
    });

    test('缺 code 或 state 回 null', () {
      expect(
        oidcCallbackParams(Uri.parse('$kOidcScheme://$kOidcHost?code=abc')),
        isNull,
      );
      expect(
        oidcCallbackParams(Uri.parse('$kOidcScheme://$kOidcHost?state=xyz')),
        isNull,
      );
    });
  });

  // 第一百零四批：多帳號中繼資料（純函式，不進 DB）。
  group('帳號資料序列化', () {
    test('往返保留所有欄位', () {
      final account = HomingAccount(
        id: 'homing_2',
        userId: '@alice:example.org',
        homeserver: 'https://example.org',
        addedAt: 123456,
      );
      final decoded = parseAccounts(encodeAccounts(<HomingAccount>[account]));
      expect(decoded.length, 1);
      expect(decoded.first.id, 'homing_2');
      expect(decoded.first.userId, '@alice:example.org');
      expect(decoded.first.homeserver, 'https://example.org');
      expect(decoded.first.dbFile, 'homing_2.db');
    });

    test('既有 ring 帳號仍用 ring.db', () {
      final legacy = HomingAccount(
        id: kLegacyAccountId,
        userId: '@bob:matrix.org',
        homeserver: 'https://matrix.org',
        addedAt: 1,
      );
      expect(legacy.dbFile, 'ring.db');
    });

    test('壞資料回空清單，不拋例外', () {
      expect(parseAccounts('not json'), isEmpty);
      expect(parseAccounts('{}'), isEmpty);
      expect(parseAccounts(null), isEmpty);
    });
  });
}
