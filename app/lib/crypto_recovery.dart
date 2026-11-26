// 金鑰恢復（recovery key／密語）相關的**錯誤分流與就緒等待**。
//
// ⚠️ 本檔**不碰任何加密演算法、金鑰交換或驗證邏輯**：只做兩件事——
//  1. 把 SDK 拋出的例外翻譯成使用者看得懂、且**可行動**的訊息；
//  2. 在自我簽章（selfSign）之前，確認**本裝置自己的 device key 已經同步回來**。
//
// 為什麼需要第 2 點（實機根因，2026-11-14）：
//   SDK `CrossSigning.selfSign()`（`lib/encryption/cross_signing.dart` L96-97）
//   在自我簽章前會讀 `client.userDeviceKeys[userID]?.deviceKeys[deviceID]`；
//   若**本裝置的 device key 尚未回填**（例如初次登入時 initial sync 逾時，
//   實機 logcat：`Error during processing events - TimeoutException after
//   0:00:10` → 之後才出現 `Updating user device keys in database...`），
//   SDK 會丟出 `Master or user keys not found`。
//   該錯誤**與 recovery key 本身是否正確無關**，但舊 UI 一律顯示
//   「recovery key 或密語不正確」→ 誤導使用者重複貼錯 key。
import 'dart:async';

import 'package:matrix/encryption.dart' show InvalidPassphraseException;
import 'package:matrix/matrix.dart';

/// SDK 自我簽章缺少本裝置金鑰時的固定錯誤字串（cross_signing.dart L97）。
const String kOwnDeviceKeysMissingError = 'Master or user keys not found';

/// 將金鑰恢復相關的例外轉為使用者可讀訊息。
///
/// 分流原則：**能重試的原因**與**輸入錯誤**分開說，避免把「時序未就緒」
/// 誤報成「你的 key 不對」。
String describeRecoveryError(Object error) {
  final text = error.toString();

  // ① 本裝置 device key 尚未同步回來（可稍候重試）。
  if (text.contains(kOwnDeviceKeysMissingError)) {
    return '本裝置金鑰尚未同步完成（連線較慢或初始 sync 逾時），'
        '請稍候再試一次；也可先略過，稍後到「設定 → 進階」重試';
  }

  // ② 使用者輸入的 recovery key／密語不正確（SDK `InvalidPassphraseException`）。
  if (error is InvalidPassphraseException) {
    return 'recovery key 或密語不正確（${error.cause}）';
  }
  if (text.contains('Bad MAC') ||
      text.contains('Incorrect') ||
      text.contains('Wrong / unknown key')) {
    return 'recovery key 或密語不正確';
  }

  // ③ SDK 的加密身份狀態問題（原文含 SDK 自身的拼字，勿更正以便對照原始碼）。
  if (text.contains('not initalized')) {
    return '此帳號尚未初始化加密身份（請確認帳號是否已設定金鑰備份）';
  }
  if (text.contains('already connected')) {
    return '此裝置已連上加密身份，無需再解密';
  }
  if (text.contains('End to end encryption not available')) {
    return '此裝置未啟用端對端加密';
  }

  // ④ 其他：原樣帶出（透明顯示，不吞掉細節）。
  return '解密失敗（$text）';
}

/// 本裝置自己的 device key 是否已回填（官方 `client.userDeviceKeys`）。
bool hasOwnDeviceKeys(Client client) {
  final userId = client.userID;
  final deviceId = client.deviceID;
  if (userId == null || deviceId == null) return false;
  return client.userDeviceKeys[userId]?.deviceKeys[deviceId] != null;
}

/// 等待本裝置的 device key 就緒（最多 [timeout]）。
///
/// 只讀官方欄位、不觸碰金鑰；回傳是否在時限內就緒。
Future<bool> waitForOwnDeviceKeys(
  Client client, {
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  return waitUntil(() => hasOwnDeviceKeys(client), timeout: timeout, interval: interval);
}

/// 等待條件成立（可注入 probe，便於單元測試）。
Future<bool> waitUntil(
  bool Function() probe, {
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (probe()) return true;
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(interval);
  }
}

/// 第九十四批（人類授權 C）：`restoreCryptoIdentity()` 只解鎖 SSSS／自我
/// 簽章，**不會**把 megolm session 抓回本機 → 重裝後舊訊息仍無法解密。
/// 此函式補上「金鑰備份還原」（官方 getRoomKeysBackupInfo → getRoomKeys →
/// loadFromResponse，與 BackupRestoreScreen 同一條官方路徑），全程只呼叫
/// matrix SDK 官方 API、不碰任何加密演算法／金鑰內容。
///
/// 回傳還原的 session 數（0＝備份內無 session 或失敗）；失敗拋例外由呼叫端分流。
Future<int> restoreKeyBackupSessions(Client client) async {
  final encryption = client.encryption;
  if (encryption == null) {
    throw StateError('End to end encryption not available');
  }
  final keyManager = encryption.keyManager;
  // 跳過 SDK 5 分鐘版本快取（同 BackupRestoreDeps.fromClient 的 false）。
  final info = await keyManager.getRoomKeysBackupInfo(false);
  final keys = await _fetchKeysWithPerRoomUnion(client, keyManager, info.version);
  await keyManager.loadFromResponse(keys);
  return keys.rooms.values.fold<int>(0, (n, r) => n + r.sessions.length);
}

/// 同 BackupRestoreDeps.fromClient 的全量＋逐房聯集（實測全量端點會漏
/// session）。只呼叫官方 getRoomKeys／getRoomKeysByRoomId。
Future<RoomKeys> _fetchKeysWithPerRoomUnion(
  Client client,
  dynamic keyManager,
  String version,
) async {
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
    } on Object {
      // 此房在備份中不存在（官方 404）＝正常，略過。
    }
  }
  return RoomKeys.fromJson(
    {'rooms': merged.map((k, v) => MapEntry(k, v.toJson()))},
  );
}
