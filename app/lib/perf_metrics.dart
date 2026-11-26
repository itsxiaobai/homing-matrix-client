// 效能量測記錄（第五十七批・效能）——**唯讀、不含任何使用者資料**。
//
// 用途：人類回報「資料太多就載到超卡」「Android 直接當成沒有回應」→ 需要
// **可重現的數值**而不是目視。本檔提供極簡的記憶體量測記錄：
// * 聊天室每次重載記一筆（耗時、訊息數、計畫列數、已建構列數）。
// * 設定 → 進階 → 診斷資訊 可直接看到最近幾筆（**不寫入磁碟、不上傳**）。
//
// ⚠️ 只記錄**計數與耗時**，**不記錄訊息內容／寄件者／事件 ID**（避免個資
// 進入診斷輸出）。保留上限 20 筆（記憶體可忽略）。
library;

/// 一筆量測記錄。
class PerfSample {
  const PerfSample({
    required this.name,
    required this.micros,
    this.counts = const {},
  });

  /// 記錄名稱（例如 `chat.load`）。
  final String name;

  /// 耗時（微秒）。
  final int micros;

  /// 附加計數（例如訊息數、列數）。
  final Map<String, int> counts;

  /// 人可讀格式。
  String format() {
    final buf = StringBuffer('$name：${(micros / 1000).toStringAsFixed(1)} ms');
    if (counts.isNotEmpty) {
      final parts = counts.entries.map((e) => '${e.key}=${e.value}').join('、');
      buf.write('（$parts）');
    }
    return buf.toString();
  }
}

/// 記憶體內的量測記錄（靜態；單一行程）。
class PerfLog {
  PerfLog._();

  static const int maxSamples = 20;
  static final List<PerfSample> _samples = <PerfSample>[];

  /// 記錄一筆（**不拋例外**；量測不得影響主流程）。
  static void record(String name, int micros, [Map<String, int>? counts]) {
    try {
      _samples.add(PerfSample(
        name: name,
        micros: micros,
        counts: counts ?? const {},
      ));
      while (_samples.length > maxSamples) {
        _samples.removeAt(0);
      }
    } catch (_) {
      // 量測失敗不得影響 App 行為。
    }
  }

  /// 最近幾筆（由新到舊）。
  static List<PerfSample> get samples => List<PerfSample>.unmodifiable(_samples);

  /// 最近幾筆的人可讀摘要（ newest first）。
  static String dump({int limit = 10}) {
    if (_samples.isEmpty) {
      return '（尚無記錄）';
    }
    final items = _samples.reversed.take(limit).map((s) => s.format()).join('\n');
    return items;
  }

  /// 清空（診斷頁可呼叫；僅影響本行程）。
  static void clear() => _samples.clear();
}
