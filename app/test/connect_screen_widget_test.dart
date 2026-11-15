// 任務：Phase 0 / 0.10 — ConnectScreen 骨架 widget 測試（注入假檢查器，不打網路）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/connect_screen.dart';

void main() {
  Uri? handled;

  Future<String?> fakeChecker(Uri uri) async => null; // 永遠成功

  setUp(() => handled = null);

  testWidgets('預設 homeserver 為 matrix.org', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ConnectScreen(checkServer: fakeChecker)),
    );

    expect(find.text('matrix.org'), findsWidgets);
  });

  testWidgets('提供 Homing 自架伺服器選項（尚未提供、不可選）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ConnectScreen(checkServer: fakeChecker)),
    );

    await tester.tap(find.text('matrix.org（預設）'));
    await tester.pumpAndSettle();

    expect(find.text('Homing 自架伺服器（尚未提供）'), findsWidgets);
  });

  testWidgets('空輸入顯示錯誤訊息，且不呼叫檢查器', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectScreen(
          checkServer: (_) async {
            called = true;
            return 'server error';
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('檢查連線'));
    await tester.pump();

    expect(find.text('請輸入有效的 homeserver 位址（例如 matrix.org）'),
        findsOneWidget);
    expect(called, isFalse);
  });

  testWidgets('無效位址顯示錯誤訊息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectScreen(
          checkServer: (_) => throw StateError('不應被呼叫'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'http://example.org');
    await tester.tap(find.text('檢查連線'));
    await tester.pump();

    expect(find.text('請輸入有效的 homeserver 位址（例如 matrix.org）'),
        findsOneWidget);
  });

  testWidgets('有效位址成功後顯示成功訊息並回呼 resolved URL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectScreen(
          checkServer: fakeChecker,
          onHandled: (uri) => handled = uri,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'matrix.local');
    await tester.tap(find.text('檢查連線'));
    await tester.pumpAndSettle();

    expect(find.textContaining('連線成功'), findsOneWidget);
    expect(handled?.toString(), 'https://matrix.local');
  });

  testWidgets('檢查器回傳錯誤時顯示該錯誤', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectScreen(
          checkServer: (uri) => Future.value('伺服器不相容（M_UNKNOWN）'),
          onHandled: (uri) => handled = uri,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'bad.example.org');
    await tester.tap(find.text('檢查連線'));
    await tester.pumpAndSettle();

    expect(find.text('伺服器不相容（M_UNKNOWN）'), findsOneWidget);
    expect(handled, isNull);
  });
}
