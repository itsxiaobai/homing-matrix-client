// 第一百零三批（人類指示「完成 MAS」）：Matrix Authentication Service／OIDC 登入。
//
// 使用既有依賴（matrix SDK 的 MSC2964／2966 extension、app_links、url_launcher），
// **零新增依賴**。只呼叫官方 SDK API，不自行處理 token／加密。
//
// 流程：checkHomeserver → registerOidcClient（native，自訂 scheme）
//       → initOidcLoginSession → 外部瀏覽器授權 → app_links 收回 code/state
//       → oidcLogin（SDK 內部 init）→ 既有 onLoggedIn／crypto 自動化。
import 'dart:async';

import 'package:matrix/matrix.dart';

import 'client_factory.dart';

/// App 自訂 scheme（Android intent-filter／iOS CFBundleURLTypes 需對應）。
const String kOidcScheme = 'io.github.itsxiaobai.homing';
const String kOidcHost = 'oidc';

/// 動態註冊用的 redirect URI。native application type 允許自訂 scheme。
final Uri kOidcRedirectUri = Uri(scheme: kOidcScheme, host: kOidcHost);

final StreamController<Uri> _oidcCallbacks = StreamController<Uri>.broadcast();

/// SSO 授權完成後由 main.dart 的 deep link 分流推送。
Stream<Uri> get oidcCallbackStream => _oidcCallbacks.stream;

void pushOidcCallback(Uri uri) {
  if (!_oidcCallbacks.isClosed) _oidcCallbacks.add(uri);
}

/// 是否為本 App 的 OIDC callback（供 main.dart 分流，避免被當成分享內容）。
bool isOidcCallback(Uri uri) =>
    uri.scheme == kOidcScheme && uri.host == kOidcHost;

/// 解析 callback 上的 code／state；缺任一项回 null。
({String code, String state})? oidcCallbackParams(Uri uri) {
  if (!isOidcCallback(uri)) return null;
  final code = uri.queryParameters['code'];
  final state = uri.queryParameters['state'];
  if (code == null || code.isEmpty || state == null || state.isEmpty) {
    return null;
  }
  return (code: code, state: state);
}

/// 一批 OIDC 登入所需的 client ＋ session（session 內有 state／codeVerifier，
/// 必須留到 callback 回來；App 被殺掉就重來一次流程）。
class OidcLoginSessionHolder {
  const OidcLoginSessionHolder({
    required this.client,
    required this.session,
  });

  final Client client;
  final OidcLoginSession session;
}

/// 準備 OIDC 登入：動態註冊 client 並建立 authorization URI。
Future<OidcLoginSessionHolder> prepareOidcLogin(
  Uri homeserver, {
  Future<Client> Function()? createClient,
}) async {
  final client = await (createClient ?? createPersistentClient)();
  // fetchAuthMetadata：registerOidcClient／initOidcLoginSession 內部會讀它。
  await client.checkHomeserver(homeserver, fetchAuthMetadata: true);
  final oidcClient = await client.registerOidcClient(
    redirectUris: <Uri>[kOidcRedirectUri],
    applicationType: OidcApplicationType.native,
    clientInformation: OidcClientInformation(
      clientName: 'Homing',
      clientUri: Uri.parse('https://github.com/itsxiaobai/homing-alpha'),
      logoUri: null,
      tosUri: null,
      policyUri: null,
    ),
  );
  final session = await client.initOidcLoginSession(
    oidcClientData: oidcClient,
    redirectUri: kOidcRedirectUri,
  );
  return OidcLoginSessionHolder(client: client, session: session);
}

/// 用 callback 的 code／state 完成登入（SDK 官方 oidcLogin，內部 init）。
Future<void> completeOidcLogin(
  OidcLoginSessionHolder holder,
  Uri callback,
) async {
  final params = oidcCallbackParams(callback);
  if (params == null) {
    throw const FormatException('OIDC callback 缺少 code 或 state');
  }
  await holder.client.oidcLogin(
    session: holder.session,
    code: params.code,
    state: params.state,
  );
}
