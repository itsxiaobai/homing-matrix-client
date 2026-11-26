// backlog 批次 E（2026-11-01 人類 4 項回饋）：新功能骨架測試（不打網路）。
// * poll_compat（雙前綴相容）：start 事件穩定型別解析、回應掃描
//   （unstable＋stable 皆計；每人取最新一次；忽略結束事件之後的回應）、
//   結束偵測。
// * _ChatPollTile：穩定型別（m.poll.start）投票磚在注入 loader 下可渲染
//   （dual 相容；實際投票／結束送出需實機驗證）。
// * 訊息選取（草案 UI）：長按選單 ＝ 回覆／複製文字／檢舉／分享至外部；
//   注入測試無 event → 無 emoji 反應列；選「回覆」→ 預覽列 → 解除。
// 頭像（getDownloadUri → NetworkImage）與滑動手勢、實際回覆（SDK
// sendTextEvent(inReplyTo:)）需實機驗證；widget test 無平台通道。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
// TimelineChunk 官方 SDK 未由 matrix.dart 導出；測試僅用於離線構造 Timeline
// （poll_compat 的掃描層），不改 app 引用路徑。
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/poll_compat.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:homing/ui/image_preview_screen.dart';

Event makeEvent(
  Room room, {
  required String type,
  required Map<String, dynamic> content,
  String eventId = r'$e1',
  required DateTime ts,
  String sender = '@bob:matrix.org',
}) => Event(
  type: type,
  content: content,
  senderId: sender,
  eventId: eventId,
  originServerTs: ts,
  room: room,
);

/// 測試用 Timeline（不做任何網路呼叫）。
Timeline makeTimeline(Room room, List<Event> events) =>
    Timeline(room: room, chunk: TimelineChunk(events: events));

