import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/ui/add_friend_screen.dart';
import 'package:homing/ui/block_user_screen.dart';
import 'package:homing/ui/contacts_screen.dart';
import 'package:homing/ui/key_backup_recovery_screen.dart';
import 'package:homing/ui/report_user_screen.dart';

void main() {
  testWidgets('contacts screen renders', (tester) async {
    final client = createClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          client: client,
          loadContacts: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 第二十一批：好友 tab（預設）空文案照稿；群組文案挪進 tab。
    await tester.tap(find.text('群組 (0)'));
    await tester.pumpAndSettle();
    expect(find.text('沒有群組'), findsOneWidget);
  });

  testWidgets('add friend validation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddFriendScreen(
          homeserver: Uri.parse('https://matrix.org'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('送出邀請'));
    await tester.pumpAndSettle();
    expect(find.textContaining('請輸入有效的 Matrix ID'), findsOneWidget);
  });

  testWidgets('block user empties list smoke', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlockUserScreen(
          block: (_) async {},
          listBlocked: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('封鎖使用者'), findsOneWidget);
  });

  testWidgets('report user submission', (tester) async {
    final reports = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ReportUserScreen(
          report: (target, reason) async => reports.add([target, reason]),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '@bad:matrix.org');
    await tester.enterText(find.byType(TextField).last, 'scam');
    await tester.tap(find.text('送出檢舉'));
    await tester.pumpAndSettle();
    expect(reports, hasLength(1));
  });

  testWidgets('key backup submit', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: KeyBackupRecoveryScreen(onRecover: (k) async => values.add(k)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'key');
    await tester.tap(find.text('恢復金鑰'));
    await tester.pumpAndSettle();
    expect(values, ['key']);
  });

}
