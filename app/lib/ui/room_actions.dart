// 第二十五批（人類四項整合指示）：首頁「＋」與聯絡人 FAB 共用的動作流程。
// —— 自 rooms_screen 原樣抽出（建立聊天室／加入公開聊天室／Space 底下聊天室
// 清單），建立入口一次、兩處畫面共用；零新依賴、零協定邏輯。
// 全部 SDK 官方 API：`Client.createRoom`／`queryPublicRooms`／`joinRoom`／
// `getSpaceHierarchy`。本檔不觸碰加密／金鑰。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../voip/call_manager.dart';
import 'chat_screen.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化

/// 三選項 sheet 的回傳代碼（'create'／'join'／'friend'；取消＝null）。
///
/// 人類拍板（2026-11-08）：聯絡人 FAB 與首頁「＋」同一組三項——
/// 「加入個人」＝加入好友（Matrix ID／QR）、「群組」＝建立聊天室（Matrix
/// 私群組無「加入既有群組」通路，只能被邀請）、「公開聊天室」＝加入既有公開房。
Future<String?> showAddChatSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(AllIcons.chatBubbleOutline),
            title: Text(S.t('建立聊天室')), // 文案草案，待人類設計定稿
            onTap: () => Navigator.of(ctx).pop('create'),
          ),
          ListTile(
            leading: Icon(AllIcons.public),
            title: Text(S.t('加入公開聊天室')), // 文案草案
            onTap: () => Navigator.of(ctx).pop('join'),
          ),
          ListTile(
            leading: Icon(AllIcons.qrCodeScanner),
            title: Text(S.t('加入好友（Matrix ID／QR）')), // 文案草案
            onTap: () => Navigator.of(ctx).pop('friend'),
          ),
        ],
      ),
    ),
  );
}

/// 統一入口：顯示三選項 sheet 並執行對應流程。
/// [openAddFriend]＝呼叫端既有的加入好友畫面導向（兩處畫面各有注入點）；
/// [onRoomsChanged]＝流程動到房間後的清單重載（各畫面 _load）；
/// [openRoom]＝測試注入點（預設開 ChatScreen）；[callManager] 透傳。
Future<void> runAddChatSheet(
  BuildContext context, {
  required Client client,
  required void Function() openAddFriend,
  CallManager? callManager,
  Future<void> Function()? onRoomsChanged,
  void Function(BuildContext context, Room room)? openRoom,
}) async {
  final action = await showAddChatSheet(context);
  if (!context.mounted) {
    return;
  }
  switch (action) {
    case 'create':
      await showCreateRoomFlow(
        context,
        client,
        callManager: callManager,
        onRoomsChanged: onRoomsChanged,
        openRoom: openRoom,
      );
    case 'join':
      await showJoinPublicRoomFlow(
        context,
        client,
        callManager: callManager,
        onRoomsChanged: onRoomsChanged,
        openRoom: openRoom,
      );
    case 'friend':
      openAddFriend();
  }
}

/// 建立聊天室（官方 `Client.createRoom(name:)`；成功 → 開啟＋重載清單）。
/// 自 rooms_screen `_createRoom` 原樣抽出（rooms_screen L1338）。
Future<void> showCreateRoomFlow(
  BuildContext context,
  Client client, {
  CallManager? callManager,
  Future<void> Function()? onRoomsChanged,
  void Function(BuildContext context, Room room)? openRoom,
}) async {
  final nameCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.t('建立聊天室')), // 草案文案
      content: TextField(
        controller: nameCtrl,
        decoration: const InputDecoration(labelText: '名稱'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.t('取消'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(S.t('建立'))),
      ],
    ),
  );
  if (ok != true) {
    nameCtrl.dispose();
    return;
  }
  final name = nameCtrl.text.trim();
  nameCtrl.dispose();
  if (name.isEmpty || !context.mounted) return;
  try {
    final roomId = await client.createRoom(name: name);
    if (!context.mounted) {
      return;
    }
    final room = client.getRoomById(roomId);
    if (room != null) {
      if (openRoom != null) {
        openRoom(context, room);
      } else {
        _defaultOpenChat(context, room, callManager);
      }
    }
    await onRoomsChanged?.call();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('建立失敗：')}$e')), // 文案草案
      );
    }
  }
}

