// UI 重構（2026-11-01，依人類 LINE_ref 標註）widget 測試（不打網路）：
// * MainShell 底部膠囊 tab 切換（IndexedStack）— 批次 G 膠囊列（Element X 式）。
//   第二十五批（人類拍板「是」）：底列 4→3（設定 tab 移除）——設定功能改由
//   首頁左上頭像面板承載（內嵌 SettingsBody）。
// * 首頁頭像面板：內嵌設定本體（裝置管理／金鑰備份／登出）。
// * 首頁 Spaces 已移除；Space 歸聯絡人「群組」。
// * 表情面板：開啟＋插入 emoji 到輸入框
// * mic 為 disabled / 輸入文字後送出鈕出現
// * 日期分隔標籤（time_format.dart 純函式）
// * 捲動列表後顯示「滑到底部」鈕
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
// CallOptions 未由 matrix barrel 匯出 → 測試離線構造 CallSession 用 src 路徑
// （同批次 E TimelineChunk 模式；正式程式不用）。
import 'package:matrix/src/voip/models/call_options.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/main.dart' show RingApp, ringFontFamily, ringTextScale, ringTheme, ringThemeMode, ringUseDynamicColor;
import 'package:homing/ui/chat_screen.dart';
import 'package:homing/ui/main_shell.dart';
import 'package:homing/ui/notification_settings_screen.dart' show ringIncomingCallBanner;
import 'package:homing/ui/time_format.dart';
import 'package:homing/voip/call_manager.dart';
import 'package:homing/voip/ring_delegate.dart';

class _FakeSpaceRoom extends Room {
  _FakeSpaceRoom({required super.client, required super.id});
  @override
  bool get isSpace => true;
}

