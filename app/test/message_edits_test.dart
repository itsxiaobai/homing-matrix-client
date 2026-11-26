// 訊息編輯解析（第四十二批）——單元測試。
// 以 SDK 官方 `Event.fromJson` 造事件（不需網路），驗證：
// ① 自建編輯對照能套用新內容；② 多個編輯取最新；③ 非編輯事件原樣；
// ④ `m.new_content` 缺漏時不誤判。
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/message_edits.dart';

Event _textEvent(
  Room room,
  String id,
  String body, {
  String? relatesTo,
  String? relType,
  Map<String, dynamic>? newContent,
  int ts = 1000,
}) {
  final content = <String, dynamic>{
    'msgtype': 'm.text',
    'body': body,
    'm.new_content': ?newContent,
  };
  if (relatesTo != null) {
    content['m.relates_to'] = {'event_id': relatesTo, 'rel_type': relType};
  }
  return Event.fromJson(<String, dynamic>{
    'event_id': id,
    'sender': '@alice:matrix.org',
    'origin_server_ts': ts,
    'type': 'm.room.message',
    'content': content,
  }, room);
}

void main() {
  late Room room;

  setUp(() {
    final client = createClient();
    room = Room(id: '!room:matrix.org', client: client);
  });

  test('①有編輯事件 → 顯示新內容並標記已編輯', () {
    final original = _textEvent(room, '\$orig', '舊內容');
    final edit = _textEvent(
      room,
      '\$edit',
      '* 新內容',
      relatesTo: '\$orig',
      relType: RelationshipTypes.edit,
      newContent: <String, dynamic>{
        'msgtype': 'm.text',
        'body': '新內容',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<b>新內容</b>',
      },
      ts: 2000,
    );
    final map = buildEditMap([original, edit]);
    final resolved = resolveMessageContent(original, map);
    expect(resolved.edited, isTrue);
    expect(resolved.body, '新內容');
    expect(resolved.formattedBody, '<b>新內容</b>');
  });

  test('②多個編輯 → 取最新（origin_server_ts）', () {
    final original = _textEvent(room, '\$orig', '舊內容');
    final edit1 = _textEvent(
      room,
      '\$e1',
      '* 第一次',
      relatesTo: '\$orig',
      relType: RelationshipTypes.edit,
      newContent: <String, dynamic>{'body': '第一次'},
      ts: 2000,
    );
    final edit2 = _textEvent(
      room,
      '\$e2',
      '* 第二次',
      relatesTo: '\$orig',
      relType: RelationshipTypes.edit,
      newContent: <String, dynamic>{'body': '第二次'},
      ts: 3000,
    );
    final map = buildEditMap([original, edit1, edit2]);
    expect(resolveMessageContent(original, map).body, '第二次');
  });

  test('③無編輯 → 原樣（未標記）', () {
    final original = _textEvent(room, '\$orig', '原內容');
    final resolved = resolveMessageContent(original, buildEditMap([original]));
    expect(resolved.edited, isFalse);
    expect(resolved.body, '原內容');
    expect(resolved.formattedBody, isNull);
  });

  test('④編輯事件缺 m.new_content → 不誤套用（維持原文）', () {
    final original = _textEvent(room, '\$orig', '原內容');
    final badEdit = _textEvent(
      room,
      '\$e1',
      '* 只有 fallback body',
      relatesTo: '\$orig',
      relType: RelationshipTypes.edit,
    );
    final map = buildEditMap([original, badEdit]);
    final resolved = resolveMessageContent(original, map);
    expect(resolved.body, '原內容');
    expect(resolved.edited, isFalse);
  });

  test('⑤非編輯關聯（例：reaction）不影響對照', () {
    final original = _textEvent(room, '\$orig', '原內容');
    final reaction = _textEvent(
      room,
      '\$r1',
      '👍',
      relatesTo: '\$orig',
      relType: RelationshipTypes.reaction,
    );
    final map = buildEditMap([original, reaction]);
    expect(map.isEmpty, isTrue);
    expect(resolveMessageContent(original, map).edited, isFalse);
  });
}
