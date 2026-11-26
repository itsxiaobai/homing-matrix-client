// 第三十批（人類批准 2026-11-10）＋第三十一批（人類批准「全部移植」＋
// 「其他人已離開」倒數 20 秒）— LiveKit 群組通話管理器。
// 組接：SDK 官方 famedly-flavor `LiveKitBackend`（MatrixRTC 成員狀態＋E2EE 金鑰
// 輪替全由 SDK 官方處理）＋ `livekit_client`（媒體連線，SDK 明文要求 App 端供應）。
//
// ⚠️ 加密邊界（依 AGENTS.md，人類批准＝SDK 官方路徑）：
// * 本檔不寫任何加密／金鑰演算法。`RingLiveKitKeyProvider` 僅是 SDK 官方
//   `EncryptionKeyProvider` 介面的「儲存↔轉發」薄殼：
//   SDK（LiveKitBackend）正式產生金鑰 → onSetEncryptionKey 原樣轉給
//   livekit_client 的 BaseKeyProvider（→ flutter_webrtc 原生 frame cryptor）；
//   onRatchetKey 回空 → SDK 官方 fallback 改生成全新金鑰（上游
//   livekit_backend.dart L146-180 官方行為）；金鑰演算法全在上游。
// * ratchet 關閉＝`VoIP.enableSFUE2EEKeyRatcheting` 官方預設 false，本批不開。
// * v0 互通性限制：famedly flavor 成員事件＝`com.famedly.call.member`
//   （SDK 刻意偏離 MSC4143）→ Element X 看不到／進不了這種群組通話
//   （SDK 上游恆定，本批次不修）。
//
// JWT 取得（官方流程，fluffychat e1ca8ae 為已證運作先例，僅流程形狀參照）：
//   client.requestOpenIdToken → POST {livekit_service_url}/sfu/get
//   body {room, openid_token, device_id} → 200 {url, jwt} → lk Room.connect。
// lk 房間名＝room.id（兩端一致）；groupCallId＝'lk:<room.id>'（與 mesh 端
// groupCallId=room.id 區隔：famedly 成員 state 同通道互搶 session，見
// fetchOrCreateGroupCall 的 VoipId(roomId, callId) 鍵）。
//
// 第三十一批映射（mesh → LiveKit，皆官方 API／既有零依賴通路）：
//   音量表＝lk ActiveSpeakersChangedEvent；連線品質＝Participant
//   ConnectionQualityUpdatedEvent＋「重新加入」；wake lock＝wakelock_plus（已
//   批准依賴，連線中啟用）；螢幕分享＝Hardware.requestCapturePermission（官方
//   MediaProjection 同意框）＋既有 ring/screen_capture 前景服務（Android 14+
//   必需，批次 II-b 已建，傳輸層無關）＋setScreenShareEnabled；鏡頭切換＝
//   LocalVideoTrack.setCameraPosition；放音裝置＝內建兩項走 livekit 官方
//   AudioManager.setSpeakerOutputPreferred，外部裝置沿用既有 ring/permissions
//   溝通裝置通道（批次二十定案機制；與 livekit 音訊路由之衝突 ⚠️待實機驗證）；
//   殘留檢查＝官方 membership isExpired 欄位觀察＋log（join 路徑 SDK 官方
//   會取消 pending delayed leave 並改寫 state，清理由 SDK 包辦）；通話記錄＝
//   CallLog.add（與 mesh 同款）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../call_log.dart';
import '../app_settings.dart';
import 'call_manager.dart';
import 'livekit_config.dart';

/// 解析 lk-jwt-service `POST /sfu/get` 之 200 回應 `{url, jwt}`；
/// 缺欄位/型別錯 → FormatException（不瞎猜，失敗即回報）。
({String url, String jwt}) parseSfuGetResponse(Map<String, Object?> json) {
  final url = json['url'];
  final jwt = json['jwt'];
  if (url is! String || url.isEmpty || jwt is! String || jwt.isEmpty) {
    throw const FormatException('sfu/get 回應缺 url 或 jwt 欄位');
  }
  return (url: url, jwt: jwt);
}

/// lk 參與者 identity 對映：`<userId>:<deviceId>`（fluffychat 已證先例）。
/// matrix.org lk-jwt-service 實際 identity 格式＝2030 實機連線後比對；
/// 若不符會 ImportError 找不到金鑰 → 停下回報，不瞎猜。
String lkParticipantIdentity(String userId, String? deviceId) =>
    deviceId == null || deviceId.isEmpty ? userId : '$userId:$deviceId';

