// 2.7 — 訊息／聊天室搜尋（功能化：結果點擊 → 跳進該房間）。
//
// 第四十八批：加上**過濾條件**（時間範圍 ＋ 訊息類型，見 `search_filters.dart`
// 的純函式）與**訊息層級**的搜尋結果（不再只搜房名／最後一則預覽）。
//
// 搜尋範圍：
// - 未指定房間 → 掃描所有房間的已載入 timeline（官方 `Room.getTimeline()`，
//   **只讀本機已載入的事件**，不額外打網路請求）。
// - 指定房間（從聊天室內進入）→ 只掃該房。
//
// 結果點擊 → 跳進該房（與既有行為一致）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'chat_screen.dart';
import 'search_filters.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import 'line_style.dart'; // 68e/68f LINE 版面

typedef MessageSearch = Future<List<String>> Function(String query);

/// 一筆搜尋結果（房間 ＋ 該則訊息）。
class MessageSearchHit {
  const MessageSearchHit({
    required this.room,
    required this.body,
    required this.sentAt,
    this.msgType,
    this.isSticker = false,
    this.eventId,
  });

  final Room room;
  final String body;
  final DateTime? sentAt;
  final String? msgType;
  final bool isSticker;
  final String? eventId;
}

class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({
    super.key,
    this.client,
    this.search,
    this.onSelectRoom,
    this.room,
  });

  /// 若提供，搜尋範圍為 client.rooms，結果點擊跳進該房間。
  final Client? client;

  /// 舊介面相容：自訂搜尋函式（回傳字串列表）。
  final MessageSearch? search;

  /// 結果點擊回呼（可選）；未提供時預設 push ChatScreen。
  final void Function(Room room)? onSelectRoom;

  /// 限定搜尋範圍（從聊天室內進入時＝該房）；null＝全部房間。
  final Room? room;

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _controller = TextEditingController();
  List<Room> _results = const [];
  List<String> _stringResults = const [];
  List<MessageSearchHit> _hits = const [];
  bool _busy = false;

  /// 第四十八批：過濾條件（時間 ＋ 類型）。
  SearchFilters _filters = const SearchFilters();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _stringResults = const [];
        _hits = const [];
      });
      return;
    }
    setState(() => _busy = true);
    List<Room> list = const [];
    if (widget.search != null) {
      // 舊介面：字串結果，無房間跳轉。
      final strs = await widget.search!(q);
      if (!mounted) return;
      // 以空 Room 列表表示；測試只檢查文字。
      setState(() {
        _busy = false;
        _stringResults = strs;
      });
      return;
    }
    final client = widget.client;
    if (client != null) {
      final ql = q.toLowerCase();
      final now = DateTime.now();
      final rooms = widget.room != null ? [widget.room!] : client.rooms;
      // 第四十八批：掃描已載入 timeline 的**訊息層級**結果（含過濾條件）。
      final hits = <MessageSearchHit>[];
      for (final room in rooms) {
        // 房名／最後一則預覽命中 → 也算結果（維持舊行為）。
        final name = room.name.toLowerCase();
        final preview = (room.lastEvent?.body ?? '').toLowerCase();
        if (name.contains(ql) ||
            preview.contains(ql) ||
            room.id.toLowerCase().contains(ql)) {
          list = [...list, room];
        }
        List<Event> events;
        try {
          final timeline = await room.getTimeline();
          events = timeline.events;
        } catch (_) {
          continue;
        }
        for (final e in events) {
          if (e.redacted) continue;
          final body = e.body;
          if (body.isEmpty) continue;
          if (!body.toLowerCase().contains(ql)) continue;
          final msgType = e.type == EventTypes.Message ? e.messageType : null;
          final isSticker = e.type == EventTypes.Sticker;
          if (!passesSearchFilters(
            _filters,
            e.originServerTs,
            msgType,
            isSticker,
            now,
          )) {
            continue;
          }
          hits.add(MessageSearchHit(
            room: room,
            body: body,
            sentAt: e.originServerTs,
            msgType: msgType,
            isSticker: isSticker,
            eventId: e.eventId,
          ));
        }
      }
      // 結果上限（避免大量結果拖慢畫面）；最新在前。
      final sorted = hits
        ..sort(
          (a, b) => (b.sentAt ?? DateTime(1970))
              .compareTo(a.sentAt ?? DateTime(1970)),
        );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _results = list;
        _hits = sorted.take(200).toList();
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = list;
    });
  }

  void _select(Room room) {
    if (widget.onSelectRoom != null) {
      widget.onSelectRoom!(room);
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: lineTitlePill(context, S.t('搜尋'))), // 文案草案
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              onChanged: _runSearch,
              decoration: InputDecoration(
                labelText: '關鍵字',
                prefixIcon: Icon(AllIcons.search),
              ),
            ),
            // 第四十八批：過濾 chip 列（時間 ＋ 類型）。
            const SizedBox(height: 8),
            _buildFilterChips(),
            const SizedBox(height: 8),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : (_stringResults.isNotEmpty
                      ? ListView.builder(
                          itemCount: _stringResults.length,
                          itemBuilder: (context, index) =>
                              ListTile(title: Text(_stringResults[index])),
                        )
                      : _hits.isNotEmpty
                          ? ListView.builder(
                              itemCount: _hits.length,
                              itemBuilder: (context, index) {
                                final hit = _hits[index];
                                final title = hit.room.name.isNotEmpty
                                    ? hit.room.name
                                    : hit.room.id;
                                return ListTile(
                                  title: Text(
                                    hit.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    [
                                      title,
                                      if (hit.sentAt != null)
                                        '${hit.sentAt!.month}/${hit.sentAt!.day}',
                                    ].join(' · '),
                                  ),
                                  onTap: () => _select(hit.room),
                                );
                              },
                            )
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final room = _results[index];
                                final title =
                                    room.name.isNotEmpty ? room.name : room.id;
                                return ListTile(
                                  title: Text(title),
                                  subtitle: Text(
                                    room.lastEvent?.body ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _select(room),
                                );
                              },
                            )),
            ),
          ],
        ),
      ),
    );
  }

  /// 第四十八批：過濾 chip 列（時間範圍 ＋ 訊息類型）。
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in SearchTimeRange.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(searchTimeRangeLabel(r)),
                selected: _filters.timeRange == r,
                onSelected: (selected) {
                  setState(() {
                    _filters = _filters.copyWith(
                      timeRange: selected ? r : SearchTimeRange.all,
                    );
                  });
                  _runSearch(_controller.text);
                },
              ),
            ),
          for (final t in SearchMessageType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(searchMessageTypeLabel(t)),
                selected: _filters.type == t,
                onSelected: (selected) {
                  setState(() {
                    _filters = _filters.copyWith(
                      type: selected ? t : SearchMessageType.all,
                    );
                  });
                  _runSearch(_controller.text);
                },
              ),
            ),
        ],
      ),
    );
  }
}
