// 貼圖包（zip）匯入與安全驗證——藍圖 Phase 3.2／3.3，
// 規格見 `STICKER_FORMAT.md`（＝藍圖 §十一）。
//
// 安全重點（藍圖 §六「惡意 zip」風險，🔴 高）：
// 1. **先掃中央目錄**（不解壓）→ 檔案數、單檔大小、解壓總量、壓縮比上限；
// 2. **路徑安全**：絕對路徑、`..`、符號連結 → 立即中止；
// 3. **格式白名單**：僅 `.png`／`.webp`／`manifest.json`／`LICENSE.txt`；
// 4. **檔頭預檢**：解碼前讀 PNG IHDR／WebP header 取得尺寸並驗上限；
// 5. **動圖拒收**：APNG（acTL）／動畫 WebP（ANIM）於檔頭階段即拒收。
//
// 本檔的「純驗證」部分（`parseStickerPack`）不碰網路、不寫檔案，可單元測試；
// 匯入（解壓到本機、上傳 homeserver、寫入本機貼圖庫）另置於
// `sticker_pack_installer.dart`。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'zip_safety.dart';

/// 驗證失敗（使用者可見訊息；不吐堆疊細節）。
class StickerPackException implements Exception {
  StickerPackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 規格 v1 的硬性限制（STICKER_FORMAT.md §4）。
class StickerPackLimits {
  const StickerPackLimits({
    this.maxFileCount = 210,
    this.maxTotalUncompressed = 50 * 1024 * 1024,
    this.maxSingleFileSize = 2 * 1024 * 1024,
    this.maxCompressionRatio = 100,
    this.maxDimension = 2048,
    this.maxPixels = 2048 * 2048,
    this.maxThumbnailSize = 512 * 1024,
    this.maxThumbnailDimension = 512,
  });

  final int maxFileCount;
  final int maxTotalUncompressed;
  final int maxSingleFileSize;
  final int maxCompressionRatio;
  final int maxDimension;
  final int maxPixels;
  final int maxThumbnailSize;
  final int maxThumbnailDimension;
}

/// 一張貼圖（驗證通過）。
class StickerPackItem {
  const StickerPackItem({
    required this.shortcode,
    required this.file,
    required this.body,
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    this.name,
    this.keywords = const [],
  });

  /// 包內唯一短碼（`^[a-z0-9_-]{1,32}$`）。
  final String shortcode;

  /// manifest 中的相對路徑（zip 內）。
  final String file;

  /// alt text（body）；空缺時以 shortcode 為預設。
  final String body;

  /// 圖片位元組（已通過檔頭預檢）。
  final Uint8List bytes;

  final String mimeType;
  final int width;
  final int height;

  /// 貼圖顯示名稱（manifest `name`；缺漏則以 shortcode 為預設）。
  final String? name;

  /// 搜尋關鍵字（manifest `keywords`；建議功能比對用）。
  ///
  /// 對應人類 2026-11-15 的多裝置同步構想：「一份 json 填入貼圖名稱、
  /// 搜尋關鍵字、檔名」——本欄位即該 json 的關鍵字來源。
  final List<String> keywords;
}

/// 通過驗證的貼圖包。
class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.author,
    required this.license,
    required this.attribution,
    required this.description,
    required this.usage,
    required this.stickers,
    required this.thumbnail,
    required this.warnings,
  });

  final String id;
  final String name;
  final String author;
  final String license;
  final String attribution;
  final String? description;

  /// 貼圖使用情境（`sticker`／`emoticon`；空＝皆可）。
  final List<String> usage;

  final List<StickerPackItem> stickers;

  /// 縮圖（zip 內路徑；未提供則 null）。
  final String? thumbnail;

  /// 警告（超過建議值但未超過硬上限）。
  final List<String> warnings;
}

