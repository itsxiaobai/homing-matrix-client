// 1.10 Push notifications skeleton (no third-party dependency, no keys stored)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

typedef NotificationPermissionRequest = Future<bool> Function();

class PushPermissionScreen extends StatefulWidget {
  const PushPermissionScreen({
    super.key,
    this.requestPermission,
  });

  final NotificationPermissionRequest? requestPermission;

  @override
  State<PushPermissionScreen> createState() => _PushPermissionScreenState();
}

class _PushPermissionScreenState extends State<PushPermissionScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _onRequest() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    bool granted = false;
    String? error;
    try {
      granted = await (widget.requestPermission ?? _defaultRequest)();
    } catch (_) {
      error = '權限請求失敗';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ??
          (granted
              ? '已取得權限（本機通知 v0：App 非前景才通知；無 FCM → 進程被殺後不通知）'
              : '權限被拒絕'); // 文案草案
    });
  }

  /// 批次十二②修（人類實測「通知功能沒辦法啟動」根因＝本檔 stub）：改接官方
  /// ring/local_notifications channel `request_permission`（Android 13+ 系統
  /// 授權對話框；<13 無 runtime 權限＝直接 true）。零新依賴。
  Future<bool> _defaultRequest() async {
    try {
      return await const MethodChannel('homing/local_notifications')
              .invokeMethod<bool>('request_permission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('通知設定'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('本機通知 v0（零第三方依賴）：App 非前景時由 Android 發本地通知。')), // 文案草案
            Text(S.t('按下開始＝請求 Android 13+ 系統通知權限（POST_NOTIFICATIONS）。')), // 文案草案

            if (_message != null) Text(_message!),
            TextButton(
              onPressed: _busy ? null : _onRequest,
              child: Text(_busy ? '請求中…' : '請求通知權限'),
            ),
          ],
        ),
      ),
    );
  }
}
