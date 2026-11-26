// Task 1.5 — Crypto integration surface (DOCUMENTATION ONLY)
//
// Status update (2026-10-31): the SDK-official forwarding layer is now
// implemented in `crypto_bridge.dart` (public matrix-dart-sdk 14.2.0 APIs
// only; SDK source untouched). What remains binding work for a human
// cryptography reviewer:
//   * instantiating screens with the bridge-backed hooks:
//       DeviceVerificationScreen(bootstrapAction: ..., verificationRequestAction: ...)
//       KeyBackupRecoveryScreen(onRecover: ...)
//       DeviceListingScreen(deviceSource: bridge.devices, onLogoutDevice: ...)
//   * driving the official Bootstrap state machine (state transitions are a
//     key-management decision and stay with the human reviewer);
//   * naming/scheduling policy for when Homing calls beginCrossSigning.
//
// AGENTS.md §五 still applies: the agent does not author crypto flow logic.
// Bridge methods are verbatim pass-throughs, which is the enforced boundary.
import 'package:matrix/matrix.dart';

/// Marker placeholder so integration points are machine-discoverable.
final class CryptoIntegrationSurface {
  final Client client;
  const CryptoIntegrationSurface(this.client);

  // Contract mapping (bridge in `crypto_bridge.dart`):
  // * bootstrapAction        -> CryptoBridge.beginCrossSigning (official Bootstrap)
  // * verificationRequestAction -> CryptoBridge.startVerification (DeviceKeys.startVerification)
  // * recoveryAction         -> CryptoBridge.openSecretStorage (ssss.open/unlock)
  // * deviceSource           -> CryptoBridge.devices (client.getDevices)
  // * onLogoutDevice         -> CryptoBridge.deleteDevice (client.deleteDevice)
  //
  // Screen instantiation + bootstrap state driving = human sign-off task.
  @override
  String toString() => 'CryptoIntegrationSurface{client: ${client.clientName}}';
}
