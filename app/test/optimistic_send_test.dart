// 第五十五批測試（2026-11-16；不打網路）：**送出訊息立即顯示、背景繼續送**。
//
// 背景（人類回報 2026-11-16）：「傳送訊息是不是應該先顯示在上面，背景繼續傳送？
// 不然使用者會覺得當機了」——舊實作是**等伺服器回應成功後**才把訊息放進列表
// （該處原註解自稱「樂觀更新」，實際相反）→ 等待期間畫面毫無變化＝像當機。
//
// 新實作：按下送出**立刻**插入 pending 訊息（半透明＋「傳送中」記號），實際
// 送出在背景進行；成功 → 由 `_load()` 以伺服器事件取代；失敗 → 移除 pending 並把
// 文字還回輸入框。
//
// 覆蓋：①送出中立即可見且標示「傳送中」②送出失敗則 pending 消失、文字還回輸入框。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:matrix/matrix.dart';

void main() {
  group('第五十五批：先顯示、背景繼續送', () {
    testWidgets('按下送出 → 訊息立即顯示並標示「傳送中」（不等伺服器）',
        (tester) async {
      final client = createClient();
      final room = Room(id: '!pending:matrix.org', client: client);
      final gate = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => const [],
            // 送出**卡住**＝模擬伺服器慢回應。
            sendMessage: (r, t) => gate.future,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '背景繼續送');
      await tester.pump(); // 輸入後送出鈕才會出現（hasText 判斷）。
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 伺服器還沒回應 → 訊息**已經**出現在畫面上，且標示「傳送中」。
      expect(find.text('背景繼續送'), findsOneWidget);
      expect(find.text('傳送中'), findsOneWidget);

      // 伺服器回應成功 → pending 消失（`_load()` 以伺服器事件取代）。
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('傳送中'), findsNothing);
    });

    testWidgets('送出失敗 → pending 消失且文字還回輸入框', (tester) async {
      final client = createClient();
      final room = Room(id: '!pending2:matrix.org', client: client);
      final gate = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => const [],
            sendMessage: (r, t) => gate.future,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '會失敗的訊息');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      expect(find.text('會失敗的訊息'), findsOneWidget);
      expect(find.text('傳送中'), findsOneWidget);

      gate.completeError(Exception('boom'));
      await tester.pumpAndSettle();

      // pending 移除、輸入框拿回文字（既有失敗行為）。
      expect(find.text('傳送中'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller?.text, '會失敗的訊息');
    });
  });
}
