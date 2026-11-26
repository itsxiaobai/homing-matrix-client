// 訊息列計畫（第五十七批・效能）——把「列的種類與分組旗標」與「Widget 建造」拆開。
//
// 問題（人類 2026-11-16 原話：「資料太多就載到超卡」「Android 直接當成沒有
// 回應」；旁證：App 行程曾被 OS OOM killer 殺，RSS ≈ 1.05 GB）：
// * 舊實作在 `build()` 內以 `_buildRows()` **逐則建立 Widget**（含日期分隔
//   chip），再把整份塞進 `ListView(children: …)` → **沒有視覺化**：訊息數
//   達數百～數千則時，每次 rebuild 都會產生**整棵 Widget 樹** → 主執行緒
//   壅塞（掉幀／ANR）＋記憶體暴增。
// * Flutter 官方解法＝**列表視覺化**（`ListView.builder`）：只為**進入可視
//   範圍**的列建立 Widget。
//
// 本檔＝視覺化的「前置計算」：O(N) 的**輕量資料**計算（日期分隔、組頭／組尾
// 旗標、自己最後一則），**不建立任何 Widget** → 可直接做單元測試。
//
// ⚠️ 本檔**不涉加密、不改同步語意、不改視覺**：列的種類、分組規則、旗標
// 定義與舊 `_buildRows()` 完全一致（見 `chat_screen.dart` 的對照註解）。
library;

/// 列的種類。
enum ChatRowKind {
  /// 日期分隔膠囊（chip）。
  daySeparator,

  /// 一則訊息。
  message,
}

/// 一列的計畫（輕量資料；不含 Widget）。
class ChatRowPlan {
  const ChatRowPlan.daySeparator(this.label)
      : kind = ChatRowKind.daySeparator,
        messageIndex = -1,
        showSender = false,
        showTime = false,
        isLatestOwn = false;

  const ChatRowPlan.message({
    required this.messageIndex,
    required this.showSender,
    required this.showTime,
    required this.isLatestOwn,
  })  : kind = ChatRowKind.message,
        label = null;

  final ChatRowKind kind;

  /// 日期分隔文字（僅 [ChatRowKind.daySeparator]）。
  final String? label;

  /// 對應的訊息索引（僅 [ChatRowKind.message]）。
  final int messageIndex;

  /// 是否為**組頭**（顯示頭像＋名字）：發送者與前一則不同時為 true。
  final bool showSender;

  /// 是否為**組尾**（顯示時間）：下一則換人／換日／沒有下一則時為 true。
  final bool showTime;

  /// 是否為「自己送出的最後一則」（可能顯示已讀標記）。
  final bool isLatestOwn;
}

/// 依訊息清單算出列計畫（**不建立 Widget**）。
///
/// 參數（皆為取值函式 → 本檔不認識 Flutter Widget，可直接單元測試）：
/// * [messageCount]＝訊息筆數。
/// * [senderOf]＝某索引的寄件者 ID。
/// * [dayLabelOf]＝某索引的日期分隔標籤；**null**＝該則沒有日期分隔
///   （例如 `sentAt` 為 null 的 pending 訊息）。
/// * [myId]＝使用者自己的 ID（用於判斷 `own`）。
/// * [latestOwnIndex]＝自己最後一則的索引（−1＝沒有）。
///
/// 分組規則（與舊 `_buildRows()` 一致）：
/// * 日期分隔 chip 插在「日期與前一則不同」的第一則**之前**。
/// * 組頭＝發送者與前一則不同（日期 chip 另計）。
/// * 組尾＝下一則換人／換日／沒有下一則。
List<ChatRowPlan> buildChatRowPlan({
  required int messageCount,
  required String? Function(int index) senderOf,
  required String? Function(int index) dayLabelOf,
  required String myId,
  required int latestOwnIndex,
}) {
  final plan = <ChatRowPlan>[];
  String? previousDayLabel;
  String? previousSender;
  for (var i = 0; i < messageCount; i++) {
    final day = dayLabelOf(i);
    if (day != null && day != previousDayLabel) {
      plan.add(ChatRowPlan.daySeparator(day));
      previousDayLabel = day;
    }
    final sender = senderOf(i);
    final own = sender == myId;
    final showSender = previousSender == null || previousSender != sender;
    final hasNext = i + 1 < messageCount;
    final nextSender = hasNext ? senderOf(i + 1) : null;
    final nextDay = hasNext ? dayLabelOf(i + 1) : null;
    final showTime = !hasNext ||
        nextSender != sender ||
        (nextDay != null && day != null && nextDay != day);
    previousSender = sender;
    plan.add(ChatRowPlan.message(
      messageIndex: i,
      showSender: showSender,
      showTime: showTime,
      isLatestOwn: own && i == latestOwnIndex,
    ));
  }
  return plan;
}
