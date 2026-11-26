// 修法 #2（解密案，人類批准 2026-11-13）：對「無旗標＋解密失敗」的舊事件
// 主動發出取鑰請求。
//
// 背景（源碼＋logcat 實機釘死，見 PROGRESS.md 解密案）：
// * SDK 的取鑰觸發點全部要求事件 content 帶 `can_request_session: true`
//   旗標：getTimeline 重試塊（room.dart L1879）、getEventContext
//   （room.dart L1776）、SSSS cacheCallback（key_manager.dart L58）。
// * 旗標只在「失敗當下正在跑的 SDK 版本」寫入（sync 失敗路徑
//   client.dart L2924→encryption.dart L252）。重裝／換儲存後端後，
//   舊事件重新落庫時若引擎未就緒（encryptionEnabled=false，
//   client.dart L2919 條件不通過）→ 原樣儲存、無旗標。
// * SDK 對已存的無旗標失敗事件**沒有任何回溯補救機制** →
//   取鑰請求永不發出（實機 logcat：request() 開頭的 INFO log 零輸出）。
//
// 本檔只呼叫 matrix 14.2.0 官方公開 API，不寫任何加密／金鑰演算：
// * `Encryption.keyManager.maybeAutoRequest(room, sessionId, senderKey,
//   onlineKeyBackupOnly: false)` —— SDK 內部同方法（decryptRoomEvent
//   L306 的呼叫），唯一差別是把「只查線上備份」關掉：SDK 預設
//   `onlineKeyBackupOnly: true`＝永遠不退回 to-device 請求。關閉後
//   流程＝先查線上備份（loadSingleKey），M_NOT_FOUND 就對房間全體
//   參與者的裝置發 `m.room_key_request`（to-device）；在線裝置
//   （Element／Element X，如同一台手機上的 Element X）回應後由 SDK
//   官方 setInboundGroupSession 存入，重開聊天室即解密顯示。
import 'package:matrix/matrix.dart';
import 'perf_metrics.dart'; // 第六十七批：解密細粒度量測（唯讀耗時／計數）

/// 單一缺失 session（取自官方 megolm content 欄位）。
class MissingSession {
  const MissingSession({required this.sessionId, this.senderKey});

  final String sessionId;
  final String? senderKey;
}

/// 從 timeline 事件列出解密失敗的 megolm session（去重）。
///
/// 判準＝事件仍為 `m.room.encrypted`（SDK 官方行為：解密成功的事件
/// 會換成明文型別，如 m.message）且 content 帶官方 `session_id` 欄位；
/// 已收回（redacted）事件與無 session_id 事件略過。
List<MissingSession> collectMissingSessions(List<Event> events) {
  final seen = <String>{};
  final out = <MissingSession>[];
  for (final event in events) {
    if (event.type != EventTypes.Encrypted || event.redacted) continue;
    final sessionId = event.content.tryGet<String>('session_id');
    if (sessionId == null || !seen.add(sessionId)) continue;
    out.add(
      MissingSession(
        sessionId: sessionId,
        senderKey: event.content.tryGet<String>('sender_key'),
      ),
    );
  }
  return out;
}

/// 對缺失 session 逐個發出取鑰請求（官方 API）。回傳請求的 session 數。
/// `onlineKeyBackupOnly: false`＝允許退回 to-device 請求（見檔頭說明）。
Future<int> requestMissingKeys(
  Room room,
  Timeline timeline, {
  bool onlineKeyBackupOnly = false,
}) async {
  final sessions = collectMissingSessions(timeline.events);
  final keyManager = room.client.encryption?.keyManager;
  if (keyManager == null) {
    throw StateError('加密引擎未就緒'); // 文案草案，待人類設計定稿
  }
  for (final session in sessions) {
    // ⚠️ 第五十七批（SDK 升級 16.0.4）：官方 `maybeAutoRequest` 的**第一參數
    // 由 `roomId` 改為 `Room` 物件**（16.0.0 的唯一 BREAKING 項；changelog：
    // 「[BREAKING] pass Room to maybeAutoRequest so it works for archived
    // rooms too」）→ 傳 `room`。
    await keyManager.maybeAutoRequest(
      room,
      session.sessionId,
      session.senderKey,
      onlineKeyBackupOnly: onlineKeyBackupOnly,
    );
  }
  return sessions.length;
}

