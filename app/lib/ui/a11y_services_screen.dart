// 第八十六批＋第九十二批：無障礙服務畫面（OCR/TTS/STT；本機處理、保護隱私）。
// 第九十二批新增：TTS 直接讀輸入文字、Whisper 模型選擇（分開下載）、
// 通話即時字幕 PoC 開關、語音訊息轉文字開關。
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../a11y_services.dart';
import '../l10n/app_strings.dart';
import 'stt_model_prefs.dart';
import '../whisper_stt.dart' as whisper;

class A11yServicesScreen extends StatefulWidget {
  const A11yServicesScreen({super.key});

  @override
  State<A11yServicesScreen> createState() => _A11yServicesScreenState();
}

class _A11yServicesScreenState extends State<A11yServicesScreen> {
  String _result = '';
  bool _busy = false;
  int _progress = 0;
  final TextEditingController _ttsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(loadSttPrefs());
  }

  @override
  void dispose() {
    _ttsCtrl.dispose();
    super.dispose();
  }

  Future<void> _ocr() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    setState(() => _busy = true);
    final text = await A11yOcr.recognize(picked.first.path!);
    if (!mounted) return;
    setState(() {
      _result = text.isEmpty ? S.t('未辨識到文字') : text;
      _busy = false;
    });
  }

  Future<void> _stt() async {
    setState(() => _busy = true);
    final text = await A11yStt.listenOnce();
    if (!mounted) return;
    setState(() {
      _result = text.isEmpty ? S.t('未辨識到語音') : text;
      _busy = false;
    });
  }

  /// 第九十二批：本機 Whisper 轉錄既有音檔（模型首次自動下載，之後快取）。
  Future<void> _transcribeFile() async {
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    if (picked.isEmpty || picked.first.path == null) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _result = S.t('首次使用會下載模型，請稍候…');
    });
    final text = await whisper.transcribeFile(
      picked.first.path!,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _result = text.isEmpty ? S.t('轉錄失敗或檔案無語音') : text;
      _busy = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('無障礙服務'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            S.t('所有辨識皆在本機處理，不送雲端、保護隱私'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // TTS 直接讀輸入文字（第九十二批 #3）。
          TextField(
            controller: _ttsCtrl,
            decoration: InputDecoration(
              labelText: S.t('輸入要朗讀的文字'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => unawaited(A11yTts.speak(_ttsCtrl.text)),
            icon: const Icon(Icons.volume_up),
            label: Text(S.t('朗讀輸入文字（TTS）')),
          ),
          const Divider(),
          // OCR / STT（通用）。
          ElevatedButton.icon(
            onPressed: _busy ? null : _ocr,
            icon: const Icon(Icons.image),
            label: Text(S.t('圖片轉文字（OCR）')),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _busy ? null : _stt,
            icon: const Icon(Icons.mic),
            label: Text(S.t('語音轉文字（STT・麥克風）')),
          ),
          const SizedBox(height: 8),
          // 第九十二批 #2：音檔 Whisper 轉錄（模型分開下載）。
          ElevatedButton.icon(
            onPressed: _busy ? null : _transcribeFile,
            icon: const Icon(Icons.audiotrack),
            label: Text(S.t('音檔轉文字（本機 Whisper）')),
          ),
          if (_busy) LinearProgressIndicator(value: _progress / 100),
          const Divider(),
          // 模型選擇（分開下載：首次轉錄時自動下載並快取）。
          Text(S.t('本機語音模型（首次使用自動下載）'),
              style: Theme.of(context).textTheme.titleSmall),
          ValueListenableBuilder<SttModelChoice>(
            valueListenable: ringSttModel,
            builder: (context, choice, _) => Column(
              children: [
                for (final m in SttModelChoice.values)
                  ListTile(
                    dense: true,
                    title: Text(switch (m) {
                      SttModelChoice.tiny => S.t('tiny（最快、舊裝置適用）'),
                      SttModelChoice.base => S.t('base（平衡）'),
                      SttModelChoice.small => S.t('small（較準、較慢）'),
                    }),
                    trailing: choice == m
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () => unawaited(setSttModel(m)),
                  ),
              ],
            ),
          ),
          const Divider(),
          // 第九十二批 #1 PoC：通話即時字幕開關。
          ValueListenableBuilder<bool>(
            valueListenable: ringCallCaptions,
            builder: (context, v, _) => SwitchListTile(
              title: Text(S.t('通話即時字幕（PoC）')),
              subtitle: Text(S.t('麥克風被通話佔用時可能無法辨識')),
              value: v,
              onChanged: (nv) => unawaited(setCallCaptions(nv)),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ringVoiceMessageTranscript,
            builder: (context, v, _) => SwitchListTile(
              title: Text(S.t('語音訊息顯示轉文字')),
              subtitle: Text(S.t('在語音訊息旁顯示本機轉錄結果')),
              value: v,
              onChanged: (nv) => unawaited(setVoiceMessageTranscript(nv)),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(child: Text(_result)),
          ),
        ],
      ),
    );
  }
}
