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
}
