// UI 重構（依人類 LINE_ref 標註，2026-11-01）— 主殼：底部導航 tab。
// 批次 G（人類批准，2026-11-02）：4 tab（聊天／聯絡人／通話／設定）；
// 通話 tab 為空骨架（僅入口占位）。底列改 Element X 式**膠囊列**（形狀／結構
// 依人類參考圖；色彩一律取自 Homing 主題種子色，**不採 Element 綠／品牌色**）。
// 「＋新增」不在底列：置頂列右側（LINE 版面位置，人類決定）。
// 斷點：DESIGN.md §1 — compact（<600dp）為底部分頁列；medium/expanded 版面屬 Phase 7。
// 樣式＝草案，待人類設計定稿（design/tokens.md 未填 → 沿用種子色）。
// 第三十四批（人類需求 #2，2026-11-12）：來電通知改**側邊橫幅**（root overlay，
// 不擋底下畫面；可接聽／拒接／點擊展開全螢幕），偏好關閉時僅系統通知欄提示。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import '../call_log.dart';
import '../app_settings.dart';
import '../message_content.dart' show isSilentMessage; // 第三十五批 #5
import '../engine_init.dart' show kRustEngineErrorKey; // 第二十七批：引擎狀態旗標
import '../emergency_feed.dart'; // 批次十六：PWS RSS 緊急示警（官方 NCDR feed）
import '../share_receiver.dart'; // 第二十六批：外部分享（文字／檔案 payload）
import '../push/push_runtime.dart';
import '../voip/call_manager.dart';
import 'call_screen.dart';
import 'chat_screen.dart'; // 批次十四：點開通知進對應聊天室
import 'contacts_screen.dart';
import 'design_tokens.dart';
import 'group_call_screen.dart';
import 'livekit_call_screen.dart'; // 第三十二批④：點通話通知回通話畫面
import 'notification_settings_screen.dart'; // 批次十二②偏好執行緒
import 'rooms_screen.dart';
import 'emergency_flow_screen.dart'; // 第三十五批 #6：緊急求助流程
import 'share_to_room_screen.dart'; // 批次十三：「Send to」picker（二十六批吃 payload）
typedef ContactsLoader = Future<List<Room>> Function(Client client);

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.client,
    this.loadRooms,
    this.loadContacts,
    this.onLogout,
    this.callManager,
  });

  final Client client;
  final RoomsLoader? loadRooms;
  final ContactsLoader? loadContacts;
  final Future<void> Function(Client client)? onLogout;

  /// 通話管理（P2.15 提案）。缺省時由殼自建；測試可注入以避免初始化 WebRTC 平台層。
  final CallManager? callManager;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  bool _ownCallManager = false;
  bool _initFailureShown = false;

  /// 第二十七批：Rust 引擎初始化失敗提示已顯示旗標（一次 session 一次）。
  bool _engineWarnShown = false;
  late final CallManager callManager;

  /// 批次十二②修：POST_NOTIFICATIONS 被拒旗標（授予後由權限執行緒解除，
  /// 不再永久 cancel 輪詢訂閱）。
  bool _notifyPermDenied = false;

  static const _notifyChannel = MethodChannel('homing/local_notifications');

  StreamSubscription? _notifSync;

  /// notification_id → 已通知的 notificationCount（去重；同一則不再重發）。
  final Map<String, int> _notifiedCounts = {};

  // 第三十四批（人類需求 #2）：來電橫幅 overlay entry（root overlay）與
  // 「橫幅關閉＝僅通知欄提示」時已發的本地通知 room id（通話結束取消用）。
  OverlayEntry? _incomingBannerEntry;
  String? _incomingNotifiedRoom;

  // 批次十六：PWS RSS 緊急示警（官方 NCDR 聚合 feed；僅首頁橫幅、不彈
  // 通知＝人類決定 2026-11-07）。Timer.periodic 老舊 API 於 widget 測試會
  // 掛「Timer 仍 pending」→ 測試環境（FLUTTER_TEST）不啟動輪詢。
  Timer? _emergencyTimer;
  List<EmergencyAlert> _emergencyAlerts = const [];
  String _lastEmergencyFp = '';

  /// 第三十五批 #6：已彈過／已關閉的緊急求助流程 alert id（session 內去重；
  /// 同一則示警只問一次「需要幫忙嗎？」）。
  final Set<String> _emergencyFlowShownIds = {};

  /// 批次十二②修：權限授予 → 解除被拒旗標＋立即補一輪。_maybeNotify 自帶
  /// lifecycle／去重判斷；修復「事後去系統設定授權仍要重開 App」的舊行為。
  void _onNotificationPermissionChanged() {
    if (ringNotificationPermission.value == true && _notifyPermDenied) {
      _notifyPermDenied = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _ownCallManager = widget.callManager == null;
    // 批次十二②：啟動即還原通知偏好（總開關／訊息內容顯示／系統權限現狀）。
    unawaited(loadNotificationPrefs());
    ringNotificationPermission.addListener(_onNotificationPermissionChanged);
    // 批次十四：讀回持久化的「已通知 count」（per room），避免重開 App
    // 後把「靜音前已收、未彈過」的舊訊息重新彈出（main_shell L67）。
    unawaited(_restoreNotifiedCounts());
    // 批次十六：進殼即抓一次 PWS 示警，之後每 15 分鐘（僅前景，人類決定）。
    _startEmergencyPolling();
    // 批次十四：原生通知欄「已讀／回覆／開啟房間」動作由 MainActivity
    // 轉發至此（MethodChannel invokeMethod "notification_action"）。
    _notifyChannel.setMethodCallHandler((call) async {
      if (call.method == 'notification_action') {
        final args = call.arguments;
        if (args is Map) {
          await _onNotifAction(Map<String, dynamic>.from(args));
        }
      }
      return null;
    });
    callManager = widget.callManager ?? CallManager(client: widget.client);
    if (_ownCallManager) {
      callManager.ensureInit();
      if (callManager.callSupportError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _initFailureShown) {
            return;
          }
          _initFailureShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('通話功能不可用：${callManager.callSupportError}'),
            ),
          );
        });
      }
    }
    callManager.incomingCall.addListener(_onIncomingChange);
    callManager.incomingGroupCall.addListener(_onIncomingGroupChange);
    // 第二十七批（人類拍板）：Rust 加密引擎本 session 初始化失敗時明確
    // 提示（kv 旗標由 engine_init.dart 記錄；成功即清＝無旗標不打擾）。
    unawaited(_notifyRustEngineStatus());
    // 第 2 點：監聽外部分享接收，彈出「選擇聊天室」並轉發內容。
    unawaited(_listenShareReceiver());
    // Suggestion #5（人類決定 2026-11-05「走 local」）：本地通知 v0——
    // sync 到新訊息且 **app 不在前景**時發 Android 本地通知（零 pub 依賴；
    // 進程被殺即無推播＝無 FCM 的固有限制，PROGRESS.md 已披露）。
    _notifSync = widget.client.onSync.stream.listen((_) => unawaited(_maybeNotify()));
    // 任務 3 批次 A（人類批准 2026-11-07）：進主殼＝已登入 → 偵測 UP
    // distributor 並註冊（Android；無 distributor／非 Android 靜默 no-op，
    // 內部單次守衛；失敗不影響 App，見 push_runtime.dart 檔頭）。
    unawaited(RingPushRuntime.init(widget.client));
  }

  Future<void> _maybeNotify() async {
    // 批次十二②修：權限被拒旗標（不再永久 cancel；授予後解除）。
    if (_notifyPermDenied) {
      return;
    }
    // 批次十二②：通知設定總開關（通知設定頁；關＝完全不發本地通知）。
    if (!ringNotificationsEnabled.value) {
      return;
    }
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      // sky only App 非前景時才通知（前景顯SnackBar／既有差異 UI 便已足夠）。
      for (final room in widget.client.rooms) {
        if (room.notificationCount <= 0) {
          continue;
        }
        if (_notifiedCounts[room.id] != null &&
            _notifiedCounts[room.id] == room.notificationCount) {
          continue; // 同一則（count 未變）不重發
        }
        final before = _notifiedCounts[room.id];
        _notifiedCounts[room.id] = room.notificationCount;
        // 第三十五批 #5：無聲訊息（App 層約定旗標 dev.homing.silent）→
        // 跳過通知；仍記錄 count（該輪視為已處理；下輪 count 再變動照常評估）。
        if (isSilentMessage(room.lastEvent)) {
          unawaited(
            AppSettings.set(
              'notif_count_${room.id}',
              room.notificationCount.toString(),
            ),
          );
          continue;
        }
        // 批次十四：寫入即持久化（per room），重開 App 不會重發舊 count。
        unawaited(
          AppSettings.set('notif_count_${room.id}', room.notificationCount.toString()),
        );
        String title;
        try {
          title = room.getLocalizedDisplayname();
          if (title == 'Empty chat') {
            title = room.id;
          }
        } catch (_) {
          title = room.id;
        }
        // 批次十二②：「顯示訊息內容」關＝通知正文隱藏（同 LINE Message previews）。
        final body = ringNotificationPreview.value
            ? (room.lastEvent?.body ?? '新訊息') // 文案草案
            : '新訊息'; // 文案草案
        try {
          final ok = await _notifyChannel.invokeMethod<bool>('show', {
            'title': title,
            'body': body,
            'room': room.id,
          });
          if (ok == false) {
            // 無 POST_NOTIFICATIONS runtime 權限：批次十二②修——舊版把
            // `_notifSync` 永久 cancel，即使事後去系統設定授權也要重開 App。
            // 改旗標＋權限執行緒（授予即解除＝重新武裝，人類實測路徑）。
            _notifyPermDenied = true;
            unawaited(checkNotificationPermission().then((g) {
              ringNotificationPermission.value = g;
            }));
            _notifiedCounts[room.id] = before ?? room.notificationCount;
            // 回滾 kv（權限未授權，不應標記為已通知）。
            if (before == null) {
              unawaited(AppSettings.remove('notif_count_${room.id}').catchError((_) {}));
            } else {
              unawaited(
                AppSettings.set('notif_count_${room.id}', before.toString())
                    .catchError((_) {}),
              );
            }
            return;
          }
        } catch (_) {
          // 平台不支援／channel 未初始化：靜默（v0 行為）。
        }
      }
    }
  }

  StreamSubscription? _shareSub;

  Future<void> _listenShareReceiver() async {
    // 第二十六批（人類拍板）：冷啟動分享由 MainActivity native 暫存——
    // MainShell 首掛即讀取（未登入時 Homing 停在登入頁、MainShell 不存在＝
    // 分享留在 native 暫存，登入完成 MainShell 掛起自動開 picker）。
    // 熱啟動（onNewIntent）經 `ring/share` → main.dart 廣播流。
    final initial = await readInitialShare();
    if (initial != null && mounted) {
      await _openShare(initial);
    }
    await for (final payload in shareReceiverStream) {
      if (!mounted) return;
      await _openShare(payload);
    }
  }

  Future<void> _openShare(SharePayload payload) async {
    if (payload.isEmpty) {
      return;
    }
    // 批次十三（人類批准 2026-11-07；參考 EX 截圖 share_EX/_labeled.png）：
    // EX 式「Send to」房間選擇器（搜尋＋多選 checkbox＋右上送出）；二十六批
    // 起檔案走與聊天頁附件同一官方鏈（sendFileEvent，見 picker 檔頭）。
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShareToRoomScreen(client: widget.client, payload: payload),
      ),
    );
  }

  @override
  void dispose() {
    callManager.incomingCall.removeListener(_onIncomingChange);
    callManager.incomingGroupCall.removeListener(_onIncomingGroupChange);
    ringNotificationPermission.removeListener(_onNotificationPermissionChanged);
    _shareSub?.cancel();
    _notifSync?.cancel(); // Suggestion #5 local notifications v0
    _emergencyTimer?.cancel(); // 批次十六：PWS 示警輪詢
    // 第三十四批：主殼移除時一併收掉來電橫幅（避免 entry 殘留）。
    _removeIncomingBanner();
    if (_ownCallManager) {
      callManager.dispose();
    }
    super.dispose();
  }

  // 批次十六：PWS 示警輪詢（僅 App 前景；後台 Dart timer 會被系統凍結，
  // 不另做背景服務＝無 FCM 限制的既定披露延續）。進殼即抓一次＋每 15 分鐘。
  // widget 測試環境（FLUTTER_TEST）不啟動，避免 pending Timer 與網路。
  void _startEmergencyPolling() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    unawaited(_pollEmergency());
    _emergencyTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(_pollEmergency()),
    );
  }

  Future<void> _pollEmergency() async {
    try {
      final alerts = await fetchEmergencyAlerts();
      if (!mounted) {
        return;
      }
      // entry id 指紋：無變化不 setState（對齊 _loadEmergency 模式）。
      final fp = alerts.map((a) => a.id).join('|');
      if (fp == _lastEmergencyFp) {
        return;
      }
      _lastEmergencyFp = fp;
      setState(() => _emergencyAlerts = alerts);
      // 第三十五批 #6：緊急求助流程——地震／颱風類**新**示警（id 未彈過）
      // → 開流程畫面「需要幫忙嗎？」。否／取消後同 id 本 session 不再彈
      //（_emergencyFlowShownIds；一次輪詢最多開一個，避免示警潮連環彈窗）。
      for (final a in alerts) {
        if (isEmergencyFlowAlert(a) &&
            !_emergencyFlowShownIds.contains(a.id)) {
          _emergencyFlowShownIds.add(a.id);
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EmergencyFlowScreen(client: widget.client, alert: a),
              ),
            ),
          );
          break;
        }
      }
    } on Object {
      // 靜默：失敗保原狀，下次輪詢重試（不重試轟炸）。
    }
  }

  // 批次十四：啟動時把「已通知的 count」從 app_settings.db kv 讀回（per room）。
  // 避免重開 App 後，_notifiedCounts 為空，把「靜音前已收但未彈過」的舊
  // 第二十七批（人類拍板）：讀 kv 旗標（engine_init.dart 寫入；成功即清）
  // → 本掛載僅在「失敗旗標存在」時提示一次。無旗標＝引擎正常，不出聲。
  Future<void> _notifyRustEngineStatus() async {
    String? err;
    try {
      err = await AppSettings.get(kRustEngineErrorKey);
    } catch (_) {
      // kv 讀取失敗（測試環境等）＝不打擾。
      return;
    }
    if (!mounted || err == null || _engineWarnShown) {
      return;
    }
    _engineWarnShown = true;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '加密引擎未就緒：加密／驗證功能可能無法使用（$err）。請重啟 Homing；若重現請回報。',
        ),
      ),
    );
  }

  // 訊息重新彈出（即「軟體重開後一直跳出靜音前收到的通知」的根因）。
  Future<void> _restoreNotifiedCounts() async {
    try {
      // kv 只能讀單一 key；這裡以 notif_count_<roomId> 儲存。rooms 尚未載入時
      // 先不做（_rooms 由 RoomsScreen 獨立管理），改由 _maybeNotify 寫入時
      // 即時持久化；此處只做「一次性讀回」保護（下次重開才生效）。
      // 採「寫入即持久化，讀取由 _maybeNotify 的首次比對補齊」策略：
      // 若 kv 有值但記憶體為空，則以 kv 值為準（避免重發）。
      for (final room in widget.client.rooms) {
        final v = await AppSettings.get('notif_count_${room.id}');
        if (v != null) {
          final n = int.tryParse(v);
          if (n != null) {
            _notifiedCounts[room.id] = n;
          }
        }
      }
    } on Object {
      // 無 DB 環境（測試）或讀取失敗：記憶體為空，下次有新訊息才會彈。
    }
  }

  // 批次十四：原生通知欄點選「已讀／回覆／開啟房間」後由 MainActivity
  // 轉發至此（MethodChannel 'homing/local_notifications' method "notification_action"）。
  Future<void> _onNotifAction(Map<String, dynamic> args) async {
    final action = args['action'] as String?;
    final roomId = args['room_id'] as String?;
    final replyText = args['reply_text'] as String?;
    if (roomId == null || action == null) {
      return;
    }
    final room = widget.client.rooms.firstWhere(
      (r) => r.id == roomId,
      orElse: () => throw StateError('room not found: $roomId'),
    );
    switch (action) {
      case 'read':
        // 已讀：官方 setReadMarker（每 read 恆送 public+private receipt；
        // client.dart receiptsPublicByDefault=true），並取消該房間通知。
        try {
          final last = room.lastEvent;
          if (last != null) {
            await room.setReadMarker(last.eventId);
          }
        } on Object {
          // 失敗不洗版；靜默。
        }
        break;
      case 'reply':
        // 回覆：官方 Room.sendTextEvent（加密房 SDK 自動加密，App 端不介入）。
        if (replyText != null && replyText.isNotEmpty) {
          try {
            await room.sendTextEvent(replyText);
          } on Object {
            // 發送失敗不洗版。
          }
        }
        break;
      case 'open':
        // 開啟聊天室：直接 push 對應的 ChatScreen（不須先進軟體首頁）。
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(
                room: room,
                callManager: callManager,
              ),
            ),
          );
        }
        break;
      case 'open_call':
        // 第三十二批②：點通話通知 → 直接回到通話畫面（同一 Flutter 主頁；
        // 通話 session 由 CallManager 持有，重入只會重用、不會重新加入）
        // （草案：尚未處理 PiP 中點入的展開，僅一般返回路徑，待人類設計）。
        if (mounted) {
          unawaited(
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => LiveKitCallScreen(
                  room: room,
                  manager: callManager,
                ),
              ),
            ),
          );
        }
        break;
    }
    // 任何動作後都取消該房間通知＋清記憶體，避免重複彈。
    try {
      await _notifyChannel.invokeMethod<bool>('cancel', {'room': roomId});
    } catch (_) {}
    _notifiedCounts.remove(roomId);
    unawaited(AppSettings.remove('notif_count_$roomId').catchError((_) {}));
  }

  /// 接聽後靠 CallScreen 自行監聽 session 狀態；來電彈出全螢幕 route（草案；
  /// 背景／鎖屏時的 FCM 推播不在本批，見 PROGRESS.md 記錄）。
  /// 遠端發起的群組通話 → 全螢幕 route 顯示（草案）。
  /// **第三十四批改（人類需求 #2「來電通知在旁邊出現，可選擇是否隱藏」）**：
  /// 自動彈全螢幕的行為由**側邊橫幅**（root overlay，不擋底下畫面）取代——
  /// 開＝橫幅（接聽／拒接／點擊展開全螢幕）；關＝不顯示橫幅，僅以既有本地
  /// 通知 channel 提示（v0 披露：通知「開啟」＝進聊天室，通話續用聊天室
  /// 通話鈕回到通話狀態——批次 II-e 同房間重用鏈）。同時移除舊
  /// `activeCall == session` guard：`_onNewCall` 先設 `activeCall` 才設
  /// `incomingCall.value`，該 guard 恆真（1:1 來電本就無法自動彈出）。
  void _onIncomingChange() {
    final session = callManager.incomingCall.value;
    if (session == null) {
      // 橫幅關閉由 _IncomingBannerHost 統一處理（兩來電 notifier 皆空才移除）。
      unawaited(_cancelIncomingCallNotification());
      return;
    }
    if (!mounted) {
      return;
    }
    if (ringIncomingCallBanner.value) {
      _showIncomingBanner();
      return;
    }
    unawaited(_postIncomingCallNotification(session.room, '來電'));
  }

  void _onIncomingGroupChange() {
    final gc = callManager.incomingGroupCall.value;
    if (gc == null) {
      // 橫幅關閉由 _IncomingBannerHost 統一處理（兩來電 notifier 皆空才移除）。
      unawaited(_cancelIncomingCallNotification());
      return;
    }
    if (!mounted) {
      return;
    }
    if (ringIncomingCallBanner.value) {
      _showIncomingBanner();
      return;
    }
    unawaited(_postIncomingCallNotification(gc.room, '群組通話邀請'));
  }

  // ─── 第三十四批：來電橫幅（root overlay）＋通知欄提示路徑 ───

  /// 顯示來電橫幅（已開則略過；單一橫幅 v0＝不疊第二則）。
  void _showIncomingBanner() {
    if (_incomingBannerEntry != null || !mounted) {
      return;
    }
    try {
      final entry = OverlayEntry(
        builder: (_) => _IncomingBannerHost(
          manager: callManager,
          onDismiss: _removeIncomingBanner,
          onAccept: () => unawaited(_acceptIncoming()),
          onDecline: () => unawaited(_declineIncoming()),
          onExpandCall: _expandIncoming,
          onJoinGroup: _joinIncomingGroup,
          onIgnoreGroup: _ignoreIncomingGroup,
        ),
      );
      _incomingBannerEntry = entry;
      Overlay.of(context, rootOverlay: true).insert(entry);
    } catch (_) {
      // 無 root overlay（測試環境等）：靜默；來電仍可由聊天室通話鈕接聽。
      _incomingBannerEntry = null;
    }
  }

  void _removeIncomingBanner() {
    final entry = _incomingBannerEntry;
    _incomingBannerEntry = null;
    if (entry == null) {
      return;
    }
    try {
      entry.remove();
    } catch (_) {
      // entry 已被移除（teardown 競態）：靜默。
    }
  }

  /// 橫幅關閉（偏好 off）時的來電提示：既有本地通知 channel（草案）。
  /// 通話結束時取消；與訊息通知共用同一通知 id（roomKey.hashCode）＝後到
  /// 覆蓋先到的（原生 channel v0 限制，披露）。
  Future<void> _postIncomingCallNotification(Room room, String body) async {
    if (_incomingNotifiedRoom == room.id) {
      return; // 同一通只提示一次。
    }
    _incomingNotifiedRoom = room.id;
    try {
      await _notifyChannel.invokeMethod<bool>('show', {
        'title': _incomingCallDisplayName(room),
        'body': body, // 文案草案
        'room': room.id,
      });
    } catch (_) {
      // 非 Android／channel 未初始化（測試環境）：靜默。
    }
  }

  Future<void> _cancelIncomingCallNotification() async {
    final roomId = _incomingNotifiedRoom;
    if (roomId == null) {
      return;
    }
    _incomingNotifiedRoom = null;
    try {
      await _notifyChannel.invokeMethod<bool>('cancel', {'room': roomId});
    } catch (_) {
      // 測試環境等：靜默。
    }
  }

  /// 第三十四批：橫幅「接聽」——官方 answerCurrent 後收橫幅、展開全螢幕
  /// 通話畫面（CallScreen 自行監聽 session 狀態；既有鏈路）。
  Future<void> _acceptIncoming() async {
    final session =
        callManager.incomingCall.value ?? callManager.activeCall;
    if (session == null) {
      return;
    }
    try {
      await callManager.answerCurrent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接聽失敗：$e')), // 文案草案
        );
      }
    }
    _removeIncomingBanner();
    if (!mounted || callManager.activeCall != session) {
      return;
    }
    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: session, manager: callManager),
          fullscreenDialog: true,
        ),
      ),
    );
  }

  /// 第三十四批：橫幅「拒接」——官方 rejectCurrent（橫幅隨 notifier 清空自關）。
  Future<void> _declineIncoming() async {
    try {
      await callManager.rejectCurrent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拒接失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 第三十四批：橫幅點擊展開——收橫幅後開全螢幕通話畫面（未接聽；畫面內
  /// 仍可接聽／拒接）。
  void _expandIncoming(CallSession session) {
    _removeIncomingBanner();
    if (!mounted || callManager.activeCall != session) {
      return;
    }
    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: session, manager: callManager),
          fullscreenDialog: true,
        ),
      ),
    );
  }

  /// 第三十四批：群組橫幅「加入」／點擊展開——收橫幅後開群組通話畫面
  /// （加入按鈕在畫面內；沿用原全螢幕 route 鏈路）。
  void _joinIncomingGroup(GroupCallSession gc) {
    _removeIncomingBanner();
    if (!mounted) {
      return;
    }
    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              GroupCallScreen(groupCall: gc, manager: callManager),
          fullscreenDialog: true,
        ),
      ),
    );
  }

  /// 第三十四批：群組橫幅「忽略」——不加入（mesh 群通無拒接協定操作；
  /// 對方會在逾時後收掉，v0 披露）。
  void _ignoreIncomingGroup(GroupCallSession gc) {
    callManager.clearGroupCall(gc);
  }

  @override
  Widget build(BuildContext context) {
    // 第三十五批 #1（Web/desktop；DESIGN.md §1 斷點策略）：視窗寬度
    // ≥ 600 dp（medium／expanded）＝側欄導航（Material 3 NavigationRail，
    // 草案樣式待人類定稿）取代底部膠囊列；< 600 dp（compact）維持既有
    // 膠囊列。藍圖 §三B 的雙欄聊天版面屬 Phase 4／7 UI 定稿範圍，本批
    // 僅做導航形狀切換（單欄內容＋側欄）。
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final body = IndexedStack(
      index: _tab,
      children: [
        RoomsScreen(
          client: widget.client,
          loadRooms: widget.loadRooms,
          onLogout: widget.onLogout,
          callManager: callManager,
          emergencyAlerts: _emergencyAlerts, // 批次十六：PWS 示警橫幅
        ),
        ContactsScreen(
          client: widget.client,
          loadContacts: widget.loadContacts,
          callManager: callManager,
        ),
        // 第二十二批（LINE_ref calls 稿）：通話 tab＝大標題＋tile 重排
        // ＋每列電話鈕（一對一重撥）。注入 client／呼叫管理重撥。
        _CallsTab(client: widget.client, callManager: callManager),
        // 第二十五批（人類拍板「是」）：底列設定 tab 移除（4→3）——設定
        // 功能整合進首頁左上頭像（RoomsScreen.appBar 頭像 → 面板內嵌
        // SettingsBody）；登出入口由該面板承載。
      ],
    );
    return Scaffold(
      body: wide
          ? Row(
              children: [
                // 側欄（草案；無寫死寬度——Rail 自帶主題預設寬）。
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final tab in _tabs)
                      NavigationRailDestination(
                        icon: Icon(tab.$1),
                        selectedIcon: Icon(tab.$2),
                        label: Text(tab.$3), // 文案待人類設計定稿
                      ),
                  ],
                ),
                Expanded(child: body),
              ],
            )
          : body,
      // 批次 G→H：膠囊列。第二十一批（人類 mockup 2026-11-08＋拍板）：膠囊
      // 底改**淺白 #ECECEC**（SVG 直出；深色＝種子派生 surfaceContainerHigh，
      // 草案）；選中項＝灰 chip 框住圖示、標籤仍常顯。顏色全走 design_tokens。
      // 仍用 Scaffold.bottomNavigationBar（不 extendBody：內容不會被遮擋）。
      // 第三十五批 #1：僅 <600 dp（compact）顯示；≥600 dp 改側欄（上方）。
      bottomNavigationBar: wide
          ? null
          : SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? kPillSurface
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            children: [
              for (final (index, tab) in _tabs.indexed)
                Expanded(
                  child: Tooltip(
                    message: tab.$3, // 文案待人類設計定稿
                    child: InkWell(
                      borderRadius: BorderRadius.circular(36),
                      onTap: () => setState(() => _tab = index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 第二十一批：選中＝灰 chip 框住圖示（mockup 構圖）。
                            Builder(
                              builder: (context) {
                                final icon = Icon(
                                  _tab == index ? tab.$2 : tab.$1,
                                  size: 22,
                                  color: _capsuleItemColor(
                                    context,
                                    selected: _tab == index,
                                  ),
                                );
                                if (_tab != index) {
                                  return icon;
                                }
                                final theme = Theme.of(context);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.brightness == Brightness.light
                                        ? kChipSurface
                                        : theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: icon,
                                );
                              },
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tab.$3, // 草案：文字標籤（人類決定補上）
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                color: _capsuleItemColor(
                                  context,
                                  selected: _tab == index,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 膠囊項前景色（草案）：淺色＝token 文字色（選中主字／未選次要）；深色＝
  /// onSurface 全彩／60% 透明度（狀態對比；主題一致層，非固定色值）。
  Color _capsuleItemColor(BuildContext context, {required bool selected}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (theme.brightness == Brightness.light) {
      return selected ? kTextPrimary : kTextSecondary;
    }
    return selected
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.6);
  }
}

/// 批次 G：4 tab 定義（未選狀態圖示／已選圖示／標籤）。
/// 第二十一批（mockup 2026-11-08）：「聊天」標籤改「聊天室」。
/// 第二十五批（人類拍板「是」）：底列 4→3——「設定」tab 移除（設定整合進
/// 首頁左上頭像）。
const List<(IconData, IconData, String)> _tabs = [
  (Icons.chat_bubble_outline, Icons.chat_bubble, '聊天室'),
  (Icons.person_outline, Icons.person, '聯絡人'),
  (Icons.call_outlined, Icons.call, '通話'),
];

/// 第三十四批：來電顯示名稱（官方 getLocalizedDisplayname；'Empty chat' 退回
/// room.id——與列表既有規則一致）。
String _incomingCallDisplayName(Room room) {
  try {
    final name = room.getLocalizedDisplayname();
    return name == 'Empty chat' ? room.id : name;
  } catch (_) {
    return room.id;
  }
}

/// 第三十四批（人類需求 #2）：來電側邊橫幅 host——掛在 root overlay，
/// 監聽 CallManager 兩個來電 notifier；兩者皆空時回呼 onDismiss 移除
/// overlay entry（不擋底下畫面；樣式草案，待人類設計定稿）。
/// 動作回呼由 MainShell 建立時直接注入（overlay 子樹找不到 MainShell
/// state，不走路徑查找）。
class _IncomingBannerHost extends StatefulWidget {
  const _IncomingBannerHost({
    required this.manager,
    required this.onDismiss,
    required this.onAccept,
    required this.onDecline,
    required this.onExpandCall,
    required this.onJoinGroup,
    required this.onIgnoreGroup,
  });

  final CallManager manager;
  final VoidCallback onDismiss;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final void Function(CallSession session) onExpandCall;
  final void Function(GroupCallSession gc) onJoinGroup;
  final void Function(GroupCallSession gc) onIgnoreGroup;

  @override
  State<_IncomingBannerHost> createState() => _IncomingBannerHostState();
}

class _IncomingBannerHostState extends State<_IncomingBannerHost> {
  @override
  void initState() {
    super.initState();
    widget.manager.incomingCall.addListener(_changed);
    widget.manager.incomingGroupCall.addListener(_changed);
  }

  @override
  void didUpdateWidget(_IncomingBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.manager, widget.manager)) {
      oldWidget.manager.incomingCall.removeListener(_changed);
      oldWidget.manager.incomingGroupCall.removeListener(_changed);
      widget.manager.incomingCall.addListener(_changed);
      widget.manager.incomingGroupCall.addListener(_changed);
    }
  }

  void _changed() {
    final any = widget.manager.incomingCall.value != null ||
        widget.manager.incomingGroupCall.value != null;
    if (!any) {
      widget.onDismiss(); // 移除 overlay entry（不在 build 內執行）。
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.manager.incomingCall.removeListener(_changed);
    widget.manager.incomingGroupCall.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 偏好關閉＝本 entry 不繪製橫幅（來電提示改走通知欄；下次來電生效）。
    if (!ringIncomingCallBanner.value) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
          child: _bannerBody(),
        ),
      ),
    );
  }

  Widget _bannerBody() {
    final session = widget.manager.incomingCall.value;
    if (session != null) {
      return _IncomingBannerCard(
        title: '來電', // 文案草案
        name: _incomingCallDisplayName(session.room),
        primaryLabel: '接聽', // 文案草案
        onPrimary: widget.onAccept,
        secondaryLabel: '拒接', // 文案草案
        onSecondary: widget.onDecline,
        onExpand: () => widget.onExpandCall(session),
      );
    }
    final group = widget.manager.incomingGroupCall.value;
    if (group != null) {
      return _IncomingBannerCard(
        title: '群組通話邀請', // 文案草案
        name: _incomingCallDisplayName(group.room),
        primaryLabel: '加入', // 文案草案
        onPrimary: () => widget.onJoinGroup(group),
        secondaryLabel: '忽略', // 文案草案
        onSecondary: () => widget.onIgnoreGroup(group),
        onExpand: () => widget.onJoinGroup(group),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 第三十四批：來電橫幅本體（草案）。最小樣式（主題容器色）；不寫死寬度
/// （上限＝畫面寬 0.72 倍，超長名稱省略）。
class _IncomingBannerCard extends StatelessWidget {
  const _IncomingBannerCard({
    required this.title,
    required this.name,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.onExpand,
  });

  final String title;
  final String name;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    return Semantics(
      liveRegion: true, // 無障礙：橫幅出現時播報（草案）。
      label: '$title：$name',
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onExpand,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(onPressed: onPrimary, child: Text(primaryLabel)),
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 批次 II-d：通話分區顯示**通話紀錄**（本機 SQLite；草案，待人類設計定稿）。
class _CallsTab extends StatefulWidget {
  // 第二十二批（LINE_ref calls 稿）：注入 client／callManager——tile 電話鈕
  // =一對一重撥（官方 `CallManager.startCall`，同 ChatScreen 現行鏈路）。
  const _CallsTab({required this.client, required this.callManager});

  final Client client;
  final CallManager callManager;

  @override
  State<_CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<_CallsTab> {
  List<CallLogEntry> _entries = const <CallLogEntry>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CallLog.list();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  String _formatDuration(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    if (m == 0) return '${r}s';
    return '${m}m${r}s';
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (d == today) return '今天 $hh:$mm';
    return '${t.month}/${t.day} $hh:$mm';
  }

  /// 第二十二批（LINE_ref calls 稿）：tile 重排——頭像／名字（未接＝紅字，
  /// 主題 error 色）/名字下＝日期＋方向箭號（↙來電／↗去電；群組＝群圖示）
  /// ＋時長；1:1 每列右端電話鈕＝重撥。點 tile 本體＝開該聊天室。
  /// 頂列大標題稿風（headline 同第二十一批首頁）；右上維持「重新整理」
  /// （稿上的 ⋮ 無 Homing 對應功能，不投射）。**顏色不取自 LINE 截圖**。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '通話紀錄',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700), // 文案待 UI 定稿
        ),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('尚無通話紀錄')) // 文案草案
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (ctx, i) {
                    final e = _entries[i];
                    final missed = e.outcome == 'missed';
                    final theme = Theme.of(ctx);
                    final incoming = e.direction == 'incoming';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kAccent,
                        child: Text(
                          e.peerName.runes.isEmpty
                              ? '?'
                              : String.fromCharCode(e.peerName.runes.first),
                          style: const TextStyle(color: kTextPrimary),
                        ),
                      ),
                      title: Text(
                        e.peerName,
                        style: TextStyle(
                          color: missed ? theme.colorScheme.error : null,
                        ),
                      ),
                      subtitle: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 第二十二批：方向箭號（稿上 ↙ 來電 / ↗ 去電；
                          // 群組＝群圖示）。
                          Icon(
                            e.isGroup
                                ? Icons.groups_2
                                : (incoming
                                    ? Icons.south_west
                                    : Icons.north_east),
                            size: 14,
                            color: missed
                                ? theme.colorScheme.error
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatTime(e.startedAt)}'
                            '${e.durationMs > 0 ? ' · ${_formatDuration(e.durationMs)}' : ''}'
                            '${missed ? ' · 未接' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      // 稿上 per-column 電話鈕：僅 1:1（== can dial）；群組通話
                      // 入口維持在聊天室頁 → 群組列無鈕（點本體進房）。
                      trailing: e.isGroup
                          ? null
                          : IconButton(
                              tooltip: '撥出', // 文案草案
                              onPressed: () => unawaited(_redial(e)),
                              icon: const Icon(Icons.call_outlined),
                            ),
                      onTap: () => _openRoom(e),
                    );
                  },
                ),
    );
  }

  /// 第二十二批：點 tile 本體 → 開啟對應聊天室（既有 ChatScreen 鏈路；
  /// 房間已不存在 → SnackBar，不靜默）。
  void _openRoom(CallLogEntry e) {
    final room = widget.client.getRoomById(e.roomId);
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此聊天室已不存在')), // 文案草案
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(room: room, callManager: widget.callManager),
      ),
    );
  }

  /// 第二十二批：1:1 重撥（官方 `CallManager.startCall`，同 ChatScreen 現行
  /// 鏈路；通話管理不可用／房間已刪 → SnackBar，不自製協定）。
  Future<void> _redial(CallLogEntry e) async {
    if (!widget.callManager.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '通話功能不可用'
            '${widget.callManager.callSupportError != null ? '：${widget.callManager.callSupportError}' : ''}',
          ), // 文案草案
        ),
      );
      return;
    }
    final room = widget.client.getRoomById(e.roomId);
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此聊天室已不存在')), // 文案草案
      );
      return;
    }
    try {
      final session =
          await widget.callManager.startCall(room, video: false);
      if (!mounted) {
        await session.hangup(reason: CallErrorCode.userHangup);
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CallScreen(session: session, manager: widget.callManager),
          fullscreenDialog: true,
        ),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法撥打：$err')), // 文案草案
        );
      }
    }
  }
}
