// 第七十批（人類指示「先 1（content 旗標），如果不行再 2；收回時提供
// 一般收回／無痕收回選項」）— Homing 間的無痕收回。
//
// 做法：SDK `Room.redactEvent(eventId, reason: ...)` 的 reason 會進
// m.room.redaction 事件的 content → 用固定前綴當 Homing 私有旗標；
// 收到紅action 的 Homing client 以 `Event.redactedBecause.content['reason']`
// 判斷，因而**整列不 render**（不是顯示「[已收回]」）。
// 其他客戶端不認識此字串，仍會照自己的方式顯示收回（跨客戶端無痕做不到）。
//
// 不新增依賴、不改加密邏輯（只傳字串給官方 API）。分兩層：
// ① 純函式（可單測）；② 本機 kv 記憶已無痕收回的 eventId（跨重開／極端順序）。

import 'dart:convert';

import 'app_settings.dart';

/// 寫入 `reason` 的 Homing 私有前綴（版本化，日後可換 v2）。
const String kSilentRedactionMarker = 'io.github.itsxiaobai.silent:v1';

/// 無痕收回時傳給官方 redactEvent 的 reason 值。
String silentRedactionReason() => kSilentRedactionMarker;

/// 紅action 事件的 content 是否帶無痕旗標（純函式）。
bool isSilentRedactionContent(Map<String, Object?>? content) {
  final reason = content?['reason'];
  if (reason is! String) return false;
  return reason.contains(kSilentRedactionMarker);
}

/// 本機 kv key（JSON array of eventId）。
const String kSilentRedactionIdsKey = 'silent_redaction_ids';

/// 解析 kv（壞資料回空集合）。
Set<String> parseSilentRedactionIds(String? raw) {
  if (raw == null || raw.isEmpty) return <String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <String>{};
    return decoded.whereType<String>().toSet();
  } on Object {
    return <String>{};
  }
}

String encodeSilentRedactionIds(Set<String> ids) =>
    jsonEncode(ids.toList()..sort());

Future<Set<String>> loadSilentRedactions() async {
  try {
    return parseSilentRedactionIds(
      await AppSettings.get(kSilentRedactionIdsKey),
    );
  } on Object {
    return <String>{};
  }
}

Future<void> saveSilentRedactions(Set<String> ids) async {
  await AppSettings.set(kSilentRedactionIdsKey, encodeSilentRedactionIds(ids));
}

/// 記憶一筆（冪等）。
Future<void> addSilentRedactionId(Set<String> memory, String eventId) async {
  if (eventId.isEmpty || memory.contains(eventId)) return;
  memory.add(eventId);
  await saveSilentRedactions(memory);
}
