// 批次 B（人類指示 2026-11-01）— 聊天室釘選置頂。
// 儲存：Matrix account data（跨裝置同步）＋ 本機 sqflite（離線快取）。
// 事件類型：com.ring.pinned_rooms，內容 {"rooms": [roomId, ...]}。
// 草案，待人類設計定稿。
import 'package:sqflite/sqflite.dart';
import 'package:matrix/matrix.dart';

class PinnedRoomsStore {
  PinnedRoomsStore(this.client);

  final Client client;
  static const String _eventType = 'com.ring.pinned_rooms';
  Database? _db;

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    // v2：新增 `unpinned` tombstone 表——取消釘選時即使 account data
    // 寫回遠端失敗（_writeRemote 失敗被靜默），下一次 sync() 聯集合併
    // 也不會再「復活」該釘選（這是「無法取消釘選」的根因）。
    _db = await openDatabase(
      '${await getDatabasesPath()}/pinned_rooms.db',
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE pinned (room_id TEXT PRIMARY KEY, pinned_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE unpinned (room_id TEXT PRIMARY KEY, unpinned_at INTEGER NOT NULL)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS unpinned (room_id TEXT PRIMARY KEY, unpinned_at INTEGER NOT NULL)',
          );
        }
      },
    );
    return _db!;
  }

  /// 從本機快取載入釘選清單。
  Future<Set<String>> loadLocal() async {
    final db = await _openDb();
    final rows = await db.query('pinned');
    return rows.map((r) => r['room_id'] as String).toSet();
  }

  /// 從 Matrix account data 載入釘選清單。
  Set<String> loadRemote() {
    final ev = client.accountData[_eventType];
    final rooms = ev?.content['rooms'];
    if (rooms is List) {
      return rooms.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  /// 本機「曾明確取消釘選」的房間（tombstone；防遠端殘值復活）。
  Future<Set<String>> loadTombstones() async {
    final db = await _openDb();
    final rows = await db.query('unpinned');
    return rows.map((r) => r['room_id'] as String).toSet();
  }

  /// 合併本機與遠端（聯集），並寫回兩者。
  Future<Set<String>> sync() async {
    final local = await loadLocal();
    final remote = loadRemote();
    final tombstones = await loadTombstones();
    // tombstone 優先：已明確取消者即使遠端（可能的殘值）也不再合併。
    final merged = <String>{...local, ...remote}..removeAll(tombstones);
    await _writeLocal(merged);
    await _writeRemote(merged);
    return merged;
  }

  Future<void> _writeLocal(Set<String> ids) async {
    final db = await _openDb();
    await db.delete('pinned');
    for (final id in ids) {
      await db.insert('pinned', {
        'room_id': id,
        'pinned_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _writeTombstones(Set<String> ids) async {
    final db = await _openDb();
    await db.delete('unpinned');
    for (final id in ids) {
      await db.insert('unpinned', {
        'room_id': id,
        'unpinned_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _writeRemote(Set<String> ids) async {
    final uid = client.userID;
    if (uid == null) return;
    try {
      await client.setAccountData(uid, _eventType, {'rooms': ids.toList()});
    } catch (_) {
      // homeserver 不支援 account data 時忽略；本機快取仍有效。
    }
  }

  Future<void> pin(String roomId) async {
    final local = await loadLocal();
    final remote = loadRemote();
    final tombstones = await loadTombstones();
    tombstones.remove(roomId); // 重新釘選 → 清掉 tombstone。
    final merged = <String>{...local, ...remote, roomId};
    await _writeLocal(merged);
    await _writeRemote(merged);
    await _writeTombstones(tombstones);
  }

  Future<void> unpin(String roomId) async {
    final local = await loadLocal();
    final remote = loadRemote();
    final tombstones = await loadTombstones()..add(roomId);
    final merged = <String>{...local, ...remote}..remove(roomId);
    await _writeLocal(merged);
    await _writeRemote(merged);
    await _writeTombstones(tombstones);
  }

  Future<bool> isPinned(String roomId) async {
    final ids = await loadLocal();
    if (ids.contains(roomId)) return true;
    return loadRemote().contains(roomId);
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}
