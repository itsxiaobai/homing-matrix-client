// 任務：Phase 1 / 1.4 — 對話列表骨架（草案，待人類設計）
// UI 重構（依人類 LINE_ref 標註，2026-11-01）：頂部搜尋列＋QR 加好友鈕；
// 列表列＝頭像／名稱／預覽／時間（SDK lastEvent／notificationCount）。
// 依 AGENTS.md UI 規則：不寫死寬度、文案與版面待人類定稿草案。
// 邊界：本檔不觸碰加密邏輯；房間資料一律由 SDK（Matrix 官方）提供。
// 注意：骨架僅實作「開啟一對一／群組對話」入口；未讀徽章顯示官方
// `notificationCount`（不製作紅點吸引機制，僅顯示既有資料）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'add_friend_screen.dart';
import 'chat_screen.dart';
import 'design_tokens.dart';
import '../accounts_store.dart'
    show
        HomingAccount,
        loadAccounts,
        loadActiveAccountId; // 第一百零四批：多帳號
import '../app_settings.dart';
import '../emergency_feed.dart'; // 批次十六：PWS RSS 緊急示警
import 'emergency_flow_screen.dart'; // 第四十二批：緊急卡片「安否報告」→ 求助流程
import 'notification_settings_screen.dart'; // 第四十三批：頂列通知設定 icon
import '../markdown_message.dart'; // 第四十二批：列表預覽的 Markdown 渲染
import '../message_content.dart' show kMarkdownRenderFlag; // 2026-11-20：渲染要求旗標
import '../offline_queue.dart';
import '../pinned_rooms.dart';
import '../poll_compat.dart';
import '../voip/call_manager.dart';
import 'device_verification_dialog.dart';
import 'room_actions.dart'; // 第二十五批：「＋」三選項與建立／加入公開房共用流程
import 'settings_screen.dart'; // 第二十五批：頭像面板內嵌 SettingsBody
import 'time_format.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './a11y.dart'; // 無障礙：按鈕功能說明
import 'compound_icon.dart'; // 第七十批 c：Compound 圖示（覆蓋 68 自繪）

/// 恢復加密身分的動作抽象（供測試注入；預設呼叫 SDK 官方
/// `Client.initCryptoIdentity(reuseExistingStorageRecoveryKeyOrPassphrase:)`）。
typedef EncryptionRecovery = Future<void> Function(String recoveryKey);

/// 載入對話列表的抽象（供 widget 測試注入；預設用 SDK 的 roomsLoader＋rooms）。
typedef RoomsLoader = Future<List<Room>> Function(Client client);

/// 開啟單一對話的抽象（供測試注入；預設導向 ChatScreen）。
typedef RoomOpener = void Function(BuildContext context, Room room);