void main() {
  group('MainShell', () {
    testWidgets('底部 3 tab 切換（IndexedStack index 變化；設定 tab 已移除）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      // 第三十五批 #1 響應式：widget 測試預設視窗 800×600 已落入 ≥600dp
      // 側欄分支；受測對象是 compact 膠囊列，故明示 compact 尺寸。
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(500, 900)),
            child: MainShell(
              client: client,
              loadRooms: (_) async => [room],
              loadContacts: (_) async => [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      IndexedStack stackOf(WidgetTester t) =>
          t.widget<IndexedStack>(find.byType(IndexedStack).first);

      // 預設停在聊天 tab；對話列表列出房間。
      expect(stackOf(tester).index, 0);
      expect(find.text('!room-a:matrix.org'), findsOneWidget);

      // 批次 H（人類實機回饋）：膠囊可見＋文字標籤有畫出來。
      // 第二十五批：底列 4→3（設定移除；人類拍板「是」）。
      // 第六十一批重設計：各 tab 另有頁面大標題（IndexedStack 會掛載全部
      // 子頁 → 標題與膠囊標籤同名會同時存在）→ 以 Tooltip 訊息精準斷言
      // 膠囊列標籤（每個 tab 恰一個 Tooltip）。
      expect(find.byTooltip('聊天室'), findsOneWidget);
      expect(find.byTooltip('聯絡人'), findsOneWidget);
      expect(find.byTooltip('通話'), findsOneWidget);
      expect(find.byTooltip('設定'), findsNothing);

      // 切到聯絡人（byTooltip → 膠囊列 tab）。
      await tester.tap(find.byTooltip('聯絡人'));
      await tester.pumpAndSettle();
      expect(stackOf(tester).index, 1);
      // 第二十一批：好友 tab（預設）空文案照稿。
      expect(find.text('加個好友吧！'), findsOneWidget);

      // 批次 G：通話 tab（index 2）為空骨架。
      await tester.tap(find.byTooltip('通話'));
      await tester.pumpAndSettle();
      expect(stackOf(tester).index, 2);
      expect(find.text('尚無通話紀錄'), findsOneWidget);
    });

    testWidgets('第二十五批：首頁左上頭像 → 面板內嵌設定本體（裝置管理／金鑰備份／登出）',
        (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      // 單一 pump 期注入 onLogout（同 root widget 重 pump 會沿用 Element tree，
      // 先前開著的面板 route 不會關閉，會干擾第二次開啟）。
      var logoutCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            client: client,
            loadRooms: (_) async => [room],
            loadContacts: (_) async => [],
            onLogout: (c) async {
              logoutCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 點 AppBar 左上頭像 → 帳號面板（bottom sheet 內嵌 SettingsBody）。
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(CircleAvatar),
        ).first,
      );
      await tester.pumpAndSettle();

      // 設定本體（原設定頁分區；人類拍板「設定功能整合到首頁左上頭像」）。
      expect(find.text('個人名稱（未設定）'), findsOneWidget); // Profile 區
      // 批次 III-b／第六十九批：Profile 區與新增的「已讀與訊息」分區佔面值，
      // 「裝置管理」「金鑰備份診斷與還原」須捲動後才建構（懶 ListView）。
      expect(find.text('資料匯出'), findsNothing);
      for (var i = 0; i < 14 && find.text('裝置管理').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(find.text('裝置管理'), findsOneWidget);
      expect(find.text('金鑰備份診斷與還原'), findsOneWidget);

      // 第四十二批：新增「封鎖與隱私」分區（列表中間 → 捲到才建構）。
      for (var i = 0; i < 14 && find.text('隱藏的聊天室').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(find.text('封鎖名單'), findsOneWidget);
      expect(find.text('隱藏的聊天室'), findsOneWidget);
      // 面板清單（最上層 ListView）捲到底 → 資料匯出／登出建構出來。
      for (var i = 0; i < 14 && find.text('登出').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(find.text('登出'), findsOneWidget);
      expect(find.text('資料匯出'), findsOneWidget);

      // 點「登出」→ 確認對話框 → 確認後呼叫注入的 onLogout（經 RoomsScreen
      // 傳入面板；SettingsBody 同鏈路）。
      await tester.ensureVisible(find.text('登出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登出'));
      await tester.pumpAndSettle();
      expect(find.text('確定要登出此裝置？'), findsOneWidget);
      // 對話框裡也有一個「登出」→ 取 overlay 內最後那個（晚於 ListTile）。
      await tester.tap(find.text('登出').last);
      await tester.pumpAndSettle();
      expect(logoutCalled, isTrue);
    });

    testWidgets('批次 G：頂列「＋」→ 三項合一 sheet（建立／加入公開／好友QR）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            client: client,
            loadRooms: (_) async => [room],
            loadContacts: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('新增'));
      await tester.pumpAndSettle();
      // 第二十五批：sheet 搬入共用 room_actions（三項照舊）。
      expect(find.text('建立聊天室'), findsOneWidget);
      expect(find.text('加入公開聊天室'), findsOneWidget);
      expect(find.text('加入好友（Matrix ID／QR）'), findsOneWidget);

      // 點 sheet 外（modal barrier）→ 關閉，不觸發任何方法（不打網路）。
      await tester.tapAt(const Offset(400, 80));
      await tester.pumpAndSettle();
      expect(find.text('建立聊天室'), findsNothing);
    });

    testWidgets('第二十五批／2026-11-20 覆核：首頁不顯示 Spaces；Space 回群組（點開 Space 清單）',
        (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      final space = _FakeSpaceRoom(client: client, id: '!space-a:matrix.org');
      // 第三十五批 #1 響應式：明示 compact 尺寸（膠囊列路徑），見上組說明。
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(500, 900)),
            child: MainShell(
              client: client,
              loadRooms: (_) async => [room, space],
              loadContacts: (_) async => [room, space],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 首頁：Spaces 收合區塊已移除；Space 不出現在主列表。
      expect(find.text('Spaces（1）'), findsNothing);
      expect(find.text('!space-a:matrix.org'), findsNothing);

      // 聯絡人：2026-11-20（人類指示）Space 回「群組」，第四 tab 撤銷。
      // 測試環境無 state：room-a 非 direct chat 亦判不出公開 → 與 Space
      // 一併落「群組」，共 2 條 → 標籤「群組 (2)」。
      await tester.tap(find.byTooltip('聯絡人'));
      await tester.pumpAndSettle();
      expect(find.text('群組 (2)'), findsOneWidget);
      await tester.tap(find.text('群組 (2)'));
      await tester.pumpAndSettle();

      // 點 Space tile → Space 底下聊天室清單（官方 getSpaceHierarchy；
      // 測試環境 fail-open → 空清單文案）。
      await tester.tap(find.text('!space-a:matrix.org'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Space 底下的聊天室'), findsOneWidget);
    });

    testWidgets('第三十五批 #1：≥600dp＝NavigationRail 側欄、<600dp＝膠囊列（DESIGN.md §1）',
        (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      Future<void> pump(Size size) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size),
              child: MainShell(
                client: client,
                loadRooms: (_) async => [room],
                loadContacts: (_) async => [],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // compact：無 Rail；膠囊列 tab（Tooltip）可用。
      await pump(const Size(500, 900));
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byTooltip('聯絡人'), findsOneWidget);

      // wide（600dp 邊界值）：Rail 出現、膠囊列退場；點 rail destination 切 tab。
      await pump(const Size(600, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byTooltip('聯絡人'), findsNothing);
      // 第六十八批 a：Rail 圖示改自繪 LineIconWidget → 以 destination 標籤點選。
      await tester.tap(find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('聯絡人'),
      ));
      await tester.pumpAndSettle();
      final IndexedStack stack =
          tester.widget<IndexedStack>(find.byType(IndexedStack).first);
      expect(stack.index, 1);
    });
  });

  group('第三十四批：來電側邊橫幅（人類需求 #2）', () {
    testWidgets('來電時橫幅出現；通話結束自動消失；偏好關閉時不顯示', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      final manager = CallManager(client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            client: client,
            loadRooms: (_) async => [room],
            loadContacts: (_) async => [],
            // 注入 manager（不自建 → 不 ensureInit，不碰 WebRTC 平台層）。
            callManager: manager,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('來電'), findsNothing);

      // 官方 CallSession 離線構造（CallOptions 未由 barrel 匯出 → src 路徑）。
      final voip = VoIP(client, RingWebRTCDelegate());
      final session = CallSession(
        CallOptions(
          callId: 'c1',
          type: CallType.kVoice,
          dir: CallDirection.kIncoming,
          localPartyId: 'dev1',
          voip: voip,
          room: room,
          iceServers: const [],
        ),
      );
      manager.incomingCall.value = session;
      await tester.pumpAndSettle();

      expect(find.text('來電'), findsOneWidget); // 橫幅標題（文案草案）
      expect(find.text('接聽'), findsOneWidget);
      expect(find.text('拒接'), findsOneWidget);

      // 通話結束（notifier 清空）→ 橫幅自動移除（host 兩者皆空 → dismiss）。
      manager.incomingCall.value = null;
      await tester.pumpAndSettle();
      expect(find.text('來電'), findsNothing);

      // 偏好關閉（人類需求「可選擇是否隱藏」）→ 不顯示橫幅。
      ringIncomingCallBanner.value = false;
      manager.incomingCall.value = session;
      await tester.pumpAndSettle();
      expect(find.text('來電'), findsNothing);

      // 還原（不影響其他測試；通知欄提示路徑的 native 行為屬實機驗證）。
      manager.incomingCall.value = null;
      await tester.pumpAndSettle();
      ringIncomingCallBanner.value = true;
    });
  });

  group('RingApp 外觀執行緒（批次 H）', () {
    test('ringTheme 純函式：fontFamily 有帶入 ThemeData', () {
      final withFont = ringTheme(
        Brightness.light,
        seedColor: const Color(0xFFFFBD9F),
        fontFamily: 'ringCustom',
      );
      // 本 Flutter 版本的 ThemeData 無 fontFamily getter（僅建構參數，
      // 套用進 textTheme）→ 由 textTheme 讀回驗證。
      expect(withFont.textTheme.bodyLarge!.fontFamily, 'ringCustom');
      final defaultFont = ringTheme(
        Brightness.light,
        seedColor: const Color(0xFFFFBD9F),
      );
      expect(defaultFont.textTheme.bodyLarge!.fontFamily, isNot('ringCustom'));
    });

    testWidgets('外觀 notifier 變動 → MaterialApp 主題即時重建', (tester) async {
      addTearDown(() {
        ringFontFamily.value = null;
        ringUseDynamicColor.value = false;
      });
      ringFontFamily.value = null;
      ringUseDynamicColor.value = false;

      await tester.pumpWidget(RingApp(vodozemacReady: true, seedColorHex: null));
      await tester.pump();

      ThemeData themeOf() => Theme.of(tester.element(find.byType(Navigator).first));
      String? fontFamilyOf() => themeOf().textTheme.bodyLarge!.fontFamily;
      expect(fontFamilyOf(), isNot('ringCustom'));

      // 字型即時生效（人類批准「導入即生效」）。
      // 注意：MaterialApp 內建 AnimatedTheme 有 200ms 過渡 → 需 settle 到底。
      ringFontFamily.value = 'ringCustom';
      await tester.pumpAndSettle();
      expect(fontFamilyOf(), 'ringCustom');

      // 動態取色開關：測試環境無平台桌布色 → 維持種子色分支（真機動態色
      // 效果屬實機驗證）。
      ringUseDynamicColor.value = true;
      await tester.pumpAndSettle();
      expect(fontFamilyOf(), 'ringCustom'); // 不重置字型
    });
    testWidgets('批次 I①：文字大小與深淺模式 notifier 即時更新', (tester) async {
      addTearDown(() {
        ringTextScale.value = 1.0;
        ringThemeMode.value = ThemeMode.system;
      });
      ringTextScale.value = 1.0;
      ringThemeMode.value = ThemeMode.system;
      await tester.pumpWidget(RingApp(vodozemacReady: true, seedColorHex: null));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
      expect(app.themeMode, ThemeMode.system);
      final mq = MediaQuery.of(tester.element(find.byType(Navigator).first));
      expect(mq.textScaler.scale(10), closeTo(10.0, 0.001));

      ringTextScale.value = 1.3;
      ringThemeMode.value = ThemeMode.dark;
      await tester.pumpAndSettle();
      final app2 = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
      expect(app2.themeMode, ThemeMode.dark);
      final mq2 = MediaQuery.of(tester.element(find.byType(Navigator).first));
      expect(mq2.textScaler.scale(10), closeTo(13.0, 0.001));
    });
  });

  group('ChatScreen（UI 重構）', () {
    ChatMessageView msg(String body, DateTime at) => ChatMessageView(
          sender: '@someone:matrix.org',
          body: body,
          sentAt: at,
        );

    testWidgets('mic 為 disabled；輸入文字後送出鈕出現且可按', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      final sent = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [],
            sendMessage: (_, text) async => sent.add(text),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 第七十批 e：無文字 → mic 可按（開語音錄音面板；無障礙 tooltip 保留）。
      expect(find.byIcon(Icons.send), findsNothing);
      final mic = find.byIcon(Icons.mic_none);
      expect(mic, findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: mic, matching: find.byType(IconButton)).first,
            )
            .onPressed,
        isNotNull,
      );

      // 輸入文字 → 送出鈕出現且啟用。
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      final send = find.byIcon(Icons.send);
      expect(send, findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: send, matching: find.byType(IconButton)).first,
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(sent, ['hi']);
    });

    testWidgets('批次 G：輸入列單一「＋」→ 選單三項（相機／照片／檔案）', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [],
            sendMessage: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2026-11-20：相機／相簿已移到輸入列（面板外），閉合時即可見；
      // 「＋」面板內只剩 Files／聯絡／位置。
      expect(find.byTooltip('新增附件'), findsOneWidget);
      expect(find.byTooltip('相機'), findsOneWidget);
      expect(find.byTooltip('相簿'), findsOneWidget);
      expect(find.text('檔案'), findsNothing);

      await tester.tap(find.byTooltip('新增附件'));
      await tester.pumpAndSettle();
      expect(find.text('檔案'), findsOneWidget);

      // 不實際點選項（file picker／相機權限屬裝置行為）；點「×」收起面板。
      // 2026-11-20：相機／相簿在面板外，收起後仍可見；只檢查面板選項消失。
      await tester.tap(find.byTooltip('關閉附件面板'));
      await tester.pumpAndSettle();
      expect(find.text('檔案'), findsNothing);
      expect(find.byTooltip('相機'), findsOneWidget);
    });

    testWidgets('表情面板：開啟後插入 emoji 到輸入框', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byIcon(Icons.emoji_emotions_outlined);
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // 面板開啟：表情 tab 出現（貼圖 tab 為骨架殼）。
      expect(find.text('表情'), findsOneWidget);
      expect(find.text('貼圖'), findsOneWidget);

      // 插入 emoji：網格第一個（IconButton 的 tooltip／child 文字）。
      await tester.tap(find.text('😀'));
      await tester.pumpAndSettle();
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.text, '😀');
    });

    testWidgets('日期分隔：跨日訊息插入「昨天→今天」樣式的分隔標籤', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);

      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      final mm = twoDaysAgo.month.toString().padLeft(2, '0');
      final dd = twoDaysAgo.day.toString().padLeft(2, '0');

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async =>
                [msg('舊訊息', twoDaysAgo), msg('新訊息', now)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('今天'), findsOneWidget);
      // twoDaysAgo → 今年其他日 → MM/DD（time_format.dart 純函式）。
      expect(find.text('$mm/$dd'), findsOneWidget);
      expect(daySeparatorLabel(twoDaysAgo), '$mm/$dd');
      expect(daySeparatorLabel(now), '今天');
    });

    testWidgets('捲動列表後出現「滑到底部」鈕', (tester) async {
      final client = createClient();
      final room = Room(id: '!room-a:matrix.org', client: client);
      final now = DateTime.now();

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            room: room,
            loadMessages: (_) async => [
              for (var i = 0; i < 30; i++)
                msg('訊息 $i', now.subtract(Duration(seconds: 30 - i))),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 起始在底部：無按鈕。
      expect(find.byIcon(Icons.arrow_downward), findsNothing);

      // 2026-11-03 重構：ListView(reverse: true)（官方聊天室標準做法，
      // offset 0＝最新）——視覺上「下拉看舊訊息」＝ Offset(0, 200)
      //（reverse 軸向：offset 離 0 越遠＝越舊）。
      await tester.drag(find.byType(ListView), const Offset(0, 200));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      // 點按鈕 → 回到底部（offset 0）→ 按鈕消失。
      await tester.tap(find.byIcon(Icons.arrow_downward));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });
  });
}
