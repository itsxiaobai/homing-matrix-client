// 第八十批（人類指示）：通話「錄製中」**狀態**（不是實際錄音——錄音需新依賴，
// 人類選「先只做狀態開關＋UI」）。
//
// 做法：Homing 自訂 state event（`io.github.itsxiaobai.call.recording`）：
//  - 公開錄製狀態（預設開）：通話中寫入房間 state → 其他 Homing 用戶進房／
//    通話時讀到 → 聊天室名稱旁顯示「錄製中」。
//  - 關：只本機記憶，不寫 state（其他通話者看不到）。
// 結束通話清掉 state（其他用戶的標示消失）。
//
// 不新增依賴、不改加密邏輯（自訂 state 內容為非敏感布林值）；SDK 官方
// setRoomStateWithKey／room.states 讀寫。純函式部分可單測。

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'app_settings.dart';

/// Homing 自訂 state event type（記錄通話錄製中狀態）。
const String kCallRecordingStateType = 'io.github.itsxiaobai.call.recording';

/// state event 的 stateKey（單一即可；一房同時仅一通話錄製狀態）。
const String kCallRecordingStateKey = '';

/// 「公開錄製狀態」偏好（true＝讓所有通話者看見；預設開）。
final ValueNotifier<bool> ringPublicRecordingStatus =
    ValueNotifier<bool>(true);

const String _kPublicPrefKey = 'public_recording_status';

Future<void> loadPublicRecordingPref() async {
  try {
    ringPublicRecordingStatus.value =
        (await AppSettings.get(_kPublicPrefKey)) != '0'; // 預設開
  } on Object {
    ringPublicRecordingStatus.value = true;
  }
}

Future<void> setPublicRecordingPref(bool enabled) async {
  ringPublicRecordingStatus.value = enabled;
  try {
    await AppSettings.set(_kPublicPrefKey, enabled ? '1' : '0');
  } on Object {
    // 寫入失敗：本 session 仍生效。
  }
}

/// state 內容：{recording: bool, public: bool, ts: int}
Map<String, Object?> buildRecordingState({required bool recording, required bool publicVisible}) =>
    <String, Object?>{
      'recording': recording,
      'public': publicVisible,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

/// 解析 state event（內容是 JSON map；壞資料＝false）。
bool parseRecordingState(Map<String, Object?>? content) {
  if (content == null) return false;
  return content['recording'] == true;
}

/// 從房間 state 讀「錄製中」（其他 Homing 用戶的畫面用）。
bool isRoomRecording(Room room) {
  try {
    final state = room.states[kCallRecordingStateType]?[kCallRecordingStateKey];
    if (state == null) return false;
    return parseRecordingState(state.content);
  } on Object {
    return false;
  }
}

/// 寫入／清除（SDK 官方 API）。
Future<void> setRoomRecording(
  Room room, {
  required bool recording,
  required bool publicVisible,
}) async {
  if (!publicVisible && !recording) {
    // 結束時不論偏好都要清 state，避免其他用戶看到過期「錄製中」。
    await room.client.setRoomStateWithKey(
      room.id,
      kCallRecordingStateType,
      kCallRecordingStateKey,
      buildRecordingState(recording: false, publicVisible: false),
    );
    return;
  }
  await room.client.setRoomStateWithKey(
    room.id,
    kCallRecordingStateType,
    kCallRecordingStateKey,
    buildRecordingState(recording: recording, publicVisible: publicVisible),
  );
}

/// 本機「我正在標示錄製中」記憶（跨重開可選；此批只做 session 內 notifier）。
final ValueNotifier<bool> ringLocalCallRecording = ValueNotifier<bool>(false);