/// 從 famedly flavor `com.famedly.call.member` state 內容抽取
/// type=='livekit' 之 membership 的 call_id，供加入端與發起端
/// 取得同一 groupCallId。找不到回 null（發起端用預設 `'lk:<room.id>'`）。
String? deriveLiveKitGroupCallIdFromContent(Map<String, Object?> content) {
  final mems = content['memberships'];
  if (mems is! List) {
    return null;
  }
  for (final mem in mems) {
    if (mem is! Map) {
      continue;
    }
    final foci = mem['foci_active'];
    final isLivekit = foci is List &&
        foci.any((f) => f is Map && f['type'] == 'livekit');
    if (!isLivekit) {
      continue;
    }
    final callId = mem['call_id'];
    if (callId is String && callId.isNotEmpty) {
      return callId;
    }
  }
  return null;
}

/// SDK 官方 `EncryptionKeyProvider` 介面的 Homing 實作：純儲存＋原樣轉發。
class RingLiveKitKeyProvider implements EncryptionKeyProvider {
  RingLiveKitKeyProvider();

  Future<lk.BaseKeyProvider>? _baseFuture;
  lk.Room? _room;

  /// 由 [LiveKitCallManager] 於 lk Room 建立後 attach，讓
  /// onSetEncryptionKey 能把 keyIndex push 給 lk 的 e2eeManager。
  void attachRoom(lk.Room? room) => _room = room;

  /// 首次呼叫建立原生 keyProvider（webrtc frameCryptorFactory，官方 API）。
  Future<lk.BaseKeyProvider> ensureReady() {
    final existing = _baseFuture;
    if (existing != null) {
      return existing;
    }
    // 參數取 fluffychat 已證組合（matrixRTC：非 sharedKey、無 lk 自
    // ratchet、金鑰未備妥丟影格）。
    final options = rtc.KeyProviderOptions(
      sharedKey: false,
      ratchetSalt: Uint8List.fromList('LKFrameEncryptionKey'.codeUnits),
      ratchetWindowSize: 0,
      discardFrameWhenCryptorNotReady: true,
      keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
    );
    return _baseFuture = rtc.frameCryptorFactory
        .createDefaultKeyProvider(options)
        .then((native) => lk.BaseKeyProvider(native, options));
  }

  @override
  Future<void> onSetEncryptionKey(
    CallParticipant participant,
    Uint8List key,
    int index,
  ) async {
    final identity =
        lkParticipantIdentity(participant.userId, participant.deviceId);
    final base = await ensureReady();
    await base.setRawKey(key, participantId: identity, keyIndex: index);
    final room = _room;
    try {
      await room?.e2eeManager?.setKeyIndex(index, participantIdentity: identity);
    } catch (_) {
      // e2eeManager 尚未 setup 或 cryptor 未建立：金鑰已存於 base provider，
      // UI 建立發送器／接收器時 SDK 會用 getLatestIndex 取得。
    }
  }

  @override
  Future<Uint8List> onRatchetKey(CallParticipant participant, int index) async {
    // Homing 不自訂 ratchet 演算法（AGENTS 加密紅線）。回空 → SDK 官方
    // fallback：ratchet 失敗改 `_makeNewSenderKey` 重新造 key 廣播。
    return Uint8List(0);
  }

  @override
  Future<Uint8List> onExportKey(CallParticipant participant, int index) async {
    final identity =
        lkParticipantIdentity(participant.userId, participant.deviceId);
    final base = await ensureReady();
    return base.exportKey(identity, index);
  }
}

enum LiveKitCallPhase { joining, connected, error, left }

/// LiveKit 群組通話管理器：foci → groupCall → JWT → lk Room → track。
/// 第三十一批：由 CallManager 持有（同 mesh「按返回通話繼續、可從聊天室
/// 再進入」批次 II-j 語意）；畫面 just 綁定。
class LiveKitCallManager extends ChangeNotifier {
  LiveKitCallManager(this.callManager);

  final CallManager callManager;

  Client get client => callManager.client;

  VoIP get _voip =>
      callManager.voip ??
      (throw StateError('通話初始化尚未完成'));

  RingLiveKitKeyProvider get keyProvider => callManager.livekitKeyProvider;

