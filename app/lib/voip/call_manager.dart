// P2.15 提案（人類指示 2026-11-01）— 一對一通話管理（草案）。
// 組接：SDK 官方 VoIP（`m.call.*`）＋ RingWebRTCDelegate（flutter_webrtc）。
// 邊界：本檔不寫加密／金鑰程式碼（E2EE keyProvider 不啟用，SDK 預設行為）；
// 群組通話暫緩；來電偵測僅在 App 接近活躍時運作（背景推送不在本批）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'livekit_call_manager.dart'
    show LiveKitCallManager, LiveKitCallPhase, RingLiveKitKeyProvider;
import 'ring_delegate.dart';

/// 批次二十八（人類拍板 2026-11-10）：glare 來電不再吞掉。背景（已定位根因）：
/// SDK 官方 glare（voip call_session.dart L208-240，callId 字典序取捨）會決定
/// 哪一保留，但我們原版 `_onNewCall` 在 `activeCall` 未清空時**直接丟棄**新來電
/// → 兩端同時撥打時勝出方向的來電 UI 永不出現＝「無法互接」。
/// 修法：暫存 `pendingIncoming`，待 `activeCall` 清空後浮現（官方 `callHasEnded`
/// 監察；無 timer）。
String callStateLabel(CallState s) {
  switch (s) {
    case CallState.kFledgling:
      return '準備中';
    case CallState.kWaitLocalMedia:
      return '取得麥克風／攝影機…';
    case CallState.kCreateOffer:
      return '建立邀請…';
    case CallState.kInviteSent:
      return '撥打中…';
    case CallState.kCreateAnswer:
      return '建立接聽…';
    case CallState.kRinging:
      return '響鈴中…';
    case CallState.kConnecting:
      return '連線中…';
    case CallState.kConnected:
      return '通話中';
    case CallState.kEnding:
      return '掛斷中…';
    case CallState.kEnded:
      return '已結束';
  }
}

/// 通話計時顯示（純函式）：mm:ss（>=1h 使用 h:mm:ss）。
String formatCallDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final sm = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sm' : '${m.toString().padLeft(2, '0')}:$sm';
}

class CallManager extends ChangeNotifier {
  CallManager({required this.client});

  final Client client;

  RingWebRTCDelegate? _delegate;
  VoIP? _voip;
  bool _initialized = false;

  /// SDK 回呼層（供未來鈴聲／未接來電 UI 接口查驗用；目前未接來電僅記於
  /// `onMissedCall` 流，App 尚未顯示未接清單）。
  RingWebRTCDelegate? get delegate => _delegate;

  /// SDK VoIP 本體（第三十批：LiveKitCallManager 取用官方
  /// fetchOrCreateGroupCall 等入口；未初始化時 null）。
  VoIP? get voip => _voip;

  /// 第三十批（人類批准 2026-11-10）：LiveKit E2EE 金鑰之官方介面薄殼
  /// （實作在 livekit_call_manager.dart；純儲存↔轉發，零自製演算法）。
  /// ensureInit 時注入 delegate，SDK `LiveKitBackend` 的金鑰事件即路由到這裡。
  final RingLiveKitKeyProvider livekitKeyProvider = RingLiveKitKeyProvider();

  /// 第三十一批（mesh 批次 II-j 語意移植）：LiveKit 群通 session 持有——
  /// 「按返回＝通話繼續、可從聊天室再進入」。畫面 dispose 不離開；明確
  /// 掛斷／自動退出才清空（由 [clearLiveKit] 收尾）。
  LiveKitCallManager? _activeLiveKit;
  LiveKitCallManager? get activeLiveKit => _activeLiveKit;
  Room? activeLiveKitRoom;

  /// 取得（或建立）活躍的 LiveKit session。⑥ 同房間且進行中 → 直接重用。
  Future<LiveKitCallManager> getOrCreateLiveKit(Room room) async {
    final existing = _activeLiveKit;
    if (existing != null &&
        activeLiveKitRoom?.id == room.id &&
        (existing.phase == LiveKitCallPhase.joining ||
            existing.phase == LiveKitCallPhase.connected)) {
      return existing;
    }
    if (existing != null) {
      await existing.leave(userTerminate: false);
    }
    final fresh = LiveKitCallManager(this);
    _activeLiveKit = fresh;
    activeLiveKitRoom = room;
    return fresh;
  }

