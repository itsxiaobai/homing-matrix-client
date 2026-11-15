// Task 1.5a — Crypto-UI Bridge (SDK official methods only)
//
// Agent does NOT author encryption logic, key derivation, key storage policy,
// verification state transitions, or bootstrap flow decisions. Every method in
// this file is a direct pass-through to ONE public matrix-dart-sdk 14.2.0 API:
//   * encryption.bootstrap(...)            -> Bootstrap state machine (human drives states)
//   * encryption.ssss.open / .unlock(...)  -> SSSS unlock (official decrypt path)
//   * DeviceKeys.startVerification(...)    -> official key verification request
//   * client.getDevices() / deleteDevice() -> device metadata (non-crypto)
// No SDK source is modified; no dependency added.
// Human cryptography review of this binding is still required (AGENTS.md §五).
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Forwards Homing UI actions to the matrix SDK's official crypto entry points.
final class CryptoBridge {
  const CryptoBridge({required this.client});

  final Client client;

  /// SDK `Encryption?` is null until the client is logged in with an
  /// initialized crypto engine. Bridge refuses to invent one.
  Encryption _requireEncryption() {
    final encryption = client.encryption;
    if (encryption == null) {
      throw StateError(
        'crypto unavailable: SDK encryption engine not initialized '
        '(client must be logged in with encryption enabled)',
      );
    }
    return encryption;
  }

  /// Returns the SDK's official bootstrap state machine (cross-signing +
  /// SSSS setup). The caller drives each state via the official onUpdate
  /// handler; Homing does not decide state transitions.
  Bootstrap beginCrossSigning({void Function(Bootstrap)? onUpdate}) =>
      _requireEncryption().bootstrap(onUpdate: onUpdate);

  /// Returns the official SSSS handle for the default key (or an explicit
  /// key id). Unlocking remains an explicit caller action.
  OpenSSSS secretStorageHandle([String? identifier]) =>
      _requireEncryption().ssss.open(identifier);

  /// Unlocks SSSS with a recovery key through the SDK's official decrypt
  /// path only, then returns the unlocked handle (contains the recovery key
  /// string surfaced by the SDK itself).
  Future<OpenSSSS> openSecretStorage(String recoveryKey) async {
    final handle = secretStorageHandle();
    await handle.unlock(recoveryKey: recoveryKey);
    return handle;
  }

  /// Requests an official key verification round for one of the cached
  /// device keys of [userId]. Requires `client.init()` to have loaded
  /// `userDeviceKeys`; the SDK handles the to-device protocol itself.
  Future<KeyVerification> startVerification({
    required String userId,
    required String deviceId,
  }) {
    final keys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    if (keys == null) {
      throw StateError(
        'device keys not cached for $userId / $deviceId '
        '(sync/init must have completed first)',
      );
    }
    return keys.startVerification();
  }

  /// Official device metadata listing (non-crypto Client API).
  Future<List<Device>?> devices() => client.getDevices();

  /// Official device logout/deletion (non-crypto Client API).
  Future<void> deleteDevice(String deviceId) => client.deleteDevice(deviceId);
}
