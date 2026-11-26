// 任務：Phase 1 / 1.4 — RoomsScreen／ChatScreen 骨架 widget 測試（不打網路）
// 2026-11-01（UI 重構）：送出改以 `find.byIcon(Icons.send)`；
//   空輸入案例改為「mic 為 disabled」檢查（語音訊息不在藍圖，人類決定）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:homing/ui/rooms_screen.dart';

void main() {
  group('RoomsScreen', () {
    testWidgets('載入對話列表並顯示房間名／ID，點擊開啟對話', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      Room? openedRoom;
      await tester.pumpWidget(
        MaterialApp(
          home: RoomsScreen(
            client: client,
            loadRooms: (_) async => [room],
            openRoom: (_, r) => openedRoom = r,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('!room-a:matrix.org'), findsWidgets);
      expect(openedRoom, isNull);

      await tester.tap(find.byType(ListTile).first);
      await tester.pump();

      expect(openedRoom?.id, '!room-a:matrix.org');
    });

    testWidgets('無對話時顯示說明', (tester) async {
      final client = createClient();
      await tester.pumpWidget(
        MaterialApp(
          home: RoomsScreen(
            client: client,
            loadRooms: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 第二十一批 mockup：無房間空文案照稿。
      expect(find.text('好像是時候跟朋友聊天了？'), findsOneWidget);
    });

    testWidgets('載入失敗顯示錯誤', (tester) async {
      final client = createClient();
      await tester.pumpWidget(
        MaterialApp(
          home: RoomsScreen(
            client: client,
            loadRooms: (_) => throw Exception('offline'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('無法載入對話列表'), findsOneWidget);
    });
  });

  group('ChatScreen', () {
    testWidgets('顯示既有文字訊息（舊上、新下）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              const ChatMessageView(sender: '@alice:matrix.org', body: 'hello'),
              const ChatMessageView(sender: '@bob:matrix.org', body: 'hi'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('hi'), findsOneWidget);
      expect(find.text('@alice:matrix.org'), findsOneWidget);
    });

    testWidgets('送出訊息：以輸入字串呼叫 sender 並重新載入', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      final sent = <String>[];
      var loadCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async {
              loadCount++;
              return sent.isEmpty
                  ? []
                  : [ChatMessageView(sender: client.userID ?? '', body: sent.last)];
            },
            sendMessage: (_, text) async => sent.add(text),          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ping');
      await tester.pump(); // 輸入後 build 一幀，送出鈕才會出現
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(sent, ['ping']);
      expect(loadCount, 2);
      expect(find.text('ping'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // 清空後仍只有一個輸入框
    });

    testWidgets('送出失敗顯示錯誤', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [],
            sendMessage: (_, ignored) => throw Exception('offline'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump(); // 輸入後 build 一幀，送出鈕才會出現
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('送出失敗'), findsOneWidget);
    });

    testWidgets('空輸入不顯示送出鈕；mic 為 disabled（語音訊息未提供）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [],
            sendMessage: (_, ignored) async => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 第七十批 e：無文字 → mic 可按（開語音面板）。
      expect(find.byIcon(Icons.send), findsNothing);
      final mic = find.byIcon(Icons.mic_none);
      expect(mic, findsOneWidget);
      final micButton = tester.widget<IconButton>(
        find.ancestor(of: mic, matching: find.byType(IconButton)).first,
      );
      expect(micButton.onPressed, isNotNull);
      expect(called, isFalse);
    });

    testWidgets('載入時有 eventId 就呼叫 markRead', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      final marked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              const ChatMessageView(
                sender: '@alice:matrix.org',
                body: 'hello',
                eventId: 'evt-1',
              ),
            ],
            markRead: (r, m) async => marked.add(m.eventId ?? ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(marked, ['evt-1']);
    });

    testWidgets('第二十四批：typing 指示（官方 m.typing ephemerals）顯示在輸入列上方',
        (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      // 官方通路：`Room.setEphemeral`（SDK 同步期同樣入口）寫入 typing
      // ephemerals → `Room.typingUsers` 讀回。純記憶體，不打網路。
      room.setEphemeral(
        BasicEvent(
          type: 'm.typing',
          content: {'user_ids': ['@bob:matrix.org']},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(room: room, loadMessages: (_) async => []),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('正在輸入'), findsOneWidget);
      // SDK `Room.setEphemeral` 有內建超時清空 Timer
      //（client.typingIndicatorTimeout 預設 30s）→ 測試尾聲推進假時鐘讓它
      // 觸發，避免 widget 樹銷毀後仍有 pending timer。
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('第二十四批：無人輸入時不顯示 typing 指示', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(room: room, loadMessages: (_) async => []),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('正在輸入'), findsNothing);
    });

    testWidgets('第二十四批：isEdited 訊息顯示 (已編輯) 記號', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              const ChatMessageView(
                sender: '@alice:matrix.org',
                body: '編輯後的文字',
                eventId: 'evt-2',
                isEdited: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('編輯後的文字'), findsOneWidget);
      expect(find.text('(已編輯)'), findsOneWidget);
    });
  });
}
