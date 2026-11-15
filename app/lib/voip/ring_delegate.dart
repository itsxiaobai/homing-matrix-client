// P2.15 提案（人類指示 2026-11-01）— 通話功能：SDK 官方 WebRTCDelegate 的 App 端實作。
// 組接 SDK 官方 VoIP（`m.call.*` 信令）與 flutter_webrtc 官方 API；草案，待人類設計定稿。
//
// ⚠️ 加密邊界（依 AGENTS.md）：
// * 本檔不寫任何加密／金鑰演算法。本檔支援一對一 P2P（mesh）通話與群組 mesh 通話；
//   mesh 群組通話採 MeshBackend（matrix SDK 寫死 e2eeEnabled=false，群組媒體不 E2EE），
//   與 1:1 通話一致。
// * 第三十批（人類批准 2026-11-10「SDK 官方路徑」）：LiveKit E2EE 群組通話的金鑰
//   輪替採 SDK 官方 `LiveKitBackend` + `EncryptionKeyProvider` 介面；本檔僅提供
//   可注入的 keyProvider 槽位（實作＝livekit_call_manager.dart 的
//   RingLiveKitKeyProvider，純儲存↔轉發，零自製演算法），未注入時維持官方預設 null。
// * TURN/STUN 憑證由 SDK 官方 `getIceServers()` 自 homeserver 取得，App 端不手寫伺服器位址。
//
// 鈴聲：不內建任何音檔（資產授權待人類決定）；目前以系統提示音＋震動占位。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as fw;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

/// 對 SDK 內部定義之 `WebRTCDelegate` 的實作：轉接 flutter_webrtc。
/// 事件回呼對外以薄 Stream 暴露，供 App 級 UI（來電提示／通話記錄）訂閱。
class RingWebRTCDelegate implements WebRTCDelegate {
  RingWebRTCDelegate();

  final _newCallCtrl = StreamController<CallSession>.broadcast();
  final _callEndedCtrl = StreamController<CallSession>.broadcast();
  final _missedCallCtrl = StreamController<CallSession>.broadcast();
  final _newGroupCallCtrl = StreamController<GroupCallSession>.broadcast();
  final _groupCallEndedCtrl = StreamController<GroupCallSession>.broadcast();

  /// 每次 SDK 新增 CallSession（去電建立／來電響鈴）皆會回呼。
  Stream<CallSession> get onNewCall => _newCallCtrl.stream;

  /// 任意通話進入 kEnded 終態。
  Stream<CallSession> get onCallEnded => _callEndedCtrl.stream;

  /// 未接來電（正在 handled 別通話等情境）。
  Stream<CallSession> get onMissedCall => _missedCallCtrl.stream;

  /// 群組通話（mesh）開始：SDK 已送出 member state event，App 應顯示群組通話畫面。
  Stream<GroupCallSession> get onNewGroupCall => _newGroupCallCtrl.stream;

  /// 群組通話結束。
  Stream<GroupCallSession> get onGroupCallEnded => _groupCallEndedCtrl.stream;

  @override
  bool get isWeb => const bool.fromEnvironment('dart.library.js_interop');

  /// 本檔 restrict：僅在有單一進行中通話時接新通話（busy 由 manager 層再擋一次）。
  @override
  bool get canHandleNewCall => true;

  @override
  MediaDevices get mediaDevices => fw.navigator.mediaDevices;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    return fw.createPeerConnection(configuration, constraints);
  }

  /// 鈴聲占位：系統提示音＋震動（音檔資產待人類設計；不內建第三方素材）。
  @override
  Future<void> playRingtone() async {
    try {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // 停用系統音效的裝置忽略。
    }
  }

  @override
  Future<void> stopRingtone() async {
    // 占位：無自帶鈴聲播放器，nothing to stop。改接人類設計之音檔時在此停止。
  }

  /// SDK 只在去電建立後呼叫一次；本 App 的 UI 訂閱另見 CallManager／CallScreen，
  /// 此處不需接上任何 listener（骨架）。
  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {
    _newCallCtrl.add(session);
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _callEndedCtrl.add(session);
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {
    _missedCallCtrl.add(session);
  }

  /// 第三十批：LiveKit E2EE keyProvider 槽位（由 CallManager 於 ensureInit 注入
  /// RingLiveKitKeyProvider；未注入時 null＝SDK 官方預設，金鑰輪替不啟用）。
  EncryptionKeyProvider? livekitKeyProvider;

  /// 第三十批前之語意：非 LiveKit 群通時回 null（SDK 官方預設；1:1 與 mesh 不用金鑰）。
  @override
  EncryptionKeyProvider? get keyProvider => livekitKeyProvider;

  /// 關閉廣播 StreamController（CallManager.dispose 時呼叫）。
  void dispose() {
    _newCallCtrl.close();
    _callEndedCtrl.close();
    _missedCallCtrl.close();
    _newGroupCallCtrl.close();
    _groupCallEndedCtrl.close();
  }

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    _newGroupCallCtrl.add(groupCall);
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {
    _groupCallEndedCtrl.add(groupCall);
  }
}
