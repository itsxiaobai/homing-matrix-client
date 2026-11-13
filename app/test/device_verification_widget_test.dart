// 第二十五批（人類拍板「3. 是」）：無作用 skeleton 裝置驗證畫面
//（device_verification_screen.dart）與新裝置建立（new_device_setup_screen.dart）
// /新裝置驗證（new_device_verification_flow_screen.dart）死檔刪除——官方沒有
// 這個東西；對應測試案例移除。官方 SAS 裝置驗證現為 settings_screen「進階」
// 區入口（SDK `DeviceKeys.startVerification` → device_verification_dialog）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/ui/device_listing_screen.dart';
import 'package:homing/ui/key_backup_recovery_screen.dart';

void main() {
  testWidgets('device listing shows empty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceListingScreen(
          loadDevices: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('key backup recovery submit', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: KeyBackupRecoveryScreen(
          onRecover: (key) async => values.add(key),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'recovery-key');
    await tester.tap(find.text('恢復金鑰'));
    await tester.pumpAndSettle();
    expect(values, ['recovery-key']);
    expect(find.textContaining('已嘗試恢復'), findsOneWidget);
  });
}
