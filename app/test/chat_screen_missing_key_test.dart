// 修法 #2：chat_screen「向其他裝置請求缺失金鑰」入口 widget 測試。
// 動作以 fake 注入（不打網路、不碰真實金鑰）；驗證入口顯示條件、
// 回報文案與錯誤透明化。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/ui/chat_screen.dart';

ChatScreen _screen(Room room, {MissingKeyRepairAction? action}) => ChatScreen(
      room: room,
      loadMessages: (_) async => const [],
      requestMissingKeys: action,
    );

Room _encryptedRoom() {
  final client = createClient();
  final room = Room(id: '!room-a:matrix.org', client: client);
  room.setState(
    StrippedStateEvent(
      type: EventTypes.Encryption,
      content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
      senderId: client.userID ?? '@alice:matrix.org',
      stateKey: '',
    ),
  );
  return room;
}

Future<void> _openMenuAndTapItem(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('向其他裝置請求缺失金鑰'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('加密房間顯示入口；點擊後 SnackBar 回報請求數', (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: _screen(
          _encryptedRoom(),
          action: (room) async {
            requested.add(room.id);
            return 3;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openMenuAndTapItem(tester);

    expect(find.textContaining('已向其他裝置請求 3 個缺失金鑰'), findsOneWidget);
    expect(requested.single, '!room-a:matrix.org');
  });

  testWidgets('沒有缺失金鑰時顯示明確提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _screen(_encryptedRoom(), action: (_) async => 0)),
    );
    await tester.pumpAndSettle();

    await _openMenuAndTapItem(tester);

    expect(find.textContaining('沒有偵測到需要請求的金鑰'), findsOneWidget);
  });

  testWidgets('失敗顯示真實錯誤（不遮蔽）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _screen(
          _encryptedRoom(),
          action: (_) async => throw Exception('boom-real-message'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openMenuAndTapItem(tester);

    expect(find.textContaining('請求失敗'), findsOneWidget);
    expect(find.textContaining('boom-real-message'), findsOneWidget);
  });
}
