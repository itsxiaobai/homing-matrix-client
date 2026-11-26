// backlog 批次 D（人類指示 2026-11-01，含投票）：發起投票畫面（草案）。
// 只用 SDK 官方 API：matrix 14.2.0 `msc_extensions/msc_3381_polls`
// （`Room.startPoll` + `PollAnswer`；事件前綴為 unstable `org.matrix.msc3381.poll.*`
// —— 本機源碼 PollEventContent.startType，與 Element 的穩定 `m.poll.*` 可能
// 不互通：Element 僅顯示 fallback 文字。此限制記錄於 PROGRESS.md。零加密邏輯）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import './a11y.dart'; // 無障礙：按鈕功能說明
import 'line_style.dart'; // 68e/68f：共用標題語彙

/// 發起投票（測試可注入 [startPoll]；預設=SDK 官方 `Room.startPoll`）。
class PollCreateScreen extends StatefulWidget {
  const PollCreateScreen({
    super.key,
    required this.room,
    this.startPoll,
  });

  final Room room;

  /// 注入點（預設用 SDK 官方 API）：
  /// 回傳 poll start event id（或 null）。
  final Future<String?> Function(String question, List<String> options,
      {required bool disclosed})? startPoll;

  @override
  State<PollCreateScreen> createState() => _PollCreateScreenState();
}

class _PollCreateScreenState extends State<PollCreateScreen> {
  final _questionController = TextEditingController();

  /// 每個選項一個持久 controller（避免 rebuild 重建 controller 導致輸入重置）。
  final _options = <TextEditingController>[TextEditingController(), TextEditingController()];

  bool _disclosed = true; // 預設公開投票（草案）
  bool _submitting = false;

  bool get _valid {
    final question = _questionController.text.trim();
    final options = _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    return question.isNotEmpty && options.length >= 2;
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final question = _questionController.text.trim();
      final options = _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
      final f = widget.startPoll;
      if (f != null) {
        await f(question, options, disclosed: _disclosed);
      } else {
        // SDK 官方。
        await widget.room.startPoll(
          question: question,
          kind: _disclosed ? PollKind.disclosed : PollKind.undisclosed,
          maxSelections: 1, // 草案：先單選（待人類設計定稿）
          answers: [
            // 選項 id 用 ASCII（optN），避免事件 id 校驗問題；文字為人類輸入。
            for (var i = 0; i < options.length; i++)
              PollAnswer(id: 'opt${i + 1}', mText: options[i]),
          ],
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('無法發起投票：')}$e')), // 文案草案
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const maxOptions = 10; // SDK 上限 20；草案 UI 先限 10（待人類定稿）
    return Scaffold(
      appBar: AppBar(
        title: lineTitlePill(context, S.t('發起投票')), // 文案草案
        actions: [
          // 送出鈕以 controller 監聽驅動（不依賴 onChanged 的 rebuild）。
          ListenableBuilder(
            listenable: Listenable.merge([
              _questionController,
              ..._options,
            ]),
            builder: (context, _) => TextButton(
              onPressed: (_valid && !_submitting) ? _submit : null,
              child: Text(S.t('送出')), // 文案草案
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _questionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '問題', // 文案草案
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _options.length; i++)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _options[i],
                    decoration: InputDecoration(
                      labelText: '選項 ${i + 1}', // 文案草案
                    ),
                  ),
                ),
                a11yButton(label: S.t('刪除選項'), child: IconButton(
                  tooltip: S.t('刪除選項'),
                  onPressed: _options.length <= 2
                      ? null
                      : () {
                          setState(() {
                            _options.removeAt(i).dispose();
                          });
                        },
                  icon: Icon(AllIcons.removeCircleOutline),
                )),
              ],
            ),
          if (_options.length < maxOptions)
            TextButton.icon(
              onPressed: () {
                setState(() => _options.add(TextEditingController()));
              },
              icon: Icon(AllIcons.add),
              label: Text(S.t('新增選項')), // 文案草案
            ),
          SwitchListTile(
            // 文案草案：disclosed＝投票後可見投票人。
            title: Text(S.t('公開投票（顯示投票人）')),
            value: _disclosed,
            onChanged: (v) {
              setState(() => _disclosed = v);
            },
          ),
          const SizedBox(height: 8),
          Text(
            // 範圍限制文案（草案；來源：本機 SDK PollEventContent unstable 前綴）
            '注意：投票以 Matrix 事件（MSC3381）送出；其他客戶端（如 Element）'
            '可能只看到文字，無法投票。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
