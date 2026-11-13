import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/device_management_screen.dart';

void main() {
  testWidgets('show device list and remove one', (tester) async {
    final devices = [
      const DeviceView(id: 'd1', displayName: 'Phone A', lastSeen: 'now'),
      const DeviceView(id: 'd2', displayName: 'Phone B', lastSeen: 'now'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceManagementScreen(
          loadDevices: () async => devices,
          onDeleteDevice: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phone A'), findsWidgets);

    await tester.tap(find.text('遠端登出').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('登出裝置'));
    await tester.pumpAndSettle();
    expect(find.text('Phone A'), findsNothing); // after successful deletion
  });
}
