// 第三十五批 #6：緊急聯絡人管理（本機 kv `emergency_contacts`；草案，
// 待人類設計定稿）。資料＝Matrix user ID 清單（**本機**儲存不送伺服器）；
// 選項來源＝既有 1:1 好友聊天室（directChats）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key, required this.client});

  final Client client;

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  List<Room> _friends = const [];
  Set<String> _saved = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await AppSettings.emergencyContacts();
      final friends = widget.client.rooms
          .where((r) => r.isDirectChat)
          .toList()
        ..sort((a, b) => _titleOf(a).compareTo(_titleOf(b)));
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = friends;
        _saved = contacts.toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _titleOf(Room room) {
    try {
      final display = room.getLocalizedDisplayname();
      if (display.isEmpty || display == 'Empty chat') {
        final name = room.name;
        return name.isNotEmpty ? name : room.id;
      }
      return display;
    } catch (_) {
      final name = room.name;
      return name.isNotEmpty ? name : room.id;
    }
  }

  Future<void> _toggle(Room room, bool on) async {
    setState(() {
      if (on) {
        _saved.add(room.id);
      } else {
        _saved.remove(room.id);
      }
    });
    // 即時保存（草案；失敗如實提示——聯絡人漏存＝緊急時找不到人）。
    try {
      final userIds = <String>[
        for (final r in _friends)
          if (_saved.contains(r.id))
            r.directChatMatrixID ?? r.id,
      ];
      await AppSettings.setEmergencyContacts(userIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：$e')), // 文案草案
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('緊急聯絡人')), // 文案草案
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('載入失敗：$_error')) // 文案草案
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        // 文案草案
                        '緊急求助時優先通知這些人（僅存於此裝置）。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: _friends.isEmpty
                          ? const Center(
                              child: Text('還沒有好友聊天室'), // 文案草案
                            )
                          : ListView.builder(
                              itemCount: _friends.length,
                              itemBuilder: (context, i) {
                                final room = _friends[i];
                                final checked = _saved.contains(room.id);
                                return CheckboxListTile(
                                  value: checked,
                                  title: Text(_titleOf(room)),
                                  subtitle: Text(room.id),
                                  onChanged: (v) =>
                                      _toggle(room, v ?? false),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
