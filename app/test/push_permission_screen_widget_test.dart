import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/push_permission_screen.dart';

void main() {
  testWidgets('push permission denied reports failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PushPermissionScreen(requestPermission: () async => false),
      ),
    );
    await tester.tap(find.text('請求通知權限'));
    await tester.pumpAndSettle();
    expect(find.textContaining('權限被拒絕'), findsOneWidget);
  });

  testWidgets('push permission granted reports success', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PushPermissionScreen(requestPermission: () async => true),
      ),
    );
    await tester.tap(find.text('請求通知權限'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已取得權限'), findsOneWidget);
  });
}
