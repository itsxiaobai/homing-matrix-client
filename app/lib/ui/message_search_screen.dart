// 2.7 — 訊息／聊天室搜尋（功能化：結果點擊 → 跳進該房間）；草案，待人類設計定稿。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'chat_screen.dart';

typedef MessageSearch = Future<List<String>> Function(String query);

class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({super.key, this.client, this.search, this.onSelectRoom});

  /// 若提供，搜尋範圍為 client.rooms，結果點擊跳進該房間。
  final Client? client;

  /// 舊介面相容：自訂搜尋函式（回傳字串列表）。
  final MessageSearch? search;

  /// 結果點擊回呼（可選）；未提供時預設 push ChatScreen。
  final void Function(Room room)? onSelectRoom;

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _controller = TextEditingController();
  List<Room> _results = const [];
  List<String> _stringResults = const [];
  bool _busy = false;

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
      list = client.rooms.where((r) {
        final name = r.name.toLowerCase();
        final preview = (r.lastEvent?.body ?? '').toLowerCase();
        return name.contains(ql) || preview.contains(ql) || r.id.toLowerCase().contains(ql);
      }).toList();
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
      appBar: AppBar(title: const Text('搜尋')), // 文案草案
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              onChanged: _runSearch,
              decoration: const InputDecoration(
                labelText: '關鍵字',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : (_stringResults.isNotEmpty
                      ? ListView.builder(
                          itemCount: _stringResults.length,
                          itemBuilder: (context, index) => ListTile(title: Text(_stringResults[index])),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final room = _results[index];
                            final title = room.name.isNotEmpty ? room.name : room.id;
                            return ListTile(
                              title: Text(title),
                              subtitle: Text(room.lastEvent?.body ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
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
}
