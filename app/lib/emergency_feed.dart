// 批次十六 v0 — 緊急示警（PWS RSS）：官方 NCDR「民生示警公開資料平台」
// 聚合 Atom feed。零新依賴：dart:io HttpClient ＋ 手寫迷你 Atom 剝析
//（官方 feed 為機器產生的固定結構；解析全程 try/catch，失敗回空清單不出錯）。
//
// 官方規則依循（alerts.ncdr.nat.gov.tw 開發專區 CAPATOMfeedRules.pdf、
// alerts-rss 頁，查證 2026-11-07）：
//   1. 僅取 cap:status=Actual（官方明示 cap:status=test 勿用於對外產品）。
//   2. 以 entry <id> 辨識同一示警（避免重複接收同一則）。
//   3. 解析 cap:expires 判斷示警是否仍生效（feed 目錄回溯 7 天，會含過期項）。
//   4. cap:msgType=Cancel（撤銷）不顯示。
//
// 授權：feed 自帶 <rights>Public Domain</rights>；其政府資料開放平臺資料集
// 以「政府資料開放授權條款-第1版」登錄（依顯名義務，UI 必須標示資料來源，
// 見 kEmergencyFeedAttribution ＋ rooms_screen 免責文案）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'app_settings.dart'; // 第六十四批④：測試示警 kv（本機；無循環依賴）

/// 聚合端點（**第三十五批 #6 改**：人類指定以 cbs.tw 為主——查證 2026-11-12：
/// `cbs.tw/files/rssatomfeed.xml` 回應 HTTP 200、`<updated>` 當日新鮮、
/// `<id>` 指向 alerts.ncdr.nat.gov.tw、author NCDR ＝ NCDR 官方 CAP 通路
/// （批次十六誤判為第三方 mirror，更正）。官方 RssAtomFeeds.ashx 保留為
/// **自動 fallback**（主端點網路失敗／非 200 時改抓，同批 16 已查證通路）。
/// 兩端點 feed 元素形狀不同（見 _parseAtomFeed），解析器雙形狀相容）。
const String kEmergencyFeedUrl = 'https://cbs.tw/files/rssatomfeed.xml';
const String kEmergencyFeedFallbackUrl =
    'https://alerts.ncdr.nat.gov.tw/RssAtomFeeds.ashx';

/// 顯名聲明（政府資料開放授權條款第 3 條(二)：未盡顯名標示義務者，視為
/// 自始未取得授權）→ 由 rooms_screen 橫幅下方顯示。
const String kEmergencyFeedAttribution =
    '資料來源：國家災害防救科技中心 民生示警公開資料平台（政府資料開放授權條款）';

/// 僅顯示高風險類別（人類決定 2026-11-07「僅高風險類別」；**清單為草案**，
/// 待人類指定／增修——改這一個常數即可）。
const List<String> kHighRiskCategories = <String>[
  '地震速報',
  '地震報告',
  '海嘯',
  '颱風',
  '淹水',
  '土石流',
  '疏散避難',
];

/// 一則示警（解析後的最小欄位集）。
class EmergencyAlert {
  const EmergencyAlert({
    required this.id,
    required this.category,
    required this.sender,
    required this.summary,
    required this.link,
    required this.sent,
    required this.expires,
  });

  final String id; // entry id（官方示警識別碼，去重用）
  final String category; // 示警類別（entry title／category term）
  final String sender; // 發布機關（author，例：中央氣象署／水利署）
  final String summary; // 純文字內容（去 HTML 標籤）
  final String link; // 原始 .cap 檔 URL
  final DateTime? sent; // entry updated
  final DateTime? expires; // cap:expires（過期判斷）
}

/// 抓取官方聚合 feed，回傳「Actual＋未過期＋高風險類別」條目（sent 新→舊排序）。
/// 任何網路／解析失敗皆回空清單（不丟錯、不出錯；下次輪詢重試）。
Future<List<EmergencyAlert>> fetchEmergencyAlerts({
  HttpClient? httpClient,
  Duration timeout = const Duration(seconds: 20),
  DateTime? now,
  List<String> categories = kHighRiskCategories,
}) async {
  final HttpClient own = httpClient ?? HttpClient();
  final at = now ?? DateTime.now().toUtc();
  try {
    // 第三十五批 #6：主端點（人類指定 cbs.tw）→ 網路失敗／非 200 時自動
    // 改抓官方 RssAtomFeeds.ashx（批 16 查證通路）。解析成功但**零條目＝
    // 正常狀態**（此刻無示警），不觸發 fallback。
    final primary = await _fetchFromUrl(own, kEmergencyFeedUrl, timeout, at, categories);
    if (primary != null) {
      return primary;
    }
    return await _fetchFromUrl(own, kEmergencyFeedFallbackUrl, timeout, at, categories) ??
        const <EmergencyAlert>[];
  } on Object {
    return const [];
  } finally {
    // 僅在自行建立 client 時關閉（測試可注入共用 client）。
    if (httpClient == null) {
      own.close(force: true);
    }
  }
}