  LiveKitCallPhase phase = LiveKitCallPhase.left;
  String? statusText; // joining 過程階段文案（草案）
  String? errorMessage;

  /// UI 目標房（rejoin 用）。
  Room? _targetRoom;

  lk.Room? get room => _room;
  lk.Room? _room;
  GroupCallSession? _groupCall;
  final List<lk.CancelListenFunc> _listenCancels = [];

  DateTime? _connectedAt;
  bool _callLogged = false;

  // ---- 第三十一批：speak 高亮 / 連線品質 / 倒數 --------------------------

  /// 目前說話者 identity 集合（lk ActiveSpeakersChangedEvent 官方事件）。
  Set<String> activeSpeakerIdentities = {};

  /// 本機連線品質（lk 官方 ConnectionQuality；poor/lost → UI 顯示重新加入）。
  lk.ConnectionQuality ownQuality = lk.ConnectionQuality.unknown;

  /// 「其他人已離開」倒數剩餘秒數；-1＝未啟動（人類拍板 20 秒）。
  int othersLeftCountdown = -1;
  Timer? _othersLeftTimer;
  bool _sawARemoteParticipant = false;

  /// 自動退出的提示（畫面 pop 後以 snackbar 顯示；草案文案）。
  String? exitNotice;

  /// 加入前殘留狀態觀察（F 簡化版；官方 isExpired 欄位；僅記錄，SDK 官方
  /// join 路徑會取消 pending delayed leave 並改寫自己的成員 state）。
  String? staleMembershipNote;

  // ---- join 流程 ----------------------------------------------------------

