// 金鑰備份診斷與還原（解密案修法 #1，人類批准 2026-11-13）。
//
// 目的：把 matrix SDK 金鑰備份還原的「靜默失敗」變成看得到的狀態與判決。
//
// * 全程只呼叫 matrix 14.2.0 官方公開 API，無自製加密邏輯：
//   - `KeyManager.getRoomKeysBackupInfo()`（版本／演算法／數量／authData）
//   - `Client.getRoomKeys(version)`（官方取得備份全部 session）
//   - `KeyManager.loadFromResponse(keys)`（官方 `loadAllKeys()` 的還原本體）
//   - `KeyManager.getInboundGroupSession()`（還原後探測是否存入本機）
// * 只顯示備份中繼資料與數量；不顯示、不輸出、不落地任何金鑰內容。
// * 錯誤一律顯示真實內容（錯誤透明化——本案教訓：三種底層錯誤全被
//   同一句「密語不正確」遮蔽）。
// * 判決＝官方還原流程本身：還原後抽樣探測 session 是否存入本機。
//   存入 0 ＝ SSSS 快取密鑰無法解開現行備份（最可能：備份換版時密語未同步）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

/// 診斷／還原所需之官方 API 注入點（測試注入用；正式路徑見
/// [BackupRestoreDeps.fromClient]）。
typedef BackupInfoLoader
    = Future<GetRoomKeysVersionCurrentResponse> Function();
typedef BackupKeysFetcher = Future<RoomKeys> Function(String version);
typedef BackupRestorer = Future<void> Function(RoomKeys keys);

/// 還原後探測：session 是否已存入本機（官方 in-memory 金鑰快取查詢）。
typedef SessionProbe = bool Function(String roomId, String sessionId);

class BackupRestoreDeps {
  const BackupRestoreDeps({
    required this.loadInfo,
    required this.fetchKeys,
    required this.restore,
    required this.probeSession,
  });

  final BackupInfoLoader loadInfo;
  final BackupKeysFetcher fetchKeys;
  final BackupRestorer restore;
  final SessionProbe probeSession;

