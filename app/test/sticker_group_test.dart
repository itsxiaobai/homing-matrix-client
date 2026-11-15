// 第四十六批：貼圖依 pack 分組（`groupStickersByPack`）——單元測試。
//
// 規則：
// - 有 `packId` 者 → 同一 pack 成一組，組內順序＝原順序。
// - 無 `packId` 者（相簿單張匯入）→ 各自成一組（「單張貼圖」）。
// - 組順序＝各組第一個貼圖在原清單中的位置（不重排跨組順序）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/sticker_suggestions.dart';
import 'package:homing/ui/sticker_manager_screen.dart';

StickerLibraryEntry entry(int id, {String? packId}) => StickerLibraryEntry(
      id: id,
      path: '/tmp/sticker-$id.png',
      name: 'sticker-$id.png',
      packId: packId,
    );

void main() {
  group('groupStickersByPack', () {
    test('同一 pack 的貼圖合成一組，組內順序保持原順序', () {
      final groups = groupStickersByPack([
        entry(1, packId: 'pack-a'),
        entry(2, packId: 'pack-a'),
        entry(3, packId: 'pack-b'),
      ]);

      expect(groups.length, 2);
      expect(groups[0].packId, 'pack-a');
      expect(groups[0].entries.map((e) => e.id).toList(), [1, 2]);
      expect(groups[1].packId, 'pack-b');
      expect(groups[1].entries.map((e) => e.id).toList(), [3]);
    });

    test('無 packId 者各自成組（單張貼圖）', () {
      final groups = groupStickersByPack([
        entry(1),
        entry(2),
      ]);

      expect(groups.length, 2);
      expect(groups.every((g) => g.packId == null), isTrue);
      expect(groups.every((g) => g.title == '單張貼圖'), isTrue);
    });

    test('空清單 → 空結果', () {
      expect(groupStickersByPack(const []), isEmpty);
    });

    test('同一 pack 不連續出現 → 仍合併為同一組（依首次出現位置）', () {
      final groups = groupStickersByPack([
        entry(1, packId: 'pack-a'),
        entry(2, packId: 'pack-b'),
        entry(3, packId: 'pack-a'),
      ]);

      expect(groups.length, 2);
      expect(groups[0].packId, 'pack-a');
      expect(groups[0].entries.map((e) => e.id).toList(), [1, 3]);
      expect(groups[1].packId, 'pack-b');
    });
  });
}
