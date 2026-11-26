// 2.6 skeleton — mute / unread badge UX
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import 'line_style.dart'; // 68e/68f：共用標題語彙

class MuteBadgeScreen extends StatefulWidget {
  const MuteBadgeScreen({super.key, this.initialBadgeCount = 0});

  final int initialBadgeCount;

  @override
  State<MuteBadgeScreen> createState() => _MuteBadgeScreenState();
}

class _MuteBadgeScreenState extends State<MuteBadgeScreen> {
  bool _muted = false;
  int _badge = 0;

  @override
  void initState() {
    super.initState();
    _badge = widget.initialBadgeCount;
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _badge = _muted ? 0 : widget.initialBadgeCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: lineTitlePill(context, S.t('靜音/未讀徽章（Skeleton）'))),
      body: Column(
        children: [
          if (_badge > 0 && !_muted)
            Badge(
              label: Text('$_badge'),
              child: Icon(AllIcons.message, color: Colors.black),
            ),
          if (_muted) Text(S.t('已靜音')),
          TextButton(onPressed: _toggleMute, child: Text(_muted ? '取消靜音' : '靜音')),
        ],
      ),
    );
  }
}
