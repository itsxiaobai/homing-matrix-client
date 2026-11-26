// 訊息編輯解析（`m.replace`）——第四十二批（人類回報「已編輯訊息仍然還顯示
// 過去訊息」）。
//
// 為什麼不只用 SDK 的 `Event.getDisplayEvent(timeline)`：
// - SDK 的聚合樹 `timeline.aggregatedEvents` 只在**未加密**事件加入 timeline 時
//   建立；**E2EE 房間**的編輯事件在 sync 當下仍是 `m.room.encrypted`，
//   其 `relationshipType` 為 null → 不會被聚合 → 顯示舊內容。
// - 本模組直接掃描**已解密**的事件（含 App 端自行解密的事件）建立
//   「被編輯事件 id → 最新編輯事件」對照 → E2EE 房間同樣能正確套用編輯。
// - 仍保留 SDK 官方 `getDisplayEvent` 作為 fallback（未加密房間的既有路徑）。
import 'package:matrix/matrix.dart';

/// 解析後的訊息顯示內容。
class ResolvedMessageContent {
  const ResolvedMessageContent({
    required this.body,
    this.formattedBody,
    required this.edited,
  });

  /// 純文字內容（已套用編輯）。
  final String body;

  /// HTML 內容（`formatted_body`；已套用編輯）；無則 null。
  final String? formattedBody;

  /// 是否被編輯過（顯示「(已編輯)」記號用）。
  final bool edited;
}

/// 第五十六批（2026-11-16）：把**本機自己送出且成功**的編輯併入解析。
///
/// 為什麼需要：編輯（`m.replace`）的取得在兩處都有「只查一次」的快取——
/// SDK `Timeline._relationRequests`（成功後永久保留）與 App 端
/// `_editRelationsChecked` → **對同一則訊息的「後續編輯」永遠抓不到**
/// → 編輯完畫面不動，要等下一則其他事件帶來重載才會變（人類回報：
/// 「靠編輯完要其他地方有更新的時候才會變」）。
///
/// [localEdits] 為「被編輯事件 id → 新 body」（本機送出並成功者）。
///
/// 優先順序：**官方路徑真的換了內容才採用官方**；若官方只標了「已編輯」但
/// 內容沒變（SDK 聚合的編輯事件未通過「僅原作者的編輯有效」篩選）→ 以本機
/// 對照為準（否則會出現「有 (已編輯) 記號但內容還是舊的」）。
ResolvedMessageContent resolveWithLocalEdits(
  Event event,
  Map<String, Event> editMap, {
  Timeline? timeline,
  Map<String, String> localEdits = const {},
}) {
  final resolved = resolveMessageContent(event, editMap, timeline: timeline);
  final local = localEdits[event.eventId];
  if (local == null) {
    return resolved;
  }
  // 官方路徑真的套用了新內容 → 以官方為準。
  if (resolved.edited && resolved.body != event.body) {
    return resolved;
  }
  // 官方只標「已編輯」但內容沒變 → 以本機對照為準。
  // ⚠️ `formattedBody` 一併清掉：舊的 HTML 對應**舊內容** → 泡泡優先渲染
  // formattedBody → 會顯示舊文字（畫面與內容不一致）。
  return ResolvedMessageContent(
    body: local,
    formattedBody: null,
    edited: true,
  );
}

/// 建立「被編輯事件 id → 最新編輯事件」對照（依 `originServerTs` 取最新）。
Map<String, Event> buildEditMap(Iterable<Event> events) {
  final map = <String, Event>{};
  for (final e in events) {
    if (e.relationshipType != RelationshipTypes.edit) {
      continue;
    }
    final target = e.relationshipEventId;
    if (target == null || target.isEmpty) {
      continue;
    }
    final prev = map[target];
    if (prev == null || e.originServerTs.isAfter(prev.originServerTs)) {
      map[target] = e;
    }
  }
  return map;
}

/// 取出編輯事件的新內容（`m.new_content`）。
({String? body, String? formattedBody})? newContentOf(Event edit) {
  final raw = edit.content['m.new_content'];
  if (raw is! Map) {
    return null;
  }
  final body = raw['body'];
  final fb = raw['formatted_body'];
  return (
    body: body is String ? body : null,
    formattedBody: fb is String && fb.isNotEmpty ? fb : null,
  );
}

/// 解析事件的顯示內容（含編輯套用）。
///
/// [editMap] 由 [buildEditMap] 產生；[timeline] 為可选的 SDK 官方 fallback。
ResolvedMessageContent resolveMessageContent(
  Event event,
  Map<String, Event> editMap, {
  Timeline? timeline,
}) {
  final edit = editMap[event.eventId];
  if (edit != null) {
    final nc = newContentOf(edit);
    if (nc != null) {
      return ResolvedMessageContent(
        body: nc.body ?? event.body,
        formattedBody: nc.formattedBody,
        edited: true,
      );
    }
  }
  // Fallback：SDK 官方聚合解析（未加密房間；官方 getDisplayEvent 已處理
  // 「僅原作者的編輯有效」的語意）。
  if (timeline != null) {
    try {
      if (event.hasAggregatedEvents(timeline, RelationshipTypes.edit)) {
        final display = event.getDisplayEvent(timeline);
        return ResolvedMessageContent(
          body: display.body,
          formattedBody:
              display.formattedText.isNotEmpty ? display.formattedText : null,
          edited: true,
        );
      }
    } catch (_) {
      // 官方 API 失敗 → 退回原內容（不丟訊息）。
    }
  }
  return ResolvedMessageContent(
    body: event.body,
    formattedBody: null,
    edited: false,
  );
}