/// 修法 #3（解密案，2026-11-13 實機釘死）：房間 `m.room.encryption` state
/// 缺失時的官方補救。
///
/// 背景（源碼＋logcat 實證）：SDK timeline 載入只在
/// `room.encrypted && client.encryptionEnabled` 時解密（timeline.dart
/// L288），`room.encrypted` 取決於本機 state 有無 `m.room.encryption`
/// （room.dart L2733→2737）。重裝後首次 sync 若中斷，此 state 可能缺落；
/// 之後解密被**完全跳過且零 log**（decryptRoomEventSync 的失敗必印
/// `Could not decrypt event`，實機 verbose 下開房一條皆無）——事件恆為
/// m.room.encrypted 佔位，session 即使已在 DB 也没有被呼叫的機會
/// （實機 diag：7/7 IN-DB、loadFromDB valid=true，timeline encrypted=0）。
///
/// 補救＝純官方 API、不含任何加密演算：
/// * `client.getRoomStateWithKey(roomId, 'm.room.encryption', '')`
///   （SDK 內部同方法，room.dart L2054）
/// * `database.transaction` 內 `storeEventUpdate(..., EventUpdateType.state,
///   ...)`（SDK sync 同路徑，matrix_sdk_database.dart L1191 起）＋
///   `room.setState(...)`（room.dart L135，記憶體層）。
///
/// 回傳 true＝state 本缺、已自伺服器補回（呼叫端應重建 timeline 觸發解密）；
/// false＝state 本來就有／房間真的非加密（伺服器 404）／任何失敗。
Future<bool> ensureRoomEncryptionState(Room room) async {
  try {
    if (room.encrypted) return false;
    // 第六十七批：負面結果快取——查過「伺服器也無 m.room.encryption」的
    // 房間不再重打 HTTP（`getRoomStateWithKey` 是**網路 API**，matrix 16
    // generated/api.dart L5045；公開房每次 404 就是過去訊息載入卡 7 秒
    // 的真因）。**無 TTL**；登出清除（clearDecryptedEventCache）。
    // 網路失敗**不記入**（可能是暫時離線，下次仍重試）。
    if (_knownUnencryptedRooms.contains(room.id)) return false;
    final content = await room.client.getRoomStateWithKey(
      room.id,
      EventTypes.Encryption,
      '',
    );
    if (content.tryGet<String>('algorithm') == null) {
      // 伺服器也無此 state＝非加密房（官方行為），不需要補。
      _knownUnencryptedRooms.add(room.id);
      return false;
    }
    final stateEvent = Event(
      type: EventTypes.Encryption,
      content: content,
      // state 修補事件：eventId／ts 以本地佔位值標記（SDK 端 state 解密
      // 判準只讀 content.algorithm； eventId 僅作資料完整性欄位）。
      eventId: '\$local-state-repair-${DateTime.now().millisecondsSinceEpoch}',
      senderId: room.client.userID ?? '',
      stateKey: '',
      originServerTs: DateTime.now(),
      room: room,
    );
    await room.client.database.transaction(() async {
      await room.client.database.storeEventUpdate(
        room.id,
        stateEvent,
        EventUpdateType.state,
        room.client,
      );
    });
    room.setState(stateEvent);
    return true;
  } catch (_) {
    // 任何失敗（非加密房 404／測試假 client）＝不阻斷開房。
    return false;
  }
}

/// 修法 #4/#5（解密案，2026-11-13 源碼＋實機釘死）：對未解密的
/// `m.room.encrypted` 事件補解密。
///
/// 背景：SDK 對「重裝／換儲存後重新載入的舊事件」沒有任何重解機制——
/// /context 重建路徑只解密帶 `can_request_session: true` 旗標的事件
/// （room.dart L1775-1776；旗標只由「失敗當下正在跑的 SDK 實例」寫入），
/// timeline 載入路徑（timeline.dart L288）雖無旗標判準，但實機證實
/// 重裝後 stored 事件（8/8 帶旗標）同樣不被重解＝訊息恆為未解密佔位、
/// session 即使已在本機 DB 也沒有被解密路徑呼叫的機會
/// （實機 diag：7/7 IN-DB 且 loadFromDB valid=true）。
///
/// 補法＝以官方 `Encryption.decryptRoomEvent`（SDK 同函式，room.dart
/// L1777 與 timeline.dart L291 同呼叫）對每個 `m.room.encrypted` 事件
/// 補解密，**帶旗標事件一併重試**（修法 #5；實機：8/8 ok、0 fail）：
/// * 失敗回傳的 BadEncrypted 事件會自動觸發官方 maybeAutoRequest 取鑰
///   （encryption.dart L300-307）——與 SDK 行為一致。
/// * 已收回（redacted）事件略過。
/// 回傳新 list（順序不變；不修改輸入）。
///
/// **第六十七批（人類指示「已經載入的所有資料存入 cache，並嚴禁像 LINE
/// 限時存取」）**：解密結果快取——每個房間已成功解密的事件以 eventId 存入
/// `decryptedEventCache`（公開供同專案測試注入；App 端只透過下列函式讀寫），
/// 之後每次載入**直接重用、不再重解**（過去訊息卡頓的最大成本＝每輪載入
/// 把整個時間窗逐筆 megolm 重解）。快取：
/// * **無任何 TTL／到期／限時存取機制**——一經解密，App session 內持續
///   可用，不因時間清理（明文禁令：僅記憶體；登出時全清，見
///   `clearDecryptedEventCache`）。
/// * 只快取**成功**解密；失敗者每次載入仍重試（鑰匙可能在之後到達，
///   取鑰請求語意不變）。
final Map<String, Map<String, Event>> decryptedEventCache = {};

