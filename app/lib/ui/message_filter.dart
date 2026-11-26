// Task 1.9b — 訊息過濾（關鍵字 / 封鎖者訊息隱藏）skeleton
// 純函式，供 UI 或 Chat timeline 用；Scope: hide matching content.
// 支援： blocked sender mxids, keyword contains, case-insensitive.
import 'package:matrix/matrix.dart';

class ChatFilter {
  final Set<String> blockedSenders;
  final Set<String> mutedKeywords;

  const ChatFilter({this.blockedSenders = const {}, this.mutedKeywords = const {}});

  /// Should this message event be visible in UI? Messages from blocked sender or
  /// matching muted keyword are hidden.
  bool isVisible(Event event) {
    if (blockedSenders.contains(event.senderId)) {
      return false;
    }
    final body = event.body.toLowerCase();
    for (final k in mutedKeywords) {
      if (body.contains(k.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  /// Filter a list of events (ids, oldest-first expected) to visible subset.
  List<Event> filterEvents(List<Event> events) {
    return events.where(isVisible).toList();
  }
}
