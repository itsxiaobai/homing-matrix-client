// 媒體本機快取（離線可讀・**方案 A**：只做媒體快取＋容量管理）。
//
// 目標（人類 2026-11-17「離線快取先提案」→ 選定 **A**）：
// * 讓使用者①**快速**看到先前看過的媒體（不必每次重新下載）②**離線時**仍可
//   閱讀已載入的媒體。
// * **不做**對話文字快取（SDK 事件 DB 已能離線可讀）＋**不做**本機加密
//   （＝金鑰流程，屬紅線；本次刻意避開，見 `OFFLINE_CACHE_PROPOSAL.md`）。
//
// 設計要點：
// * 儲存位置：**app cache 目錄**（`getApplicationCacheDirectory()`；系統可在
//   空間不足時回收 → 屬「快取」而非「永久資料」）。
// * 容量管理：**LRU**（最久未用先清）＋**上限**（預設 512 MB，可調）。
// * 索引：以 `index.json` 記錄每筆的 key／大小／最後使用時間（**不含任何
//   訊息內容**；key 為 eventId 雜湊）。
// * 純邏輯（[selectEvictions]）與 IO 分離 → 可單元測試。
//
// ⚠️ 隱私（已寫入 `known_problems.md` / 待寫入 `PRIVACY.md`）：快取會讓「已刪除
// 的訊息」其媒體仍留在本機 → 設定頁提供「立即清除」。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

/// 快取上限預設值（512 MB）。
const int kMediaCacheDefaultMaxBytes = 512 * 1024 * 1024;

/// kv key：媒體快取容量上限（bytes）。
const String kMediaCacheMaxBytesKey = 'media_cache_max_bytes';

/// 讀取容量上限（未設定 → 預設 512 MB）。
Future<int> loadMediaCacheMaxBytes() async {
  try {
    final raw = await AppSettings.get(kMediaCacheMaxBytesKey);
    final v = int.tryParse(raw ?? '');
    if (v != null && v > 0) return v;
  } catch (_) {
    // 讀取失敗 → 用預設值。
  }
  return kMediaCacheDefaultMaxBytes;
}

/// 儲存容量上限並立即套用（設定頁）。
Future<void> saveMediaCacheMaxBytes(int bytes) async {
  try {
    await AppSettings.set(kMediaCacheMaxBytesKey, bytes.toString());
  } catch (_) {
    // 寫入失敗不影響當前 session。
  }
  try {
    await (await mediaCache()).setMaxBytes(bytes);
  } catch (_) {
    // 忽略。
  }
}

/// 快取索引檔名。
const String kMediaCacheIndexFile = 'index.json';

/// 一筆快取索引（**只有大小與時間，沒有內容**）。
class MediaCacheEntry {
  const MediaCacheEntry({
    required this.key,
    required this.size,
    required this.lastUsed,
  });

  /// 快取鍵（eventId 的雜湊；不對外暴露）。
  final String key;

  /// 檔案大小（bytes）。
  final int size;

  /// 最後使用時間（epoch ms）。
  final int lastUsed;

  MediaCacheEntry copyWith({int? size, int? lastUsed}) => MediaCacheEntry(
        key: key,
        size: size ?? this.size,
        lastUsed: lastUsed ?? this.lastUsed,
      );

  Map<String, dynamic> toJson() =>
      {'k': key, 's': size, 't': lastUsed};

  static MediaCacheEntry fromJson(Map<String, dynamic> j) => MediaCacheEntry(
        key: j['k'] as String,
        size: (j['s'] as num).toInt(),
        lastUsed: (j['t'] as num).toInt(),
      );
}

/// 快取用量統計。
class MediaCacheStats {
  const MediaCacheStats({
    required this.fileCount,
    required this.totalBytes,
    required this.maxBytes,
  });

  final int fileCount;
  final int totalBytes;
  final int maxBytes;

  /// 人可讀字串（MB）。
  String format() {
    final mb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final maxMb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
    return '$fileCount 個檔案、$mb MB／上限 $maxMb MB';
  }
}

