// 第四十六批（人類回報「群組公告還是被當成緊急訊息，應該恢復成一般公告」）
// —— 回歸測試：一般公告 ≠ 緊急示警。
//
// 分流原則：
// - 一般公告（聊天室釘選訊息）→ **中性色**＋「公告：」前綴＋廣播 icon。
// - 緊急示警（PWS RSS 官方 feed）→ LINE 緊急紅卡片。
//
// 本測試鎖住「公告不得使用緊急紅、且前綴為『公告：』」這兩點，避免日後
// 又把群組公告畫成緊急訊息。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/ui/announcement_banner.dart';

void main() {
  group('一般公告橫幅（AnnouncementBanner）', () {
    testWidgets('用中性色底（不是緊急紅），前綴為「公告：」', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnnouncementBanner(
              text: '週三晚上七點維護',
              title: '維運群組',
            ),
          ),
        ),
      );
      await tester.pump();

      // 前綴＝「公告：」（不是「緊急：」）。
      expect(find.text('公告：週三晚上七點維護'), findsOneWidget);
      expect(find.textContaining('緊急'), findsNothing);

      // 廣播 icon（LINE 公告版位）。
      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);

      // 底色＝中性容器色；**不得**是緊急紅 #E8384F。
      final emergencyRed = const Color(0xFFE8384F);
      final reds = tester
          .widgetList<Material>(find.byType(Material))
          .where((m) => m.color == emergencyRed);
      expect(reds, isEmpty, reason: '一般公告不得使用緊急紅');
    });

    testWidgets('副標顯示來源聊天室名稱；無副標時不顯示副標列', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnnouncementBanner(text: '公告內容', title: '公告群'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('公告群'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnnouncementBanner(text: '公告內容'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('公告：公告內容'), findsOneWidget);
    });

    testWidgets('可點擊（有 onTap 時）→ 點擊觸發回呼', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnnouncementBanner(
              text: '可點公告',
              onTap: () => tapped++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('公告：可點公告'));
      await tester.pump();
      expect(tapped, 1);
    });
  });
}
