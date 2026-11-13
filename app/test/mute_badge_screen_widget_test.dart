import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/mute_badge_screen.dart';

void main() {
  testWidgets('shows badge then mute clears it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MuteBadgeScreen(initialBadgeCount: 3)),
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('靜音'));
    await tester.pumpAndSettle();
    expect(find.text('已靜音'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });
}
