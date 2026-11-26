// P2.15 提案（人類指示 2026-11-01）— 一對一通話畫面（草案，待人類設計定稿）。
// UI 骨架：來電（接聽／掛斷）→ 通話中（遠端大畫面＋本機小畫面、控鈕：靜音／攝影機／掛斷）。
// 電話緞帶與樣式全由人類定稿；本檔不引入任何音檔／logo（AGENTS.md）。
// 通話行為全部呼叫 SDK 官方 `CallSession` 方法；不寫任何加密／金鑰程式碼。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pip/pip.dart' show PipState;
import 'package:matrix/matrix.dart';

import '../pip_helper.dart';
import '../bluetooth_permission.dart'; // 第十八批：BLUETOOTH_CONNECT 權限
import '../call_log.dart';
import '../voip/call_manager.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import 'call_recording_badge.dart';
import 'call_captions_overlay.dart';
import 'stt_model_prefs.dart'; // 第九十二批：字幕偏好 // 第九十二批：通話字幕 PoC // 第八十批：錄製狀態 UI
import '../call_recording_status.dart'; // 第八十批：錄製中狀態

/// 全螢幕通話畫面。`session` 由 CallManager 建立後注入。
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.session, required this.manager});

  final CallSession session;
  final CallManager manager;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  CallSession get session => widget.session;

  RTCVideoRenderer? _remoteRenderer;
  // SDK 內部型別 WrappedMediaStream 未被 package:matrix 匯出（不可命名），
  // 僅保存參照以判斷「同一 stream 不重綁」。屬 SDK 官方物件之參考。
  Object? _remoteStreamRef;
  RTCVideoRenderer? _localRenderer;
  Object? _localStreamRef;
  CallState _state = CallState.kFledgling;
  bool _micMuted = false;
  // Suggestion #6「支援通話放音裝置調整（參考 Discord）」：揚聲器開關草案——
  // 預設送話器（earpiece）＝Webrtc 官方預設；切換走 flutter_webrtc 官方
  // `Helper.setSpeakerphoneOn`（media_stream_track_impl.dart L83 官方取代
  // 已棄用的 enableSpeakerphone）。
  bool _speakerOn = false;

  /// 批次十三①：外部音訊輸出裝置選擇（官方 `MediaDevices` →
  /// `navigator.mediaDevices.enumerateDevices()` 過濾 kind=audiooutput，
  /// 除去內建 speaker/earpiece 兩類即藍牙／有線等外部裝置；零新依賴）。
  /// **已知限制（披露）**：deviceId 為套件 `AudioDeviceKind` 種類名
  ///（bluetooth／wired-headset…，原生 AudioDeviceKind.java L8-12），
  /// 非特定耳機 unique id → 兩支藍牙耳機清單同名，選擇＝「切到這一類」。
  String? _externalAudioDevice;
  DateTime? _callStartedAt;
  bool _connected = false;
  bool _rejected = false;
  bool _callLogged = false;
  bool _videoMuted = false;
  bool _controlsVisible = true; // 批次 II⑦：控制列可收合（人類拍板「只收合控制列」）。
  bool _togglingMic = false; // 批次 II⑥：避免重複點擊 race。
  bool _togglingCam = false;
  bool _wasInPip = false;
  bool _pipActive = false;
  StreamSubscription<CallState>? _stateSub;
  StreamSubscription<MediaStream>? _localStreamChangedSub;
  // ②-B 修：遠端流變更事件（kFeedsChanged）訂閱 → 重查重綁遠端 renderer。
  StreamSubscription<CallStateChange>? _callEventSub;
  // 第二十八批（臨時診斷列，下一批除役——如批次十九模式）：官方
  // `getIceServers()` 數量；initState 取一次即可（TURN 憑證快取）。
  Future<int>? _iceCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 批次 II-h：PiP 狀態回呼。
    unawaited(PipHelper.registerObserver((state) {
      if (!mounted) return;
      if (state == PipState.pipStateStarted) {
        setState(() {
          _wasInPip = true;
          _pipActive = true; // 批次 II-j：統一與 group 相同（原為 false）。
          _controlsVisible = false;
        });
      } else if (state == PipState.pipStateStopped) {
        setState(() {
          _wasInPip = false;
          _pipActive = false;
          _controlsVisible = true;
        });
      }
    }));
    _state = session.state;
    _callStartedAt = DateTime.now();
    _iceCount = widget.manager.diagnosticIceServerCount(); // 二十八批臨診
    _micMuted = session.isMicrophoneMuted;
    _videoMuted = session.isLocalVideoMuted;
    _stateSub = session.onCallStateChanged.stream.listen((s) {
      if (!mounted) {
        return;
      }
      setState(() {
        _state = s;
        // 批次 II⑥：狀態變化時同步 SDK 真值，避免本地旗標與實際 track 脫鉤。
        _micMuted = session.isMicrophoneMuted;
        _videoMuted = session.isLocalVideoMuted;
        if (s == CallState.kConnected) _connected = true;
      });
      if (s == CallState.kConnected || s == CallState.kConnecting) {
        unawaited(_attachStreams());
        // 批次 II-h：通話接通後啟動前景服務，避免最小化被回收。
        unawaited(_startCallForegroundService());
      }
      if (s == CallState.kEnded) {
        unawaited(_stopCallForegroundService());

        // 批次 II-c：清除 SDK 狀態（避免「前一次通話的身份還留在通話中」）。
        unawaited(Future<void>.microtask(() {
          try {
            widget.manager.clearCall(session);
          } catch (_) {}
        }));
        // 批次 II-d：寫入通話紀錄（草案）。
        unawaited(_logCall(_rejected
            ? 'rejected'
            : (_connected ? 'completed' : 'missed')));
        // 保留一瞬間讓人看到「已結束」，然後可靠地關閉路由。
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) {
            nav.pop();
          }
        });
      }
    });
    unawaited(_attachStreams());
    // 批次 II-f/j：相機關閉後重新開啟時 SDK 會 onStreamChanged（新增視訊 track），
    // 需重新綁定渲染器，否則畫面卡在轉圈/舊串流。註冊改為 helper（II-j）：
    // 若進入畫面當下尚無 local stream（如來電未接聽），_attachStreams 時補註冊。
    _registerLocalStreamListener();
    // ②-B 修（人類實測 2026-11-07「靜音時對端看到攝影機關掉」）：遠端流原本
    // 只在 kConnected/kConnecting 綁一次，之後完全不響應遠端流變更——SDK 收到
    // `m.call.sdp_stream_metadata`（對端靜音等）會 fire kFeedsChanged
    //（call_session.dart onSDPStreamMetadataReceived → fireCallEvent），遠端流
    // 被標記變動／停止後 renderer 不重綁、畫面即失效。訂閱官方
    // `onCallEventChanged`（call_session.dart L109）於 kFeedsChanged 重查重綁；
    // `_attachStreams` 內 identical guard（L257）＝同一 stream 物件不重初始化，
    // 僅於換綁時觸發，不重轟。
    _callEventSub = session.onCallEventChanged.stream.listen((e) {
      if (!mounted) {
        return;
      }
      if (e == CallStateChange.kFeedsChanged) {
        unawaited(_attachStreams());
      }
    });
  }

  // 批次 II-j：local stream 可能晚於 initState 產生（來電接聽流程），
  // 因此在 _attachStreams 也嘗試補註冊（每個 State 只註冊一次）。
  void _registerLocalStreamListener() {
    final local = session.localUserMediaStream;
    if (local == null || _localStreamChangedSub != null) return;
    _localStreamChangedSub = local.onStreamChanged.stream.listen((stream) {
      if (!mounted) return;
      unawaited(_rebindLocalRenderer(stream, local));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_wasInPip && !_pipActive) {
      // 批次 II-h：最小化時自動進入 PiP。
      unawaited(_autoEnterPip());
    }
    if (state == AppLifecycleState.resumed && _pipActive) {
      // 批次 II-j：與 group 相同——從 PiP 擴大回全螢幕時恢復控制列
      //（若 PiP 觀察者未及時觸發，此處為兜底）。
      if (mounted) setState(() { _pipActive = false; _controlsVisible = true; });
    }
  }

  Future<void> _autoEnterPip() async {
    final ok = await PipHelper.enter();
    if (ok && mounted) {
      setState(() {
        _wasInPip = true;
        _pipActive = true;
        _controlsVisible = false;
      });
    }
  }

  Future<void> _startCallForegroundService() async {
    try {
      await const MethodChannel('homing/call_service').invokeMethod('start');
    } catch (_) {}
  }

  Future<void> _stopCallForegroundService() async {
    try {
      await const MethodChannel('homing/call_service').invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> _logCall(String outcome) async {
    if (_callLogged) return;
    _callLogged = true;
    final started = _callStartedAt ?? DateTime.now();
    final duration = DateTime.now().difference(started).inMilliseconds;
    final direction =
        session.direction == CallDirection.kIncoming ? 'incoming' : 'outgoing';
    final peerId = session.remoteUserId ?? session.room.id;
    final peerName = session.room.name.isNotEmpty ? session.room.name : peerId;
    await CallLog.add(
      direction: direction,
      peerId: peerId,
      peerName: peerName,
      roomId: session.room.id,
      isGroup: false,
      startedAt: started,
      durationMs: duration < 0 ? 0 : duration,
      outcome: outcome,
    );
  }

  Future<void> _rebindLocalRenderer(MediaStream stream, WrappedMediaStream local) async {
    await _localRenderer?.dispose();
    final renderer = RTCVideoRenderer();
    try {
      await renderer.initialize();
    } catch (_) {
      await renderer.dispose();
      return;
    }
    renderer.srcObject = stream;
    if (!mounted) {
      await renderer.dispose();
      return;
    }
    setState(() {
      _localStreamRef = local;
      _localRenderer = renderer;
    });
  }

  @override
  void dispose() {
    // 批次 II-e：使用者按返回離開畫面時**不**掛斷（通話繼續、退到聊天室），
    // 因此 dispose 不清除 SDK 狀態；僅在 kEnded／_hangup 時清除。
    // 批次 II-j：
    //   1) 補 removeObserver（原 II-h 替換靜默未命中 → 死亡 State 會在別的
    //      畫面最小化時觸發 auto-PiP）＋ unregisterObserver。
    //   2) 不再於 dispose 寫通話紀錄（原寫法會在「返回後通話繼續」時
    //      誤寫一筆 completed/failed；改僅於 kEnded／_hangup 寫入）。
    WidgetsBinding.instance.removeObserver(this);
    unawaited(PipHelper.unregisterObserver());

    _stateSub?.cancel();
    _localStreamChangedSub?.cancel();
    _callEventSub?.cancel(); // ②-B 修：遠端流變更訂閱
    _remoteRenderer?.dispose();
    _localRenderer?.dispose();
    _remoteStreamRef = null;
    _localStreamRef = null;
    super.dispose();
  }

  /// 將 SDK 官方 WrappedMediaStream 綁到 flutter_webrtc 渲染器：
  /// 遠端大畫面（優先 usermedia）＋本機小畫面。不寫任何取流／加密邏輯。
  Future<void> _attachStreams() async {
    final remote = session.getRemoteStreams
        .where((s) => s.purpose == 'm.usermedia' && s.stream != null)
        .toList();
    final local = session.localUserMediaStream;
    // 批次 II-j：local stream 晚到時補註冊 onStreamChanged（避免重開轉圈問題復發）。
    _registerLocalStreamListener();

    if (remote.isNotEmpty) {
      final stream = remote.first;
      if (!identical(_remoteStreamRef, stream) || _remoteRenderer == null) {
        await _remoteRenderer?.dispose();
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = stream.stream;
        if (mounted) {
          setState(() {
            _remoteStreamRef = stream;
            _remoteRenderer = renderer;
          });
        } else {
          await renderer.dispose();
        }
      }
    }
    if (local != null && local.stream != null) {
      if (!identical(_localStreamRef, local) || _localRenderer == null) {
        await _localRenderer?.dispose();
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = local.stream;
        // 鏡像交給 RTCVideoView（mirror 屬 View 參數；renderer 層不用設定）。
        if (mounted) {
          setState(() {
            _localStreamRef = local;
            _localRenderer = renderer;
          });
        } else {
          await renderer.dispose();
        }
      }
    }
  }

  bool get _isVideoCall =>
      session.getLocalStreams.any((s) => s.purpose == 'm.usermedia') ||
      session.localUserMediaStream != null;

  Future<void> _toggleMic() async {
    if (_togglingMic || _state == CallState.kEnded) return;
    _togglingMic = true;
    final target = !_micMuted;
    // 批次 II-c：UI 先行反應（避免「嚴重延遲」），失敗回滾。
    if (mounted) setState(() => _micMuted = target);
    try {
      await session.setMicrophoneMuted(target);
      // ②-B 修（人類實測 2026-11-07）：移除批次 II⑥ 的手動 track.enabled 翻轉
      // ——SDK `setMicrophoneMuted`（call_session.dart L826-829）已做
      // `setAudioMuted` ＋ `updateMuteStatus()`（L1235-1256）：統一翻轉
      // track 吋 enabled 並送 `m.call.sdp_stream_metadata`。原註解「SDK 僅設
      // 旗標」為誤判；自行再翻同值冪等但屬多餘 desync 面。
      if (mounted) {
        setState(() => _micMuted = session.isMicrophoneMuted);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _micMuted = session.isMicrophoneMuted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('切換麥克風失敗：')}$e')),
        );
      }
    } finally {
      _togglingMic = false;
    }
  }

  Future<void> _toggleCamera() async {
    if (_togglingCam || _state == CallState.kEnded) return;
    _togglingCam = true;
    final target = !_videoMuted;
    // 批次 II-c：UI 先行反應。
    if (mounted) setState(() => _videoMuted = target);
    try {
      await session.setLocalVideoMuted(target);
      // ②-B 修：同 `_toggleMic`——SDK `setLocalVideoMuted`（call_session.dart
      // L749-754）已翻旗標＋`updateMuteStatus()`（track.enabled＋metadata）；
      // 移除批次 II⑥ 的手動 video track 翻轉。
      if (mounted) {
        setState(() => _videoMuted = session.isLocalVideoMuted);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _videoMuted = session.isLocalVideoMuted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('切換攝影機失敗：')}$e')),
        );
      }
    } finally {
      _togglingCam = false;
    }
  }

  /// 批次 III-b（人類回報「通話時無法切換鏡頭」）：
  /// flutter_webrtc 官方 `Helper.switchCamera` 前後鏡頭切換（本地 track）。
  Future<void> _switchCamera() async {
    try {
      final local = session.localUserMediaStream?.stream;
      for (final t in local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
        await Helper.switchCamera(t);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('無法切換鏡頭：')}$e')), // 文案草案
        );
      }
    }
  }

  Future<void> _hangup() async {
    try {
      await session.hangup(reason: CallErrorCode.userHangup);
      unawaited(_logCall(_connected ? 'completed' : 'failed'));
      widget.manager.clearCall(session);
      unawaited(_stopCallForegroundService());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('掛斷失敗：')}$e')),
        );
      }
    }
  }

  Future<void> _enterPip() async {
    final ok = await PipHelper.enter();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('此裝置不支援 PiP'))), // 文案草案
      );
    }
  }

  Future<void> _answer() async {
    await session.answer();
    // Suggestion #6：接聽後套用揚聲器偏好（官方 Helper；失敗不影響通話）。
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
  }

  /// 批次十一次：「支援通話放音裝置調整」改 **Discord 式輸出選單**（人類
  /// 指示「請依照 Discord 設計修改」＋參考圖 dc/1793614407662.jpg：底部
  /// sheet「選擇音訊輸出」＋分組「這個電話」＝電話（聽筒）／喇叭，radio
  /// 顯示當前選擇）。骨架為最小樣式（主題色；文案草案，待人類定稿）；
  /// 切換走同一官方 `Helper.setSpeakerphoneOn`。DC 分組內另列藍牙／耳機
  /// ——官方 Helper 無裝置清單來源，現階段僅兩項（披露）。
  Future<void> _showAudioOutputSheet() async {
    final deviceNote = '本機'; // 文案草案（無 device_info 依賴，不報型號）
    // 第十八批②-A 根因修（人類實測 APK 2018，2026-11-07）：Android 12+ 藍牙
    // 列舉需 BLUETOOTH_CONNECT——manifest 原缺此權限，AudioSwitch 掃描永不含
    // 藍牙、重試無效（sheet 只剩內建兩項）。開 sheet 先請求（已授權→不彈框；
    // 拒絕→僅內建＋提示文案），拿到結果再枚舉。
    await requestBluetoothPermission();
    // 第十三批①：外部輸出裝置清單（失敗／未連接 → 空清單，維持原內建兩項）。
    final externalDevices = await _externalAudioOutputs();
    if (!mounted) {
      return;
    }
    final result = await showModalBottomSheet<Object?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // DC 範本格式：頂部把手。
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Text(S.t('選擇音訊輸出'), style: Theme.of(sheetContext).textTheme.titleMedium), // 文案草案
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(S.t('這個電話'), // 文案草案（DC 分組名）
                  style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            _audioOutputRow(
              sheetContext,
              title: S.t('電話'), // 文案草案
              subtitle: deviceNote,
              icon: AllIcons.smartphone,
              // 第十三批①：選到外部裝置時，內建兩項不打點。
              selected: _externalAudioDevice == null && !_speakerOn,
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            _audioOutputRow(
              sheetContext,
              title: S.t('喇叭'), // 文案草案
              subtitle: deviceNote,
              icon: AllIcons.volumeUp,
              selected: _externalAudioDevice == null && _speakerOn,
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            // 第十八批：沒有外部裝置時顯示說明（原樣貌靜默——人類實測 2026-11-07
            // 只見內建兩項、無任何解釋）。骨架樣式／草案文案，待人類定稿。
            if (externalDevices.isEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(S.t('目前沒有偵測到外部放音裝置'), // 文案草案
                    style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
            // 第十三批①：外部裝置分組（Discord 同款分組；人類批准 2026-11-07）。
            if (externalDevices.isNotEmpty) ...[
              const SizedBox(height: 4),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Theme.of(sheetContext).colorScheme.outlineVariant,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(S.t('外部裝置'), // 文案草案（DC 分組名）
                    style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              for (final d in externalDevices)
                _audioOutputRow(
                  sheetContext,
                  title: _externalAudioTitle(d.kind, d.label),
                  subtitle: d.label,
                  icon: d.kind == 'bluetooth' ? AllIcons.headset : AllIcons.headphones,
                  selected: _externalAudioDevice == d.kind,
                  onTap: () => Navigator.pop(sheetContext, d.kind),
                ),
            ],
            // 第十九批臨時診斷除錯列已於第二十批移除（根因定案：
            // fork AudioSwitch 清單維護問題 → 自建溝通裝置枚舉＋選擇）。
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    // 依 sheet 選擇套用（官方 Helper；null＝關閉未選，不套用）。
    // bool＝內建（電話／喇叭）；String＝外部裝置 kind（第十三批①）。
    if (result is bool) {
      await _setSpeaker(result);
    } else if (result is String && result.isNotEmpty) {
      await _applyExternalAudio(result);
    }
  }

  /// 批次十三①：單次枚舉外部輸出裝置（去重 kind／label；官方
  /// `navigator.mediaDevices.enumerateDevices()` → 內部走 getSources）。
  /// 失敗（引擎未初始化／非 Android）→ 空。
  Future<List<({String kind, String label})>>
      _enumerateAudioOutputsOnce() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final out = <({String kind, String label})>[];
      final seen = <String>{};
      for (final d in devices) {
        final kind = d.deviceId;
        if (d.kind != 'audiooutput' ||
            kind.isEmpty ||
            kind == 'speaker' ||
            kind == 'earpiece' ||
            !seen.add(kind)) {
          continue;
        }
        out.add((kind: kind, label: d.label.isEmpty ? kind : d.label));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// ②-A（第二十批定案）：Android 12+ 改走自建溝通裝置枚舉（官方
  /// `AudioManager.getAvailableCommunicationDevices()`；進程內診斷證實
  /// fork AudioSwitch 清單與系統脫節——comm 候選有筆電耳機、AudioSwitch
  /// 列舉永缺），同步即時讀取、無 fork 非同步就緒問題，不重試。Android 11
  /// 以下（或通道不可用 → null）維持 1.6.3 舊路徑＋重試（批次十七）。
  /// 內建 earpiece／speaker 由「這個電話」分組處理，外部分組只列非內建。
  Future<List<({String kind, String label})>> _externalAudioOutputs() async {
    final own = await enumerateCommunicationDevices();
    if (own != null) {
      final out = <({String kind, String label})>[];
      final seen = <String>{};
      for (final d in own) {
        if (d.id == 'builtin_earpiece' ||
            d.id == 'builtin_speaker' ||
            d.id == 'builtin_speaker_safe' ||
            !seen.add(d.id)) {
          continue;
        }
        out.add((kind: d.id, label: d.name.isEmpty ? d.id : d.name));
      }
      return out;
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final out = await _enumerateAudioOutputsOnce();
      if (out.isNotEmpty) {
        return out;
      }
      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    return const [];
  }

  /// 批次十三①：外部裝置列顯示標籤（種類名 → 中文草案；未知 fallback 原始
  /// label）。第二十批：kind 命名併入官方型別名（Android 12+ 自建枚舉）。
  String _externalAudioTitle(String kind, String label) {
    switch (kind) {
      case 'bluetooth':
      case 'bluetooth_sco':
      case 'bluetooth_a2dp':
      case 'ble_headset':
      case 'ble_speaker':
        return '藍牙耳機'; // 文案草案
      case 'wired-headset':
      case 'wired_headset':
      case 'wired_headphones':
      case 'usb_headset':
        return '有線耳機'; // 文案草案
      default:
        return label;
    }
  }

  /// 批次十三①：套用外部輸出裝置。第二十批：Android 12+ 首選官方
  /// `AudioManager.setCommunicationDevice`（原生套用後回讀溝通裝置型別
  /// 二次驗證）；false＝裝置斷線／系統拒絕／驗證失敗 → 提示＋回退、且
  /// 不再走 1.6.3 Helper（兩套 kind 命名不同，不可混用）。通道不支援
  /// （非 Android／<S → null）→ 維持 1.6.3 舊路徑＋批次十七二次驗證。
  /// 披露（同前）：種類級選擇；fork 選擇路徑的 no-op gate 未解
  /// （選擇有 verification 把關，known_problems 已列）。
  Future<void> _applyExternalAudio(String kind) async {
    final previous = _externalAudioDevice;
    final verified = await setCommunicationDevice(kind);
    if (verified != null) {
      setState(() => _externalAudioDevice = verified ? kind : previous);
      if (mounted && !verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.t('切換放音裝置失敗：裝置可能已斷線')), // 文案草案
          ),
        );
      }
      return;
    }
    setState(() => _externalAudioDevice = kind);
    try {
      await Helper.selectAudioOutput(kind);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('切換放音裝置失敗：')}$e')), // 文案草案
        );
        setState(() => _externalAudioDevice = previous);
      }
      return;
    }
    // ②-A：選後驗證（單次枚舉；裝置斷線→清單空/不含該 kind → 提示＋回退）。
    final still = await _enumerateAudioOutputsOnce();
    if (mounted && !still.any((d) => d.kind == kind)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('找不到所選放音裝置，可能已斷線'))), // 文案草案
      );
      setState(() => _externalAudioDevice = previous);
    }
  }

  /// 批次十一次：sheet 內一列（骨架；radio 顯示當前選擇）。
  Widget _audioOutputRow(
    BuildContext sheetContext, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: selected
          ? Icon(
              AllIcons.circle,
              size: 20,
              color: Theme.of(sheetContext).colorScheme.primary,
            )
          : Icon(
              AllIcons.circleOutlined,
              size: 20,
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }

  /// 批次十一次：依 sheet 選擇套用放音裝置。第二十批：Android 12+ 一律先走
  /// 官方 `setCommunicationDevice`（同 sheet 外部選擇同一機制——避免 fork
  /// speakerphone 旗標與系統溝通裝置兩套路由互打架）；<S／系統拒絕／該內建
  /// 裝置不在溝通清單（false）／通道異常（null）→ 回退 1.6.3 Helper＋失敗回退 UI。
  Future<void> _setSpeaker(bool target) async {
    final builtinId = target ? 'builtin_speaker' : 'builtin_earpiece';
    final verified = await setCommunicationDevice(builtinId);
    if (verified == true) {
      // 第十三批①：回內建裝置＝同時清除外部選擇（radio 顯示回到內建群）。
      setState(() {
        _speakerOn = target; // UI 先行反應。
        _externalAudioDevice = null;
      });
      return;
    }
    setState(() {
      _speakerOn = target;
      _externalAudioDevice = null;
    });
    try {
      await Helper.setSpeakerphoneOn(target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('切換放音裝置失敗：')}$e')), // 文案草案
        );
        setState(() => _speakerOn = !target);
      }
    }
  }

  Future<void> _reject() async {
    _rejected = true;
    await session.reject();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingRinging =
        _state == CallState.kRinging && session.direction == CallDirection.kIncoming;
    final ended = _state == CallState.kEnded;
    final remoteTitle = session.remoteUserId ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 頂部：對方 ID 與狀態（文案草案）。
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          remoteTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      CallRecordingBadge(room: session.room),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    callStateLabel(_state),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // 第二十八批（臨時診斷列，下一批除役——如批次十九模式）：
            // ICE 清單數量（官方 getIceServers；=0 或 -1 見披露）＋最近一次
            // 通話終態記錄。供「連不上／glare」回報判讀；樣式草案。
            FutureBuilder<int>(
              future: _iceCount,
              builder: (context, snap) => Text(
                '二十八診斷: ICE=${snap.data ?? "…"}（0/負值=沒有中繼伺服器）'
                '${widget.manager.diagnosticLastCallEnd == null ? "" : " · 上通${widget.manager.diagnosticLastCallEnd}"}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ),
            // 媒體區：連線以後視訊（遠端大畫面＋本機小畫面）；音訊占位為頭像圓。
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                child: Semantics(
                  label: S.t('通話畫面（點按顯示或隱藏控制列）'),
                  child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_remoteRenderer != null)
                    RTCVideoView(_remoteRenderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  else
                    Icon(
                      _isVideoCall ? AllIcons.videocamOutlined : AllIcons.phone,
                      size: 64,
                      color: Colors.white70,
                    ),
                  if (_localRenderer != null && _isVideoCall && !ended)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 96,
                          height: 128,
                          child: RTCVideoView(_localRenderer!, mirror: true),
                        ),
                      ),
                    ),
                  // 批次 II⑦：控制列收合切換（人類拍板「只收合控制列」）。
                  // 點此鈕：控制列消失／跳出；不需最小化 App 即可切換可見性。
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _roundButton(
                      tooltip: _controlsVisible ? '收合控制列' : '顯示控制列',
                      icon: _controlsVisible
                          ? AllIcons.visibilityOff
                          : AllIcons.visibility,
                      onPressed: () =>
                          setState(() => _controlsVisible = !_controlsVisible),
                    ),
                  ),
                ],
              ),
              ),
            ),
            ),
            // 第九十二批 PoC：通話即時字幕（受無障礙偏好控制）。
            ValueListenableBuilder<bool>(
              valueListenable: ringCallCaptions,
              builder: (context, enabled, _) => enabled
                  ? const CallCaptionsOverlay(text: '', active: true)
                  : const SizedBox.shrink(),
            ),
            // 控制列（草案）：來電 __ 接聽／掛斷；進行中 __ 麥克風／攝影機／結束。
            // 批次 II⑦：收合時隱藏；收合狀態下僅保留右下角的「恢復」鈕（避免
            // 使用者找不到控制項）。
            if (_controlsVisible)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: isIncomingRinging
                      ? [
                          _roundButton(
                            tooltip: S.t('掛斷（拒接）'),
                            icon: AllIcons.callEnd,
                            color: Colors.red,
                            onPressed: _reject,
                          ),
                          _roundButton(
                            tooltip: S.t('接聽'),
                            icon: AllIcons.call,
                            color: Colors.green,
                            onPressed: _answer,
                          ),
                        ]
                      : [
                          _roundButton(
                            tooltip: _micMuted ? '取消靜音' : '靜音',
                            icon: _micMuted ? AllIcons.micOff : AllIcons.mic,
                            onPressed: ended ? null : _toggleMic,
                          ),
                          if (_isVideoCall)
                            _roundButton(
                              tooltip: _videoMuted ? '開啟攝影機' : '關閉攝影機',
                              icon: _videoMuted
                                  ? AllIcons.videocamOff
                                  : AllIcons.videocam,
                              onPressed: ended ? null : _toggleCamera,
                            ),
                          // 批次 III-b：前後鏡頭切換（人類指示）。僅視訊通話顯示。
                          if (_isVideoCall && !ended)
                            _roundButton(
                              tooltip: S.t('切換鏡頭'), // 文案草案
                              icon: AllIcons.cameraswitchOutlined,
                              onPressed: _switchCamera,
                            ),
                          // Suggestion #6＋批次十一次：放音裝置調整 → Discord 式輸出選單。
                          _roundButton(
                            tooltip: S.t('選擇音訊輸出'), // 文案草案
                            icon: _speakerOn ? AllIcons.volumeUp : AllIcons.phoneInTalk,
                            onPressed: ended ? null : _showAudioOutputSheet,
                          ),
                          // 第八十批：錄製中狀態（只顯示狀態；實際錄音未提供）。
                          _roundButton(
                            tooltip: S.t('錄製狀態'),
                            icon: ringLocalCallRecording.value
                                ? AllIcons.radioButtonChecked
                                : AllIcons.radioButtonOff,
                            color: ringLocalCallRecording.value ? Colors.red : null,
                            onPressed: ended
                                ? null
                                : () {
                                    unawaited(showCallRecordingSheet(
                                      context,
                                      room: session.room,
                                    ));
                                  },
                          ),
                          _roundButton(
                            tooltip: S.t('子母畫面 (PiP)'),
                            icon: AllIcons.pictureInPictureAlt,
                            onPressed: ended ? null : _enterPip,
                          ),
                          _roundButton(
                            tooltip: S.t('結束通話'),
                            icon: AllIcons.callEnd,
                            color: Colors.red,
                            onPressed: ended ? null : _hangup,
                          ),
                        ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _roundButton(
                      tooltip: S.t('顯示控制列'),
                      icon: AllIcons.visibility,
                      onPressed: () =>
                          setState(() => _controlsVisible = true),
                    ),
                    if (!ended && !isIncomingRinging)
                      _roundButton(
                        tooltip: S.t('結束通話'),
                        icon: AllIcons.callEnd,
                        color: Colors.red,
                        onPressed: _hangup,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    // 文案／視覺待人類定稿；目前為 Material 3 最小樣式。
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: onPressed == null
            ? null
            : (color != null ? Colors.white : null),
      ),
      icon: Icon(icon),
    );
  }
}