/// 預設開啟：ChatScreen（與 rooms_screen／contacts_screen 同鏈路）。
void _defaultOpenChat(
  BuildContext context,
  Room room,
  CallManager? callManager,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatScreen(room: room, callManager: callManager),
    ),
  );
}

/// 加入公開聊天室瀏覽器（官方 `Client.queryPublicRooms`／`Client.joinRoom`；
/// SDK 內建 API）。搜尋＝輸入中本地過濾（官方資料 ordinal 不動）；送出 →
/// 官方 generic_search_term 伺服器端重查。limit 100 一次性（不實作無限
/// 滾動）。點未加入房 → joinRoom 後開啟；已加入 → 直接開啟。失敗 → SnackBar
/// （不靜默）。自 rooms_screen `_joinPublicRoom+_openPublicRoom` 原樣抽出。
Future<void> showJoinPublicRoomFlow(
  BuildContext context,
  Client client, {
  CallManager? callManager,
  Future<void> Function()? onRoomsChanged,
  void Function(BuildContext context, Room room)? openRoom,
}) async {
  List<PublishedRoomsChunk>? results;
  String? errorMessage;
  try {
    final resp = await client.queryPublicRooms();
    results = resp.chunk;
  } on Object catch (e) {
    errorMessage = '無法取得公開聊天室：$e'; // 文案草案
  }
  if (!context.mounted) {
    return;
  }
  // 可變狀態放 builder 外（重建不會掉焦點；queryCtrl 於面板關閉後釋放）。
  final queryCtrl = TextEditingController();
  var query = '';
  var list = results ?? const <PublishedRoomsChunk>[];
  var message = errorMessage;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(S.t('加入公開聊天室'), // 文案草案
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: queryCtrl,
                  decoration: InputDecoration(
                    hintText: S.t('搜尋聊天室'), // 文案草案
                    prefixIcon: Icon(AllIcons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setSheetState(() {
                    query = v.trim();
                    list = (results ?? const <PublishedRoomsChunk>[])
                        .where((c) =>
                            query.isEmpty ||
                            (c.name ?? '').toLowerCase().contains(
                                  query.toLowerCase(),
                                ) ||
                            c.roomId
                                .toLowerCase()
                                .contains(query.toLowerCase()))
                        .toList();
                  }),
                  onSubmitted: (v) async {
                    // 官方伺服器端搜尋（generic_search_term；草案流程）。
                    setSheetState(() => list = const []);
                    try {
                      final r = await client.queryPublicRooms(
                        filter: PublicRoomQueryFilter(
                          genericSearchTerm: v.trim(),
                        ),
                      );
                      results = r.chunk;
                      if (sheetCtx.mounted) {
                        setSheetState(() {
                          query = v.trim();
                          list = results ?? const [];
                          message = null;
                        });
                      }
                    } on Object catch (e) {
                      if (sheetCtx.mounted) {
                        setSheetState(
                          () => message = '搜尋失敗：$e', // 文案草案
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 4),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      message ?? '沒有公開聊天室', // 文案草案
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  LimitedBox(
                    maxHeight: 360,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final chunk = list[i];
                        final joined =
                            client.getRoomById(chunk.roomId) != null;
                        final name = (chunk.name != null &&
                                chunk.name!.isNotEmpty)
                            ? chunk.name!
                            : chunk.roomId;
                        return ListTile(
                          leading: Icon(AllIcons.public),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // 成員數（官方 numJoinedMembers）；0 不顯示（草案）。
                          subtitle: chunk.numJoinedMembers > 0
                              ? Text('${chunk.numJoinedMembers}${S.t(' 位成員')}') // 文案草案
                              : null,
                          trailing: joined
                              ? Text(S.t('已加入'), // 文案草案
                                  style:
                                      Theme.of(ctx).textTheme.bodySmall,
                                )
                              : null,
                          onTap: () => unawaited(
                            openPublicRoom(
                              context,
                              client,
                              chunk,
                              callManager: callManager,
                              onRoomsChanged: onRoomsChanged,
                              openRoom: openRoom,
                              close: () {
                                if (Navigator.of(sheetCtx).canPop()) {
                                  Navigator.of(sheetCtx).pop();
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  queryCtrl.dispose();
}

/// 點公開房——未加入 → 官方 joinRoom 後開啟；已加入 → 直接開啟。
/// [close]＝收起瀏覽面板（成功開啟前）。失敗 → SnackBar（不靜默）。
Future<void> openPublicRoom(
  BuildContext context,
  Client client,
  PublishedRoomsChunk chunk, {
  CallManager? callManager,
  Future<void> Function()? onRoomsChanged,
  void Function(BuildContext context, Room room)? openRoom,
  required void Function() close,
}) async {
  try {
    var room = client.getRoomById(chunk.roomId);
    if (room == null) {
      final joinedId = await client.joinRoom(chunk.roomId);
      room = client.getRoomById(joinedId);
      if (room != null) {
        await onRoomsChanged?.call();
      }
    }
    if (room != null) {
      close();
      if (context.mounted) {
        if (openRoom != null) {
          openRoom(context, room);
        } else {
          _defaultOpenChat(context, room, callManager);
        }
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('已加入但尚未同步（稍後再試）'))), // 文案草案
      );
    }
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('無法加入公開聊天室：')}$e')), // 文案草案
      );
    }
  }
}

/// 點 Space → 顯示該 Space 的所有可用聊天室。資料來源：SDK 官方 hierarchy API
///（`Client.getSpaceHierarchy`，v1 端點），含「尚未加入但可加入」的聊天室；
/// 點未加入者 → 直接加入再開啟（草案流程）。自 rooms_screen `_showSpaceRooms`
/// 原樣抽出（第二十五批起由聯絡人「群組」區塊的 Space tile 呼叫）。
Future<void> showSpaceRoomsSheet(
  BuildContext context,
  Client client,
  Room space, {
  CallManager? callManager,
  Future<void> Function()? onRoomsChanged,
  void Function(BuildContext context, Room room)? openRoom,
}) async {
  final result = await showModalBottomSheet<Object?>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                'Space 底下的聊天室（${_roomDisplayTitle(space)}）', // 文案草案
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
          ),
          Flexible(
            child: FutureBuilder<GetSpaceHierarchyResponse>(
              future: client
                  .getSpaceHierarchy(space.id, maxDepth: 1, limit: 100)
                  .catchError((Object _) => GetSpaceHierarchyResponse(rooms: [])),
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  );
                }
                final rooms = snap.data?.rooms ?? const <SpaceRoomsChunk$2>[];
                if (rooms.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(S.t('此 Space 沒有可顯示的聊天室')), // 文案草案
                  );
                }
                return ListView(
                  children: [
                    for (final r in rooms.where((r) => r.roomType != 'm.space'))
                      ListTile(
                        leading: Icon(AllIcons.chatBubbleOutline),
                        title: Text(r.name ?? r.canonicalAlias ?? r.roomId),
                        subtitle: Text(
                          '${r.numJoinedMembers} 人'
                          '${r.topic != null && r.topic!.isNotEmpty ? '・${r.topic}' : ''}', // 文案草案
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(ctx, r.roomId),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  // sheet 回傳所選聊天室（pop(ctx, roomId)）。未加入者 → 官方
  // `Client.joinRoom` 加入後開啟（草案流程；失敗以 SnackBar 告知）。
  final selected = result is String ? result : null;
  if (selected == null || !context.mounted) {
    return;
  }
  try {
    final joinedId = await client.joinRoom(selected);
    await onRoomsChanged?.call();
    if (!context.mounted) return;
    final room = client.getRoomById(joinedId);
    if (room != null) {
      if (openRoom != null) {
        openRoom(context, room);
      } else {
        _defaultOpenChat(context, room, callManager);
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('加入失敗：')}$e')), // 文案草案
      );
    }
  }
}

/// 房間顯示名稱（官方 `Room.getLocalizedDisplayname()`；'Empty chat'／失敗 →
/// room.name → room.id 保底，永不擲錯）。
String _roomDisplayTitle(Room room) {
  try {
    final display = room.getLocalizedDisplayname();
    return (display.isEmpty || display == 'Empty chat')
        ? (room.name.isNotEmpty ? room.name : room.id)
        : display;
  } on Object {
    return room.name.isNotEmpty ? room.name : room.id;
  }
}
