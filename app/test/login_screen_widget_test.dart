// 任務：Phase 1 / 1.3 — LoginScreen 骨架 widget 測試（全部注入假動作，不打網路）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/auth.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/login_screen.dart';

void main() {
  final homeserver = Uri.parse('https://matrix.org');
  late Client bareClient;

  setUp(() {
    bareClient = createClient(); // 不落地；僅提供 Client 物件供回呼
  });

  Widget buildScreen({
    PasswordLoginStub? login,
    RegistrationPageResolver? resolver,
    UrlOpener? opener,
    void Function(Client)? onLoggedIn,
    Future<String?> Function(Uri homeserver)? checkServer,
  }) =>
      MaterialApp(
        home: LoginScreen(
          homeserver: homeserver,
          login: login,
          checkServer: checkServer ?? (_) async => null,
          onLoggedIn: onLoggedIn,
          resolveRegistrationPage: resolver,
          openUrl: opener,
        ),
      );

  testWidgets('顯示 homeserver 與登入欄位', (tester) async {
    await tester.pumpWidget(buildScreen());
    // 第三十四批：預設收合——只顯示 matrix.org（預設）＋自訂伺服器連結。
    expect(find.text('matrix.org（預設）'), findsOneWidget);
    expect(find.text('如果有自己的伺服器，請按這裡！'), findsOneWidget);
    expect(find.text('登入'), findsWidgets);
    expect(find.text('前往網頁註冊'), findsOneWidget);
    // 收合時僅帳號／密碼兩個 TextField（homeserver 欄位已收起）。
    expect(find.byType(TextField), findsNWidgets(2));

    // 點連結 → 展開伺服器選項（homeserver 欄位與目前位址出現）。
    await tester.tap(find.text('如果有自己的伺服器，請按這裡！'));
    await tester.pumpAndSettle();
    expect(find.text('Homeserver 位址'), findsOneWidget);
    expect(find.text('伺服器：https://matrix.org'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('空白帳密顯示提示且不呼叫登入', (tester) async {
    var called = false;
    await tester.pumpWidget(
      buildScreen(
        login: ({
          required homeserver,
          required user,
          required password,
        }) async {
          called = true;
          return bareClient;
        },
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pump();

    expect(find.text('請輸入帳號與密碼'), findsOneWidget);
    expect(called, isFalse);
  });

  testWidgets('登入成功時以正規化帳號呼叫並回呼持久流程', (tester) async {
    String? seenUser;
    String? seenPassword;
    Uri? seenHomeserver;
    Client? seenClient;
    await tester.pumpWidget(
      buildScreen(
        onLoggedIn: (client) => seenClient = client,
        login: ({
          required homeserver,
          required user,
          required password,
        }) async {
          seenHomeserver = homeserver;
          seenUser = user;
          seenPassword = password;
          return bareClient;
        },
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    // ignore: avoid_print
    print('DEBUG count=${find.widgetWithText(TextButton, '登入').evaluate().length}');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();

    expect(seenHomeserver, homeserver);
    expect(seenUser, '@alice:matrix.org');
    expect(seenPassword, 'secret');
    expect(seenClient, same(bareClient));
  });

  testWidgets('登入成功且未提供 onLoggedIn 時顯示提示', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        login: ({
          required homeserver,
          required user,
          required password,
        }) async => bareClient,
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    // ignore: avoid_print
    print('DEBUG count=${find.widgetWithText(TextButton, '登入').evaluate().length}');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已登入'), findsOneWidget);
  });

  testWidgets('M_FORBIDDEN 顯示帳號或密碼錯誤', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        login: ({
          required homeserver,
          required user,
          required password,
        }) async {
          throw MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Invalid password',
          });
        },
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();

    expect(find.text('帳號或密碼錯誤'), findsOneWidget);
  });

  testWidgets('網路錯誤顯示無法連線', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        login: ({
          required homeserver,
          required user,
          required password,
        }) async {
          throw Exception('network down');
        },
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    // ignore: avoid_print
    print('DEBUG count=${find.widgetWithText(TextButton, '登入').evaluate().length}');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();

    expect(find.text('無法連線：請檢查網路或稍後再試'), findsOneWidget);
  });

  testWidgets('前往網頁註冊：解析到 URL 時交給 opener', (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      buildScreen(
        resolver: (_) async => Uri.parse('https://account.matrix.org/register'),
        opener: (url) async {
          opened = url;
          return true;
        },
      ),
    );

    await tester.tap(find.text('前往網頁註冊'));
    await tester.pumpAndSettle();
    // Suggestion #3：開啟前有保管提醒 dialog → 確認後才交給 opener。
    await tester.tap(find.text('我記住了，開始註冊'));
    await tester.pumpAndSettle();

    expect(opened?.toString(), 'https://account.matrix.org/register');
    expect(find.textContaining('無法開啟'), findsNothing);
  });

  testWidgets('前往網頁註冊：無註冊頁資訊時顯示說明', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        resolver: (_) async => null,
        opener: (url) async => true,
      ),
    );

    await tester.tap(find.text('前往網頁註冊'));
    await tester.pumpAndSettle();
    // Suggestion #3：開啟前有保管提醒 dialog → 確認後才交給 opener。
    await tester.tap(find.text('我記住了，開始註冊'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未提供網頁註冊資訊'), findsOneWidget);
  });

  testWidgets('前往網頁註冊：瀏覽器開啟失敗時提供網址', (tester) async {
    await tester.pumpWidget(
      buildScreen(
        resolver: (_) async => Uri.parse('https://account.matrix.org/register'),
        opener: (url) async => false,
      ),
    );

    await tester.tap(find.text('前往網頁註冊'));
    await tester.pumpAndSettle();
    // Suggestion #3：開啟前有保管提醒 dialog → 確認後才交給 opener。
    await tester.tap(find.text('我記住了，開始註冊'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('https://account.matrix.org/register'),
      findsWidgets,
    );
    expect(find.textContaining('無法開啟瀏覽器'), findsOneWidget);
  });

  testWidgets('批次 I②：一站式送出先測後登入（失敗則不呼叫登入）', (tester) async {
    final order = <String>[];
    await tester.pumpWidget(
      buildScreen(
        login: ({required homeserver, required user, required password}) async {
          order.add('login');
          return bareClient;
        },
        checkServer: (hs) async {
          order.add('check');
          return null;
        },
        onLoggedIn: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();
    expect(order, <String>['check', 'login']);

    var called = false;
    await tester.pumpWidget(
      buildScreen(
        login: ({required homeserver, required user, required password}) async {
          called = true;
          return bareClient;
        },
        checkServer: (hs) async => 'boom',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('連線測試失敗'), findsOneWidget);
    expect(called, isFalse);
  });

  testWidgets('第三十四批：收合預設＝登入直接使用 matrix.org', (tester) async {
    Uri? seenHomeserver;
    await tester.pumpWidget(
      buildScreen(
        login: ({required homeserver, required user, required password}) async {
          seenHomeserver = homeserver;
          return bareClient;
        },
        onLoggedIn: (_) {},
      ),
    );
    // 不點開自訂伺服器選項——直接填帳密送出。
    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();
    expect(seenHomeserver, homeserver); // matrix.org（預設）
  });

  testWidgets('第三十四批：展開自訂伺服器後，登入使用輸入的 homeserver', (tester) async {
    Uri? seenHomeserver;
    await tester.pumpWidget(
      buildScreen(
        checkServer: (_) async => null,
        login: ({required homeserver, required user, required password}) async {
          seenHomeserver = homeserver;
          return bareClient;
        },
        onLoggedIn: (_) {},
      ),
    );
    await tester.tap(find.text('如果有自己的伺服器，請按這裡！'));
    await tester.pumpAndSettle();
    // 展開後 TextField：0＝homeserver、1＝帳號、2＝密碼。
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://example.org',
    );
    await tester.enterText(find.byType(TextField).at(1), 'alice');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    await tester.tap(find.widgetWithText(TextButton, '登入'));
    await tester.pumpAndSettle();
    expect(seenHomeserver, Uri.parse('https://example.org'));
  });
}

/// 測試用別名，避免與 lib 的 typedef 名稱在測試中混淆。
typedef PasswordLoginStub = Future<Client> Function({
  required Uri homeserver,
  required String user,
  required String password,
});
