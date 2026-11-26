// 第六十九批（F-2/P1 預約訊息）＋第八十一批（人類「全部做；#4 放 server」）。
//
// Matrix 協定沒有預約送出 → 純 client 側：**server account data 為權威**
// （io.github.itsxiaobai.scheduled，per-user → 不同帳號自然隔離），
// 本機 kv 為快取／離線 fallback。前景 Timer 到期呼叫 SDK 官方 sendEvent。
// ⚠️ 前景限制：App 凍結／殺掉時 Timer 不觸發 → 重開補送（不另做背景服務）。
//
// 本檔做純邏輯＋AppSettings 讀寫＋Client account data 橋接（可單測純函式）。
import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'app_settings.dart';

/// 本機 kv key（離線快取／舊格式）。
const String kScheduledMessagesKey = 'scheduled_messages';

/// **server account data type**（per-user，不同帳號隔離）。
const String kScheduledAccountDataType = 'io.github.itsxiaobai.scheduled';

class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.roomId,
    required this.text,
    required this.dueAt,
    this.silent = false,
    this.markdown = false,
    this.failCount = 0,
    this.repeatDays = 0,
    this.attachmentName,
    this.attachmentMime,
  });

  final String id;
  final String roomId;
  final String text;

  /// 到期時間（millisecondsSinceEpoch，絕對時刻）。
  final int dueAt;

  ///  #2：無聲傳送旗標（到期送出時套用）。
  final bool silent;

  /// #2：Markdown 格式化（到期送出時套用）。
  final bool markdown;

  /// #3：連續失敗次數（達閾值→通知並停送）。
  final int failCount;

  /// #5：重複週期（天；0＝只送一次）。到期後算下一次而非移除。
  final int repeatDays;

  /// #6：附件檔名／MIME（metadata 可進 server；**路徑只存本機**）。
  final String? attachmentName;
  final String? attachmentMime;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'roomId': roomId,
        'text': text,
        'dueAt': dueAt,
        'silent': silent,
        'markdown': markdown,
        'failCount': failCount,
        'repeatDays': repeatDays,
        if (attachmentName != null) 'attachmentName': attachmentName,
        if (attachmentMime != null) 'attachmentMime': attachmentMime,
      };

  static ScheduledMessage? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final roomId = value['roomId'];
    final text = value['text'];
    final dueAt = value['dueAt'];
    if (id is! String ||
        roomId is! String ||
        text is! String ||
        dueAt is! int) {
      return null;
    }
    if (id.isEmpty || roomId.isEmpty || text.isEmpty) return null;
    return ScheduledMessage(
      id: id,
      roomId: roomId,
      text: text,
      dueAt: dueAt,
      silent: value['silent'] == true,
      markdown: value['markdown'] == true,
      failCount: value['failCount'] is int ? value['failCount'] as int : 0,
      repeatDays: value['repeatDays'] is int ? value['repeatDays'] as int : 0,
      attachmentName: value['attachmentName'] is String
          ? value['attachmentName'] as String
          : null,
      attachmentMime: value['attachmentMime'] is String
          ? value['attachmentMime'] as String
          : null,
    );
  }
}

/// 舊格式（只有 id/roomId/text/dueAt）也能解析，新欄位給預設值。
List<ScheduledMessage> parseScheduledMessages(String? raw) {
  if (raw == null || raw.isEmpty) return const <ScheduledMessage>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <ScheduledMessage>[];
    final result = <ScheduledMessage>[];
    for (final item in decoded) {
      final parsed = ScheduledMessage.fromJson(item);
      if (parsed != null) result.add(parsed);
    }
    return result;
  } on Object {
    return const <ScheduledMessage>[];
  }
}

String encodeScheduledMessages(List<ScheduledMessage> messages) =>
    jsonEncode(<Object?>[for (final m in messages) m.toJson()]);

List<ScheduledMessage> dueScheduledMessages(
  List<ScheduledMessage> messages,
  int now,
) =>
    messages.where((m) => m.dueAt <= now).toList();

/// #5：計算下一次到期（repeatDays>0）；只加整天，避免閏月漂移。
int nextDueAt(ScheduledMessage m, int now) {
  if (m.repeatDays <= 0) return m.dueAt;
  var next = m.dueAt;
  final day = Duration(days: m.repeatDays).inMilliseconds;
  while (next <= now) {
    next += day;
  }
  return next;
}

