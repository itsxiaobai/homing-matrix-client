// 第三十五批測試（人類需求 #4/#5/#6/#13/#14；不打網路）。
// * #5 無聲傳送：旗標判讀＋content 組裝＋ChatScreen 注入送出（silent 復位）。
// * #13 Markdown：送出端 markdownToMessageHtml；收訊端白名單 spans。
// * #14 原始訊息：渲染白名單（未知標籤剝殼／mx-reply 剝除／entity 解碼）＋
//   長按「查看原始訊息」dialog（content JSON）。
// * #4 貼圖白名單：`_stickerMime` 私有 → 以行為測試覆蓋（sendRich 注入與
//   貼圖路徑獨立；MIME 判斷的行為由 widget 測試以外函式覆蓋不易，改由
//   批次 III-b 既有路徑＋本批 nullable 語意以 lint/analyze 把關）。
//   補充：main_shell 的 FLUTTER_TEST guard 不啟動輪詢 → #6 觸發走直接
//   構造 Screen；feed parser 走公開 parseEmergencyFeedXml（雙形狀 fixture
//   取自 2026-11-12 cbs.tw 實抓樣本與批 16 官方通路樣本）。
// * #6 緊急流程：模板純函式＋三步驟 widget 測試（119＝不碰 DB 路徑）＋
//   ShareToRoomScreen 預選（SDK testing-only rooms setter 注入）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/emergency_feed.dart';
import 'package:homing/markdown_message.dart';
import 'package:homing/message_content.dart';
import 'package:homing/share_receiver.dart';
import 'package:homing/ui/chat_screen.dart';
import 'package:homing/ui/emergency_flow_screen.dart';
import 'package:homing/ui/share_to_room_screen.dart';
import 'package:matrix/matrix.dart';

Event makeEvent(
  Room room, {
  required Map<String, dynamic> content,
  String eventId = r'$e1',
  required DateTime ts,
  String sender = '@bob:matrix.org',
}) => Event(
  type: 'm.room.message',
  content: content,
  senderId: sender,
  eventId: eventId,
  originServerTs: ts,
  room: room,
);

/// 收集 spans 全部文字（遞迴；斷言用）。
String collectText(List<InlineSpan> spans) {
  final buf = StringBuffer();
  void walk(List<InlineSpan> list) {
    for (final s in list) {
      if (s is TextSpan) {
        buf.write(s.text);
        walk(s.children ?? const []);
      }
    }
  }
  walk(spans);
  return buf.toString();
}

/// cbs.tw 無前綴形狀（2026-11-12 實抓；expires 已調整為測試用未來時點）。
const String kCbsTwFixture = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://alerts.ncdr.nat.gov.tw/RSS.aspx</id>
  <title>NCDR_CAP-</title>
  <updated>2026-11-12T15:09:35+08:00</updated>
  <author><name>NCDR</name></author>
  <entry>
    <id>A2026111213135287746424460</id>
    <title>水庫放流</title>
    <sent>2026-11-12T14:16:03+08:00</sent>
    <expires>2026-11-12T16:45:15+08:00</expires>
    <sender><value>台灣電力股份有限公司大觀發電廠</value></sender>
    <status>Actual</status>
    <msgType>Alert</msgType>
    <link rel="alternate" href="https://cbs.tw/26113cdd5d1d"/>
    <text>[水庫放水警戒]武界壩 自20時起實施調節性放水</text>
  </entry>
  <entry>
    <id>A2026111213135287746424461</id>
    <title>地震速報</title>
    <sent>2026-11-12T14:20:00+08:00</sent>
    <expires>2026-11-12T16:50:00+08:00</expires>
    <sender><value>交通部中央氣象署</value></sender>
    <status>Actual</status>
    <msgType>Alert</msgType>
    <text>震度 4 級</text>
  </entry>
  <entry>
    <id>A2026111213135287746424462</id>
    <title>地震速報（撤銷）</title>
    <sent>2026-11-12T14:25:00+08:00</sent>
    <expires>2026-11-12T16:55:00+08:00</expires>
    <status>Actual</status>
    <msgType>Cancel</msgType>
    <text>撤銷</text>
  </entry>
