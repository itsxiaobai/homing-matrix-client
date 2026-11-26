// UI 重構（依人類 LINE_ref 標註，2026-11-01）— 時間／日期顯示純函式。
// 文案格式屬「草案，待人類設計定稿」（AGENTS.md：最終版面由人類設計）。
// 規則僅取自產業通用慣例（藍圖 §十二 允許沿用）：泡內 HH:mm；列表今天顯示時間、
// 其他顯示日期；泡泡間在日期變更處插入分隔標籤（今天／昨天／MM/DD）。
library;

import '../l10n/app_strings.dart';

/// 泡內／列表今天的時間顯示：24 小時制 HH:mm。
String formatChatTime(DateTime t) {
  final d = t.toLocal();
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// 對話列表列右側時間：今天 → HH:mm；今年 → MM/DD；跨年 → YYYY/MM/DD。
String formatListTime(DateTime t) {
  final d = t.toLocal();
  final now = DateTime.now();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) {
    return formatChatTime(d);
  }
  if (d.year != now.year) {
    return '${d.year}/$mm/$dd';
  }
  return '$mm/$dd';
}

/// 訊息流水線中、日期變更處的分隔標籤。
/// 今天 → 「今天」；昨天 → 「昨天」；今年其他日 → 「MM/DD」；跨年 → 「YYYY/MM/DD」。
String daySeparatorLabel(DateTime t) {
  final d = t.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(d.year, d.month, d.day);
  final diffDays = today.difference(date).inDays;
  if (diffDays == 0) {
    return S.t('今天');
  }
  if (diffDays == 1) {
    return S.t('昨天');
  }
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  if (d.year != now.year) {
    return '${d.year}/$mm/$dd';
  }
  return '$mm/$dd';
}
