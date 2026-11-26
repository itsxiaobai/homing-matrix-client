// 第七十九批（人類指示）：自訂好友名稱／暱稱——**只存本機、只自己看得到**。
// 覆寫顯示於聯絡人列表／聊天室標題／訊息寄件者；不送伺服器、不改 Matrix
// profile（其他使用者完全看不到）。零新依賴（沿用 AppSettings/sqflite）。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_settings.dart';

const String kLocalNicknamesKey = 'local_nicknames';

/// userId（@user:server）→ 本機暱稱。
final ValueNotifier<Map<String, String>> ringLocalNicknames =
    ValueNotifier<Map<String, String>>(<String, String>{});

/// 解析 kv；壞資料回空（不讓壞格式炸掉 App）。
Map<String, String> parseLocalNicknames(String? raw) {
  if (raw == null || raw.isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, String>{};
    final out = <String, String>{};
    decoded.forEach((key, value) {
      if (key is String && value is String && key.isNotEmpty && value.isNotEmpty) {
        out[key] = value;
      }
    });
    return out;
  } on Object {
    return <String, String>{};
  }
}

String encodeLocalNicknames(Map<String, String> names) => jsonEncode(names);

/// 讀回（失敗＝空）。
Future<void> loadLocalNicknames() async {
  try {
    ringLocalNicknames.value = parseLocalNicknames(
      await AppSettings.get(kLocalNicknamesKey),
    );
  } on Object {
    ringLocalNicknames.value = <String, String>{};
  }
}

Future<void> saveLocalNicknames(Map<String, String> names) async {
  ringLocalNicknames.value = Map<String, String>.from(names);
  try {
    await AppSettings.set(kLocalNicknamesKey, encodeLocalNicknames(names));
  } on Object {
    // 寫入失敗：本 session 仍生效。
  }
}

Future<void> setLocalNickname(String userId, String name) async {
  if (userId.isEmpty) return;
  final next = Map<String, String>.from(ringLocalNicknames.value);
  final clean = name.trim();
  if (clean.isEmpty) {
    next.remove(userId);
  } else {
    next[userId] = clean;
  }
  await saveLocalNicknames(next);
}

Future<void> removeLocalNickname(String userId) async {
  final next = Map<String, String>.from(ringLocalNicknames.value)..remove(userId);
  await saveLocalNicknames(next);
}

/// 顯示名：本機暱稱優先，沒有則用官方顯示名／fallback。
String localDisplayName(String userId, String fallback) {
  final nick = ringLocalNicknames.value[userId];
  return (nick != null && nick.isNotEmpty) ? nick : fallback;
}