  /// 加入（發起或加入均走此路）：成員狀態＋金鑰由 SDK 官方包辦。
  Future<void> join(Room targetRoom, {bool video = true}) async {
    if (phase == LiveKitCallPhase.joining || phase == LiveKitCallPhase.connected) {
      return;
    }
    try {
      callManager.ensureInit();
      if (!callManager.isSupported) {
        throw StateError(callManager.callSupportError ?? '通話功能不可用');
      }
      _resetSessionState();
      _targetRoom = targetRoom;
      _set(phase: LiveKitCallPhase.joining, statusText: '準備中…');
      final foci = await resolveLiveKitFoci(client);
      if (foci == null) {
        throw StateError('此服務商暫不支援多人通話，仍可使用原本的通話功能');
      }

      // F｜殘留觀察：房內自己過期的 livekit membership（官方 isExpired 欄位）。
      _inspectStaleMembership(targetRoom);

      // groupCallId：優先用房內既有 livekit membership 呼出的 call_id，讓
      // 兩端落在同一個 famedly 通道上的 session；否則用固定預設值。
      final existingGroupId = _existingLiveKitGroupId(targetRoom) ?? 'lk:${targetRoom.id}';
      final backend = LiveKitBackend(
        livekitServiceUrl: foci.serviceUrl,
        livekitAlias: targetRoom.id, // lk 房名＝room.id（兩端一致）
      );
      final gc = await _voip.fetchOrCreateGroupCall(
        existingGroupId,
        targetRoom,
        backend,
        'm.call',
        'm.room',
      );
      _groupCall = gc;

      _set(phase: LiveKitCallPhase.joining, statusText: '通知成員…');
      await gc.enter(); // famedly 成員 state＋preShareKey 官方包辦

      // 金鑰容器先備好（enter→preShareKey 已先凍 onSetEncryptionKey 其中）
      await keyProvider.ensureReady();

      _set(phase: LiveKitCallPhase.joining, statusText: '連線中…');
      final credentials = await _fetchSfuCredentials(targetRoom, foci.serviceUrl);

      final base = await keyProvider.ensureReady();
      final lkRoom = lk.Room(
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          encryption: lk.E2EEOptions(keyProvider: base),
        ),
      );
      _room = lkRoom;
      keyProvider.attachRoom(lkRoom);
      _subscribeRoomEvents(lkRoom);
      await lkRoom.connect(credentials.url, credentials.jwt);

      // 麥克風／攝影機各擬 ON；失敗不攔掉整個啟動（v0 盡力）。
      final local = lkRoom.localParticipant;
      if (local != null) {
        await _loadCameraPreference(); // 第三十二批③：沿用上次前後鏡頭選擇。
        try {
          await local.setMicrophoneEnabled(true);
        } catch (e) {
          statusText = '麥克風啟用失敗：$e';
          notifyListeners();
        }
        // 2026-11-20：語音通話（video=false）預設不開鏡頭。
        try {
          await local.setCameraEnabled(video);
        } catch (e) {
          statusText = '攝影機啟用失敗：$e';
          notifyListeners();
        }
      }
      _connectedAt = DateTime.now();
      _callLogged = false;
      // D｜wake lock：連線中保持螢幕不眠（離場即關）。
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      // 第三十二批④：通話通知（前景服務）由 manager 管理——返回／最小化後
      // session 仍在，通知也應持續存在（原實作在畫面層，pop 後斷管）。
      // 連線中啟動；螢幕分享切換時 update（④即時狀態）；離場 stop。
      unawaited(_startCallService());
      _set(phase: LiveKitCallPhase.connected, statusText: null);
    } catch (e) {
      errorMessage = '無法加入多人通話：$e'; // 文案草案
      statusText = null;
      phase = LiveKitCallPhase.error;
      notifyListeners();
      await _cleanup(); // 部署中的成員 state 要撤回（gc.leave）
    }
  }

  /// 官方 JWT 流：requestOpenIdToken → POST {serviceUrl}/sfu/get。
  Future<({String url, String jwt})> _fetchSfuCredentials(
    Room targetRoom,
    String serviceUrl,
  ) async {
    final userId = client.userID;
    if (userId == null) {
      throw StateError('未登入');
    }
    final openId = await client.requestOpenIdToken(userId, {});
    final url = serviceUrl.replaceAll(RegExp(r'/+$'), '');
    final response = await client.httpClient.post(
      Uri.parse('$url/sfu/get'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'room': targetRoom.id,
        'openid_token': openId.toJson(),
        'device_id': client.deviceID,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('JWT 服務回應 ${response.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    return parseSfuGetResponse(json);
  }

  String? _existingLiveKitGroupId(Room targetRoom) {
    final states = targetRoom.states[EventTypes.GroupCallMember];
    if (states == null) {
      return null;
    }
    for (final event in states.values) {
      final id = deriveLiveKitGroupCallIdFromContent(event.content);
      if (id != null) {
        return id;
      }
    }
    return null;
  }

  /// F｜殘留檢查（簡化版）：自己 device 的 livekit membership 已過期（官方
  /// `isExpired`）但 state 未清 → 記 note。SDK 官方 join 路徑會取消 pending
  /// delayed leave（famedly_call_extension.dart L207-245 官方行為）並以
  /// enter 改寫自己的成員 state，實質清理由 SDK 包辦；此處僅透明化記錄。
  void _inspectStaleMembership(Room targetRoom) {
    try {
      final voip = _voip;
      final userId = client.userID;
      final deviceId = client.deviceID;
      if (userId == null || deviceId == null) {
        return;
      }
      for (final mem in targetRoom.getCallMembershipsForUser(userId, deviceId, voip)) {
        if (mem.backend is LiveKitBackend) {
          final note = 'own expired=${mem.isExpired} callId=${mem.callId}';
          debugPrint('[LiveKit] stale membership: $note');
          if (mem.isExpired) {
            staleMembershipNote = note;
          }
        }
      }
    } catch (_) {
      // 研究診斷用途，任何失敗不擋加入流程。
    }
  }

  // ---- lk Room 事件 --------------------------------------------------------

  void _subscribeRoomEvents(lk.Room lkRoom) {
    void touch() => notifyListeners();
    _listenCancels
      ..add(lkRoom.events.on<lk.ParticipantConnectedEvent>((_) {
        _sawARemoteParticipant = true;
        _stopOthersLeftCountdown(); // 有人加入 → 取消倒數
        touch();
      }))
      ..add(
        lkRoom.events.on<lk.ParticipantDisconnectedEvent>((_) {
          _checkOthersLeft();
          touch();
        }),
      )
      ..add(lkRoom.events.on<lk.TrackSubscribedEvent>((_) => touch()))
      ..add(lkRoom.events.on<lk.TrackUnsubscribedEvent>((_) => touch()))
      ..add(lkRoom.events.on<lk.TrackMutedEvent>((_) => touch()))
      ..add(lkRoom.events.on<lk.TrackUnmutedEvent>((_) => touch()))
      ..add(lkRoom.events.on<lk.LocalTrackPublishedEvent>((_) => touch()))
      ..add(lkRoom.events.on<lk.LocalTrackUnpublishedEvent>((_) => touch()))
      // 音量表（說話人高亮）：lk 官方 ActiveSpeakersChangedEvent。
      ..add(
        lkRoom.events.on<lk.ActiveSpeakersChangedEvent>((event) {
          activeSpeakerIdentities =
              event.speakers.map((p) => p.identity).toSet();
          touch();
        }),
      )
      // 連線品質（自身）：poor/lost → UI 顯示「重新加入」。
      ..add(
        lkRoom.events.on<lk.ParticipantConnectionQualityUpdatedEvent>((event) {
          final local = lkRoom.localParticipant;
          if (local != null && identical(event.participant, local)) {
            ownQuality = event.connectionQuality;
            touch();
          }
        }),
      )
      ..add(
        lkRoom.events.on<lk.RoomDisconnectedEvent>((_) {
          if (phase == LiveKitCallPhase.connected ||
              phase == LiveKitCallPhase.joining) {
            errorMessage = '連線已中斷'; // 文案草案
            statusText = null;
            phase = LiveKitCallPhase.error;
            notifyListeners();
          }
        }),
      )
      // 第三十二批⑥：表情符號（官方 publishData 資料通路；topic 過濾）。
      ..add(
        lkRoom.events.on<lk.DataReceivedEvent>((event) {
          if (event.topic != liveKitReactionTopic) {
            return;
          }
          final decoded = liveKitReactionDecode(event.data);
          if (decoded == null) {
            return;
          }
          _addReaction(decoded.identity, decoded.emoji);
        }),
      );
  }

  // ---- 第三十一批 B：其他人已離開 → 倒數自動退出 ---------------------------

  /// 觸發條件（第三十二批修：人類實測「20 秒倒數沒有出現」）：曾至少有
  /// 1 位遠端參與者加入過（_sawARemoteParticipant），此刻 lk 遠端全空。
  /// 原第二重確認（SDK 成員狀態 gc.participants）移除——famedly 成員 state
  /// 的清除走延遲事件（delayed leave），實機會殘留數十秒，把倒數整個擋死。
  /// 改以 lk 端為單一事實來源；「發起人獨自等待不誤掛」由
  /// _sawARemoteParticipant 旗標守住。倒數 20 秒（人類拍板），期間有人加入
  /// 即取消；或手動離開。
  void _checkOthersLeft() {
    final lkRoom = _room;
    if (lkRoom == null || !_sawARemoteParticipant) {
      return;
    }
    if (phase != LiveKitCallPhase.connected) {
      return;
    }
    if (lkRoom.remoteParticipants.isNotEmpty) {
      _stopOthersLeftCountdown();
      return;
    }
    _startOthersLeftCountdown();
  }

  /// 倒數規則純函式（可單元測試）：任一條件不滿足 → 不倒數。
  static bool othersLeftShouldCountdown({
    required bool sawRemoteParticipant,
    required int remoteParticipantCount,
    required bool connected,
  }) =>
      sawRemoteParticipant &&
      connected &&
      remoteParticipantCount == 0;

  void _startOthersLeftCountdown() {
    final timer = _othersLeftTimer;
    if (timer != null) {
      return; // 已在倒數。
    }
    othersLeftCountdown = 20;
    notifyListeners();
    _othersLeftTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = othersLeftCountdown - 1;
      if (next <= 0) {
        t.cancel();
        _othersLeftTimer = null;
        othersLeftCountdown = -1;
        _autoExit();
      } else {
        othersLeftCountdown = next;
        notifyListeners();
      }
    });
  }

  void _stopOthersLeftCountdown() {
    _othersLeftTimer?.cancel();
    _othersLeftTimer = null;
    if (othersLeftCountdown != -1) {
      othersLeftCountdown = -1;
      notifyListeners();
    }
  }

  Future<void> _autoExit() async {
    exitNotice = '其他人已離開，已自動結束通話'; // 文案草案
    await _logCall('completed'); // 與正常離開同款記錄
    await leave(userTerminate: false);
  }

  // ---- 第三十二批⑥：通話表情符號 -------------------------------------------

  /// 目前正在飄的表情符號（全員；含自己）。超過 5 秒自動消失。
  List<({String identity, String emoji})> recentReactions = [];
  final Map<String, Timer> _reactionTimers = {};

  /// 發送表情符號（官方 `publishData` 資料通路；LOSSY 即可，掉一顆無妨）。
  /// 披露：表情符號走 lk 資料通道，**未經 E2EE 幀加密**（v0；內容僅 emoji，
  /// 不含敏感訊息；若要加密需另行設計，屬加密必停區）。
  Future<void> sendReaction(String emoji) async {
    final local = _room?.localParticipant;
    if (local == null || phase != LiveKitCallPhase.connected) {
      return;
    }
    final payload = liveKitReactionEncode(
      emoji: emoji,
      identity: local.identity,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await local.publishData(
        utf8.encode(payload),
        reliable: false,
        topic: liveKitReactionTopic,
      );
      _addReaction(local.identity, emoji); // 自己端也即時飄。
    } catch (e) {
      statusText = '無法傳送表情符號：$e';
    } finally {
      notifyListeners();
    }
  }

  void _addReaction(String identity, String emoji) {
    final key = '$identity|$emoji';
    _reactionTimers.remove(key)?.cancel();
    recentReactions.add((identity: identity, emoji: emoji));
    _reactionTimers[key] = Timer(const Duration(seconds: 5), () {
      _reactionTimers.remove(key);
      recentReactions.removeWhere(
        (r) => r.identity == identity && r.emoji == emoji,
      );
      notifyListeners();
    });
    notifyListeners();
  }

  // ---- 第三十一批：媒體操作門面 -------------------------------------------

  lk.LocalVideoTrack? get localCameraTrack {
    final track =
        _room?.localParticipant?.getTrackPublicationBySource(lk.TrackSource.camera)?.track;
    return track is lk.LocalVideoTrack ? track : null;
  }

  lk.LocalVideoTrack? get localScreenShareTrack {
    final track = _room?.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.screenShareVideo)
        ?.track;
    return track is lk.LocalVideoTrack ? track : null;
  }

  lk.VideoTrack? screenShareTrackOf(lk.Participant participant) {
    final track = participant
        .getTrackPublicationBySource(lk.TrackSource.screenShareVideo)
        ?.track;
    return track is lk.VideoTrack ? track : null;
  }

  /// 該參與者的攝影機視訊軌（遠端或本機；無視訊 → null，UI 顯示頭像）。
  lk.VideoTrack? videoTrackOf(lk.Participant participant) {
    final track =
        participant.getTrackPublicationBySource(lk.TrackSource.camera)?.track;
    return track is lk.VideoTrack ? track : null;
  }

  bool get isScreenSharing {
    final pub = _room?.localParticipant
        ?.getTrackPublicationBySource(lk.TrackSource.screenShareVideo);
    return pub != null && !pub.muted;
  }

  bool get isMicOn => _room?.localParticipant?.isMicrophoneEnabled() ?? false;

  bool get isCamOn => _room?.localParticipant?.isCameraEnabled() ?? false;

  bool get qualityPoor =>
      ownQuality == lk.ConnectionQuality.poor ||
      ownQuality == lk.ConnectionQuality.lost;

  Future<void> toggleMic() async {
    final local = _room?.localParticipant;
    if (local == null) {
      return;
    }
    try {
      await local.setMicrophoneEnabled(!isMicOn);
    } finally {
      notifyListeners();
    }
  }

  Future<void> toggleCam() async {
    final local = _room?.localParticipant;
    if (local == null) {
      return;
    }
    try {
      await local.setCameraEnabled(!isCamOn);
    } finally {
      notifyListeners();
    }
  }

  /// 前後鏡頭切換（官方 `LocalVideoTrack.setCameraPosition`）。
  /// 第三十二批③：上次的選擇記憶於本機 kv（app_settings `lk_camera_front`），
  /// 下次通話自動沿用（預設前鏡頭）；僅本機儲存，不送伺服器。
  bool _cameraFront = true;

  Future<void> _loadCameraPreference() async {
    try {
      final stored = await AppSettings.get('lk_camera_front');
      if (stored == '0') {
        _cameraFront = false;
      }
    } catch (_) {
      // 記憶讀取失敗 → 維持預設（前鏡頭），不擋通話。
    }
  }

  Future<void> flipCamera() async {
    final track = localCameraTrack;
    if (track == null) {
      return;
    }
    try {
      final next = _cameraFront ? lk.CameraPosition.back : lk.CameraPosition.front;
      await track.setCameraPosition(next);
      _cameraFront = next == lk.CameraPosition.front;
      unawaited(
        AppSettings.set('lk_camera_front', _cameraFront ? '1' : '0')
            .catchError((_) {}),
      );
    } catch (e) {
      statusText = '無法切換鏡頭：$e';
    } finally {
      notifyListeners();
    }
  }

  /// 內建放音裝置：喇叭／電話（官方 `AudioManager.setSpeakerOutputPreferred`；
  /// force=true＝選喇叭時不吃掉「有線／藍牙優先」預設）。
  Future<void> setBuiltinSpeaker(bool on) async {
    try {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(on, force: on);
    } catch (e) {
      statusText = '切換放音裝置失敗：$e';
    } finally {
      notifyListeners();
    }
  }

  /// 螢幕分享：
  /// ①官方 `Hardware.requestCapturePermission`（MediaProjection 同意框，
  ///   Android 14+ 必須先取得同意）；
  /// ②既有 `ring/screen_capture` 前景服務（批次 II-b 建置，傳輸層無關）；
  /// ③官方 `setScreenShareEnabled`（共用目前音訊／視訊加密金鑰路徑）。
  Future<void> toggleScreenShare() async {
    final local = _room?.localParticipant;
    if (local == null || phase != LiveKitCallPhase.connected) {
      return;
    }
    final turningOn = !isScreenSharing;
    if (turningOn) {
      bool granted;
      try {
        // SDK 官方將此 API 標記 experimental（CHANGELOG：官方提供給 App 端
        // 啟動螢幕分享同意框，不必自行 import flutter_webrtc）；本批即官方
        // 建議用法，若上游變動則跟隨上游調整。
        granted = await lk.Hardware.instance
            .requestCapturePermission(fullScreenOnly: true); // ignore: experimental_member_use
      } catch (e) {
        statusText = '無法啟動螢幕分享同意流程：$e';
        notifyListeners();
        return;
      }
      if (!granted) {
        statusText = '未授權螢幕錄製'; // 文案草案
        notifyListeners();
        return;
      }
      try {
        await const MethodChannel('homing/screen_capture').invokeMethod('start');
      } on PlatformException catch (e) {
        statusText = '無法啟動螢幕分享服務：${e.message}';
        notifyListeners();
        return;
      }
    }
    try {
      await local.setScreenShareEnabled(turningOn);
    } catch (e) {
      statusText = '螢幕分享失敗：$e';
      try {
        await const MethodChannel('homing/screen_capture').invokeMethod('stop');
      } catch (_) {}
    } finally {
      // 第三十二批④：通知狀態即時更新（正在分享螢幕 ↔ 通話進行中）。
      unawaited(_updateCallService());
      notifyListeners();
    }
  }

  // ---- 第三十二批：通話通知（前景服務）生命週期 ------------------------------

  Future<void> _startCallService() async {
    try {
      await const MethodChannel('homing/call_service').invokeMethod('start', {
        'status': nativeCallServiceStatus,
        'room_id': _targetRoom?.id ?? '',
      });
    } catch (_) {}
  }

  Future<void> _updateCallService() async {
    try {
      await const MethodChannel('homing/call_service').invokeMethod('update', {
        'status': nativeCallServiceStatus,
        'room_id': _targetRoom?.id ?? '',
      });
    } catch (_) {}
  }

  /// 通知狀態文案（對應原生 `ring_call_status` extra：active/share）。
  String get nativeCallServiceStatus => isScreenSharing ? 'share' : 'active';

  Future<void> _stopCallService() async {
    try {
      await const MethodChannel('homing/call_service').invokeMethod('stop');
    } catch (_) {}
  }

  /// 停止螢幕分享（離場時收尾呼叫）。
  Future<void> _stopScreenShareService() async {
    try {
      await const MethodChannel('homing/screen_capture').invokeMethod('stop');
    } catch (_) {}
  }

  /// E｜「重新加入」：官方 leave＋join 重跑（lk 重連與成員 state 重寫）。
  Future<void> rejoin() async {
    final room = _targetRoom;
    if (room == null) {
      return;
    }
    await leave(userTerminate: false);
    await join(room);
  }

  // ---- 離場 ---------------------------------------------------------------

  /// 掛斷：成員 state 撤回（SDK gc.leave 官方包辦）＋ lk Room 清理。
  /// [userTerminate]＝使用者明確掛斷（寫通話記錄）；自動退出時會先自行記錄。
  Future<void> leave({bool userTerminate = true}) async {
    if (userTerminate && _connectedAt != null) {
      await _logCall('completed');
    }
    phase = LiveKitCallPhase.left;
    statusText = null;
    notifyListeners();
    await _cleanup();
    callManager.clearLiveKit(this);
  }

  /// 通話記錄（與 mesh 群組通話同款格式；一次連線只記一筆）。
  Future<void> _logCall(String outcome) async {
    if (_callLogged || _connectedAt == null) {
      return;
    }
    _callLogged = true;
    final room = _targetRoom;
    final started = _connectedAt!;
    final duration = DateTime.now().difference(started).inMilliseconds;
    final name = room?.name.isNotEmpty ?? false ? room!.name : (room?.id ?? '');
    try {
      await CallLog.add(
        direction: 'group',
        peerId: room?.id ?? '',
        peerName: name,
        roomId: room?.id ?? '',
        isGroup: true,
        startedAt: started,
        durationMs: duration < 0 ? 0 : duration,
        outcome: outcome,
      );
    } catch (_) {
      // 記錄失敗不擋離開流程。
    }
  }

  void _resetSessionState() {
    _targetRoom = null;
    _groupCall = null;
    _connectedAt = null;
    _callLogged = false;
    _sawARemoteParticipant = false;
    activeSpeakerIdentities = {};
    ownQuality = lk.ConnectionQuality.unknown;
    _stopOthersLeftCountdown();
    staleMembershipNote = null;
    statusText = null;
    errorMessage = null;
  }

  Future<void> _cleanup() async {
    // D｜wake lock 關閉。
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    // 第三十二批④：通知（前景服務）結束即消失；清除最近的表情符號飄浮。
    await _stopCallService();
    recentReactions.clear();
    _reactionTimers.clear();
    // 螢幕分享前景服務收尾。
    if (isScreenSharing) {
      await _stopScreenShareService();
    }
    keyProvider.attachRoom(null);
    for (final cancel in List.of(_listenCancels)) {
      try {
        await cancel();
      } catch (_) {}
    }
    _listenCancels.clear();
    final lkRoom = _room;
    _room = null;
    if (lkRoom != null) {
      try {
        await lkRoom.disconnect();
      } catch (_) {}
      try {
        await lkRoom.dispose();
      } catch (_) {}
    }
    final gc = _groupCall;
    _groupCall = null;
    if (gc != null) {
      try {
        await gc.leave();
      } catch (_) {
        // 官方 leave 已可能設 delayed event；失敗不鳥（v0 伺服器端會逾時撤）。
      }
    }
  }

  @override
  void dispose() {
    unawaited(leave(userTerminate: false));
    super.dispose();
  }

  void _set({
    required LiveKitCallPhase phase,
    String? statusText,
  }) {
    this.phase = phase;
    this.statusText = statusText;
    notifyListeners();
  }
}

