// P2.15b（人類指示 2026-11-01）— 群組通話畫面（mesh，草案，待人類設計定稿）。
// 7 項功能：音量表（說話人高亮）、視訊關閉顯示頭像、參與者名稱、動態排版、螢幕分享、PiP 隱藏按鈕、參與者列表。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart';
import 'package:pip/pip.dart' show PipState;

import '../pip_helper.dart';
import '../bluetooth_permission.dart'; // 第十八批：BLUETOOTH_CONNECT 權限
import '../call_log.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../voip/call_manager.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key, required this.groupCall, required this.manager});

  final GroupCallSession groupCall;
  final CallManager manager;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> with WidgetsBindingObserver {
  GroupCallSession get gc => widget.groupCall;
  MeshBackend get backend => gc.backend as MeshBackend;

  final List<WrappedMediaStream> _remoteStreams = [];
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  RTCVideoRenderer? _localRenderer;
  WrappedMediaStream? _localStreamRef;
  RTCVideoRenderer? _screenRenderer;
  StreamSubscription<MediaStream>? _localStreamChangedSub;

  bool _micMuted = false;
  bool _videoMuted = false;
  // 批次十：「支援通話放音裝置調整」（人類回饋「沒有專門控制的按鈕」根因＝
  // 按鈕只在 1:1 call_screen，群組通話控制列漏掉）。與 call_screen 同款：
  // 官方 flutter_webrtc `Helper.setSpeakerphoneOn`（media_stream_track_impl
  // .dart L83 官方正路）；預設送話器（earpiece）＝Webrtc 預設。
  bool _speakerOn = false;

  /// 批次十三①：外部音訊輸出裝置選擇（與 call_screen 同款；官方
  /// `navigator.mediaDevices.enumerateDevices()` 過濾 kind=audiooutput）。
  /// **已知限制（披露）**：deviceId 為套件 `AudioDeviceKind` 種類名
  ///（bluetooth／wired-headset…），非特定耳機 unique id → 選擇＝「切到這一類」。
  String? _externalAudioDevice;
  bool _screenSharing = false;
  bool _controlsVisible = true;
  DateTime? _callStartedAt;
  bool _callLogged = false;
  bool _pipActive = false;
  bool _wasInPip = false;
  GroupCallState _state = GroupCallState.localCallFeedUninitialized;
  CallParticipant? _activeSpeaker;

  StreamSubscription<WrappedMediaStream>? _addSub;
  StreamSubscription<WrappedMediaStream>? _removeSub;
  StreamSubscription<MatrixRTCCallEvent>? _stateSub;
  // 批次 II-j：stream 尚未就緒時的 onStreamChanged 訂閱（離開/移除時取消，避免累積）。
  final Map<String, StreamSubscription<MediaStream>> _pendingStreamSubs = {};
  Timer? _speakerTimer;

  @override
  void initState() {
    super.initState();
    _state = gc.state;
    _callStartedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // 批次 II-j（原 II-h 替換靜默未命中，此處補上）：PiP 狀態回呼。
    unawaited(PipHelper.registerObserver((state) {
      if (!mounted) return;
      if (state == PipState.pipStateStarted) {
        setState(() { _wasInPip = true; _pipActive = true; _controlsVisible = false; });
      } else if (state == PipState.pipStateStopped) {
        setState(() { _wasInPip = false; _pipActive = false; _controlsVisible = true; });
      }
    }));
    _micMuted = backend.localUserMediaStream?.isAudioMuted() ?? false;
    _videoMuted = backend.localUserMediaStream?.isVideoMuted() ?? false;
    _remoteStreams.addAll(backend.userMediaStreams.where((s) => !s.isLocal()));
    _remoteStreams.addAll(backend.screenShareStreams.where((s) => !s.isLocal()));
    _addSub = backend.onStreamAdd.stream.listen((s) {
      if (s.isLocal()) return; // 批次 II-e：本地串流不加入遠端列表（避免自己出現兩次）。
      if (mounted && !_remoteStreams.any((x) => x.id == s.id)) {
        setState(() => _remoteStreams.add(s));
      }
      unawaited(_ensureRenderer(s));
    });
    _removeSub = backend.onStreamRemoved.stream.listen((s) {
      if (mounted) {
        setState(() => _remoteStreams.removeWhere((x) => x.id == s.id));
        _remoteRenderers.remove(s.id)?.dispose();
      }
      // 批次 II-j：順手取消該串流的 pending 訂閱。
      _pendingStreamSubs.remove(s.id)?.cancel();
    });
    _stateSub = gc.matrixRTCEventStream.stream.listen((e) {
      if (e is GroupCallStateChanged && mounted) {
        setState(() => _state = e.state);
        if (e.state == GroupCallState.ended) {
          unawaited(_logGroupCall('completed'));
          // 批次 II-j：結束時關前景服務（dispose 不再因「返回時通話繼續」而關）。
          unawaited(_stopCallForegroundService());
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }
    });
    _speakerTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final sp = backend.activeSpeaker;
      if (sp != _activeSpeaker) {
        setState(() => _activeSpeaker = sp);
      }
    });
    unawaited(_attachLocal());
    // 批次 II-f/j：相機關閉後重新開啟時 SDK 會 onStreamChanged（新增視訊 track），
    // 需重新綁定渲染器，否則參與者畫面卡在轉圈。註冊改為 helper（II-j）：
    // 若進入畫面當下尚無 local stream（未加入前），_attachLocal 時補註冊。
    _registerLocalStreamListener();
    for (final s in _remoteStreams) {
      unawaited(_ensureRenderer(s));
    }
  }

  // 批次 II-j：local stream 可能晚於 initState 產生（尚未加入群組通話前），
  // 因此在 _attachLocal 也嘗試補註冊（每個 State 只註冊一次）。
  void _registerLocalStreamListener() {
    final localWrapped = backend.localUserMediaStream;
    if (localWrapped == null || _localStreamChangedSub != null) return;
    _localStreamChangedSub = localWrapped.onStreamChanged.stream.listen((stream) {
      if (!mounted) return;
      unawaited(_rebindLocalRenderer(stream, localWrapped));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_wasInPip && !_pipActive && _joined) {
      unawaited(_autoEnterPip());
    }
    if (state == AppLifecycleState.resumed && _pipActive) {
      // 退出 PiP 後恢復按鈕。
      if (mounted) setState(() { _pipActive = false; _controlsVisible = true; });
    }
  }

  Future<void> _autoEnterPip() async {
    final ok = await PipHelper.enter();
    if (ok && mounted) {
      setState(() { _wasInPip = true; _pipActive = true; _controlsVisible = false; });
      unawaited(_startCallForegroundService());
    }
  }

  Future<void> _startCallForegroundService() async {
    try { await const MethodChannel('homing/call_service').invokeMethod('start'); } catch (_) {}
  }

  Future<void> _stopCallForegroundService() async {
    try { await const MethodChannel('homing/call_service').invokeMethod('stop'); } catch (_) {}
  }

  @override
  void dispose() {
    // 批次 II-j（人類拍板）：群組通話「按返回」與一對一相同——通話繼續、
    // 可從聊天室再進入同一 session。因此 dispose **不再** clearGroupCall、
    // **不再**關前景服務、**不再**寫通話紀錄（僅 _leave／ended／kEnded 時處理）。
    WidgetsBinding.instance.removeObserver(this);
    unawaited(PipHelper.unregisterObserver());
    _addSub?.cancel();
    _removeSub?.cancel();
    _localStreamChangedSub?.cancel();
    _stateSub?.cancel();
    for (final sub in _pendingStreamSubs.values) {
      sub.cancel();
    }
    _pendingStreamSubs.clear();
    _speakerTimer?.cancel();
    WakelockPlus.disable();
    if (_screenSharing) {
      // 批次 II-b：確保前景服務關閉。
      try {
        const MethodChannel('homing/screen_capture').invokeMethod('stop');
      } catch (_) {}
    }
    _localRenderer?.dispose();
    _screenRenderer?.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _rebindLocalRenderer(MediaStream stream, WrappedMediaStream localWrapped) async {
    await _localRenderer?.dispose();
    final r = RTCVideoRenderer();
    try {
      await r.initialize();
    } catch (_) {
      await r.dispose();
      return;
    }
    r.srcObject = stream;
    if (!mounted) {
      await r.dispose();
      return;
    }
    setState(() {
      _localStreamRef = localWrapped;
      _localRenderer = r;
    });
  }

  Future<void> _attachLocal() async {
    final local = backend.localUserMediaStream;
    if (local == null || local.stream == null) return;
    // 批次 II-j：local stream 晚到時補註冊 onStreamChanged（避免重開轉圈問題復發）。
    _registerLocalStreamListener();
    if (identical(_localStreamRef, local)) return;
    await _localRenderer?.dispose();
    final r = RTCVideoRenderer();
    await r.initialize();
    r.srcObject = local.stream;
    if (mounted) {
      setState(() {
        _localStreamRef = local;
        _localRenderer = r;
      });
    } else {
      await r.dispose();
    }
  }

  Future<void> _ensureRenderer(WrappedMediaStream s) async {
    if (_remoteRenderers.containsKey(s.id)) return;
    if (s.stream == null) {
      // 批次 II-g/j：串流尚未就緒時監聽 onStreamChanged 重試，避免永久轉圈。
      // II-j：訂閱存入 _pendingStreamSubs（同一 stream 只掛一次，離開時取消）。
      if (_pendingStreamSubs.containsKey(s.id)) return;
      _pendingStreamSubs[s.id] = s.onStreamChanged.stream.listen((stream) {
        _pendingStreamSubs.remove(s.id)?.cancel();
        if (mounted) {
          unawaited(_ensureRenderer(s));
        }
      });
      return;
    }
    final r = RTCVideoRenderer();
    try {
      await r.initialize();
    } catch (_) {
      await r.dispose();
      return;
    }
    r.srcObject = s.stream;
    if (mounted) {
      setState(() => _remoteRenderers[s.id] = r);
    } else {
      await r.dispose();
    }
  }

  bool get _joined => _state == GroupCallState.entered ||
      _state == GroupCallState.entering ||
      _state == GroupCallState.leaving;

  Future<void> _join() async {
    try {
      await gc.enter();
      // 批次十：加入後套用放音裝置偏好（官方 Helper；失敗不影響通話）。
      try {
        await Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
      unawaited(_startCallForegroundService());
      if (mounted) {
        setState(() => _state = gc.state);
        unawaited(_attachLocal());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入失敗：$e')));
      }
    }
  }

  Future<void> _toggleMic() async {
    final local = backend.localUserMediaStream;
    if (local == null) return;
    final muted = !_micMuted;
    try {
      await backend.setDeviceMuted(gc, muted, MediaInputKind.audioinput);
      if (mounted) setState(() => _micMuted = muted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('切換麥克風失敗：$e')));
      }
    }
  }

  Future<void> _toggleCamera() async {
    final local = backend.localUserMediaStream;
    if (local == null) return;
    final muted = !_videoMuted;
    try {
      await backend.setDeviceMuted(gc, muted, MediaInputKind.videoinput);
      if (mounted) setState(() => _videoMuted = muted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('切換攝影機失敗：$e')));
      }
    }
  }

  /// 批次十一次：群組通話放音裝置改 **Discord 式輸出選單**（人類指示；與
  /// call_screen 同款骨架）。
  Future<void> _showAudioOutputSheet() async {
    final deviceNote = '本機'; // 文案草案
    // 第十八批②-A 根因修（人類實測 APK 2018，2026-11-07）：Android 12+ 藍牙
    // 列舉需 BLUETOOTH_CONNECT——manifest 原缺此權限，AudioSwitch 掃描永不含
    // 藍牙、重試無效（sheet 只剩內建兩項）。開 sheet 先請求（已授權→不彈框；
    // 拒絕→僅內建＋提示文案），拿到結果再枚舉。同 call_screen。
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
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Text('選擇音訊輸出', style: Theme.of(sheetContext).textTheme.titleMedium), // 文案草案
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '這個電話', // 文案草案
                  style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            _audioOutputRow(
              sheetContext,
              title: '電話', // 文案草案
              subtitle: deviceNote,
              icon: Icons.smartphone,
              // 第十三批①：選到外部裝置時，內建兩項不打點。
              selected: _externalAudioDevice == null && !_speakerOn,
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            _audioOutputRow(
              sheetContext,
              title: '喇叭', // 文案草案
              subtitle: deviceNote,
              icon: Icons.volume_up,
              selected: _externalAudioDevice == null && _speakerOn,
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            // 第十八批：沒有外部裝置時顯示說明（原樣貌靜默——人類實測 2026-11-07
            // 只見內建兩項、無任何解釋；同 call_screen）。骨架樣式／草案文案，
            // 待人類定稿。
            if (externalDevices.isEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    '目前沒有偵測到外部放音裝置', // 文案草案
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
                  child: Text(
                    '外部裝置', // 文案草案（DC 分組名）
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
                  icon: d.kind == 'bluetooth' ? Icons.headset : Icons.headphones,
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
    // 依 sheet 選擇套用：bool＝內建；String＝外部裝置 kind（第十三批①）。
    if (result is bool) {
      await _setSpeaker(result);
    } else if (result is String && result.isNotEmpty) {
      await _applyExternalAudio(result);
    }
  }

  /// 批次十三①：單次枚舉外部輸出裝置（去重 kind／label；官方
  /// `navigator.mediaDevices.enumerateDevices()`）。失敗（引擎未初始化／
  /// 非 Android）→ 空。
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
  /// fork AudioSwitch 清單與系統脫節），同步即時讀取、不重試。Android 11
  /// 以下（或通道不可用 → null）維持 1.6.3 舊路徑＋重試（批次十七，同
  /// call_screen）。內建 earpiece／speaker 由「這個電話」分組處理，
  /// 外部分組只列非內建。
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
  /// （非 Android／<S → null）→ 維持 1.6.3 舊路徑＋批次十七二次驗證
  /// （種類級選擇／fork no-op gate 的披露同前，known_problems 已列）。
  Future<void> _applyExternalAudio(String kind) async {
    final previous = _externalAudioDevice;
    final verified = await setCommunicationDevice(kind);
    if (verified != null) {
      setState(() => _externalAudioDevice = verified ? kind : previous);
      if (mounted && !verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('切換放音裝置失敗：裝置可能已斷線'), // 文案草案
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
          SnackBar(content: Text('切換放音裝置失敗：$e')), // 文案草案
        );
        setState(() => _externalAudioDevice = previous);
      }
      return;
    }
    final still = await _enumerateAudioOutputsOnce();
    if (mounted && !still.any((d) => d.kind == kind)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到所選放音裝置，可能已斷線')), // 文案草案
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
              Icons.circle,
              size: 20,
              color: Theme.of(sheetContext).colorScheme.primary,
            )
          : Icon(
              Icons.circle_outlined,
              size: 20,
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }

  /// 批次十一次：依 sheet 選擇套用。第二十批：Android 12+ 一律先走官方
  /// `setCommunicationDevice`（同 sheet 外部選擇同一機制——避免 fork
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
          SnackBar(content: Text('切換放音裝置失敗：$e')), // 文案草案
        );
        setState(() => _speakerOn = !target);
      }
    }
  }

  /// 批次 III-b：前後鏡頭切換（官方 `Helper.switchCamera`；人類指示）。
  Future<void> _switchCamera() async {
    try {
      final local = backend.localUserMediaStream?.stream;
      for (final t in local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
        await Helper.switchCamera(t);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法切換鏡頭：$e')), // 文案草案
        );
      }
    }
  }

  Future<void> _toggleScreenShare() async {
    // 批次 II-b＋第 7 點（人類回報「Android 15 分享畫面會當機」）根因：
    // Android 14+（15 尤甚）規定 **必須先取得 MediaProjection 使用者同意**，
    // 才能啟動 FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION 型前景服務；
    // 未同意就 startForegroundService → startForeground(mediaProjection)
    // 拋出 ForegroundServiceTypeNotAllowedException／SecurityException → 閃退。
    // 官方流程修正：flutter_webrtc `Helper.requestCapturePermission` 先彈
    // 系統同意對話框（webrtc 內部保存 consent），同意後才啟動前景服務，
    // 之後 `setScreensharingEnabled` 走 getDisplayMedia 不再二彈對話框。
    if (!_screenSharing) {
      try {
        final granted = await Helper.requestCapturePermission(
          fullScreenOnly: true,
        );
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('未授權螢幕錄製')), // 文案草案
            );
          }
          return;
        }
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('無法啟動螢幕分享同意流程：$e')), // 文案草案
          );
        }
        return;
      }
      try {
        await const MethodChannel('homing/screen_capture').invokeMethod('start');
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('無法啟動螢幕分享服務：${e.message}')),
          );
        }
        return;
      }
    }
    try {
      await backend.setScreensharingEnabled(gc, !_screenSharing, '');
      if (mounted) {
        setState(() => _screenSharing = !_screenSharing);
        // 螢幕分享期間保持螢幕常亮，避免系統回收 App
        if (_screenSharing) {
          await WakelockPlus.enable();
        } else {
          await WakelockPlus.disable();
          await const MethodChannel('homing/screen_capture').invokeMethod('stop');
          if (mounted) setState(() => _controlsVisible = true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('螢幕分享失敗：$e')));
        // 失敗時確保前景服務關閉、控制列恢復。
        try {
          await const MethodChannel('homing/screen_capture').invokeMethod('stop');
        } catch (_) {}
        if (mounted) setState(() => _controlsVisible = true);
      }
    }
  }

  Future<void> _enterPip() async {
    final ok = await PipHelper.enter();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此裝置不支援 PiP')),
      );
    } else if (mounted) {
      setState(() => _pipActive = true);
    }
  }

  Future<void> _logGroupCall(String outcome) async {
    if (_callLogged) return;
    _callLogged = true;
    final started = _callStartedAt ?? DateTime.now();
    final duration = DateTime.now().difference(started).inMilliseconds;
    final room = gc.room;
    final name = room.name.isNotEmpty ? room.name : room.id;
    await CallLog.add(
      direction: 'group',
      peerId: room.id,
      peerName: name,
      roomId: room.id,
      isGroup: true,
      startedAt: started,
      durationMs: duration < 0 ? 0 : duration,
      outcome: outcome,
    );
  }

  Future<void> _leave() async {
    try {
      await WakelockPlus.disable();
      await _logGroupCall('completed');
      await _stopCallForegroundService();
      await widget.manager.leaveGroupCall();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('離開失敗：$e')));
      }
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _showParticipants() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('參與者（${gc.participants.length}）', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final p in gc.participants)
              ListTile(
                leading: CircleAvatar(child: Text(_initial(p.userId))),
                title: Text(_displayName(p.userId)),
                subtitle: Text(p.isLocal ? '（我）' : p.userId),
              ),
          ],
        ),
      ),
    );
  }

  String _displayName(String userId) {
    final at = userId.indexOf(':');
    final local = at > 0 ? userId.substring(1, at) : userId;
    return local;
  }

  String _initial(String userId) {
    final name = _displayName(userId);
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  bool _isSpeaking(CallParticipant? p) {
    if (p == null || _activeSpeaker == null) return false;
    return p.userId == _activeSpeaker!.userId && p.deviceId == _activeSpeaker!.deviceId;
  }

  bool _hasVideo(WrappedMediaStream s) {
    try {
      return !s.videoMuted && (s.stream?.getVideoTracks().isNotEmpty ?? false);
    } catch (_) {
      return !s.videoMuted;
    }
  }

  int _crossAxisCount(int n) {
    if (n <= 1) return 1;
    if (n <= 4) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final screenShares = backend.screenShareStreams.where((s) => !s.isLocal()).toList();
    final allStreams = <WrappedMediaStream>[];
    final seenIds = <String>{};
    // 批次 II-e：螢幕分享優先（分享中時先放分享串流）。
    for (final s in screenShares) {
      if (seenIds.add(s.id)) allStreams.add(s);
    }
    // 本機畫面
    if (_localRenderer != null && backend.localUserMediaStream != null) {
      if (seenIds.add(backend.localUserMediaStream!.id)) {
        allStreams.insert(0, backend.localUserMediaStream!);
      }
    }
    // 遠端
    for (final s in _remoteStreams) {
      if (seenIds.add(s.id)) allStreams.add(s);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 頂部：標題 + 參與者數
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _GroupAvatar(room: gc.room),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          gc.room.name.isNotEmpty ? gc.room.name : gc.room.id,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '群組通話（${gc.participants.length} 人）',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (!_pipActive) ...[
                    IconButton(
                      tooltip: '參與者',
                      onPressed: _showParticipants,
                      icon: const Icon(Icons.people, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
            // 媒體區
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                child: !_joined
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '群組通話（${gc.participants.length} 人）',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _join,
                            icon: const Icon(Icons.call),
                            label: const Text('加入通話'),
                          ),
                        ],
                      ),
                    )
                  : screenShares.isNotEmpty
                      ? Column(
                          children: [
                            // 批次 II-e＋第 3 點（人類回報「分享畫面不定時不自動調整」）：
                            // 舊條件 `(_screenSharing && screenShares.isNotEmpty)`
                            // 讓**觀看端**（本地未開 share flag）掉進 GridView 小格，
                            // 分享視窗時有時無。改為「有任何分享串流即大畫面」；
                            // 並以 contain: true 完整呈現（不裁切、比例自動貼合）。
                            Expanded(
                              flex: 3,
                              child: _remoteRenderers[screenShares.first.id] != null
                                  ? _VideoTile(
                                      renderer: _remoteRenderers[screenShares.first.id]!,
                                      label: '螢幕分享',
                                      speaking: false,
                                      hasVideo: true,
                                      avatarFallback: false,
                                      contain: true,
                                    )
                                  : const Center(child: Icon(Icons.person, color: Colors.white54, size: 40)),
                            ),
                            // 參與者縮圖列。
                            SizedBox(
                              height: 88,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  if (_localRenderer != null)
                                    SizedBox(
                                      width: 96,
                                      child: _VideoTile(
                                        renderer: _localRenderer!,
                                        label: '我',
                                        speaking: _isSpeaking(gc.localParticipant),
                                        hasVideo: !_videoMuted,
                                        avatarFallback: true,
                                      ),
                                    ),
                                  for (final s in _remoteStreams)
                                    if (_remoteRenderers[s.id] != null)
                                      SizedBox(
                                        width: 96,
                                        child: _VideoTile(
                                          renderer: _remoteRenderers[s.id]!,
                                          label: _displayName(s.participant.userId),
                                          speaking: _isSpeaking(s.participant),
                                          hasVideo: _hasVideo(s),
                                          avatarFallback: true,
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : GridView.count(
                          crossAxisCount: _crossAxisCount(allStreams.length.clamp(1, 9)),
                          children: [
                            // 本機
                            if (_localRenderer != null)
                              _VideoTile(
                                renderer: _localRenderer!,
                                label: '我',
                                speaking: _isSpeaking(gc.localParticipant),
                                hasVideo: !_videoMuted,
                                avatarFallback: true,
                              ),
                            // 遠端
                            for (final s in _remoteStreams)
                              if (_remoteRenderers[s.id] != null)
                                _VideoTile(
                                  renderer: _remoteRenderers[s.id]!,
                                  label: _displayName(s.participant.userId),
                                  speaking: _isSpeaking(s.participant),
                                  hasVideo: _hasVideo(s),
                                  avatarFallback: true,
                                )
                              else
                                const Center(child: Icon(Icons.person, color: Colors.white54, size: 40)),
                          ],
                        ),
              ),
            ),
            // 控制列（PiP 時隱藏）
            if (_controlsVisible && !_pipActive && _joined)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      tooltip: _micMuted ? '取消靜音' : '靜音',
                      onPressed: _toggleMic,
                      icon: Icon(_micMuted ? Icons.mic_off : Icons.mic),
                    ),
                    IconButton.filled(
                      tooltip: _videoMuted ? '開啟攝影機' : '關閉攝影機',
                      onPressed: _toggleCamera,
                      icon: Icon(_videoMuted ? Icons.videocam_off : Icons.videocam),
                    ),
                    // 批次 III-b：前後鏡頭切換（人類指示）。
                    IconButton.filled(
                      tooltip: '切換鏡頭', // 文案草案
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                    // 批次十一次：放音裝置 → Discord 式輸出選單。
                    IconButton.filled(
                      tooltip: '選擇音訊輸出', // 文案草案
                      onPressed: _showAudioOutputSheet,
                      icon: Icon(_speakerOn ? Icons.volume_up : Icons.phone_in_talk),
                    ),
                    IconButton.filled(
                      tooltip: _screenSharing ? '停止分享' : '分享螢幕',
                      onPressed: _toggleScreenShare,
                      icon: Icon(_screenSharing ? Icons.stop_screen_share : Icons.screen_share),
                    ),
                    IconButton.filled(
                      tooltip: '子母畫面 (PiP)',
                      onPressed: _enterPip,
                      icon: const Icon(Icons.picture_in_picture_alt),
                    ),
                    IconButton.filled(
                      tooltip: '離開通話',
                      style: IconButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: _leave,
                      icon: const Icon(Icons.call_end, color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 單一視訊 tile：視訊關閉時顯示頭像 + 名稱疊加 + 說話高亮。
class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.renderer,
    required this.label,
    required this.speaking,
    required this.hasVideo,
    this.avatarFallback = false,
    this.contain = false,
  });

  final RTCVideoRenderer renderer;
  final String label;
  final bool speaking;
  final bool hasVideo;
  final bool avatarFallback;

  /// 通話時分享螢幕（人類回報「視窗不一定每次都能自動調整畫面」）：
  /// 螢幕分享用 **Contain**（完整顯示不裁切）；人物流維持 Cover。
  /// Cover 對橫向螢幕串流會裁掉左右／上下，看起來像「畫面沒有調整」。
  final bool contain;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: speaking ? Border.all(color: Colors.greenAccent, width: 3) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo)
            RTCVideoView(
              renderer,
              objectFit: contain
                  ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                  : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: CircleAvatar(
                radius: 32,
                child: Text(
                  label.isEmpty ? '?' : label[0].toUpperCase(),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          // 名稱（左下角）
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          // 音量表（說話時顯示綠色圓點）
          if (speaking)
            const Positioned(
              right: 8,
              top: 8,
              child: Icon(Icons.volume_up, color: Colors.greenAccent, size: 20),
            ),
        ],
      ),
    );
  }
}

/// 群組通話標頭頭像（草案）：有 avatar mxc 時載入（含認證媒體 header），
/// 否則顯示房間名首字。
class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.room});

  final Room room;

  Uri? _safeAvatar() {
    try {
      return room.avatar;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = room.name.isNotEmpty ? room.name : room.id;
    final first = title.runes.isEmpty ? null : String.fromCharCode(title.runes.first);
    final avatar = _safeAvatar();
    if (avatar == null) {
      return CircleAvatar(child: Text(first ?? '?'));
    }
    return FutureBuilder<(Uri, bool)>(
      future: () async {
        final uri = await avatar.getThumbnailUri(room.client, width: 64, height: 64);
        final auth = await room.client.authenticatedMediaSupported();
        return (uri, auth);
      }(),
      builder: (context, snap) {
        if (snap.hasData) {
          final (uri, auth) = snap.data!;
          return CircleAvatar(
            backgroundImage: NetworkImage(
              uri.toString(),
              headers: auth
                  ? <String, String>{'authorization': 'Bearer ${room.client.accessToken}'}
                  : null,
            ),
          );
        }
        return CircleAvatar(child: Text(first ?? '?'));
      },
    );
  }
}
