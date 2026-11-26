// 任務（人類批准 2026-11-06）：啟動時修復裝置金鑰快取的過大資料列。
//
// 背景（logcat 定案，見對話 2026-11-06）：
//   E SQLiteQuery: Row too big to fit into CursorWindow requiredPos=82,
//     totalRows=83; query: SELECT * FROM box_device_keys_list
//   SDK 啟動時整表 `SELECT *`（matrix_sdk_database.dart →
//   `getUserDeviceKeys` → Box.getAllValues）載入裝置金鑰快取；單筆
//   `v`（DeviceKeysList 的 JSON 字串）超過 Android CursorWindow（約
//   2MB）上限時整個查詢擲例外 → `_userDeviceKeys` 永遠空 Map →
//   診斷面板「userDeviceKeys 載入／self device 在快取」永遠 false、
//   outbound megolm session 建立時成員查詢每次空手而歸（傳送慢）。
//
// 本檔邊界（AGENTS.md）：**純 SQL 清除公開金鑰快取髒資料**。
// 不讀取、不解析 `v` 的內容（全部只在 SQL 端以 length() 度量）；
// 不碰任何金鑰交換／簽章／解密邏輯。被刪的資料是「伺服器上有的公開
// 金鑰快取」，SDK 於下一次 sync 完成 `updateUserDeviceKeys()` 時自動
// 重新 query 回填，無資料遺失風險。
import 'package:sqflite/sqlite_api.dart';

/// 單筆快取資料列的安全上限（bytes）。正常單一使用者的
/// DeviceKeysList JSON 只有數 KB；超過此值＝舊版累積的髒資料，
/// 並足以炸掉整表讀取（CursorWindow 上限約 2MB，取一半保守值）。
const int kRingMaxDeviceKeysRowBytes = 1 << 20; // 1MB

/// 修復結果（供初始化日誌／測試判斷；不顯示任何金鑰內容）。
class DeviceKeysCacheRepairReport {
  const DeviceKeysCacheRepairReport({
    required this.deletedKeys,
    required this.oversized,
    this.failed,
  });

  /// 實際刪除的 `k`（= Matrix user id；非金鑰內容）。
  final List<String> deletedKeys;

  /// 偵測到的過長資料列：`k` -> `length(v)`。
  final Map<String, int> oversized;

  /// 排查本身失敗的原因（例如全新安裝時表尚未建立、其他 SQL 錯誤）；
  /// null＝排查成功執行。失敗時不在本次刪除任何資料。
  final String? failed;

  bool get cleaned => deletedKeys.isNotEmpty;
}

/// 掃描並刪除 `box_device_keys_list` 中過大的資料列。
///
/// 以 `SELECT k, length(v)` 度量（SQLite 端計算長度，不把大字串傳回
/// CursorWindow，因此本查詢即使存在超過 2MB 的資料列也不會炸）。
/// 只刪除 `length(v) > [maxRowBytes]` 的 `k`；其餘資料原樣保留。
/// 本函式保證不擲例外（失敗一律回 [DeviceKeysCacheRepairReport.failed]），
/// 呼叫端可以直接 await，不影響登入初始化流程。
Future<DeviceKeysCacheRepairReport> repairOversizedDeviceKeysRows(
  Database db, {
  int maxRowBytes = kRingMaxDeviceKeysRowBytes,
  String table = 'box_device_keys_list',
}) async {
  List<Map<String, Object?>> rows;
  try {
    rows = await db.rawQuery('SELECT k, length(v) AS len FROM `$table`');
  } catch (e) {
    // 全新安裝時表尚未建立（SDK 於 BoxCollection.open 建立）等情境：
    // 沒有東西可修，靜默通過。
    return DeviceKeysCacheRepairReport(
      deletedKeys: const [],
      oversized: const {},
      failed: '$e',
    );
  }

  final oversized = <String, int>{};
  for (final row in rows) {
    final k = row['k'];
    final len = row['len'];
    if (k is String && len is int && len > maxRowBytes) {
      oversized[k] = len;
    }
  }
  if (oversized.isEmpty) {
    return DeviceKeysCacheRepairReport(
      deletedKeys: const [],
      oversized: const {},
    );
  }

  try {
    final keys = oversized.keys.toList();
    final placeholders = List.filled(keys.length, '?').join(', ');
    await db.delete(
      table,
      where: 'k IN ($placeholders)',
      whereArgs: keys,
    );
    return DeviceKeysCacheRepairReport(
      deletedKeys: keys,
      oversized: oversized,
    );
  } catch (e) {
    return DeviceKeysCacheRepairReport(
      deletedKeys: const [],
      oversized: oversized,
      failed: '$e',
    );
  }
}
