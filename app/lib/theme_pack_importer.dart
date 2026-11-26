// 主題包（zip）匯入與安全驗證——藍圖 §九第 13 項（人類 2026-11-15：「你出草案
// 我審」→ 規格草案見 `THEME_FORMAT.md` v1）。
//
// 與貼圖包同一套安全模型（共用 `zip_safety.dart`）：
// ① 先掃中央目錄（不解壓）→ 檔案數／單檔大小／總大小／壓縮比；
// ② 路徑安全（絕對路徑／`..`／反斜線／符號連結）；
// ③ 白名單（根目錄只允許 `theme.json`／`LICENSE.txt`；資產須在
//    `wallpaper/`、`fonts/`、`icons/` 內）；
// ④ `theme.json` 欄位驗證（含 `#RRGGBB` 色彩格式）；
// ⑤ 桌布檔頭預檢（PNG／WebP 取尺寸；拒 GIF／APNG）。
//
// 純驗證部分（`parseThemePack`）不碰網路／不寫檔，可單元測試。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'ui/app_icons.dart';
import 'ui/app_icons_generated.dart' show kAllIconSlotNames;
import 'zip_safety.dart';

/// 驗證失敗（使用者可見訊息）。
class ThemePackException implements Exception {
  ThemePackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// v1 硬性限制（`THEME_FORMAT.md` §3）。
class ThemePackLimits {
  const ThemePackLimits({
    this.maxFileCount = 100,
    this.maxTotalUncompressed = 80 * 1024 * 1024,
    this.maxSingleFileSize = 8 * 1024 * 1024,
    this.maxCompressionRatio = 100,
    this.maxWallpaperDimension = 4096,
    this.maxWallpaperPixels = 8388608,
  });

  final int maxFileCount;
  final int maxTotalUncompressed;
  final int maxSingleFileSize;
  final int maxCompressionRatio;
  final int maxWallpaperDimension;
  final int maxWallpaperPixels;
}

/// 驗證後的主題包。
class ThemePack {
  const ThemePack({
    required this.id,
    required this.name,
    required this.author,
    required this.license,
    required this.attribution,
    required this.description,
    required this.colors,
    required this.assets,
    required this.icons,
    required this.warnings,
  });

  final String id;
  final String name;
  final String author;
  final String license;
  final String attribution;
  final String? description;

  /// 配色（鍵值見 `THEME_FORMAT.md` §2）。
  final Map<String, String> colors;

  /// 資產路徑（相對於 zip 根）→ 實際路徑。
  final Map<String, String> assets;

  /// 圖示覆寫（第五十七批）：槽位名 → Material 名稱或 `{font, codepoint}`。
  /// 已驗證（合法槽位／合法 Material 名稱／合法 codepoint）。
  final Map<String, String> icons;

