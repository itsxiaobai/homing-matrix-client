// 聯絡人 tab widget 測試（第二十一批 2026-11-08：三個膠囊 tab 好友／群組／
// 公開聊天室；空文案照人類 mockup）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/ui/contacts_screen.dart';

/// 第二十五批：Space 容器替身（SDK Room.isSpace 無自有 setter，測試覆寫）。
class _FakeSpaceRoom extends Room {
  _FakeSpaceRoom({required super.client, required super.id});
  @override
  bool get isSpace => true;
}

/// 第二十六批：partial 房替身——重啟後記憶體 states 缺 m.room.join_rules
/// （SDK importantStateEvents 預載清單不含它＝實機 47 房全落群組的根因）。
class _FakePartialRoom extends Room {
  _FakePartialRoom({required super.client, required super.id});
  @override
  JoinRules? get joinRules => null;
}

void main() {
  testWidgets('聯絡人畫面：空清單顯示稿文案＋三 tab 計數', (tester) async {
    final client = createClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 好友 tab（預設）：空文案照稿。tab 計數＝mockup『好友 (0)』格式。
    expect(find.text('加個好友吧！'), findsOneWidget);
    expect(find.text('好友 (0)'), findsOneWidget);
    expect(find.text('群組 (0)'), findsOneWidget);
    expect(find.text('公開聊天室 (0)'), findsOneWidget);
    // 群組 tab：切過去後顯示沿用文案「沒有群組」。
    await tester.tap(find.text('群組 (0)'));
    await tester.pumpAndSettle();
    expect(find.text('沒有群組'), findsOneWidget);
  });

  testWidgets('第二十三批分類：join rule public＝公開聊天室 tab；其他＝群組',
      (tester) async {
    final client = createClient();
    // 無 join rule 的房 → 群組（保守私密）；join rule public（官方
    // EventTypes.RoomJoinRules state）→ 公開聊天室 tab。
    final privateGroup = Room(id: '!g:matrix.org', client: client);
    final publicRoom = Room(id: '!p:matrix.org', client: client);
    publicRoom.setState(
      StrippedStateEvent(
        type: EventTypes.RoomJoinRules,
        senderId: '@alice:matrix.org',
        stateKey: '',
        content: {'join_rule': 'public'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [privateGroup, publicRoom],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('好友 (0)'), findsOneWidget);
    expect(find.text('群組 (1)'), findsOneWidget);
    expect(find.text('公開聊天室 (1)'), findsOneWidget);
    // 公開 tab：勤務照分類列出已加入公開房。
    await tester.tap(find.text('公開聊天室 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('!p:matrix.org'), findsOneWidget);
  });

  testWidgets('第二十五批／2026-11-20 覆核：Space 一律歸「群組」（不因 public join rule 落公開區）',
      (tester) async {
    final client = createClient();
    // public join rule 的 Space（容器）→ 群組（人類拍板，二十五批）；
    // 非 Space 的公開房 → 公開聊天室（既有語意）。
    final fakeSpace = _FakeSpaceRoom(client: client, id: '!s:matrix.org')
      ..setState(StrippedStateEvent(
        type: EventTypes.RoomJoinRules,
        senderId: '@alice:matrix.org',
        stateKey: '',
        content: {'join_rule': 'public'},
      ));
    final publicRoom = Room(id: '!p:matrix.org', client: client)
      ..setState(StrippedStateEvent(
        type: EventTypes.RoomJoinRules,
        senderId: '@alice:matrix.org',
        stateKey: '',
        content: {'join_rule': 'public'},
      ));
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [fakeSpace, publicRoom],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 2026-11-20（人類指示）：Space 回「群組」，第四 tab 已撤銷。
    expect(find.text('好友 (0)'), findsOneWidget);
    expect(find.text('群組 (1)'), findsOneWidget);
    expect(find.text('公開聊天室 (1)'), findsOneWidget);
    await tester.tap(find.text('群組 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('!s:matrix.org'), findsOneWidget);
  });

  testWidgets('第二十五批：FAB「＋」→ 三選項 sheet（加入個人／建立聊天室／加入公開）',
      (tester) async {
    final client = createClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    // 共用（首頁「＋」同源）room_actions 三項。
    expect(find.text('加入好友（Matrix ID／QR）'), findsOneWidget);
    expect(find.text('建立聊天室'), findsOneWidget);
    expect(find.text('加入公開聊天室'), findsOneWidget);

    // 點「建立聊天室」→ 名稱對話框（官方 createRoom 前置；不打網路）。
    await tester.tap(find.text('建立聊天室'));
    await tester.pumpAndSettle();
    expect(find.text('建立'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('建立'), findsNothing);
  });

  testWidgets('direct chat 歸「好友」、普通房歸「群組」，點擊開啟對話', (tester) async {
    final client = createClient();
    // 注入官方 m.direct 帳號資料：SDK `Room.directChatMatrixID` 依此判斷。
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@alice:matrix.org': <String>['!direct:matrix.org'],
      },
    );
    final directRoom = Room(id: '!direct:matrix.org', client: client);
    final groupRoom = Room(id: '!group:matrix.org', client: client);
    // 2026-11-03（title 重構後）：SDK `getLocalizedDisplayname` 對缺
    // 成員 state 的 hero 會走官方 `unsafeGetUserFromMemoryOrFallback` →
    // fire-and-forget `requestUser`（測試環境無 DB → LateError）。注入
    // 真實的 m.room.member state（等同真機 sync 後的狀態）。
    directRoom.setState(StrippedStateEvent(
      type: EventTypes.RoomMember,
      senderId: '@alice:matrix.org',
      stateKey: '@alice:matrix.org',
      content: {'membership': 'join', 'displayname': 'Alice'},
    ));

    Room? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [groupRoom, directRoom],
          openContact: (_, r) => opened = r,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第二十一批：計數進 tab 標籤。
    expect(find.text('好友 (1)'), findsOneWidget);
    expect(find.text('群組 (1)'), findsOneWidget);

    // 好友 tab（預設開啟）內的列表項（direct 在前，收藏置頂排序不變）。
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    expect(opened?.id, '!direct:matrix.org');
  });

  testWidgets('第二十六批：partial 房記憶體缺 join_rules → resolveJoinRules 兜底',
      (tester) async {
    final client = createClient();
    // 重啟後 partial 房（實機根因）：記憶體 states 缺 m.room.join_rules。
    final partialPublic = _FakePartialRoom(client: client, id: '!pp:matrix.org');
    // 記憶體已有 join_rules 的房（sync 更新過的）直接用記憶體值、不問兜底。
    final warmRoom = Room(id: '!warm:matrix.org', client: client)
      ..setState(StrippedStateEvent(
        type: EventTypes.RoomJoinRules,
        senderId: '@alice:matrix.org',
        stateKey: '',
        content: {'join_rule': 'invite'},
      ));
    final resolved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [partialPublic, warmRoom],
          resolveJoinRules: (room) {
            resolved.add(room.id);
            return room.id == '!pp:matrix.org' ? JoinRules.public : null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('群組 (1)'), findsOneWidget);
    expect(find.text('公開聊天室 (1)'), findsOneWidget);
    // 兜底只問「記憶體缺值」的房（warmRoom 記憶體即中）。
    expect(resolved, ['!pp:matrix.org']);
    await tester.tap(find.text('公開聊天室 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('!pp:matrix.org'), findsOneWidget);
  });
}
