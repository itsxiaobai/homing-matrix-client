// 聊天室版面尺寸（LINE 版位慣例）——第四十一批的單元測試。
// 純函式：不依賴 Flutter widget，可於測試環境直接驗證。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/chat_layout.dart';

void main() {
  group('maxBubbleWidth', () {
    test('①文字泡泡最大寬度＝視窗寬 × 0.68（2026-11-15 收窄）', () {
      expect(maxBubbleWidth(400, kTextBubbleWidthFactor), closeTo(272, 0.01));
    });

    test('②圖片最大寬度＝視窗寬 × 0.55（不滿版；2026-11-15 收窄）', () {
      expect(maxBubbleWidth(400, kImageBubbleWidthFactor), closeTo(220, 0.01));
    });

    test('③視窗越寬，寬度越大（不寫死寬度）', () {
      expect(maxBubbleWidth(800, kTextBubbleWidthFactor),
          greaterThan(maxBubbleWidth(400, kTextBubbleWidthFactor)));
    });
  });

  group('stickerDisplaySize', () {
    test('①一般手機視窗 → 取視窗比例（不上限）', () {
      // 400dp 視窗 → 400 × 0.42 = 168dp，但上限 110dp（2026-11-15 收窄）→ 取 110。
      expect(stickerDisplaySize(400), closeTo(110, 0.01));
    });

    test('②小視窗 → 不超過視窗比例（避免貼圖比畫面還大）', () {
      expect(stickerDisplaySize(200), closeTo(84, 0.01));
    });

    test('③平板／桌面視窗 → 仍受上限約束（不過大）', () {
      expect(stickerDisplaySize(1200), closeTo(kStickerMaxSizeDp, 0.01));
    });
  });
}
