// 2.9 skeleton — data export (json/html exporter injected)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef ExportAction = Future<void> Function(String format);

class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key, this.exporter});
  final ExportAction? exporter;

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _onExport(String format) async {
    setState(() {_busy = true; _message = null;});
    String? err;
    try {
      await (widget.exporter ?? (f) async {})(format);
    } catch (_) { err = '匯出失敗'; }
    if (!mounted) return;
    setState(() {_busy = false; _message = err ?? '匯出成功（$format）';});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('資料匯出'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextButton(onPressed: _busy ? null : () => _onExport('JSON'), child: Text(_busy ? '匯出中…' : '匯出 JSON')),
            TextButton(onPressed: _busy ? null : () => _onExport('HTML'), child: Text(S.t('匯出 HTML'))),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}