  final List<String> warnings;
}

/// 驗證並解析主題包 zip（純函式）。
ThemePack parseThemePack(
  Uint8List zipBytes, {
  ThemePackLimits limits = const ThemePackLimits(),
}) {
  if (zipBytes.isEmpty) {
    throw ThemePackException('檔案是空的');
  }

  // ① 中央目錄掃描。
  final entries = readZipEntries(zipBytes);
  if (entries.isEmpty) {
    throw ThemePackException('不是有效的 zip 檔');
  }
  if (entries.length > limits.maxFileCount) {
    throw ThemePackException(
      '主題包內檔案過多（${entries.length} 個，上限 ${limits.maxFileCount}）',
    );
  }
  var total = 0;
  for (final e in entries) {
    if (e.uncompressedSize > limits.maxSingleFileSize) {
      throw ThemePackException(
        '檔案過大：${e.name}（${_mb(e.uncompressedSize)}，上限 '
        '${_mb(limits.maxSingleFileSize)}）',
      );
    }
    total += e.uncompressedSize;
    if (total > limits.maxTotalUncompressed) {
      throw ThemePackException(
        '解壓後總大小超過 ${_mb(limits.maxTotalUncompressed)}',
      );
    }
    final ratio = e.compressedSize <= 0
        ? (e.uncompressedSize > 0 ? 999999 : 0)
        : e.uncompressedSize / e.compressedSize;
    if (ratio > limits.maxCompressionRatio) {
      throw ThemePackException(
        '${e.name} 壓縮比過高（${ratio.toStringAsFixed(0)}:1）',
      );
    }
  }

  // ② 解壓並檢查路徑／白名單。
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw ThemePackException('zip 檔損毀或格式不正確');
  }
  final byName = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (file.isDirectory) continue;
    if (file.isSymbolicLink) {
      throw ThemePackException('主題包不得包含符號連結');
    }
    final name = file.name;
    if (!isSafeZipPath(name)) {
      throw ThemePackException('主題包含不安全的路徑：$name');
    }
    if (!_isAllowedPath(name)) {
      throw ThemePackException('主題包含不允許的檔案：$name');
    }
    byName[name] = file;
  }

  // ③ theme.json 驗證。
  final manifestFile = byName['theme.json'];
  if (manifestFile == null) {
    throw ThemePackException('主題包缺少 theme.json');
  }
  final Map<String, dynamic> manifest;
  try {
    final decoded = jsonDecode(utf8.decode(manifestFile.content));
    if (decoded is! Map) {
      throw const FormatException('not an object');
    }
    manifest = decoded.cast<String, dynamic>();
  } catch (_) {
    throw ThemePackException('theme.json 不是有效的 JSON 物件');
  }
  if (manifest['spec_version'] != '1.0') {
    throw ThemePackException('不支援的 spec_version：${manifest['spec_version']}');
  }
  final id = _requireString(manifest, 'id');
  if (id.length > 255) {
    throw ThemePackException('theme.id 過長（上限 255 bytes）');
  }
  final name = _requireString(manifest, 'name');
  final author = _requireString(manifest, 'author');
  final license = _requireString(manifest, 'license');
  final attribution = _requireString(manifest, 'attribution');

  // ④ 配色（只接受 `#RRGGBB`）。
  final colors = <String, String>{};
  final rawColors = manifest['colors'];
  if (rawColors != null) {
    if (rawColors is! Map) {
      throw ThemePackException('theme.json 的 colors 必須是物件');
    }
    for (final entry in rawColors.entries) {
      final v = entry.value;
      if (v is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) {
        throw ThemePackException(
          'colors.${entry.key} 必須是 #RRGGBB 格式（收到：$v）',
        );
      }
      colors[entry.key.toString()] = v.toUpperCase();
    }
  }

  // ⑤ 資產路徑（存在且在允許目錄內）＋ 桌布尺寸預檢。
  final assets = <String, String>{};
  final warnings = <String>[];
  final rawAssets = manifest['assets'];
  if (rawAssets != null) {
    if (rawAssets is! Map) {
      throw ThemePackException('theme.json 的 assets 必須是物件');
    }
    for (final entry in rawAssets.entries) {
      final path = entry.value;
      if (path is! String || path.isEmpty) {
        throw ThemePackException('assets.${entry.key} 必須是字串路徑');
      }
      if (!isSafeZipPath(path) || !_isAllowedPath(path)) {
        throw ThemePackException('assets.${entry.key} 路徑不允許：$path');
      }
      final file = byName[path];
      if (file == null) {
        throw ThemePackException('資產檔不存在：$path');
      }
      if (path.startsWith('wallpaper/')) {
        final dims = _inspectWallpaper(file.content, path, limits);
        if (dims.width < 1080 || dims.height < 1080) {
          warnings.add('$path 尺寸小於建議值 1080px');
        }
      }
      assets[entry.key.toString()] = path;
    }
  }

  // ⑤a 圖示覆寫（第五十七批）：只接受合法槽位；值為 Material 名稱字串，
  //     或 `{font: "...ttf", codepoint: "e001"}`（字型需隨包提供）。
  final icons = <String, String>{};
  final rawIcons = manifest['icons'];
  if (rawIcons != null) {
    if (rawIcons is! Map) {
      throw ThemePackException('theme.json 的 icons 必須是物件');
    }
    for (final entry in rawIcons.entries) {
      final slot = entry.key.toString();
      if (!kAllIconSlotNames.contains(slot)) {
        throw ThemePackException('icons.$slot 不是合法的圖示槽位');
      }
      final value = entry.value;
      if (value is String) {
        if (materialIconByName(value) == null) {
          throw ThemePackException('icons.$slot 的 Material 圖示名稱無效：$value');
        }
        icons[slot] = value;
      } else if (value is Map) {
        final font = value['font'];
        final cp = value['codepoint'];
        if (font is! String || font.isEmpty || !font.endsWith('.ttf')) {
          throw ThemePackException('icons.$slot.font 必須是 .ttf 檔名');
        }
        final codePoint = cp is String ? int.tryParse(cp, radix: 16) : null;
        if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) {
          throw ThemePackException('icons.$slot.codepoint 必須是有效的十六進位碼位');
        }
        if (!byName.containsKey('fonts/$font')) {
          throw ThemePackException('icons.$slot 指定的字型不在包內：fonts/$font');
        }
        icons[slot] = 'font:$font:${codePoint.toRadixString(16)}';
      } else {
        throw ThemePackException('icons.$slot 的值格式無效');
      }
    }
  }

  return ThemePack(
    id: id,
    name: name,
    author: author,
    license: license,
    attribution: attribution,
    description: manifest['description'] is String
        ? manifest['description'] as String
        : null,
    colors: colors,
    assets: assets,
    icons: icons,
    warnings: warnings,
  );
}

