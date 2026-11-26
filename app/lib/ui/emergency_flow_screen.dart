// 第三十五批 #6（人類 2026-11-12 拍板）— 緊急求助流程（草案待人類設計定稿）。
//
// **第六十六批（人類指示 2026-11-17）再重設計**（前一版＝第六十四批⑤）：
// * **現況通報不再送訊息**——「你受影響了嗎？」選擇只寫**本機記錄**並顯示在
//   緊急卡片（現況：沒事／受影響）；同時首頁會**解析好友傳來的現況訊息**
//   顯示各好友狀態（rooms_screen；沒受影響的人不需要再傳訊息）。
// * **求助**（點「受影響」後）：**直接開始編輯訊息** →
//   *有緊急聯絡人*＝詢問「傳送給緊急聯絡人（名字…）？」，選送出才傳出去；
//   *沒有緊急聯絡人*＝編輯完開**挑選器**（ShareToRoomScreen；一對一／群組／
//   公開聊天室分節，第六十六批）自己選傳給誰。
// * 「所有人（全部好友）」獨立選項移除（人類拍板）；119 於第六十四批⑤移除。
// * 送出後記錄（`emergency_feed.dart`，本機 kv）→ 卡片顯示**已通報名單**。
//
// 緊急訊息 ≠ 聊天室公告（announcement_rooms 橫幅＝被動資訊，批次十二⑤）；
// 本流程是**主動求助**（兩者資料來源與用途不同）。
//
// **披露**：①收件對象由使用者選（緊急聯絡人預選／挑選器自選；可含群組）；
// ②送出＝既有官方 `Room.sendTextEvent`（加密房 SDK 自動加密）＋
// `sendWithRateLimitRetry`（429 退避，同分享管線）；部分失敗不中斷其餘，
// 失敗者**不**計入已通報名單；③現況記錄僅存本機。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import '../emergency_feed.dart';
import '../share_receiver.dart' show SharePayload;
import 'chat_screen.dart' show sendWithRateLimitRetry;
import 'share_to_room_screen.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import 'line_style.dart'; // 68e/68f：共用標題語彙

/// 求助訊息模板（純函式，供測試；文案草案待人類定稿）。
String emergencyFlowMessage(EmergencyAlert alert) {
  final head = '【緊急求助】';
  final body = StringBuffer('示警：${alert.category}\n');
  if (alert.summary.isNotEmpty) {
    body.writeln(alert.summary);
  }
  const tail = '—— 來自 Homing 緊急求助';
  return '$head我可能需要幫忙，請聯絡我。\n$body$tail';
}

/// 現況訊息模板（第六十四批⑤；純函式，供測試；文案草案）。
/// 受影響／沒事（報平安）兩種。**第六十六批**：現況不再由 App 送出，但
/// 模板保留——好友仍可能手動送此格式，首頁解析用（rooms_screen）。
String emergencyStatusMessage(EmergencyAlert alert, {required bool affected}) {
  final body = StringBuffer('示警：${alert.category}\n');
  if (alert.summary.isNotEmpty) {
    body.writeln(alert.summary);
  }
  const tail = '—— 來自 Homing 傳送現況';
  if (affected) {
    return '【緊急現況】我可能受此示警影響，正在確認狀況。\n$body$tail';
  }
  return '【報平安】我沒事，不受此示警影響。\n$body$tail';
}

class EmergencyFlowScreen extends StatefulWidget {
  const EmergencyFlowScreen({
    super.key,
    required this.client,
    required this.alert,
    /// 送出注入縫（僅測試用；正式＝官方 `Room.sendTextEvent`＋429 退避）。
    this.sendText,
  });

  final Client client;
  final EmergencyAlert alert;
  final Future<void> Function(Room room, String text)? sendText;

  @override
  State<EmergencyFlowScreen> createState() => _EmergencyFlowScreenState();
}

