// zip 安全檢查共用模組（貼圖包與主題包共用同一份實作）。
//
// 只做「不解壓」階段的安全判讀：
// - 讀 **中央目錄**（central directory）取得每個 entry 的名稱、壓縮後大小、
//   解壓後大小 → 檔案數、單檔大小、總大小、壓縮比上限。
// - 路徑安全：絕對路徑、`..`、反斜線、符號連結（由呼叫端依 ArchiveFile 判斷）。
//
// 不涉及任何加密或協定邏輯；純位元組判讀。
import 'dart:convert';
import 'dart:typed_data';

/// 中央目錄中的一個 entry。
class ZipEntryInfo {
  const ZipEntryInfo({
    required this.name,
    required this.compressedSize,
    required this.uncompressedSize,
  });

  final String name;
  final int compressedSize;
  final int uncompressedSize;
}

/// 讀取 zip 的中央目錄（回傳空清單＝非有效 zip）。
///
/// 實作說明：掃描 EOCD（signature `0x06054b50`）→ 由其取得中央目錄偏移與
/// 筆數 → 逐筆讀 `0x02014b50` 的中央目錄記錄（壓縮後／解壓後大小、檔名長度…）。
List<ZipEntryInfo> readZipEntries(Uint8List bytes) {
  // 找 EOCD（由尾端往前最多 65557 bytes）。
  var eocd = -1;
  final min = bytes.length < 65557 ? 0 : bytes.length - 65557;
  for (var i = bytes.length - 22; i >= min; i--) {
    if (i < 0) break;
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4B &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return const [];

  final count = bytes[eocd + 10] | (bytes[eocd + 11] << 8);
  var offset = bytes[eocd + 16] |
      (bytes[eocd + 17] << 8) |
      (bytes[eocd + 18] << 16) |
      (bytes[eocd + 19] << 24);

  final entries = <ZipEntryInfo>[];
  for (var i = 0; i < count; i++) {
    if (offset + 46 > bytes.length) break;
    if (!(bytes[offset] == 0x50 &&
        bytes[offset + 1] == 0x4B &&
        bytes[offset + 2] == 0x01 &&
        bytes[offset + 3] == 0x02)) {
      break;
    }
    final compressed = bytes[offset + 20] |
        (bytes[offset + 21] << 8) |
        (bytes[offset + 22] << 16) |
        (bytes[offset + 23] << 24);
    final uncompressed = bytes[offset + 24] |
        (bytes[offset + 25] << 8) |
        (bytes[offset + 26] << 16) |
        (bytes[offset + 27] << 24);
    final nameLen = bytes[offset + 28] | (bytes[offset + 29] << 8);
    final extraLen = bytes[offset + 30] | (bytes[offset + 31] << 8);
    final commentLen = bytes[offset + 32] | (bytes[offset + 33] << 8);
    final nameBytes = bytes.sublist(offset + 46, offset + 46 + nameLen);
    entries.add(ZipEntryInfo(
      name: utf8.decode(nameBytes, allowMalformed: true),
      compressedSize: compressed,
      uncompressedSize: uncompressed,
    ));
    offset += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

/// 路徑是否安全（無絕對路徑、無 `..`、無反斜線、非空）。
bool isSafeZipPath(String name) {
  if (name.isEmpty) return false;
  if (name.startsWith('/')) return false;
  if (name.contains('\\')) return false;
  if (name.contains(':')) return false;
  if (name.split('/').contains('..')) return false;
  return true;
}
