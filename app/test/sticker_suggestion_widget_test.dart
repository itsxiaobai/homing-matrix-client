// 貼圖關鍵字聯想（backlog #8）— 聊天室建議列 widget 測試。
// 版位參考 LINE：建議貼圖列出現在**輸入框上方**；點擊即送出該貼圖。
// 貼圖庫以注入的 fake 提供（不打網路、不碰本機 DB）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/sticker_suggestions.dart';
import 'package:homing/ui/chat_screen.dart';

void main() {
  testWidgets('輸入關鍵字 → 輸入框上方出現建議貼圖；清空後消失', (tester) async {
    final client = createClient();
    final room = Room(id: '!room-a:matrix.org', client: client);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          room: room,
          loadMessages: (_) async => [],
          stickerLibraryLoader: () async => const [
            StickerLibraryEntry(id: 1, path: '/tmp/none_cat_happy.png', name: 'cat_happy.png'),
            StickerLibraryEntry(id: 2, path: '/tmp/none_dog.png', name: 'dog.png'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 尚未輸入 → 無建議列。
    expect(find.byTooltip('cat_happy'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ha');
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('cat_happy'), findsOneWidget);
    // 不相關的貼圖不出現。
    expect(find.byTooltip('dog'), findsNothing);

    // 清空輸入 → 建議列消失。
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('cat_happy'), findsNothing);
  });
}