/// 單一 URL 抓取＋解析。回 null＝抓取失敗（丟例外或非 200）。
Future<List<EmergencyAlert>?> _fetchFromUrl(
  HttpClient client,
  String url,
  Duration timeout,
  DateTime now,
  List<String> categories,
) async {
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/xml');
    req.headers.set(HttpHeaders.userAgentHeader, 'Homing/1.0 (emergency feed)');
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode != 200) {
      // 非正常回應：不重試轟炸，回 null（上層改試 fallback／下次輪詢再取）。
      await resp.drain<void>();
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) {
        // 異常超大回應：放棄本次（防呆）。
        await resp.drain<void>();
        return null;
      }
    }
    final xml = utf8.decode(bytes, allowMalformed: true);
    final all = parseEmergencyFeedXml(xml, now);
    // 高風險類別過濾（title 含關鍵字即命中）。
    return [
      for (final a in all)
        if (categories.any((k) => a.category.contains(k))) a,
    ];
  } on Object {
    return null;
  }
}

/// 第三十五批：解析入口改**公開**（雙形狀相容 parser 的測試／除錯入口；
/// 純函式不打網路）。`_fetchFromUrl` 與測試共用同一條解析路徑。
List<EmergencyAlert> parseEmergencyFeedXml(String xml, DateTime now) {
  final alerts = <EmergencyAlert>[];
  try {
    final entryRe = RegExp(r'<entry>[\s\S]*?</entry>');
    for (final match in entryRe.allMatches(xml)) {
      final entry = match.group(0) ?? '';
      final id = _tag(entry, 'id');
      if (id.isEmpty) {
        continue; // 無 id 無法去重 → 略過
      }
      // 第三十五批 #6：雙 feed 形狀——官方 RssAtomFeeds.ashx 用 `cap:` 前綴
      //（cap:status／cap:msgType／cap:expires），cbs.tw 用**無前綴**同名元素
      //（status／msgType／expires，另有 sent／text／sender>value）。取兩者。
      final status = _tagAny(entry, const ['cap:status', 'status']).trim();
      if (status.toLowerCase() != 'actual') {
        continue; // 官方規則：非 Actual（test/Exercise 等）不對外顯示
      }
      final msgType = _tagAny(entry, const ['cap:msgType', 'msgType']).trim();
      if (msgType == 'Cancel' || msgType == 'cancel') {
        continue; // 撤銷類條目不顯示
      }
      final expires = _parseFlexible(_tagAny(entry, const ['cap:expires', 'expires']));
      if (expires != null && !expires.isAfter(now)) {
        continue; // 已過期 → 不顯示
      }
      alerts.add(
        EmergencyAlert(
          id: id,
          category: _tag(entry, 'title').trim(),
          sender: _sender(entry),
          summary: _stripTags(_tagAny(entry, const ['summary', 'text', 'description'])),
          link: _link(entry),
          sent: _parseFlexible(_tagAny(entry, const ['cap:sent', 'sent', 'updated'])),
          expires: expires,
        ),
      );
    }
  } on Object {
    // 解析損毀 → 已收集到的仍可回，或空清單；不出錯。
  }
  alerts.sort((a, b) {
    final at = a.sent?.millisecondsSinceEpoch ?? 0;
    final bt = b.sent?.millisecondsSinceEpoch ?? 0;
    return bt.compareTo(at); // sent 新→舊
  });
  return alerts;
}

String _tag(String xml, String tag) {
  final m = RegExp('<$tag>[\\s\\S]*?</$tag>').firstMatch(xml);
  if (m == null) {
    return '';
  }
  final inner = m.group(0) ?? '';
  final start = inner.indexOf('>');
  final end = inner.lastIndexOf('<');
  if (start < 0 || end <= start) {
    return '';
  }
  return inner.substring(start + 1, end).trim();
}

