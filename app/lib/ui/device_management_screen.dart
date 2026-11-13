// Task 1.14 — device management screen（草案，待人類設計定稿）
// 批次 III-c（人類決定「可強化內建頁」）：本裝置標示／重新命名／
// 遠端登出確認＋失敗訊息。遠端登出的 UIA（伺服端要求密碼重驗證）
// 由呼叫端（settings_screen）以官方 `Client.uiaRequestBackground` 處理；
// 本檔不寫加密／協定邏輯。
import 'dart:async';

import 'package:flutter/material.dart';

typedef DevicesLoader = Future<List<DeviceView>> Function();
typedef DeviceDeleteAction = Future<void> Function(DeviceView device);
typedef DeviceRenameAction = Future<void> Function(DeviceView device, String newName);

class DeviceView {
  const DeviceView({
    required this.id,
    required this.displayName,
    required this.lastSeen,
    this.isCurrent = false,
  });
  final String id;
  final String displayName;
  final String lastSeen;

  /// 批次 III-c：SDK `client.deviceID`；本裝置加粗＋「本裝置」徽章。
  final bool isCurrent;
}

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({
    super.key,
    this.loadDevices,
    this.onDeleteDevice,
    this.onRenameDevice,
  });
  final DevicesLoader? loadDevices;
  final DeviceDeleteAction? onDeleteDevice;

  /// 批次 III-c：重新命名裝置（官方 `POST /devices/{id}` PUT updateDevice）。
  final DeviceRenameAction? onRenameDevice;

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<DeviceView> _devices = const [];
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final list = await (widget.loadDevices ?? _defaultLoad).call();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _devices = list;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '無法載入裝置';
      });
    }
  }

  Future<List<DeviceView>> _defaultLoad() async => const [];

  /// 批次 III-c：遠端登出（先確認、成功後刷新、失敗顯示原因）。
  Future<void> _delete(DeviceView dev) async {
    if (widget.onDeleteDevice == null) {
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('登出「${dev.displayName}」？'), // 文案草案
        content: const Text(
          '該裝置將被登出並無法再收到此帳號訊息。『本裝置』請勿在此登出。', // 文案草案
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登出裝置'), // 文案草案
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    try {
      await widget.onDeleteDevice!(dev);
      if (!mounted) return;
      setState(() {
        _devices = _devices.where((d) => d.id != dev.id).toList();
        _message = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 批次 III-c：顯示具體失敗原因（含 UIA 取消／密碼錯誤）。
        _message = '登出失敗：$e'; // 文案草案
      });
    }
  }

  /// 批次 III-c：重新命名裝置（官方 updateDevice；input 預填現名）。
  Future<void> _rename(DeviceView dev) async {
    if (widget.onRenameDevice == null) {
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController(text: dev.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新命名裝置'), // 文案草案
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '裝置名稱'), // 文案草案
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('儲存'), // 文案草案
          ),
        ],
      ),
    );
    if (newName == null || newName == dev.displayName || !mounted) {
      return;
    }
    try {
      await widget.onRenameDevice!(dev, newName);
      if (!mounted) return;
      setState(() {
        _devices = [
          for (final d in _devices)
            if (d.id == dev.id)
              DeviceView(
                id: d.id,
                displayName: newName,
                lastSeen: d.lastSeen,
                isCurrent: d.isCurrent,
              )
            else
              d,
        ];
        _message = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = '重新命名失敗：$e'; // 文案草案
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('裝置管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('沒有已登入的裝置'), // 文案草案
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final dev = _devices[index];
                      return ListTile(
                        leading: Icon(
                          dev.isCurrent
                              ? Icons.smartphone
                              : Icons.devices_other,
                        ),
                        title: Text(
                          dev.displayName,
                          style: dev.isCurrent
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                        subtitle: Text(
                          dev.isCurrent ? '本裝置・${dev.id}' : dev.id, // 文案草案
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onRenameDevice != null)
                              IconButton(
                                tooltip: '重新命名裝置', // 文案草案
                                onPressed: () => unawaited(_rename(dev)),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            if (widget.onDeleteDevice != null)
                              TextButton(
                                onPressed: () => unawaited(_delete(dev)),
                                child: const Text('遠端登出'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