/// 讀快取（null＝無快取；呼叫端照舊走官方解密）。
Event? _cachedDecryptedEvent(Room room, String eventId) {
  return decryptedEventCache[room.id]?[eventId];
}

void _storeDecryptedEvent(Room room, Event decrypted) {
  final id = decrypted.eventId;
  if (id.isEmpty) return;
  final bucket = decryptedEventCache[room.id] ?? <String, Event>{};
  bucket[id] = decrypted;
  decryptedEventCache[room.id] = bucket;
}

/// 登出時清除解密快取（所有房間；僅記憶體）。
/// 同時清「已知非加密房」負面快取（無 TTL，但換帳號必須重查）。
void clearDecryptedEventCache() {
  decryptedEventCache.clear();
  _knownUnencryptedRooms.clear();
}

/// 第六十七批：已知「非加密房」id（負面結果快取，無 TTL；見
/// `ensureRoomEncryptionState`）。
final Set<String> _knownUnencryptedRooms = {};

Future<List<Event>> decryptUndecryptedEvents(
  Room room,
  List<Event> events,
) async {
  final encryption = room.client.encryption;
  final out = List<Event>.of(events);
  // 第六十七批：細粒度量測（站上診斷資訊「效能量測」區）：區分快取命中／
  // 實際解密／失敗，以定位 7 秒 load 的成本落在何處（只記計數）。
  final watch = Stopwatch()..start();
  var hits = 0;
  var decryptions = 0;
  var failures = 0;
  for (var i = 0; i < out.length; i++) {
    final e = out[i];
    if (e.type != EventTypes.Encrypted || e.redacted) continue;
    final cached = _cachedDecryptedEvent(room, e.eventId);
    if (cached != null) {
      out[i] = cached; // 快取重用（無 TTL；不重解、不需引擎）。
      hits++;
      continue;
    }
    if (encryption == null) {
      failures++;
      continue;
    }
    try {
      final decrypted = await encryption.decryptRoomEvent(e);
      out[i] = decrypted;
      _storeDecryptedEvent(room, decrypted);
      decryptions++;
      // 讓出 UI 執行緒：megolm 解密（vodozemac）是同步 CPU 成本，逐筆
      // await 之間插入 zero-duration delay → 給 paint／手勢機會，
      // 即使大量歷史一次解密也不會被 Android 判 ANR。
      await Future<void>.delayed(Duration.zero);
    } catch (_) {
      failures++;
      // 任何例外＝保留原事件（顯示佔位），不阻斷訊息列。
      // 失敗不進快取 → 下次載入仍重試（鑰匙到達後可解）。
    }
  }
  watch.stop();
  PerfLog.record(
    'chat.decrypt',
    watch.elapsedMicroseconds,
    {
      '總數': out.length,
      '快取': hits,
      '解密': decryptions,
      '失敗': failures,
    },
  );
  // 第九十九批（人類授權 C）：解密失敗後**自動**對缺失 session 發官方
  // maybeAutoRequest 取鑰（第五十一批解密案缺的最後一環）。只呼叫官方 API，
  // 不碰任何加密演算法／金鑰內容；失敗靜默（不干擾一般使用者）。
  if (failures > 0) {
    final encryption = room.client.encryption;
    final keyManager = encryption?.keyManager;
    if (keyManager != null) {
      final missing = collectMissingSessions(out);
      for (final session in missing) {
        try {
          await keyManager.maybeAutoRequest(
            room,
            session.sessionId,
            session.senderKey,
            onlineKeyBackupOnly: false,
          );
        } on Object {
          // 取鑰失敗靜默：下次載入仍會重試（不進快取、不阻斷列表）。
        }
      }
    }
  }
  return out;
}
