// 緊急訊息卡片（第四十二批；人類提供 LINE 參考圖）——widget 測試。
// 版位：滿版紅底＋白字（類別／說明／廣播 icon）＋動作「傳送現況」「詳細來看」。
// 第六十四批⑤（人類指示 2026-11-17）：「安否報告」改名「傳送現況」；
// 右上**叉叉關閉**；卡片**移入清單**（跟著畫面滑動）；有傳送現況記錄時
// 顯示**現況＋已通報名單**。
// 第六十六批：好友現況顯示行（1:1 房最新訊息解析；注入測試房間＋lastEvent）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/emergency_feed.dart';
import 'package:homing/ui/rooms_screen.dart';
import 'package:homing/ui/compound_icon.dart'; // 2026-11-20：icon 改 Compound
import 'package:matrix/matrix.dart';

void main() {
  EmergencyAlert makeAlert(String id) => EmergencyAlert(
        id: id,
        category: '地震速報',
        sender: '中央氣象署',
        summary: '宜蘭縣近海發生芮氏 5.9 地震',
        link: 'https://example.tw/cap',
        sent: DateTime(2026, 11, 15, 12, 30),
        expires: DateTime(2026, 11, 15, 14, 30),
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<EmergencyAlert> alerts,
    EmergencyStatusRecord? status,
    Client? client,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoomsScreen(
          client: client ?? createClient(), // 卡片不需 client（僅渲染）
          loadRooms: (_) async => const [],
          emergencyAlerts: alerts,
          // 第六十四批⑤：狀態記錄注入縫（僅測試；正式由 _loadEmergency 讀 kv）。
          statusRecords: status == null ? null : {status.alertId: status},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('示警以紅色卡片呈現，含傳送現況／詳細來看兩個動作＋叉叉關閉',
      (tester) async {
    await pumpCard(tester, alerts: [makeAlert('e1')]);

    // 卡片文字
    expect(find.text('地震速報'), findsOneWidget);
    expect(find.textContaining('宜蘭縣近海'), findsOneWidget);
    // 動作按鈕（第六十四批⑤：「安否報告」→「傳送現況」）
    expect(find.text('安否報告'), findsNothing);
    expect(find.text('傳送現況'), findsOneWidget);
    expect(find.text('詳細來看'), findsOneWidget);
    // 右上叉叉關閉（第六十四批⑤；2026-11-20 改 Compound SVG）
    expect(
      find.byWidgetPredicate(
        (w) => w is CompoundIcon && w.name == CompoundIcons.close,
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('關閉'), findsOneWidget);
    // 廣播 icon（Compound；原 campaign 無對應 → notifications）
    expect(
      find.byWidgetPredicate(
        (w) => w is CompoundIcon &&
            w.name == CompoundIcons.notifications &&
            w.size == 34, // 卡片廣播圖 34dp；首頁頂列通知鈕 24dp
      ),
      findsOneWidget,
    );
    // 紅底（LINE 緊急紅）
    final reds = tester
        .widgetList<Material>(find.byType(Material))
        .where((m) => m.color == const Color(0xFFE8384F));
    expect(reds, isNotEmpty, reason: '應有 LINE 緊急紅的卡片底色');
  });

  testWidgets('叉叉關閉 → 卡片消失（session 隱藏）', (tester) async {
    await pumpCard(tester, alerts: [makeAlert('e1')]);
    expect(find.text('地震速報'), findsOneWidget);
    await tester.tap(find.byTooltip('關閉'));
    await tester.pump();
    expect(find.text('地震速報'), findsNothing);
  });

  testWidgets('有傳送現況記錄 → 顯示現況＋已通報名單', (tester) async {
    final alert = makeAlert('e1');
    await pumpCard(
      tester,
      alerts: [alert],
      status: EmergencyStatusRecord(
        alertId: 'e1',
        affected: true,
        notified: const [(roomId: '!a:matrix.org', name: 'Alice')],
        updatedAt: DateTime(2026, 11, 15, 13, 0),
      ),
    );
    expect(find.textContaining('受影響'), findsOneWidget);
    expect(find.textContaining('已通報'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
  });

  // 第六十六批（人類指示「顯示哪些好友受影響和沒受影響」）：好友現況解析——
  // 1:1 房最新訊息含【緊急現況】／【報平安】＋示警類別＋時間窗 → 卡片顯示行。
  testWidgets('好友現況：最新訊息含標記 → 卡片顯示該好友受影響／沒事',
      (tester) async {
    final client = createClient();
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:matrix.org': <String>['!dm:matrix.org'],
      },
    );
    final room = Room(id: '!dm:matrix.org', client: client);
    room.setState(StrippedStateEvent(
      type: EventTypes.RoomMember,
      senderId: '@bob:matrix.org',
      stateKey: '@bob:matrix.org',
      content: {'membership': 'join', 'displayname': 'Bob'},
    ));
    // 最新訊息＝Bob 的報平安（含示警類別；時間窗內）。
    room.lastEvent = Event(
      type: EventTypes.Message,
      eventId: 'e1',
      senderId: '@bob:matrix.org',
      room: room,
      originServerTs: DateTime(2026, 11, 15, 13, 0),
      content: {
        'msgtype': 'm.text',
        'body':
            '【報平安】我沒事，不受此示警影響。\n示警：地震速報\n—— 來自 Homing 傳送現況',
      },
    );
    // Official testing-only setter（SDK；測試離線注入房間清單）。
    client.rooms = [room];

    await pumpCard(tester, alerts: [makeAlert('e1')], client: client);
    await tester.pump();

    // 卡片顯示好友現況行（好友名＋沒事）。
    expect(find.textContaining('好友現況'), findsOneWidget);
    expect(find.textContaining('Bob'), findsOneWidget);
  });

  testWidgets('好友現況：訊息無標記 → 不顯示好友現況行', (tester) async {
    final client = createClient();
    final room = Room(id: '!dm2:matrix.org', client: client);
    room.lastEvent = Event(
      type: EventTypes.Message,
      eventId: 'e2',
      senderId: '@carol:matrix.org',
      room: room,
      originServerTs: DateTime(2026, 11, 15, 13, 0),
      content: {'msgtype': 'm.text', 'body': '今天天氣不錯'},
    );
    client.rooms = [room];

    await pumpCard(tester, alerts: [makeAlert('e1')], client: client);
    await tester.pump();
    expect(find.textContaining('好友現況'), findsNothing);
  });

  testWidgets('卡片在清單內（跟著畫面滑動；不在固定頂部）', (tester) async {
    await pumpCard(tester, alerts: [makeAlert('e1')]);
    // 卡片的上層應可捲動（ListView／CustomScroll），而非固定 Column。
    final scrollers = find.byWidgetPredicate(
      (w) => w is ListView || w is CustomScrollView || w is SingleChildScrollView,
    );
    expect(scrollers, findsWidgets);
    final cardCenter = tester.getCenter(find.text('傳送現況'));
    final scrollerFound = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .evaluate()
        .isNotEmpty;
    expect(scrollerFound, isTrue, reason: '卡片應在可捲動區內');
    // 確保卡片中心落在可捲動 viewport 內（不在固定 Column）。
    final viewportRect = tester.getRect(find.byType(Viewport).first);
    expect(viewportRect.contains(cardCenter), isTrue);
  });
}