class _EmergencyFlowScreenState extends State<EmergencyFlowScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;

  /// 現況選擇結果（null＝尚未選＝顯示現況選擇；true＝受影響＝編輯訊息）。
  bool _affected = false;

  /// 緊急聯絡人（initState 預取；讀取失敗＝未設定）。
  List<String> _contactIds = const [];

  @override
  void initState() {
    super.initState();
    _messageController.text = emergencyFlowMessage(widget.alert);
    unawaited(_loadContacts());
  }

  Future<void> _loadContacts() async {
    List<String> ids;
    try {
      ids = await AppSettings.emergencyContacts();
    } on Object {
      ids = const []; // 無 DB（測試環境）→ 視同未設定。
    }
    if (mounted) {
      setState(() => _contactIds = ids);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// 現況選擇：**只寫本機記錄＋更新卡片顯示，不送任何訊息**（第六十六批
  /// 人類指示）。沒事 → 記錄後關閉；受影響 → 記錄後進入編輯（求助）。
  Future<void> _pickAffected(bool affected) async {
    try {
      final existing = await loadEmergencyStatuses();
      final prev = existing[widget.alert.id];
      await recordEmergencyStatus(
        EmergencyStatusRecord(
          alertId: widget.alert.id,
          affected: affected,
          // 已通報名單沿用既有記錄（求助送出過的不清掉）。
          notified: prev?.notified ?? const [],
          updatedAt: DateTime.now(),
        ),
      );
    } on Object {
      // 記錄失敗（無 DB）不擋流程。
    }
    if (affected) {
      if (mounted) {
        setState(() => _affected = true); // 受影響 → 編輯訊息（求助）。
      }
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  /// 房間顯示名（best-effort；失敗用 id）。
  String _roomName(Room room) {
    try {
      final n = room.getLocalizedDisplayname();
      if (n.isNotEmpty && n != 'Empty chat') {
        return n;
      }
    } catch (_) {}
    return room.id;
  }

  /// 送出訊息到指定房間 id（逐房；部分失敗不中斷；成功者寫入已通報記錄）。
  Future<void> _sendTo(Set<String> roomIds, String text) async {
    final targets = widget.client.rooms
        .where((r) => roomIds.contains(r.id))
        .toList();
    final delivered = <({String roomId, String name})>[];
    for (final room in targets) {
      final name = _roomName(room);
      try {
        final send = widget.sendText;
        if (send != null) {
          await send(room, text);
        } else {
          await sendWithRateLimitRetry(() => room.sendTextEvent(text));
        }
        delivered.add((roomId: room.id, name: name));
      } catch (_) {
        // 失敗不計入已通報（不假成功）。
      }
      if (mounted) {
        setState(() {});
      }
    }
    if (delivered.isNotEmpty) {
      try {
        final existing = await loadEmergencyStatuses();
        final prev = existing[widget.alert.id];
        await recordEmergencyStatus(
          EmergencyStatusRecord(
            alertId: widget.alert.id,
            // 求助送出＝沿用既有狀態（現況選擇已記錄；無記錄視同受影響）。
            affected: prev?.affected ?? true,
            notified: [...?prev?.notified, ...delivered],
            updatedAt: DateTime.now(),
          ),
        );
      } on Object {
        // 記錄失敗不影響送出結果（卡片顯示會缺，但不擋流程）。
      }
    }
    if (!mounted) {
      return;
    }
    final failedCount = targets.length - delivered.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failedCount == 0
              ? '已送出給 ${delivered.length} 個對象'
              : '已送出 ${delivered.length} 個；失敗 $failedCount 個',
        ),
      ),
    );
  }

  /// 有緊急聯絡人：詢問「傳送給緊急聯絡人（名字…）」——**選送出才傳出去**
  /// （人類指示）。設定了但都沒有對應聊天室 → 退回挑選器（同沒設定的路徑）。
  Future<void> _sendToContacts() async {
    if (_sending) {
      return;
    }
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('訊息內容不可空白'))), // 文案草案
      );
      return;
    }
    final rooms = widget.client.rooms
        .where((r) => _contactIds.contains(r.directChatMatrixID))
        .toList();
    if (rooms.isEmpty) {
      await _openPicker();
      return;
    }
    setState(() => _sending = true);
    await _sendTo({for (final r in rooms) r.id}, text);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    Navigator.of(context).pop();
  }

  /// 沒有緊急聯絡人（或「選擇其他對象」）：開**挑選器**（第六十六批：
  /// 一對一／群組／公開聊天室分節）。挑選器自行送出；成功名單經 `onDelivered`
  /// 記錄（預選＝緊急聯絡人對應的 1:1 房，有設定的話）。返回即結束流程。
  Future<void> _openPicker() async {
    final preselected = widget.client.rooms
        .where((r) => _contactIds.contains(r.directChatMatrixID))
        .map((r) => r.id)
        .toSet();
    await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => ShareToRoomScreen(
          client: widget.client,
          payload: SharePayload(text: _messageController.text.trim()),
          preselectedRoomIds: preselected,
          title: S.t('選擇傳給誰'), // 文案草案
          onDelivered: (ids, names) async {
            // 挑選器送出成功 → 記入已通報（第六十六批：卡片顯示名單）。
            try {
              final existing = await loadEmergencyStatuses();
              final prev = existing[widget.alert.id];
              await recordEmergencyStatus(
                EmergencyStatusRecord(
                  alertId: widget.alert.id,
                  affected: prev?.affected ?? true,
                  notified: [
                    ...?prev?.notified,
                    for (var i = 0; i < ids.length; i++)
                      (roomId: ids[i], name: names[i]),
                  ],
                  updatedAt: DateTime.now(),
                ),
              );
            } on Object {
              // 記錄失敗不擋流程。
            }
          },
        ),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: lineTitlePill(context, S.t('傳送現況')), // 文案草案（第六十四批⑤改名）
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          // 鍵盤展開可捲動（第六十四批⑤溢出修正）。
          child: SingleChildScrollView(
            child: _affected ? _editStep() : _statusStep(),
          ),
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

  /// 步驟一：現況選擇（人類指示「先選擇有沒有受影響」）。
  /// **第六十六批：只記錄顯示，不送任何訊息。**
  Widget _statusStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          S.t('你受影響了嗎？'), // 文案草案
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _alertCard(),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => unawaited(_pickAffected(false)),
          child: Text(S.t('沒事')), // 文案草案（報平安；只記錄不送訊息）
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => unawaited(_pickAffected(true)),
          child: Text(S.t('受影響')), // 文案草案
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.t('取消')), // 文案草案
        ),
      ],
    );
  }

  /// 步驟二（點「受影響」後）：**編輯緊急訊息** → 傳送對象
  /// （有緊急聯絡人＝詢問「傳送給緊急聯絡人（名字…）？」，選送出才傳；
  /// 沒設定＝「選擇傳給誰」開挑選器。第六十六批人類指示）。
  Widget _editStep() {
    final contactRooms = widget.client.rooms
        .where((r) => _contactIds.contains(r.directChatMatrixID))
        .toList();
    final hasContacts = contactRooms.isNotEmpty;
    final names = [
      for (final r in contactRooms) _roomName(r),
    ].join('、');
    final spinner = const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.t('編輯緊急訊息'), // 文案草案（人類「開始編輯訊息」）
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
        const SizedBox(height: 16),
        if (hasContacts) ...[
          Text(
            '${S.t('傳送給緊急聯絡人')}（$names）？', // 人類指定格式
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _sending ? null : () => unawaited(_sendToContacts()),
            child: _sending ? spinner : Text(S.t('送出')), // 選是才傳出去
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _sending ? null : () => unawaited(_openPicker()),
            child: Text(S.t('選擇其他對象')), // 文案草案
          ),
        ] else ...[
          FilledButton(
            onPressed: _sending ? null : () => unawaited(_openPicker()),
            child: _sending
                ? spinner
                : Text(S.t('選擇傳給誰')), // 人類「編輯完選擇傳給誰」
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sending
              ? null
              : () => setState(() => _affected = false), // 回現況選擇
          child: Text(S.t('上一步')), // 文案草案
        ),
      ],
    );
  }
}