  /// session 明確離場（掛斷／自動退出／rejoin 重啟）後由
  /// LiveKitCallManager 呼叫收尾。
  void clearLiveKit(LiveKitCallManager manager) {
    if (identical(_activeLiveKit, manager)) {
      _activeLiveKit = null;
      activeLiveKitRoom = null;
    }
  }

  @override
  void dispose() {
    unawaited(_syncWatch?.cancel());
    _syncWatch = null;
    _delegate?.dispose();
    super.dispose();
  }

  /// 第二十八批（臨時診斷，下一批除役）：官方 `VoIP.getIceServers()` 數量。
  /// 返回 −1＝取得失敗（SDK 官方行為：失敗即空清單，無 STUN 兜底）；
  /// −2＝VoIP 未初始化。
  Future<int> diagnosticIceServerCount() async {
    final voip = _voip;
    if (voip == null) {
      return -2;
    }
    try {
      return (await voip.getIceServers()).length;
    } catch (_) {
      return -1;
    }
  }

  /// 初始化失敗訊息（如裝置不支援／初始化例外）；非 null 時通話入口應禁用告知。
  String? callSupportError;

  /// 目前唯一在意的通話（一對一框架：同時僅一通）。
  CallSession? activeCall;

  /// 來電會話（非 null 時 UI 應顯示來電按鈕／彈出通話畫面）。
  final ValueNotifier<CallSession?> incomingCall = ValueNotifier(null);

  /// 第二十八批：glare 勝出但 activeCall 佔用中被暫存的來電。
  /// `activeCall` 清空後由 [onCallEnded 串流] 浮現為 `incomingCall`。
  CallSession? pendingIncoming;
  bool _surfacingPending = false;

  /// 第二十八批：最近一次 SDK 釘 `onCallEnded` 的終態記錄（診斷列／logcat 用）。
  String? diagnosticLastCallEnd;

  /// 第二十八批：節流不私用的官方 sync 鈎——若 `activeCall` 已終態但
  /// SDK onCallEnded 沒觸發（批次 II-c 已註記的既有現象）→ 清掉殘留，
  /// 讓「無法發起（已有通話進行中）」的卡死自動解除。onSync 每輪一次，
  /// 無 Timer（widget 測試安全）。
  StreamSubscription? _syncWatch;
  void _watchStaleCalls() {
    _syncWatch ??= client.onSync.stream.listen((_) {
      final current = activeCall;
      if (current != null && current.callHasEnded) {
        clearCall(current);
      }
      final pending = pendingIncoming;
      if (pending != null && pending.callHasEnded) {
        pendingIncoming = null; // SDK 官方 lifetime 逾時 → 棄暫存。
      }
    });
  }

  /// 群組通話（mesh）進行中。
  final ValueNotifier<GroupCallSession?> activeGroupCall = ValueNotifier(null);

  /// 來電／遠端發起的群組通話（需使用者加入）。
  final ValueNotifier<GroupCallSession?> incomingGroupCall = ValueNotifier(null);

  void ensureInit() {
    if (_initialized) {
      return;
    }
    try {
      final delegate = RingWebRTCDelegate();
      // 第三十批：注入 LiveKit E2EE keyProvider（官方介面；mesh 不受影響）。
      delegate.livekitKeyProvider = livekitKeyProvider;
      final voip = VoIP(client, delegate);
      _delegate = delegate;
      _voip = voip;
      _initialized = true;

      delegate.onNewCall.listen(_onNewCall);
      delegate.onCallEnded.listen(_onCallEnded);
      delegate.onNewGroupCall.listen(_onNewGroupCall);
      delegate.onGroupCallEnded.listen(_onGroupCallEnded);
      // 批次二十八：殘留終態 session 掃除（見 _watchStaleCalls 註解）。
      if (client.isLogged()) {
        _watchStaleCalls();
      }
      client.onLoginStateChanged.stream.listen((state) {
        if (state == LoginState.loggedIn) {
          _watchStaleCalls();
        } else if (state == LoginState.loggedOut) {
          unawaited(_syncWatch?.cancel());
          _syncWatch = null;
          activeCall = null;
          pendingIncoming = null;
        }
      });
    } catch (e) {
      callSupportError = '通話功能初始化失敗：$e';
      _initialized = true; // 不重試；UI 以 callSupportError 告知。
    }
    notifyListeners();
  }

