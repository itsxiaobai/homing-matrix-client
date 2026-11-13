import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/group_chat_create_screen.dart';

void main() {
  testWidgets('group create success invokes create callback', (tester) async {
    final created = <List<dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: GroupChatCreateScreen(
          create: (name, invited) async => created.add([name, invited]),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'test-group');
    await tester.enterText(find.byType(TextField).last, '@alice:matrix.org');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('建立群组'));
    await tester.pumpAndSettle();

    expect(created.length, 1);
    expect(created.first[0], 'test-group');
  });

  testWidgets('empty group name reports error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const GroupChatCreateScreen()),
    );
    await tester.tap(find.text('建立群组'));
    await tester.pumpAndSettle();
    expect(find.text('群组名称必填'), findsOneWidget);
  });
}