class _Dims {
  const _Dims(this.width, this.height);
  final int width;
  final int height;
}

/// 桌布檔頭預檢（PNG／WebP；拒 GIF／APNG）。
_Dims _inspectWallpaper(
  Uint8List bytes,
  String path,
  ThemePackLimits limits,
) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.gif')) {
    throw ThemePackException('不支援 GIF 桌布：$path');
  }
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
      throw ThemePackException('PNG 檔頭不完整：$path');
    }
    final width = (bytes[16] << 24) |
        (bytes[17] << 16) |
        (bytes[18] << 8) |
        bytes[19];
    final height = (bytes[20] << 24) |
        (bytes[21] << 16) |
        (bytes[22] << 8) |
        bytes[23];
    _checkDims(width, height, limits, path);
    return _Dims(width, height);
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
      throw ThemePackException('WebP 檔頭不完整：$path');
    }
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    int width;
    int height;
    if (chunk == 'VP8 ') {
      width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
      height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
    } else if (chunk == 'VP8L') {
      final bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) |
          (bytes[24] << 24);
      width = (bits & 0x3FFF) + 1;
      height = ((bits >> 14) & 0x3FFF) + 1;
    } else if (chunk == 'VP8X') {
      width = (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1;
      height = (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1;
    } else {
      throw ThemePackException('不支援的 WebP 類型（$chunk）：$path');
    }
    _checkDims(width, height, limits, path);
    return _Dims(width, height);
  }
  throw ThemePackException('桌布僅支援 PNG／JPEG／WebP（靜態）：$path');
}

void _checkDims(int width, int height, ThemePackLimits limits, String path) {
  if (width <= 0 || height <= 0) {
    throw ThemePackException('圖片尺寸無效：$path');
  }
  if (width > limits.maxWallpaperDimension ||
      height > limits.maxWallpaperDimension) {
    throw ThemePackException(
      '桌布長邊超過 ${limits.maxWallpaperDimension}px：$path',
    );
  }
  if (width * height > limits.maxWallpaperPixels) {
    throw ThemePackException('桌布像素數超過上限：$path');
  }
}

bool _isAllowedPath(String name) {
  final lower = name.toLowerCase();
  if (lower == 'theme.json') return true;
  if (lower == 'license.txt') return true;
  if (lower.startsWith('wallpaper/')) {
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }
  if (lower.startsWith('fonts/')) {
    return lower.endsWith('.ttf') || lower.endsWith('.otf');
  }
  if (lower.startsWith('icons/')) {
    return lower.endsWith('.svg');
  }
  return false;
}

String _requireString(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v is! String || v.isEmpty) {
    throw ThemePackException('theme.json 缺少必要欄位：$key');
  }
  return v;
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
