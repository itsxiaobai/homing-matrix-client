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
// * `Encryption.keyManager.maybeAutoRequest(roomId, sessionId, senderKey,
//   onlineKeyBackupOnly: false)` —— SDK 內部同方法（decryptRoomEvent
//   L306 的呼叫），唯一差別是把「只查線上備份」關掉：SDK 預設
//   `onlineKeyBackupOnly: true`＝永遠不退回 to-device 請求。關閉後
//   流程＝先查線上備份（loadSingleKey），M_NOT_FOUND 就對房間全體
//   參與者的裝置發 `m.room_key_request`（to-device）；在線裝置
//   （Element／Element X，如同一台手機上的 Element X）回應後由 SDK
//   官方 setInboundGroupSession 存入，重開聊天室即解密顯示。
import 'package:matrix/matrix.dart';

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
///
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
    await keyManager.maybeAutoRequest(
      room.id,
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
    final content = await room.client.getRoomStateWithKey(
      room.id,
      EventTypes.Encryption,
      '',
    );
    if (content.tryGet<String>('algorithm') == null) {
      // 伺服器也無此 state＝非加密房（官方行為），不需要補。
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
Future<List<Event>> decryptUndecryptedEvents(
  Room room,
  List<Event> events,
) async {
  final encryption = room.client.encryption;
  if (encryption == null) return events;
  final out = List<Event>.of(events);
  for (var i = 0; i < out.length; i++) {
    final e = out[i];
    if (e.type != EventTypes.Encrypted || e.redacted) continue;
    try {
      out[i] = await encryption.decryptRoomEvent(e);
    } catch (_) {
      // 任何例外＝保留原事件（顯示佔位），不阻斷訊息列。
    }
  }
  return out;
}
