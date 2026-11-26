// 第七十九批（人類指示「製作預約傳送功能」）：跨房間預約管理頁。
// 既有功能在 chat_screen 房間選單可看本房預約；本頁從設定進入，列出所有房。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/app_strings.dart';
import '../scheduled_messages.dart';
import 'app_icons_generated.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key, required this.client});

  final Client client;

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  List<ScheduledMessage> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final all = await loadScheduledFromServer(widget.client);
    if (!mounted) return;
    setState(() {
      _items = all..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      _loading = false;
    });
  }

  /// #5：编辑預約（改時間／週期／無聲／Markdown）。
  Future<void> _edit(ScheduledMessage m) async {
    final now = DateTime.now();
    final initial = DateTime.fromMillisecondsSinceEpoch(m.dueAt);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? initial : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => TextFieldDialog(
        title: S.t('重複週期（天，0＝只送一次）'),
        initial: '${m.repeatDays}',
      ),
    );
    if (days == null || !mounted) return;
    await updateScheduledMessage(widget.client, m.id, ScheduledMessage(
      id: m.id,
      roomId: m.roomId,
      text: m.text,
      dueAt: due.millisecondsSinceEpoch,
      silent: m.silent,
      markdown: m.markdown,
      repeatDays: days < 0 ? 0 : days,
    ));
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('預約訊息'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(S.t('目前沒有預約訊息')))
              : ListView(
                  children: [
                    for (final m in _items)
                      ListTile(
                        leading: Icon(AllIcons.schedule),
                        title: Text(
                          m.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${S.t('房間')}：${m.roomId}\n'
                          '${formatScheduledDue(m.dueAt)}'
                          '${m.repeatDays > 0 ? ' · 每 ${m.repeatDays} 天' : ''}'
                          '${m.silent ? ' · ${S.t('無聲')}' : ''}'
                          '${m.markdown ? ' · Markdown' : ''}'
                          '${m.failCount > 0 ? ' · ${S.t('失敗')} ${m.failCount}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: S.t('编辑預約'),
                              icon: Icon(AllIcons.editOutlined),
                              onPressed: () =>
                                  unawaited(_edit(m)),
                            ),
                            IconButton(
                              tooltip: S.t('取消預約'),
                              icon: Icon(AllIcons.close),
                              onPressed: () async {
                                await removeScheduledMessage(widget.client, m.id);
                                unawaited(_load());
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

String formatScheduledDue(int dueAt) {
  final t = DateTime.fromMillisecondsSinceEpoch(dueAt);
  return '${t.year}/${_two(t.month)}/${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 簡單整數輸入 dialog（供週期設定）。
class TextFieldDialog extends StatefulWidget {
  const TextFieldDialog({
    super.key,
    required this.title,
    required this.initial,
  });

  final String title;
  final String initial;

  @override
  State<TextFieldDialog> createState() => _TextFieldDialogState();
}

class _TextFieldDialogState extends State<TextFieldDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t('取消')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_controller.text) ?? 0),
          child: Text(S.t('儲存')),
        ),
      ],
    );
  }
}
