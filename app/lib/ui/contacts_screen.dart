// 任務 Phase 1 / 1.7 — 聯絡人列表（草案待人類設計）。
// UI 重構（依人類 LINE_ref 標註，2026-11-01）：好友／群組兩小節。
// 第二十一批：三個膠囊 tab（帶數量）＋搜尋列＋FAB「＋」；空文案照稿。
// 第二十三批（人類 2026-11-08 指示「重新分類照 LINE 模型」）：
//   一對一＝好友；私密多人（官方 join rule 非 public）＝群組；已加入的
//   公開聊天室（官方 `Room.joinRules == public`）＝公開聊天室 tab。
//   「加入公開聊天室」（瀏覽遠端公開房目錄）＝首頁「＋」新增選項（此頁不再
//   拉 getPublicRooms）。頂列兩顆 icon 依 mockup 仍移除（加入好友→FAB）。
// 第二十五批（人類四項整合指示；拍板補充）：
//   ①Space 一律歸「群組」區塊（`_isPublicRoom` 排除 `Room.isSpace`——
//     避免 public joinRules 的 Space 誤落第三塊）；群組中的 Space tile 點擊
//     → Space 底下聊天室清單（官方 getSpaceHierarchy）。
// 2026-11-20（人類指示）：撤銷第七十九批的 Space 第四 tab，回復本條「Space 一律
//   歸群組」語意；Space tile 點開仍走官方 getSpaceHierarchy（見 _buildContactTile）。
//   ②FAB「＋」＝三選項（人類拍板：加入個人／群組＝建立聊天室／公開聊天室
//     ＝加入既有公開房）——sheet＋流程與首頁「＋」共用（room_actions.dart）。
//   ③首頁 Spaces 區塊移除；「公開聊天室」移至第三區塊、私群組（自建／受邀）
//     第二區塊（既有分類語意，明文固定）。
// 本地 cache：Task 1.7 引用 client.rooms 的 direct chat 房間作為「聯絡人」展示；
// 實際 cache 由 SDK internal DB 維護（matrix-dart-sdk）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import '../local_nicknames.dart'; // 第七十九批：本機暱稱
import 'add_friend_screen.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'design_tokens.dart';
import 'room_actions.dart'; // 第二十五批：FAB 三選項／Space 聊天室清單共用流程
import '../voip/call_manager.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import './a11y.dart'; // 無障礙：按鈕功能說明
import 'line_style.dart';
import 'compound_icon.dart'; // 68c–68f：LINE 自繪圖示

typedef ContactsLoader = Future<List<Room>> Function(Client client);

