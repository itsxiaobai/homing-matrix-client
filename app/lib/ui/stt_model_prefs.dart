// 第九十二批：本機 Whisper STT 模型偏好（分開下載、只本機）。
// 型號／下載狀態寫本機 kv；模型檔由 whisper_ggml 快取（首次使用自動下載）。
import 'package:flutter/foundation.dart';

import '../app_settings.dart';

/// 模型代號（對應 whisper_ggml 的 WhisperModel；用字串避免依賴 enum 於設定層）。
enum SttModelChoice { tiny, base, small }

final ValueNotifier<SttModelChoice> ringSttModel =
    ValueNotifier<SttModelChoice>(SttModelChoice.tiny);

/// 是否啟用通話即時字幕（預設關；需模型已下載）。
final ValueNotifier<bool> ringCallCaptions = ValueNotifier<bool>(false);

/// 是否啟用語音訊息「轉文字」按鈕（預設關）。
final ValueNotifier<bool> ringVoiceMessageTranscript = ValueNotifier<bool>(false);

const String _kModelKey = 'stt_model';
const String _kCaptionsKey = 'call_captions';
const String _kVoiceTranscriptKey = 'voice_msg_transcript';

/// 比照其他 prefs loader：DB 不可用時退回預設值，不讓未捕獲的 async error
/// 擊穿呼叫端（widget 測試環境未初始化 sqflite factory 即為此情境）。
Future<String?> _read(String key) async {
  try {
    return await AppSettings.get(key);
  } on Object {
    return null;
  }
}

Future<void> loadSttPrefs() async {
  ringSttModel.value = switch (await _read(_kModelKey)) {
    'base' => SttModelChoice.base,
    'small' => SttModelChoice.small,
    _ => SttModelChoice.tiny,
  };
  ringCallCaptions.value = (await _read(_kCaptionsKey)) == '1';
  ringVoiceMessageTranscript.value =
      (await _read(_kVoiceTranscriptKey)) == '1';
}

Future<void> setSttModel(SttModelChoice choice) async {
  ringSttModel.value = choice;
  await AppSettings.set(_kModelKey, choice.name);
}

Future<void> setCallCaptions(bool v) async {
  ringCallCaptions.value = v;
  await AppSettings.set(_kCaptionsKey, v ? '1' : '0');
}

Future<void> setVoiceMessageTranscript(bool v) async {
  ringVoiceMessageTranscript.value = v;
  await AppSettings.set(_kVoiceTranscriptKey, v ? '1' : '0');
}