  bool get isSupported => _initialized && callSupportError == null;

  void _onNewCall(CallSession session) {
    // 一對一僅在意來電（kIncoming）；去電由 startCall 自行接管。
    if (session.direction != CallDirection.kIncoming) {
      return;
    }
    // === 第二十八批：glare 勝出來電不再吞掉 ===
    // 既有進行中通話：先暫存（SDK 官方 glare 已做字典序取捨；亦保護極短
    // 過渡期），待 active 清空再浮現；真正忙碌時使用者可在 UI 明確
    // 接／拒（官方 answer／reject），而非靜默讓對方乾等。
    final current = activeCall;
    if (current != null && !current.callHasEnded && !identical(current, session)) {
      pendingIncoming ??= session;
      return;
    }
    activeCall = session;
    incomingCall.value = session;
    notifyListeners();
  }

  /// 第二十八批：`activeCall` 清空後浮現暫存的 glare 勝出來電。
  void _surfacePendingIncoming() {
    if (_surfacingPending) {
      return;
    }
    _surfacingPending = true;
    // microtask：讓同批次 onCallEnded 先把 activeCall 清乾淨再判斷。
    scheduleMicrotask(() {
      _surfacingPending = false;
      final pending = pendingIncoming;
      if (pending == null) {
        return;
      }
      if (pending.callHasEnded) {
        // SDK 官方 lifetime 逾時或對方取消：棄暫存（不浮現）。
        pendingIncoming = null;
        return;
      }
      final current = activeCall;
      if (current != null && !current.callHasEnded) {
        return; // 仍忙碌：留待下一次 surface。
      }
      activeCall = pending;
      pendingIncoming = null;
      incomingCall.value = pending;
      notifyListeners();
    });
  }

  void _onCallEnded(CallSession session) {
    diagnosticLastCallEnd =
        '${DateTime.now().toIso8601String().substring(11, 19)} 終態（state=${session.state}）'; // 文案草案
    if (identical(activeCall, session)) {
      activeCall = null;
      if (identical(incomingCall.value, session)) {
        incomingCall.value = null;
      }
      notifyListeners();
      _surfacePendingIncoming(); // 第二十八批：glare 勝出來電補位。
    } else if (identical(incomingCall.value, session)) {
      incomingCall.value = null;
      notifyListeners();
      _surfacePendingIncoming();
    } else if (identical(pendingIncoming, session)) {
      pendingIncoming = null; // 暫存中的來電被對方取消/lifetime 逾時。
    }
  }