/// 驗證並解析貼圖包 zip（純函式：不寫檔、不上傳、不碰 DB）。
///
/// [zipBytes] 為 zip 檔內容；[limits] 可覆寫預設上限（測試用）。
StickerPack parseStickerPack(
  Uint8List zipBytes, {
  StickerPackLimits limits = const StickerPackLimits(),
}) {
  if (zipBytes.isEmpty) {
    throw StickerPackException('檔案是空的');
  }

  // ① 先讀中央目錄（不解壓）→ 檔案數／大小／壓縮比檢查。
  final entries = readZipEntries(zipBytes);
  if (entries.isEmpty) {
    throw StickerPackException('不是有效的 zip 檔');
  }
  if (entries.length > limits.maxFileCount) {
    throw StickerPackException(
      '貼圖包內檔案過多（${entries.length} 個，上限 ${limits.maxFileCount}）',
    );
  }
  var totalUncompressed = 0;
  for (final e in entries) {
    if (e.uncompressedSize > limits.maxSingleFileSize) {
      throw StickerPackException(
        '檔案過大：${e.name}（${_mb(e.uncompressedSize)}，上限 '
        '${_mb(limits.maxSingleFileSize)}）',
      );
    }
    totalUncompressed += e.uncompressedSize;
    if (totalUncompressed > limits.maxTotalUncompressed) {
      throw StickerPackException(
        '解壓後總大小超過 ${_mb(limits.maxTotalUncompressed)}',
      );
    }
    final ratio = e.compressedSize <= 0
        ? (e.uncompressedSize > 0 ? 999999 : 0)
        : e.uncompressedSize / e.compressedSize;
    if (ratio > limits.maxCompressionRatio) {
      throw StickerPackException(
        '${e.name} 壓縮比過高（${ratio.toStringAsFixed(0)}:1，上限 '
        '${limits.maxCompressionRatio}:1）',
      );
    }
  }

  // ② 解壓（逐 entry；archive 為延遲解壓）。
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw StickerPackException('zip 檔損毀或格式不正確');
  }

  // ③ 路徑與白名單檢查（不解壓內容即可判定的先做）。
  final byName = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (file.isDirectory) continue;
    if (file.isSymbolicLink) {
      throw StickerPackException('貼圖包不得包含符號連結');
    }
    final name = file.name;
    if (name.startsWith('/') || name.contains('\\') || name.contains(':')) {
      throw StickerPackException('貼圖包含絕對路徑：$name');
    }
    if (name.split('/').contains('..')) {
      throw StickerPackException('貼圖包含上層路徑（..）：$name');
    }
    if (!_isAllowedPath(name)) {
      throw StickerPackException('貼圖包含不允許的檔案：$name');
    }
    byName[name] = file;
  }

  // ④ manifest 驗證。
  final manifestFile = byName['manifest.json'];
  if (manifestFile == null) {
    throw StickerPackException('貼圖包缺少 manifest.json');
  }
  final Map<String, dynamic> manifest;
  try {
    final decoded = jsonDecode(utf8.decode(manifestFile.content));
    if (decoded is! Map) {
      throw const FormatException('not an object');
    }
    manifest = decoded.cast<String, dynamic>();
  } catch (_) {
    throw StickerPackException('manifest.json 不是有效的 JSON 物件');
  }

  final specVersion = manifest['spec_version'];
  if (specVersion != '1.0') {
    throw StickerPackException('不支援的 spec_version：$specVersion');
  }
  final id = _requireString(manifest, 'id');
  if (id.isEmpty || id.length > 255) {
    throw StickerPackException('manifest.id 必須是 1–255 bytes 的字串');
  }
  final name = _requireString(manifest, 'name');
  final author = _requireString(manifest, 'author');
  final license = _requireString(manifest, 'license');
  final attribution = _requireString(manifest, 'attribution');

  final usageList = manifest['usage'];
  final usage = <String>[];
  if (usageList is List) {
    for (final u in usageList) {
      if (u is! String) {
        throw StickerPackException('manifest.usage 只能含字串');
      }
      if (u != 'sticker' && u != 'emoticon') {
        throw StickerPackException('manifest.usage 不支援的值：$u');
      }
      usage.add(u);
    }
  } else if (usageList != null) {
    throw StickerPackException('manifest.usage 必須是陣列');
  }

  final rawStickers = manifest['stickers'];
  if (rawStickers is! List || rawStickers.isEmpty) {
    throw StickerPackException('manifest.stickers 必須是非空陣列');
  }
  if (rawStickers.length > 200) {
    throw StickerPackException('貼圖數量超過上限（200）');
  }

  final warnings = <String>[];
  final shortcodes = <String>{};
  final items = <StickerPackItem>[];
  for (final raw in rawStickers) {
    if (raw is! Map) {
      throw StickerPackException('manifest.stickers 的元素格式錯誤');
    }
    final item = raw.cast<String, dynamic>();
    final shortcode = _requireString(item, 'shortcode');
    if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(shortcode)) {
      throw StickerPackException('shortcode 格式不合法：$shortcode');
    }
    if (!shortcodes.add(shortcode)) {
      throw StickerPackException('shortcode 重複：$shortcode');
    }
    final filePath = _requireString(item, 'file');
    if (!filePath.startsWith('stickers/')) {
      throw StickerPackException('貼圖必須放在 stickers/ 目錄下：$filePath');
    }
    final archiveFile = byName[filePath];
    if (archiveFile == null) {
      throw StickerPackException('貼圖檔不存在：$filePath');
    }
    final bytes = archiveFile.content;
    final header = _inspectImage(bytes, filePath, limits, warnings);
    final body = (item['body'] is String && (item['body'] as String).isNotEmpty)
        ? item['body'] as String
        : shortcode;
    // 顯示名稱（選用；缺漏＝shortcode）。
    final rawName = item['name'];
    final displayName = (rawName is String && rawName.trim().isNotEmpty)
        ? rawName.trim()
        : shortcode;
    // 搜尋關鍵字（選用陣列；字串皆轉小寫去空白）。
    final rawKeywords = item['keywords'];
    final keywords = <String>[];
    if (rawKeywords is List) {
      for (final k in rawKeywords) {
        if (k is! String) {
          throw StickerPackException('stickers[].keywords 只能含字串');
        }
        final t = k.trim().toLowerCase();
        if (t.isNotEmpty && !keywords.contains(t)) keywords.add(t);
      }
    } else if (rawKeywords != null) {
      throw StickerPackException('stickers[].keywords 必須是陣列');
    }
    items.add(StickerPackItem(
      shortcode: shortcode,
      file: filePath,
      body: body,
      bytes: bytes,
      mimeType: header.mimeType,
      width: header.width,
      height: header.height,
      name: displayName,
      keywords: keywords,
    ));
  }

  // ⑤ 縮圖（選用）。
  String? thumbnail;
  final rawThumb = manifest['thumbnail'];
  if (rawThumb is String && rawThumb.isNotEmpty) {
    final thumbFile = byName[rawThumb];
    if (thumbFile == null) {
      throw StickerPackException('縮圖檔不存在：$rawThumb');
    }
    if (thumbFile.size > limits.maxThumbnailSize) {
      throw StickerPackException(
        '縮圖過大（${_mb(thumbFile.size)}，上限 ${_mb(limits.maxThumbnailSize)}）',
      );
    }
    final thumbHeader = _inspectImage(thumbFile.content, rawThumb, limits, warnings);
    if (thumbHeader.width > limits.maxThumbnailDimension ||
        thumbHeader.height > limits.maxThumbnailDimension) {
      throw StickerPackException('縮圖尺寸超過 ${limits.maxThumbnailDimension}px');
    }
    thumbnail = rawThumb;
  }

  // LICENSE.txt 僅允許存在，不解析內容（權利宣告由創作者負責）。
  return StickerPack(
    id: id,
    name: name,
    author: author,
    license: license,
    attribution: attribution,
    description: manifest['description'] is String
        ? manifest['description'] as String
        : null,
    usage: usage,
    stickers: items,
    thumbnail: thumbnail,
    warnings: warnings,
  );
}

