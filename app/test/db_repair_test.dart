// 任務（人類批准 2026-11-06）— db_repair 的純邏輯測試。
// 背景：logcat 定案「Row too big to fit into CursorWindow」於
// `SELECT * FROM box_device_keys_list` → SDK 裝置金鑰快取永遠載不出。
// 本測試以 sqflite_common_ffi 建構同一 schema，驗證：
//   ①過大資料列被刪、正常資料列保留
//   ②修復後整表 SELECT（SDK getAllValues 同款）不再炸
//   ③表不存在（全新安裝）不擲例外、不刪任何東西
//   ④沒有過大資料列時 zero-op
// 邊界：不讀解析任何金鑰內容，v 一律用合成字串（JSON 形狀即可，無金鑰）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homing/db_repair.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _ddl = 'CREATE TABLE box_device_keys_list '
    '(k TEXT PRIMARY KEY NOT NULL, v TEXT)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Database, DeviceKeysCacheRepairReport)> run({
    required List<(String, String)> rows,
    int maxRowBytes = 64,
    bool createTable = true,
  }) async {
    // 每個測試獨立的暫存檔 DB（:memory: 在 ffi factory 下跨 open 共用）。
    final dir = Directory.systemTemp.createTempSync('ring_db_repair_test');
    final database = await databaseFactoryFfiNoIsolate.openDatabase(
      '${dir.path}/ring.db',
    );
    if (createTable) {
      await database.execute(_ddl);
      final batch = database.batch();
      for (final (k, v) in rows) {
        batch.insert('box_device_keys_list', {'k': k, 'v': v});
      }
      await batch.commit();
    }
    // 呼叫端保證不擲例外——整測試同時驗證這一點。
    final report = await repairOversizedDeviceKeysRows(
      database,
      maxRowBytes: maxRowBytes,
    );
    return (database, report);
  }

  group('repairOversizedDeviceKeysRows（金鑰快取髒資料修復）', () {
    test('①過大資料列被刪、正常資料列保留，且整表 SELECT 不再炸', () async {
      final (database, report) = await run(rows: [
        // 模擬正常使用者的 DeviceKeysList JSON（遠小於門檻）。
        ('@alice:matrix.org', '{"user_id":"@alice:matrix.org"}'),
        // 模擬炸掉整表的髒資料（>64 bytes）。
        ('@legacy:matrix.org', 'x' * 1024),
        ('@bob:example.net', '{}'),
      ]);

      expect(report.cleaned, isTrue);
      expect(report.deletedKeys, ['@legacy:matrix.org']);
      expect(report.oversized.keys, ['@legacy:matrix.org']);
      expect(report.failed, isNull);

      // 過濾後整表查詢成功（原本會炸的打破點）。
      final after = await database.query('box_device_keys_list');
      expect(after.length, 2);
      expect(after.map((r) => r['k']),
          unorderedEquals(['@alice:matrix.org', '@bob:example.net']));
    });

    test('②沒有過大資料列 → zero-op（不刪任何東西）', () async {
      final (database, report) = await run(rows: [
        ('@alice:matrix.org', '{"user_id":"@alice:matrix.org"}'),
      ]);

      expect(report.cleaned, isFalse);
      expect(report.deletedKeys, isEmpty);
      expect(report.failed, isNull);
      final after = await database.query('box_device_keys_list');
      expect(after.length, 1);
    });

    test('③表不存在（全新安裝情境）→ 不擲例外、nothing removed', () async {
      final (database, report) = await run(rows: const [], createTable: false);

      expect(report.failed, isNotNull);
      expect(report.cleaned, isFalse);
      // 靜默通過後資料庫仍可用（登入流程不受影響）。
      await database.execute(_ddl);
    });
  });
}
