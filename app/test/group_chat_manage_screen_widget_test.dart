import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/group_chat_manage_screen.dart';

void main() {
  testWidgets('invite triggers and lists members', (tester) async {
    final invites = <String>[];
    final members = <String>['@existing:matrix.org'];
    await tester.pumpWidget(
      MaterialApp(
        home: GroupMemberManageScreen(
          inviteMember: (id) async => invites.add(id),
          kickMember: (_) async {},
          loadMembers: () async => members,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@existing:matrix.org'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '@new:matrix.org');
    await tester.tap(find.text('邀請'));
    await tester.pumpAndSettle();

    expect(invites, ['@new:matrix.org']);
  });
}
