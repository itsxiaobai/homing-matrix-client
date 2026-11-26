// 第一百零四批：多帳號切換（人類要求「像 SchildiNext 那樣可以切換」）。
//
// 設計底線：既有 `ring.db`（SDK name/DB name 都是 'ring'）**原封保留**給第一個
// 帳號，不改名、不搬資料（人類先前選過「不改名以免孤立既有資料」）。
// 新帳號各自用 independent DB 檔與 SDK name → SDK 的 secure storage key
// （client_data_<name>、olm_account_<name>、ssss_cache_<name>_*）天然分開，
// App 端不碰任何金鑰內容。
//
// 只存帳號中繼資料（id／Matrix ID／homeserver）在 app_settings 的 kv，
// token 與 olm account 仍由 SDK 官方管理。
import 'dart:convert';

import 'app_settings.dart';

const String kAccountsKey = 'homing_accounts';
const String kActiveAccountKey = 'homing_active_account';

/// 舊單一帳號的 SDK name／DB 檔（保留既有資料）。
const String kLegacyAccountId = 'ring';

class HomingAccount {
  const HomingAccount({
    required this.id,
    required this.userId,
    required this.homeserver,
    required this.addedAt,
  });

  /// SDK database name／secure storage 前綴，同時是 DB 檔名（不含 .db）。
  final String id;
  final String userId;
  final String homeserver;
  final int addedAt;

  String get dbFile => id == kLegacyAccountId ? 'ring.db' : '$id.db';

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'userId': userId,
        'homeserver': homeserver,
        'addedAt': addedAt,
      };

  static HomingAccount? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    final userId = v['userId'];
    final hs = v['homeserver'];
    final ts = v['addedAt'];
    if (id is! String || id.isEmpty) return null;
    if (userId is! String || userId.isEmpty) return null;
    if (hs is! String || hs.isEmpty) return null;
    if (ts is! int) return null;
    return HomingAccount(
      id: id,
      userId: userId,
      homeserver: hs,
      addedAt: ts,
    );
  }
}

List<HomingAccount> parseAccounts(String? raw) {
  if (raw == null || raw.isEmpty) return <HomingAccount>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <HomingAccount>[];
    return decoded
        .map(HomingAccount.fromJson)
        .whereType<HomingAccount>()
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  } on Object {
    return <HomingAccount>[];
  }
}

String encodeAccounts(List<HomingAccount> accounts) =>
    jsonEncode(<Object?>[for (final a in accounts) a.toJson()]);

Future<List<HomingAccount>> loadAccounts() async {
  try {
    return parseAccounts(await AppSettings.get(kAccountsKey));
  } on Object {
    return <HomingAccount>[];
  }
}

Future<void> saveAccounts(List<HomingAccount> accounts) async {
  await AppSettings.set(kAccountsKey, encodeAccounts(accounts));
}

/// 目前使用中的帳號 id（null＝尚未選擇／尚未登入）。
Future<String?> loadActiveAccountId() async {
  try {
    return await AppSettings.get(kActiveAccountKey);
  } on Object {
    return null;
  }
}

Future<void> setActiveAccountId(String id) async {
  await AppSettings.set(kActiveAccountKey, id);
}

/// 取得目前帳號物件（找不到回 null）。
Future<HomingAccount?> loadActiveAccount() async {
  final id = await loadActiveAccountId();
  if (id == null) return null;
  final accounts = await loadAccounts();
  for (final account in accounts) {
    if (account.id == id) return account;
  }
  return null;
}

/// 新增（或更新同名 Matrix ID）帳號並設為目前帳號。
/// 第一個帳號沿用 'ring'／ring.db；其後用 homing_2、homing_3…。
Future<HomingAccount> addAccount({
  required String userId,
  required Uri homeserver,
  String? accountId,
}) async {
  final accounts = await loadAccounts();
  for (final account in accounts) {
    if (account.userId == userId && account.homeserver == homeserver.toString()) {
      await setActiveAccountId(account.id);
      return account;
    }
  }
  String id;
  if (accountId != null && accountId.isNotEmpty) {
    id = accountId;
  } else if (accounts.isEmpty) {
    id = kLegacyAccountId;
  } else {
    var n = 2;
    final used = accounts.map((a) => a.id).toSet();
    while (used.contains('homing_$n')) {
      n++;
    }
    id = 'homing_$n';
  }
  final account = HomingAccount(
    id: id,
    userId: userId,
    homeserver: homeserver.toString(),
    addedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await saveAccounts(<HomingAccount>[account, ...accounts]);
  await setActiveAccountId(id);
  return account;
}

/// 計算下一個新帳號要用的 id（與 [addAccount] 的自動編號規則一致）。
Future<String> nextAccountId() async {
  final accounts = await loadAccounts();
  if (accounts.isEmpty) return kLegacyAccountId;
  var n = 2;
  final used = accounts.map((a) => a.id).toSet();
  while (used.contains('homing_$n')) {
    n++;
  }
  return 'homing_$n';
}

/// 移除帳號中繼資料（不刪 SDK session；登出由 SDK 自己清 token）。
Future<void> removeAccount(String id) async {
  final accounts = await loadAccounts();
  await saveAccounts(accounts.where((a) => a.id != id).toList());
  final active = await loadActiveAccountId();
  if (active == id) {
    final rest = await loadAccounts();
    await setActiveAccountId(rest.isEmpty ? '' : rest.first.id);
  }
}
