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
import '../app_settings.dart';
import '../emergency_feed.dart'; // 批次十六：PWS RSS 緊急示警
import '../offline_queue.dart';
import '../pinned_rooms.dart';
import '../poll_compat.dart';
import '../voip/call_manager.dart';
import 'device_verification_dialog.dart';
import 'room_actions.dart'; // 第二十五批：「＋」三選項與建立／加入公開房共用流程
import 'settings_screen.dart'; // 第二十五批：頭像面板內嵌 SettingsBody
import 'time_format.dart';

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
  const RoomsScreen({super.key, required this.client, this.loadRooms, this.openRoom, this.onLogout, this.recoverEncryption, this.callManager, this.emergencyAlerts = const []});

  final Client client;
  final RoomsLoader? loadRooms;
  final RoomOpener? openRoom;

  /// 批次十六：PWS RSS 緊急示警（官方 NCDR 聚合 feed；由 main_shell 前景
  /// 輪詢（15 分鐘、僅 Actual＋未過期＋高風險類別＝人類決定 2026-11-07）。
  /// 預設空清單（測試無網路；banner-only 不彈通知）。
  final List<EmergencyAlert> emergencyAlerts;

  /// 通話管理（P2.15 提案）：透傳至 ChatScreen（null 時聊天畫面不顯示通話鈕）。
  final CallManager? callManager;

  /// 登出出口（骨架：回呼後由上一層導航；未提供則呼叫 SDK logout 並顯示訊息）。
  final Future<void> Function(Client client)? onLogout;

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

  /// 批次十二⑤（Phase 4.2 草案）：首頁緊急訊息橫幅＝「公告房間」（room_info
  /// 本機旗標）的最新**官方**釘選訊息。觸發條件為草案，待人類定稿（可否決）。
  List<({String roomId, String title, String text})> _emergency = const [];
  String _lastEmergencyFingerprint = '';

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
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
    // 批次十二⑤：首頁緊急橫幅刷新（公告房間 ∩ 官方釘選；有變才 setState）。
    unawaited(_loadEmergency());
  }

  /// 批次十二⑤（Phase 4.2 草案）：橫幅資料＝AppSettings 公告房間旗標（純本機）
  /// ∩ `Room.pinnedEventIds`（官方 room.dart L185）最新一筆，內容查
  /// `Room.getEventById`（官方 room.dart L2225）。指紋比對避免每次 sync setState。
  Future<void> _loadEmergency() async {
    if (!mounted) {
      return;
    }
    Set<String> announce;
    try {
      announce = await AppSettings.announcementRooms();
    } catch (_) {
      return;
    }
    if (announce.isEmpty) {
      if (_lastEmergencyFingerprint.isNotEmpty) {
        _lastEmergencyFingerprint = '';
        if (mounted) {
          setState(() => _emergency = const []);
        }
      }
      return;
    }
    final roomList = [
      for (final room in widget.client.rooms)
        if (announce.contains(room.id)) room,
    ];
    final lines = <String>[];
    final banners = <({String roomId, String title, String text})>[];
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
      final id = ids.last;
      lines.add('${room.id}:$id');
      Event? ev;
      try {
        ev = await room.getEventById(id); // 官方（room.dart L2225）
      } catch (_) {}
      final body =
          (ev == null || ev.redacted) ? '' : (ev.body.isNotEmpty ? ev.body : '');
      if (body.isEmpty) {
        continue;
      }
      String name = room.id;
      try {
        final n = room.getLocalizedDisplayname(); // 官方（room.dart L228）
        if (n.isNotEmpty && n != 'Empty chat') {
          name = n;
        }
      } catch (_) {}
      banners.add((roomId: room.id, title: name, text: body));
    }
    final fp = lines.join('|');
    if (fp == _lastEmergencyFingerprint) {
      return;
    }
    _lastEmergencyFingerprint = fp;
    if (mounted) {
      setState(() => _emergency = banners);
    }
  }

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

  /// 點擊橫幅 → 開啟公告聊天室（骨架行為草案）。
  void _openEmergencyRoom(String roomId) {
    for (final room in widget.client.rooms) {
      if (room.id == roomId) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(room: room, callManager: widget.callManager),
          ),
        );
        return;
      }
    }
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
        title: const Text('恢復加密身分'), // 文案待 UI 定稿
        content: TextField(
          controller: controller,
          obscureText: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Recovery key',
            hintText: '貼上 Element / matrix.org 產生的 recovery key',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('恢復'),
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
        const SnackBar(
          content: Text('加密身分已恢復；請在 Element 重新整理頁面以同步驗證狀態'),
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
        SnackBar(content: Text('恢復失敗：$e')),
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openAvatarAccountSheet,
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
            const SizedBox(width: 12),
            Text(
              '聊天', // 文案待 UI 定稿；草案，非最終視覺
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          // 恢復加密（異常時才出現；藍圖 1.5 保持原樣）。
          if (!_encryptionRecovered)
            TextButton(
              onPressed: _recoverEncryption,
              child: const Text('恢復加密'),
            ),
          // （第二十一批）「新增」鈕依 mockup 移入搜尋列右端。
          // 第二十五批（人類指示）：驗證／診斷移入設定進階區 → 選單只剩登出。
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'logout':
                  _onLogout();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'logout', child: Text('登出')),
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
                    decoration: const InputDecoration(
                      // 批次 III-a（人類指示）：「搜尋對話」→「搜尋聊天室」。
                      hintText: '搜尋聊天室',
                      hintStyle: TextStyle(color: kTextSecondary),
                      prefixIcon: Icon(Icons.search, color: kTextSecondary),
                      isDense: true,
                      filled: true,
                      fillColor: kSearchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '新增', // 文案草案，待人類設計定稿
                  onPressed: _showAddSheet,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: '加入好友（Matrix ID／QR）',
                  onPressed: _openAddFriend,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
          ),
          // 批次十二⑤（Phase 4.2 草案）：緊急訊息橫幅座（new_ref/home 頂部職
          // 位）——公告房間的最新官方釘選訊息；點擊開啟聊天室。紅色系（配色
          // 與樣式待人類設計定稿）。
          for (final b in _emergency)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.campaign_outlined),
                title: Text(
                  '緊急：${b.text}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ), // 文案草案
                subtitle: Text(b.title), // 來源聊天室名稱（文案草案）
                onTap: () => _openEmergencyRoom(b.roomId),
              ),
            ),
          // 批次十六：PWS RSS 緊急示警（官方 NCDR 聚合 feed；僅 Actual＋未
          // 過期＋高風險類別）。與「公告房間」橫幅並列同座（v0 無詳情頁；
          // onTap=null 不導航）。
          for (final e in widget.emergencyAlerts) ...[
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(
                  '緊急：${e.category}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ), // 文案草案
                subtitle: Text(
                  '${e.sender}・${_alertTime(e)}\n${e.summary}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: null, // v0：無詳情頁（骨架；接力人類設計定稿）
              ),
            ),
          ],
          if (widget.emergencyAlerts.isNotEmpty)
            // 批次十六：顯名＋免責（政府資料開放授權條款第 3 條(二)顯名義務；
            // 資料機關可隨時停止提供／不負賠償 → 小字敘述）。文案草案。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                '$kEmergencyFeedAttribution\n'
                '示警可能延遲或不完整；緊急時請以中央氣象署及地方政府原發布管道為準。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
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
                          // 第二十五批（人類指示「首頁的 Spaces 拿掉」）：Spaces
                          // 收合區塊刪除——Space 歸聯絡人「群組」區塊（點開
                          // Space 底下聊天室清單，見 contacts_screen）。
                          for (final room in filtered) _buildRoomTile(room),
                          // 已隱藏對話（本機過濾，不刪伺服器資料）；收合展開。
                          if (hiddenRooms.isNotEmpty && _search.isEmpty) ...[
                            InkWell(
                              onTap: () => setState(() => _hiddenExpanded = !_hiddenExpanded),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      _hiddenExpanded ? Icons.expand_more : Icons.expand_less,
                                      size: 18,
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
                            if (_hiddenExpanded)
                              for (final room in hiddenRooms)
                                ListTile(
                                  leading: const Icon(Icons.visibility_off_outlined),
                                  title: Text(_roomTitle(room)),
                                  trailing: TextButton(
                                    child: const Text('取消隱藏'), // 文案草案
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
                child: Text(
                  '設定', // 文案待人類定稿（草案）
                  style: Theme.of(ctx).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
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
            content: Text('已隱藏「${_roomTitle(room)}」'), // 文案草案
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失敗：$e')),
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
          SnackBar(content: Text('操作失敗：$e')),
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
        title: Text('刪除「${_roomTitle(room)}」？'), // 文案草案
        content: const Text('這會退出聊天室並讓本裝置不再顯示該對話（伺服器端）。\n' '此操作無法在本裝置復原。'), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
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
          SnackBar(content: Text('刪除失敗：$e')),
        );
      }
    }
  }

  Widget _buildRoomTile(Room room) {
    final last = room.lastEvent;
    final preview = _roomPreview(room, last);
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
      title: Text(_roomTitle(room)),
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(muted ? Icons.notifications : Icons.notifications_off),
                  title: Text(muted ? '取消靜音' : '靜音'), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'mute'),
                ),
                ListTile(
                  leading: Icon(_pinned.contains(room.id) ? Icons.push_pin : Icons.push_pin_outlined),
                  title: Text(_pinned.contains(room.id) ? '取消釘選' : '釘選'), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'pin'),
                ),
                // 未讀/已讀**互斥**（人類回饋 2026-11-03「未讀訊息不應出現
                // 『標記為未讀』」）：未讀 → 只顯示「標記為已讀」（官方
                // `setReadMarker`＋`markUnread(false)`）；已讀 → 只顯示
                // 「標記為未讀」（官方 `Room.markUnread(true)`）。
                ListTile(
                  leading: Icon(room.isUnread
                      ? Icons.mark_chat_read_outlined
                      : Icons.mark_chat_unread_outlined),
                  title: Text(room.isUnread ? '標記為已讀' : '標記為未讀'), // 草案文案
                  onTap: () => Navigator.pop(ctx, room.isUnread ? 'read' : 'unread'),
                ),
                // Issues「增加隱藏／刪除對話」：隱藏＝本機過濾；刪除＝官方
                // `Room.leave`＋`Room.forget`（伺服器端收回，需確認）。
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('隱藏對話'), // 草案文案
                  onTap: () => Navigator.pop(ctx, 'hide'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('刪除對話'), // 草案文案
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
                SnackBar(content: Text('操作失敗：$e')),
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
                SnackBar(content: Text('操作失敗：$e')),
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
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗：$e')));
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
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗：$e')));
          }
        }
      },
      subtitle: isInvite
          // 批次 III-c：受邀房間明確顯示邀請狀態（點按 → 接受／拒絕流程）。
          ? const Text('邀請中（點按處理）') // 文案草案
          : Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_formatRoomTime(room), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pinned.contains(room.id)) ...[
                Icon(Icons.push_pin, size: 14, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 4),
              ],
              if (muted) ...[
                Icon(
                  Icons.notifications_off,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
              ],
              // 未讀徽章：SDK 官方（notificationCount ＋ account data
              // m.marked_unread）；點數＝手動標記未讀。
              if (unread) _UnreadBadge(count: unreadCount, dotWhenZero: true),
            ],
          ),
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
        title: Text('加入「${_roomTitle(room)}」？'), // 文案草案
        content: const Text('你已被邀請加入此聊天室。'), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'decline'),
            child: const Text('拒絕'), // 文案草案（官方 leave）
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'accept'),
            child: const Text('接受'), // 文案草案（官方 join）
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
          SnackBar(content: Text('操作失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 列表時間：今天 → HH:mm；其他 → MM/DD／YYYY/MM/DD（time_format.dart）。
  String _formatRoomTime(Room room) {
    return formatListTime(room.latestEventReceivedTime);
  }

  /// 最近事件預覽（相簿首頁預覽文案）；無事件 → 空。
  /// 批次 E：投票事件（unstable/stable 雙前綴）顯示為「投票」而非
  /// SDK fallback 的「Unknown message format of type …」（人類 2026-11-01 實測回報）。
  String _roomPreview(Room room, Event? last) {
    if (last == null) {
      return '';
    }
    if (kPollStartTypes.contains(last.type)) {
      return '投票'; // 文案草案
    }
    if (kPollEndTypes.contains(last.type)) {
      return '投票已結束'; // 文案草案
    }
    switch (last.type) {
      case EventTypes.Message:
        return last.body; // msgtype 的預覽後綴（如 [圖片]）待人類定稿
      case EventTypes.Encrypted:
        return '[加密訊息]'; // 與聊天室占位一致
      default:
        return last.body;
    }
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : (count > 0 ? '$count' : (dotWhenZero ? '•' : '')),
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
