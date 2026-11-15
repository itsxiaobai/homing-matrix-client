// 緊急訊息卡片（第四十二批；人類提供 LINE 參考圖）——widget 測試。
// 版位：滿版紅底＋白字（類別／說明／廣播 icon）＋動作「安否報告」「詳細來看」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/emergency_feed.dart';
import 'package:homing/ui/rooms_screen.dart';

void main() {
  testWidgets('示警以紅色卡片呈現，含安否報告／詳細來看兩個動作', (tester) async {
    final alert = EmergencyAlert(
      id: 'e1',
      category: '地震速報',
      sender: '中央氣象署',
      summary: '宜蘭縣近海發生芮氏 5.9 地震',
      link: 'https://example.tw/cap',
      sent: DateTime(2026, 11, 15, 12, 30),
      expires: DateTime(2026, 11, 15, 14, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoomsScreen(
          client: createClient(), // 卡片不需 client（僅渲染）
          loadRooms: (_) async => const [],
          emergencyAlerts: [alert],
        ),
      ),
    );
    await tester.pump();

    // 卡片文字
    expect(find.text('地震速報'), findsOneWidget);
    expect(find.textContaining('宜蘭縣近海'), findsOneWidget);
    // 動作按鈕（LINE：安否を報告／詳細を見る）
    expect(find.text('安否報告'), findsOneWidget);
    expect(find.text('詳細來看'), findsOneWidget);
    // 廣播 icon
    expect(find.byIcon(Icons.campaign), findsOneWidget);
    // 紅底（LINE 緊急紅）
    final reds = tester
        .widgetList<Material>(find.byType(Material))
        .where((m) => m.color == const Color(0xFFE8384F));
    expect(reds, isNotEmpty, reason: '應有 LINE 緊急紅的卡片底色');
  });
}
