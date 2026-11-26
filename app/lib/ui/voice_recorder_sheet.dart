// 第七十批 e：LINE 式語音訊息錄音面板（點 mic → 面板→ 錄音→ 試聽→ 送出）。
// 無障礙：每個按鈕皆有 tooltip＋Semantics label（人類指示「需為無障礙功能保留」）。
// 送出走官方 sendFileEvent（加密房 SDK 自動 crypto）；本檔不寫任何加密邏輯。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../l10n/app_strings.dart';
import 'a11y.dart';
import 'compound_icon.dart';

/// 語音錄音面板的結果（null＝取消；String＝本機錄音檔路徑）。
/// 呼叫端負責用官方 sendFileEvent 送出並清理暫存。
typedef VoiceRecordResult = Future<String?> Function(
  BuildContext context, {
  required String path,
  required int durationMs,
});

/// 顯示 LINE 式語音錄音面板。
/// 流程：點錄音 → 錄音中（計時＋停止／刪除）→ 試聽（播放／刪除／送出）。
Future<void> showVoiceRecorderSheet(
  BuildContext context, {
  required VoiceRecordResult onSend,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    // 第七十批 g：全寬（LINE 截圖：面板占滿螢幕寬度，不是置中窄卡）。
    // 只約束最小寬度＝螢幕寬；高度仍由內容決定（isScrollControlled）。
    constraints: BoxConstraints(
      minWidth: MediaQuery.sizeOf(context).width,
      maxWidth: MediaQuery.sizeOf(context).width,
    ),
    builder: (_) => _VoiceRecorderSheet(onSend: onSend),
  );
}

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet({required this.onSend});

  final VoiceRecordResult onSend;

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  /// idle：等候點錄音；recording：錄音中；review：可試聽／送出。
  String _stage = 'idle';
  String? _path;
  DateTime? _started;
  int _elapsedMs = 0;
  Timer? _ticker;
  bool _playing = false;
  bool _hasListened = false; // 第七十批 h：試聽過才allow送出（呼應「送出前先試聽」）

  void _markListened() {
    if (!_hasListened && mounted) setState(() => _hasListened = true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    // 取消時清暫存（已送出的由呼叫端清）。
    if (_stage != 'sent' && _path != null) {
      try { File(_path!).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('需要麥克風權限才能錄語音'))),
        );
      }
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _path!,
      );
      _started = DateTime.now();
      _elapsedMs = 0;
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {
          _elapsedMs = DateTime.now().difference(_started!).inMilliseconds;
        });
      });
      if (mounted) setState(() => _stage = 'recording');
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('錄音啟動失敗')}：$e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    try { await _recorder.stop(); } catch (_) {}
    if (_path == null || !File(_path!).existsSync() || _elapsedMs < 500) {
      if (mounted) setState(() => _stage = 'idle');
      return;
    }
    if (mounted) setState(() => _stage = 'review');
  }

  Future<void> _togglePlayback() async {
    if (_path == null) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await _player.setFilePath(_path!);
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
      await _player.play();
      if (mounted) setState(() => _playing = true);
      _markListened();
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_path == null) return;
    // 第七十批 h：送出前先試聽——未試聽按送出給提示，不送出。
    if (!_hasListened) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('請先試聽語音訊息'))),
        );
      }
      return;
    }
    final path = _path!;
    final ms = _elapsedMs;
    _stage = 'sent'; // 避免 dispose 清掉已送出的檔。
    Navigator.of(context).pop();
    await widget.onSend(context, path: path, durationMs: ms);
  }

  void _delete() {
    _ticker?.cancel();
    if (_path != null) {
      try { File(_path!).deleteSync(); } catch (_) {}
    }
    _path = null;
    _elapsedMs = 0;
    _hasListened = false;
    if (mounted) setState(() => _stage = 'idle');
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg = const Color(0xFF111111);
    final green = const Color(0xFF06C755);
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽把手
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 全寬內容（LINE：白色面板、大字提示、大圓鈕）。
            switch (_stage) {
              'idle' => _buildIdle(fg, green),
              'recording' => _buildRecording(fg, green),
              _ => _buildReview(fg, green),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildIdle(Color fg, Color green) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Text(S.t('點一下開始錄語音'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 17)),
          const SizedBox(height: 20),
          Semantics(
            button: true,
            label: S.t('開始錄音'),
            child: IconButton(
              tooltip: S.t('開始錄音'),
              onPressed: _startRecording,
              icon: Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300, width: 4),
                ),
                child: Center(
                  child: Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecording(Color fg, Color green) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      child: Column(
        children: [
          Text(_fmt(_elapsedMs),
              style: TextStyle(color: green, fontSize: 26, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionButton(
                icon: CompoundIcons.delete,
                label: S.t('取消錄音'),
                color: Colors.red,
                onTap: _delete,
              ),
              Semantics(
                button: true,
                label: S.t('停止錄音'),
                child: IconButton(
                  tooltip: S.t('停止錄音'),
                  onPressed: _stopRecording,
                  icon: Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: green),
                    child: Center(
                      child: Container(width: 28, height: 28, color: Colors.white),
                    ),
                  ),
                ),
              ),
              _actionButton(
                icon: CompoundIcons.sendSolid,
                label: S.t('送出語音'),
                color: Colors.blue,
                onTap: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReview(Color fg, Color green) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      child: Column(
        children: [
          Text(_fmt(_elapsedMs),
              style: TextStyle(color: green, fontSize: 26, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionButton(
                icon: CompoundIcons.delete,
                label: S.t('取消錄音'),
                color: Colors.red,
                onTap: _delete,
              ),
              Semantics(
                button: true,
                label: _playing ? S.t('暫停播放') : S.t('試聽語音'),
                child: IconButton(
                  tooltip: _playing ? S.t('暫停播放') : S.t('試聽語音'),
                  onPressed: _togglePlayback,
                  icon: Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: green, width: 5),
                    ),
                    child: Center(
                      child: CompoundIcon(
                        // 第七十批 h：中央是播放/暫停（不是紙飛機）。
                        _playing ? CompoundIcons.pause : CompoundIcons.play,
                        size: 38,
                        color: green,
                      ),
                    ),
                  ),
                ),
              ),
              _actionButton(
                icon: CompoundIcons.sendSolid,
                label: S.t('送出語音'),
                // 第七十批 h：未試聽 → 灰顯（禁用），試聽後才可送出。
                color: _hasListened ? Colors.blue : Colors.grey.shade400,
                onTap: _send, // 未試聽時 _send 內 guard 會提示「請先試聽」。
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: green,
            child: Text(
              _hasListened
                  ? S.t('試聽完成，可送出')
                  : S.t('送出前先試聽語音訊息'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return a11yButton(
      label: label,
      child: Semantics(
        button: true,
        label: label,
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Center(
              child: CompoundIcon(icon, size: 24, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
