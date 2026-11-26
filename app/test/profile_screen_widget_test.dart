// 第四十七批：個人資料頁（獨立頁）——widget 測試。
//
// 驗收重點：
// - 設定頁的 Profile 區已改為**一列**（點入獨立頁）。
// - 個人資料頁含：大頭像、顯示名稱列、Matrix ID 列、頭像動作列。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/profile_screen.dart';
import 'package:homing/ui/settings_screen.dart';

void main() {
  testWidgets('個人資料頁：大頭像＋顯示名稱列＋Matrix ID 列＋動作列', (tester) async {
    final client = createClient();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(client: client),
      ),
    );
    await tester.pump();

    // 頁面標題
    expect(find.text('個人資料'), findsOneWidget);
    // 顯示名稱列與 Matrix ID 列
    expect(find.text('顯示名稱'), findsOneWidget);
    expect(find.text('Matrix ID'), findsOneWidget);
    // 頭像動作（相簿／拍照）
    expect(find.text('從相簿選擇'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    // 點大頭像 → 三選項 sheet
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.text('變更頭像'), findsOneWidget);
    expect(find.text('移除頭像'), findsNothing, reason: '無頭像時不顯示「移除頭像」');
  });

  testWidgets('設定頁：Profile 區改為一列並可進入個人資料頁', (tester) async {
    final client = createClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsBody(client: client),
        ),
      ),
    );
    await tester.pump();

    // Profile 列（顯示名稱或「個人名稱（未設定）」＋ chevron）。
    expect(find.text('個人名稱（未設定）'), findsOneWidget);

    // 點入個人資料頁。
    await tester.tap(find.text('個人名稱（未設定）'));
    await tester.pumpAndSettle();
    expect(find.text('個人資料'), findsOneWidget);
    expect(find.text('Matrix ID'), findsOneWidget);
  });
}