/// 供 UI 顯示的參與者名（identity=`<userId>:<deviceId>` → 顯示 userId 本地段）。
/// 磚塊文案草案，待人類設計定稿。
String liveKitTileLabel(lk.Participant participant) {
  final identity = participant.identity;
  if (identity.isNotEmpty) {
    return identity;
  }
  return participant.name.isNotEmpty ? participant.name : '…';
}

// ---- 第三十二批⑥：表情符號 payload（公開純函式，供單元測試）--------------

/// 資料通路 topic（send 與 receive 過濾用同一值）。
const String liveKitReactionTopic = 'ring.reaction';

/// 編碼表情符號 payload：`{"kind":"reaction","emoji":...,"identity":...,"ts":...}`。
String liveKitReactionEncode({
  required String emoji,
  required String identity,
  required int ts,
}) =>
    jsonEncode({
      'kind': 'reaction',
      'emoji': emoji,
      'identity': identity,
      'ts': ts,
    });

/// 解碼表情符號 payload；kind 不符／缺欄位 → null（接收端不瞎猜直接丟棄）。
({String identity, String emoji})? liveKitReactionDecode(List<int> data) {
  try {
    final json = jsonDecode(utf8.decode(data));
    if (json is! Map) {
      return null;
    }
    final kind = json['kind'];
    final emoji = json['emoji'];
    final identity = json['identity'];
    if (kind != 'reaction' || emoji is! String || identity is! String) {
      return null;
    }
    if (emoji.isEmpty || identity.isEmpty) {
      return null;
    }
    return (identity: identity, emoji: emoji);
  } on FormatException {
    return null;
  } on Object {
    return null;
  }
}
