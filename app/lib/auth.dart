// 任務：Phase 1 / 1.3 — 登入與「網頁註冊」流程（骨架）
// 邊界（依 AGENTS.md）：
// * 不處理加密／金鑰／裝置驗證；本檔只做帳密登入與網頁註冊連結。
// * 1.4 前置（人類批准儲存方案 C）：登入改回**持久化 Client**
//   （`MatrixSdkDatabase.init` ＋ sqflite ＋ flutter_secure_storage，
//   access token／SSSS cache 走系統安全儲存；加密金鑰由 SDK 管理）。
// * 註冊：matrix.org（MAS）已關閉客戶端 /register，只提供網頁註冊；
//   本檔由 auth_metadata 的 issuer 推導網頁註冊頁（matrix.org 實測
//   https://account.matrix.org/register 回 200；其他伺服器⚠️待查證）。
import 'package:matrix/matrix.dart';
// Suggestion #1：官方 CryptoSetupExtension（getCryptoIdentityState／
// initCryptoIdentity）未由 matrix.dart 匯出 → 直引官方路徑。
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';

import 'client_factory.dart';

/// 預設 homeserver（人類決策 2026-10-31：matrix.org 為優先路徑）
final Uri defaultHomeserver = Uri.parse('https://matrix.org');

/// 密碼登入的動作抽象，供 UI 測試注入（不打網路）。
typedef PasswordLogin = Future<Client> Function({
  required Uri homeserver,
  required String user,
  required String password,
});

/// Suggestion #1「第一次登入時自動上傳裝置金鑰」（**人類批准 2026-11-05**；
/// 批准範圍＝「只有更動進行順序與自動化」，零自製加密邏輯——全部 SDK 官方 API）。
///
/// 背景（SDK matrix-14.2.0 官方源碼）：
/// * `Client.login()` → `Client.init()` 內部已自動建立 Encryption 並上傳
///   **olm 裝置金鑰**（olm_manager.dart L57-73：新 account 時
///   `uploadKeys(uploadDeviceKeys: true)`）。
/// * 但裝置要顯示「verified by its owner」還需要 cross-signing／SSSS；
///   未初始化時官方入口是 `Client.initCryptoIdentity()`（SDK
///   crypto_setup_extension.dart；生成新 SSSS／cross-signing／金鑰備份並
///   **自動自簽本裝置**，回傳新生成的 recovery key 字串）。
///
/// 本函式＝登入後的「進行順序與自動化」：
/// * `getCryptoIdentityState()`（官方）判斷狀態；
/// * identity **尚未初始化**（且帳號無任何 cross-signing／金鑰備份
///   account 資料）→ 官方 `initCryptoIdentity()` 自動設定；
/// * **已初始化**（含部份建立的混合狀態）→ **不動**（避免 wipe 使用者既有
///   identity；連線需 recovery key，由既有恢復流程人工處理）。
/// * 回傳新 recovery key（人類決定：登入後立即以畫面顯示一次供複製保管）；
///   失敗一律回 null（不阻擋登入）。
Future<String?> ensureFirstLoginCryptoIdentity(Client client) async {
  try {
    // 官方（client README／crypto_setup_extension）：等待首次同步再判斷，
    // 避免 account data 未到即誤判「未初始化」。
    final state = await client.getCryptoIdentityState();
    if (state.initialized) {
      return null;
    }
    // 防誤 wipe：任何一項 cross-signing／金鑰備份 account 資料已存在
    //（= 曾由其他 client建立的部份 identity）→ 不自動建立，留人工流程。
    const provisionedTypes = [
      EventTypes.MegolmBackup,
      EventTypes.CrossSigningSelfSigning,
      EventTypes.CrossSigningUserSigning,
      EventTypes.CrossSigningMasterKey,
    ];
    for (final type in provisionedTypes) {
      if (client.accountData[type] != null) {
        return null;
      }
    }
    return await client.initCryptoIdentity();
  } catch (_) {
    // 網路／timeout／引擎未載入：自動化失敗不留阻塞；人工恢復流程仍可用。
    return null;
  }
}

/// 以帳號密碼登入並回到**已持久化的 Client**（方案 C 儲存）。
///
/// * 登入走 `m.login.password`（MAS 相容層支援）。
/// * Client／Database 由 [createClient] 建立（client_factory 則持久化）；
///   成功後 session 與金鑰由 SDK 保存（Matrix 官方機制）。
/// * 失敗時丟出 [MatrixException] 或一般例外。
Future<Client> loginWithPassword({
  required Uri homeserver,
  required String user,
  required String password,
  Future<Client> Function()? createClient,
}) async {
  final client = await (createClient ?? createPersistentClient)();
  await client.checkHomeserver(homeserver);
  await client.login(
    LoginType.mLoginPassword,
    identifier: AuthenticationUserIdentifier(user: user),
    password: password,
    initialDeviceDisplayName: 'Homing (Flutter)',
  );
  return client;
}

/// 解析註冊頁的動作抽象，供 UI 測試注入（不打網路）。
typedef RegistrationPageResolver = Future<Uri?> Function(Uri homeserver);

/// 取得該 homeserver 的「網頁註冊頁」。
///
/// * 支援 MAS（delegated auth）的伺服器：auth_metadata 會带 issuer，
///   依 MAS 慣例註冊頁位於 `issuer + register`。
/// * 不支援 auth_metadata 的伺服器：回傳 `null`（由 UI 顯示說明）。
Future<Uri?> resolveRegistrationPage(Uri homeserver) async {
  final api = MatrixApi(homeserver: homeserver);
  try {
    final metadata = await api.getAuthMetadata();
    return registrationPageFromIssuer(metadata.issuer);
  } catch (_) {
    // 包含 M_UNRECOGNIZED（舊版 Synapse）與網路錯誤；註冊頁未知。
    return null;
  }
}

/// 由 OIDC issuer 推導 MAS 註冊頁。
///
/// 例：`https://account.matrix.org/` → `https://account.matrix.org/register`
/// （matrix.org 於 2026-10-31 實測回 HTTP 200）。
Uri? registrationPageFromIssuer(Uri issuer) {
  if (issuer.host.isEmpty) {
    return null;
  }
  var path = issuer.path;
  if (!path.endsWith('/')) {
    path = '$path/';
  }
  return issuer.replace(path: '${path}register');
}

/// 將使用者輸入正規化為 Matrix 使用者 ID。
///
/// 接受 `alice`、`@alice:matrix.org`、`alice:matrix.org`；
/// 只有本地部分時，網域取自 homeserver 的 host。
String normalizeUserId(String input, Uri homeserver) {
  final trimmed = input.trim();
  if (trimmed.startsWith('@')) {
    return trimmed;
  }
  if (trimmed.contains(':')) {
    return '@$trimmed';
  }
  return '@$trimmed:${homeserver.host}';
}
