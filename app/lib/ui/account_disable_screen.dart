// 2.10 skeleton — account disable/erase (UI only + injected action)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef AccountDisableAction = Future<void> Function({bool erase});

class AccountDisableScreen extends StatefulWidget {
  const AccountDisableScreen({super.key, this.disable});
  final AccountDisableAction? disable;

  @override
  State<AccountDisableScreen> createState() => _AccountDisableScreenState();
}

class _AccountDisableScreenState extends State<AccountDisableScreen> {
  bool _erase = true;
  bool _busy = false;
  String? _message;

  Future<void> _onDisable() async {
    setState(() {_busy = true; _message = null;});
    String? err;
    try {
      await (widget.disable ?? (e) async {})(erase: _erase);
    } catch (_) { err = '停用失敗'; }
    if (!mounted) return;
    setState(() {_busy = false; _message = err ?? '已停用帳號（伺服器端依 homeserver 政策）';});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('停用帳號（Skeleton）'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _erase,
              onChanged: _busy ? null : (v) => setState(() => _erase = v ?? false),
              title: const Text('Erase（ directory remove; follow homeserver policy）'),
            ),
            Text(S.t('注意：Matrix 停用不等于從伺服器資料庫刪除；伺服器依 homeserver 政策處理。')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _onDisable,
              child: Text(_busy ? '停用中…' : '確認停用'),
            ),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}