/// 第三十五批 #6：多候選標籤取值（首個非空命中）——雙 feed 形狀相容。
/// 注意：_tag 以「精確標籤名」比對，故 `status` 不會誤吃到 `cap:status`
///（正則含字面 `>` 前綴邊界）。
String _tagAny(String xml, List<String> tags) {
  for (final tag in tags) {
    final v = _tag(xml, tag);
    if (v.isNotEmpty) {
      return v;
    }
  }
  return '';
}

/// 發布機關：官方形狀＝`<author><name>`；cbs.tw 形狀＝`<sender><value>`；
/// 兩者皆無 → 裸 `<sender>`／`<cap:sender>`（cap:sender 為 URI，僅供後備）。
String _sender(String entry) {
  final named = _author(entry);
  if (named.isNotEmpty) {
    return named;
  }
  final nested =
      RegExp(r'<sender>\s*<value>[\s\S]*?</value>\s*</sender>')
          .firstMatch(entry);
  if (nested != null) {
    return _stripTags(nested.group(0) ?? '');
  }
  return _stripTags(_tagAny(entry, const ['cap:sender', 'sender']));
}

String _author(String entry) {
  final m = RegExp(r'<author>[\s\S]*?<name>[\s\S]*?</name>[\s\S]*?</author>')
      .firstMatch(entry);
  if (m == null) {
    return '';
  }
  return _stripTags(m.group(0) ?? '');
}

String _link(String entry) {
  final m = RegExp(r'<link[^>]*href="([^"]+)"').firstMatch(entry);
  return m?.group(1) ?? '';
}

/// 去 HTML 標籤＋還原最常見的 XML entities（summary 標為 type="html"，
/// 實測為純文字；此處僅防呆）。
String _stripTags(String raw) {
  var s = raw;
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  const entities = <String, String>{
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&nbsp;': ' ',
  };
  for (final e in entities.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// 解析時間：先試 ISO8601（updated）；失敗再試官方 cap 時間格式
///（機器產生之 zh-TW 表示法：「2026/11/8 下午 11:00:00」12 小時制，
/// 下午 hh→+12h（12 時除外）、上午 12 時→0 時）。
DateTime? _parseFlexible(String raw) {  if (raw.isEmpty) {
    return null;
  }
  final iso = DateTime.tryParse(raw);
  if (iso != null) {
    return iso;
  }
  final m = RegExp(
    r'(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})\s*(上午|下午|早上|中午)?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?',
    multiLine: false,
  ).firstMatch(raw);
  if (m == null) {
    return null;
  }
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  var hour = int.parse(m.group(5)!);
  final minute = int.parse(m.group(6)!);
  final second = int.tryParse(m.group(7) ?? '0') ?? 0;
  final period = m.group(4);
  if (period != null && period.isNotEmpty) {
    if (period == '下午') {
      if (hour != 12) {
        hour += 12;
      }
    } else if (period == '上午' || period == '早上') {
      if (hour == 12) {
        hour = 0;
      }
    }
  }
  try {
    return DateTime(year, month, day, hour, minute, second);
  } on Object {
    return null;
  }
}

/// 第三十五批 #6（人類 2026-11-12 拍板）：緊急求助流程的觸發類別——
/// 地震／颱風（「在地震／颱風入境緊急訊息後跳出」）。「全國性或大範圍」
/// v0 以**類別白名單代理**：地震速報／地震報告／颱風 本就屬全國或大範圍
/// 示警；feed 的 polygon／areaDesc 地理範圍判斷 v0 未做（**披露**）。
/// 海嘯未列入（人類僅指定地震／颱風；要納入改此常數即可）。
const List<String> kEmergencyFlowCategories = <String>[
  '地震速報',
  '地震報告',
  '颱風',
];

/// 該則示警是否觸發緊急求助流程（category 含關鍵字即命中，同主清單規則）。
bool isEmergencyFlowAlert(EmergencyAlert alert) {
  return kEmergencyFlowCategories.any((k) => alert.category.contains(k));
}

// ── 第六十四批④：示警測試選項（人類要求「提供緊急訊息測試選項」）──────
//
// 用途：驗證緊急訊息管線（首頁紅卡片／求助流程彈窗／詳情對話框）**不待真實
// 災害**。機制＝本機 kv 存一則合成示警（JSON）；rooms_screen `_loadEmergency`
// 讀取後與官方 feed 同座顯示（id 去重），關閉開關／逾時即消失。
//
// ⚠️ 官方 feed 規則第 1 條「cap:status=test 勿用於對外產品」指**官方測試
// 資料**；本合成示警為**本機測試選項**（明確標示「測試」、不落入任何官方
// 資料欄位），僅存本機、不對外送出。

/// kv key：示警測試選項（JSON；空／無＝關閉）。
const String kEmergencyTestAlertKey = 'emergency_test_alert';

/// 第一百零六批：測試示警開關變更通知。
/// 開關頁寫 kv 後遞增；rooms_screen／main_shell 監聽並立即刷新，
/// 不必等下一次 sync 或 15 分鐘輪詢（人類回報「測試時橫幅沒出現」）。
final ValueNotifier<int> emergencyRefreshNotifier = ValueNotifier<int>(0);

/// 測試示警有效時限（開啟後 1 小時自動失效；避免忘記關閉長期掛卡片）。
const Duration kEmergencyTestAlertTtl = Duration(hours: 1);

/// 建立一則**合成**測試示警。`id` 帶 `homing-test-` 前綴（不與官方 feed 的
/// entry id 相撞）；category 含「地震速報（測試）」→ 同時命中
/// `isEmergencyFlowAlert`（可測求助流程彈窗）。
EmergencyAlert buildTestEmergencyAlert({required String id, DateTime? now}) {
  final at = (now ?? DateTime.now()).toLocal();
  return EmergencyAlert(
    id: id,
    category: '地震速報（測試）', // 文案草案：卡片標題＋明示測試性質
    sender: 'Homing 測試',
    summary: '這是測試示警（非真實災害）：用於確認緊急訊息顯示與求助流程。', // 文案草案
    link: '',
    sent: at,
    expires: at.add(kEmergencyTestAlertTtl),
  );
}

/// 合成示警 → kv JSON（僅本機；不送網路）。
String encodeTestEmergencyAlert(EmergencyAlert alert) {
  return jsonEncode(<String, Object?>{
    'id': alert.id,
    'category': alert.category,
    'sender': alert.sender,
    'summary': alert.summary,
    'sent': alert.sent?.toIso8601String(),
    'expires': alert.expires?.toIso8601String(),
  });
}

/// kv JSON → 合成示警；格式錯誤／**已過期** → null（關閉或自然失效）。
/// 回傳的示警**未經**官方 feed（Actual／expires）以外的過濾——合成資料
/// 自帶 expires，逾期即失效。
EmergencyAlert? parseTestEmergencyAlert(Object? raw, {DateTime? now}) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final expiresRaw = decoded['expires'];
    final expires =
        expiresRaw is String ? DateTime.tryParse(expiresRaw) : null;
    if (expires == null ||
        expires.isBefore(now ?? DateTime.now())) {
      return null; // 過期（或無效）＝自動關閉。
    }
    final sentRaw = decoded['sent'];
    return EmergencyAlert(
      id: decoded['id'] is String ? decoded['id'] as String : '',
      category: decoded['category'] is String ? decoded['category'] as String : '',
      sender: decoded['sender'] is String ? decoded['sender'] as String : '',
      summary: decoded['summary'] is String ? decoded['summary'] as String : '',
      link: '',
      sent: sentRaw is String ? DateTime.tryParse(sentRaw) : null,
      expires: expires,
    );
  } on Object {
    return null;
  }
}

