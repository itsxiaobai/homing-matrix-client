// 批次 E（2026-11-01 人類批准）：Matrix 投票（MSC3381）雙前綴相容層（草案）。
// 事實（本機 SDK matrix-14.2.0 源碼）：`PollEventContent.startType` 等常數為
// **unstable** 前綴 `org.matrix.msc3381.*`；MSC3381 未併入 spec（2026-11-06
// 已查證至最新 spec：v1.18 v1.19 changelog 內含內容均無投票相關項；
// MSC 原文 https://github.com/matrix-org/matrix-spec-proposals/blob/main/
// proposals/3381-polls.md 仍堅持「stable 型別僅限支援 extensible events 的
// room version」且 Element 系（rust-sdk 依賴 ruma）在一般 room version
// 同樣只發 unstable 型別）。結論：Homing 發送端走 unstable 前綴是**正確
// 行為**，不需也不應改；本檔僅做讀取相容，不含任何加密邏輯（加密由
// 房間的官方 E2EE 機制處理）。

import 'package:matrix/matrix.dart';

/// start 事件：unstable（SDK 官方）＋ stable 名稱（MSC3381 文件）。
const kPollStartTypes = {
  PollEventContent.startType, // org.matrix.msc3381.poll.start
  'm.poll.start',
};

const kPollResponseTypes = {
  PollEventContent.responseType, // org.matrix.msc3381.poll.response
  'm.poll.response',
};

const kPollEndTypes = {
  PollEventContent.endType, // org.matrix.msc3381.poll.end
  'm.poll.end',
};

/// 讀 start 事件內容（dual：unstable＋stable 鍵）。
/// SDK 官方 `Event.parsedPollEventContent` 只讀 unstable 鍵，且強制要求
/// `org.matrix.msc1767.text` fallback 欄位（缺了直接 throw）→ 不能直接用。
PollStartContent? pollStartContentCompat(Event event) {
  for (final key in kPollStartTypes) {
    final raw = event.content[key];
    if (raw is Map<String, dynamic>) {
      return PollStartContent.fromJson(raw);
    }
  }
  return null;
}

/// 取事件指向的 reference 目標（m.relates_to.event_id；官方欄位）。
String? _referenceTarget(Event event) {
  final rel = event.content['m.relates_to'];
  if (rel is Map<String, dynamic>) {
    final target = rel['event_id'];
    if (target is String) {
      return target;
    }
  }
  return null;
}

/// 投票結束事件的時間（dual end 型別；任一存在即算結束，取最早一個）。
DateTime? pollEndedTsCompat(Timeline timeline, String startEventId) {
  DateTime? earliest;
  for (final e in timeline.events) {
    if (!kPollEndTypes.contains(e.type) || _referenceTarget(e) != startEventId) {
      continue;
    }
    final ts = e.originServerTs;
    if (earliest == null || ts.isBefore(earliest)) {
      earliest = ts;
    }
  }
  return earliest;
}

/// 投票是否已被結束（unstable＋stable 的 end 事件皆視為結束）。
bool pollEndedCompat(Timeline timeline, String startEventId) {
  return pollEndedTsCompat(timeline, startEventId) != null;
}

/// 從 timeline 掃描「回應這個投票」的事件（unstable＋stable 皆計）→
/// 每人**最新一次**的選擇（SDK 官方 getPollResponses 同規則：
/// 較舊的 response 忽略；結束事件之後的 response 也忽略）。
///
/// 為何不用 SDK 官方版：`Event.getPollResponses` 只認 unstable response
/// 型別且經 reference 聚合索引；Element 系可能發出穩定型別 `m.poll.response`。
Map<String, Set<String>> pollResponsesCompat(
  Timeline timeline,
  String startEventId,
) {
  final endTs = pollEndedTsCompat(timeline, startEventId);
  // timeline.events 由新到舊 → 每人**第一次**見到即最新一次。
  final out = <String, Set<String>>{};
  for (final event in timeline.events) {
    if (!kPollResponseTypes.contains(event.type) ||
        _referenceTarget(event) != startEventId) {
      continue;
    }
    if (endTs != null && event.originServerTs.isAfter(endTs)) {
      continue; // 結束後的回應不計（SDK 官方同規則）。
    }
    // 投票內容鍵與事件型別同前綴：unstable 事件 → org.matrix.msc3381.poll.response；
    // stable 事件 → m.poll.response。
    final payloadKey =
        event.type.startsWith('m.')
        ? 'm.poll.response'
        : PollEventContent.responseType;
    final payload = event.content[payloadKey];
    final raw = payload is Map<String, dynamic>
        ? payload['answers']
        : null;
    final votes = (raw is List)
        ? raw.whereType<String>().toSet()
        : <String>{};
    if (votes.isEmpty) {
      continue; // 空回應＝未投票（草案；放入計票反而誤導）。
    }
    if (out.containsKey(event.senderId)) {
      continue; // 已記錄較新的一次。
    }
    out[event.senderId] = votes;
  }
  return out;
}

/// 發送結束投票：SDK 官方 `Event.endPoll` 同 schema（unstable end 型別＋
/// m.relates_to reference）＋ **org.matrix.msc1767.text fallback 文字**
/// （批次 E 人類批准；部分客戶端需要文字 fallback 才能顯示「已結束」）。
Future<String?> endPollWithFallback(Room room, Event startEvent) {
  return room.sendEvent(
    {
      'm.relates_to': {
        'rel_type': RelationshipTypes.reference,
        'event_id': startEvent.eventId,
      },
      PollEventContent.endType: <String, dynamic>{},
      'org.matrix.msc1767.text': '投票已結束', // 文案草案
    },
    type: PollEventContent.endType,
  );
}
