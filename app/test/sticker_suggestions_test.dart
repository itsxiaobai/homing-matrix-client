// 貼圖關鍵字聯想（backlog #8；人類 2026-11-03 目標 #8）— 純邏輯單元測試。
// 不碰 Flutter／DB／網路：僅驗證 `sticker_suggestions.dart` 的比對與排序。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/sticker_suggestions.dart';

const _library = <StickerLibraryEntry>[
  StickerLibraryEntry(id: 1, path: '/tmp/cat_happy.png', name: 'cat_happy.png'),
  StickerLibraryEntry(id: 2, path: '/tmp/cat_sad.png', name: 'cat_sad.png'),
  StickerLibraryEntry(id: 3, path: '/tmp/dog.png', name: 'dog.png'),
  StickerLibraryEntry(id: 4, path: '/tmp/貓咪開心.png', name: '貓咪開心.png'),
];

void main() {
  group('suggestStickers', () {
    test('①空白輸入 → 不建議', () {
      expect(suggestStickers(text: '', library: _library), isEmpty);
      expect(suggestStickers(text: '   ', library: _library), isEmpty);
    });

    test('②純 ASCII 單字元 → 不建議（避免雜訊）', () {
      expect(suggestStickers(text: 'c', library: _library), isEmpty);
    });

    test('③token 開頭符合 → 建議該貼圖', () {
      final r = suggestStickers(text: 'ha', library: _library);
      expect(r.length, 1);
      expect(r.first.entry.id, 1); // cat_happy
      expect(r.first.entry.name, 'cat_happy.png');
    });

    test('④整串包含 → 建議且分數高於 token 開頭符合', () {
      final r = suggestStickers(text: 'cat', library: _library);
      expect(r.map((e) => e.entry.id), containsAll(<int>[1, 2]));
      // "cat" 同時是 cat_happy／cat_sad 的 token 前綴與 stem 子字串，
      // 分數相同時依名稱排序（cat_happy 在前）。
      expect(r.first.entry.id, 1);
    });

    test('⑤中文子字串比對（不需分詞）', () {
      final r = suggestStickers(text: '開心', library: _library);
      expect(r.length, 1);
      expect(r.first.entry.id, 4);
    });

    test('⑥無關字詞 → 不建議', () {
      expect(suggestStickers(text: 'zzz', library: _library), isEmpty);
    });

    test('⑦結果上限（limit）', () {
      final r = suggestStickers(text: 'c', library: _library, limit: 0);
      expect(r, isEmpty);
      final r2 = suggestStickers(text: 'cat', library: _library, limit: 1);
      expect(r2.length, 1);
    });

    test('⑧無名稱（name 為 null）→ 不建議、不爆', () {
      const lib = <StickerLibraryEntry>[
        StickerLibraryEntry(id: 9, path: '/tmp/x.png'),
      ];
      expect(suggestStickers(text: 'x', library: lib), isEmpty);
    });
  });

  group('stickerKeywords / stickerStem', () {
    test('①副檔名去除＋token 切分', () {
      expect(stickerStem('cat_happy.png'), 'cat_happy');
      expect(stickerKeywords('cat_happy.png'), <String>['cat', 'happy']);
      expect(stickerKeywords('貓咪開心.png'), <String>['貓咪開心']);
      expect(stickerKeywords(null), isEmpty);
    });
  });
}