/// #3：失敗上限（連續失敗達此值→通知使用者並停止重試）。
const int kScheduledMaxFailures = 3;

// ---- 本機 kv（快取／離線 fallback） ----
Future<List<ScheduledMessage>> loadScheduledMessages() async {
  try {
    return parseScheduledMessages(await AppSettings.get(kScheduledMessagesKey));
  } on Object {
    return const <ScheduledMessage>[];
  }
}

Future<void> saveScheduledMessages(List<ScheduledMessage> messages) async {
  await AppSettings.set(kScheduledMessagesKey, encodeScheduledMessages(messages));
}

// ---- server account data（per-user；不同帳號隔離） ----
List<ScheduledMessage> parseScheduledAccountData(Object? content) {
  if (content is! Map) return const <ScheduledMessage>[];
  final list = content['messages'];
  if (list is! List) return const <ScheduledMessage>[];
  final result = <ScheduledMessage>[];
  for (final item in list) {
    final parsed = ScheduledMessage.fromJson(item);
    if (parsed != null) result.add(parsed);
  }
  return result;
}

/// 從 server account data 載入（失敗→回本機 kv）。
Future<List<ScheduledMessage>> loadScheduledFromServer(Client client) async {
  try {
    final content = client.accountData[kScheduledAccountDataType]?.content;
    final list = parseScheduledAccountData(content);
    await saveScheduledMessages(list); // 更新本機快取
    return list;
  } on Object {
    return loadScheduledMessages();
  }
}

/// 寫回 server＋本機（server 為權威）。
Future<void> saveScheduledToServer(
  Client client,
  List<ScheduledMessage> messages,
) async {
  await saveScheduledMessages(messages);
  final uid = client.userID;
  if (uid == null) return;
  try {
    await client.setAccountData(
      uid,
      kScheduledAccountDataType,
      <String, Object?>{'messages': [
        for (final m in messages) m.toJson(),
      ]},
    );
  } on Object {
    // homeserver 不支援 account data：本機快取仍有效（離線情形）。
  }
}

Future<void> addScheduledMessage(Client? client, ScheduledMessage message) async {
  final all = client == null
      ? await loadScheduledMessages()
      : await loadScheduledFromServer(client);
  final next = <ScheduledMessage>[
    ...all.where((m) => m.id != message.id),
    message,
  ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  if (client == null) {
    await saveScheduledMessages(next);
  } else {
    await saveScheduledToServer(client, next);
  }
}

Future<void> removeScheduledMessage(Client? client, String id) async {
  final all = client == null
      ? await loadScheduledMessages()
      : await loadScheduledFromServer(client);
  final next = all.where((m) => m.id != id).toList();
  if (client == null) {
    await saveScheduledMessages(next);
  } else {
    await saveScheduledToServer(client, next);
  }
}

/// #5：编辑既有预约（同 id 覆写内容／时间）。
Future<void> updateScheduledMessage(
  Client? client,
  String id,
  ScheduledMessage updated,
) async {
  final all = client == null
      ? await loadScheduledMessages()
      : await loadScheduledFromServer(client);
  final next = all
      .map((m) => m.id == id ? updated : m)
      .toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  if (client == null) {
    await saveScheduledMessages(next);
  } else {
    await saveScheduledToServer(client, next);
  }
}

// ---- #6：附件本機路徑（不進 server；server 只存 metadata） ----
const String kScheduledAttachmentPathsKey = 'scheduled_attachment_paths';

Map<String, String> parseAttachmentPaths(String? raw) {
  if (raw == null || raw.isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, String>{};
    return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
  } on Object {
    return <String, String>{};
  }
}

Future<Map<String, String>> loadAttachmentPaths() async {
  try {
    return parseAttachmentPaths(await AppSettings.get(kScheduledAttachmentPathsKey));
  } on Object {
    return <String, String>{};
  }
}

Future<void> saveAttachmentPaths(Map<String, String> paths) async {
  await AppSettings.set(kScheduledAttachmentPathsKey, jsonEncode(paths));
}

Future<void> setAttachmentPath(String id, String path) async {
  final all = await loadAttachmentPaths();
  all[id] = path;
  await saveAttachmentPaths(all);
}

Future<void> removeAttachmentPath(String id) async {
  final all = await loadAttachmentPaths();
  all.remove(id);
  await saveAttachmentPaths(all);
}
