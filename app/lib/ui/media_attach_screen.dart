// 2.8 skeleton — attach photo/video (UI only)
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import 'line_style.dart'; // 68e/68f：共用標題語彙

typedef MediaAttachAction = Future<void> Function(String path, bool isVideo);

class MediaAttachScreen extends StatefulWidget {
  const MediaAttachScreen({super.key, this.attach});
  final MediaAttachAction? attach;

  @override
  State<MediaAttachScreen> createState() => _MediaAttachScreenState();
}

class _MediaAttachScreenState extends State<MediaAttachScreen> {
  final _controller = TextEditingController();
  bool _isVideo = false;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onAttach() async {
    final path = _controller.text.trim();
    if (path.isEmpty) {
      setState(() => _message = '請輸入媒體路徑');
      return;
    }
    setState(() {_busy = true; _message = null;});
    String? err;
    try {
      await (widget.attach ?? _noop)(path, _isVideo);
    } catch (_) { err = '附加失敗'; }
    if (!mounted) return;
    setState(() {_busy = false; _message = err ?? '已送 "$path"（待 homeserver 上傳）';});
  }

  Future<void> _noop(String path, bool isVideo) async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: lineTitlePill(context, S.t('附加照片/影片（Skeleton）'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '本地路徑（placeholder; real圖片/视频selector由SDK/UI integration handling）'),
            ),
            SwitchListTile(
              value: _isVideo,
              onChanged: _busy ? null : (v) => setState(() => _isVideo = v),
              title: Text(S.t('影片')),
            ),
            TextButton(onPressed: _busy ? null : _onAttach, child: Text(_busy ? '傳送中…' : '附加')),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    );
  }
}
