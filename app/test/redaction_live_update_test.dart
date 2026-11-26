// 第五十四批測試（2026-11-16；不打網路）：**收回（m.room.redaction）即時更新**。
//
// 背景（人類回報 2026-11-16：「對方收回訊息，本機要重開才會更新」）：
// * 官方 SDK 只對 `room.lastEvent` 做 `Event.setRedactionEvent`
//   （matrix client.dart L3188）；其餘事件的收回狀態只存在 DB 裡。
// * 本專案 `_defaultLoadMessages` 重用同一 Timeline 實例（避免丟掉
//   requestHistory 抓到的歷史窗口）→ 記憶體中的舊事件物件永遠不會被標記
//   → 畫面不更新，必須重開 App。
//
// 修法：`applyRedactionToEvents` 就地套用收回（與官方 SDK 對 lastEvent 的
// 同一手法），不重建 Timeline。
//
// 覆蓋：套用成功／目標不在清單／收回事件缺少 redacts 欄位。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:matrix/matrix.dart';

Event _msg(
  Room room, {
  required String eventId,
  String body = '嗨',
}) =>
    Event(
      type: EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': body},
      senderId: '@alice:matrix.org',
      eventId: eventId,
      originServerTs: DateTime(2026, 11, 16, 10),
      room: room,
    );

Event _redaction(
  Room room, {
  String? redacts,
}) =>
    Event(
      type: EventTypes.Redaction,
      content: redacts == null
          ? <String, dynamic>{}
          : <String, dynamic>{'redacts': redacts},
      senderId: '@bob:matrix.org',
      eventId: r'$redaction-1',
      originServerTs: DateTime(2026, 11, 16, 11),
      room: room,
    );

void main() {
  group('第五十四批：收回即時更新', () {
    test('套用收回 → 目標事件被標記為已收回（回傳 true）', () {
      final client = createClient();
      final room = Room(id: '!redact:matrix.org', client: client);
      final target = _msg(room, eventId: r'$target');
      final other = _msg(room, eventId: r'$other');

      expect(target.redacted, isFalse);

      final applied = applyRedactionToEvents(
        [target, other],
        _redaction(room, redacts: r'$target'),
      );

      expect(applied, isTrue);
      expect(target.redacted, isTrue);
      // 其他事件不受影響。
      expect(other.redacted, isFalse);
    });

    test('目標不在當前清單 → 回傳 false（不影響任何事件）', () {
      final client = createClient();
      final room = Room(id: '!redact2:matrix.org', client: client);
      final other = _msg(room, eventId: r'$other');

      final applied = applyRedactionToEvents(
        [other],
        _redaction(room, redacts: r'$not-here'),
      );

      expect(applied, isFalse);
      expect(other.redacted, isFalse);
    });

    test('收回事件缺少 redacts 欄位 → 回傳 false', () {
      final client = createClient();
      final room = Room(id: '!redact3:matrix.org', client: client);
      final target = _msg(room, eventId: r'$target');

      final applied = applyRedactionToEvents([target], _redaction(room));

      expect(applied, isFalse);
      expect(target.redacted, isFalse);
    });
  });
}
