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

  // 第六十七批：已解密事件快取（無 TTL）——重載時**重用**，不重解、不需引擎。
  test('decryptUndecryptedEvents：快取命中直接重用；登出清除後回到原事件', () async {
    final room = _room();
    clearDecryptedEventCache();
    final encrypted = _event(
      room,
      eventId: r'$cached',
      content: {'session_id': 'S-cache'},
    );
    // 以官方解析路徑造一則「已解密」事件當作快取值。
    final decrypted = Event.fromMatrixEvent(
      MatrixEvent.fromJson(<String, Object?>{
        'event_id': r'$cached',
        'sender': '@alice:matrix.org',
        'origin_server_ts': 1700000000000,
        'type': EventTypes.Message,
        'content': {'msgtype': 'm.text', 'body': '已解密的舊訊息'},
      }),
      room,
    );
    decryptedEventCache[room.id] = {r'$cached': decrypted};

    final first = await decryptUndecryptedEvents(room, [encrypted]);
    expect(identical(first.single, decrypted), isTrue); // 快取重用

    clearDecryptedEventCache(); // 登出＝清快取
    final second = await decryptUndecryptedEvents(room, [encrypted]);
    expect(identical(second.single, encrypted), isTrue); // 無引擎 → 原事件保留
  });
}
