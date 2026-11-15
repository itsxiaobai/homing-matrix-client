// P2.15c（人類指示 2026-11-01）— MatrixRTC foci 發現（MSC4143）。
// 讀 homeserver 的 /.well-known/matrix/client，取 org.matrix.msc4143.rtc_foci，
// 找 type=livekit 的 focus，回傳 (serviceUrl, alias) 或 null（homeserver 未提供）。
// 不寫任何加密／金鑰程式碼；僅做 foci 解析。
import 'package:matrix/matrix.dart';

/// 從 homeserver 的 well-known 取得 LiveKit foci。
/// 回傳 (livekitServiceUrl, livekitAlias)；homeserver 未公告或解析失敗回 null。
Future<({String serviceUrl, String alias})?> resolveLiveKitFoci(Client client) async {
  try {
    final wk = await client.getWellknown();
    final foci = wk.additionalProperties['org.matrix.msc4143.rtc_foci'];
    if (foci is! List || foci.isEmpty) {
      return null;
    }
    Map<String, dynamic>? lk;
    for (final f in foci) {
      if (f is Map && f['type'] == 'livekit') {
        lk = Map<String, dynamic>.from(f);
        break;
      }
    }
    if (lk == null) {
      return null;
    }
    final url = lk['livekit_service_url'] as String?;
    if (url == null || url.isEmpty) {
      return null;
    }
    final alias = (lk['livekit_alias'] as String?) ?? (client.userID ?? 'ring');
    return (serviceUrl: url, alias: alias);
  } catch (_) {
    return null;
  }
}
