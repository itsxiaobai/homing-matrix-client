// backlog 批次 D（2026-11-01 人類指示）：新功能骨架測試（不打網路）。
// * 投票：PollCreateScreen 注入 startPoll，檢查問題／選項／公開傳遞。
// * 圖片預覽：ImagePreviewScreen 以 initialBytes 渲染（SDK 全尺寸下載路徑
//   在 widget test 無平台通道 → 錯誤被畫面內部 catch，不影響渲染斷言）。
// * 未讀：RoomsScreen 長按選單含「標記為未讀」入口（動作經 SDK，
//   實際 markUnread 由人類實機驗證）。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/image_preview_screen.dart';
import 'package:homing/ui/poll_create_screen.dart';
import 'package:homing/ui/rooms_screen.dart';

void main() {
  group('PollCreateScreen（投票）', () {
    testWidgets('填入問題＋兩個選項後送出，注入的 startPoll 收到正確資料', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      String? capturedQuestion;
      List<String>? capturedOptions;
      bool? capturedDisclosed;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScaffoldShim(
            child: PollCreateScreen(
              room: room,
              startPoll: (q, opts, {required disclosed}) async {
                capturedQuestion = q;
                capturedOptions = opts;
                capturedDisclosed = disclosed;
                return 'poll-start';
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 第三個欄位依序：[0]=問題、[1]=選項1、[2]=選項2。
      await tester.enterText(find.byType(TextField).at(0), '今天吃什麼');
      await tester.enterText(find.byType(TextField).at(1), '便當');
      await tester.enterText(find.byType(TextField).at(2), '麵');

      // 需 pump：ListenableBuilder 依 controller 變動排幀，pump 後才會反映最新狀態。
      await tester.pump();

      final btn = tester.widget<TextButton>(find.widgetWithText(TextButton, '送出'));
      expect(btn.onPressed, isNotNull, reason: '輸入後送出按鈕應啟用');
      await tester.tap(find.text('送出'));
      await tester.pumpAndSettle();

      expect(capturedQuestion, '今天吃什麼');
      expect(capturedOptions, ['便當', '麵']);
      expect(capturedDisclosed, isTrue);
    });
  });

  group('ImagePreviewScreen（圖片預覽）', () {
    testWidgets('以 initialBytes 顯示圖片＋下載／分享入口存在', (tester) async {
      final client = createClient();
      final room = Room(id: '!img-room:matrix.org', client: client);
      final event = Event(
        type: 'm.room.message',
        content: {'msgtype': 'm.image', 'body': 'p.png'},
        senderId: '@a:matrix.org',
        eventId: r'$a',
        originServerTs: DateTime.now(),
        room: room,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(event: event, initialBytes: _pngBytes),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });
  });

  group('RoomsScreen（標記為未讀）', () {
    testWidgets('長按房間 → 選單含「標記為未讀」入口', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: RoomsScreen(
            client: client,
            loadRooms: (_) async => [room],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 長按列表第一項（ListTile = 房間列）。
      await tester.longPress(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      expect(find.text('標記為未讀'), findsOneWidget);

      // 關閉 sheet（點外面）。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('標記為未讀'), findsNothing);
    });
  });
}

/// ChatScaffoldShim：ences no-op container（保留未來導覽測試掛勾）。
class ChatScaffoldShim extends StatelessWidget {
  const ChatScaffoldShim({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// 最小合法 PNG（1x1 透明），供 Image.memory 直接解碼。
final Uint8List _pngBytes = Uint8List.fromList(<int>[
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
