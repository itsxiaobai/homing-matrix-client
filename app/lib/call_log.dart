// 通話紀錄（本機 SQLite，零新依賴；草案，待人類設計定稿）。
// 記錄每次通話的對象、方向、開始時間、時長與結果；僅本機儲存，不送伺服器。
import 'package:sqflite/sqflite.dart';

class CallLogEntry {
  CallLogEntry({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.peerName,
    required this.roomId,
    required this.isGroup,
    required this.startedAt,
    required this.durationMs,
    required this.outcome,
  });

  final int id;
  final String direction; // 'outgoing' / 'incoming'
  final String peerId;
  final String peerName;
  final String roomId;
  final bool isGroup;
  final DateTime startedAt;
  final int durationMs;
  final String outcome; // 'completed' / 'missed' / 'rejected' / 'failed'
}

class CallLog {
  CallLog._();
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      '${await getDatabasesPath()}/call_log.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE call_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            direction TEXT NOT NULL,
            peer_id TEXT NOT NULL,
            peer_name TEXT NOT NULL,
            room_id TEXT NOT NULL,
            is_group INTEGER NOT NULL,
            started_at INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            outcome TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> add({
    required String direction,
    required String peerId,
    required String peerName,
    required String roomId,
    required bool isGroup,
    required DateTime startedAt,
    required int durationMs,
    required String outcome,
  }) async {
    try {
      final db = await _open();
      await db.insert('call_log', <String, Object?>{
        'direction': direction,
        'peer_id': peerId,
        'peer_name': peerName,
        'room_id': roomId,
        'is_group': isGroup ? 1 : 0,
        'started_at': startedAt.millisecondsSinceEpoch,
        'duration_ms': durationMs,
        'outcome': outcome,
      });
    } catch (_) {
      // 記錄失敗不阻擋通話流程（草案）。
    }
  }

  static Future<List<CallLogEntry>> list({int limit = 100}) async {
    try {
      final db = await _open();
      final rows = await db.query(
        'call_log',
        orderBy: 'started_at DESC',
        limit: limit,
      );
      return rows
          .map((r) => CallLogEntry(
                id: r['id'] as int,
                direction: r['direction'] as String,
                peerId: r['peer_id'] as String,
                peerName: r['peer_name'] as String,
                roomId: r['room_id'] as String,
                isGroup: (r['is_group'] as int) == 1,
                startedAt: DateTime.fromMillisecondsSinceEpoch(
                  r['started_at'] as int,
                ),
                durationMs: r['duration_ms'] as int,
                outcome: r['outcome'] as String,
              ))
          .toList();
    } catch (_) {
      return <CallLogEntry>[];
    }
  }
}
