// 第六十四批（人類指示 2026-11-17）：
// * ① 公告自動找過去訊息：首頁公告橫幅點擊 → 開房＋自動跳到釘選訊息
//   （`ChatScreen.jumpToEventId`；不在已載入窗口時有界 requestHistory）。
// * ② 圖片預覽左右滑：`ImagePreviewScreen` gallery（清單＋index＋每事件
//   loader 縫）；貼圖頁**不顯示**下載／分享（既有語意逐頁生效）。
// * ③ 點他人頭像顯示資訊：`_SenderAvatar` tooltip → 成員資訊 bottom sheet
//   （顯示名／Matrix ID；草案）。
// * ④ 緊急訊息測試選項：合成示警（build／encode／parse 純函式）；
//   `isEmergencyFlowAlert` 命中（求助流程可測）。
// UI 皆為草案（AGENTS.md：最終介面待人類設計）。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/emergency_feed.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:homing/ui/image_preview_screen.dart';

/// 最小合法 PNG（1x1 透明），供 Image.memory 直接解碼（同 batch_d 模式）。
final Uint8List pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  group('第六十四批①：公告自動跳到釘選訊息（ChatScreen.jumpToEventId）', () {
    testWidgets('訊息在已載入窗口 → 進房自動定位該訊息', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      // 50 則單行文字（時間序；目標＝第 3 則（很舊）→ 未跳轉時不會被
      // 建構（reverse 清單＋lazy builder，cacheExtent 之外）。
      const targetBody = '公告：本週五下午停電維護';
      final messages = <ChatMessageView>[
        for (var i = 0; i < 50; i++)
          ChatMessageView(
            sender: '@alice:matrix.org',
            body: i == 2 ? targetBody : '訊息 $i',
            eventId: '\$m$i',
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => messages,
            jumpToEventId: '\$m2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 自動跳轉成功 → 目標列被建構（可視範圍內）。
      expect(find.text(targetBody), findsOneWidget);
    });

    testWidgets('訊息太舊找不到 → SnackBar 如實提示（不假跳）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-b:matrix.org', client: client);

      final messages = <ChatMessageView>[
        for (var i = 0; i < 10; i++)
          ChatMessageView(
            sender: '@alice:matrix.org',
            body: '訊息 $i',
            eventId: '\$m$i',
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => messages,
            jumpToEventId: '\$missing',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 注入 loader（無 timeline）→ 直接提示「無法自動定位」。
      expect(find.textContaining('無法自動定位'), findsOneWidget);
    });
  });

  group('第六十四批②：圖片預覽左右滑（ImagePreviewScreen gallery）', () {
    // 三張圖（時間序）：A 圖片、B 圖片（初始）、C 貼圖（不可下載／分享）。
    (List<Event>, List<Event>) buildGallery() {
      final client = createClient();
      final room = Room(id: '!gallery:matrix.org', client: client);
      Event ev(String id, String body, {bool sticker = false}) => Event(
            type: sticker ? EventTypes.Sticker : 'm.room.message',
            content: sticker
                ? {'body': body}
                : {'msgtype': 'm.image', 'body': body},
            senderId: '@alice:matrix.org',
            eventId: id,
            originServerTs: DateTime.now(),
            room: room,
          );
      return (
        [ev(r'$a', 'a.png'), ev(r'$b', 'b.png'), ev(r'$c', 'c.png', sticker: true)],
        [ev(r'$a2', 'a2.png'), ev(r'$b2', 'b2.png'), ev(r'$c2', 'c2.png')],
      );
    }

    testWidgets('初始頁顯示指定圖片；左滑到下一張（貼圖頁隱藏下載／分享）',
        (tester) async {
      final (gallery, _) = buildGallery();
      final bytesOf = <String, Uint8List>{
        for (final e in gallery) e.body: pngBytes,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: gallery[1],
            initialBytes: pngBytes,
            galleryEvents: gallery,
            galleryInitialIndex: 1,
            loadGalleryBytes: (e) async => bytesOf[e.body],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始＝B 頁：標題與圖片可見，下載／分享入口存在（非貼圖）。
      expect(find.text('b.png'), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);

      // 左滑 → C 頁（貼圖）：下載／分享隱藏、改顯示說明（第五十四批語意）。
      // （拖曳目標＝PageView 本體＋fling 速度（緩慢拖過半頁會被彈回原頁）；
      // AppBar 標題同為 'b.png' 不可作為拖點。）
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('c.png'), findsOneWidget);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.textContaining('貼圖不提供下載'), findsOneWidget);

      // 右滑回 B 頁：下載／分享恢復。
      await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('b.png'), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });

    testWidgets('galleryInitialIndex 越界 → 落回第 0 頁', (tester) async {
      final (gallery, _) = buildGallery();

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: gallery[0],
            galleryEvents: gallery,
            galleryInitialIndex: 99,
            loadGalleryBytes: (_) async => pngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('a.png'), findsOneWidget);
    });

    testWidgets('放大中拖到圖片邊界還繼續滑 → 回 1x 並換下一張', (tester) async {
      final (gallery, _) = buildGallery();

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: gallery[0],
            initialBytes: pngBytes,
            galleryEvents: gallery,
            galleryInitialIndex: 0,
            loadGalleryBytes: (_) async => pngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 雙擊進入放大模式（2x，以頁面中心為錨）。
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // 單指拖曳：先移到圖片邊界（IV 夾取 tx），再繼續同方向滑 →
      // 累積翻頁意圖（門檻 96px，草案）超過 → 回 1x 換下一張。
      final gesture = await tester.startGesture(const Offset(400, 350));
      for (var i = 0; i < 14; i++) {
        await gesture.moveBy(const Offset(-50, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 已退出放大模式（回 1x）且換到下一張（b）。
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('b.png'), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });

    testWidgets('放大中拖到邊界換頁時已在最後一張 → 維持放大不換頁', (tester) async {
      final (gallery, _) = buildGallery();

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: gallery[2], // 最後一張（貼圖）。
            galleryEvents: gallery,
            galleryInitialIndex: 2,
            loadGalleryBytes: (_) async => pngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(InteractiveViewer), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(400, 350));
      for (var i = 0; i < 14; i++) {
        await gesture.moveBy(const Offset(-50, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 端頁不換頁：維持放大模式、仍在 c.png。
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('c.png'), findsOneWidget);
    });

    // 第六十四批⑤（人類實機回饋「1x 沒辦法兩指放大」）：自訂
    // _PinchToZoomRecognizer——僅兩指搶 arena；捏合即進入放大模式，倍率
    // 跟隨捏合（SDK 實證：scale 自 1.0 起算累積；見 image_preview_screen
    // 檔頭）。單指左右滑仍換頁＝既有 fling 測試涵蓋。
    testWidgets('1x 兩指捏合 → 進入放大（IV），倍率隨捏合', (tester) async {
      final (gallery, _) = buildGallery();

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: gallery[0],
            initialBytes: pngBytes,
            galleryEvents: gallery,
            galleryInitialIndex: 0,
            loadGalleryBytes: (_) async => pngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);

      // 兩指落下（間距 40）→ 同步外移 ±20×3（間距 40→160）。
      final g1 = await tester.startGesture(const Offset(380, 300));
      final g2 = await tester.startGesture(const Offset(420, 300));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(-20, 0));
        await g2.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }

      // 捏合 → 進入放大模式（IV 子樹），倍率跟隨捏合（≈4x）。
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final ctrl = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final m = ctrl.value;
      expect(m[0], closeTo(4.0, 0.5));

      // 手勢結束 → 維持放大（≤1 才退出）。
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('a.png'), findsOneWidget);
    });
  });

  group('第六十四批③：點他人頭像顯示對方資訊（bottom sheet；草案）', () {
    testWidgets('他人頭像 tap → sheet 顯示顯示名／Matrix ID', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-c:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => const [
              ChatMessageView(sender: '@alice:matrix.org', body: 'hello'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 無 member state（fake room）→ 顯示名 fallback＝Matrix ID。
      await tester.tap(find.byTooltip('顯示成員資訊'));
      await tester.pumpAndSettle();

      expect(find.text('@alice:matrix.org'), findsWidgets);
      expect(find.textContaining('顯示成員資訊'), findsNothing);

      // 關閉 sheet。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('@alice:matrix.org'), findsOneWidget);
    });
  });

  group('第六十四批④：緊急訊息測試選項（合成示警；純函式）', () {
    test('buildTestEmergencyAlert：命中求助流程類別＋標明測試', () {
      final alert = buildTestEmergencyAlert(id: 'homing-test-1');
      expect(alert.id, 'homing-test-1');
      expect(alert.category, contains('測試'));
      expect(alert.category, contains('地震速報')); // isEmergencyFlowAlert 命中
      expect(isEmergencyFlowAlert(alert), isTrue);
      expect(alert.sent, isNotNull);
      expect(alert.expires, isNotNull);
      expect(alert.expires!.isAfter(alert.sent!), isTrue);
    });

    test('encode／parse 往返；無效／過期＝null（自動關閉）', () {
      final alert = buildTestEmergencyAlert(id: 'homing-test-2');
      final encoded = encodeTestEmergencyAlert(alert);
      final parsed = parseTestEmergencyAlert(encoded);
      expect(parsed, isNotNull);
      expect(parsed!.id, alert.id);
      expect(parsed.category, alert.category);
      expect(parsed.summary, alert.summary);

      // 無效輸入 → null。
      expect(parseTestEmergencyAlert(null), isNull);
      expect(parseTestEmergencyAlert(''), isNull);
      expect(parseTestEmergencyAlert('not-json'), isNull);

      // 過期 → null（1 小時 TTL 自動失效）。
      final expired = EmergencyAlert(
        id: 'homing-test-3',
        category: '地震速報（測試）',
        sender: 'Homing 測試',
        summary: 'x',
        link: '',
        sent: DateTime(2026, 1, 1),
        expires: DateTime(2026, 1, 1, 2),
      );
      expect(
        parseTestEmergencyAlert(
          encodeTestEmergencyAlert(expired),
          now: DateTime(2026, 1, 2),
        ),
        isNull,
      );
    });
  });
}
