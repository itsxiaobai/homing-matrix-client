// 2.2 skeleton — group member management (UI + official SDK hooks)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef InviteMemberAction = Future<void> Function(String mxid);
typedef KickMemberAction = Future<void> Function(String mxid);
typedef MembersSource = Future<List<String>> Function();

class GroupMemberManageScreen extends StatefulWidget {
  const GroupMemberManageScreen({
    super.key,
    this.inviteMember,
    this.kickMember,
    this.loadMembers,
  });

  final InviteMemberAction? inviteMember;
  final KickMemberAction? kickMember;
  final MembersSource? loadMembers;

  @override
  State<GroupMemberManageScreen> createState() => _GroupMemberManageScreenState();
}

class _GroupMemberManageScreenState extends State<GroupMemberManageScreen> {
  final _controller = TextEditingController();
  List<String> _members = const [];
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await (widget.loadMembers ?? _defaultLoad)();
      if (!mounted) return;
      setState(() {
        _members = list;
      });
    } catch (_) {
      if (mounted) setState(() => _message = '載入成員失敗');
    }
  }

  Future<List<String>> _defaultLoad() async => const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _onInvite() async {
    final mx = _controller.text.trim();
    if (mx.isEmpty) return;
    setState(() {_busy = true; _message = null;});
    String? err;
    try {
      await (widget.inviteMember ?? _defaultInvite)(mx);
    } catch (_) { err = '邀請失敗'; }
    if (!mounted) return;
    setState(() {_busy = false; _message = err ?? '已邀請 $mx';});
    await _load();
  }

  Future<void> _onKick(String mx) async {
    if (_busy) return;
    setState(() {_busy = true; _message = null;});
    String? err;
    try {
      await (widget.kickMember ?? (m) async {})(mx);
    } catch (_) { err = '移除失敗'; }
    if (!mounted) return;
    setState(() {_busy = false; _message = err ?? '已移除 $mx';});
    await _load();
  }

  Future<void> _defaultInvite(String mx) async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('群组成员管理（Skeleton）'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _controller, enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Matrix ID')),
            TextButton(onPressed: _busy ? null : _onInvite, child: Text(S.t('邀請'))),
            if (_message != null) Text(_message!),
            Expanded(
              child: ListView.builder(
                itemCount: _members.length,
                itemBuilder: (context, index) {
                  final m = _members[index];
                  return ListTile(
                    title: Text(m),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _onKick(m),
                      child: Text(S.t('移除')),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
