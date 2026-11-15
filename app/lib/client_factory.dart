// 任務：Phase 1 / 1.3～1.4 — 客戶端與本地儲存（儲存方案 C，人類批准 2026-10-31）
//
// 組成（方案 C）：
// * sqflite：`MatrixSdkDatabase` 的行動端 SQLite 後端（資料庫檔存 app 目錄）。
// * flutter_secure_storage：SDK `MatrixSdkDatabase.init(secureStorage:)` 參數——
//   access token 與 SSSS cache 另存系統安全儲存（Keychain/Keystore），
//   DB 損毀時可恢復（SDK 官方支援，非本專案自製加密邏輯）。
// * 加密協議：完全由 SDK（Matrix 官方 vodozemac）處理；本檔不寫任何加密程式。
//
// 可匯出／可離開：資料均在本機 App 目錄與系統安全儲存；登出時 SDK 清除 session。
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/db_repair.dart';
import 'package:sqflite/sqflite.dart';

/// 建立具持久化儲存的 Client（登入後 session／金鑰由 SDK 保存）。
///
/// 資料庫名稱固定 `ring`；同一裝置上的多帳號情境留待後續階段（待人工決定）。
Future<Client> createPersistentClient() async {
  final db = await openDatabase(
    '${await getDatabasesPath()}/ring.db',
    version: 1,
  );
  // 任務 2026-11-06（人類批准）：清除裝置金鑰快取中會炸掉整表載入的
  // 過大資料列（「Row too big to fit into CursorWindow」）；詳見
  // db_repair.dart 檔頭。失敗也不影響登入流程（內部保證不擲例外）。
  final repair = await repairOversizedDeviceKeysRows(db);
  if (repair.cleaned) {
    Logs().i(
      'db_repair: removed ${repair.deletedKeys.length} oversized device keys '
      'cache rows (${repair.oversized})',
    );
  } else if (repair.failed != null) {
    Logs().w('db_repair: scan failed, nothing removed: ${repair.failed}');
  }
  final secureStorage = const FlutterSecureStorage();
  // flutter_secure_storage 的方法帶選擇性參數；包一層以符合 SDK 的 record 簽名。
  final matrixDb = await MatrixSdkDatabase.init(
    'ring',
    database: db,
    secureStorage: (
      read: (key) => secureStorage.read(key: key),
      write: (key, value) => secureStorage.write(key: key, value: value),
      delete: (key) => secureStorage.delete(key: key),
    ),
  );
  return Client(
    'ring',
    database: matrixDb,
    // 第二十六批（人類拍板，公開聊天室分類根因修）：SDK 14.2.0 記憶體預載
    // 清單（client.dart L275-284 重要 state）**不含 m.room.join_rules**——
    // App 重啟後 partial 房間的 `Room.joinRules` 恆 null → 聯絡人分類把
    // 公開房全落「群組」（實機 47 房全誤證據）。加入官方構造參數
    // importantStateEvents 後，sync 取得的 join_rules 由 SDK 永久存進
    // preload box、重啟即載入記憶體。既有（歷史 sync）房間的 join_rules
    // 不在 preload box → contacts_screen 另以官方單一 state 端點補查
    // （session 內，人類拍板）。
    importantStateEvents: {EventTypes.RoomJoinRules},
  );
}

/// 檢查 homeserver 相容性（規格版本、登入流程）。
/// 回傳 `null` 表示檢查通過；否則回傳可直接顯示給使用者的錯誤訊息。
///
/// 檢查用 Client 不落地（in-memory Hive，不寫檔）——僅用於 0.10 的連線檢查。
Future<String?> checkServer(Uri homeserverUrl) async {
  final client = createClient();
  try {
    await client.checkHomeserver(homeserverUrl);
    return null;
  } on MatrixException catch (e) {
    return '伺服器不相容（${e.error}）';
  } catch (e) {
    return '無法連線：請檢查位址與網路';
  }
}

/// 連線檢查用 Client（不落地；供 0.10 骨架）。
Client createClient() {
  final db = MatrixSdkDatabase.buildWithoutOpen('ring');
  return Client('ring', database: db);
}
