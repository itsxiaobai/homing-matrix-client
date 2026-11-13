// 任務：Phase 1 / 1.1 — Flutter + matrix（matrix-dart-sdk）整合測試
//
// 邊界（依 AGENTS.md）：
// * 本檔不含任何加密邏輯、金鑰交換或金鑰處理程式碼。
// * 帳密一律由環境變數 RING_TEST_USER / RING_TEST_PASS 提供，不寫入任何檔案；
//   缺少環境變數時登入測試自動略過（skip）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/auth.dart' show resolveRegistrationPage;
import 'package:homing/client_factory.dart' show checkServer;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 藍圖 §一：初期用 matrix.org（客戶端必須支援自訂 homeserver URL，此值僅為測試預設）
const _matrixOrg = 'https://matrix.org';

/// 建立僅存在於測試進程記憶體內的 Client（in-memory sqlite，不落檔）
Future<Client> _testClient(String name) async {
  final sqfliteDb = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
  );
  final matrixDb = await MatrixSdkDatabase.init(name, database: sqfliteDb);
  return Client(name, database: matrixDb);
}

void main() {
  test(
    '1. homeserver 連線與相容性測試（無需帳號）',
    () async {
      final client = await _testClient('ring_integration_test');
      final (wellKnown, versions, loginTypes, _) =
          await client.checkHomeserver(Uri.parse(_matrixOrg));

      // 檢查 well-known 探索與實際 homeserver 已解析
      expect(client.homeserver, isNotNull);
      expect(wellKnown, isNotNull);

      // 檢查回傳規格版本清單，且至少有一版與 SDK 支援版本重疊
      expect(versions.versions, isNotEmpty);
      expect(
        versions.versions.any(Client.supportedVersions.contains),
        isTrue,
      );

      // 檢查登入流程（藍圖 P0：帳號密碼登入是基本要求）
      expect(
        loginTypes.map((f) => f.type),
        contains(LoginType.mLoginPassword),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '2. 帳號密碼登入測試（需要 RING_TEST_USER / RING_TEST_PASS）',
    () async {
      final user = Platform.environment['RING_TEST_USER'] ?? '';
      final pass = Platform.environment['RING_TEST_PASS'] ?? '';

      final client = await _testClient('ring_integration_test');
      await client.checkHomeserver(Uri.parse(_matrixOrg));

      final response = await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: user),
        password: pass,
        initialDeviceDisplayName: 'ring-integration-test',
      );
      expect(response.userId, isNotNull);
      expect(client.isLogged(), isTrue);

      // 測試後登出，避免該裝置 session 遺留在帳號上
      await client.logout();
    },
    skip: (Platform.environment['RING_TEST_USER'] ?? '').isEmpty ||
            (Platform.environment['RING_TEST_PASS'] ?? '').isEmpty
        ? '未提供 RING_TEST_USER/RING_TEST_PASS；帳號登入路徑延後至 1.3 以真實環境驗證（阻塞項 A 決議 D，2026-10-31）'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '3. 0.10 自訂 homeserver URL：以 client_factory 實測 matrix.org（無需帳號）',
    () async {
      expect(await checkServer(Uri.parse('https://matrix.org')), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '4. 1.3 matrix.org 網頁註冊頁解析（MAS delegated auth，無需帳號）',
    () async {
      final page = await resolveRegistrationPage(Uri.parse(_matrixOrg));
      expect(page, isNotNull);
      expect(page.toString(), 'https://account.matrix.org/register');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
