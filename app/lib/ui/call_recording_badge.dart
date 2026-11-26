// 第八十批：通話標題右側「錄製中」標示＋公開錄製狀態開關 sheet。
// 只做狀態（不是實際錄音）；其他 Homing 用戶由 room state 讀到同一狀態。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../call_recording_status.dart';
import '../l10n/app_strings.dart';
import 'app_icons_generated.dart';
import 'compound_icon.dart'; // 2026-11-20：開始錄製按鈕圖示

/// 標題列右側的「錄製中」小標（公開狀態或本機狀態任一成立即顯示）。
class CallRecordingBadge extends StatelessWidget {
  const CallRecordingBadge({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ringLocalCallRecording,
      builder: (context, local, _) {
        final visible = local || isRoomRecording(room);
        if (!visible) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            S.t('錄製中'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

/// 通話中「錄製狀態」開關 sheet。
/// - 「公開錄製狀態」(預設開)：寫 room state → 其他 Homing 通話者看得到。
/// - 本機開關：只自己看得到（不寫 state）。
Future<void> showCallRecordingSheet(
  BuildContext context, {
  required Room room,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.t('錄製狀態'),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            SwitchListTile(
              title: Text(S.t('標示錄製中')),
              subtitle: Text(S.t('只顯示狀態；實際錄音尚未提供')),
              value: ringLocalCallRecording.value,
              onChanged: (v) async {
                ringLocalCallRecording.value = v;
                await setRoomRecording(
                  room,
                  recording: v,
                  publicVisible: ringPublicRecordingStatus.value,
                );
                setState(() {});
              },
            ),
            SwitchListTile(
              title: Text(S.t('公開錄製狀態')),
              subtitle: Text(S.t('開＝所有通話者都能看見錄製中（預設開）')),
              value: ringPublicRecordingStatus.value,
              onChanged: (v) async {
                await setPublicRecordingPref(v);
                await setRoomRecording(
                  room,
                  recording: ringLocalCallRecording.value,
                  publicVisible: v,
                );
                setState(() {});
              },
            ),
            ListTile(
              leading: Icon(AllIcons.infoOutline),
              title: Text(S.t('狀態會顯示在通話標題右側')),
            ),
            // 2026-11-20：開始錄製按鈕（語音訊息鍵設計；目前為狀態切换）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton.icon(
                onPressed: () async {
                  final next = !ringLocalCallRecording.value;
                  ringLocalCallRecording.value = next;
                  await setRoomRecording(
                    room,
                    recording: next,
                    publicVisible: ringPublicRecordingStatus.value,
                  );
                  setState(() {});
                },
                icon: CompoundIcon(CompoundIcons.record,
                    size: 18, color: Colors.white),
                label: Text(ringLocalCallRecording.value
                    ? S.t('停止錄製')
                    : S.t('開始錄製')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
