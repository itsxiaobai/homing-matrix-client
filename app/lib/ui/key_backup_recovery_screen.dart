// Task 1.5 skeleton — key backup recovery (UI only)
import 'package:flutter/material.dart';

typedef RecoveryAction = Future<void> Function(String recoveryKey);

class KeyBackupRecoveryScreen extends StatefulWidget {
  const KeyBackupRecoveryScreen({
    super.key,
    this.onRecover,
  });

  final RecoveryAction? onRecover;

  @override
  State<KeyBackupRecoveryScreen> createState() => _KeyBackupRecoveryScreenState();
}

class _KeyBackupRecoveryScreenState extends State<KeyBackupRecoveryScreen> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    String? error;
    try {
      await (widget.onRecover ?? _default)(_controller.text.trim());
    } catch (_) {
      error = '恢復失敗';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? '已嘗試恢復（需 SDK 官方流程，人工審核）';
    });
  }

  Future<void> _default(String key) async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('金鑰備份恢復（recovery key）')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Recovery key / 密語',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '恢復中…' : '恢復金鑰'),
            ),
            if (_message != null) Text(_message!),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '⚠️ 歷史訊息無法恢復時沒有 recovery key 且沒有任何已驗證裝置。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
