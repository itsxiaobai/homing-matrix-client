// 第九十二批：本機 Whisper STT（whisper_ggml）——音檔轉錄＋模型分開下載。
// 隱私：音檔／模型全在本機，不送雲端、不需 API key。
// 舊裝置：tiny 模型最小最快（Android API 24+ 可跑）；使用者可選 base/small。
import 'dart:io';

import 'package:whisper_ggml/whisper_ggml.dart';

import 'ui/stt_model_prefs.dart';

/// 依偏好把 WhisperModel 轉成 whisper_ggml 的型別。
WhisperModel _model(SttModelChoice choice) => switch (choice) {
      SttModelChoice.base => WhisperModel.base,
      SttModelChoice.small => WhisperModel.small,
      SttModelChoice.tiny => WhisperModel.tiny,
    };

/// 轉錄本機音檔（首次使用會自動下載模型，之後快取）。
/// [onProgress] 為 0–100 的下載／推論進度（粗略）。
Future<String> transcribeFile(
  String audioPath, {
  String lang = 'zh',
  void Function(int percent)? onProgress,
}) async {
  if (!File(audioPath).existsSync()) return '';
  final controller = WhisperController();
  try {
    final result = await controller.transcribe(
      model: _model(ringSttModel.value),
      audioPath: audioPath,
      lang: lang,
      onProgress: onProgress,
    );
    return result?.transcription.text.trim() ?? '';
  } on Object {
    return ''; // 模型未下載／解碼失敗 → 靜默（不影響一般使用者）。
  }
}
