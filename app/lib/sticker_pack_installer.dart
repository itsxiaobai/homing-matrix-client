// 貼圖包（zip）安裝——藍圖 Phase 3.2「zip 匯入流程（串流解壓 → 驗證 → 上傳媒體）」。
//
// 流程（STICKER_FORMAT.md §5 的本機部分）：
// 1. `parseStickerPack` 完成**所有**安全驗證（中央目錄掃描、路徑安全、白名單、
//    檔頭預檢）——本檔假設收到的 `StickerPack` 已通過驗證；
// 2. 解壓圖片到本機貼圖庫資料夾（供預覽與關鍵字建議）；
// 3. 以官方 `Client.uploadContent` 上傳至 homeserver，取得 `mxc://`；
// 4. 寫入本機貼圖庫（`app_settings.db` 的 `stickers` 表），記住 mxc 以便送出時
//    **不重複上傳**。
//
// 房間狀態事件（`m.room.image_pack`）與 account data（`m.image_pack.rooms`）
// 的寫入位置屬藍圖 3.11「個人貼圖庫」**待人工決定**，本檔只提供
// `buildPackContent`（純函式，見 `sticker_pack_importer.dart`），未接 UI。
import 'dart:io';

import 'package:matrix/matrix.dart';

import 'app_settings.dart';
import 'sticker_pack_importer.dart';
import 'sticker_pack_store.dart';

/// 匯入結果（供 UI 顯示摘要）。
class StickerPackInstallResult {
  const StickerPackInstallResult({
    required this.packId,
    required this.packName,
    required this.imported,
    required this.uploaded,
    required this.warnings,
  });

  final String packId;
  final String packName;

  /// 匯入張數。
  final int imported;

  /// 成功上傳 homeserver 的張數（部分失敗時小於 imported）。
  final int uploaded;

  final List<String> warnings;
}

/// 安裝貼圖包（解壓到本機＋上傳 homeserver＋寫入本機貼圖庫）。
Future<StickerPackInstallResult> installStickerPack({
  required Client client,
  required StickerPack pack,
  required Directory libraryDir,
}) async {
  final dir = Directory('${libraryDir.path}/${_safeDirName(pack.id)}');
  await dir.create(recursive: true);

  var uploaded = 0;
  final packItems = <Map<String, dynamic>>[];
  for (final item in pack.stickers) {
    final ext = item.mimeType == 'image/png' ? '.png' : '.webp';
    final file = File('${dir.path}/${item.shortcode}$ext');
    await file.writeAsBytes(item.bytes, flush: true);

    String? mxc;
    try {
      final uri = await client.uploadContent(
        item.bytes,
        filename: '${item.shortcode}$ext',
        contentType: item.mimeType,
      );
      mxc = uri.toString();
      uploaded++;
    } catch (_) {
      // 上傳失敗不中斷整包：該貼圖仍留在本機庫，送出時會再嘗試上傳。
    }

    packItems.add(<String, dynamic>{
      'shortcode': item.shortcode,
      'body': item.body,
      'url': mxc ?? '',
      'info': <String, dynamic>{
        'w': item.width,
        'h': item.height,
        'mimetype': item.mimeType,
        'size': item.bytes.length,
      },
    });

    await AppSettings.addSticker(
      file.path,
      // 顯示名稱：manifest 的 `name`（缺漏＝shortcode）。
      name: item.name ?? item.shortcode,
      mxcUrl: mxc,
      body: item.body,
      packId: pack.id,
      // 搜尋關鍵字：創作者於 manifest 指定（建議功能優先比對）＋shortcode
      // 本身（保底：即使創作者沒給關鍵字，短碼仍可被建議到）。
      keywords: item.keywords.contains(item.shortcode)
          ? item.keywords
          : [...item.keywords, item.shortcode],
    );
  }

  // 藍圖 3.11（人類決定：專用私密貼圖庫房間）→ 保存 pack 中繼資料，
  // 之後可一鍵把 pack 事件寫進貼圖庫房間（跨裝置共用）。
  try {
    await StickerPackStore.savePackMeta(pack, packItems);
  } catch (_) {
    // 儲存失敗不影響本次匯入（使用者仍可在本機使用貼圖）。
  }

  return StickerPackInstallResult(
    packId: pack.id,
    packName: pack.name,
    imported: pack.stickers.length,
    uploaded: uploaded,
    warnings: pack.warnings,
  );
}

/// 目錄名安全化（只保留英數字與 `._-`；避免路徑穿越與非法字元）。
String _safeDirName(String id) {
  final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final trimmed = cleaned.isEmpty ? 'pack' : cleaned;
  return trimmed.length <= 64 ? trimmed : trimmed.substring(0, 64);
}
