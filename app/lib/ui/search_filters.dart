// 第四十八批：訊息搜尋的**過濾條件**（時間範圍 ＋ 訊息類型）——純函式。
//
// 設計原則（純函式、可測試、不依賴 Flutter）：
// - 時間範圍以「訊息送出時間」比對，不使用伺服器查詢（避免額外網路請求）。
// - 類型過濾以 Matrix **官方 msgtype** 判斷（`m.text`／`m.image`／`m.file`／
//   `m.video`／`m.audio`／`m.location`；貼圖另以事件型別 `m.sticker` 判斷）。
// - 空條件＝全部通過（不過濾）。
//
// 這些條件**只影響顯示哪些搜尋結果**，不影響資料本身。
library;

/// 搜尋結果的時間範圍。
enum SearchTimeRange {
  /// 不限時間。
  all,

  /// 今天。
  today,

  /// 最近 7 天（含今天）。
  week,

  /// 最近 30 天（含今天）。
  month,
}

/// 搜尋結果的訊息類型。
enum SearchMessageType {
  /// 不限類型。
  all,

  /// 純文字（`m.text`）。
  text,

  /// 圖片（`m.image`）。
  image,

  /// 檔案／影片／音訊（`m.file`／`m.video`／`m.audio`）。
  file,

  /// 位置（`m.location`）。
  location,

  /// 貼圖（事件型別 `m.sticker`）。
  sticker,
}

/// 搜尋過濾條件（時間 ＋ 類型）。
class SearchFilters {
  const SearchFilters({this.timeRange = SearchTimeRange.all, this.type = SearchMessageType.all});

  final SearchTimeRange timeRange;
  final SearchMessageType type;

  /// 是否有任何條件（false＝不需過濾）。
  bool get isEmpty => timeRange == SearchTimeRange.all && type == SearchMessageType.all;

  SearchFilters copyWith({SearchTimeRange? timeRange, SearchMessageType? type}) =>
      SearchFilters(
        timeRange: timeRange ?? this.timeRange,
        type: type ?? this.type,
      );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.timeRange == timeRange &&
      other.type == type;

  @override
  int get hashCode => Object.hash(timeRange, type);
}

/// 時間範圍的起始時間（含）；[now] 可注入以便測試。
///
/// 回傳 null＝不限時間。
DateTime? searchTimeRangeStart(SearchTimeRange range, DateTime now) {
  switch (range) {
    case SearchTimeRange.all:
      return null;
    case SearchTimeRange.today:
      final d = now.toLocal();
      return DateTime(d.year, d.month, d.day);
    case SearchTimeRange.week:
      final d = now.toLocal();
      return DateTime(d.year, d.month, d.day).subtract(const Duration(days: 6));
    case SearchTimeRange.month:
      final d = now.toLocal();
      return DateTime(d.year, d.month, d.day).subtract(const Duration(days: 29));
  }
}

/// 訊息是否通過時間條件。
///
/// [sentAt] 為 null（測試注入或缺時間戳）→ **通過**（不因缺資料而漏掉結果）。
bool passesTimeFilter(SearchTimeRange range, DateTime? sentAt, DateTime now) {
  if (range == SearchTimeRange.all) return true;
  if (sentAt == null) return true;
  final start = searchTimeRangeStart(range, now);
  if (start == null) return true;
  return !sentAt.toLocal().isBefore(start);
}

/// 訊息是否通過類型條件。
///
/// [msgType] 為 Matrix 官方 msgtype；[isSticker] 為事件型別是否 `m.sticker`
/// （貼圖在 Matrix 是**事件型別**而非 msgtype，故分開判斷）。
bool passesTypeFilter(SearchMessageType type, String? msgType, bool isSticker) {
  switch (type) {
    case SearchMessageType.all:
      return true;
    case SearchMessageType.text:
      return !isSticker && msgType == 'm.text';
    case SearchMessageType.image:
      return !isSticker && msgType == 'm.image';
    case SearchMessageType.file:
      return !isSticker &&
          (msgType == 'm.file' || msgType == 'm.video' || msgType == 'm.audio');
    case SearchMessageType.location:
      return !isSticker && msgType == 'm.location';
    case SearchMessageType.sticker:
      return isSticker;
  }
}

/// 綜合判斷（時間 ＋ 類型）。
bool passesSearchFilters(
  SearchFilters filters,
  DateTime? sentAt,
  String? msgType,
  bool isSticker,
  DateTime now,
) =>
    passesTimeFilter(filters.timeRange, sentAt, now) &&
    passesTypeFilter(filters.type, msgType, isSticker);

/// 時間範圍的顯示文案（中文；LINE 版位的 filter chip 文案）。
String searchTimeRangeLabel(SearchTimeRange range) {
  switch (range) {
    case SearchTimeRange.all:
      return '全部時間';
    case SearchTimeRange.today:
      return '今天';
    case SearchTimeRange.week:
      return '最近 7 天';
    case SearchTimeRange.month:
      return '最近 30 天';
  }
}

/// 類型的顯示文案。
String searchMessageTypeLabel(SearchMessageType type) {
  switch (type) {
    case SearchMessageType.all:
      return '全部類型';
    case SearchMessageType.text:
      return '文字';
    case SearchMessageType.image:
      return '圖片';
    case SearchMessageType.file:
      return '檔案';
    case SearchMessageType.location:
      return '位置';
    case SearchMessageType.sticker:
      return '貼圖';
  }
}
