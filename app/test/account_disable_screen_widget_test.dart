import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/account_disable_screen.dart';

void main() {
  testWidgets('account disable invokes callback', (tester) async {
    final actions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDisableScreen(
          disable: ({bool erase = true}) async => actions.add(erase),
        ),
      ),
    );
    await tester.tap(find.text('確認停用'));
    await tester.pumpAndSettle();
    expect(actions, [true]);
    expect(find.textContaining('已停用帳號'), findsOneWidget);
  });
}
