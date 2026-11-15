import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/group_encrypted_room_screen.dart';

void main() {
  testWidgets('group encrypted room screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GroupEncryptedRoomScreen(roomId: '!foo:server.org')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Room: !foo:server.org（SDK official E2EE, no agent crypto）'), findsOneWidget);
  });
}
