// 第三十五批 #6（人類 2026-11-12 拍板）— 緊急求助流程（LINE 式；草案
// 待人類設計定稿）。
//
// 觸發：PWS 示警輪詢（main_shell，15 分鐘前景）偵測到「地震／颱風」類
// 新示警（`isEmergencyFlowAlert`）→ 開本畫面（同一 alert id session 內只彈一次）。
//
// 流程（人類指定）：
//   步驟一「需要幫忙嗎？」是／否（否＝關閉；同 id 不再彈）。
//   步驟二「幫你聯絡誰？」緊急聯絡人／所有人／119。
//   步驟三訊息**預覽（可編輯）**（人類「使用者會先知道訊息長什麼樣子」）
//         → 重用 ShareToRoomScreen（預選對象；「發到哪裡讓使用者決定」）。
//
// 119＝**自動發訊息，不撥號**（人類拍板）：訊息模板請收訊者協助通報 119。
// 緊急訊息 ≠ 聊天室公告（announcement_rooms 橫幅＝被動資訊，批次十二⑤）；
// 本流程是**主動求助**（兩者資料來源與用途不同）。
//
// **披露**：①僅 App 前景輪詢（無 FCM 限制延續，App 未開啟時不觸發）；
// ②「所有人」＝所有 1:1 好友聊天室預選（群組不預選）；
// ③「緊急聯絡人」未設定時＝不預選，picker 全列讓使用者自選。
// ④送出＝既有官方 `Room.sendTextEvent`（加密房 SDK 自動加密）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import '../emergency_feed.dart';
import '../share_receiver.dart' show SharePayload;
import 'share_to_room_screen.dart';

/// 步驟二的三個對象（人類指定：「緊急聯絡人／所有人／119」）。
enum EmergencyFlowTarget { contacts, everyone, e119 }

/// 訊息模板（純函式，供測試；文案草案待人類定稿）。
String emergencyFlowMessage(EmergencyAlert alert, EmergencyFlowTarget target) {
  final head = '【緊急求助】';
  final body = StringBuffer('示警：${alert.category}\n');
  if (alert.summary.isNotEmpty) {
    body.writeln(alert.summary);
  }
  final tail = '—— 來自 Homing 緊急求助';
  switch (target) {
    case EmergencyFlowTarget.contacts:
    case EmergencyFlowTarget.everyone:
      return '$head我可能需要幫忙，請聯絡我。\n$body$tail';
    case EmergencyFlowTarget.e119:
      return '$head請協助撥打 119（消防／救護），我可能需要緊急救援。\n$body$tail';
  }
}

class EmergencyFlowScreen extends StatefulWidget {
  const EmergencyFlowScreen({
    super.key,
    required this.client,
    required this.alert,
  });

  final Client client;
  final EmergencyAlert alert;

  @override
  State<EmergencyFlowScreen> createState() => _EmergencyFlowScreenState();
}

enum _Step { ask, target, confirm }

class _EmergencyFlowScreenState extends State<EmergencyFlowScreen> {
  _Step _step = _Step.ask;
  EmergencyFlowTarget? _target;
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _pickTarget(EmergencyFlowTarget target) {
    setState(() {
      _target = target;
      _messageController.text =
          emergencyFlowMessage(widget.alert, target);
      _step = _Step.confirm;
    });
  }

  /// 預選房間（草案規則見檔頭披露②③）；送出與否仍由使用者在 picker 決定。
  Future<Set<String>> _preselectedIds() async {
    final directChats = widget.client.rooms
        .where((r) => r.isDirectChat)
        .toList();
    switch (_target!) {
      case EmergencyFlowTarget.contacts:
        final ids = await AppSettings.emergencyContacts();
        return {
          for (final r in directChats)
            if (ids.contains(r.directChatMatrixID)) r.id,
        };
      case EmergencyFlowTarget.everyone:
        return {for (final r in directChats) r.id};
      case EmergencyFlowTarget.e119:
        return const {};
    }
  }

  Future<void> _openDestinationPicker() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('訊息內容不可空白')), // 文案草案
      );
      return;
    }
    final ids = await _preselectedIds();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShareToRoomScreen(
          client: widget.client,
          payload: SharePayload.textOnly(text),
          preselectedRoomIds: ids,
          title: '選擇要通知的對象', // 文案草案
        ),
      ),
    );
    // picker 自行 pop 並回報結果 → 流程結束關閉（草案；待人類定稿）。
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('緊急求助'), // 文案草案
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (_step) {
            _Step.ask => _askStep(),
            _Step.target => _targetStep(),
            _Step.confirm => _confirmStep(),
          },
        ),
      ),
    );
  }

  Widget _alertCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.alert.category,
              style: theme.textTheme.titleMedium,
            ),
            if (widget.alert.sender.isNotEmpty)
              Text(
                widget.alert.sender,
                style: theme.textTheme.bodySmall,
              ),
            if (widget.alert.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.alert.summary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _askStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          '需要幫忙嗎？', // 人類指定文案
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _alertCard(),
        const Spacer(),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.target),
          child: const Text('是'), // 人類指定文案
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('否'), // 人類指定文案
        ),
      ],
    );
  }

  Widget _targetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          '幫你聯絡誰？', // 人類指定文案
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        _alertCard(),
        const Spacer(),
        ListTile(
          leading: const Icon(Icons.favorite_outline),
          title: const Text('緊急聯絡人'), // 人類指定文案
          subtitle: const Text('預選你在「設定→緊急聯絡人」指定的人'), // 文案草案
          onTap: () => _pickTarget(EmergencyFlowTarget.contacts),
        ),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('所有人'), // 人類指定文案
          subtitle: const Text('預選所有好友（1:1）聊天室'), // 文案草案
          onTap: () => _pickTarget(EmergencyFlowTarget.everyone),
        ),
        ListTile(
          leading: const Icon(Icons.emergency_outlined),
          title: const Text('119'), // 人類指定文案
          subtitle: const Text('發訊息請對方協助通報 119（不自動撥號）'), // 文案草案
          onTap: () => _pickTarget(EmergencyFlowTarget.e119),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'), // 文案草案
        ),
      ],
    );
  }

  Widget _confirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          '訊息預覽（可編輯）', // 文案草案（人類「先知道訊息長什麼樣子」）
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _messageController,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          // 文案草案
          '送出前可再選擇／調整要通知的對象。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => unawaited(_openDestinationPicker()),
          child: const Text('選擇要通知的對象'), // 文案草案
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = _Step.target),
          child: const Text('上一步'), // 文案草案
        ),
      ],
    );
  }
}