void main() {
  group('poll_compat（雙前綴相容，接收端）', () {
    test('start 事件：穩定型別 m.poll.start 可解析（Element 系相容）', () {
      final client = createClient();
      final room = Room(id: '!room:matrix.org', client: client);
      final base = DateTime(2026, 11, 1, 10);
      final event = makeEvent(
        room,
        type: 'm.poll.start',
        content: {
          'm.poll.start': {
            'kind': PollKind.disclosed.name,
            'max_selections': 1,
            'question': {'org.matrix.msc1767.text': '今天吃什麼？'},
            'answers': [
              {'id': 'a', 'org.matrix.msc1767.text': '便當'},
              {'id': 'b', 'org.matrix.msc1767.text': '麵'},
            ],
          },
        },
        eventId: r'$p',
        ts: base.add(const Duration(minutes: 1)),
      );
      final poll = pollStartContentCompat(event);
      expect(poll, isNotNull);
      expect(poll!.question.mText, '今天吃什麼？');
      expect(poll.answers.map((a) => a.mText), ['便當', '麵']);
      // 非投票事件（例如 m.room.message）→ null（不誤判）。
      final notPoll = makeEvent(
        room,
        type: 'm.room.message',
        content: {'msgtype': 'm.text', 'body': 'hi'},
        eventId: r'$t',
        ts: base.add(const Duration(minutes: 1)),
      );
      expect(pollStartContentCompat(notPoll), isNull);
    });

    test('回應掃描：unstable＋stable 皆計；每人取最新；沒有結束事件照常計', () {
      final client = createClient();
      final room = Room(id: '!room:matrix.org', client: client);
      final base = DateTime(2026, 11, 1, 10);
      // timeline 由新到舊（SDK 實際排序）。
      final timeline = makeTimeline(room, [
        makeEvent(
          room,
          type: 'm.poll.response', // 穩定（Element 系）
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reference,
              'event_id': r'$p',
            },
            'm.poll.response': {'answers': ['b']},
          },
          eventId: r'$r-new',
          ts: base.add(const Duration(minutes: 4)),
        ),
        makeEvent(
          room,
          type: PollEventContent.responseType, // unstable（SDK/Homing）
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reference,
              'event_id': r'$p',
            },
            PollEventContent.responseType: {'answers': ['a']},
          },
          eventId: r'$r-old',
          ts: base.add(const Duration(minutes: 1)),
        ),
        makeEvent(
          room,
          type: PollEventContent.responseType,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reference,
              'event_id': r'$p',
            },
            PollEventContent.responseType: {'answers': ['a']},
          },
          eventId: r'$r-carl',
          ts: base.add(const Duration(minutes: 2)),
          sender: '@carl:matrix.org',
        ),
      ]);
      final votes = pollResponsesCompat(timeline, r'$p');
      expect(votes['@bob:matrix.org'], {'b'}); // 最新一次覆蓋較舊一次。
      expect(votes['@carl:matrix.org'], {'a'});
      expect(pollEndedCompat(timeline, r'$p'), isFalse);
    });

    test('結束偵測與「結束後的回應不計」', () {
      final client = createClient();
      final room = Room(id: '!room:matrix.org', client: client);
      final base = DateTime(2026, 11, 1, 10);
      final timeline = makeTimeline(room, [
        makeEvent(
          room,
          type: PollEventContent.endType,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reference,
              'event_id': r'$p',
            },
            PollEventContent.endType: {},
          },
          eventId: r'$end',
          ts: base.add(const Duration(minutes: 3)),
          sender: '@alice:matrix.org',
        ),
        makeEvent(
          room,
          type: PollEventContent.responseType,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reference,
              'event_id': r'$p',
            },
            PollEventContent.responseType: {'answers': ['late']},
          },
          eventId: r'$r-late',
          ts: base.add(const Duration(minutes: 5)),
        ),
        makeEvent(
          room,
          type: PollEventContent.responseType,
          content: {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reference,
              'event_id': r'$p',
            },
            PollEventContent.responseType: {'answers': ['early']},
          },
          eventId: r'$r-early',
          ts: base.add(const Duration(minutes: 1)),
        ),
      ]);
      expect(pollEndedCompat(timeline, r'$p'), isTrue);
      final votes = pollResponsesCompat(timeline, r'$p');
      // 結束後的回應不計（SDK getPollResponses 同規則）。
      expect(votes['@bob:matrix.org'], {'early'});
    });
  });

  group('ChatScreen 訊息選取（草案；注入測試契約：loadMessages 事件為 null）', () {
    testWidgets('長按訊息 → 選單；選「回覆」→ 預覽列；解除', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              const ChatMessageView(sender: '@bob:matrix.org', body: '早安'),
            ],
            sendMessage: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('早安'));
      await tester.pumpAndSettle();

      expect(find.text('回覆'), findsOneWidget);
      expect(find.text('複製文字'), findsOneWidget);
      expect(find.text('分享至外部'), findsOneWidget);
      expect(find.text('檢舉'), findsOneWidget);
      // 無 event → 無 emoji 反應列（草案預設組 👍…）。
      expect(find.text('👍'), findsNothing);

      await tester.tap(find.text('回覆'));
      await tester.pumpAndSettle();

      // 回覆預覽列出現（輸入列上方）。
      expect(find.text('@bob:matrix.org：早安'), findsOneWidget);
      // 解除回覆。
      await tester.tap(find.byTooltip('解除回覆'));
      await tester.pumpAndSettle();
      expect(find.text('@bob:matrix.org：早安'), findsNothing);
    });

    testWidgets('穩定型別 m.poll.start 的投票磚可渲染（dual 相容）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              ChatMessageView(
                sender: '@bob:matrix.org',
                body: '[投票]', // 文案草案（SDK body 為 Unknown…，不宜露出）
                isPoll: true,
                event: makeEvent(
                  room,
                  type: 'm.poll.start',
                  content: {
                    'm.poll.start': {
                      'kind': PollKind.disclosed.name,
                      'max_selections': 1,
                      'question': {'org.matrix.msc1767.text': '今天吃什麼？'},
                      'answers': [
                        {'id': 'a', 'org.matrix.msc1767.text': '便當'},
                        {'id': 'b', 'org.matrix.msc1767.text': '麵'},
                      ],
                    },
                  },
                  eventId: r'$p',
                  ts: DateTime(2026, 11, 1, 10),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('今天吃什麼？'), findsOneWidget);
      expect(find.text('便當'), findsOneWidget);
      expect(find.text('麵'), findsOneWidget);
      // 注入 loader → 無 timeline → 非互動（不顯示投票按鈕）。
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('ImagePreviewScreen（批次 F：滿屏 viewport＋全尺寸載入狀態可見）', () {
    /// 測試用：與批次 D 測試檔相同的最小 PNG（1x1）；檔案間私有常數不可共用，
    /// 這裡另留一份（Uint8List 以便注入 loader 直接回傳）。
    final Uint8List png = Uint8List.fromList(<int>[
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

    /// 一次雙擊 = 兩次 tap，中間 pump 100ms（> kDoubleTapMinTime 40ms、
    /// < kDoubleTapTimeout 300ms；測試框架虛擬時鐘）。
    /// 第六十四批②：1x（未放大）為**純圖子樹**（無 InteractiveViewer）→
    /// 以畫面座標雙擊（頁面中心）；放大中雙擊由 InteractiveViewer 接收。
    Future<void> doubleTap(WidgetTester tester) async {
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('viewport 為滿屏（不受縮圖原生尺寸侷限）＋載入中提示', (tester) async {
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
      final loader = Completer<Uint8List?>(); // 保持「載入中」狀態。

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: event,
            initialBytes: png,
            loadFullBytes: () => loader.future,
          ),
        ),
      );
      await tester.pump();

      // 批次 F：滿屏 viewport。第六十四批②：1x 為純圖子樹（雙擊才進
      // InteractiveViewer）→ 以 1x 的頁面容器量測，恰為整個 body 區域
      //（測試 viewport 800×600 扣 AppBar）。人類 2026-11-17（兩指捏合）：
      // 頁面容器改 **RawGestureDetector**（雙擊＋自訂兩指捏合 recognizer）。
      // （畫面上還有其他偵測器——底部按鈕等 → 限定「Image 的祖先、且在
      // PageView 內」的那一個。）
      final bodySize = tester.getSize(find.byType(Stack).first);
      final pageGd = find
          .ancestor(
            of: find.byType(Image),
            matching: find.byType(RawGestureDetector),
          )
          .first;
      expect(
        tester.getSize(pageGd),
        bodySize,
      );
      // 全尺寸載入中的提示層（占位縮圖僅是臨時畫面）。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      loader.complete(png); // 收尾（避免懸掃 future）。
      await tester.pump();
    });

    testWidgets('雙擊放大以螢幕中心為錨（1x→2x→4x→1x；中心點不動）', (tester) async {
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
      final loader = Completer<Uint8List?>(); // 讓 zoom 只受雙擊驅動。

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: event,
            initialBytes: png,
            loadFullBytes: () => loader.future,
          ),
        ),
      );
      await tester.pump();

      TransformationController ctrl(WidgetTester t) =>
          t.widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!;

      // 雙擊 1 → 2x（進入放大模式＝InteractiveViewer 子樹）。
      // 錨 = viewer 中心：tx = cx(1−s) = −cx。
      await doubleTap(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      final viewerSize = tester.getSize(find.byType(InteractiveViewer));
      var m = ctrl(tester).value;
      expect(m[0], closeTo(2.0, 0.001));
      expect(m[5], closeTo(2.0, 0.001));
      expect(m[12], closeTo(-viewerSize.width / 2, 0.5));
      expect(m[13], closeTo(-viewerSize.height / 2, 0.5));

      // 雙擊 2 → 4x；tx = cx(1−4) = −3·cx。
      await doubleTap(tester);
      m = ctrl(tester).value;
      expect(m[0], closeTo(4.0, 0.001));
      expect(m[12], closeTo(-3 * viewerSize.width / 2, 0.5));
      expect(m[13], closeTo(-3 * viewerSize.height / 2, 0.5));

      // 雙擊 3 → 回 1x：退出放大模式（回到純圖子樹、無 InteractiveViewer）。
      await doubleTap(tester);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(Image), findsOneWidget);

      loader.complete(png); // 收尾。
      await tester.pump();
    });

    testWidgets('注入 loader 成功 → 換上全尺寸並重置縮放', (tester) async {
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
      final loader = Completer<Uint8List?>();

      await tester.pumpWidget(
        MaterialApp(
          home: ImagePreviewScreen(
            event: event,
            initialBytes: png,
            loadFullBytes: () => loader.future,
          ),
        ),
      );
      await tester.pump();

      // 先在縮圖占位上放大到 2x。
      await doubleTap(tester);

      loader.complete(png); // 全尺寸到齊。
      await tester.pumpAndSettle();

      // 第六十四批②：全尺寸到齊 → 重置縮放＝退出放大模式（回到 1x 純圖
      // 子樹；批次 F 的「重置縮放」語意以無 InteractiveViewer 呈現）。
      expect(find.byType(InteractiveViewer), findsNothing);
      // 載入完成 → 提示層消失；全尺寸 bytes 已在畫面（仍是 Image.memory）。
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('注入 loader 失敗 → 保留縮圖並顯示提示（不靜默）', (tester) async {
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
          home: ImagePreviewScreen(
            event: event,
            initialBytes: png,
            loadFullBytes: () async {
              throw StateError('boom');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 縮圖仍在（可基本瀏覽），頂部顯示失敗提示（文案草案）。
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('僅顯示縮圖（原始檔載入失敗）'), findsOneWidget);
    });
  });
}
