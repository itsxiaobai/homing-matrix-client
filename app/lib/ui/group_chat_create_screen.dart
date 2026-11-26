// 2.1 skeleton — group chat creation (UI only)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef CreateGroupRoom = Future<void> Function(String name, List<String> invited);

class GroupChatCreateScreen extends StatefulWidget {
  const GroupChatCreateScreen({super.key, this.create});
  final CreateGroupRoom? create;

  @override
  State<GroupChatCreateScreen> createState() => _GroupChatCreateScreenState();
}

class _GroupChatCreateScreenState extends State<GroupChatCreateScreen> {
  final _name = TextEditingController();
  final _member = TextEditingController();
  final List<String> _members = [];
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _member.dispose();
    super.dispose();
  }

  void _addMember() {
    final id = _member.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _members.add(id);
      _member.clear();
    });
  }

  Future<void> _onCreate() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _message = '群组名称必填');
      return;
    }
    setState(() {_busy = true; _message = null;});
    String? error;
    try {
      await (widget.create ?? ((name, members) async {}))(name, List.unmodifiable(_members));
    } catch (_) {
      error = '建立失败';
    }
    if (!mounted) return;
    setState(() {_busy = false; _message = error ?? '群组建立完成（SDK 通过）';});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('建立群组（Skeleton）'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _name, enabled: !_busy, decoration: const InputDecoration(labelText: '群组名称')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _member, enabled: !_busy, decoration: const InputDecoration(labelText: '邀请 Matrix ID'))),
                TextButton(onPressed: _busy ? null : _addMember, child: Text(S.t('加入'))),
              ],
            ),
            Text('${S.t('成员')}: ${_members.join(', ')}'),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _onCreate, child: Text(_busy ? '建立中…' : '建立群组')),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}
