// 修法 #2：collectMissingSessions 單元測試（不打網路、不碰真實金鑰）。
// 以 SDK 官方解析路徑（MatrixEvent.fromJson → Event.fromMatrixEvent）建事件。
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/missing_key_repair.dart';

Event _event(
  Room room, {
  required String eventId,
  String? type,
  Map<String, Object?> content = const {},
  Map<String, Object?>? unsigned,
}) {
  final matrixEvent = MatrixEvent.fromJson(<String, Object?>{
    'event_id': eventId,
    'sender': '@alice:matrix.org',
    'origin_server_ts': 1700000000000,
    'type': type ?? EventTypes.Encrypted,
    'content': content,
    'unsigned': ?unsigned,
  });
  return Event.fromMatrixEvent(matrixEvent, room);
}

Room _room() {
  final client = createClient();
  return Room(id: '!room-a:matrix.org', client: client);
}

void main() {
  test('列出解密失敗的 megolm session（同 session 去重）', () {
    final room = _room();
    final sessions = collectMissingSessions([
      _event(
        room,
        eventId: r'$a',
        content: {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'ciphertext': 'C',
          'session_id': 'S1',
          'sender_key': 'K1',
          'msgtype': MessageTypes.BadEncrypted,
        },
      ),
      // 同一 session 的第二則失敗事件 → 應去重（只請求一次）。
      _event(room, eventId: r'$b', content: {'session_id': 'S1', 'sender_key': 'K1'}),
      _event(room, eventId: r'$c', content: {'session_id': 'S2', 'sender_key': 'K2'}),
    ]);
    expect(sessions.map((s) => s.sessionId), ['S1', 'S2']);
    expect(sessions.first.senderKey, 'K1');
  });

  test('已解密／已收回／缺 session_id 的事件略過', () {
    final room = _room();
    final sessions = collectMissingSessions([
      // 解密成功的事件由 SDK 換成明文型別 → 不收。
      _event(
        room,
        eventId: r'$d',
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': 'ok'},
      ),
      // 已收回事件 → 不收（redacted_because 為完整的收回事件，SDK 慣例）。
      _event(
        room,
        eventId: r'$e',
        content: {'session_id': 'S3'},
        unsigned: {
          'redacted_because': <String, Object?>{
            'event_id': r'$redact-1',
            'sender': '@alice:matrix.org',
            'origin_server_ts': 1700000001000,
            'type': EventTypes.Redaction,
            'redacts': r'$e',
            'content': <String, Object?>{},
          },
        },
      ),
      // 無 session_id（如 olm 事件）→ 不收。
      _event(room, eventId: r'$f', content: {'ciphertext': 'C'}),
    ]);
    expect(sessions, isEmpty);
  });
}
