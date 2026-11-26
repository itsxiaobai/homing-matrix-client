// 批次十二③（人類指示「all」＋new_ref/room info 結構參考）：
// 聊天室資訊頁骨架。全部使用 SDK 官方 API：
//   靜音＝`Room.pushRuleState`／`setPushRuleState`（room.dart L2488/L2534，
//     rooms_screen L1110 同一用法：state != notify 即視為已靜音）
//   成員＝既有 GroupMemberManageScreen（官方 getParticipants／invite／kick）
//   邀請＝`Room.invite(id)`（room.dart L1574）
//   離開＝官方 `Room.leave()`＋`Room.forget()`（rooms_screen _deleteRoom 同路徑）
//   2026-11-21：公告改為自動抓所有房間的 pinnedEventIds（標準 m.pinned_events）。
//     的觸發來源，Phase 4 草案——待人類定稿；不影響伺服器狀態）。
// 封鎖／檢舉／非好友過濾＝既有畫面（block_user_screen／report_user_screen／
// message_filter），本頁不重複（上輪分析更正）。骨架草案，待人類設計定稿。
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'group_chat_manage_screen.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化

class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({super.key, required this.room});

  final Room room;

  @override
  State<RoomInfoScreen> createState() => _RoomInfoScreenState();
}

class _RoomInfoScreenState extends State<RoomInfoScreen> {
  bool _muted = false;
  int _memberCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? name;
    try {
      name = widget.room.getLocalizedDisplayname();
      if (name == 'Empty chat') {
        name = null;
      }
    } catch (_) {}
    // 2026-11-21：公告改為自動抓所有房間的 pinnedEventIds，不再有本機旗標。
    var muted = false;
    try {
      muted = widget.room.pushRuleState != PushRuleState.notify;
    } catch (_) {}
    var members = 0;
    try {
      members = widget.room.getParticipants().length;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _muted = muted;
      _memberCount = members;
    });
  }

  /// 第二十四批：state 變更權限（官方 `Room.canChangeStateEvent`；例外＝
  /// 無 state → 不顯示管理項，保守）。
  bool _canChange(String type) {
    try {
      return widget.room.canChangeStateEvent(type);
    } on Object {
      return false;
    }
  }

  /// 第二十四批：更改房名（官方 `Room.setName`；SDK 組 m.room.name state）。
  Future<void> _editName() async {
    final controller = TextEditingController();
    String current = '';
    try {
      current = widget.room.getLocalizedDisplayname();
      if (current == 'Empty chat') {
        current = '';
      }
    } catch (_) {}
    controller.text = current == widget.room.id ? '' : current;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('更改名稱')), // 文案草案
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '聊天室名稱'), // 文案草案
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.t('儲存')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await widget.room.setName(name);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('名稱已更新'))), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('更改失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 第二十四批：編輯說明／topic（官方 `Room.setDescription` — SDK 對
  /// m.room.topic state 的 setter 名稱；無 `setTopic`）。
  Future<void> _editTopic() async {
    final controller = TextEditingController();
    var current = '';
    try {
      current = widget.room.topic;
    } catch (_) {}
    controller.text = current;
    final topic = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('聊天室說明')), // 文案草案
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: S.t('輸入聊天室說明（目前不顯示給好友列表）'), // 文案草案
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.t('儲存')),
          ),
        ],
      ),
    );
    if (topic == null) return;
    try {
      await widget.room.setDescription(topic);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(topic.isEmpty ? '已清除說明' : '說明已更新')), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('更新失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 第二十四批：更換／移除房間頭像（官方 `Room.setAvatar(MatrixFile?)`：
  /// SDK 內建 uploadContent→組 m.room.avatar state；null＝移除）。官方
  ///_matrix含義：Media 下載由 SDK 處理。圖片來源＝相簿 ImagePicker。
  Future<void> _editRoomAvatar() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('聊天室頭像')), // 文案草案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(AllIcons.photoOutlined),
              title: Text(S.t('從相簿選擇')), // 文案草案
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            ListTile(
              leading: Icon(AllIcons.deleteOutline),
              title: Text(S.t('移除頭像')), // 文案草案
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'remove') {
        await widget.room.setAvatar(null);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.t('頭像已移除'))), // 文案草案
          );
        }
        return;
      }
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      await widget.room.setAvatar(
        MatrixFile(bytes: bytes, name: picked.name),
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('頭像已更新'))), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('操作失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 靜音＝官方 push rule（rooms_screen 同款判斷）。
  Future<void> _setMuted(bool value) async {
    try {
      await widget.room.setPushRuleState(
        value ? PushRuleState.dontNotify : PushRuleState.notify,
      );
      if (mounted) setState(() => _muted = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('設定失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 邀請＝官方 `Room.invite`。v0：與既有成員管理共用成功／失敗訊息樣式。
  Future<void> _invite() async {
    final controller = TextEditingController();
    final mxid = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('邀請成員')), // 文案草案
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Matrix ID（例如 @user:server）', // 文案草案
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.t('邀請')),
          ),
        ],
      ),
    );
    if (mxid == null || mxid.isEmpty) return;
    try {
      await widget.room.invite(mxid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('已邀請 ')}$mxid')), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('邀請失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 離開＋刪除對話＝官方 leave＋forget（rooms_screen._deleteRoom 同確認文案）。
  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('退出聊天室？')), // 文案草案
        content: const Text(
          '這會退出聊天室並讓本裝置不再顯示該對話（伺服器端）。\n此操作無法在本裝置復原。',
        ), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('退出')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.room.leave();
      try {
        await widget.room.forget();
      } catch (_) {
        // forget 失敗（例如需先完成 leave 同步）→ 以房間清單過濾為準。
      }
      // 已退出 → 資訊頁／聊天室都不再有內容，回導覽根（骨架行為）。
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('退出失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.room.id;
    try {
      final name = widget.room.getLocalizedDisplayname();
      if (name.isNotEmpty && name != 'Empty chat') {
        title = name;
      }
    } catch (_) {}
    String? topic;
    try {
      topic = (widget.room.topic.isNotEmpty && widget.room.topic != '')
          ? widget.room.topic
          : null;
    } catch (_) {}
    return Scaffold(
      appBar: AppBar(title: Text(title)), // 文案／視覺待 UI 定稿
      body: ListView(
        children: [
          // 標頭：名稱＋ID＋成員數＋topic（骨架，零樣式）。
          ListTile(
            leading: Icon(AllIcons.chatBubbleOutline),
            title: Text(title),
            subtitle: Text(
              [
                widget.room.id,
                if (_memberCount > 0) '成員 $_memberCount', // 文案草案
              ].join('\n'),
            ),
          ),
          if (topic != null)
            ListTile(
              leading: Icon(AllIcons.notes),
              title: Text(S.t('說明')), // 文案草案
              subtitle: Text(topic),
            ),
          // 第二十四批（Matrix 應有功能）：群組管理三項——房名／說明／頭像，
          // 通通走 SDK 官方 API；**僅群組**（一對一無房名/頭像語意）且有
          // state 變更權限（官方 `Room.canChangeStateEvent`）才顯示。
          if (!widget.room.isDirectChat && _canChange(EventTypes.RoomName))
            ListTile(
              leading: Icon(AllIcons.badgeOutlined),
              title: Text(S.t('更改名稱')), // 文案草案
              onTap: _editName,
            ),
          if (!widget.room.isDirectChat && _canChange(EventTypes.RoomTopic))
            ListTile(
              leading: Icon(AllIcons.notesOutlined),
              title: Text(topic == null ? '新增說明' : '編輯說明'), // 文案草案
              onTap: _editTopic,
            ),
          if (!widget.room.isDirectChat && _canChange(EventTypes.RoomAvatar))
            ListTile(
              leading: Icon(AllIcons.imageOutlined),
              title: Text(S.t('更換頭像')), // 文案草案
              onTap: _editRoomAvatar,
            ),
          const Divider(),
          SwitchListTile(
            title: Text(S.t('靜音')), // 2.5
            subtitle: Text(S.t('官方通知規則（伺服器端）')), // 文案草案
            value: _muted,
            onChanged: (v) => _setMuted(v),
          ),
          const Divider(),
          ListTile(
            leading: Icon(AllIcons.groupOutlined),
            title: Text(S.t('成員管理')), // 2.2（既有骨架畫面）
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GroupMemberManageScreen(
                    loadMembers: () async {
                      final participants = widget.room.getParticipants();
                      return [
                        for (final p in participants) p.id,
                      ];
                    },
                    inviteMember: (mxid) => widget.room.invite(mxid),
                    kickMember: (mxid) => widget.room.kick(mxid),
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(AllIcons.personAddOutlined),
            title: Text(S.t('邀請成員')), // 文案草案
            onTap: _invite,
          ),
          const Divider(),
          ListTile(
            leading: Icon(AllIcons.logout),
            title: Text(S.t('退出聊天室')), // 文案草案
            onTap: _leave,
          ),
        ],
      ),
    );
  }
}
