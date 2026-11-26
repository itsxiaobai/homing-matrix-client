// 媒體快取（第五十七批・離線可讀方案 A）單元測試。
//
// 對應實作：`app/lib/media_cache.dart`。本檔只測**純邏輯**（LRU 挑選）與
// 鍵值產生；檔案 IO 與 SDK 下載留待實機驗收。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/media_cache.dart';

void main() {
  group('selectEvictions（LRU・第五十七批）', () {
    test('未超過上限 → 不刪任何', () {
      final entries = [
        MediaCacheEntry(key: 'a', size: 100, lastUsed: 1),
        MediaCacheEntry(key: 'b', size: 100, lastUsed: 2),
      ];
      expect(selectEvictions(entries, 1000), isEmpty);
    });

    test('超過上限 → 先刪最久未用', () {
      final entries = [
        MediaCacheEntry(key: 'old', size: 100, lastUsed: 1),
        MediaCacheEntry(key: 'new', size: 100, lastUsed: 5),
      ];
      expect(selectEvictions(entries, 150), ['old']);
    });

    test('需要刪多筆 → 依最舊→最新順序', () {
      final entries = [
        MediaCacheEntry(key: 'a', size: 100, lastUsed: 3),
        MediaCacheEntry(key: 'b', size: 100, lastUsed: 1),
        MediaCacheEntry(key: 'c', size: 100, lastUsed: 2),
      ];
      // 總量 300、上限 150 → 刪掉最舊的 b、c（剩 a = 100）。
      expect(selectEvictions(entries, 150), ['b', 'c']);
    });

    test('空索引 → 不刪', () {
      expect(selectEvictions(const [], 100), isEmpty);
    });
  });

  group('MediaCache.keyFor（第五十七批）', () {
    test('同一 eventId → 同一鍵；縮圖與原圖不同鍵', () {
      final a = MediaCache.keyFor('\$event-1');
      final b = MediaCache.keyFor('\$event-1');
      final thumb = MediaCache.keyFor('\$event-1', thumbnail: true);
      expect(a, b);
      expect(thumb, isNot(a));
    });

    test('不同 eventId → 不同鍵', () {
      expect(
        MediaCache.keyFor('event-1'),
        isNot(MediaCache.keyFor('event-2')),
      );
    });

    test('鍵不含原始 eventId（避免檔名洩漏／非法字元）', () {
      final key = MediaCache.keyFor('\$matrix:example.com:abc!def');
      expect(key.contains('example.com'), isFalse);
      expect(key.contains('!'), isFalse);
    });
  });
}