/// 讀取本機 kv 的測試示警（`AppSettings.get`；無 sqflite 環境丟例外由呼叫端
/// 捕捉 → 視同關閉）。回 null＝關閉／過期／格式錯誤。
Future<EmergencyAlert?> loadTestEmergencyAlert() async {
  // 延遲 import 於函式內不可行 → 直接 import app_settings（無循環依賴：
  // app_settings 不 import emergency_feed）。
  final raw = await AppSettings.get(kEmergencyTestAlertKey);
  return parseTestEmergencyAlert(raw);
}

// ── 第六十四批⑤：傳送現況（人類指示 2026-11-17）──────────────────────
// 人類指示：不要一進軟體就彈「需要幫忙嗎」；首頁緊急卡片的「安否報告」改名
// 「傳送現況」——先選**有沒有受影響**（訊息送給好友公開狀態），受影響才出現
// 求助選項。送出後**緊急卡片顯示已通報名單與現況**（是否受影響）。
// 記錄僅存本機 kv（JSON map：alertId → 記錄；不對外同步）。

/// kv key：傳送現況記錄（JSON map）。
const String kEmergencyStatusKey = 'emergency_status';

/// 單一示警的現況記錄（本機；供緊急卡片顯示）。
class EmergencyStatusRecord {
  const EmergencyStatusRecord({
    required this.alertId,
    required this.affected,
    required this.notified,
    required this.updatedAt,
  });

  final String alertId;

  /// true＝受影響；false＝沒事（報平安）。
  final bool affected;

