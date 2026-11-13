import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/media_attach_screen.dart';

void main() {
  testWidgets('attach callback receives path and type', (tester) async {
    final captured = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaAttachScreen(
          attach: (path, isVideo) async => captured.add([path, isVideo]),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '/tmp/foo.png');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('附加'));
    await tester.pumpAndSettle();

    expect(captured.length, 1);
    expect(captured.first[0], '/tmp/foo.png');
    expect(captured.first[1], isTrue);
    expect(find.textContaining('已送'), findsOneWidget);
  });
}