/// **純函式**：挑出要刪除的項目（LRU）。
///
/// [entries] 為目前的索引；回傳**要刪掉**的 key（由最久未用開始），
/// 直到剩下的總大小不超過 [maxBytes]。回傳空清單＝未超量。
List<String> selectEvictions(List<MediaCacheEntry> entries, int maxBytes) {
  final sorted = [...entries]..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
  var total = 0;
  for (final e in sorted) {
    total += e.size;
  }
  final evicted = <String>[];
  for (final e in sorted) {
    if (total <= maxBytes) break;
    evicted.add(e.key);
    total -= e.size;
  }
  return evicted;
}

/// 媒體快取（檔案型；**不含加密**）。
class MediaCache {
  MediaCache._(this._dir, this._maxBytes, this._entries);

  final Directory _dir;
  int _maxBytes;
  final Map<String, MediaCacheEntry> _entries;

  /// 目前用量統計。
  MediaCacheStats get stats => MediaCacheStats(
        fileCount: _entries.length,
        totalBytes: _entries.values.fold(0, (a, b) => a + b.size),
        maxBytes: _maxBytes,
      );

  /// 開啟（或建立）快取目錄並載入索引。
  ///
  /// [maxBytes]＝容量上限（<=0 表示不限制）。
  /// [root]＝測試用（注入目錄）；正式路徑取 app cache 目錄。
  static Future<MediaCache> open({
    int maxBytes = kMediaCacheDefaultMaxBytes,
    Directory? root,
  }) async {
    final base = root ?? await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/media_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final cache = MediaCache._(dir, maxBytes, <String, MediaCacheEntry>{});
    await cache._loadIndex();
    return cache;
  }

  /// 改變容量上限（並立即套用 LRU 清理）。
  Future<void> setMaxBytes(int maxBytes) async {
    _maxBytes = maxBytes;
    await _evictIfNeeded();
  }

  /// 快取鍵（由 eventId 產生；**不直接用 eventId 當檔名**）。
  static String keyFor(String eventId, {bool thumbnail = false}) {
    // 簡單但足夠的散列（避免檔名含非法字元；不需密碼學強度）。
    var h = 0x811c9dc5;
    for (final c in eventId.codeUnits) {
      h = (h ^ c) & 0x1fffffff;
      h = (h * 31) & 0x1fffffff;
    }
    return '${h.toRadixString(16)}'
        '${thumbnail ? '_t' : ''}'
        '${_extSuffix(eventId)}';
  }

  static String _extSuffix(String eventId) => '';

  File _fileFor(String key) => File('${_dir.path}/$key.bin');

