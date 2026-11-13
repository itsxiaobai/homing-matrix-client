import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/ui/message_filter.dart';

void main() {
  test('filter sender blocked', () {
    final f = ChatFilter(blockedSenders: {'@bad:server'}, mutedKeywords: {});
    final ev = fakeEvent(senderId: '@bad:server', body: 'hello');
    expect(f.isVisible(ev), isFalse);
  });

  test('filter keyword block', () {
    final f = ChatFilter(blockedSenders: {}, mutedKeywords: {'spam'});
    final ev = fakeEvent(senderId: '@alice:server', body: 'buy spam now');
    expect(f.isVisible(ev), isFalse);
  });

  test('filter passes normal', () {
    final f = ChatFilter(blockedSenders: {}, mutedKeywords: {});
    final ev = fakeEvent(senderId: '@alice:server', body: 'hi');
    expect(f.isVisible(ev), isTrue);
  });

  test('filter filterEvents list', () {
    final f = ChatFilter(blockedSenders: {'@bad:server'}, mutedKeywords: {'spam'});
    final events = [
      fakeEvent(senderId: '@bad:server', body: 'x'),
      fakeEvent(senderId: '@alice:server', body: 'buy spam'),
      fakeEvent(senderId: '@bob:server', body: 'hi'),
    ];
    expect(f.filterEvents(events), hasLength(1));
  });
}

/// Minimal Event factory via matrix JSON for testing util.
Event fakeEvent({required String senderId, required String body}) {
  return Event.fromJson(
    {
      'event_id': '\$e',
      'type': 'm.room.message',
      'sender': senderId,
      'origin_server_ts': 1,
      'content': {'msgtype': 'm.text', 'body': body},
    },
    Room(id: '!r:s', client: _bareClient()),
  );
}

Client _bareClient() {
  // lightweight in-memory without open? Use buildWithoutOpen directly via matrix
  return Client(
    'ring',
    database: MatrixSdkDatabase.buildWithoutOpen('ring'),
  );
}
