// 第八十六批（人類指示）：無障礙服務——OCR／TTS／STT。
// **隱私設計**：全部本機處理（TTS/STT 用系統引擎、OCR 用 ML Kit 本機模型），
// 不送雲端、不上传任何訊息／圖片／音檔；舊裝置可跑（無需雲端 API／大模型）。
// 新增依賴：flutter_tts / speech_to_text / google_mlkit_text_recognition。
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 文字轉語音（ TalkBack 之外的「讀出訊息」）。
class A11yTts {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  static Future<void> speak(String text, {String locale = 'zh-TW'}) async {
    try {
      if (!_ready) {
        await _tts.setLanguage(locale);
        await _tts.setSpeechRate(0.9);
        _ready = true;
      }
      await _tts.speak(text);
    } on Object {
      // 無 TTS 引擎 → 靜默（不影響一般使用者）。
      return;
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // 引擎未就緒時停止失敗可忽略。
      return;
    }
  }
}

/// 語音轉文字（把語音訊息／麥克風內容轉成可讀文字；本機引擎）。
class A11yStt {
  static final SpeechToText _stt = SpeechToText();
  static bool _available = false;

  static Future<bool> initialize() async {
    try {
      _available = await _stt.initialize();
    } on Object {
      _available = false;
    }
    return _available;
  }

  /// 監聽一段語音（需麥克風權限）；結果透過回呼回傳。
  static Future<String> listenOnce({
    String locale = 'zh-TW',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_available && !await initialize()) return '';
    final buffer = StringBuffer();
    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(localeId: locale),
        onResult: (r) => buffer.writeln(r.recognizedWords),
      );
      await Future<void>.delayed(timeout);
      await _stt.stop();
    } on Object {
      // 失敗回傳已辨識部分（buffer 可能為空）。
      return buffer.toString().trim();
    }
    return buffer.toString().trim();
  }

  static Future<void> stop() async {
    try {
      await _stt.stop();
    } on Object {
      // 引擎未就緒時停止失敗可忽略。
      return;
    }
  }
}

/// 圖片轉文字（OCR；ML Kit **本機**模型，不送雲端）。
class A11yOcr {
  static Future<String> recognize(String imagePath) async {
    if (!File(imagePath).existsSync()) return '';
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text;
    } on Object {
      return '';
    } finally {
      recognizer.close();
    }
  }
}
