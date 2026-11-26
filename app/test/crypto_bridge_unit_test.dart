import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';
import 'package:homing/crypto_bridge.dart';

void main() {
  // A client that is not logged in has no encryption engine; the bridge must
  // refuse to invent one (forwards to official SDK API or throws).
  Client client() =>
      Client('ring', database: MatrixSdkDatabase.buildWithoutOpen('ring'));

  test('beginCrossSigning forwards to official Bootstrap or throws cleanly',
      () {
    final bridge = CryptoBridge(client: client());
    expect(
      () => bridge.beginCrossSigning(),
      throwsA(isA<StateError>()),
    );
  });

  test('secretStorageHandle/openSecretStorage require SDK engine', () async {
    final bridge = CryptoBridge(client: client());
    expect(() => bridge.secretStorageHandle(), throwsA(isA<StateError>()));
    await expectLater(
      bridge.openSecretStorage('EsTS'),
      throwsA(isA<StateError>()),
    );
  });

  test('startVerification requires cached device keys', () async {
    final bridge = CryptoBridge(client: client());
    try {
      await bridge.startVerification(
        userId: '@alice:example.org',
        deviceId: 'NODEVICE',
      );
      fail('expected StateError or engine-unavailable failure');
    } on StateError {
      // cached-keys guard fired (no engine: userDeviceKeys is empty)
    } on Exception {
      // SDK's own error surfaced; still a pass-through, no Homing logic
    }
  });

  test('bridge is a const-forwarding surface over the client', () {
    final c = client();
    final b1 = CryptoBridge(client: c);
    final b2 = CryptoBridge(client: c);
    expect(identical(b1, b2), isFalse);
    expect(b1.client, same(c));
    expect(b2.client, same(c));
  });
}
