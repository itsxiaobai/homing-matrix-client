// 貼圖關鍵字聯想（backlog #8；人類 2026-11-03 目標 #8「貼圖可連結特定關鍵字，
// 當使用者在輸入框打出相關字詞時，自動彈出建議貼圖」＋「建議貼圖不保留
// （不持久存使用者輸入）」）。
//
// 本檔為**純邏輯**：不 import Flutter、不碰網路、不讀寫資料庫，便於單元測試。
//
// 關鍵字來源＝使用者自行匯入的貼圖檔名（短碼／名稱），例如 `cat_happy.png`
// → 關鍵字 `cat`、`happy`。Homing 不內建任何關鍵字資料庫，也不複製任何
// LINE 貼圖素材（見藍圖 §十二「LINE 禁區」）。
//
// 隱私：輸入內容**只存在記憶體**（呼叫端傳入的 `text`），本檔不寫入任何
// 儲存空間、不記錄、不上傳；離開輸入框即失效。
library;

/// 貼圖庫中的一張貼圖（對應 `app_settings.db` 的 `stickers` 表一列）。
class StickerLibraryEntry {
  const StickerLibraryEntry({
    required this.id,
    required this.path,
    this.name,
    this.mxcUrl,
    this.body,
    this.packId,
    this.keywords = const [],
  });

  final int id;

  /// 本機檔案路徑（預覽用；zip 匯入者為解壓後的本機副本）。
  final String path;

  /// 匯入時的檔名（可為 null）；關鍵字即由此推導。
  final String? name;

  /// 已上傳 homeserver 的媒體 URI（zip 貼圖包匯入後存在；送出時直接使用，
  /// 不重複上傳）。null＝僅本機貼圖，送出時才上傳。
  final String? mxcUrl;

  /// alt text（送出時的 `body`）。
  final String? body;

  /// 所屬貼圖包 id（zip 匯入者）。
  final String? packId;

  /// 搜尋關鍵字（創作者於貼圖包 manifest 指定；建議功能優先比對此清單）。
  /// 空＝退回檔名 token（見 `stickerKeywords`）。
  final List<String> keywords;
}

/// 一筆建議結果（貼圖＋比對分數）。
class StickerSuggestion {
  const StickerSuggestion({required this.entry, required this.score});

  final StickerLibraryEntry entry;

  /// 分數越大越相關（僅供排序，非使用者可見）。
  final int score;
}

/// CJK（中日韓）字元範圍（常用 Unicode 区段；用於中文關鍵字的子字串比對）。
final RegExp _cjk = RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]');

/// 關鍵字切分用的分隔符（底線、連字號、空白、括號、點…）。
final RegExp _separator = RegExp(r'[^0-9a-z\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]+');

/// 去掉副檔名（僅取最後一個點之後為副檔名的部分）。
String stickerStem(String? name) {
  if (name == null || name.isEmpty) return '';
  final base = name.split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0) return base;
  return base.substring(0, dot);
}

/// 貼圖的關鍵字清單（全部小寫）：**創作者指定的 `keywords` 優先**，
/// 再補上檔名 token（避免只有檔名時無法被建議到）。
List<String> stickerSearchKeywords(StickerLibraryEntry entry) {
  final out = <String>[];
  for (final k in entry.keywords) {
    final t = k.trim().toLowerCase();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  for (final t in stickerKeywords(entry.name)) {
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// 由檔名推導關鍵字清單（全部小寫）。
///
/// - `cat_happy.png` → `['cat', 'happy']`
/// - `貓咪開心.png` → `['貓咪開心']`（CJK 不分詞，以整串子字串比對）
List<String> stickerKeywords(String? name) {
  final stem = stickerStem(name).toLowerCase();
  if (stem.isEmpty) return const [];
  final parts = stem.split(_separator).where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? [stem] : parts;
}

/// 依輸入內容建議貼圖。
///
/// 比對規則（由強到弱）：
/// 1. 關鍵字**整串包含**輸入（`query` 為檔名／短碼的子字串）→ 分數 `len×10`
/// 2. 關鍵字 token **開頭符合**輸入 → 分數 `len×5`
/// 3. 關鍵字 token **內含**輸入 → 分數 `len×2`
///
/// 規則說明：
/// - 純 ASCII 輸入長度 < 2 → 不建議（避免單字母雜訊）
/// - 空白輸入 → 不建議
/// - 分數相同時依檔名排序（穩定、可預期）
List<StickerSuggestion> suggestStickers({
  required String text,
  required List<StickerLibraryEntry> library,
  int limit = 8,
}) {
  final query = text.trim().toLowerCase();
  if (query.isEmpty) return const [];
  final hasCjk = _cjk.hasMatch(query);
  if (!hasCjk && query.length < 2) return const [];

  final results = <StickerSuggestion>[];
  for (final entry in library) {
    final stem = stickerStem(entry.name).toLowerCase();
    if (stem.isEmpty) continue;
    var score = 0;
    if (stem.contains(query)) {
      score = query.length * 10;
    } else {
      for (final token in stickerSearchKeywords(entry)) {
        if (token.startsWith(query)) {
          score = _max(score, query.length * 5);
        } else if (token.contains(query)) {
          score = _max(score, query.length * 2);
        }
      }
    }
    if (score > 0) {
      results.add(StickerSuggestion(entry: entry, score: score));
    }
  }

  results.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byName = stickerStem(a.entry.name)
        .toLowerCase()
        .compareTo(stickerStem(b.entry.name).toLowerCase());
    if (byName != 0) return byName;
    return a.entry.id.compareTo(b.entry.id);
  });

  if (results.length <= limit) return results;
  return results.sublist(0, limit);
}

int _max(int a, int b) => a > b ? a : b;
