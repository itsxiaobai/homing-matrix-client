// 任務：Phase 0 / 0.10（骨架）＋ Phase 1 / 1.3（homeserver 選項）
// 草案，待人類設計：本檔為「無樣式／最小樣式」骨架元件（依 AGENTS.md UI 規則）。
// * 不寫死寬度（僅依內容與 Responsive 容器預設行為）
// * 未定配色／字型／間距／圖示（DESIGN.md 定稿前不越界）
// 預設 matrix.org（人類決策 2026-10-31）；另提供「Homing 自架伺服器」選項（尚未架設）。
import 'package:flutter/material.dart';

import '../auth.dart';
import '../client_factory.dart';
import '../homeserver_url.dart';

/// 檢查 homeserver 的動作抽象，供 widget 測試注入（不打網路）。
typedef ServerChecker = Future<String?> Function(Uri homeserverUrl);

/// homeserver 選項（草案；最終文案與版面由人類定稿）。
enum HomeserverPreset {
  matrixOrg('matrix.org（預設）'),
  custom('自訂 homeserver'),
  ringSelfHosted('Homing 自架伺服器（尚未提供）');

  const HomeserverPreset(this.label);
  final String label;
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, this.checkServer, this.onHandled});

  final ServerChecker? checkServer;

  /// 連線檢查通過後的出口：導向登入畫面（1.3）。
  final void Function(Uri resolvedUrl)? onHandled;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _urlController = TextEditingController(text: defaultHomeserver.host);
  HomeserverPreset _preset = HomeserverPreset.matrixOrg;
  String? _message; // 錯誤或成功訊息
  bool _checking = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _selectPreset(HomeserverPreset? preset) {
    if (preset == null) {
      return;
    }
    setState(() {
      _preset = preset;
      _message = null;
      switch (preset) {
        case HomeserverPreset.matrixOrg:
          _urlController.text = defaultHomeserver.host;
        case HomeserverPreset.custom:
          _urlController.clear();
        case HomeserverPreset.ringSelfHosted:
          // 尚未架設：不提供位址，僅說明。
          _urlController.clear();
          _message = 'Homing 自架伺服器尚未架設；目前請使用 matrix.org 或自訂 homeserver。';
      }
    });
  }

  Future<void> _onSubmit() async {
    if (_preset == HomeserverPreset.ringSelfHosted) {
      setState(() {
        _message = 'Homing 自架伺服器尚未架設；目前請使用 matrix.org 或自訂 homeserver。';
      });
      return;
    }

    final uri = parseUserHomeserverUrl(_urlController.text);
    if (uri == null) {
      setState(() {
        _message = '請輸入有效的 homeserver 位址（例如 matrix.org）';
      });
      return;
    }
    setState(() {
      _checking = true;
      _message = null;
    });
    String? error;
    try {
      error = await (widget.checkServer ?? checkServer)(uri);
    } catch (_) {
      error = '無法連線：請檢查位址與網路';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _message = error ?? '連線成功';
    });
    if (error == null) {
      widget.onHandled?.call(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('選擇 homeserver'), // 文案待 UI 定稿
              DropdownButtonFormField<HomeserverPreset>(
                initialValue: _preset,
                decoration: const InputDecoration(labelText: '伺服器選項'),
                items: [
                  for (final preset in HomeserverPreset.values)
                    DropdownMenuItem(
                      value: preset,
                      enabled: preset != HomeserverPreset.ringSelfHosted,
                      child: Text(preset.label),
                    ),
                ],
                onChanged: _checking ? null : _selectPreset,
              ),
              TextField(
                controller: _urlController,
                enabled: !_checking &&
                    _preset != HomeserverPreset.ringSelfHosted,
                onChanged: (_) {
                  if (_preset != HomeserverPreset.custom) {
                    setState(() => _preset = HomeserverPreset.custom);
                  }
                },
                onSubmitted: (_) => _onSubmit(),
                decoration: const InputDecoration(
                  labelText: 'homeserver 位址',
                  // placeholder 文案待定稿
                ),
              ),
              TextButton(
                onPressed: _checking ? null : _onSubmit,
                child: Text(_checking ? '檢查中…' : '檢查連線'),
              ),
              if (_message != null) Text(_message!),
              // 說明：matrix.org 的註冊由網頁處理（客戶端 /register 已關閉）。
              const Text('matrix.org 採網頁註冊；下一步可前往登入或註冊頁。'),
            ],
          ),
        ),
      ),
    );
  }
}
