// 任務：Phase 0 / 0.10 — 客戶端支援自訂 homeserver URL
// 邊界（依 AGENTS.md）：不含加密／金鑰邏輯；此檔僅做使用者輸入解析。

/// 解析使用者輸入的 homeserver 位址。
///
/// 接受 `matrix.org`、`https://matrix.org`、`localhost:8008` 等常見輸入：
/// * 無 scheme 時預補 `https://`
/// * 一律要求 https；僅 localhost／127.0.0.1／[::1] 允許 http（本機開發測試用）
/// * 不接受帶路徑、query 或 fragment 的位址（homeserver 依規格以 host:port 為準）
/// * host 隻字元白名單（字母、數字、點、連字號、底線），避免寬鬆解析放進怪樣本
///
/// 回傳 `null` 代表輸入無效。
Uri? parseUserHomeserverUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  var text = trimmed;
  if (!text.contains('://')) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null) {
    return null;
  }

  final host = uri.host;
  if (host.isEmpty) {
    return null;
  }

  final isLocalhost =
      host == 'localhost' || host == '127.0.0.1' || host == '[::1]';
  if (!(uri.scheme == 'https' || (uri.scheme == 'http' && isLocalhost))) {
    return null;
  }

  // Homeserver 位址不含路徑、query、fragment
  if (uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }

  // host 驗證：一般名稱採白名單；IPv6 隻形式為 [::1]（僅本機例外允許 http，
  // 而非本機的 IPv6 仍需 https 並放行其括用法）
  final isIPv6 = host.startsWith('[') && host.endsWith(']');
  final hostValid = isIPv6
      ? RegExp(r'^\[[0-9a-fA-F:.]+\]$').hasMatch(host)
      : RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$').hasMatch(host);
  if (!hostValid) {
    return null;
  }

  return uri.replace(path: '');
}
