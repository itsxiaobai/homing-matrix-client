// 2.4 skeleton — 離線訊息佇列（本地 SQLite，網路恢復後由 SDK sync 觸發送出）
//
// 任務 4 升級（人類批准 2026-11-07）：附件也入佇列（圖片／影片／任何檔），
// 文字與附件**依送出時的原始順序**入列（chat_screen 送信序列鏈保證），
// drain 也照 id ASC 依序送出——先進先出，順序不亂。
//
// 所有送出仍呼叫 SDK 官方 `Room.sendTextEvent` / `Room.sendFileEvent`，
// 準備／加密共用 media_upload.dart 官方鏈路；App 端不寫加密邏輯。
//
// 隱私注意（人類知情批准 2026-11-07）：附件以「來源檔案路徑」入列
// （file_picker／相機皆留有真實路徑）；無路徑時才存 bytes BLOB，
// 且僅收 < 5MB（避免 SQLite 膨脹）。與現行文字佇列同級的本地儲存。
import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:matrix/matrix.dart';
import 'media_upload.dart';

class OfflineQueue {
  static Database? _db;

  /// v2（任務 4，人類批准 2026-11-07）：新增附件欄位＋重試計數。
  static Future<Database> _open() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      '${await getDatabasesPath()}/offline_queue.db',
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE queue ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'room_id TEXT NOT NULL, '
          'body TEXT NOT NULL, '
          'kind TEXT NOT NULL DEFAULT "text", '
          'file_name TEXT, '
          'file_path TEXT, '
          'bytes BLOB, '
          'attempts INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL)',
        );
      },
      onUpgrade: (db, from, to) async {
        // 既有 v1 資料（純文字）逐一補欄，不清不重存。
        for (final col in const [
          ['kind', 'TEXT NOT NULL DEFAULT "text"'],
          ['file_name', 'TEXT'],
          ['file_path', 'TEXT'],
          ['bytes', 'BLOB'],
          ['attempts', 'INTEGER NOT NULL DEFAULT 0'],
        ]) {
          try {
            await db.execute('ALTER TABLE queue ADD COLUMN ${col[0]} ${col[1]}');
          } catch (_) {
            // 已存在（如 v2 裝置升級重跑）→ 忽略。
          }
        }
      },
    );
    return _db!;
  }

  /// 將一則訊息排入離線佇列。
  static Future<int> enqueue(String roomId, String body) async {
    final db = await _open();
    return db.insert('queue', {
      'room_id': roomId,
      'body': body,
      'kind': 'text',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 無路徑附件的 BLOB 收件上限（避免 SQLite 膨脹；人類批准 2026-11-07）。
  /// 有真實路徑的附件（file_picker／相機）不受此限。
  static const int kRingOfflineQueueBlobMaxBytes = 5 * 1024 * 1024;

  /// 將一個附件排入離線佇列（任務 4）。回傳 row id；bytes 超限且無路徑
  /// 時回 -1（不入列，呼叫端顯示失敗原因）。
  ///
  /// 與文字同一張表、同一條 id 序列 → drain（id ASC）自然依入列順序送出，
  /// 滿足「傳檔時送文字也入佇列、照順序完成」（人類批准 2026-11-07）。
  static Future<int> enqueueAttachment({
    required String roomId,
    required String name,
    required Uint8List bytes,
    String? path,
  }) async {
    final db = await _open();
    // 優先存路徑（零 DB 膨脹）；無路徑 → 小檔存 BLOB；再不行 → 拒收。
    final usePath = path != null && path.isNotEmpty;
    final storeBytes = (!usePath && bytes.lengthInBytes < kRingOfflineQueueBlobMaxBytes)
        ? bytes
        : null;
    if (!usePath && storeBytes == null) {
      return -1;
    }
    return db.insert('queue', {
      'room_id': roomId,
      'body': name,
      'kind': 'attachment',
      'file_name': name,
      'file_path': usePath ? path : null,
      'bytes': storeBytes,
      'attempts': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 取得所有待送訊息（舊的在前）。
  static Future<List<Map<String, Object?>>> pending() async {
    final db = await _open();
    return db.query('queue', orderBy: 'id ASC');
  }

  /// 移除已成功送出的佇列項目。
  static Future<void> remove(int id) async {
    final db = await _open();
    await db.delete('queue', where: 'id = ?', whereArgs: [id]);
  }

  /// 自動重試上限（任務 4，人類批准 2026-11-07）：attempts >= 上限的列
  /// 不再自動送（保留在表內，供問題排查），避免壞檔／壞房無限打 homeserver。
  static const int kRingOfflineQueueMaxAttempts = 5;

  /// 嘗試送出所有待送訊息；成功者移除，失敗者保留（attempts++）供下次
  /// 重試。由 RoomsScreen 的 onSync 監聽觸發（sync 成功代表連線恢復）。
  ///
  /// **依序送出**：id ASC（＝入列順序，文字與附件混排同序）、逐列 await，
  /// 前一則失敗**不阻斷**下一則（失敗件下次 sync 再試）。
  static Future<void> drain(Client client) async {
    final rows = await pending();
    for (final row in rows) {
      final id = row['id'] as int;
      final roomId = row['room_id'] as String;
      final body = row['body'] as String;
      final kind = (row['kind'] as String?) ?? 'text';
      final attempts = (row['attempts'] as int?) ?? 0;
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      if (attempts >= kRingOfflineQueueMaxAttempts) {
        continue; // 超上限：不自動重試（列保留）。
      }
      try {
        if (kind == 'attachment') {
          await _drainAttachment(client, room, row);
        } else {
          await room.sendTextEvent(body);
        }
        await remove(id);
      } catch (_) {
        // 保留供下次 sync 重試（attempts++ 由 [pending] 讀者於下方更新）。
        try {
          final db = await _open();
          await db.update(
            'queue',
            {'attempts': attempts + 1},
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (_) {}
      }
    }
  }

  /// 附件列送出（任務 4）：讀檔 → 圖片走官方 prepare → 加密房走官方
  /// encryptFileInBackground（App 端零自寫演算法）→ sendFileEvent。
  /// 準備／加密與 chat_screen `_sendOne` 共用同一批官方鏈路函式。
  static Future<void> _drainAttachment(
    Client client,
    Room room,
    Map<String, Object?> row,
  ) async {
    final name = (row['file_name'] as String?) ??
        (row['body'] as String?) ??
        'attachment';
    final storedPath = row['file_path'] as String?;
    final storedBytes = row['bytes'] as Uint8List?;
    Uint8List bytes;
    if (storedPath != null && File(storedPath).existsSync()) {
      bytes = await File(storedPath).readAsBytes();
    } else if (storedBytes != null) {
      bytes = storedBytes;
    } else {
      // 來源檔已被清理（file_picker 逾時清 cache 等）→ 不可送，丟錯讓
      // drain 計 attempts（很快會到上限停手，不無限重試）。
      throw StateError('attachment source missing ($storedPath)');
    }
    final isImage = isImageFileName(name);
    final isVideo = isVideoFileName(name);
    var sendBytes = bytes;
    ImagePreparation? prep;
    MatrixImageFile? thumbnail;
    int? width;
    int? height;
    String? mime;
    if (isImage) {
      prep = await prepareImageInBackground(bytes: bytes, name: name);
      sendBytes = prep?.upload?.bytes ?? bytes;
      width = prep?.upload?.width ?? prep?.width;
      height = prep?.upload?.height ?? prep?.height;
      mime = prep?.upload?.mimeType;
      thumbnail = prep?.thumbnail;
    }
    EncryptedFile? encrypted;
    if (room.encrypted) {
      encrypted = await encryptFileInBackground(sendBytes);
    }
    final file = buildUploadFile(
      bytes: sendBytes,
      name: name,
      isImage: isImage,
      isVideo: isVideo,
      image: prep,
      imageWidth: width,
      imageHeight: height,
      imageMimeType: mime,
      encrypted: encrypted,
    );
    await room.sendFileEvent(file, thumbnail: thumbnail);
  }

  /// 待送數量（供 UI 顯示 badge，skeleton）。
  static Future<int> count() async {
    final db = await _open();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM queue');
    return (r.first['c'] as int?) ?? 0;
  }
}
