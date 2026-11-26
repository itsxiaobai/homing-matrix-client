// 隱藏的聊天室清單（第四十二批：人類「外加隱藏／封鎖名單應顯示並可還原」）。
//
// 版位參考 LINE「設定 → 好友／封鎖」與 Homing 首頁的隱藏收合區；集中到設定頁
// 讓使用者找得到並**一鍵還原**（解除隱藏＝本機標記移除，伺服器資料不動）。
//
// 資料來源：本機 `app_settings.db` 的 `hidden_rooms` 表（純本機過濾）＋
// 官方房間名稱（`Room.getLocalizedDisplayname()`）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）

/// 隱藏的聊天室（可還原）。
class HiddenRoomsScreen extends StatefulWidget {
  const HiddenRoomsScreen({super.key, required this.client});

  final Client client;

  @override
  State<HiddenRoomsScreen> createState() => _HiddenRoomsScreenState();
}

class _HiddenRoomsScreenState extends State<HiddenRoomsScreen> {
  List<({String id, String name, String time})> _rooms = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Set<String> hidden;
    try {
      hidden = await AppSettings.hiddenRooms();
    } catch (_) {
      hidden = const <String>{};
    }
    final list = <({String id, String name, String time})>[];
    for (final id in hidden) {
      final room = widget.client.getRoomById(id);
      var name = id;
      try {
        final n = room?.getLocalizedDisplayname();
        if (n != null && n.isNotEmpty && n != 'Empty chat') {
          name = n;
        }
      } catch (_) {}
      list.add((id: id, name: name, time: ''));
    }
    if (!mounted) return;
    setState(() {
      _rooms = list;
      _loading = false;
    });
  }

  /// 還原顯示（解除本機隱藏標記；不影響伺服器資料）。
  Future<void> _restore(String id, String name) async {
    try {
      await AppSettings.unhideRoom(id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('已還原顯示「')}$name」')), // 草案文案
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('還原失敗：')}$e')), // 草案文案
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('隱藏的聊天室'))), // 草案文案
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? Center(
                  child: Text(S.t('沒有隱藏的聊天室')), // 草案文案
                )
              : ListView.separated(
                  itemCount: _rooms.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = _rooms[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          r.name.isEmpty ? '?' : r.name.characters.first,
                        ),
                      ),
                      title: Text(r.name),
                      subtitle: Text(r.id),
                      trailing: TextButton(
                        onPressed: () => _restore(r.id, r.name),
                        child: Text(S.t('還原顯示')), // 草案文案
                      ),
                    );
                  },
                ),
    );
  }
}
