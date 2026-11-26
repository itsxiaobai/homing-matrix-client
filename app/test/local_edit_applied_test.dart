// 第五十六批測試（2026-11-16；不打網路）：**本機自己送出的編輯要立即套用**。
//
// 背景（人類回報 2026-11-16：「靠編輯完要其他地方有更新的時候才會變」）：
// 編輯（`m.replace`）的取得在兩處都有「只查一次」的快取——SDK
// `Timeline._relationRequests`（成功後永久保留）與 App 端
// `_editRelationsChecked` → **對同一則訊息的「後續編輯」永遠抓不到**。
//
// 修法：`resolveWithLocalEdits` 把「本機自己送出且成功」的編輯
// （targetEventId → 新 body）併入解析，官方對照優先、本機對照兜底。
//
// 覆蓋：①官方對照有編輯 → 用官方的 ②官方對照沒有、但本機有 → 用本機的
// ③兩者都沒有 → 維持原內容 ④官方只標「已編輯」但內容沒變 → 用本機的
// （否則會出現「有 (已編輯) 記號但內容還是舊的」）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/message_edits.dart';
import 'package:matrix/matrix.dart';

void main() {
  group('第五十六批：本機編輯立即套用', () {
    final client = Client(
      'homing',
      database: MatrixSdkDatabase.buildWithoutOpen('homing'),
    );
    final room = Room(id: '!edits:matrix.org', client: client);

    Event msg(String id, String body) => Event(
          type: EventTypes.Message,
          content: {'msgtype': 'm.text', 'body': body},
          senderId: '@alice:matrix.org',
          eventId: id,
          originServerTs: DateTime(2026, 11, 16, 10),
          room: room,
        );

    Event edit(String id, String target, String newBody) => Event(
          type: EventTypes.Message,
          content: {
            'msgtype': 'm.text',
            'body': '* $newBody',
            'm.new_content': {'msgtype': 'm.text', 'body': newBody},
            'm.relates_to': {
              'rel_type': RelationshipTypes.edit,
              'event_id': target,
            },
          },
          senderId: '@alice:matrix.org',
          eventId: id,
          originServerTs: DateTime(2026, 11, 16, 11),
          room: room,
        );

    test('官方對照有編輯 → 套用官方內容', () {
      final target = msg(r'$m1', '原文');
      final e = edit(r'$e1', r'$m1', '官方新內容');
      final resolved = resolveWithLocalEdits(
        target,
        buildEditMap([e]),
        localEdits: const {r'$m1': '本機新內容'},
      );
      expect(resolved.edited, isTrue);
      expect(resolved.body, '官方新內容');
    });

    test('官方對照沒有（relations 快取抓不到）但本機有 → 套用本機內容', () {
      final target = msg(r'$m2', '原文');
      final resolved = resolveWithLocalEdits(
        target,
        const {},
        localEdits: const {r'$m2': '本機新內容'},
      );
      expect(resolved.edited, isTrue);
      expect(resolved.body, '本機新內容');
    });

    test('兩者都沒有 → 維持原內容、未標記編輯', () {
      final target = msg(r'$m3', '原文');
      final resolved = resolveWithLocalEdits(target, const {});
      expect(resolved.edited, isFalse);
      expect(resolved.body, '原文');
    });

    test('官方只標「已編輯」但內容沒變 → 以本機對照為準', () {
      // 官方對照裡的編輯事件沒有 `m.new_content`（解析不出新內容）→
      // 官方解析結果會是「標了編輯、但 body 仍是原文」→ 不能採用，
      // 否則畫面會出現「有 (已編輯) 記號但內容還是舊的」。
      final target = msg(r'$m4', '原文');
      final noNewContent = Event(
        type: EventTypes.Message,
        content: {
          'msgtype': 'm.text',
          'body': '* 某個內容',
          'm.relates_to': {
            'rel_type': RelationshipTypes.edit,
            'event_id': r'$m4',
          },
        },
        senderId: '@alice:matrix.org',
        eventId: r'$e4',
        originServerTs: DateTime(2026, 11, 16, 11),
        room: room,
      );
      final resolved = resolveWithLocalEdits(
        target,
        buildEditMap([noNewContent]),
        localEdits: const {r'$m4': '本機新內容'},
      );
      expect(resolved.edited, isTrue);
      expect(resolved.body, '本機新內容');
    });
  });
}