  /// 已送出的對象（房間 id＋送出當下的顯示名快照；送出即記錄，不回收）。
  final List<({String roomId, String name})> notified;

  final DateTime updatedAt;
}

/// 記錄 → JSON（純函式，供測試）。
Map<String, Object?> encodeEmergencyStatusRecord(EmergencyStatusRecord r) {
  return <String, Object?>{
    'alertId': r.alertId,
    'affected': r.affected,
    'notified': [
      for (final n in r.notified)
        <String, Object?>{'id': n.roomId, 'name': n.name},
    ],
    'updatedAt': r.updatedAt.toIso8601String(),
  };
}

/// JSON → 記錄；格式錯誤 → null（純函式，供測試）。
EmergencyStatusRecord? parseEmergencyStatusRecord(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final alertId = raw['alertId'];
  final affected = raw['affected'];
  final updatedAtRaw = raw['updatedAt'];
  if (alertId is! String ||
      alertId.isEmpty ||
      affected is! bool ||
      updatedAtRaw is! String) {
    return null;
  }
  final updatedAt = DateTime.tryParse(updatedAtRaw);
  if (updatedAt == null) {
    return null;
  }
  final notifiedRaw = raw['notified'];
  final notified = <({String roomId, String name})>[];
  if (notifiedRaw is List) {
    for (final n in notifiedRaw) {
      if (n is Map && n['id'] is String && n['name'] is String) {
        notified.add((roomId: n['id'] as String, name: n['name'] as String));
      }
    }
  }
  return EmergencyStatusRecord(
    alertId: alertId,
    affected: affected,
    notified: notified,
    updatedAt: updatedAt,
  );
}

/// 讀取全部現況記錄（kv JSON map：alertId → 記錄；無／格式錯誤 → 空 map）。
Future<Map<String, EmergencyStatusRecord>> loadEmergencyStatuses() async {
  final raw = await AppSettings.get(kEmergencyStatusKey);
  if (raw is! String || raw.isEmpty) {
    return {};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return {};
    }
    final out = <String, EmergencyStatusRecord>{};
    for (final entry in decoded.entries) {
      final rec = parseEmergencyStatusRecord(entry.value);
      if (rec != null) {
        out[rec.alertId] = rec;
      }
    }
    return out;
  } on Object {
    return {};
  }
}

/// 合併寫入一筆記錄（既有其他示警的記錄保留；純函式部分＋kv 寫入）。
Future<void> recordEmergencyStatus(EmergencyStatusRecord record) async {
  final existing = await loadEmergencyStatuses();
  existing[record.alertId] = record;
  final encoded = <String, Object?>{
    for (final e in existing.entries) e.key: encodeEmergencyStatusRecord(e.value),
  };
  await AppSettings.set(kEmergencyStatusKey, jsonEncode(encoded));
}

// ── 第六十六批：好友現況解析（人類指示 2026-11-17）────────────────────
// 人類指示：「通報有沒有受影響只需要在緊急訊息下顯示哪些好友受影響和沒受
// 影響」。App 解析好友傳來的現況訊息（emergency_flow_screen 既有模板格式：
// 【緊急現況】／【報平安】開頭＋「示警：類別」行），在緊急卡片下逐位顯示
// 該好友狀態；沒受影響的人不需要再傳訊息。
//
// **披露**：①v0 只看各 1:1 房**最新一則**訊息（房間 lastEvent；歷史訊息不
// 回掃）；②比對＝本文含標記＋含示警類別字樣＋時間窗（示警 sent 之後寬容
// 5 分鐘、expires 之前）；③純文字比對，無簽章驗證（同 App 好友之間）。

/// 好友現況標記（與 emergency_flow_screen `emergencyStatusMessage` 模板一致）。
const String kFriendStatusAffectedMark = '【緊急現況】';
const String kFriendStatusSafeMark = '【報平安】';

/// 解析好友現況訊息本文（**純函式**，供測試；不打網路）。
/// 回 true＝受影響、false＝沒事（報平安）、null＝非現況訊息或示警類別不匹配。
bool? parseFriendEmergencyStatus(String body, String alertCategory) {
  final isAffected = body.contains(kFriendStatusAffectedMark);
  final isSafe = body.contains(kFriendStatusSafeMark);
  if (!isAffected && !isSafe) {
    return null;
  }
  if (isAffected && isSafe) {
    // 兩個標記同時出現（異常）→ 不判定。
    return null;
  }
  if (!body.contains(alertCategory)) {
    return null;
  }
  return isAffected;
}
