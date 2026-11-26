// 主題包（zip）安裝：解壓資產 → 本機主題目錄 → 登錄主題（藍圖 §九第 13 項）。
//
// 與貼圖包相同的安全前提：**只安裝已通過 `parseThemePack` 驗證的包**
// （本檔不重複驗證，呼叫端必須先驗）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'app_settings.dart';
import 'theme_pack_importer.dart';

/// 安裝結果。
class ThemePackInstallResult {
  const ThemePackInstallResult({
    required this.packId,
    required this.packName,
    required this.wallpaperPath,
    required this.seed,
    required this.warnings,
  });

  final String packId;
  final String packName;

  /// 已安裝的桌布路徑（無則 null）。
  final String? wallpaperPath;

  /// 種子色（`RRGGBB`，無則 null）。
  final String? seed;

  final List<String> warnings;
}

/// 安裝主題包：解壓資產到本機、登錄 `themes` 表、並保存 `theme.json` 全文
/// （供日後同步或重裝還原）。
Future<ThemePackInstallResult> installThemePack({
  required ThemePack pack,
  required Uint8List zipBytes,
  required Directory themesDir,
}) async {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final dir = Directory('${themesDir.path}/${pack.id}');
  await dir.create(recursive: true);

  String? wallpaperPath;
  final assets = pack.assets;
  final wallpaperKey = assets.containsKey('wallpaper_light')
      ? 'wallpaper_light'
      : (assets.containsKey('wallpaper_dark') ? 'wallpaper_dark' : null);

  for (final entry in assets.entries) {
    final rel = entry.value;
    final file = archive.findFile(rel);
    if (file == null) {
      continue;
    }
    final target = File('${dir.path}/${rel.split('/').last}');
    await target.writeAsBytes(file.content, flush: true);
    if (entry.key == wallpaperKey) {
      wallpaperPath = target.path;
    }
  }

  // 種子色：主題色以無 `#` 的 `RRGGBB` 儲存（沿用既有 `themes.seed` 格式）。
  final seed = pack.colors['seed']?.replaceFirst('#', '');

  // 登錄主題（名稱／種子色／桌布）。
  final themeId = await AppSettings.addTheme(
    pack.name,
    seed: seed,
    wallpaper: wallpaperPath,
  );

  // 第五十七批：把圖示覆寫另存一份（以 themes.id 為 key，供「套用主題」即時讀取）。
  if (pack.icons.isNotEmpty) {
    await AppSettings.set('theme_icons_$themeId', jsonEncode(pack.icons));
  }

  // 保存 theme.json 全文（同步／重裝還原用）。
  await AppSettings.set(
    'theme_pack_${pack.id}',
    jsonEncode(<String, dynamic>{
      'id': pack.id,
      'name': pack.name,
      'author': pack.author,
      'license': pack.license,
      'attribution': pack.attribution,
      'colors': pack.colors,
      'assets': pack.assets,
      'icons': pack.icons, // 第五十七批：圖示變數化（主題包可覆換）
    }),
  );

  return ThemePackInstallResult(
    packId: pack.id,
    packName: pack.name,
    wallpaperPath: wallpaperPath,
    seed: seed,
    warnings: pack.warnings,
  );
}
