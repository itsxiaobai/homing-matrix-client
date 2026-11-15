// 第四十八批：訊息搜尋過濾條件（時間範圍 ＋ 訊息類型）——單元測試。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/ui/search_filters.dart';

void main() {
  final now = DateTime(2026, 11, 16, 12, 0);

  group('時間範圍過濾', () {
    test('全部時間 → 全部通過（含 null 送出時間）', () {
      expect(passesTimeFilter(SearchTimeRange.all, now, now), isTrue);
      expect(passesTimeFilter(SearchTimeRange.all, null, now), isTrue);
    });

    test('今天 → 只通過今天（含零點）', () {
      final todayMidnight = DateTime(2026, 11, 16);
      expect(passesTimeFilter(SearchTimeRange.today, todayMidnight, now), isTrue);
      expect(passesTimeFilter(SearchTimeRange.today, now, now), isTrue);
      expect(
        passesTimeFilter(
          SearchTimeRange.today,
          DateTime(2026, 11, 15, 23, 59),
          now,
        ),
        isFalse,
      );
    });

    test('最近 7 天 → 含今天往回 6 天', () {
      expect(
        passesTimeFilter(
          SearchTimeRange.week,
          DateTime(2026, 11, 10),
          now,
        ),
        isTrue,
      );
      expect(
        passesTimeFilter(
          SearchTimeRange.week,
          DateTime(2026, 11, 9),
          now,
        ),
        isFalse,
      );
    });

    test('最近 30 天 → 含今天往回 29 天', () {
      expect(
        passesTimeFilter(
          SearchTimeRange.month,
          DateTime(2026, 10, 18),
          now,
        ),
        isTrue,
      );
      expect(
        passesTimeFilter(
          SearchTimeRange.month,
          DateTime(2026, 10, 17),
          now,
        ),
        isFalse,
      );
    });

    test('送出時間為 null → 通過（不因缺資料漏掉結果）', () {
      expect(passesTimeFilter(SearchTimeRange.today, null, now), isTrue);
    });
  });

  group('訊息類型過濾', () {
    test('全部類型 → 全部通過', () {
      expect(passesTypeFilter(SearchMessageType.all, 'm.text', false), isTrue);
      expect(passesTypeFilter(SearchMessageType.all, null, true), isTrue);
    });

    test('文字 → 只有 m.text', () {
      expect(passesTypeFilter(SearchMessageType.text, 'm.text', false), isTrue);
      expect(passesTypeFilter(SearchMessageType.text, 'm.image', false), isFalse);
      expect(passesTypeFilter(SearchMessageType.text, null, true), isFalse);
    });

    test('圖片 → 只有 m.image', () {
      expect(passesTypeFilter(SearchMessageType.image, 'm.image', false), isTrue);
      expect(passesTypeFilter(SearchMessageType.image, 'm.text', false), isFalse);
    });

    test('檔案 → m.file／m.video／m.audio', () {
      expect(passesTypeFilter(SearchMessageType.file, 'm.file', false), isTrue);
      expect(passesTypeFilter(SearchMessageType.file, 'm.video', false), isTrue);
      expect(passesTypeFilter(SearchMessageType.file, 'm.audio', false), isTrue);
      expect(passesTypeFilter(SearchMessageType.file, 'm.text', false), isFalse);
    });

    test('位置 → 只有 m.location', () {
      expect(
        passesTypeFilter(SearchMessageType.location, 'm.location', false),
        isTrue,
      );
      expect(
        passesTypeFilter(SearchMessageType.location, 'm.text', false),
        isFalse,
      );
    });

    test('貼圖 → 只看事件型別 m.sticker（不看 msgtype）', () {
      expect(passesTypeFilter(SearchMessageType.sticker, null, true), isTrue);
      expect(passesTypeFilter(SearchMessageType.sticker, 'm.text', false), isFalse);
    });
  });

  group('綜合過濾', () {
    test('時間與類型都須通過', () {
      const filters = SearchFilters(
        timeRange: SearchTimeRange.today,
        type: SearchMessageType.text,
      );
      expect(
        passesSearchFilters(
          filters,
          DateTime(2026, 11, 16, 9),
          'm.text',
          false,
          now,
        ),
        isTrue,
      );
      // 時間過、類型不過
      expect(
        passesSearchFilters(
          filters,
          DateTime(2026, 11, 16, 9),
          'm.image',
          false,
          now,
        ),
        isFalse,
      );
      // 類型過、時間不過
      expect(
        passesSearchFilters(
          filters,
          DateTime(2026, 11, 10, 9),
          'm.text',
          false,
          now,
        ),
        isFalse,
      );
    });

    test('空條件 → isEmpty', () {
      expect(const SearchFilters().isEmpty, isTrue);
      expect(
        const SearchFilters(timeRange: SearchTimeRange.today).isEmpty,
        isFalse,
      );
    });
  });

  group('文案', () {
    test('時間與類型皆有中文文案', () {
      expect(searchTimeRangeLabel(SearchTimeRange.all), '全部時間');
      expect(searchTimeRangeLabel(SearchTimeRange.today), '今天');
      expect(searchMessageTypeLabel(SearchMessageType.all), '全部類型');
      expect(searchMessageTypeLabel(SearchMessageType.sticker), '貼圖');
    });
  });
}
