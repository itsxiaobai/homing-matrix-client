import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/add_friend_screen.dart';

void main() {
  group('parseMatrixUserId', () {
    test('canonical mxid', () {
      expect(parseMatrixUserId('@alice:matrix.org'), '@alice:matrix.org');
    });

    test('strip matrix.to link', () {
      expect(
        parseMatrixUserId('https://matrix.to/#/@alice:example.net'),
        '@alice:example.net',
      );
    });

    test('reject invalid', () {
      expect(parseMatrixUserId('alice'), isNull);
    });
  });

  testWidgets('invite button reports error on invalid input', (tester) async {
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

  testWidgets('QR scan injects value + confirm dialog sends invite', (tester) async {
    String? invited;
    await tester.pumpWidget(
      MaterialApp(
        home: AddFriendScreen(
          homeserver: Uri.parse('https://matrix.org'),
          scanQr: () async => '@bob:matrix.org',
          invite: (mxid) async {
            invited = mxid;
          },
        ),
      ),
    );
    await tester.tap(find.text('掃碼'));
    await tester.pumpAndSettle();
    // 2026-11-06 行為修復（人類批准）：掃出有效好友碼 → 欄位填入＋
    // 先彈確認對話框，**不再**直接送出、也不再「掃完沒有任何反應」。
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '@bob:matrix.org');
    // 「送出邀請」在畫面與對話框重名 → 限位於 AlertDialog 內點擊。
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('送出邀請')),
    );
    await tester.pumpAndSettle();
    expect(invited, '@bob:matrix.org');
    expect(find.textContaining('已送出邀請至 @bob:matrix.org'), findsOneWidget);
  });

  testWidgets('QR scan with non-friendcode content shows explicit error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddFriendScreen(
          homeserver: Uri.parse('https://matrix.org'),
          scanQr: () async => 'https://example.com/not-a-mxid',
        ),
      ),
    );
    await tester.tap(find.text('掃碼'));
    await tester.pumpAndSettle();
    // 不是 Homing 好友碼 → 明確提示（原為填入字串後靜默）。
    expect(find.textContaining('不是 Homing 好友碼'), findsOneWidget);
  });
}
