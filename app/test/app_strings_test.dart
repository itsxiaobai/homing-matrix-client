// 多語言字串層（第五十七批）單元測試。
//
// 對應實作：`app/lib/l10n/app_strings.dart`（**零新依賴**的自建字串表：
// key ＝ 繁中原文，缺翻譯時自動回落原文）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/l10n/app_strings.dart';

void main() {
  group('AppStrings（第五十七批）', () {
    tearDown(() {
      // 還原預設語言（避免影響同行程其他測試）。
      setAppLocale(AppLocale.zhTW);
    });

    test('預設語言為繁中 → 原樣回傳', () {
      expect(currentAppLocale, AppLocale.zhTW);
      expect(S.t('設定'), '設定');
    });

    test('切英文 → 有翻譯者回英文', () {
      setAppLocale(AppLocale.en);
      expect(currentAppLocale, AppLocale.en);
      expect(S.t('設定'), 'Settings');
      expect(S.t('顯示通知'), 'Show notifications');
    });

    test('切英文 → 查無翻譯者回落繁中原文（不顯示空字串）', () {
      setAppLocale(AppLocale.en);
      expect(S.t('這是尚未翻譯的字串'), '這是尚未翻譯的字串');
    });

    test('切回繁中 → 再次原樣回傳', () {
      setAppLocale(AppLocale.en);
      setAppLocale(AppLocale.zhTW);
      expect(S.t('設定'), '設定');
    });

    // 第一百零七批：i18n 補齊後的新增翻譯。
    test('新增的登入／帳號／歡迎頁 key 都有英文翻譯', () {
      setAppLocale(AppLocale.en);
      expect(S.t('使用 QR 碼登入'), 'Sign in with QR code');
      expect(S.t('手動登入'), 'Sign in manually');
      expect(S.t('建立帳號'), 'Create account');
      expect(S.t('切換帳號'), 'Switch account');
      expect(S.t('新增帳號'), 'Add account');
      expect(S.t('使用單一登入'), 'Sign in with SSO');
      expect(S.t('全域聊天室背景'), 'Global chat background');
      expect(S.t('通話紀錄'), 'Call history');
    });

    test('notifier 會通知變化（供上層重建 → 文字即時更新）', () {
      var notified = 0;
      void listener() => notified++;
      appLocaleNotifier.addListener(listener);
      addTearDown(() => appLocaleNotifier.removeListener(listener));
      setAppLocale(AppLocale.en);
      expect(notified, 1);
      setAppLocale(AppLocale.en); // 同一語言 → 不再通知
      expect(notified, 1);
    });
  });
}
