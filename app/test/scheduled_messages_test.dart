// 第六十九批（F-2/P1 預約訊息）：純邏輯單元測試（不碰 sqflite／Timer）。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/scheduled_messages.dart';

void main() {
  group('預約訊息（第六十九批）', () {
    test('解析空值／壞格式 → 空清單', () {
      expect(parseScheduledMessages(null), isEmpty);
      expect(parseScheduledMessages('not json'), isEmpty);
      expect(parseScheduledMessages('{}'), isEmpty);
      expect(parseScheduledMessages('[1, "x", null]'), isEmpty);
    });

    test('序列化 → 解析 還原欄位', () {
      final messages = [
        ScheduledMessage(
          id: 'a',
          roomId: '!r:example.org',
          text: '記得繳費',
          dueAt: 1800000000000,
        ),
      ];
      final decoded = parseScheduledMessages(encodeScheduledMessages(messages));
      expect(decoded.length, 1);
      expect(decoded.first.id, 'a');
      expect(decoded.first.roomId, '!r:example.org');
      expect(decoded.first.text, '記得繳費');
      expect(decoded.first.dueAt, 1800000000000);
    });

    test('缺欄位／空欄位的項目被略過', () {
      final raw = '[{"id":"ok","roomId":"!r","text":"hi","dueAt":5},'
          '{"id":"","roomId":"!r","text":"hi","dueAt":5},'
          '{"id":"bad","roomId":"!r","dueAt":5}]';
      expect(parseScheduledMessages(raw).length, 1);
    });

    test('到期筛选：dueAt <= now', () {
      final messages = [
        ScheduledMessage(id: 'a', roomId: '!r', text: '過去', dueAt: 100),
        ScheduledMessage(id: 'b', roomId: '!r', text: '現在', dueAt: 200),
        ScheduledMessage(id: 'c', roomId: '!r', text: '未來', dueAt: 300),
      ];
      final due = dueScheduledMessages(messages, 200);
      expect(due.map((m) => m.id), ['a', 'b']);
      expect(dueScheduledMessages(messages, 50), isEmpty);
    });

    test('第八十一批：新欄位silent/markdown/failCount/repeatDays 還原', () {
      final raw = jsonEncode([
        {
          'id': 'x',
          'roomId': '!r',
          'text': 'hi',
          'dueAt': 100,
          'silent': true,
          'markdown': true,
          'failCount': 2,
          'repeatDays': 7,
        }
      ]);
      final m = parseScheduledMessages(raw).single;
      expect(m.silent, isTrue);
      expect(m.markdown, isTrue);
      expect(m.failCount, 2);
      expect(m.repeatDays, 7);
    });

    test('第八十一批：週期計算 nextDueAt', () {
      final m = ScheduledMessage(
        id: 'r',
        roomId: '!r',
        text: 'hi',
        dueAt: 100,
        repeatDays: 7,
      );
      final day = const Duration(days: 7).inMilliseconds;
      expect(nextDueAt(m, 100), 100 + day);
      expect(nextDueAt(m, 100 + day * 3), 100 + day * 4);
      expect(nextDueAt(ScheduledMessage(
        id: 'o',
        roomId: '!r',
        text: 'hi',
        dueAt: 100,
      ), 999), 100);
    });

    test('第八十二批：附件本機路徑解析', () {
      expect(parseAttachmentPaths(null), isEmpty);
      expect(parseAttachmentPaths('bad'), isEmpty);
      final m = ScheduledMessage(
        id: 'a',
        roomId: '!r',
        text: 'file.pdf',
        dueAt: 5,
        attachmentName: 'file.pdf',
        attachmentMime: 'pdf',
      );
      expect(m.attachmentName, 'file.pdf');
      expect(parseAttachmentPaths('{"a":"/tmp/x.pdf"}')['a'], '/tmp/x.pdf');
    });

    test('第八十一批：Server account data 解析', () {
      expect(parseScheduledAccountData(null), isEmpty);
      expect(parseScheduledAccountData(<String, Object?>{}), isEmpty);
      expect(
        parseScheduledAccountData(<String, Object?>{
          'messages': [
            <String, Object?>{
              'id': 'a',
              'roomId': '!r',
              'text': 'hi',
              'dueAt': 5,
            }
          ]
        }).length,
        1,
      );
    });
  });
}
