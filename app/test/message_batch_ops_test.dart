// 第四十八批：訊息批次操作（多選）——widget 測試。
//
// 驗收重點：
// - 長按訊息 → 選單含「多選」。
// - 點「多選」→ 進入多選模式（頂列換成批次列，顯示已選數）。
// - 多選模式下點按訊息 → 切換選取（已選數增減）。
// - 點「取消多選」→ 離開多選模式。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:matrix/matrix.dart';

void main() {
  testWidgets('長按訊息 → 「多選」→ 批次列顯示已選數 → 可切換選取',
      (tester) async {
    final client = createClient();
    final room = Room(id: '!room-a:matrix.org', client: client);
    final now = DateTime(2026, 11, 16, 12, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          room: room,
          loadMessages: (_) async => [
            ChatMessageView(
              sender: '@someone:matrix.org',
              body: '第一則',
              sentAt: now,
              eventId: '\$m1',
            ),
            ChatMessageView(
              sender: '@someone:matrix.org',
              body: '第二則',
              sentAt: now,
              eventId: '\$m2',
            ),
          ],
          sendMessage: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 長按第一則訊息 → 動作選單。
    await tester.longPress(find.text('第一則'));
    await tester.pumpAndSettle();
    expect(find.text('多選'), findsOneWidget);

    // 點「多選」→ 進入多選模式（頂列＝批次列；被長按的那則**預先選取**）。
    await tester.tap(find.text('多選'));
    await tester.pumpAndSettle();
    expect(find.text('已選 1 則'), findsOneWidget);

    // 多選模式下點按訊息 → 切換選取（第二則加入 → 已選 2 則）。
    await tester.tap(find.text('第二則'));
    await tester.pumpAndSettle();
    expect(find.text('已選 2 則'), findsOneWidget);

    // 再點第二則 → 取消選取（已選 1 則）。
    await tester.tap(find.text('第二則'));
    await tester.pumpAndSettle();
    expect(find.text('已選 1 則'), findsOneWidget);

    // 再點第一則（原本已選）→ 取消選取 → 已選 0 則。
    await tester.tap(find.text('第一則'));
    await tester.pumpAndSettle();
    expect(find.text('已選 0 則'), findsOneWidget);

    // 再點第二則 → 已選 1 則。
    await tester.tap(find.text('第二則'));
    await tester.pumpAndSettle();
    expect(find.text('已選 1 則'), findsOneWidget);

    // 取消多選 → 離開批次列。
    // 2026-11-20：取消多選改 CompoundIcon(close)，用 tooltip 定位。
    await tester.tap(find.byTooltip('取消多選'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已選'), findsNothing);
  });
}