/// 建立 pack 事件的 content（STICKER_FORMAT.md §7 的對映）。
///
/// [mxcByShortcode]＝shortcode → `mxc://…`；[infoByShortcode]＝shortcode → info。
Map<String, dynamic> buildPackContent(
  StickerPack pack,
  Map<String, String> mxcByShortcode,
  Map<String, Map<String, dynamic>> infoByShortcode,
) {
  final images = <String, dynamic>{};
  for (final item in pack.stickers) {
    final mxc = mxcByShortcode[item.shortcode];
    if (mxc == null) continue;
    final info = infoByShortcode[item.shortcode];
    images[item.shortcode] = <String, dynamic>{
      'url': mxc,
      'body': item.body,
      'info': ?info,
    };
  }
  final packMeta = <String, dynamic>{
    'display_name': pack.name,
    'attribution': '${pack.author} — ${pack.attribution}',
    if (pack.usage.isNotEmpty) 'usage': pack.usage,
  };
  return <String, dynamic>{'images': images, 'pack': packMeta};
}

// ── 內部工具 ────────────────────────────────────────────────────────────

class _ImageHeader {
  const _ImageHeader(this.mimeType, this.width, this.height);

  final String mimeType;
  final int width;
  final int height;
}

/// 檔頭預檢：格式、尺寸、像素數、是否動圖（不解碼像素）。
_ImageHeader _inspectImage(
  Uint8List bytes,
  String path,
  StickerPackLimits limits,
  List<String> warnings,
) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    if (bytes.length < 24) {
      throw StickerPackException('PNG 檔頭不完整：$path');
    }
    // IHDR：signature(8) + length(4) + type(4) → 寬高在 byte 16..24。
    final width = _be32(bytes, 16);
    final height = _be32(bytes, 20);
    _checkDimensions(width, height, limits, path, warnings);
    if (_pngIsAnimated(bytes)) {
      throw StickerPackException('不支援動態貼圖（APNG）：$path');
    }
    return _ImageHeader('image/png', width, height);
  }
  if (bytes.length >= 16 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    if (bytes.length < 30) {
      throw StickerPackException('WebP 檔頭不完整：$path');
    }
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    int width;
    int height;
    if (chunk == 'VP8 ') {
      // 有損：frame tag(3) + sync code(3) → 寬高在 byte 26..30（14 bits）。
      width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
      height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
    } else if (chunk == 'VP8L') {
      // 無損：bits 於 byte 21..25（寬高各 14 bits，減 1）。
      final bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) |
          (bytes[24] << 24);
      width = (bits & 0x3FFF) + 1;
      height = ((bits >> 14) & 0x3FFF) + 1;
    } else if (chunk == 'VP8X') {
      // 擴充：canvas 寬高為 24-bit LE（byte 24..27 / 27..30）＋1。
      width = (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1;
      height = (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1;
    } else {
      throw StickerPackException('不支援的 WebP 類型（$chunk）：$path');
    }
    _checkDimensions(width, height, limits, path, warnings);
    if (_webPIsAnimated(bytes)) {
      throw StickerPackException('不支援動態貼圖（動畫 WebP）：$path');
    }
    return _ImageHeader('image/webp', width, height);
  }
  throw StickerPackException('只接受 PNG 或 WebP（靜態）圖片：$path');
}