/// 單一房間的「顯示狀態指紋」（純函式，測試可直接呼叫；2026-11-06 修復）。
/// 只列入 UI 實際渲染的欄位：排序鍵（lastEvent）、名稱、預覽 body、
/// 未讀、釘選、隱藏、頭像、邀請狀態。任何會讓畫面變化的輸入變動都應
/// 改變這個字串；反之不渲染的欄位不列入（避免無意義重畫）。
String roomDisplayFingerprint(
  Room room, {
  required bool pinned,
  required bool hidden,
}) {
  final ev = room.lastEvent;
  // getLocalizedDisplayname 在部分房間狀態（如測試／未登入情境）可能擲錯；
  // 指紋函式必須永不擲錯（失敗→退回 room.id 保底）。
  String displayName;
  try {
    displayName = room.getLocalizedDisplayname();
  } catch (_) {
    displayName = room.id;
  }
  return [
    room.id,
    room.membership.name,
    pinned ? 'pin' : '',
    hidden ? 'hide' : '',
    '${room.notificationCount}',
    room.isUnread || room.markedUnread ? 'u' : '',
    displayName,
    ev?.eventId ?? '',
    '${ev?.originServerTs ?? 0}',
    ev?.body ?? '',
    room.avatar?.toString() ?? '',
  ].join('|');
}

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key, required this.client, this.loadRooms, this.openRoom, this.onLogout, this.onSwitchAccount, this.onAddAccount, this.recoverEncryption, this.callManager, this.emergencyAlerts = const [], this.statusRecords});

  final Client client;
  final RoomsLoader? loadRooms;
  final RoomOpener? openRoom;

  /// 批次十六：PWS RSS 緊急示警（官方 NCDR 聚合 feed；由 main_shell 前景
  /// 輪詢（15 分鐘、僅 Actual＋未過期＋高風險類別＝人類決定 2026-11-07）。
  /// 預設空清單（測試無網路；banner-only 不彈通知）。
  final List<EmergencyAlert> emergencyAlerts;

  /// 第六十四批⑤：傳送現況記錄**注入縫**（僅測試；正式路徑不傳 →
  /// `_loadEmergency` 讀本機 kv）。null＝走 kv。
  final Map<String, EmergencyStatusRecord>? statusRecords;

  /// 通話管理（P2.15 提案）：透傳至 ChatScreen（null 時聊天畫面不顯示通話鈕）。
  final CallManager? callManager;

  /// 登出出口（骨架：回呼後由上一層導航；未提供則呼叫 SDK logout 並顯示訊息）。
  final Future<void> Function(Client client)? onLogout;

  /// 第一百零四批：多帳號切換／新增（未提供時不顯示這些入口）。
  final Future<void> Function(HomingAccount account)? onSwitchAccount;
  final VoidCallback? onAddAccount;

  /// 恢復加密身分（人類批准 2026-10-31）：呼叫 SDK 官方
  /// `initCryptoIdentity`；未提供則走官方預設路徑。
  final EncryptionRecovery? recoverEncryption;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<Room> _rooms = const [];
  String? _message;
  bool _loading = true;
  bool _encryptionRecovered = false;

  // 第二十五批（人類指示「沒有頭像才用名稱第一個字母」）：官方 profile 頭像
  // 縮圖（fetchOwnProfile→getThumbnailUri＋認證媒體，SettingsBody 同鏈路）；
  // null＝尚無頭像 → 顯示 userID 首字（現行樣式）。讀取前先看移除旗標
  //（AppSettings.ownAvatarRemovedFlag，設定頁同源）避免 server profile 快取
  // 舊值鬼影（移除後數分鐘內仍回舊 url——第十三批查證）。
  (Uri, bool)? _homeAvatar;
  bool _draining = false;
  StreamSubscription? _roomUpdateSub;
  StreamSubscription<KeyVerification>? _verificationSub;
  final _searchController = TextEditingController();
  String _search = '';
  Timer? _reloadTimer;

  PinnedRoomsStore? _pinnedStore;
  Set<String> _pinned = const {};

  /// Issues「增加隱藏／刪除對話」：本機隱藏清單（AppSettings.hidden_rooms）。
  Set<String> _hidden = const {};

  /// 房間列表顯示指紋（上次值）：逐房組合 UI 渲染欄位，避免整頁大判斷
  /// 只比「數量／第一間 id」造成的精靈式不刷新。
  String _lastRoomListFingerprint = '';

  /// 已隱藏聊天區塊（列表底部收合，草案 UI）。
  bool _hiddenExpanded = false;

  /// 批次十二⑤（Phase 4.2 草案）：首頁**公告列**＝「公告房間」（room_info
  /// 本機旗標）的最新**官方**釘選訊息。觸發條件為草案，待人類定稿（可否決）。
  /// 公告（聊天室釘選訊息）橫幅資料；第四十二批加入時間戳（時效判斷）與
  /// 是否為公告（與災害示警分流）。
  /// 第六十四批①：加入 `eventId`——點擊橫幅 → 開房＋**自動跳到該訊息**
  /// （人類：「公告自動找過去訊息，不要讓使用者自己找」）。
  /// 聊天室釘選公告橫幅資料（型別保留供指紋比對）。
  /// 第九十三批：首頁不再顯示釘選公告（只在各聊天室內呈現）→ 此欄位不再
  /// render，但保留收集以維持 pin 變更刷新。
  List<
          ({
            String roomId,
            String title,
            String text,
            DateTime? sentAt,
            String eventId,
          })>
      // ignore: unused_field
      _emergency = const [];

  /// 第六十四批④：示警**測試**選項（人類要求「提供緊急訊息測試選項」）。
  /// 本機 kv（`emergency_test_alert`）的合成示警；關閉／過期＝null。
  /// 與 PWS 官方 feed **分流**：id 帶 `homing-test-` 前綴、類別含「（測試）」，
  /// 卡片與詳情頁皆標明測試性質（非真實災害）。
  EmergencyAlert? _testAlert;

  /// 第六十四批⑤：傳送現況記錄（alertId → 記錄；求助流程送出後寫入本機
  /// kv）。卡片顯示**現況（是否受影響）＋已通報名單**（人類指示）。
  Map<String, EmergencyStatusRecord> _statusRecords = {};
  String _lastStatusFingerprint = '';

  /// 第六十六批：**好友現況**（alertId → 各 1:1 房最新訊息解析結果；人類
  /// 指示「顯示哪些好友受影響和沒受影響」）。v0 只看最新一則訊息（披露）。
  final Map<String, List<({String name, bool affected})>> _friendStatuses = {};
  String _lastFriendStatusFingerprint = '';

  /// 第六十四批⑤：本 session **叉叉關閉**的示警 id（人類指示「右上有關閉
  /// 選項」）。僅隱藏顯示（不刪 kv／不影響官方 feed 輪詢）；測試示警的叉叉
  /// 另清 kv（與緊急聯絡人頁開關同步）。
  final Set<String> _emergencyDismissed = {};

  /// 第四十二批：預覽快取（room id → 預覽內容，含**編輯後**內容與 Markdown）。
  /// 官方 `Room.getTimeline()` 為非同步 → 先在載入時算好，列表渲染時同步取用。
  final Map<String, ({String text, String? formatted})> _previews = {};
  String _lastEmergencyFingerprint = '';

  @override
  void initState() {
    super.initState();
    // 第一百零六批：測試示警開關變更 → 立即刷新橫幅。
    emergencyRefreshNotifier.addListener(_onEmergencyRefresh);
    _pinnedStore = PinnedRoomsStore(widget.client);
    _pinnedStore!.sync().then((ids) {
      if (mounted) setState(() => _pinned = ids);
    }).catchError((_) {});
    _roomUpdateSub = widget.client.onSync.stream.listen((_) {
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _load();
          _drainOfflineQueue();
        }
      });
    });
    _verificationSub = widget.client.onKeyVerificationRequest.stream.listen((request) {
      // 第二十五批：互斥旗標改為 device_verification_dialog 共用（設定頁
      // 「驗證裝置」入口同源）——兩個官方 SAS 對話框不再疊放。
      if (!mounted || deviceVerificationDialogShowing) return;
      showDeviceVerificationDialog(context, request);
    });
    _encryptionRecovered =
        widget.client.encryption?.crossSigning.isSelfSigned == true;
    _load();
    // 第二十五批：首頁左上頭像（官方 profile 縮圖；無頭像 → 首字 fallback）。
    unawaited(_refreshHomeAvatar());
  }

  void _onEmergencyRefresh() {
    if (mounted) unawaited(_loadEmergency());
  }

  @override
  void dispose() {
    emergencyRefreshNotifier.removeListener(_onEmergencyRefresh);
    _roomUpdateSub?.cancel();
    _verificationSub?.cancel();
    _searchController.dispose();
    _reloadTimer?.cancel();
    _pinnedStore?.dispose();
    super.dispose();
  }

  Future<List<Room>> _defaultLoad(Client client) async {
    // 首次同步前 rooms 為空；等待第一次 onSync 更新（骨架：不做精細等待，
    // 空房間也可能由「沒有對話」處理）。
    if (client.rooms.isEmpty) {
      try {
        await client.onSync.stream.first.timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    return client.rooms;
  }

  /// 釘選置頂（「聊天頁釘選聊天室應出現在最上方」）：統一排序入口。
  void _sortRooms() {
    final rooms = [..._rooms];
    final pinned = _pinned;
    rooms.sort((a, b) {
      final ap = pinned.contains(a.id);
      final bp = pinned.contains(b.id);
      if (ap != bp) return ap ? -1 : 1;
      return b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);
    });
    _rooms = rooms;
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    final hadRooms = _rooms.isNotEmpty;
    if (!hadRooms) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }

    List<Room> rooms;
    try {
      rooms = await (widget.loadRooms ?? _defaultLoad)(widget.client);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _message = '無法載入對話列表：請檢查網路';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    try {
      _pinned = await _pinnedStore?.sync() ?? _pinned;
    } catch (_) {}
    try {
      _hidden = await AppSettings.hiddenRooms();
    } catch (_) {}
    // 僅在房間列表實際變更時更新，避免 sync 觸發的重複 rebuild。
    // 
    // 舊判斷＝「房間數變 || 第一間 id 變」：凡影響顯示但不動這兩項的更新
    // （未讀數、預覽文字、頭像、名稱、pin 同步、隱藏、邀請狀態）整列表
    // 不重畫 → 「頭像無法即時更新」「釘選殘留」等回報的共同根因。
    // 改為逐房「顯示狀態指紋」比對（只含 UI 實際渲染的欄位；成本遠低於
    // 每次 sync 的整頁 setState），有變才 setState＋重排序。
    final fingerprint = [
      for (final room in rooms)
        roomDisplayFingerprint(
          room,
          pinned: _pinned.contains(room.id),
          hidden: _hidden.contains(room.id),
        ),
    ].join('\n');
    final changed = fingerprint != _lastRoomListFingerprint;
    _lastRoomListFingerprint = fingerprint;
    if (changed) {
      try {
        _pinned = await _pinnedStore?.sync() ?? _pinned;
      } catch (_) {}
      if (mounted) {
        // 一律重排序（釘選＋時間）；舊實作把 sort 包在 changed 分支，
        // 且釘選變更後從不重排序 → 釘選房間留在原地。
        setState(() {
          _loading = false;
          _rooms = rooms;
          _sortRooms();
        });
      }
    } else {
      if (mounted && _loading) setState(() => _loading = false);
    }
    // 批次十二⑤：首頁公告列刷新（公告房間 ∩ 官方釘選；有變才 setState）。
    unawaited(_loadEmergency());
    // 第四十二批：預覽（含編輯與 Markdown）需官方 timeline（非同步）→ 載入後算。
    unawaited(_refreshPreviews(rooms));
  }

  /// 批次十二⑤（Phase 4.2 草案）：橫幅資料＝AppSettings 公告房間旗標（純本機）
  /// ∩ `Room.pinnedEventIds`（官方 room.dart L185）最新一筆，內容查
  /// `Room.getEventById`（官方 room.dart L2225）。指紋比對避免每次 sync setState。
  /// 第六十四批④：同時讀**示警測試** kv（獨立於公告房間旗標；無公告房間時
  /// 不提早返回——測試示警卡片仍要能刷新）。
  Future<void> _loadEmergency() async {
    if (!mounted) {
      return;
    }
    // 第六十四批④：示警測試選項（本機 kv；讀取失敗＝無測試示警，不阻擋）。
    EmergencyAlert? test;
    try {
      test = await loadTestEmergencyAlert();
    } catch (_) {
      test = null;
    }
    if (!mounted) {
      return;
    }
    // 第六十四批⑤：傳送現況記錄（卡片顯示現況＋已通報名單）。指紋含記錄
    // 更新時間 → 求助流程送出後回來（_loadEmergency 重跑）即刷新。
    // 注入縫優先（僅測試；正式＝本機 kv）。
    Map<String, EmergencyStatusRecord> statuses =
        widget.statusRecords ?? {};
    if (widget.statusRecords == null) {
      try {
        statuses = await loadEmergencyStatuses();
      } catch (_) {
        statuses = {};
      }
    }
    if (!mounted) {
      return;
    }
    final fpStatuses = statuses.entries
        .map((e) => '${e.key}:${e.value.updatedAt.millisecondsSinceEpoch}')
        .join('|');
    if (fpStatuses != _lastStatusFingerprint) {
      _lastStatusFingerprint = fpStatuses;
      setState(() => _statusRecords = statuses);
    }
    // 第六十六批：好友現況解析（各 1:1 房最新一則訊息 vs 現況／報平安標記）。
    await _loadFriendStatuses();
    // 2026-11-21：比照 Element X——直接掃**所有**房間的 `pinnedEventIds`
    // （Matrix 標準 state `m.pinned_events`），不再需要本機「公告房間」旗標。
    final roomList = widget.client.rooms;
    final lines = <String>[];
    final banners = <({
      String roomId,
      String title,
      String text,
      DateTime? sentAt,
      String eventId,
    })>[];
    for (final room in roomList) {
      List<String> ids;
      try {
        ids = room.pinnedEventIds;
      } catch (_) {
        continue;
      }
      if (ids.isEmpty) {
        continue;
      }
      // 第四十二批：`pinnedEventIds` 的順序**未定義** → 不能直接取 `ids.last`；
      // 改為逐一取事件，依 `originServerTs` 挑**最新的文字訊息**。
      Event? best;
      for (final id in ids.reversed) {
        Event? ev;
        try {
          ev = await room.getEventById(id); // 官方（room.dart L2225）
        } catch (_) {}
        if (ev == null || ev.redacted) {
          continue;
        }
        if (ev.type != EventTypes.Message || ev.messageType != 'm.text') {
          continue; // 只取文字（附件/投票不當公告）。
        }
        if (ev.body.isEmpty) {
          continue;
        }
        if (best == null ||
            ev.originServerTs.isAfter(best.originServerTs)) {
          best = ev;
        }
      }
      if (best == null) {
        continue;
      }
      // 時效：公告只在合理時間窗內顯示（預設 24 小時）→ 避免舊釘選永久
      // 掛在首頁當「公告」。
      final sentAt = best.originServerTs;
      if (sentAt.isBefore(
        DateTime.now().subtract(const Duration(hours: 24)),
      )) {
        continue;
      }
      lines.add('${room.id}:${best.eventId}');
      String name = room.id;
      try {
        final n = room.getLocalizedDisplayname(); // 官方（room.dart L228）
        if (n.isNotEmpty && n != 'Empty chat') {
          name = n;
        }
      } catch (_) {}
      banners.add((
        roomId: room.id,
        title: name,
        text: best.body,
        sentAt: sentAt,
        eventId: best.eventId, // 第六十四批①：點橫幅 → 開房＋自動跳到此訊息。
      ));
    }
    // 指紋含測試示警 id（第六十四批④：切換開關後下一次刷新即生效）。
    final fp = '${lines.join('|')}|${test?.id ?? ''}';
    if (fp == _lastEmergencyFingerprint) {
      return;
    }
    _lastEmergencyFingerprint = fp;
    if (mounted) {
      setState(() {
        _emergency = banners;
        _testAlert = test;
      });
    }
  }

  /// 第六十六批：好友現況解析（人類指示「顯示哪些好友受影響和沒受影響」）。
  /// 資料＝各 **1:1 房最新一則訊息**（`Room.lastEvent`，sync 後的記憶體欄位，
  /// 純讀取不打網路）vs 現況／報平安標記（emergency_feed 純函式）。時間窗＝
  /// 示警 `sent` 之後（寬容 5 分鐘）且 `expires` 之前。有變才 setState。
  /// **披露**：v0 只看最新一則訊息；純文字比對、無簽章驗證。
  Future<void> _loadFriendStatuses() async {
    final alerts = _visibleEmergencyAlerts;
    final next = <String, List<({String name, bool affected})>>{};
    if (alerts.isNotEmpty) {
      final directRooms = [
        for (final room in widget.client.rooms)
          if (_isDirectRoom(room)) room,
      ];
      for (final room in directRooms) {
        // 自己送出的不算（只解析**好友傳來**的現況）。
        if (room.lastEvent?.senderId == widget.client.userID) {
          continue;
        }
        String name = room.id;
        try {
          final n = room.getLocalizedDisplayname();
          if (n.isNotEmpty && n != 'Empty chat') {
            name = n;
          }
        } catch (_) {}
        for (final alert in alerts) {
          final affected = parseFriendEmergencyStatus(
            room.lastEvent?.body ?? '',
            alert.category,
          );
          if (affected == null) {
            continue;
          }
          // 時間窗：訊息須落在示警 sent（寬容 5 分鐘）～expires 之間。
          final ts = room.lastEvent?.originServerTs;
          if (ts != null) {
            final sent = alert.sent;
            if (sent != null &&
                ts.isBefore(sent.subtract(const Duration(minutes: 5)))) {
              continue;
            }
            final expires = alert.expires;
            if (expires != null && ts.isAfter(expires)) {
              continue;
            }
          }
          (next[alert.id] ??= []).add((name: name, affected: affected));
          break; // 一則訊息只對應一則示警（標記＋類別已限縮）。
        }
      }
    }
    if (!mounted) {
      return;
    }
    final fp = next.entries
        .map(
          (e) => '${e.key}=${e.value.map((f) => '${f.name}:${f.affected}').join(',')}',
        )
        .join('|');
    if (fp == _lastFriendStatusFingerprint) {
      return;
    }
    _lastFriendStatusFingerprint = fp;
    setState(() {
      _friendStatuses
        ..clear()
        ..addAll(next);
    });
  }

  bool _isDirectRoom(Room room) {
    try {
      return room.isDirectChat;
    } on Object {
      return false;
    }
  }

  /// 第六十四批⑤：可見示警清單（官方 feed＋測試示警；id 去重；扣掉本
  /// session 已被叉叉關閉者）。
  List<EmergencyAlert> get _visibleEmergencyAlerts => [
        ...widget.emergencyAlerts.where(
          (a) =>
              a.id != _testAlert?.id && !_emergencyDismissed.contains(a.id),
        ),
        if (_testAlert != null &&
            !_emergencyDismissed.contains(_testAlert!.id))
          _testAlert!,
      ];

  /// 批次十六：PWS 橫幅時間顯示（M/d HH:mm，本地時區；無 sent 回空）。
  String _alertTime(EmergencyAlert a) {
    final t = a.sent;
    if (t == null) {
      return '';
    }
    final l = t.toLocal();
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:$mm';
  }

  /// 第四十二批：緊急卡片「傳送現況」（第六十四批⑤由「安否報告」改名）→
  /// 傳送現況／求助流程（emergency_flow_screen：現況 → 受影響才出現求助）。
  /// 流程關閉後重抓記錄（卡片顯示現況＋已通報名單）。
  void _openEmergencyReportFlow(EmergencyAlert alert) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                EmergencyFlowScreen(client: widget.client, alert: alert),
          ),
        )
        .then((_) {
          if (mounted) {
            unawaited(_loadEmergency());
          }
        });
  }

  /// 第六十四批⑤：叉叉關閉（session 隱藏）。測試示警另清 kv（與緊急聯絡人
  /// 頁開關同步；kv 清除後 _loadEmergency 重跑即消失）。
  void _dismissEmergency(EmergencyAlert alert) {
    setState(() => _emergencyDismissed.add(alert.id));
    if (alert.id.startsWith('homing-test-')) {
      unawaited(
        AppSettings.remove(kEmergencyTestAlertKey).catchError((_) {}),
      );
    }
  }

  /// 第四十二批：災害示警詳情（可捲動全文；含出處與免責）。
  void _showEmergencyDetail(EmergencyAlert a) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${a.category}・${a.sender}'), // 文案草案
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(a.summary), // 摘要全文
              const SizedBox(height: 12),
              Text(
                a.sent == null ? '' : _alertTimeFrom(a.sent!),
                style: Theme.of(ctx).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              Text(
                kEmergencyFeedAttribution,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('關閉')), // 文案草案
          ),
        ],
      ),
    );
  }

  /// 時間字串（M/d HH:mm；第四十二批：公告與示警共用）。
  String _alertTimeFrom(DateTime t) {
    final l = t.toLocal();
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:$mm';
  }

  Future<void> _drainOfflineQueue() async {
    if (_draining) return;
    _draining = true;
    try {
      await OfflineQueue.drain(widget.client);
    } catch (_) {}
    _draining = false;
  }

  Future<void> _recoverEncryption() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('恢復加密身分')), // 文案待 UI 定稿
        content: TextField(
          controller: controller,
          obscureText: true,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            labelText: 'Recovery key',
            hintText: S.t('貼上 Element / matrix.org 產生的 recovery key'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(S.t('恢復')),
          ),
        ],
      ),
    );
    if (raw == null || raw.isEmpty || !mounted) {
      controller.dispose();
      return;
    }
    final key = raw.replaceAll(RegExp(r'\s+'), '');
    try {
      await (widget.recoverEncryption ?? _defaultRecoverEncryption)(key);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _encryptionRecovered = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.t('加密身分已恢復；請在 Element 重新整理頁面以同步驗證狀態')),
        ),
      );
      try {
        await widget.client.sync();
      } catch (_) {}
      await _load();
    } catch (e) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('恢復失敗：')}$e')),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _defaultRecoverEncryption(String recoveryKey) async {
    if (widget.client.encryption == null) {
      throw StateError('加密引擎未啟用（vodozemac 未載入）');
    }
    // 確保 cross-signing 裝置金鑰已載入，否則 self-sign 不會執行、裝置維持未驗證。
    if (widget.client.userDeviceKeysLoading != null) {
      await widget.client.userDeviceKeysLoading!
          .timeout(const Duration(seconds: 8))
          .catchError((_) {});
    }
    // 官方 SDK API：reuse 既有 SSSS key，不 wipe 既有 cross-signing。
    if (widget.client.accountDataLoading != null) {
      await widget.client.accountDataLoading!
          .timeout(const Duration(seconds: 8))
          .catchError((_) {});
    }
    await widget.client.initCryptoIdentity(
      reuseExistingStorageRecoveryKeyOrPassphrase: recoveryKey,
    );
  }

  // 第二十五批（人類指示「驗證裝置、診斷功能移入設定中的進階區域」）：
  // _startDeviceVerification／_showDiagnostics／_selfSignWithRecoveryKey
  // 三段官方 SDK 流程**原樣搬入** settings_screen（SettingsBody），本檔
  // 刪除副本。⋮ 選單只剩登出（見 build）。進房時官方驗證邀請自動彈窗
  // （上方監聽）不動。

  Future<void> _onLogout() async {
    try {
      if (widget.onLogout != null) {
        await widget.onLogout!(widget.client);
      } else {
        await widget.client.logout();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '登出失敗：請檢查網路');
      }
      return;
    }
    if (mounted) {
      setState(() => _message = '已登出');
      try {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _rooms
        .where((r) =>
            // 第二十五批（人類指示「首頁的 Spaces 拿掉」）：Space 不再出現在
            // 首頁（歸聯絡人「群組」區塊，點開 Space 底下聊天室清單）。
            !r.isSpace &&
            !_hidden.contains(r.id) &&
            (_search.isEmpty ||
                _roomTitle(r).toLowerCase().contains(_search.toLowerCase()) ||
                r.id.toLowerCase().contains(_search.toLowerCase())))
        .toList();
    // 已隱藏區塊同樣不參與主列表（取消隱藏在此區塊，草案 UI）；Space 同上。
    final hiddenRooms = _rooms
        .where((r) => _hidden.contains(r.id))
        .where((r) => !r.isSpace)
        .toList();
    return Scaffold(
      appBar: AppBar(
        // 第二十一批（人類 mockup v0_2）：頭像＋大標題「聊天」（草案）。
        // 第二十五批（人類指示「設定功能整合到首頁左上頭像」）：左上頭像＝
        // 官方 profile 縮圖（沒有頭像才顯示名稱首字）；點擊 → 帳號面板
        //（bottom sheet 內嵌 SettingsBody——設定＋更換頭像＋登出入口）。
        title: Row(
          children: [
            // 第六十二批（無障礙盤點）：頭像＝開設定面板的按鈕 → 補 Semantics
            // button＋label（否則 TalkBack 對純頭像圖無功能說明）。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openAvatarAccountSheet,
              child: Semantics(
                button: true,
                label: S.t('設定（開啟帳號面板）'),
                child: CircleAvatar(
                  backgroundColor: kAccent,
                  backgroundImage: _homeAvatar == null
                      ? null
                      : NetworkImage(
                          _homeAvatar!.$1.toString(),
                          headers: _homeAvatar!.$2
                              ? <String, String>{
                                  'authorization':
                                      'Bearer ${widget.client.accessToken}',
                                }
                              : null,
                        ),
                  child: _homeAvatar == null
                      ? Text(
                          _userInitial(),
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 第六十一批（LINE_ref chats 截圖）：頂列＝**綠色圓角膠囊**（「Chats ▾」
            // 構圖）。Homing 的「聯絡人」是獨立 tab（非膠囊下拉切換）→ 膠囊僅
            // 顯示目前 tab 名（無下拉），頭像仍保留（設定入口，功能不變）。
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: kLineGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    S.t('聊天室'), // 文案待 UI 定稿；草案，非最終視覺
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 2),
                  CompoundIcon(
                    CompoundIcons.chevronDown,
                    size: 16,
                    color: const Color(0xFFFFFFFF),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 第四十三批（LINE 版位：頂列右側 icon 組）：通知設定＋新增。
          // LINE 的右側組＝相簿／日曆／通知／＋；Homing 對應＝通知設定／＋
          // （相簿與日曆為 LINE 專屬功能，不做）。
          a11yButton(label: S.t('通知設定'), child: IconButton(
            tooltip: S.t('通知設定'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotificationSettingsScreen(client: widget.client),
              ),
            ),
            icon: CompoundIcon(
              CompoundIcons.notifications,
              size: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          )),
          a11yButton(label: S.t('新增'), child: IconButton(
            tooltip: S.t('新增'),
            onPressed: _showAddSheet,
            icon: CompoundIcon(
              CompoundIcons.plus,
              size: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          )),
          // 恢復加密（異常時才出現；藍圖 1.5 保持原樣）。
          if (!_encryptionRecovered)
            TextButton(
              onPressed: _recoverEncryption,
              child: Text(S.t('恢復加密')),
            ),
          // （第二十一批）「新增」鈕依 mockup 移入搜尋列右端。
          // 第二十五批（人類指示）：驗證／診斷移入設定進階區 → 選單只剩登出。
          PopupMenuButton<String>(
            tooltip: S.t('更多'),
            icon: CompoundIcon(
              CompoundIcons.menu,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onSelected: (value) {
              switch (value) {
                case 'logout':
                  _onLogout();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'logout', child: Text(S.t('登出'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 頂部搜尋列（樣式第二十一次依 mockup：token 底色＋小圓角）＋
          // 右端「＋」（新增 sheet）與 QR（既有 1.8 加好友畫面）。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _search = v.trim()),
                    decoration: InputDecoration(
                      // 批次 III-a（人類指示）：「搜尋對話」→「搜尋聊天室」。
                      hintText: S.t('搜尋'),
                      hintStyle: TextStyle(color: kLineTimeText),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CompoundIcon(
                          CompoundIcons.search,
                          size: 20,
                          color: kLineTimeText,
                        ),
                      ),
                      isDense: true,
                      filled: true,
                      // 第六十八批 a（LINE_ref）：搜尋列＝深色 #1F1F1F／
                      // 淺色 #F2F2F2 的**膠囊**（半徑 24，不是 8）。
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? kLineBar
                          : const Color(0xFFF2F2F2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide.none,
                      ),
                      // 第七十批 b：移除右端 scan 圖標（人類指示「把搜尋欄
                      // 右邊掃描功能拿掉」）——保留左側自繪放大鏡即可。
                    ),
                  ),
                ),
                // 第四十三批（LINE 版位）：搜尋列只保留搜尋框；
                // 「新增」移到頂列右側 icon 組；「加入好友（QR）」在聯絡人頁。
              ],
            ),
          ),
          // 第九十三批（人類指示）：**首頁只顯示緊急訊息**（PWS RSS）。
          // 聊天室釘選公告不在首頁顯示——公告只在各自聊天室內呈現
          // （ChatScreen 的 AnnouncementBanner）。下方 _visibleEmergencyAlerts
          // 即 PWS 緊急卡片，保留。
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty && _visibleEmergencyAlerts.isEmpty
                    ? Center(
                        child: Text(
                          // 第二十一批（mockup v0_2）：無房間空文案照稿；
                          // 搜尋無結果維持既有草案文案。
                          _message ??
                              (_rooms.isEmpty
                                  ? '好像是時候跟朋友聊天了？'
                                  : '沒有符合的對話'),
                        ),
                      )
                    : ListView(
                        children: [
                          // 第六十四批⑤：緊急卡片在清單頂（跟著畫面滑動）。
                          // 批次十六：PWS RSS 緊急示警（官方 NCDR 聚合 feed；
                          // 僅 Actual＋未過期＋高風險類別）。第四十二批：LINE
                          // 紅色緊急卡片版位。第六十四批④：**示警測試**（本機
                          // kv 合成示警）同座顯示；⑤：叉叉關閉（session 隱藏）。
                          for (final e in _visibleEmergencyAlerts)
                            _EmergencyAlertCard(
                              alert: e,
                              timeText: _alertTime(e),
                              status: _statusRecords[e.id],
                              // 第六十六批：好友現況顯示行。
                              friendStatuses: _friendStatuses[e.id] ?? const [],
                              onReportSafety: () =>
                                  _openEmergencyReportFlow(e),
                              onViewDetail: () => _showEmergencyDetail(e),
                              onClose: () => _dismissEmergency(e),
                            ),
                          if (_visibleEmergencyAlerts.isNotEmpty)
                            // 批次十六：顯名＋免責（政府資料開放授權條款第 3 條
                            // (二)顯名義務；資料機關可隨時停止提供／不負賠償 →
                            // 小字敘述）。文案草案。
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                              child: Text(
                                '$kEmergencyFeedAttribution\n'
                                '示警可能延遲或不完整；緊急時請以中央氣象署及地方政府原發布管道為準。',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          // 第二十五批（人類指示「首頁的 Spaces 拿掉」）：Spaces
                          // 收合區塊刪除——Space 歸聯絡人「群組」區塊（點開
                          // Space 底下聊天室清單，見 contacts_screen）。
                          for (final room in filtered) _buildRoomTile(room),
                          // 已隱藏對話（本機過濾，不刪伺服器資料）；收合展開。
                          if (hiddenRooms.isNotEmpty && _search.isEmpty) ...[
                            InkWell(
                              onTap: () => setState(() => _hiddenExpanded = !_hiddenExpanded),
                              child: Semantics(
                                button: true,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                  child: Row(
                                  children: [
                                    CompoundIcon(
                                      _hiddenExpanded ? CompoundIcons.collapse : CompoundIcons.expand,
                                      size: 18,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '已隱藏對話（${hiddenRooms.length}）', // 文案草案
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              ),
                            ),
                            if (_hiddenExpanded)
                              for (final room in hiddenRooms)
                                ListTile(
                                  leading: CompoundIcon(CompoundIcons.visibilityOff, size: 24, color: Theme.of(context).colorScheme.onSurface),
                                  title: Text(_roomTitle(room)),
                                  trailing: TextButton(
                                    child: Text(S.t('取消隱藏')), // 文案草案
                                    onPressed: () => _unhideRoom(room),
                                  ),
                                ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // 第二十五批：（首頁 Spaces 拿掉；人類指示）_buildSpaceTile／_showSpaceRooms
  // 搬出到 room_actions.dart 的 showSpaceRoomsSheet，由聯絡人「群組」區塊呼叫。

  /// 第二十五批（人類指示「設定功能整合到首頁左上頭像；能變換頭像」）：
  /// 帳號面板 bottom sheet **內嵌 SettingsBody**（設定本體：Profile 頭像＋
  /// 變更頭像三選項＋各分區；登出入口仍在設定本體 App info 區）。
  /// 面板關閉後重抓官方 profile，讓左上頭像即時反映更換／移除。
  Future<void> _openAvatarAccountSheet() async {
    // 第一百零四批：讀取帳號清單（只含中繼資料，不碰 token／金鑰）。
    final accounts = await loadAccounts();
    final activeId = await loadActiveAccountId();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(S.t('設定'), // 文案待人類定稿（草案）
                  style: Theme.of(ctx).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              // 第一百零四批：多帳號（僅在上一層提供回調時顯示）。
              if (accounts.length > 1 || widget.onAddAccount != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        S.t('切換帳號'),
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                    ),
                    for (final account in accounts)
                      ListTile(
                        dense: true,
                        title: Text(
                          account.userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          account.homeserver,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: account.id == activeId
                            ? Text(S.t('目前'))
                            : null,
                        onTap: account.id == activeId ||
                                widget.onSwitchAccount == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                unawaited(widget.onSwitchAccount!(account));
                              },
                      ),
                    if (widget.onAddAccount != null)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_add_alt),
                        title: Text(S.t('新增帳號')),
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onAddAccount!();
                        },
                      ),
                  ],
                ),
              Expanded(
                child: SettingsBody(
                  client: widget.client,
                  onLogout: widget.onLogout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // 面板關閉 →重抓頭像（更換／移除後左上頭像同步；SettingsBody 內部已把
    // 官方 profile 快取 mark outdated → fetchOwnProfile 回真值）。
    unawaited(_refreshHomeAvatar());
  }

  /// 第二十五批：官方 profile 頭像抓取（SettingsBody `_loadProfile` 同鏈路：
  /// fetchOwnProfile → getThumbnailUri＋authenticatedMediaSupported）。
  /// 移除旗標期間不畫舊頭像（server profile 快取可能滯留舊值——第十三批
  /// 查證）；任何失敗 → 保持 fallback（首字）。
  Future<void> _refreshHomeAvatar() async {
    try {
      final flag = await AppSettings.get(AppSettings.ownAvatarRemovedFlag);
      if (flag != null && flag.isNotEmpty) {
        if (mounted) {
          setState(() => _homeAvatar = null);
        }
        return;
      }
      final profile = await widget.client.fetchOwnProfile();
      final url = profile.avatarUrl;
      if (url == null) {
        if (mounted) {
          setState(() => _homeAvatar = null);
        }
        return;
      }
      final thumb = await url.getThumbnailUri(widget.client, width: 96, height: 96);
      final auth = await widget.client.authenticatedMediaSupported();
      if (mounted) {
        setState(() => _homeAvatar = (thumb, auth));
      }
    } on Object {
      // 測試環境／離線／無頭像 → 保持 null（首字 fallback）。
    }
  }

  /// 第二十五批：「＋」三選項 sheet 與聯絡人 FAB **共用**同一份（room_actions；
  /// 人類拍板兩處同一組：建立聊天室／加入公開聊天室／加入好友）。建立與加入
  /// 公開房流程也由共用檔執行（官方 createRoom／queryPublicRooms）。
  Future<void> _showAddSheet() async {
    await runAddChatSheet(
      context,
      client: widget.client,
      openAddFriend: _openAddFriend,
      callManager: widget.callManager,
      onRoomsChanged: _load,
      openRoom: widget.openRoom,
    );
  }

  // 第二十五批：_joinPublicRoom／_openPublicRoom 搬出到 room_actions.dart
  // （showJoinPublicRoomFlow／openPublicRoom）；首頁與聯絡人共用。

  /// 第二十一批（mockup v0_2）：首頁頭像首字（官方 userID 首字元，略過 '@'）。
  String _userInitial() {
    final id = widget.client.userID ?? '';
    final runes = id.runes.skip(1); // 略過 '@'
    if (runes.isEmpty) {
      return '?';
    }
    return String.fromCharCode(runes.first);
  }

  // 第二十五批：_createRoom 搬出到 room_actions.dart（showCreateRoomFlow）。

  void _openAddFriend() {
    // SDK `Client.homeserver` 為 Uri?（連線後必為值）；此處僅作顯示提示用。
    final homeserver = widget.client.homeserver ?? Uri();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 批次 III-c：傳入 client → _defaultInvite 走官方 startDirectChat。
        builder: (_) => AddFriendScreen(homeserver: homeserver, client: widget.client),
      ),
    );
  }

  Uri? _safeAvatar(Room room) {
    try {
      return room.avatar;
    } catch (_) {
      return null;
    }
  }

  /// Issues「增加隱藏／刪除對話」：隱藏＝本機 AppSettings.hidden_rooms；
  /// 對話從主列表消失，收合區可取消隱藏（資料不動伺服器）。
  Future<void> _hideRoom(Room room) async {
    try {
      await AppSettings.hideRoom(room.id);
      if (!mounted) return;
      setState(() {
        _hidden = {..._hidden, room.id};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${S.t('已隱藏「')}${_roomTitle(room)}」'), // 文案草案
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('操作失敗：')}$e')),
        );
      }
    }
  }

  Future<void> _unhideRoom(Room room) async {
    try {
      await AppSettings.unhideRoom(room.id);
      if (!mounted) return;
      setState(() {
        _hidden = _hidden.where((id) => id != room.id).toSet();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('操作失敗：')}$e')),
        );
      }
    }
  }

  /// 刪除對話＝官方 `Room.leave()`（退出）＋官方 `Room.forget()`
  ///（memory 房間自塵 room list）。退出為不可逆 server 操作 → 先確認。
  Future<void> _deleteRoom(Room room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.t('刪除「')}${_roomTitle(room)}」？'), // 文案草案
        content: Text('${S.t('這會退出聊天室並讓本裝置不再顯示該對話（伺服器端）。')}\n${S.t('此操作無法在本裝置復原。')}'), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('刪除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await room.leave();
      try {
        await room.forget();
      } catch (_) {
        // forget 失敗（例如需先完成 leave 同步）→ 下次 _load 過濾仍正確。
      }
      if (mounted) {
        setState(() => _rooms = _rooms.where((r) => r.id != room.id).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('刪除失敗：')}$e')),
        );
      }
    }
  }

  Widget _buildRoomTile(Room room) {
    final last = room.lastEvent;
    // 第四十二批：優先用預覽快取（含編輯後內容與 Markdown；載入時以官方
    // timeline 計算），取不到才退回同步估算。
    final preview = _previews[room.id] ?? _roomPreview(room, last);
    // 批次 D：未讀 = 伺服器通知計數 或 手動標記未讀（SDK 官方
    // `Room.isUnread`：notificationCount > 0 || markedUnread）。
    final unread = room.isUnread;
    final unreadCount = room.notificationCount;
    final muted = room.pushRuleState != PushRuleState.notify;
    // 批次 III-c（人類回報「好友邀請無法接收」）：受邀房間不再直接開
    // ChatScreen（受邀 membership 的 timeline 不可靠），改跳接受／拒絕流程。
    final isInvite = room.membership == Membership.invite;
    return ListTile(
      leading: _RoomAvatar(
        title: _roomTitle(room),
        avatar: room.isDirectChat ? null : _safeAvatar(room),
        client: widget.client,
      ),
      // 第四十五批（LINE 版位）：小徽章（置頂／靜音）緊貼**房名右側**
      // （LINE 的靜音符號即置於名稱後），右側欄只留「時間＋未讀徽章」。
      title: Row(
        children: [
          Flexible(
            child: Text(
              _roomTitle(room),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (_pinned.contains(room.id)) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: S.t('已釘選'),
              child: CompoundIcon(
                CompoundIcons.pin,
                size: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          if (muted) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: S.t('靜音'),
              child: CompoundIcon(
                CompoundIcons.notificationsOff,
                size: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CompoundIcon(muted ? CompoundIcons.notifications : CompoundIcons.notificationsOff, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  title: Text(muted ? '取消靜音' : '靜音'), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'mute'),
                ),
                ListTile(
                  leading: CompoundIcon(CompoundIcons.pin, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  title: Text(_pinned.contains(room.id) ? '取消釘選' : '釘選'), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'pin'),
                ),
                // 未讀/已讀**互斥**（人類回饋 2026-11-03「未讀訊息不應出現
                // 『標記為未讀』」）：未讀 → 只顯示「標記為已讀」（官方
                // `setReadMarker`＋`markUnread(false)`）；已讀 → 只顯示
                // 「標記為未讀」（官方 `Room.markUnread(true)`）。
                ListTile(
                  leading: CompoundIcon(room.isUnread ? CompoundIcons.markRead : CompoundIcons.markUnread, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  title: Text(room.isUnread ? '標記為已讀' : '標記為未讀'), // 草案文案
                  onTap: () => Navigator.pop(ctx, room.isUnread ? 'read' : 'unread'),
                ),
                // Issues「增加隱藏／刪除對話」：隱藏＝本機過濾；刪除＝官方
                // `Room.leave`＋`Room.forget`（伺服器端收回，需確認）。
                ListTile(
                  leading: CompoundIcon(CompoundIcons.visibilityOff, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  title: Text(S.t('隱藏對話')), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'hide'),
                ),
                ListTile(
                  leading: CompoundIcon(CompoundIcons.delete, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  title: Text(S.t('刪除對話')), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ),
          ),
        );
        if (action == 'read') {
          try {
            // 已讀動作官方等價（Room.lastEvent 涵蓋最新事件）：setReadMarker
            //（receipt/m_read 同 event id）＋ 清掉手動未讀旗標（markUnread(false)
            // 官方：unread == markedUnread 時 no-op，不會丟錯）。
            final target = room.lastEvent?.eventId;
            if (target != null) {
              await room.setReadMarker(target, mRead: target);
            }
            await room.markUnread(false);
            if (mounted) setState(() {});
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${S.t('操作失敗：')}$e')),
              );
            }
          }
        }
        if (action == 'hide') {
          await _hideRoom(room);
        }
        if (action == 'delete') {
          await _deleteRoom(room);
        }
        if (action == 'unread') {
          try {
            await room.markUnread(true);
            if (mounted) setState(() {});
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${S.t('操作失敗：')}$e')),
              );
            }
          }
        }
        if (action == 'mute') {
          final newState = muted ? PushRuleState.notify : PushRuleState.dontNotify;
          try {
            await room.setPushRuleState(newState);
            if (mounted) setState(() {});
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${S.t('操作失敗：')}$e')));
          }
        } else if (action == 'pin') {
          try {
            if (_pinned.contains(room.id)) {
              await _pinnedStore?.unpin(room.id);
            } else {
              await _pinnedStore?.pin(room.id);
            }
            _pinned = await _pinnedStore?.loadLocal() ?? _pinned;
            // 釘選置頂根因：列表只在整批重載（changed）時才排序；釘選／取消
            // 釘選只更新 `_pinned` 後 `setState(() {})`，`_rooms` 順序不變 →
            // 釘選房間留在原地。此處立即重排序（草案行為：釘選即跳最上方）。
            if (mounted) {
              setState(_sortRooms);
            }
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${S.t('操作失敗：')}$e')));
          }
        }
      },
      subtitle: isInvite
          // 批次 III-c：受邀房間明確顯示邀請狀態（點按 → 接受／拒絕流程）。
          ? Text(S.t('邀請中（點按處理）')) // 文案草案
          : _roomPreviewWidget(preview.text, preview.formatted),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatRoomTime(room),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? kLineTimeText
                      : kTextSecondary,
                ),
          ),
          const SizedBox(height: 2),
          // 第四十五批：置頂／靜音徽章已移到標題列（房名右側），
          // 此處只留未讀徽章（SDK 官方 notificationCount ＋ account data
          // m.marked_unread；點數＝手動標記未讀）。
          if (unread) _UnreadBadge(count: unreadCount, dotWhenZero: true),
        ],
      ),
      onTap: isInvite && widget.openRoom == null
          ? () => unawaited(_showInviteDialog(room))
          : () => (widget.openRoom ?? _defaultOpenRoom)(context, room),
    );
  }

  /// 批次 III-c：受邀聊天室 → 接受／拒絕（官方 `Room.join`／`Room.leave`；
  /// 無自製協定邏輯）。接受後開啟 ChatScreen（草案流程）。
  Future<void> _showInviteDialog(Room room) async {
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.t('加入「')}${_roomTitle(room)}」？'), // 文案草案
        content: Text(S.t('你已被邀請加入此聊天室。')), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'decline'),
            child: Text(S.t('拒絕')), // 文案草案（官方 leave）
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'accept'),
            child: Text(S.t('接受')), // 文案草案（官方 join）
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'accept') {
        await room.join();
        await _load();
        if (!mounted) return;
        _defaultOpenRoom(context, room);
      } else {
        await room.leave();
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('操作失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 列表時間：今天 → HH:mm；其他 → MM/DD／YYYY/MM/DD（time_format.dart）。
  String _formatRoomTime(Room room) {
    return formatListTime(room.latestEventReceivedTime);
  }

  /// 第四十二批：重新計算各房間的預覽（**編輯後**內容＋Markdown HTML）。
  ///
  /// 官方 `Room.getTimeline()` 為非同步，故在載入房間後批次計算並放入
  /// `_previews`；列表渲染時同步取用（取不到則退回同步估算）。
  /// 房間數量上限 60，避免首次載入時對 homeserver 過多請求。
  Future<void> _refreshPreviews(List<Room> rooms) async {
    final out = <String, ({String text, String? formatted})>{};
    for (final room in rooms.take(60)) {
      try {
        final timeline = await room.getTimeline();
        final last = room.lastEvent;
        if (last == null) {
          continue;
        }
        var body = last.body;
        String? formatted;
        final edited = _editedContentOf(last);
        if (edited != null) {
          // 編輯事件 → 新內容（避免顯示規格 fallback「* 文字」）。
          body = edited.body;
          formatted = edited.formatted;
        } else {
          try {
            // 編輯：官方聚合解析（僅原作者的編輯有效）。
            final display = last.getDisplayEvent(timeline);
            body = display.body;
            if (display.formattedText.isNotEmpty) {
              formatted = display.formattedText;
            }
          } catch (_) {
            // 官方 API 不可用 → 用原 body。
          }
        }
        // LINE 版位：寄件者 ＋ 動作描述 ＋ 內容。
        final prefix =
            '${_previewSenderName(room, last)}${_previewActionText(last)}';
        out[room.id] = (
          text: prefix.isEmpty ? body : '$prefix$body',
          formatted: formatted,
        );
      } catch (_) {
        // 取不到 timeline（離線等）→ 該房間不進快取。
      }
    }
    if (!mounted) {
      return;
    }
    _previews
      ..clear()
      ..addAll(out);
    setState(() {});
  }

  /// 第四十二批：**編輯事件**（`m.replace`）本身攜帶新內容（`m.new_content`）；
  /// 其 `body` 是規格要求的 fallback（前置 `* `）→ 預覽一律顯示**新內容**。
  ({String body, String? formatted})? _editedContentOf(Event last) {
    try {
      if (last.relationshipType != RelationshipTypes.edit) {
        return null;
      }
      final nc = last.content['m.new_content'];
      if (nc is! Map) {
        return null;
      }
      final body = nc['body'];
      final fb = nc['formatted_body'];
      if (body is! String || body.isEmpty) {
        return null;
      }
      return (
        body: body,
        formatted: fb is String && fb.isNotEmpty ? fb : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 最近事件預覽（相簿首頁預覽文案）；無事件 → 空。
  /// 批次 E：投票事件（unstable/stable 雙前綴）顯示為「投票」而非
  /// SDK fallback 的「Unknown message format of type …」（人類 2026-11-01 實測回報）。
  ///
  /// 第四十二批：**編輯**（官方 `getDisplayEvent` 聚合路徑）與
  /// **Markdown**（`formatted_body`）都套用在預覽上。
  ({String text, String? formatted}) _roomPreview(Room room, Event? last) {
    if (last == null) {
      return (text: '', formatted: null);
    }
    if (kPollStartTypes.contains(last.type)) {
      return (text: '投票', formatted: null); // 文案草案
    }
    if (kPollEndTypes.contains(last.type)) {
      return (text: '投票已結束', formatted: null); // 文案草案
    }
    if (last.type == EventTypes.Encrypted) {
      return (text: '[加密訊息]', formatted: null); // 與聊天室占位一致
    }
    // 2026-11-20：只有帶 Homing 渲染要求旗標的訊息才渲染 Markdown；
    // 舊訊息／其他客戶端（即使有 formatted_body）一律純文字預覽。
    final markdownRequested = last.content[kMarkdownRenderFlag] == true;
    // 第四十二批：編輯事件 → 顯示新內容（其 body 為規格 fallback「* 文字」）。
    final edited = _editedContentOf(last);
    if (edited != null) {
      return (
        text: edited.body,
        formatted: markdownRequested ? edited.formatted : null,
      );
    }
    String? formatted;
    try {
      final fb = last.content['formatted_body'];
      if (markdownRequested && fb is String && fb.isNotEmpty) {
        formatted = fb;
      }
    } catch (_) {}
    return (text: last.body, formatted: formatted);
  }

  /// 第四十二批（LINE 版位）：列表摘要＝**「寄件者 ＋ 動作描述 ＋ 內容」**。
  ///
  /// LINE 的聊天列表摘要會寫明「某人 sent a photo.」這類動作（參考
  /// `LINE_ref/new_ref/homepage/Screenshot_20261102-093135_labeled.png`）。
  /// 繁中版本：群組房顯示寄件者名稱；一對一房不顯示（只有自己與對方）。
  /// 動作描述依事件類型（照片／貼圖／影片／檔案／語音／位置／投票／通話）。
  String _previewActionText(Event last) {
    if (last.type == EventTypes.Sticker) {
      return '傳送了貼圖 ';
    }
    if (last.type == EventTypes.CallInvite) {
      return '[通話] ';
    }
    if (last.type == EventTypes.Message) {
      switch (last.messageType) {
        case 'm.image':
          return '傳送了照片 ';
        case 'm.video':
          return '傳送了影片 ';
        case 'm.audio':
          return '傳送了語音 ';
        case 'm.file':
          return '傳送了檔案 ';
        case 'm.location':
          return '分享了位置 ';
        default:
          return '';
      }
    }
    return '';
  }

  /// 寄件者顯示名稱（群組房摘要前綴；官方 member state → calcDisplayname）。
  String _previewSenderName(Room room, Event last) {
    try {
      if (room.isDirectChat) {
        return '';
      }
      final member =
          room.getState(EventTypes.RoomMember, last.senderId);
      final name = member?.asUser(room).calcDisplayname();
      if (name != null && name.isNotEmpty) {
        return '$name ';
      }
    } catch (_) {
      // 無 member state → 不加前綴。
    }
    return '';
  }

  /// 預覽元件：Markdown 以 RichText 渲染（第四十二批：人類要求
  /// 「聊天室外預覽也應支援 Markdown」）；無 Markdown 則純文字。
  Widget _roomPreviewWidget(String text, String? formatted) {
    // 第六十八批 a（LINE_ref）：深色預覽 #8C8C8C、13px；標題 16px/w600。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? const TextStyle(color: kLineTimeText, fontSize: 13)
        : (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontSize: 13);
    if (formatted != null && formatted.isNotEmpty) {
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: formattedMessageSpans(
            formatted,
            baseStyle: base,
            linkStyle: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }

  void _defaultOpenRoom(BuildContext context, Room room) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(room: room, callManager: widget.callManager),
      ),
    );
  }

  // 顯示名稱：房間名 → 回退至 ID。displayname 計算（hero users 等）待定稿。
  String _roomTitle(Room room) {
    // Issues「私人聊天室無法顯示使用者名稱」：`room.name`（m.room.name）
    // 一對一房間通常為空 → 舊實作顯示 `!roomId`。改 SDK 官方
    // `getLocalizedDisplayname()`（room.dart L228：name → canonicalAlias →
    // directChatMatrixID／heroes 成員名），失敗再退回舊行為。
    try {
      final display = room.getLocalizedDisplayname();
      // SDK 對「無名稱、無成員資訊」的房間回官方 MatrixDefaultLocalizations
      // 的 'Empty chat'（無法代表任何房間）→ 退回 room.id；有顯示名
      //（含 direct chat 成員名）時直接採用。
      if (display.isEmpty || display == 'Empty chat') {
        final name = room.name;
        return name.isNotEmpty ? name : room.id;
      }
      return display;
    } catch (_) {
      final name = room.name;
      return name.isNotEmpty ? name : room.id;
    }
  }
}

/// 房間頭像圓：有 avatar URL 時載入圖片，否則顯示首字。
class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({required this.title, this.avatar, required this.client});

  final String title;
  final Uri? avatar;
  final Client client;

  @override
  Widget build(BuildContext context) {
    final first = title.runes.isEmpty ? null : String.fromCharCode(title.runes.first);
    // direct chat 的 avatar 需 db（測試環境未初始化），以首字 fallback。
    Uri? safeAvatar;
    if (avatar != null) {
      try {
        safeAvatar = avatar;
      } catch (_) {
        safeAvatar = null;
      }
    }
    if (safeAvatar == null) {
      return CircleAvatar(child: Text(first ?? '?'));
    }
    return FutureBuilder<(Uri, bool)>(
      future: () async {
        final uri = await safeAvatar!.getThumbnailUri(client, width: 96, height: 96);
        final auth = await client.authenticatedMediaSupported();
        return (uri, auth);
      }(),
      builder: (context, snap) {
        if (snap.hasData) {
          final (uri, auth) = snap.data!;
          return CircleAvatar(
            backgroundImage: NetworkImage(
              uri.toString(),
              headers: auth
                  ? <String, String>{'authorization': 'Bearer ${client.accessToken}'}
                  : null,
            ),
          );
        }
        return CircleAvatar(child: Text(first ?? '?'));
      },
    );
  }
}

/// 未讀徽章（草案，待人類設計定稿）。
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, this.dotWhenZero = false});

  final int count;

  /// 批次 D：手動標記未讀（account data `m.marked_unread`）時總數可能為 0
  /// ——此時渲染圓點（無數字）。
  final bool dotWhenZero;

  @override
  Widget build(BuildContext context) {
    // 無寫死寬度：以數字內容決定寬度（Container 僅設定基本 padding）。
    // 第六十八批 a（LINE_ref）：未讀徽章＝Line 綠 #4CC764＋白字。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        // 第六十八批 a（LINE_ref）：未讀徽章＝Line 綠 #4CC764＋白字
        // （頂列膠囊同色）；第六十七批黃橙近似值作廢。
        color: kLineGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : (count > 0 ? '$count' : (dotWhenZero ? '•' : '')),
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

/// 第四十二批：LINE 版位的**緊急訊息卡片**（人類提供參考圖）。
///
/// 版位：滿版紅底＋白字；左上＝類別標題（粗體）＋說明（小字）；右側＝廣播 icon
/// ＋**叉叉關閉**（第六十四批⑤：人類指示「右上有關閉選項」）；
/// 下方＝兩個文字動作「傳送現況」「詳細來看」（中線分隔，LINE 同構；
/// 「安否報告」已於⑥改名「傳送現況」）。
/// 有**傳送現況記錄**時（⑥）顯示：現況（沒事／受影響）＋已通報名單。
///
/// 顏色：LINE 緊急紅 `#E8384F`（**草案值，待人類定稿**，見 `UI_SPEC.md`）。
class _EmergencyAlertCard extends StatelessWidget {
  const _EmergencyAlertCard({
    required this.alert,
    required this.timeText,
    required this.onReportSafety,
    required this.onViewDetail,
    required this.onClose,
    this.status,
    this.friendStatuses = const [],
  });

  final EmergencyAlert alert;
  final String timeText;
  final VoidCallback onReportSafety;
  final VoidCallback onViewDetail;

  /// 第六十四批⑤：叉叉關閉（session 隱藏；測試示警另清 kv）。
  final VoidCallback onClose;

  /// 第六十四批⑤：傳送現況記錄（null＝尚未傳送過）。
  final EmergencyStatusRecord? status;

  /// 第六十六批：好友現況（人類指示「顯示哪些好友受影響和沒受影響」）。
  /// 來源＝各 1:1 房最新訊息解析（rooms_screen `_loadFriendStatuses`）。
  final List<({String name, bool affected})> friendStatuses;

  /// LINE 緊急紅（草案值）。
  static const Color kEmergencyRed = Color(0xFFE8384F);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kEmergencyRed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (timeText.isNotEmpty) timeText,
                          alert.summary,
                        ].join('　'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      // 第六十四批⑤：現況＋已通報名單（傳送過才顯示）。
                      if (status != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          [
                            '${S.t('現況')}：${S.t(status!.affected ? '受影響' : '沒事')}',
                            if (status!.notified.isNotEmpty)
                              '${S.t('已通報')}：'
                                  '${status!.notified.map((n) => n.name).join('、')}',
                          ].join('　'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      // 第六十六批：好友現況（有解析到才顯示；人類指示「顯示
                      // 哪些好友受影響和沒受影響」）。
                      if (friendStatuses.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${S.t('好友現況')}：'
                              '${friendStatuses.map((f) => '${f.name}（${S.t(f.affected ? '受影響' : '沒事')}）').join('、')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                CompoundIcon(
                  CompoundIcons.notifications,
                  color: Colors.white,
                  size: 34,
                ), // 廣播 icon（Compound；原 AllIcons.campaign 無對應）
                // 第六十四批⑤：右上叉叉關閉（人類指示）。
                a11yButton(
                  label: S.t('關閉'),
                  child: IconButton(
                    tooltip: S.t('關閉'),
                    onPressed: onClose,
                    icon: CompoundIcon(CompoundIcons.close,
                        size: 24, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          // 動作列：「傳送現況」｜「詳細來看」
          Container(height: 1, color: Colors.white24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: onReportSafety,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(S.t('傳送現況')), // 草案文案（⑥由「安否報告」改名）
                ),
              ),
              Container(width: 1, height: 20, color: Colors.white24),
              Expanded(
                child: TextButton(
                  onPressed: onViewDetail,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(S.t('詳細來看')), // 草案文案（LINE：詳細を見る）
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
