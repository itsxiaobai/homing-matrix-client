import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/report_user_screen.dart';

void main() {
  testWidgets('submit report with target/reason', (tester) async {
    final reported = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ReportUserScreen(
          report: (target, reason) async => reported.add([target, reason]),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '@bad:matrix.org');
    await tester.enterText(find.byType(TextField).last, 'spam');
    await tester.tap(find.text('送出檢舉'));
    await tester.pumpAndSettle();
    expect(reported, hasLength(1));
    expect(reported.first, ['@bad:matrix.org', 'spam']);
    expect(find.textContaining('檢舉已送出'), findsOneWidget);
  });

  testWidgets('missing fields shows hint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const ReportUserScreen(),
      ),
    );
    await tester.tap(find.text('送出檢舉'));
    await tester.pumpAndSettle();
    expect(find.textContaining('target 與 reason 必須填寫'), findsOneWidget);
  });
}
