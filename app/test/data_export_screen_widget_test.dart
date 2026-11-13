import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/data_export_screen.dart';

void main() {
  testWidgets('export calls exporter callback', (tester) async {
    final formats = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DataExportScreen(exporter: (f) async => formats.add(f)),
      ),
    );
    await tester.tap(find.text('匯出 JSON'));
    await tester.pumpAndSettle();
    expect(formats, ['JSON']);
    expect(find.text('匯出成功（JSON）'), findsWidgets);
  });
}
