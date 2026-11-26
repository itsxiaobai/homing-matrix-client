// 基本煙霧測試（原為 flutter create 的 counter demo 測試；
// 批次 I②：登入頁整合伺服器選擇＋帳密，主流程直接進 LoginScreen）。
// 第三十四批：預設收合自訂伺服器選項（人類需求 #7）——homeserver 欄位
// 改為點「如果有自己的伺服器，請按這裡！」後展開。
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/main.dart';

void main() {
  testWidgets('RingApp 顯示登入骨架畫面', (WidgetTester tester) async {
    await tester.pumpWidget(const RingApp(vodozemacReady: false));

    // 第一百零五批：Element X 式歡迎頁（Homing 自己的品牌，不抄 Element）。
    expect(find.text('Homing'), findsOneWidget);
    expect(find.text('使用 QR 碼登入'), findsOneWidget);
    expect(find.text('手動登入'), findsOneWidget);
    expect(find.text('建立帳號'), findsOneWidget);
    expect(find.text('版本 1.1.9+2102'), findsOneWidget);

    // 進手動登入 → 收合預設：Homing（預設）＋展開連結；欄位隱藏。
    await tester.tap(find.text('手動登入'));
    await tester.pumpAndSettle();
    expect(find.text('登入'), findsWidgets);
    expect(find.text('Homing（預設）'), findsOneWidget);
    expect(find.text('如果有自己的伺服器，請按這裡！'), findsOneWidget);
    expect(find.text('Homeserver 位址'), findsNothing);
    expect(find.text('前往網頁註冊'), findsOneWidget);

    // 點連結 → 展開自訂伺服器欄位。
    await tester.tap(find.text('如果有自己的伺服器，請按這裡！'));
    await tester.pumpAndSettle();
    expect(find.text('Homeserver 位址'), findsOneWidget);
  });
}
