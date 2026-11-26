// 1.9 封鎖使用者 skeleton
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef BlockAction = Future<void> Function(String userId);
typedef UnblockAction = Future<void> Function(String userId);
typedef ListBlocked = Future<List<String>> Function();

class BlockUserScreen extends StatefulWidget {
  const BlockUserScreen({
    super.key,
    this.block,
    this.unblock,
    this.listBlocked,
  });

  final BlockAction? block;
  final UnblockAction? unblock;
  final ListBlocked? listBlocked;

  @override
  State<BlockUserScreen> createState() => _BlockUserScreenState();
}

class _BlockUserScreenState extends State<BlockUserScreen> {
  final _controller = TextEditingController();
  List<String> _blocked = const [];
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await (widget.listBlocked ?? () async => <String>[]).call();
      if (!mounted) return;
      setState(() {
        _blocked = list;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = '無法讀取封鎖名單';
      });
    }
  }

  Future<void> _onBlock() async {
    final mxid = _controller.text.trim();
    if (mxid.isEmpty) {
      setState(() => _message = '請輸入 Matrix ID');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });

    String? error;
    try {
      await (widget.block ?? _defaultBlock)(mxid);
    } catch (_) {
      error = '封鎖失敗';
    }
    if (!mounted) return;
    await _refresh();
    setState(() {
      _busy = false;
      _message = error ?? '已封鎖 $mxid';
    });
  }

  Future<void> _onUnblock(String mxid) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    String? error;
    try {
      await (widget.unblock ?? _defaultUnblock)(mxid);
    } catch (_) {
      error = '解封失敗';
    }
    if (!mounted) return;
    await _refresh();
    setState(() {
      _busy = false;
      _message = error ?? '已解除封鎖 $mxid';
    });
  }

  Future<void> _defaultBlock(String mxid) async {
    // no persistent impl in skeleton; injected in tests
  }

  Future<void> _defaultUnblock(String mxid) async {}

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('封鎖使用者'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Matrix ID',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _onBlock,
              child: Text(_busy ? '處理中…' : '封鎖'),
            ),
            if (_message != null) Text(_message!),
            const SizedBox(height: 8),
            Text(S.t('封鎖名單：')),
            Expanded(
              child: ListView.builder(
                itemCount: _blocked.length,
                itemBuilder: (context, index) {
                  final id = _blocked[index];
                  return ListTile(
                    title: Text(id),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _onUnblock(id),
                      child: Text(S.t('解封')),
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
