// 批次 C（人類指示 2026-11-01）— 自訂背景／主題／字型／貼圖 的本機設定儲存。
// 使用 sqflite（已依賴）；所有偏好本機儲存，不送伺服器。
// 草案，待人類設計定稿。
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class AppSettings {
  AppSettings._();
  static Database? _db;

  /// 第二十五批：頭像移除旗標 kv key（settings_screen 既有字面值
  /// `own_avatar_removed` 抽成共用常數——首頁頭像與設定頁共用同一旗標，
  /// 避免動字面值後出現讀寫不一致；勿隨意改名）。
  static const String ownAvatarRemovedFlag = 'own_avatar_removed';


  static Future<Database> _open() async {
    if (_db != null) return _db!;
    // v3：新增 `drafts`（Suggestion #7＋#12 訊息草稿；per-room 本機持久化）。
    // 草稿僅**本機**儲存，不送伺服器。
    // v4（批次十二①⑤）：新增 `themes`（我的主題＝桌布＋種子色的本機命名組合，
    // 「創作者設計主題」v0；zip 打包格式見 THEME_FORMAT.md，zip 讀取需
    // archive 依賴待批准，先以分項選取儲存）＋`announcement_rooms`
    // （公告房間旗標——首頁緊急訊息橫幅的觸發來源，Phase 4 草案）。
    _db = await openDatabase(
      '${await getDatabasesPath()}/app_settings.db',
      version: 4,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE room_bg (room_id TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE stickers (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL, name TEXT)',
        );
        await db.execute(
          'CREATE TABLE hidden_rooms (room_id TEXT PRIMARY KEY, hidden_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE drafts (room_id TEXT PRIMARY KEY, body TEXT NOT NULL)',
        );
        await _createV4Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS hidden_rooms (room_id TEXT PRIMARY KEY, hidden_at INTEGER NOT NULL)',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS drafts (room_id TEXT PRIMARY KEY, body TEXT NOT NULL)',
          );
        }
        if (oldVersion < 4) {
          await _createV4Tables(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createV4Tables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS themes (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'name TEXT NOT NULL, seed TEXT, wallpaper TEXT, created_at INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS announcement_rooms (room_id TEXT PRIMARY KEY, added_at INTEGER NOT NULL)',
    );
  }

  static Future<String?> get(String key) async {
    final db = await _open();
    final rows = await db.query('kv', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  static Future<void> set(String key, String value) async {
    final db = await _open();
    await db.insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> remove(String key) async {
    final db = await _open();
    await db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }

  // --- per-room background ---
  static Future<String?> getRoomBackground(String roomId) async {
    final db = await _open();
    final rows = await db.query('room_bg', where: 'room_id = ?', whereArgs: [roomId]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  static Future<void> setRoomBackground(String roomId, String value) async {
    final db = await _open();
    await db.insert('room_bg', {'room_id': roomId, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> clearRoomBackground(String roomId) async {
    final db = await _open();
    await db.delete('room_bg', where: 'room_id = ?', whereArgs: [roomId]);
  }

  // --- stickers ---
  static Future<List<({int id, String path, String? name})>> listStickers() async {
    final db = await _open();
    final rows = await db.query('stickers', orderBy: 'id ASC');
    return rows
        .map((r) => (id: r['id'] as int, path: r['path'] as String, name: r['name'] as String?))
        .toList();
  }

  static Future<int> addSticker(String path, {String? name}) async {
    final db = await _open();
    return db.insert('stickers', {'path': path, 'name': name});
  }

  static Future<void> removeSticker(int id) async {
    final db = await _open();
    await db.delete('stickers', where: 'id = ?', whereArgs: [id]);
  }

  // --- hidden rooms（Issues：增加隱藏／刪除對話；本機過濾） ---
  static Future<Set<String>> hiddenRooms() async {
    final db = await _open();
    final rows = await db.query('hidden_rooms');
    return rows.map((r) => r['room_id'] as String).toSet();
  }

  static Future<void> hideRoom(String roomId) async {
    final db = await _open();
    await db.insert('hidden_rooms', {
      'room_id': roomId,
      'hidden_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> unhideRoom(String roomId) async {
    final db = await _open();
    await db.delete('hidden_rooms', where: 'room_id = ?', whereArgs: [roomId]);
  }

  // --- 我的主題（批次十二①：創作者主題 v0＝桌布＋種子色本機組合） ---
  static Future<List<({int id, String name, String? seed, String? wallpaper})>>
      listThemes() async {
    final db = await _open();
    final rows = await db.query('themes', orderBy: 'created_at ASC');
    return rows
        .map(
          (r) => (
            id: r['id'] as int,
            name: r['name'] as String,
            seed: r['seed'] as String?,
            wallpaper: r['wallpaper'] as String?,
          ),
        )
        .toList();
  }

  static Future<int> addTheme(
    String name, {
    String? seed,
    String? wallpaper,
  }) async {
    final db = await _open();
    return db.insert('themes', {
      'name': name,
      'seed': seed,
      'wallpaper': wallpaper,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> removeTheme(int id) async {
    final db = await _open();
    await db.delete('themes', where: 'id = ?', whereArgs: [id]);
  }

  // --- 全域聊天室桌布（批次十二①：Colors／Your photos 兩入口；
  //     per-room 背景仍優先）。值格式與 room_bg 一致：'#RRGGBB' 或檔案路徑。 ---
  static Future<String?> getChatWallpaper() async {
    return get('chat_wallpaper');
  }

  static Future<void> setChatWallpaper(String value) async {
    await set('chat_wallpaper', value);
  }

  static Future<void> clearChatWallpaper() async {
    await remove('chat_wallpaper');
  }

  // --- 公告房間（批次十二⑤：首頁緊急訊息橫幅的觸發來源；本機旗標） ---
  static Future<Set<String>> announcementRooms() async {
    final db = await _open();
    final rows = await db.query('announcement_rooms');
    return rows.map((r) => r['room_id'] as String).toSet();
  }

  static Future<void> setAnnouncementRoom(String roomId, bool on) async {
    final db = await _open();
    if (!on) {
      await db.delete('announcement_rooms', where: 'room_id = ?', whereArgs: [roomId]);
      return;
    }
    await db.insert('announcement_rooms', {
      'room_id': roomId,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- per-room 訊息草稿（Suggestion #7＋#12；本機持久化） ---
  static Future<String?> getDraft(String roomId) async {    final db = await _open();
    final rows =
        await db.query('drafts', where: 'room_id = ?', whereArgs: [roomId]);
    if (rows.isEmpty) return null;
    return rows.first['body'] as String;
  }

  /// body 空字串＝清除草稿（送出後呼叫；避免殘留空列）。
  static Future<void> setDraft(String roomId, String body) async {
    final db = await _open();
    if (body.isEmpty) {
      await db.delete('drafts', where: 'room_id = ?', whereArgs: [roomId]);
      return;
    }
    await db.insert('drafts', {'room_id': roomId, 'body': body},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- 第三十五批 #6：緊急聯絡人（kv `emergency_contacts`，JSON 陣列的
  // Matrix user ID 清單；**本機**儲存不送伺服器） ---
  static Future<List<String>> emergencyContacts() async {
    final raw = await get('emergency_contacts');
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final v in decoded)
            if (v is String && v.isNotEmpty) v,
        ];
      }
    } catch (_) {
      // 損毀 → 視同未設定。
    }
    return const [];
  }

  static Future<void> setEmergencyContacts(List<String> userIds) async {
    await set('emergency_contacts', jsonEncode(userIds));
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
