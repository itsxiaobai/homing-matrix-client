// 2.6 skeleton — mute / unread badge UX
import 'package:flutter/material.dart';

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
      appBar: AppBar(title: const Text('靜音/未讀徽章（Skeleton）')),
      body: Column(
        children: [
          if (_badge > 0 && !_muted)
            Badge(
              label: Text('$_badge'),
              child: const Icon(Icons.message, color: Colors.black),
            ),
          if (_muted) const Text('已靜音'),
          TextButton(onPressed: _toggleMute, child: Text(_muted ? '取消靜音' : '靜音')),
        ],
      ),
    );
  }
}