  /// 批次 II-c：通話結束時由 UI 主動清除 SDK 狀態（SDK 的 onCallEnded 有時不觸發，
  /// 導致「前一次通話的身份還留在通話中」）。僅在 identical 時清除，避免誤清。
  void clearCall(CallSession session) {
    var changed = false;
    if (identical(activeCall, session)) {
      activeCall = null;
      changed = true;
    }
    if (identical(incomingCall.value, session)) {
      incomingCall.value = null;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void clearGroupCall(GroupCallSession gc) {
    var changed = false;
    if (identical(activeGroupCall.value, gc)) {
      activeGroupCall.value = null;
      changed = true;
    }
    if (identical(incomingGroupCall.value, gc)) {
      incomingGroupCall.value = null;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _onNewGroupCall(GroupCallSession gc) {
    // 第三十批：LiveKit（famedly flavor, backend=LiveKitBackend）群通由
    // LiveKitCallScreen／LiveKitCallManager 自行管理，不進 mesh 的
    // ValueNotifier——否則 main_shell 的 incomingGroupCall 監聽會自動彈出
    // mesh 群組通話畫面，兩套通話 UI 打架。
    if (gc.backend is LiveKitBackend) {
      return;
    }
    // 自己發起的（enter 後 handleNewGroupCall 仍會觸發）→ 只在尚未設定時更新。
    if (activeGroupCall.value == null) {
      activeGroupCall.value = gc;
    }
    // 遠端發起 → 記為 incoming（除非自己剛 enter）。
    if (gc.state != GroupCallState.entered && incomingGroupCall.value == null) {
      incomingGroupCall.value = gc;
    }
    notifyListeners();
  }

  void _onGroupCallEnded(GroupCallSession gc) {
    if (identical(activeGroupCall.value, gc)) {
      activeGroupCall.value = null;
    }
    if (identical(incomingGroupCall.value, gc)) {
      incomingGroupCall.value = null;
    }
    notifyListeners();
  }

  void clearIncoming() {
    if (incomingCall.value != null) {
      incomingCall.value = null;
      notifyListeners();
    }
    // 第二十八批：UI 關閉來電畫面＝拒接／掛斷已完成時，暫存一併清。
    if (pendingIncoming != null && pendingIncoming!.callHasEnded) {
      pendingIncoming = null;
    }
  }

  /// 撥打：一對一（direct chat）的純音訊或含視訊；userId 帶
  /// `room.directChatMatrixID`（SDK 建議：避免自己的其他裝置誤響）。
  Future<CallSession> startCall(Room room, {bool video = false}) async {
    ensureInit();
    if (!isSupported) {
      throw StateError(callSupportError ?? '通話功能不可用');
    }
    final current = activeCall;
    if (current != null && !current.callHasEnded) {
      throw StateError('已有通話進行中（${callStateLabel(current.state)}）');
    }
    if (!room.isDirectChat) {
      throw StateError('本批次僅支援一對一通話');
    }
    final session = await _voip!.inviteToCall(
      room,
      video ? CallType.kVideo : CallType.kVoice,
      userId: room.directChatMatrixID,
    );
    activeCall = session;
    notifyListeners();
    return session;
  }

  /// 發起群組通話（mesh）：建立 GroupCallSession 並 enter()。
  /// 回傳後 UI 應顯示 GroupCallScreen；遠端發起由 SDK handleNewGroupCall 觸發。
  Future<GroupCallSession> startGroupCall(Room room) async {
    ensureInit();
    if (!isSupported) {
      throw StateError(callSupportError ?? '通話功能不可用');
    }
    if (activeGroupCall.value != null) {
      throw StateError('已有群組通話進行中');
    }
    final backend = MeshBackend();
    final gc = await _voip!.fetchOrCreateGroupCall(
      room.id,
      room,
      backend,
      'm.call',
      'm.room',
    );
    await gc.enter();
    activeGroupCall.value = gc;
    notifyListeners();
    return gc;
  }

  Future<void> leaveGroupCall() async {
    final gc = activeGroupCall.value;
    if (gc == null) {
      return;
    }
    try {
      await gc.leave();
    } catch (e) {
      // 已離開或例外：記錄但不清除錯誤；仍清狀態避免 UI 卡住。
      // ignore: avoid_print
      print('leaveGroupCall failed: $e');
    }
    activeGroupCall.value = null;
    incomingGroupCall.value = null;
    notifyListeners();
  }

  Future<void> answerCurrent() async {
    final session = incomingCall.value ?? activeCall;
    if (session == null) {
      return;
    }
    await session.answer();
    notifyListeners();
  }

  Future<void> rejectCurrent() async {
    final session = incomingCall.value;
    if (session == null) {
      return;
    }
    await session.reject();
    incomingCall.value = null;
    notifyListeners();
  }

  Future<void> hangupCurrent() async {
    final session = activeCall;
    if (session == null || session.callHasEnded) {
      return;
    }
    await session.hangup(reason: CallErrorCode.userHangup);
  }
}