  /// 讀取（命中→更新 lastUsed；未命中→null）。
  Future<Uint8List?> read(String key) async {
    final entry = _entries[key];
    final file = _fileFor(key);
    if (entry == null || !await file.exists()) {
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      _entries[key] = entry.copyWith(lastUsed: DateTime.now().millisecondsSinceEpoch);
      unawaitedSave();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// 寫入（覆寫同名；並在超過上限時依 LRU 清理）。
  Future<void> write(String key, Uint8List bytes) async {
    try {
      final file = _fileFor(key);
      await file.writeAsBytes(bytes, flush: true);
      _entries[key] = MediaCacheEntry(
        key: key,
        size: bytes.lengthInBytes,
        lastUsed: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveIndex();
      await _evictIfNeeded();
    } catch (_) {
      // 快取寫入失敗不得影響正常使用（主流程照常）。
    }
  }

  /// 清除全部（設定 → 離線快取 → 立即清除）。
  Future<void> clear() async {
    try {
      if (await _dir.exists()) {
        for (final entity in await _dir.list().toList()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (_) {
      // 忽略（清除失敗不應崩潰）。
    }
    _entries.clear();
    await _saveIndex();
  }

  Future<void> _evictIfNeeded() async {
    final evicted = selectEvictions(_entries.values.toList(), _maxBytes);
    if (evicted.isEmpty) return;
    for (final key in evicted) {
      try {
        final file = _fileFor(key);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _entries.remove(key);
    }
    await _saveIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final file = File('${_dir.path}/$kMediaCacheIndexFile');
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final e = MediaCacheEntry.fromJson(item);
          _entries[e.key] = e;
        }
      }
    } catch (_) {
      // 索引損毀 → 當作空快取（不影響主流程）。
    }
  }

  Future<void> _saveIndex() async {
    try {
      final file = File('${_dir.path}/$kMediaCacheIndexFile');
      final list = _entries.values.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {
      // 忽略。
    }
  }

  /// 背景寫入索引（不 await；避免拖慢讀取路徑）。
  void unawaitedSave() {
    _saveIndex();
  }
}

/// 全域快取實例（單例；首次使用時開啟）。
MediaCache? _cacheInstance;

/// 取得（並建立）全域快取。
Future<MediaCache> mediaCache() async =>
    _cacheInstance ??= await MediaCache.open(maxBytes: await loadMediaCacheMaxBytes());

/// 測試用：重設全域快取實例。
void resetMediaCacheForTest() {
  _cacheInstance = null;
}

/// 取得媒體 bytes：**快取優先**（離線可讀・快速）＋ **與下載並行**。
///
/// 行為：
/// * 快取命中 → 立即回傳（**不等下載**）→ 離線也能讀到先前看過的媒體。
/// * 快取未命中 → 等官方 API 下載（`Event.downloadAndDecryptAttachment`；
///   加密由 SDK 官方處理，App 端零加密邏輯）→ 成功後**背景**寫入快取。
/// * 兩者都失敗 → 回 null（UI 顯示占位）。
///
/// ⚠️ 為何用「並行＋先到先用」而非「先查快取再下載」：快取是**最佳努力**的
/// 加速層，若它（例如平台不支援）卡住不應拖住畫面 → 兩者並行，谁先成功用誰；
/// 快取確定未命中才以 null 收尾。
Future<Uint8List?> loadMediaBytesWithCache(
  Event event, {
  bool thumbnail = false,
  String? cacheKey,
}) {
  final eventId = event.eventId;
  final key = cacheKey ??
      (eventId.isEmpty ? null : MediaCache.keyFor(eventId, thumbnail: thumbnail));

  final completer = Completer<Uint8List?>();
  void complete(Uint8List? bytes, {bool definitive = false}) {
    if (completer.isCompleted) return;
    if (bytes != null) {
      completer.complete(bytes);
      return;
    }
    if (definitive) {
      completer.complete(null);
    }
  }

  // ① -download（官方 API；成功即用）。
  final download = () async {
    try {
      final file = thumbnail
          ? await event.downloadAndDecryptAttachment(getThumbnail: true)
          : await event.downloadAndDecryptAttachment();
      return file.bytes;
    } catch (_) {
      return null;
    }
  }();
  download.then((bytes) {
    if (bytes != null) {
      complete(bytes);
      // 背景寫入快取（不阻塞畫面）。
      if (key != null) {
        unawaited(writeToCache(key, bytes));
      }
      return;
    }
    // 下載失敗 →  definitive 回 null（**不開 Timer**：widget 測試會抓未清理的
    // timer；離線命中由下面的快取探查在下載完成前先行 complete）。
    complete(null, definitive: true);
  });

  // ② 快取探查（**背景執行、不 await**）：只在 mobile 平台嘗試（path_provider
  //    的 app cache 目錄；widget 測試跑在 Linux → 跳過，避免 channel 卡住）。
  //    快取是最佳努力的加速層 → 不能因為它拖住畫面或留下 pending future。
  if (key != null && (Platform.isAndroid || Platform.isIOS)) {
    unawaited(() async {
      try {
        final cached = await (await mediaCache()).read(key);
        complete(cached);
      } catch (_) {
        // 快取不可用 → 不影響（下載路徑已 definitive 完成）。
      }
    }());
  } else if (key == null) {
    // 沒有 cache key（例如 pending 事件）→ 不會有命中。
  }

  return completer.future;
}

/// 背景寫入快取（失敗不影響主流程）。
Future<void> writeToCache(String key, Uint8List bytes) async {
  try {
    await (await mediaCache()).write(key, bytes);
  } catch (_) {
    // 忽略。
  }
}

/// 供 UI 使用：以快取優先的方式取得媒體的 `MatrixFile`（顯示只需要 bytes）。
Future<MatrixFile?> loadMediaFileWithCache(
  Event event, {
  bool thumbnail = false,
  String? cacheKey,
}) async {
  final bytes = await loadMediaBytesWithCache(
    event,
    thumbnail: thumbnail,
    cacheKey: cacheKey,
  );
  if (bytes == null) return null;
  return MatrixFile(
    bytes: bytes,
    name: thumbnail ? 'homing_cache_thumb' : 'homing_cache_media',
    mimeType: 'image/jpeg',
  );
}
