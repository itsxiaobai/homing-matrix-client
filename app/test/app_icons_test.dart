// 圖示變數化（第五十七批）單元測試。
// 對應：`app/lib/ui/app_icons.dart`（圖示槽位＋主題包覆寫，零新依賴）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/ui/app_icons.dart';
import 'package:homing/ui/app_icons_generated.dart';

void main() {
  setUp(() => clearAppIconOverrides());
  tearDown(() => clearAppIconOverrides());

  group('AppIcons（圖示變數化・第五十七批）', () {
    test('未覆寫時使用 Material 預設', () {
      expect(AppIcons.chat, Icons.chat_bubble_outline);
      expect(AppIcons.call, Icons.call_outlined);
      expect(hasAppIconOverrides, isFalse);
    });

    test('覆寫合法槽位 → 該槽位換圖示，其他不受影響', () {
      setAppIconOverride(AppIconName.chat, Icons.forum);
      expect(AppIcons.chat, Icons.forum);
      expect(AppIcons.call, Icons.call_outlined);
      expect(hasAppIconOverrides, isTrue);
    });

    test('非法槽位 → 忽略', () {
      setAppIconOverride('not_a_slot', Icons.ac_unit);
      expect(hasAppIconOverrides, isFalse);
    });

    test('applyThemeIconOverrides 會先清掉舊覆寫（換主題還原預設）', () {
      setAppIconOverride(AppIconName.call, Icons.phone);
      applyThemeIconOverrides({
        AppIconName.chat: 'chat_bubble',
      });
      expect(AppIcons.chat, Icons.chat_bubble);
      expect(AppIcons.call, Icons.call_outlined, reason: '舊覆寫已清掉');
      applyThemeIconOverrides(const {});
      expect(AppIcons.chat, Icons.chat_bubble_outline);
    });

    test('Material 名稱查表：合法名稱有 IconData，未知名稱 null', () {
      expect(materialIconByName('chat_bubble_outline'), isNotNull);
      expect(materialIconByName('no_such_icon'), isNull);
    });

    test('自訂字型圖示（IconData 帶 fontFamily）', () {
      final icon = fontIcon('themeIcons', 0xe001);
      expect(icon.fontFamily, 'themeIcons');
      expect(icon.codePoint, 0xe001);
    });

    test('全數槽位化（第五十八批「全部替換」）：130 個 Material 圖示皆可查', () {
      expect(kAllMaterialIconByName.length, greaterThanOrEqualTo(130));
      expect(kAllIconSlotNames.length, kAllMaterialIconByName.length);
      expect(AllIcons.chatBubbleOutline, Icons.chat_bubble_outline);
      expect(AllIcons.add, Icons.add);
    });

    test('AllIcons getter 受子題包覆寫影響', () {
      setAppIconOverride('chat_bubble_outline', Icons.forum);
      expect(AllIcons.chatBubbleOutline, Icons.forum);
      expect(AllIcons.add, Icons.add);
    });
  });
}