</feed>
''';

/// 官方通路形狀（cap: 前綴；批 16 樣本結構，expires 用 zh-TW 12 小時制）。
const String kCapPrefixFixture = '''
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:cap="urn:oasis:names:tc:emergency:cap:1.1">
  <entry>
    <id>A202611070900001</id>
    <title>颱風</title>
    <cap:status>Actual</cap:status>
    <cap:msgType>Alert</cap:msgType>
    <cap:expires>2026/11/13 上午 11:00:00</cap:expires>
    <author><name>交通部中央氣象署</name></author>
    <summary><b>陸上警報</b>請防範強風豪雨</summary>
  </entry>
  <entry>
    <id>A202611070900002</id>
    <title>測試</title>
    <cap:status>Test</cap:status>
    <cap:msgType>Alert</cap:msgType>
    <cap:expires>2026/11/13 上午 11:00:00</cap:expires>
  </entry>
</feed>
''';

void main() {
  group('#5 message_content（無聲旗標＋content 組裝）', () {
    test('isSilentMessage：null／無旗標／false ＝ 非無聲；true ＝ 無聲', () {
      expect(isSilentMessage(null), isFalse);
      final room = Room(id: '!r:matrix.org', client: createClient());
      final plain = makeEvent(
        room,
        content: {'msgtype': 'm.text', 'body': 'hi'},
        ts: DateTime(2026, 11, 12),
      );
      expect(isSilentMessage(plain), isFalse);
      final silent = makeEvent(
        room,
        content: {'msgtype': 'm.text', 'body': 'hi', 'dev.homing.silent': true},
        ts: DateTime(2026, 11, 12),
      );
      expect(isSilentMessage(silent), isTrue);
      final flagFalse = makeEvent(
        room,
        content: {'msgtype': 'm.text', 'body': 'hi', 'dev.homing.silent': false},
        ts: DateTime(2026, 11, 12),
      );
      expect(isSilentMessage(flagFalse), isFalse);
    });

    test('buildTextMessageContent：基本形狀／silent／formatted（可疊加）', () {
      final plain = buildTextMessageContent('你好');
      expect(plain['msgtype'], 'm.text');
      expect(plain['body'], '你好');
      expect(plain.containsKey('dev.homing.silent'), isFalse);
      expect(plain.containsKey('formatted_body'), isFalse);

      final silent = buildTextMessageContent('你好', silent: true);
      expect(silent['dev.homing.silent'], isTrue);

      final rich = buildTextMessageContent('你好', formattedBody: '<p>你好</p>');
      expect(rich['format'], 'org.matrix.custom.html');
      expect(rich['formatted_body'], '<p>你好</p>');

      final both = buildTextMessageContent(
        '你好',
        silent: true,
        formattedBody: '<p>你好</p>',
      );
      expect(both['dev.homing.silent'], isTrue);
      expect(both['formatted_body'], '<p>你好</p>');
    });
  });

  group('#13 markdownToMessageHtml（送出端）', () {
    test('常見語法：粗體／斜體／行內碼／清單／引用／連結', () {
      expect(markdownToMessageHtml('**粗**'), '<p><strong>粗</strong></p>');
      expect(markdownToMessageHtml('*斜*'), '<p><em>斜</em></p>');
      expect(markdownToMessageHtml('`code`'), '<p><code>code</code></p>');
      final listHtml = markdownToMessageHtml('- 甲\n- 乙')!;
      expect(listHtml, contains('<ul>'));
      expect(listHtml, contains('<li>甲</li>'));
      expect(markdownToMessageHtml('> 引用')!, contains('blockquote'));
      final linkHtml = markdownToMessageHtml('[x](https://example.com)')!;
      expect(linkHtml, contains('href="https://example.com"'));
    });

    test('空字串／不可解析 → null（呼叫端退回純文字 body）', () {
      expect(markdownToMessageHtml(''), isNull);
      expect(markdownToMessageHtml('   '), isNull);
    });
  });

  group('#14 formattedMessageSpans（收訊端白名單渲染）', () {
    test('白名單內：b／strong／i／em／u／s／code 樣式 span 產出', () {
      final spans = formattedMessageSpans('<b>粗</b><i>斜</i>');
      expect(collectText(spans), contains('粗'));
      expect(collectText(spans), contains('斜'));
    });

    test('未知標籤剝殼留文字（script／font／span）', () {
      final spans = formattedMessageSpans(
        '<script>alert(1)</script>正文<font size="9">字</font>',
      );
      final text = collectText(spans);
      expect(text, contains('alert(1)'));
      expect(text, contains('正文'));
      expect(text, contains('字'));
    });

    test('mx-reply 整段剝除（回覆引言由既有 m.relates_to 路徑呈現）', () {
      final spans = formattedMessageSpans(
        '<mx-reply><blockquote>引言</blockquote></mx-reply><p>本文</p>',
      );
      final text = collectText(spans);
      expect(text, isNot(contains('引言')));
      expect(text, contains('本文'));
    });

    test('entity 解碼：&lt; &gt; &amp; &quot; &#39;', () {
      final spans = formattedMessageSpans('&lt;tag&gt; &amp; &quot;q&quot; &#39;');
      expect(collectText(spans), '<tag> & "q" \'');
    });

    test('a href：安全 scheme 可點；javascript: 拒絕（無 recognizer）', () {
      String? tapped;
      final spans = formattedMessageSpans(
        '<a href="https://ok.example">好</a>'
        '<a href="javascript:evil()">壞</a>',
        onLinkTap: (url) => tapped = url,
      );
      final textSpans = <TextSpan>[];
      void walk(List<InlineSpan> list) {
        for (final s in list) {
          if (s is TextSpan) {
            textSpans.add(s);
            walk(s.children ?? const []);
          }
        }
      }
      walk(spans);
      final ok = textSpans.firstWhere((s) => s.text == '好');
      final bad = textSpans.firstWhere((s) => s.text == '壞');
      expect(ok.recognizer, isNotNull);
      expect(bad.recognizer, isNull);
      void tapOk() => (ok.recognizer as dynamic).onTap!();
      tapOk();
      expect(tapped, 'https://ok.example');
    });

    test('formattedMessageWidget：無輸出 → null；有輸出 → Text.rich', () {
      expect(formattedMessageWidget(''), isNull);
      expect(formattedMessageWidget('<b>x</b>'), isA<Text>());
    });
  });

  group('#6 emergency_feed（雙形狀 parser＋流程觸發類別）', () {
    final now = DateTime.parse('2026-11-12T15:00:00+08:00');

    test('cbs.tw 無前綴形狀：欄位解析＋Actual 過濾＋Cancel 剝除', () {
      final alerts = parseEmergencyFeedXml(kCbsTwFixture, now);
      // 3 條 entry：Cancel 條目剝除 → 2 條。
      expect(alerts.length, 2);
      final reservoir = alerts.firstWhere((a) => a.id.endsWith('460'));
      expect(reservoir.category, '水庫放流');
      expect(reservoir.sender, '台灣電力股份有限公司大觀發電廠');
      expect(reservoir.summary, contains('武界壩'));
      expect(reservoir.link, 'https://cbs.tw/26113cdd5d1d');
      expect(reservoir.expires, DateTime.parse('2026-11-12T16:45:15+08:00'));
      final quake = alerts.firstWhere((a) => a.id.endsWith('461'));
      expect(quake.category, '地震速報');
    });

    test('官方 cap: 前綴形狀：Test 不顯示；zh-TW expires 解析；summary 去標籤', () {
      final alerts = parseEmergencyFeedXml(
        kCapPrefixFixture,
        DateTime(2026, 11, 12, 15),
      );
      // Test 條目剝除 → 1 條（颱風）。
      expect(alerts.length, 1);
      final typhoon = alerts.single;
      expect(typhoon.id, 'A202611070900001');
      expect(typhoon.category, '颱風');
      expect(typhoon.sender, '交通部中央氣象署');
      // zh-TW 12 小時制：2026/11/13 上午 11:00:00。
      expect(typhoon.expires, DateTime(2026, 11, 13, 11));
      // summary 的 <b> 標籤剝除、entity 解碼。
      expect(typhoon.summary, contains('陸上警報'));
      expect(typhoon.summary, isNot(contains('<b>')));
    });

    test('過期條目不顯示（expires <= now）', () {
      const xml = '''
      <feed>
        <entry><id>e1</id><status>Actual</status><msgType>Alert</msgType>
        <expires>2026-11-12T10:00:00+08:00</expires><text>過期</text></entry>
      </feed>
      ''';
      expect(parseEmergencyFeedXml(xml, now), isEmpty);
    });

    test('isEmergencyFlowAlert：地震速報／地震報告／颱風 ＝ 是；其他 ＝ 否', () {
      EmergencyAlert make(String category) => EmergencyAlert(
            id: 'x',
            category: category,
            sender: '',
            summary: '',
            link: '',
            sent: null,
            expires: null,
          );
      expect(isEmergencyFlowAlert(make('地震速報')), isTrue);
      expect(isEmergencyFlowAlert(make('地震報告')), isTrue);
      expect(isEmergencyFlowAlert(make('颱風')), isTrue);
      // 高風險但不在求助流程清單。
      expect(isEmergencyFlowAlert(make('淹水')), isFalse);
      expect(isEmergencyFlowAlert(make('水庫放流')), isFalse);
      expect(isEmergencyFlowAlert(make('')), isFalse);
    });
  });

  group('#6 emergencyFlowMessage（模板純函式）', () {
    final alert = EmergencyAlert(
      id: 'a',
      category: '地震速報',
      sender: '交通部中央氣象署',
      summary: '震度 4 級',
      link: '',
      sent: null,
      expires: null,
    );

    test('contacts／everyone：求助訊息含示警類別與內容', () {
      final msg = emergencyFlowMessage(alert, EmergencyFlowTarget.contacts);
      expect(msg, contains('地震速報'));
      expect(msg, contains('震度 4 級'));
      expect(emergencyFlowMessage(alert, EmergencyFlowTarget.everyone), msg);
    });

    test('119：請對方協助通報（不自動撥號）', () {
      final msg = emergencyFlowMessage(alert, EmergencyFlowTarget.e119);
      expect(msg, contains('119'));
      expect(msg, contains('地震速報'));
      expect(msg, isNot(emergencyFlowMessage(alert, EmergencyFlowTarget.contacts)));
    });
  });

  group('#6 EmergencyFlowScreen（三步驟；草案 UI）', () {
    final alert = EmergencyAlert(
      id: 'A1',
      category: '地震速報',
      sender: '交通部中央氣象署',
      summary: '震度 4 級',
      link: '',
      sent: null,
      expires: null,
    );

    testWidgets('是 → 幫你聯絡誰？ → 119 → 訊息預覽（模板帶入可編輯）→ picker', (tester) async {
      final client = createClient();
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyFlowScreen(client: client, alert: alert),
        ),
      );
      await tester.pumpAndSettle();

      // 步驟一。
      expect(find.text('需要幫忙嗎？'), findsOneWidget);
      expect(find.text('地震速報'), findsOneWidget);
      await tester.tap(find.text('是'));
      await tester.pumpAndSettle();

      // 步驟二。
      expect(find.text('幫你聯絡誰？'), findsOneWidget);
      await tester.tap(find.text('119'));
      await tester.pumpAndSettle();

      // 步驟三：預覽帶入 119 模板（可編輯 TextField）。
      expect(find.text('訊息預覽（可編輯）'), findsOneWidget);
      final template = emergencyFlowMessage(alert, EmergencyFlowTarget.e119);
      expect(find.text(template), findsOneWidget);

      // 選擇要通知的對象 → 重用 ShareToRoomScreen（119＝不預選、不碰 DB）。
      await tester.tap(find.text('選擇要通知的對象'));
      await tester.pumpAndSettle();
      // Finder 不含 offstage（底層流程畫面按鈕不算）→ 只找 picker AppBar。
      expect(find.text('選擇要通知的對象'), findsOneWidget);
      expect(find.text('沒有可分享的聊天室'), findsOneWidget);
    });

    testWidgets('否 → 關閉', (tester) async {
      final client = createClient();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EmergencyFlowScreen(client: client, alert: alert),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('需要幫忙嗎？'), findsOneWidget);
      await tester.tap(find.text('否'));
      await tester.pumpAndSettle();
      // 流程畫面 pop → 回到按鈕頁。
      expect(find.text('需要幫忙嗎？'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('#6 ShareToRoomScreen 預選（SDK testing-only rooms setter）', () {
    testWidgets('preselectedRoomIds → checkbox 預選；title 覆寫', (tester) async {
      final client = createClient();
      final roomA = Room(id: '!a:matrix.org', client: client);
      final roomB = Room(id: '!b:matrix.org', client: client);
      // Official testing-only setter（SDK L430；測試離線注入房間清單）。
      client.rooms = [roomA, roomB];

      await tester.pumpWidget(
        MaterialApp(
          home: ShareToRoomScreen(
            client: client,
            payload: SharePayload.textOnly('緊急求助訊息'),
            preselectedRoomIds: {'!a:matrix.org'},
            title: '選擇要通知的對象',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('選擇要通知的對象'), findsOneWidget);
      final boxes = find.byType(Checkbox).evaluate().toList();
      expect(boxes.length, 2);
      expect((boxes[0].widget as Checkbox).value, isTrue); // !a 預選
      expect((boxes[1].widget as Checkbox).value, isFalse); // !b 未預選

      // 仍可增選（發到哪裡讓使用者決定）。
      await tester.tap(find.byType(ListTile).at(1));
      await tester.pumpAndSettle();
      final boxes2 = find.byType(Checkbox).evaluate().toList();
      expect((boxes2[1].widget as Checkbox).value, isTrue);
    });

    testWidgets('無預選 → 全部未勾（既有行為不變）', (tester) async {
      final client = createClient();
      client.rooms = [Room(id: '!a:matrix.org', client: client)];
      await tester.pumpWidget(
        MaterialApp(
          home: ShareToRoomScreen(
            client: client,
            payload: SharePayload.textOnly('hi'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('分享到聊天室'), findsOneWidget);
      final box = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box.value, isFalse);
    });
  });

  group('#5＋#13 ChatScreen 送出（注入 sendRichMessage）', () {
    testWidgets('無聲開關 → 送出帶 silent:true、formattedBody null', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-s:matrix.org', client: client);
      bool? capturedSilent;
      String? capturedFormatted;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => const [],
            sendRichMessage: (
              room,
              text, {
              silent = false,
              formattedBody,
            }) async {
              capturedSilent = silent;
              capturedFormatted = formattedBody;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 開附件面板 → 無聲開關（第三十五批 #5）。
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.notifications_off));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '沉靜訊息');
      await tester.pump(); // 輸入後 build 一幀，送出鈕才會出現（既有慣例）
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(capturedSilent, isTrue);
      expect(capturedFormatted, isNull);
    });

    testWidgets('Markdown 開關 → 送出帶 formatted_body', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-m:matrix.org', client: client);
      final silents = <bool>[];
      final formatted = <String?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => const [],
            sendRichMessage: (
              room,
              text, {
              silent = false,
              formattedBody,
            }) async {
              silents.add(silent);
              formatted.add(formattedBody);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.code)); // Markdown 開關（Icons.markdown 不存在）
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '**粗**');
      await tester.pump(); // 輸入後 build 一幀，送出鈕才會出現（既有慣例）
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(silents.single, isFalse);
      expect(formatted.single, '<p><strong>粗</strong></p>');
    });
  });

  group('#14 渲染＋原始訊息（ChatScreen 注入）', () {
    testWidgets('formatted_body → 白名單渲染；長按 → 查看原始訊息 dialog', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-f:matrix.org', client: client);
      final event = makeEvent(
        room,
        content: {
          'msgtype': 'm.text',
          'body': '**粗**',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<b>粗體</b>正文',
        },
        ts: DateTime(2026, 11, 12, 10),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              ChatMessageView(
                sender: '@bob:matrix.org',
                body: '**粗**',
                event: event,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 白名單渲染（Text.rich → RichText；正文文字存在）。
      expect(find.text('粗體正文', findRichText: true), findsOneWidget);

      // 長按 → 選單含「查看原始訊息」→ dialog 顯示 content JSON。
      await tester.longPress(find.text('粗體正文'));
      await tester.pumpAndSettle();
      expect(find.text('查看原始訊息'), findsOneWidget);
      await tester.tap(find.text('查看原始訊息'));
      await tester.pumpAndSettle();
      expect(find.text('原始訊息'), findsOneWidget);
      expect(find.textContaining('formatted_body'), findsOneWidget);
      expect(find.textContaining('org.matrix.custom.html'), findsOneWidget);
    });

    testWidgets('無 format 欄位 → 既有純文字路徑', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-p:matrix.org', client: client);
      final event = makeEvent(
        room,
        content: {'msgtype': 'm.text', 'body': '純文字'},
        ts: DateTime(2026, 11, 12, 10),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              ChatMessageView(
                sender: '@bob:matrix.org',
                body: '純文字',
                event: event,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('純文字'), findsOneWidget);
    });
  });
}