typedef ContactOpener = void Function(BuildContext context, Room room);

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.client,
    this.loadContacts,
    this.openContact,
    this.callManager,
    this.resolveJoinRules,
  });

  final Client client;
  final ContactsLoader? loadContacts;
  final ContactOpener? openContact;

  /// 通話管理（P2.15 提案）：透傳至 ChatScreen（null 時聊天畫面不顯示通話鈕）。
  final CallManager? callManager;

  /// 第二十六批：join_rules 兜底抽換點（測試／另鏈注入；null＝正式鏈＝
  /// 官方 `getRoomStateWithKey` 補查，見 `_effectiveJoinRules`）。
  final JoinRules? Function(Room room)? resolveJoinRules;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String? _message;
  bool _loading = true;
  // 批次十五（好友控制）：收藏好友＝本機 kv（favorite_contacts，roomId 集合）；
  // 隱藏沿用既有 hidden_rooms 表（rooms_screen 同源），聯絡人頁同樣過濾。
  Set<String> _favoriteContacts = {};
  Set<String> _hiddenRooms = {};

  // 第二十一批：膠囊 tab 狀態（0＝好友／1＝群組／2＝公開聊天室）＋搜尋。
  //  第二十三批（人類拍板 LINE 模型重新分類）：公開聊天室 tab＝**已加入**的
  //  公開房（官方 joinRules==public）；「加入公開聊天室」（瀏覽遠端目錄）＝
  //  首頁「＋」新增選項（不再在聯絡頁拉 getPublicRooms）。
  int _contactsTab = 0;
  final TextEditingController _contactSearchController =
      TextEditingController();
  String _contactSearch = '';

  @override
  void initState() {
    super.initState();
    _load();
    // 收藏／隱藏清單較 _load 晚就緒也無妨；載入後 setState 重排（favorite 置頂）。
    unawaited(_loadLocalState());
  }

  @override
  void dispose() {
    _contactSearchController.dispose();
    super.dispose();
  }

  /// 批次十五：讀回本機收藏清單（kv 是單一 key 的 json 陣列字串）＋隱藏清單。
  Future<void> _loadLocalState() async {
    try {
      final hidden = await AppSettings.hiddenRooms();
      if (mounted) {
        setState(() => _hiddenRooms = hidden);
      }
    } on Object {
      // 無 DB 環境（測試）或讀取失敗：不過濾，功能退化但不影響列表。
    }
    try {
      final v = await AppSettings.get('favorite_contacts');
      if (v != null && v.isNotEmpty) {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          final ids = decoded.whereType<String>().toSet();
          if (mounted) {
            setState(() => _favoriteContacts = ids);
          }
        }
      }
    } on Object {
      // 無 DB 環境或格式錯：收藏視為空（不影響既有列表）。
    }
  }

  Future<void> _persistFavorites() async {
    try {
      await AppSettings.set(
        'favorite_contacts',
        jsonEncode(_favoriteContacts.toList()),
      );
    } on Object {
      // 落盤失敗：本 session 排序仍有效，下次切換收藏時重寫。
    }
  }

  Future<List<Room>> _defaultLoad(Client client) async {
    return client.rooms;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _message = null;
    });

    List<Room> items;
    try {
      items = await (widget.loadContacts ?? _defaultLoad)(widget.client);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '無法載入聯絡人：請檢查網路';
      });
      return;
    }
    if (!mounted) return;
    // 批次十五：聯絡人頁尊重本機隱藏清單（hidden_rooms 與 rooms_screen 同源）。
    final visible = items.where((r) => !_hiddenRooms.contains(r.id)).toList();
    final direct = visible.where((r) => r.isDirectChat).toList()
      ..sort((a, b) => b.latestEventReceivedTime
          .compareTo(a.latestEventReceivedTime));
    // 第二十三批修正（人類 2026-11-08 指示「重新分類照 LINE 模型」）：
    //   一對一＝好友；私密多人（join rule 非 public）＝群組；
    //   已加入的公開聊天室（官方 `Room.joinRules == public`）＝公開聊天室。
    // 無 state／判別失敗 → 保守歸「群組」（LINE 語意：預設私密）。
    final others = visible.where((r) => !r.isDirectChat).toList();
    // 第二十六批（實機回報「公開聊天室仍無法分開」47 房全落群組根因）：
    // SDK 14.2.0 重啟後 partial 房間記憶體缺 m.room.join_rules（
    // importantStateEvents 不含它）→ `Room.joinRules` null。先以官方
    // 單一 state 端點補查（session 快取；人類拍板）再分類。
    final rulesOf = <Room, JoinRules?>{};
    for (final room in others) {
      rulesOf[room] = await _effectiveJoinRules(room);
    }
    // 2026-11-20（人類指示）：Space 回「群組」，撤銷第七十九批第四 tab。
    // `_isPublicRoom` 本身已排除 `Room.isSpace`，故 public join rule 的 Space
    // 仍落群組；點 Space tile 走官方 getSpaceHierarchy（見 _buildContactTile）。
    final publicJoined =
        others.where((r) => _isPublicRoom(r, rulesOf[r])).toList()
          ..sort((a, b) => b.latestEventReceivedTime
              .compareTo(a.latestEventReceivedTime));
    final groups = others.where((r) => !_isPublicRoom(r, rulesOf[r])).toList()
      ..sort((a, b) => b.latestEventReceivedTime
          .compareTo(a.latestEventReceivedTime));
    setState(() {
      _loading = false;
      _friends = direct;
      _groups = groups;
      _publicJoined = publicJoined;
    });
  }

  /// 第二十三批：官方 join rule 判別（SDK `Room.joinRules`）；null／未知 →
  /// 不視為公開（保守歸群組）。
  /// 第二十五批（人類拍板）：Space **一律**歸「群組」——即使 join rule 為
  /// public（Space 是容器不是聊天室，誤落公開區塊會拆散 Space 結構）。
  static bool _isPublicRoom(Room room, JoinRules? rules) {
    try {
      return !room.isSpace && rules == JoinRules.public;
    } on Object {
      return false;
    }
  }

  /// 第二十六批：join_rules 兜底。
  /// 根因（實機 47 房全落群組）：SDK 14.2.0 重啟後房間為 partial，記憶體
  /// states 只載「重要」清單（client.dart L275-284：RoomName／Avatar／
  /// Encryption／CanonicalAlias／Tombstone／SpaceChild／SpaceParent／
  /// RoomCreate）**未含 join_rules** → `Room.joinRules`（room.dart L2644）
  /// 恆 null。離線 DB 也無單型讀取 API（`getUnimportant...` 為排除清單
  /// 語意＝會把整房 m.room.member 事件撈出，過重）。
  /// 本函式：①記憶體有值直接回（sync 更新過的房間／重建 session）；②否則
  /// 一次 session 快取＋官方 `Client.getRoomStateWithKey`（matrix_api_lite
  /// generated api.dart L5045＝GET /rooms/{roomId}/state/{type}/{stateKey}，
  /// 已加入房間可用）補查；③成功同時以官方 `StrippedStateEvent` 補進記憶體
  /// states（同 session 其他 getter 受益）；④查失敗 → null（保守歸群組，
  /// 原行為）。`widget.resolveJoinRules`＝測試／另鏈注入點（不觸網）。
  final Map<String, JoinRules?> _joinRulesCache = {};

  Future<JoinRules?> _effectiveJoinRules(Room room) async {
    try {
      final local = room.joinRules;
      if (local != null) {
        return local;
      }
    } on Object {
      return null;
    }
    if (_joinRulesCache.containsKey(room.id)) {
      return _joinRulesCache[room.id];
    }
    final hook = widget.resolveJoinRules;
    JoinRules? fetched;
    if (hook != null) {
      try {
        fetched = hook(room);
      } on Object {
        fetched = null;
      }
    } else {
      String? text;
      try {
        final content = await widget.client.getRoomStateWithKey(
          room.id,
          EventTypes.RoomJoinRules,
          '',
        );
        text = content.tryGet<String>('join_rule');
        for (final rule in JoinRules.values) {
          if (rule.text == text) {
            fetched = rule;
            break;
          }
        }
      } on Object {
        fetched = null;
      }
      if (fetched != null) {
        try {
          room.setState(
            StrippedStateEvent(
              type: EventTypes.RoomJoinRules,
              content: <String, Object?>{'join_rule': text},
              senderId: widget.client.userID ?? '',
              stateKey: '',
            ),
          );
        } on Object {
          // 記憶體補 state 失敗不影響本次分類（fetched 已有值；既有房間
          // 下次啟動由 importantStateEvents 持久化路線補齊）。
        }
      }
    }
    _joinRulesCache[room.id] = fetched;
    return fetched;
  }

  List<Room> _friends = const [];
  List<Room> _groups = const [];
  List<Room> _publicJoined = const [];

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

  /// 第二十五批（人類拍板）：FAB「＋」→ 三選項 sheet——與首頁「＋」共用
  /// room_actions（同 sheet＋同流程）。公開房加入後 `_load` 重算分類。
  Future<void> _showAddSheet() async {
    await runAddChatSheet(
      context,
      client: widget.client,
      openAddFriend: _openAddFriend,
      callManager: widget.callManager,
      onRoomsChanged: _load,
      openRoom: (ctx, room) =>
          (widget.openContact ?? _defaultOpen)(ctx, room),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 第二十一批（mockup）：頂列僅大標題（加入好友→FAB；設定→底列 tab，
      // 原 appbar 兩顆 icon 移除＝行為跟著變，完成報告披露）。
      // 第四十一批（LINE 版位）：頂列＝大標題「好友」＋右側 icon 組
      // （新增好友／掃碼）；LINE 的 Friends 頁把「新增」放在右上 icon，
      // 本 App 保留底部 FAB（較易觸及）並在頂列加「新增好友／掃碼」快捷。
      appBar: AppBar(
        // 第七十五批（68c）：標題改 LINE 綠膠囊（與聊天列表同構）。
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: kLineGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            S.t('好友'),
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        actions: [
          a11yButton(label: S.t('新增好友（Matrix ID／QR）'), child: IconButton(
            tooltip: S.t('新增好友（Matrix ID／QR）'),
            onPressed: _showAddSheet,
            icon: lineIconWithTestFallback(Icons.person_add_alt_1_outlined, LineIcon.personAdd, size: 22, color: Theme.of(context).colorScheme.onSurface),
          )),
          a11yButton(label: S.t('加入好友（掃碼）'), child: IconButton(
            tooltip: S.t('加入好友（掃碼）'),
            onPressed: _openAddFriend,
            icon: lineIconWithTestFallback(Icons.qr_code_scanner, LineIcon.scan, size: 22, color: Theme.of(context).colorScheme.onSurface),
          )),
        ],
      ),
      // 第二十一批（mockup）：FAB＝圓角方「＋」。
      // 第二十五批（人類拍板）：點擊 → 三選項 sheet（加入個人／群組＝建立
      // 聊天室／公開聊天室＝加入既有公開房）；與首頁「＋」共用 room_actions。
      floatingActionButton: FloatingActionButton(
        tooltip: S.t('新增'), // 文案草案，待人類設計定稿
        backgroundColor: kFabFill,
        foregroundColor: kTextPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: _showAddSheet,
        child: lineIconWithTestFallback(Icons.add, LineIcon.plus, size: 22, color: Theme.of(context).colorScheme.onSurface),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 搜尋列（mockup：hint 搜尋；token 樣式同首頁）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: TextField(
                    controller: _contactSearchController,
                    onChanged: (v) => setState(() => _contactSearch = v.trim()),
                    decoration: InputDecoration(
                      hintText: S.t('搜尋名稱'),
                      hintStyle: TextStyle(color: kTextSecondary),
                      prefixIcon: Icon(AllIcons.search, color: kTextSecondary),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? kLineBar
                          : kSearchFill,
                      border: OutlineInputBorder(
                        // 第四十一批（LINE 版位）：膠囊形搜尋列（圓角 24dp）。
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                  ),
                ),
                _buildContactTabs(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_message!),
                    ),
                  ),
                Expanded(child: _contactTabContent()),
              ],
            ),
    );
  }

  /// 第四十三批（LINE 版位，依 `LINE_ref/new_ref/friends/Screenshot_20261104-172742_labeled.png`）：
  /// 分段＝**文字標籤 ＋ 底部指示線**（LINE 的 Favorites／Friends／Groups／Official accounts），
  /// 取代第二十一批的「白膠囊＋選中灰 chip」。
  ///
  /// Homing 的對應：好友／群組／公開聊天室（LINE 的 Favorites 與 Official accounts
  /// 在 Homing 另有語意：收藏＝好友長按選單；官方帳號＝藍圖 P3，尚未實作）。
  Widget _buildContactTabs() {
    const labels = ['好友', '群組', '公開聊天室'];
    final counts = [
      _friends.length,
      _groups.length,
      _publicJoined.length,
    ];
    return Row(
      children: [
        for (final (index, label) in labels.indexed)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _contactsTab = index),
              child: Semantics(
                button: true,
                selected: _contactsTab == index,
                child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '$label (${counts[index]})',
                      style: TextStyle(
                        color: _contactsTab == index ? kTextPrimary : kTextSecondary,
                        fontWeight:
                            _contactsTab == index ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  // 底部指示線（選中＝Homing 主色；未選＝透明）。
                  Container(
                    height: 2,
                    color: _contactsTab == index ? kAccent : Colors.transparent,
                  ),
                ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 第二十一批：依選中 tab 顯示好友／群組／公開聊天室列表（搜尋過濾）。
  Widget _contactTabContent() {
    final query = _contactSearch.toLowerCase();
    switch (_contactsTab) {
      case 0:
        final list = _sortedFriends()
            .where((r) =>
                query.isEmpty || _friendName(r).toLowerCase().contains(query))
            .toList();
        if (list.isEmpty) {
          return _contactEmpty(
            _friends.isEmpty ? '加個好友吧！' : '沒有符合的搜尋', // 稿文案／草案
          );
        }
        return ListView(
          children: [for (final room in list) _buildContactTile(room)],
        );
      case 1:
        final list = _groups
            .where((r) =>
                query.isEmpty || _friendName(r).toLowerCase().contains(query))
            .toList();
        if (list.isEmpty) {
          return _contactEmpty(
            _groups.isEmpty ? '沒有群組' : '沒有符合的搜尋', // 沿用草案
          );
        }
        return ListView(
          children: [for (final room in list) _buildContactTile(room)],
        );
      default:
        // 第二十三批（LINE 模型）：公開聊天室 tab＝**已加入**的公開房
        // （官方 joinRules==public；_load 分類）。瀏覽／加入遠端目錄＝
        // 首頁「＋」新增選項。
        final list = _publicJoined
            .where((r) =>
                query.isEmpty || _friendName(r).toLowerCase().contains(query))
            .toList();
        if (list.isEmpty) {
          return _contactEmpty(
            _publicJoined.isEmpty
                ? '還沒有加入公開聊天室\n（用「＋」加入公開聊天室）' // 文案草案（二十五批：入口改本頁 FAB）
                : '沒有符合的搜尋',
          );
        }
        return ListView(
          children: [for (final room in list) _buildContactTile(room)],
        );
    }
  }

  Widget _contactEmpty(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildContactTile(Room room) {
    // Issues（人類回饋 2026-11-03「好友名稱在聯絡人仍然無法顯示名稱」）：
    // 舊邏輯 `room.name: empty → room.id` 對 direct chat 顯示 `!roomId`。
    // 改官方 `Room.getLocalizedDisplayname()`（room.dart L228：
    // name → canonicalAlias → directChatMatrixID／heroes 成員名）；SDK 對
    // 無名稱無成員的房間回 'Empty chat' → 退回 room.id。
    String title;
    try {
      final display = room.getLocalizedDisplayname();
      title = (display.isEmpty || display == 'Empty chat')
          ? (room.name.isNotEmpty ? room.name : room.id)
          : display;
    } catch (_) {
      title = room.name.isNotEmpty ? room.name : room.id;
    }
    // 批次 III-a（人類回報「聯絡人標籤頁中沒有顯示頭像」）：direct chat 也
    // 讀取對方頭像；沿用批次 I 於 rooms_screen 的官方認證媒體路徑
    // （getThumbnailUri＋authenticatedMediaSupported→Bearer header），
    // 失敗／無 db（測試環境）→ 首字 fallback，不出錯。
    Widget leading = CircleAvatar(child: Text(_initialChecked(title)));
    final avatarFuture = _avatarThumbnail(room);
    if (avatarFuture != null) {
      leading = FutureBuilder<(Uri, bool)>(
        future: avatarFuture,
        builder: (context, snap) {
          if (snap.hasData) {
            final (uri, auth) = snap.data!;
            return CircleAvatar(
              backgroundImage: NetworkImage(
                uri.toString(),
                headers: auth
                    ? <String, String>{'authorization': 'Bearer ${widget.client.accessToken}'}
                    : null,
              ),
            );
          }
          return CircleAvatar(child: Text(_initialChecked(title)));
        },
      );
    }

    // 批次十五：收藏（星形）／已封鎖（禁止符）尾端圖示（樣式依人類定稿調整）。
    Widget? trailing;
    if (room.isDirectChat) {
      final mxid = room.directChatMatrixID;
      if (_favoriteContacts.contains(room.id)) {
        trailing = Icon(AllIcons.star, size: 20);
      } else if (mxid != null &&
          mxid.isNotEmpty &&
          widget.client.ignoredUsers.contains(mxid)) {
        trailing = Icon(AllIcons.block, size: 20);
      }
    }

    // 第二十五批（人類指示「Spaces 整合在聯絡人群組裡」）：Space tile 的
    // 點擊＝開「Space 底下的聊天室」清單（官方 getSpaceHierarchy；空間不是
    // 聊天室，不應像群組一樣直接開 ChatScreen）。
    final bool isSpaceTile = room.isSpace;

    return ListTile(
      leading: leading,
      title: Text(
        room.isDirectChat && room.directChatMatrixID != null
            ? localDisplayName(room.directChatMatrixID!, title)
            : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: isSpaceTile
          ? () => unawaited(showSpaceRoomsSheet(
                context,
                widget.client,
                room,
                callManager: widget.callManager,
                onRoomsChanged: _load,
                openRoom: (ctx, r) =>
                    (widget.openContact ?? _defaultOpen)(ctx, r),
              ))
          : () => (widget.openContact ?? _defaultOpen)(context, room),
      // 批次十五（好友控制）：長按好友 → 動作選單（聊天／語音通話／收藏／
      // 隱藏／刪除好友／封鎖）；群組維持原行為（僅點擊開啟）。
      onLongPress:
          room.isDirectChat ? () => unawaited(_showFriendActions(room)) : null,
    );
  }

  /// 批次十五：好友（direct chat）依收藏置頂，其餘維持原排序（最新訊息在上）。
  List<Room> _sortedFriends() {
    List<Room> list = [..._friends];
    if (_favoriteContacts.isEmpty) {
      return list;
    }
    list.sort((a, b) {
      final fa = _favoriteContacts.contains(a.id) ? 0 : 1;
      final fb = _favoriteContacts.contains(b.id) ? 0 : 1;
      if (fa != fb) {
        return fa.compareTo(fb);
      }
      return b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);
    });
    return list;
  }

  /// 批次 III-a：頭像縮圖（官方 getThumbnailUri＋認證媒體 header 判斷）。
  /// 非 direct → Room.avatar（m.room.avatar）；direct → 對方成員事件的
  /// avatar_url（state 讀取，不觸發 db getUser——測試環境會 LateError）。
  /// 失敗回 null → 首字 fallback。
  Future<(Uri, bool)>? _avatarThumbnail(Room room) {
    final avatar = _avatarUriFor(room);
    if (avatar == null) {
      return null;
    }
    try {
      return () async {
        final uri = await avatar.getThumbnailUri(widget.client, width: 64, height: 64);
        final auth = await widget.client.authenticatedMediaSupported();
        return (uri, auth);
      }();
    } on Object {
      return null;
    }
  }

  Uri? _avatarUriFor(Room room) {
    try {
      if (!room.isDirectChat) {
        return room.avatar;
      }
      final mxid = room.directChatMatrixID;
      if (mxid == null || mxid.isEmpty) {
        return null;
      }
      final member = room.getState(EventTypes.RoomMember, mxid);
      final url = member?.content['avatar_url'];
      if (url is String && url.isNotEmpty) {
        return Uri.tryParse(url);
      }
      return null;
    } on Object {
      return null;
    }
  }

  static String _initialChecked(String? raw) {    if (raw == null || raw.isEmpty || raw.runes.isEmpty) {
      return '?';
    }
    return String.fromCharCode(raw.runes.first);
  }

  void _defaultOpen(BuildContext context, Room room) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(room: room, callManager: widget.callManager),
      ),
    );
  }

  /// 批次十五：direct chat 房間的對方名稱（同 _buildContactTile 的官方
  /// getLocalizedDisplayname 邏輯，供確認對話框用）。
  String _friendName(Room room) {
    try {
      final display = room.getLocalizedDisplayname();
      final base = (display.isEmpty || display == 'Empty chat')
          ? (room.name.isNotEmpty ? room.name : room.id)
          : display;
      final mxid = room.directChatMatrixID;
      return (mxid != null && mxid.isNotEmpty)
          ? localDisplayName(mxid, base)
          : base;
    } on Object {
      return room.name.isNotEmpty ? room.name : room.id;
    }
  }

  /// 批次十五（好友控制）：長按好友 → bottom sheet 動作選單。
  /// 結構取自人類提供的 LINE_ref 參考截圖（好友長按選單：聊天／語音通話／
  /// 收藏／隱藏／刪除好友／封鎖）；不復製 LINE 品牌樣式，僅骨架元件。
  Future<void> _showFriendActions(Room room) async {
    if (!mounted) {
      return;
    }
    final mxid = room.directChatMatrixID;
    final isFavorite = _favoriteContacts.contains(room.id);
    final isIgnored = mxid != null &&
        mxid.isNotEmpty &&
        widget.client.ignoredUsers.contains(mxid);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: lineIconWithTestFallback(Icons.chat_bubble_outline, LineIcon.chat, size: 22, color: Theme.of(context).colorScheme.onSurface),
              title: Text(S.t('聊天')),
              onTap: () => Navigator.pop(ctx, 'chat'),
            ),
            if (mxid != null && mxid.isNotEmpty)
              ListTile(
                leading: lineIconWithTestFallback(Icons.edit_outlined, LineIcon.pencil, size: 22, color: Theme.of(context).colorScheme.onSurface),
                title: Text(S.t('設定暱稱')),
                subtitle: Text(S.t('只自己看得到，不會送出伺服器')),
                onTap: () => Navigator.pop(ctx, 'nickname'),
              ),
            ListTile(
              leading: lineIconWithTestFallback(Icons.call_outlined, LineIcon.phone, size: 22, color: Theme.of(context).colorScheme.onSurface),
              title: Text(S.t('語音通話')),
              onTap: () => Navigator.pop(ctx, 'call'),
            ),
            ListTile(
              leading: Icon(isFavorite ? AllIcons.starBorder : AllIcons.star),
              title: Text(isFavorite ? '取消收藏' : '收藏'),
              onTap: () => Navigator.pop(ctx, 'favorite'),
            ),
            ListTile(
              leading: Stack(alignment: Alignment.center, children: [Opacity(opacity: 0, child: Icon(Icons.visibility_off_outlined)), CompoundIcon(CompoundIcons.visibilityOff, size: 22, color: Theme.of(context).colorScheme.onSurface)]),
              title: Text(S.t('隱藏')),
              onTap: () => Navigator.pop(ctx, 'hide'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(AllIcons.personRemoveOutlined),
              title: Text(S.t('刪除好友')),
              onTap: () => Navigator.pop(ctx, 'delete'),
              iconColor: Theme.of(ctx).colorScheme.error,
              textColor: Theme.of(ctx).colorScheme.error,
            ),
            ListTile(
              leading: Icon(isIgnored ? AllIcons.block : AllIcons.blockOutlined),
              title: Text(isIgnored ? '解除封鎖' : '封鎖'),
              onTap: () =>
                  Navigator.pop(ctx, isIgnored ? 'unblock' : 'block'),
              iconColor: Theme.of(ctx).colorScheme.error,
              textColor: Theme.of(ctx).colorScheme.error,
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case 'chat':
        (widget.openContact ?? _defaultOpen)(context, room);
      case 'nickname':
        await _setNickname(room);
      case 'call':
        await _startVoiceCall(room);
      case 'favorite':
        unawaited(_toggleFavorite(room));
      case 'hide':
        unawaited(_hideFriend(room));
      case 'delete':
        unawaited(_deleteFriend(room));
      case 'block':
        unawaited(_blockFriend(room, block: true));
      case 'unblock':
        unawaited(_blockFriend(room, block: false));
    }
  }

  /// 第七十九批：設定本機暱稱（只自己看得到；空白＝移除回到官方顯示名）。
  Future<void> _setNickname(Room room) async {
    final mxid = room.directChatMatrixID;
    if (mxid == null || mxid.isEmpty || !mounted) return;
    final controller = TextEditingController(
      text: ringLocalNicknames.value[mxid] ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('設定暱稱')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: S.t('輸入暱稱（空白＝移除）'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('儲存')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await setLocalNickname(mxid, controller.text);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(Room room) async {
    if (!mounted) {
      return;
    }
    setState(() {
      if (_favoriteContacts.contains(room.id)) {
        _favoriteContacts.remove(room.id);
      } else {
        _favoriteContacts.add(room.id);
      }
    });
    await _persistFavorites();
  }

  /// 隱藏＝既有本機 hidden_rooms 表（rooms_screen「隱藏對話」同源，不影響
  /// 伺服器）。聯絡人列表 setState 移除；_load 亦會過濾（雙保險）。
  Future<void> _hideFriend(Room room) async {
    try {
      await AppSettings.hideRoom(room.id);
    } on Object {
      // 落盤失敗：本 session 仍隱藏（setState 移除），重啟後回復。
    }
    if (mounted) {
      setState(() {
        _friends = _friends.where((r) => r.id != room.id).toList();
        _groups = _groups.where((r) => r.id != room.id).toList();
        // 第二十三批：公開聊天室（已加入）同步過濾（隱藏在聯絡人頁通吃）。
        _publicJoined = _publicJoined.where((r) => r.id != room.id).toList();
      });
    }
  }

  /// 刪除好友＝官方 `Room.leave()`（退出 direct chat）＋官方 `Room.forget()`
  /// （同 rooms_screen._deleteRoom 模式）；不碰加密。
  Future<void> _deleteFriend(Room room) async {
    if (!mounted) {
      return;
    }
    final name = _friendName(room);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.t('要解除好友並刪除「')}$name${S.t('」嗎？')}'), // 文案草案（LINE_ref 結構參考）
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
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await room.leave();
      try {
        await room.forget();
      } on Object {
        // forget 失敗（如需先完成 leave 同步）→ 本地仍以 leave 結果為準。
      }
      if (mounted) {
        setState(() {
          _friends = _friends.where((r) => r.id != room.id).toList();
          _groups = _groups.where((r) => r.id != room.id).toList();
          _publicJoined = _publicJoined.where((r) => r.id != room.id).toList();
        });
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('刪除好友失敗：')}$e')),
        );
      }
    }
  }

  /// 封鎖／解除封鎖＝官方 `Client.ignoreUser`／`unignoreUser`（client.dart
  /// L3954／L3991，寫入官方 `m.ignored_user_list` account data，零新依賴）。
  /// 封鎖確認文案取自 LINE_ref 截圖結構（人類表示為語意參考）。
  Future<void> _blockFriend(Room room, {required bool block}) async {
    if (!mounted) {
      return;
    }
    final mxid = room.directChatMatrixID;
    if (mxid == null || mxid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('無法取得對方帳號，無法執行封鎖'))),
      );
      return;
    }
    if (block) {
      final name = _friendName(room);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${S.t('封鎖「')}$name」？'), // 文案草案（LINE_ref 結構參考）
          content: Text(S.t('您將不會再收到此帳號的訊息。\n您可以在「封鎖名單」中解除封鎖。')), // 文案草案
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t('封鎖')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    try {
      if (block) {
        await widget.client.ignoreUser(mxid);
      } else {
        await widget.client.unignoreUser(mxid);
      }
      if (mounted) {
        setState(() {}); // 觸發重建 → trailing 圖示（block icon）即時更新
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block ? '封鎖失敗：$e' : '解除封鎖失敗：$e')),
        );
      }
    }
  }

  /// 語音通話：同 chat_screen._startCall 的官方模式（manager.startCall →
  /// push CallScreen）；已有進行中的通話／來電時沿用（回到同一房間的通話）。
  Future<void> _startVoiceCall(Room room) async {
    final manager = widget.callManager;
    if (manager == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('通話功能不可用'))),
        );
      }
      return;
    }
    try {
      final active = manager.activeCall;
      if (active != null && !active.callHasEnded && active.room.id == room.id) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => CallScreen(session: active, manager: manager),
            fullscreenDialog: true,
          ),
        );
        return;
      }
      final incoming = manager.incomingCall.value;
      if (incoming != null &&
          !incoming.callHasEnded &&
          incoming.room.id == room.id) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => CallScreen(session: incoming, manager: manager),
            fullscreenDialog: true,
          ),
        );
        return;
      }
      final session = await manager.startCall(room, video: false);
      if (!mounted) {
        await session.hangup(reason: CallErrorCode.userHangup);
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: session, manager: manager),
          fullscreenDialog: true,
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('無法撥打：')}$e')),
        );
      }
    }
  }
}
