// P2.15c（人類指示 2026-11-01）— Picture-in-Picture（PiP）輔助。
// Android：啟用 manifest supportsPictureInPicture 後，呼叫 Pip().start() 進入 PiP。
// iOS：pip 套件使用 AVKit；WebRTC RTCVideoView 整合有限，目前僅 Android 可用。
// 草案，待人類設計定稿。
import 'package:pip/pip.dart';

class PipHelper {
  PipHelper._();
  static final Pip _pip = Pip();

  /// 是否支援 PiP（目前主要 Android）。
  static Future<bool> isSupported() async {
    try {
      return await _pip.isSupported();
    } catch (_) {
      return false;
    }
  }

  /// 註冊 PiP 狀態變化回呼（進入/離開 PiP）。
  static Future<void> registerObserver(void Function(PipState state) cb) async {
    try {
      await _pip.registerStateChangedObserver(
        PipStateChangedObserver(onPipStateChanged: (state, _) => cb(state)),
      );
    } catch (_) {}
  }

  static Future<void> unregisterObserver() async {
    try {
      await _pip.unregisterStateChangedObserver();
    } catch (_) {}
  }

  /// 進入 PiP 模式。失敗回 false，不拋例外。
  static Future<bool> enter() async {
    try {
      final supported = await _pip.isSupported();
      if (!supported) {
        return false;
      }
      await _pip.setup(const PipOptions(
        aspectRatioX: 16,
        aspectRatioY: 9,
        autoEnterEnabled: false,
      ));
      return await _pip.start();
    } catch (_) {
      return false;
    }
  }
}
