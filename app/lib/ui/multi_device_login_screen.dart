// Task 1.13 skeleton — multi-device login flow (UI only; E2EE recovery via SDK official)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef MultiDeviceQuickRecovery = Future<void> Function(String input);
typedef MultiDeviceNearbyVerification = Future<void> Function();

class MultiDeviceLoginScreen extends StatefulWidget {
  const MultiDeviceLoginScreen({
    super.key,
    this.recoveryKey,
    this.nearbyVerification,
  });

  final MultiDeviceQuickRecovery? recoveryKey;
  final MultiDeviceNearbyVerification? nearbyVerification;

  @override
  State<MultiDeviceLoginScreen> createState() => _MultiDeviceLoginScreenState();
}

class _MultiDeviceLoginScreenState extends State<MultiDeviceLoginScreen> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function()? cb, String label) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    String? error;
    try {
      await cb?.call();
    } catch (_) {
      error = '$label 失敗';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? '$label 完成（需 SDK 官方流程）';
    });
  }

  Future<void> _onRecover() async {
    await _run(
      () async => widget.recoveryKey?.call(_controller.text.trim()),
      'recovery key',
    );
  }

  Future<void> _onNearby() async {
    await _run(widget.nearbyVerification, 'QR/emoji 驗證');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('多裝置登入（Skeleton）'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('方式A：輸入 recovery key（恢復歷史解密能力）')),
            Text(S.t('方式B：QR/Emoji 驗證已有裝置')),
            TextField(
              controller: _controller,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Recovery key'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _onRecover,
              child: Text(_busy ? '恢復中…' : '方式 A：恢復'),
            ),
            TextButton(
              onPressed: _busy ? null : _onNearby,
              child: Text(S.t('方式 B：QR code')),
            ),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}
