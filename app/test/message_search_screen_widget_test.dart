import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/message_search_screen.dart';

void main() {
  testWidgets('message search shows results', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageSearchScreen(
          search: (q) async => ['hello $q', 'world'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'foo');
    await tester.pumpAndSettle();
    expect(find.text('hello foo'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);
  });

  testWidgets('empty query clears results', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageSearchScreen(
          search: (q) async => ['whatever'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'x');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('whatever'), findsNothing);
  });

  testWidgets('第四十八批：過濾 chip 列顯示時間範圍與訊息類型', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageSearchScreen(
          search: (q) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 時間範圍 chip
    expect(find.text('全部時間'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(find.text('最近 30 天'), findsOneWidget);

    // 訊息類型 chip
    expect(find.text('全部類型'), findsOneWidget);
    expect(find.text('文字'), findsOneWidget);
    expect(find.text('貼圖'), findsOneWidget);
  });

  testWidgets('第四十八批：點過濾 chip → 選取狀態切換', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageSearchScreen(
          search: (q) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todayChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, '今天'));
    expect(todayChip.selected, isFalse);

    await tester.tap(find.widgetWithText(FilterChip, '今天'));
    await tester.pumpAndSettle();

    final after = tester.widget<FilterChip>(find.widgetWithText(FilterChip, '今天'));
    expect(after.selected, isTrue);
  });
}
