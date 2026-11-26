// 第五十四批測試（2026-11-16；不打網路）：**貼圖（m.sticker）不可分享／下載**。
//
// 背景（著作權）：貼圖包**自帶授權**（例：catpack_ok.zip 為 CC0-1.0、需附
// LICENSE.txt），貼圖不應被匯出到 App 之外——「分享至外部」會把解密後的原始
// 檔寫成暫存檔交給外部 App；「下載」則存進系統相簿／檔案。
//
// 覆蓋：
// * 聊天長按動作選單：貼圖**不顯示**「分享至外部」；一般文字訊息**仍顯示**
//   （回歸保護，避免連一般訊息也被誤砍）。
// * 全屏預覽頁（ImagePreviewScreen）：貼圖**不顯示**下載／分享鈕（改顯示說明
//   文字）；一般圖片事件**仍顯示**（回歸保護）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:homing/ui/image_preview_screen.dart';
import 'package:matrix/matrix.dart';

Event _mkEvent(
  Room room, {
  required String type,
  required Map<String, dynamic> content,
  DateTime? ts,
}) =>
    Event(
      type: type,
      content: content,
      senderId: '@bob:matrix.org',
      eventId: r'$e-export-1',
      originServerTs: ts ?? DateTime(2026, 11, 16, 10),
      room: room,
    );

void main() {
  group('第五十四批：貼圖不可分享／下載（著作權）', () {
    testWidgets('聊天長按：貼圖無「分享至外部」', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-sticker:matrix.org', client: client);
      final stickerEvent = _mkEvent(
        room,
        type: EventTypes.Sticker,
        content: {
          'body': '😺 開心',
          'url': 'mxc://matrix.org/sticker1',
          'info': {'mimetype': 'image/png', 'w': 128, 'h': 128},
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            key: const ValueKey('room-sticker'),
            room: room,
            loadMessages: (_) async => [
              ChatMessageView(
                sender: '@bob:matrix.org',
                body: '😺 開心',
                event: stickerEvent,
                isSticker: true,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 貼圖以圖片 tile 渲染；測試環境 HTTP 被封鎖 → 圖片載入失敗走 fallback
      //（顯示 body 文字），tile 仍在、外層長按手勢有效。
      final stickerTile = find.text('😺 開心');
      expect(stickerTile, findsOneWidget);

      await tester.longPress(stickerTile);
      await tester.pumpAndSettle();

      // 貼圖：不得出現「分享至外部」。
      expect(find.text('分享至外部'), findsNothing);
      // 其他動作仍在（選單本身正常開啟）。
      expect(find.text('檢舉'), findsOneWidget);
    });

    testWidgets('聊天長按：一般文字訊息**仍可**分享（回歸保護）',
        (tester) async {
      final client = createClient();
      final room = Room(id: '!room-text:matrix.org', client: client);
      final textEvent = _mkEvent(
        room,
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': '一般文字'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            key: const ValueKey('room-text'),
            room: room,
            loadMessages: (_) async => [
              ChatMessageView(
                sender: '@bob:matrix.org',
                body: '一般文字',
                event: textEvent,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('一般文字'));
      await tester.pumpAndSettle();
      expect(find.text('分享至外部'), findsOneWidget);
    });

    testWidgets('全屏預覽：貼圖無下載／分享鈕；一般圖片仍有', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-preview:matrix.org', client: client);

      // ── 貼圖 ──
      final stickerEvent = _mkEvent(
        room,
        type: EventTypes.Sticker,
        content: {
          'body': '😺 開心',
          'url': 'mxc://matrix.org/sticker1',
          'info': {'mimetype': 'image/png', 'w': 128, 'h': 128},
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(event: stickerEvent),
        ),
      );
      await tester.pump();
      // 貼圖：下載／分享鈕不見，只留說明文字。
      expect(find.byIcon(Icons.download), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.text('貼圖不提供下載／分享'), findsOneWidget);

      // ── 回歸保護：一般圖片事件仍有下載／分享鈕 ──
      // （第六十四批②：同型 widget 重複 pump 需 ValueKey——否則 State 被
      // 重用、_events 等仍是前一份事件的狀態；專案既有慣例。）
      final imageEvent = _mkEvent(
        room,
        type: EventTypes.Message,
        content: {
          'msgtype': 'm.image',
          'body': 'photo.png',
          'url': 'mxc://matrix.org/photo1',
          'info': {'mimetype': 'image/png', 'w': 128, 'h': 128},
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            key: ValueKey(imageEvent.eventId),
            event: imageEvent,
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });
  });
}
