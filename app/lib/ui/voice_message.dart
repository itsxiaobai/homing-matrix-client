// 第七十批 d：語音訊息播放元件（Homing 自有，非 LINE 素材）。
// 播放走 just_audio；音訊檔由官方 Room.sendFileEvent 傳送（加密房自動加密），
// 「跟一般訊息一樣」——本檔不碰加密／金鑰。
library;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../whisper_stt.dart' as whisper;

/// 語音訊息播放列（可播放／暫停、顯示進度）。
class VoiceMessageTile extends StatefulWidget {
  const VoiceMessageTile({
    required this.url,
    required this.fileName,
    this.color,
    // 第九十二批：本機 Whisper 轉錄（偏好開啟時顯示「轉文字」按鈕）。
    this.enableTranscript = false,
    super.key,
  });

  /// 是否顯示本機轉文字按鈕（無障礙偏好）。
  final bool enableTranscript;

  /// 音訊檔 URL（SDK `event.attachment.mxc` / downloadUri）。
  final String url;

  /// 檔名（顯示於旁）。
  final String fileName;

  /// 前景色（泡泡文字色）。
  final Color? color;

  @override
  State<VoiceMessageTile> createState() => _VoiceMessageTileState();
}

class _VoiceMessageTileState extends State<VoiceMessageTile> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  String? _error; // 2026-11-21：播放失敗如實顯示，不再靜默吞掉
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _player.playerStateStream.listen((s) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_player.duration == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        // 2026-11-21：本機解密檔要用 setFilePath（setUrl 是給網路 URL，
        // 對本機路徑可能失敗）；失敗要如實顯示，不再 catch(_) 靜默。
        await _player.setFilePath(widget.url);
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = '播放失敗：$e';
          });
        }
        return;
      }
      if (mounted) setState(() => _loading = false);
    }
    try {
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _error = '播放失敗：$e');
    }
  }

  String _transcript = '';
  bool _transcribing = false;

  /// 第九十二批：本機 Whisper 轉錄（保全隱私、舊裝置可用 tiny 模型）。
  Future<void> _transcribe() async {
    if (_transcribing) return;
    setState(() {
      _transcribing = true;
      _transcript = '轉錄中…';
    });
    final text = await whisper.transcribeFile(widget.url);
    if (!mounted) return;
    setState(() {
      _transcript = text.isEmpty ? '轉錄失敗' : text;
      _transcribing = false;
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playing = _player.playing;
    final fg = widget.color ?? Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: playing ? '暫停' : '播放語音',
          onPressed: _loading ? null : _toggle,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(playing ? Icons.pause : Icons.play_arrow, color: fg),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 90,
          child: LinearProgressIndicator(
            value: _duration.inMilliseconds > 0
                ? _position.inMilliseconds / _duration.inMilliseconds
                : 0,
            color: fg,
            backgroundColor: fg.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(width: 6),
        Text(_fmt(playing || _position > Duration.zero ? _position : _duration),
            style: TextStyle(fontSize: 11, color: fg)),
        // 第九十二批：無障礙偏好開啟時顯示本機轉文字按鈕。
        if (widget.enableTranscript) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: '語音轉文字（本機）',
            icon: const Icon(Icons.text_fields, size: 18),
            color: fg,
            onPressed: _transcribing ? null : _transcribe,
          ),
        ],
      ],
    ),
    if (_error != null)
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 8),
        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
      ),
    if (_transcript.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 8),
        child: Text(
          _transcript,
          style: TextStyle(fontSize: 12, color: fg),
        ),
      ),
      ],
    );
  }
}
