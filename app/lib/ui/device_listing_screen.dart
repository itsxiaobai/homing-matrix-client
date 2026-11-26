// Task 1.5 skeleton — device listing (UI only, hooked to SDK official Device metadata)
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart'; // Device, official SDK model
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

class DeviceListingScreen extends StatefulWidget {
  const DeviceListingScreen({
    super.key,
    this.loadDevices,
    this.onLogoutDevice,
    this.deviceSource, // injected official: () => client.getDevices()
  });
  final Future<List<DeviceView>> Function()? loadDevices;
  final Future<void> Function(DeviceView)? onLogoutDevice;
  final Future<List<Device>> Function()? deviceSource;

  @override
  State<DeviceListingScreen> createState() => _DeviceListingScreenState();
}

class DeviceView {
  const DeviceView({required this.deviceId, required this.displayName, required this.lastSeenTs});
  final String deviceId;
  final String displayName;
  final int? lastSeenTs;
}

class _DeviceListingScreenState extends State<DeviceListingScreen> {
  List<DeviceView> _list = const [];
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
      List<DeviceView> list;
      if (widget.loadDevices != null) {
        list = await widget.loadDevices!();
      } else if (widget.deviceSource != null) {
        final sdk = await widget.deviceSource!();
        list = sdk
            .map(
              (d) => DeviceView(
                deviceId: d.deviceId,
                displayName: (d.displayName ?? d.deviceId),
                lastSeenTs: d.lastSeenTs,
              ),
            )
            .toList();
      } else {
        list = const [];
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _list = list;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '無法載入裝置';
      });
    }
  }

  Future<void> _delete(DeviceView dev) async {
    if (widget.onLogoutDevice != null) {
      try {
        await widget.onLogoutDevice!(dev);
        setState(() => _list = _list.where((d) => d.deviceId != dev.deviceId).toList());
      } catch (_) {
        setState(() => _message = '登出失敗');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('裝置管理'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_message != null) Text(_message!),
                Expanded(
                  child: ListView.builder(
                    itemCount: _list.length,
                    itemBuilder: (context, index) {
                      final dev = _list[index];
                      return ListTile(
                        title: Text(dev.displayName),
                        subtitle: Text(dev.deviceId),
                        trailing: TextButton(
                          onPressed: () => _delete(dev),
                          child: Text(S.t('遠端登出')),
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
