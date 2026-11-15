import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/multi_device_login_screen.dart';

void main() {
  testWidgets('recovery callback fires', (tester) async {
    String? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: MultiDeviceLoginScreen(
          recoveryKey: (v) async => seen = v,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'RK');
    await tester.tap(find.text('方式 A：恢復'));
    await tester.pumpAndSettle();
    expect(seen, 'RK');
  });

  testWidgets('nearby callback fires', (tester) async {
    var triggered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MultiDeviceLoginScreen(
          nearbyVerification: () async => triggered = true,
        ),
      ),
    );
    await tester.tap(find.text('方式 B：QR code'));
    await tester.pumpAndSettle();
    expect(triggered, isTrue);
  });
}