  /// 正式路徑：全部為 matrix SDK 官方公開方法。
  ///
  /// 呼叫前須確認 `client.encryption != null`（加密引擎已就緒）。
  factory BackupRestoreDeps.fromClient(Client client) {
    final keyManager = client.encryption!.keyManager;
    return BackupRestoreDeps(
      // `false`＝跳過 SDK 內建 5 分鐘版本快取，一律抓當下伺服器狀態。
      loadInfo: () => keyManager.getRoomKeysBackupInfo(false),
      fetchKeys: (version) async {
        // 修法 #1 強化（2026-11-13）：全量端點實測會漏 session（本案：
        // 全量 5 房/46，逐房端點對 307_67 另回 7 個）＝官方
        // loadFromResponse 看不到即不還原。故對「全量缺／空」的房間
        // 以官方逐房端點補抓做聯集（同版本、不解密任何內容）；
        // 僅補抓少數房，避免每房都打逐房端點拖慢還原。
        final keys = await client.getRoomKeys(version);
        final merged = Map.of(keys.rooms);
        final targets = client.rooms
            .where((r) => (merged[r.id]?.sessions.isEmpty ?? true))
            .toList();
        for (final room in targets) {
          try {
            final per = await client.getRoomKeysByRoomId(room.id, version);
            if (per.sessions.isEmpty) continue;
            final existing =
                merged[room.id]?.sessions ?? const <String, KeyBackupData>{};
            final union = Map.of(existing)..addAll(per.sessions);
            if (union.length > existing.length) {
              merged[room.id] = RoomKeyBackup.fromJson(
                {'sessions': union.map((k, v) => MapEntry(k, v.toJson()))},
              );
            }
          } catch (_) {
            // 此房在備份中不存在（伺服器 404）＝官方行為，略過。
          }
        }
        return RoomKeys.fromJson(
          {'rooms': merged.map((k, v) => MapEntry(k, v.toJson()))},
        );
      },
      restore: keyManager.loadFromResponse,
      probeSession: (roomId, sessionId) =>
          keyManager.getInboundGroupSession(roomId, sessionId) != null,
    );
  }
}

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key, required this.deps});

  final BackupRestoreDeps deps;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _infoLines = <String>[];
  String? _verdict;
  String? _error;
  bool _busy = false;

  /// 抽樣探測上限（避免大帳號全量探測；探測為本機記憶體查詢，成本低）。
  static const _probeLimit = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('金鑰備份診斷與還原'))), // 文案草案
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(S.t('僅顯示備份中繼資料與數量；不顯示任何金鑰內容。')), // 文案草案
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _queryBackup,
            child: Text(S.t('查詢備份狀態')), // 文案草案
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _restore,
            child: Text(S.t('從備份還原並判決')), // 文案草案
          ),
          const SizedBox(height: 16),
          if (_error != null) Text('${S.t('診斷失敗：')}$_error'), // 文案草案（真實錯誤）
          for (final line in _infoLines) Text(line),
          if (_verdict != null) Text(_verdict!), // 文案草案
        ],
      ),
    );
  }

  /// 輕量查詢：只抓備份版本資訊（官方 GET /room_keys/version）。
  Future<void> _queryBackup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.deps.loadInfo();
      if (!mounted) return;
      setState(() {
        _infoLines
          ..clear()
          ..addAll([
            '備份版本：${info.version}', // 文案草案
            '演算法：${info.algorithm.name}', // 文案草案
            '備份內含 session 數：${info.count}', // 文案草案（官方 count 欄位）
            '伺服器備份公鑰：${info.authData['public_key']}', // 文案草案
          ]);
        _busy = false;
      });
    } catch (e) {
      // 錯誤透明化：顯示真實例外內容，不再遮蔽。
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  /// 官方還原流程（同 `loadAllKeys()`：getRoomKeys → loadFromResponse）
  /// ＋還原後抽樣探測判決。
  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
      _verdict = null;
    });
    try {
      final info = await widget.deps.loadInfo();
      final keys = await widget.deps.fetchKeys(info.version);
      final rooms = keys.rooms;
      final sessionTotal =
          rooms.values.fold<int>(0, (n, r) => n + r.sessions.length);
      final lines = <String>[
        '備份版本：${info.version}', // 文案草案
        '演算法：${info.algorithm.name}', // 文案草案
        '備份內含：${rooms.length} 房 / $sessionTotal 個 session', // 文案草案
        '伺服器備份公鑰：${info.authData['public_key']}', // 文案草案
      ];
      // 官方還原本體（＝官方 loadAllKeys 內部同一條路徑）。
      await widget.deps.restore(keys);
      // 還原後抽樣探測：session 是否真的存入本機（官方 getInboundGroupSession）。
      final samples = <(String, String)>[];
      for (final entry in rooms.entries) {
        for (final sessionId in entry.value.sessions.keys) {
          samples.add((entry.key, sessionId));
          if (samples.length >= _probeLimit) break;
        }
        if (samples.length >= _probeLimit) break;
      }
      final stored =
          samples.where((s) => widget.deps.probeSession(s.$1, s.$2)).length;
      final String verdict;
      if (sessionTotal == 0) {
        verdict = '備份內沒有任何 session（無歷史可還原）。'; // 文案草案
      } else if (stored == samples.length) {
        verdict =
            '✅ 還原成功：抽樣 $stored/${samples.length} 已存入本機。請重開聊天室查看歷史訊息。'; // 文案草案
      } else if (stored > 0) {
        verdict =
            '⚠️ 部分存入：抽樣 $stored/${samples.length} 已存入本機（其餘可能為先前已取得或仍失敗）。'; // 文案草案
      } else {
        verdict =
            '⚠️ 還原未生效：抽樣 0/${samples.length} 存入本機。官方還原流程未回報錯誤，'
            '最可能原因：本機 SSSS 快取的備份密鑰與現行備份版本不符（備份換版時密語未同步更新）。'; // 文案草案
      }
      if (!mounted) return;
      setState(() {
        _infoLines
          ..clear()
          ..addAll(lines);
        _verdict = verdict;
        _busy = false;
      });
    } catch (e) {
      // 錯誤透明化：顯示真實例外內容，不再遮蔽。
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }
}
