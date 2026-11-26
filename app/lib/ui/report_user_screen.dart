// Task 1.9a — 檢舉機制 skeleton (UI-only / non-crypto)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef ReportUserAction = Future<void> Function(String targetId, String reason);

class ReportUserScreen extends StatefulWidget {
  const ReportUserScreen({super.key, this.report, this.targetDefault});
  final ReportUserAction? report;
  final String? targetDefault;

  @override
  State<ReportUserScreen> createState() => _ReportUserScreenState();
}

class _ReportUserScreenState extends State<ReportUserScreen> {
  final _target = TextEditingController();
  final _reason = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.targetDefault != null) {
      _target.text = widget.targetDefault!;
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final target = _target.text.trim();
    final reason = _reason.text.trim();
    if (target.isEmpty || reason.isEmpty) {
      setState(() => _message = 'target 與 reason 必須填寫');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });

    String? error;
    try {
      await (widget.report ?? _defaultReport)(target, reason);
    } catch (_) {
      error = '檢舉送出失敗';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? '檢舉已送出：target=$target';
    });
  }

  Future<void> _defaultReport(String target, String reason) async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('檢舉'))), // UI draft
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _target,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '目標 Matrix ID'),
            ),
            TextField(
              controller: _reason,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '原因（詐騙 / 騷擾 / 垃圾 …）'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '送出中…' : '送出檢舉'),
            ),
            if (_message != null) Text(_message!),
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(S.t('注意：上傳 homeserver 後，系統可能不顯示回應；UI 不應以回應狀態推斷對象是否存在（藍圖 §檢舉實作注意）')),
            ),
          ],
        ),
      ),
    );
  }
}
