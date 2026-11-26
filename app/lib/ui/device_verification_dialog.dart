// Task 1.5 — SAS 裝置驗證（官方 SDK state machine，App 端零加密邏輯）
//
// 由 matrix SDK 14.2.0 的 KeyVerification 狀態機驅動；本檔只負責
// 顯示 SDK 提供的 SAS（emoji/數字）並呼叫 SDK 官方的 accept/reject/cancel。
// 不實作任何加密／金鑰／簽章邏輯。
import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

/// 是否已有裝置驗證對話框顯示中（第二十五批：跨畫面互斥守門）。
/// rooms_screen 的官方驗證邀請監聽與設定頁「驗證裝置」入口共用此旗標，
/// 避免兩個官方 SAS 對話框疊放（show → 旗標 true；dismiss → false）。
bool deviceVerificationDialogShowing = false;

/// 顯示並驅動一筆 SDK 官方的 KeyVerification 請求。
Future<void> showDeviceVerificationDialog(
  BuildContext context,
  KeyVerification request,
) {
  deviceVerificationDialogShowing = true;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeviceVerificationDialog(request: request),
  ).whenComplete(() => deviceVerificationDialogShowing = false);
}

class _DeviceVerificationDialog extends StatefulWidget {
  const _DeviceVerificationDialog({required this.request});

  final KeyVerification request;

  @override
  State<_DeviceVerificationDialog> createState() =>
      _DeviceVerificationDialogState();
}

class _DeviceVerificationDialogState extends State<_DeviceVerificationDialog> {
  KeyVerification get r => widget.request;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    r.onUpdate = () {
      if (!mounted) return;
      // 自動以 emoji 方法繼續（skeleton：不提供方法選擇 UI）。
      if (r.state == KeyVerificationState.askChoice &&
          r.possibleMethods.contains(EventTypes.Sas)) {
        // fire-and-forget; onUpdate 會再次觸發 rebuild
        // ignore: discarded_futures
        r.continueVerification(EventTypes.Sas);
      }
      setState(() {});
    };
  }

  @override
  void dispose() {
    r.onUpdate = null;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _promptRecoveryKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('需要 recovery key')),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Recovery key'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(S.t('確認')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (key == null || key.isEmpty) return;
    await _run(() => r.openSSSS(recoveryKey: key));
  }

  @override
  Widget build(BuildContext context) {
    final state = r.state;
    // 完成 / 取消 / 錯誤 → 關閉對話框
    if (r.isDone) {
      final ok = state == KeyVerificationState.done && !r.canceled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '裝置驗證完成' : '驗證已取消／失敗'),
          ),
        );
      });
    }

    Widget body;
    List<Widget> actions = [];

    if (state == KeyVerificationState.askSSSS) {
      body = Text(S.t('需要解鎖 secret storage（SSSS）。'));
      actions = [
        TextButton(
          onPressed: _busy ? null : _promptRecoveryKey,
          child: Text(S.t('輸入 recovery key')),
        ),
        TextButton(
          onPressed: _busy ? null : () => _run(() => r.cancel()),
          child: Text(S.t('取消')),
        ),
      ];
    } else if (state == KeyVerificationState.waitingAccept ||
        state == KeyVerificationState.askAccept) {
      body = Text('${S.t('收到來自 ')}${r.userId}${S.t(' 的裝置驗證請求。')}');
      actions = [
        TextButton(
          onPressed: _busy ? null : () => _run(() => r.acceptVerification()),
          child: Text(S.t('接受')),
        ),
        TextButton(
          onPressed: _busy ? null : () => _run(() => r.rejectVerification()),
          child: Text(S.t('拒絕')),
        ),
      ];
    } else if (state == KeyVerificationState.askSas) {
      final emojis = r.sasEmojis;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('請比對雙方畫面顯示的 emoji 是否相同：')),
          const SizedBox(height: 8),
          Text(emojis.map((e) => '${e.emoji} ${e.name}').join('  ')),
        ],
      );
      actions = [
        TextButton(
          onPressed: _busy ? null : () => _run(() => r.acceptSas()),
          child: Text(S.t('相同')),
        ),
        TextButton(
          onPressed: _busy ? null : () => _run(() => r.rejectSas()),
          child: Text(S.t('不同')),
        ),
      ];
    } else {
      body = Text('${S.t('驗證進行中（state: ')}$state）…');
      actions = [
        TextButton(
          onPressed: _busy ? null : () => _run(() => r.cancel()),
          child: Text(S.t('取消')),
        ),
      ];
    }

    return AlertDialog(
      title: Text(S.t('裝置驗證（SAS）')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          body,
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: actions,
    );
  }
}