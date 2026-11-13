import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/block_user_screen.dart';

void main() {
  testWidgets('block button calls block action and refreshes', (tester) async {
    final blocked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BlockUserScreen(
          block: (id) async => blocked.add(id),
          listBlocked: () async => blocked,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@x:matrix.org');
    await tester.tap(find.text('封鎖'));
    await tester.pumpAndSettle();

    expect(blocked, ['@x:matrix.org']);
    expect(find.text('@x:matrix.org'), findsWidgets);
  });
}
