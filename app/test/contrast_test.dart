// 第四十九批：對比度量測（WCAG 2.1）——單元測試。
//
// 對照 WCAG 2.1 的標準範例值：
// - 黑 on 白 ＝ 21:1
// - 白 on 黑 ＝ 21:1
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/contrast.dart';

void main() {
  group('相對亮度與對比比', () {
    test('黑 on 白 ＝ 21:1；白 on 黑 ＝ 21:1', () {
      const black = Rgb8(0, 0, 0);
      const white = Rgb8(255, 255, 255);
      expect(contrastRatio(black, white), closeTo(21.0, 0.01));
      expect(contrastRatio(white, black), closeTo(21.0, 0.01));
      expect(relativeLuminance(black), closeTo(0.0, 0.001));
      expect(relativeLuminance(white), closeTo(1.0, 0.001));
    });

    test('同色 ＝ 1:1', () {
      const c = Rgb8(0x80, 0x80, 0x80);
      expect(contrastRatio(c, c), closeTo(1.0, 0.001));
    });

    test('對比值與前景背景順序無關', () {
      const a = Rgb8(0x28, 0x28, 0x28);
      const b = Rgb8(0xFF, 0xBD, 0x9F);
      expect(
        contrastRatio(a, b),
        closeTo(contrastRatio(b, a), 0.0001),
      );
    });

    test('fromHex 解析 0xFFRRGGBB', () {
      const c = Rgb8.fromHex(0xFFE8384F);
      expect(c.r, 0xE8);
      expect(c.g, 0x38);
      expect(c.b, 0x4F);
      expect(c.toString(), '#e8384f');
    });
  });

  group('等級判定', () {
    test('門檻：AA ≥ 4.5、AAA ≥ 7.0', () {
      expect(wcagLevel(7.0), WcagLevel.aaa);
      expect(wcagLevel(6.9), WcagLevel.aa);
      expect(wcagLevel(4.5), WcagLevel.aa);
      expect(wcagLevel(4.49), WcagLevel.fail);
      expect(wcagLevel(3.0), WcagLevel.fail);
    });

    test('ContrastCheck 輸出與 passesAa', () {
      final check = ContrastCheck(
        name: '測試',
        foreground: const Rgb8(0, 0, 0),
        background: const Rgb8(255, 255, 255),
        ratio: 21.0,
      );
      expect(check.level, WcagLevel.aaa);
      expect(check.passesAa, isTrue);
      expect(check.toString(), contains('21.00:1'));
    });
  });

  group('Homing 實際配色（第四十九批量測結果）', () {
    test('主文字 on 頁面底 ＝ AAA', () {
      final ratio = contrastRatio(
        const Rgb8.fromHex(0xFF282828),
        const Rgb8.fromHex(0xFFFFFFFF),
      );
      expect(wcagLevel(ratio), WcagLevel.aaa);
    });

    test('次要文字 on 頁面底 ＝ 3.95:1（**未達 AA**，待人類決策）', () {
      final ratio = contrastRatio(
        const Rgb8.fromHex(0xFF808080),
        const Rgb8.fromHex(0xFFFFFFFF),
      );
      expect(ratio, closeTo(3.95, 0.05));
      // 本測試**鎖住實測值**（供日後追蹤），但明確標示未達 AA。
      expect(wcagLevel(ratio), WcagLevel.fail);
    });

    test('白字 on 緊急紅 ＝ 4.11:1（**未達 AA**，待人類決策）', () {
      final ratio = contrastRatio(
        const Rgb8.fromHex(0xFFFFFFFF),
        const Rgb8.fromHex(0xFFE8384F),
      );
      expect(ratio, closeTo(4.11, 0.05));
      expect(wcagLevel(ratio), WcagLevel.fail);
    });
  });
}