void _checkDimensions(
  int width,
  int height,
  StickerPackLimits limits,
  String path,
  List<String> warnings,
) {
  if (width <= 0 || height <= 0) {
    throw StickerPackException('圖片尺寸無效：$path');
  }
  if (width > limits.maxDimension || height > limits.maxDimension) {
    throw StickerPackException(
      '圖片長邊超過 ${limits.maxDimension}px：$path',
    );
  }
  if (width * height > limits.maxPixels) {
    throw StickerPackException('圖片像素數超過上限：$path');
  }
  if (width < 512 || height < 512) {
    warnings.add('$path 尺寸小於建議值 512px');
  }
}

/// PNG 是否含 `acTL` chunk（APNG 動畫）。
bool _pngIsAnimated(Uint8List bytes) {
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = _be32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'acTL') return true;
    if (type == 'IEND') return false;
    offset += 12 + length; // length(4) + type(4) + data + crc(4)
  }
  return false;
}

/// WebP 是否含 `ANIM` chunk（動畫）。
bool _webPIsAnimated(Uint8List bytes) {
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (type == 'ANIM') return true;
    // RIFF chunk 的長度為**小端**（little-endian）。
    final size = _le32(bytes, offset + 4);
    offset += 8 + size + (size & 1);
  }
  return false;
}

int _le32(Uint8List b, int offset) =>
    b[offset] |
    (b[offset + 1] << 8) |
    (b[offset + 2] << 16) |
    (b[offset + 3] << 24);

int _be32(Uint8List b, int offset) =>
    (b[offset] << 24) |
    (b[offset + 1] << 16) |
    (b[offset + 2] << 8) |
    b[offset + 3];

bool _isAllowedPath(String name) {
  final lower = name.toLowerCase();
  if (lower == 'manifest.json') return true;
  if (lower == 'license.txt') return true;
  if (lower.startsWith('stickers/')) {
    return lower.endsWith('.png') || lower.endsWith('.webp');
  }
  if (lower == 'thumbnail.png' || lower == 'thumbnail.webp') return true;
  return false;
}

String _requireString(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v is! String || v.isEmpty) {
    throw StickerPackException('manifest 缺少必要欄位：$key');
  }
  return v;
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
