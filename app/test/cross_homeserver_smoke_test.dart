import 'package:flutter_test/flutter_test.dart';

import 'package:homing/homeserver_url.dart';

void main() {
  test('smoke: homeserver URL supports multiple domains', () {
    final domains = ['matrix.org', 'example.org', 'localhost:8008'];
    for (final d in domains) {
      final uri = parseUserHomeserverUrl(d);
      expect(uri, isNotNull, reason: 'failed for $d');
    }
  });

  test('parseUserHomeserverUrl rejects traversal', () {
    expect(parseUserHomeserverUrl('http://evil.org/../../etc'), isNull);
  });
}
