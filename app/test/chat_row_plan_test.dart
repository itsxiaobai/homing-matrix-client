// 訊息列計畫（第五十七批・效能）單元測試。
//
// 對應的實作：`app/lib/ui/chat_row_plan.dart`（純函式；不依賴 Flutter Widget）。
// 測試重點：日期分隔 chip 位置、組頭／組尾旗標、自己最後一則（已讀位置）。
//
// ⚠️ 重要（與舊 `_buildRows()` 行為一致）：**第一則有日期的訊息之前也會插入
// 日期分隔 chip**（舊碼的 `previousDayLabel` 初值為 null → 同樣會插）→
// 因此「N 則同日消息」＝ N+1 列（1 chip ＋ N 訊息）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/ui/chat_row_plan.dart';

/// 測試用訊息（只需寄件者與日期）。
class _Msg {
  const _Msg(this.sender, this.day);
  final String sender;
  final String? day;
}

/// 取計畫中的訊息列（略過日期 chip）。
List<ChatRowPlan> _messages(List<ChatRowPlan> plan) =>
    plan.where((r) => r.kind == ChatRowKind.message).toList();

void main() {
  group('buildChatRowPlan（第五十七批）', () {
    test('空清單 → 沒有列', () {
      final plan = buildChatRowPlan(
        messageCount: 0,
        senderOf: (_) => 'x',
        dayLabelOf: (_) => null,
        myId: 'me',
        latestOwnIndex: -1,
      );
      expect(plan, isEmpty);
    });

    test('同日同寄件者 → 1 個日期 chip ＋ 2 則訊息；組頭／組尾正確', () {
      final msgs = [
        const _Msg('a', '11/12'),
        const _Msg('a', '11/12'),
      ];
      final plan = buildChatRowPlan(
        messageCount: msgs.length,
        senderOf: (i) => msgs[i].sender,
        dayLabelOf: (i) => msgs[i].day,
        myId: 'me',
        latestOwnIndex: -1,
      );
      // 首則有日期 → 其前插入日期 chip（與舊行為一致）。
      expect(plan.length, 3);
      expect(plan[0].kind, ChatRowKind.daySeparator);
      expect(plan[0].label, '11/12');
      final rows = _messages(plan);
      expect(rows.length, 2);
      expect(rows[0].showSender, isTrue, reason: '第一則必為組頭');
      expect(rows[0].showTime, isFalse, reason: '下一則同寄件者 → 非組尾');
      expect(rows[1].showSender, isFalse, reason: '同寄件者連續 → 非組頭');
      expect(rows[1].showTime, isTrue, reason: '最後一則 → 組尾（顯示時間）');
    });

    test('換日 → 在該則之前再插入一個日期分隔 chip', () {
      final msgs = [
        const _Msg('a', '11/12'),
        const _Msg('a', '11/13'),
      ];
      final plan = buildChatRowPlan(
        messageCount: msgs.length,
        senderOf: (i) => msgs[i].sender,
        dayLabelOf: (i) => msgs[i].day,
        myId: 'me',
        latestOwnIndex: -1,
      );
      expect(plan.length, 4);
      expect(plan[0].kind, ChatRowKind.daySeparator);
      expect(plan[0].label, '11/12');
      expect(plan[1].kind, ChatRowKind.message);
      expect(plan[2].kind, ChatRowKind.daySeparator);
      expect(plan[2].label, '11/13');
      expect(plan[3].kind, ChatRowKind.message);
      expect(plan[3].messageIndex, 1);
    });

    test('換寄件者 → 新組頭（顯示頭像＋名字），前一則成為組尾', () {
      final msgs = [
        const _Msg('a', '11/12'),
        const _Msg('b', '11/12'),
      ];
      final plan = buildChatRowPlan(
        messageCount: msgs.length,
        senderOf: (i) => msgs[i].sender,
        dayLabelOf: (i) => msgs[i].day,
        myId: 'me',
        latestOwnIndex: -1,
      );
      final rows = _messages(plan);
      expect(rows.length, 2);
      expect(rows[0].showSender, isTrue);
      expect(rows[0].showTime, isTrue, reason: '下一則換人 → 組尾');
      expect(rows[1].showSender, isTrue, reason: '換寄件者 → 組頭');
      expect(rows[1].showTime, isTrue);
    });

    test('自己最後一則 → isLatestOwn（已讀標記位置）', () {
      final msgs = [
        const _Msg('me', '11/12'),
        const _Msg('b', '11/12'),
        const _Msg('me', '11/12'),
      ];
      final plan = buildChatRowPlan(
        messageCount: msgs.length,
        senderOf: (i) => msgs[i].sender,
        dayLabelOf: (i) => msgs[i].day,
        myId: 'me',
        latestOwnIndex: 2,
      );
      final rows = _messages(plan);
      expect(rows[0].isLatestOwn, isFalse);
      expect(rows[1].isLatestOwn, isFalse);
      expect(rows[2].isLatestOwn, isTrue);
    });

    test('pending（無日期）→ 不產生日期 chip', () {
      final msgs = [
        const _Msg('me', null),
        const _Msg('me', '11/12'),
      ];
      final plan = buildChatRowPlan(
        messageCount: msgs.length,
        senderOf: (i) => msgs[i].sender,
        dayLabelOf: (i) => msgs[i].day,
        myId: 'me',
        latestOwnIndex: -1,
      );
      expect(plan.where((r) => r.kind == ChatRowKind.daySeparator).length, 1);
      expect(plan.first.kind, ChatRowKind.message);
    });

    test('大量訊息（2000 則，同日）→ 2000 訊息列 ＋ 1 個日期 chip', () {
      final msgs = List<_Msg>.generate(
        2000,
        (i) => _Msg(i % 3 == 0 ? 'a' : 'b', '11/12'),
      );
      final plan = buildChatRowPlan(
        messageCount: msgs.length,
        senderOf: (i) => msgs[i].sender,
        dayLabelOf: (i) => msgs[i].day,
        myId: 'me',
        latestOwnIndex: -1,
      );
      expect(plan.length, 2001);
      expect(_messages(plan).length, 2000);
      expect(plan.where((r) => r.kind == ChatRowKind.daySeparator).length, 1);
    });
  });
}
