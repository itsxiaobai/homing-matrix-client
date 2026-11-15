// 貼圖關鍵字（第四十二批；對應人類「一份 json 填貼圖名稱／搜尋關鍵字／檔名」）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/sticker_suggestions.dart';

void main() {
  const entry = StickerLibraryEntry(
    id: 1,
    path: '/tmp/x.png',
    name: '開心的貓',
    keywords: ['happy', '開心'],
  );

  test('①創作者關鍵字優先比對', () {
    final r = suggestStickers(text: 'happ', library: const [entry]);
    expect(r.length, 1);
    expect(r.first.entry.id, 1);
  });

  test('②中文關鍵字可被建議', () {
    final r = suggestStickers(text: '開心', library: const [entry]);
    expect(r.length, 1);
  });

  test('③關鍵字與檔名 token 聯集（皆可命中）', () {
    final named = StickerLibraryEntry(
      id: 2,
      path: '/tmp/y.png',
      name: 'cat_happy',
      keywords: const ['開心'],
    );
    expect(suggestStickers(text: 'cat', library: [named]).length, 1);
    expect(suggestStickers(text: '開心', library: [named]).length, 1);
  });

  test('④不相關字詞不建議', () {
    expect(suggestStickers(text: 'zzz', library: const [entry]), isEmpty);
  });
}
