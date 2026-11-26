// 第三十五批 #6：緊急聯絡人管理（本機 kv `emergency_contacts`；草案，
// 待人類設計定稿）。資料＝Matrix user ID 清單（**本機**儲存不送伺服器）；
// 選項來源＝既有 1:1 好友聊天室（directChats）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import '../emergency_feed.dart'
    show
        buildTestEmergencyAlert,
        emergencyRefreshNotifier,
        encodeTestEmergencyAlert,
        parseTestEmergencyAlert,
        kEmergencyTestAlertKey; // 第六十四批④＋第一百零六批：示警測試選項
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import 'emergency_flow_screen.dart'; // 第六十四批④：開啟測試即彈求助流程

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

  /// 第六十四批④：示警測試開關目前狀態（kv；開啟中＝有未過期的合成示警）。
  bool _testOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await AppSettings.emergencyContacts();
      // 第六十四批④：讀測試示警現況（過期／格式錯誤＝關閉）。
      final testRaw = await AppSettings.get(kEmergencyTestAlertKey);
      final testOn = parseTestEmergencyAlert(testRaw) != null;
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
        _testOn = testOn;
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
          SnackBar(content: Text('${S.t('儲存失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 第六十四批④：示警測試開關（本機 kv；開啟＝寫入合成示警並**立即**彈出
  /// 求助流程畫面（同一 `EmergencyFlowScreen` 管線）；關閉＝移除 kv。
  /// 失敗如實提示（本機 kv 寫失敗＝測試功能不可用）。
  Future<void> _toggleTestAlert(bool on) async {
    setState(() => _testOn = on);
    try {
      if (on) {
        // id 帶時間戳：每次開啟都是新 id → 首頁指紋變化即刷新、求助流程
        // 「同一 id session 內只彈一次」的語意也不會卡住重複測試。
        final alert = buildTestEmergencyAlert(
          id: 'homing-test-${DateTime.now().millisecondsSinceEpoch}',
        );
        await AppSettings.set(
          kEmergencyTestAlertKey,
          encodeTestEmergencyAlert(alert),
        );
        // 第一百零六批：通知首頁立即刷新（不必等下一次 sync／15 分鐘輪詢）。
        emergencyRefreshNotifier.value++;
        if (mounted) {
          // 立即彈（與 main_shell 輪詢後的行為同一畫面；草案）。
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  EmergencyFlowScreen(client: widget.client, alert: alert),
            ),
          );
        }
      } else {
        await AppSettings.remove(kEmergencyTestAlertKey);
        emergencyRefreshNotifier.value++;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('操作失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('緊急聯絡人'))), // 文案草案
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('${S.t('載入失敗：')}$_error')) // 文案草案
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 第六十四批④（人類要求「提供緊急訊息測試選項」）：
                    // 示警測試開關（**草案，待人類設計定稿**）。開啟＝本機
                    // kv 寫入一則合成示警（明示測試、1 小時自動失效）→
                    // 首頁顯示測試紅卡片（rooms_screen 於下次刷新讀取）＋
                    // 立即彈出求助流程畫面（同一管線）。關閉＝移除。
                    SwitchListTile(
                      value: _testOn,
                      title: Text(S.t('示警測試（測試用，非真實）')), // 文案草案
                      subtitle: Text(
                        // 第六十六批：說明文字對齊新流程（彈窗→傳送現況
                        // 流程；重開 App 自動關閉＝第六十四批⑤）。
                        S.t('開啟＝首頁顯示測試示警卡片並開啟傳送現況流程（1 小時內有效；重開 App 自動關閉）'), // 文案草案
                      ),
                      onChanged: (v) => unawaited(_toggleTestAlert(v)),
                    ),
                    const Divider(height: 1),
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
                          ? Center(
                              child: Text(S.t('還沒有好友聊天室')), // 文案草案
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
