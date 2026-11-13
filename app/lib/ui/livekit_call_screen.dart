// 第三十批（人類批准 2026-11-10）＋第三十一批（人類批准「全部移植」，
// 「其他人已離開」倒數 20 秒）— LiveKit（多人通話）畫面。
// mesh 群組通話畫面（group_call_screen.dart）功能全部映射過來：
//   音量表（說話高亮）、視訊關閉頭像、名稱、動態排版、螢幕分享、PiP、
//   參與者列表、放音裝置選單、前後鏡頭、前景服務、通話紀錄（在 manager）、
//   ＋mesh 批 29 草案之 B（他人離開倒數 20s 自動退出）／E（訊號不佳→重新
//   加入）／D（wake lock），外加「按返回＝通話繼續」批次 II-j 語意。
// 文案均為草案待人類設計；不出現任何技術術語。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

import '../bluetooth_permission.dart';
import '../pip_helper.dart';
import '../voip/call_manager.dart';
import '../voip/livekit_call_manager.dart';

class LiveKitCallScreen extends StatefulWidget {
  const LiveKitCallScreen({super.key, required this.room, required this.manager});

  final Room room;
  final CallManager manager;

  @override
  State<LiveKitCallScreen> createState() => _LiveKitCallScreenState();
}

class _LiveKitCallScreenState extends State<LiveKitCallScreen>
    with WidgetsBindingObserver {
  LiveKitCallManager? _lk;
  bool _controlsVisible = true;
  bool _pipActive = false;
  bool _wasInPip = false;
  LiveKitCallPhase? _prevPhase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  Future<void> _attach() async {
    // 第三十一批：session 由 CallManager 持有（返回後可再進入）。
    final manager = await widget.manager.getOrCreateLiveKit(widget.room);
    if (!mounted) {
      return;
    }
    setState(() => _lk = manager);
    manager.addListener(_onManagerChanged);
    if (manager.phase != LiveKitCallPhase.connected &&
        manager.phase != LiveKitCallPhase.joining) {
      unawaited(manager.join(widget.room));
    }
  }

  void _onManagerChanged() {
    if (!mounted) {
      return;
    }
    final lkManager = _lk;
    if (lkManager == null) {
      return;
    }
    final now = lkManager.phase;
    final prev = _prevPhase;
    _prevPhase = now;
    if (prev != null && prev != now && now == LiveKitCallPhase.left) {
      final notice = lkManager.exitNotice;
      Navigator.of(context).pop(); // 掛斷／自動退出 → 離開畫面
      if (notice != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notice)));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lkManager = _lk;
    if (lkManager == null) {
      return;
    }
    if (state == AppLifecycleState.paused &&
        !_wasInPip &&
        !_pipActive &&
        lkManager.phase == LiveKitCallPhase.connected) {
      unawaited(_autoEnterPip());
    }
    if (state == AppLifecycleState.resumed && _pipActive) {
      if (mounted) {
        setState(() {
          _pipActive = false;
          _controlsVisible = true;
        });
      }
    }
  }

  Future<void> _autoEnterPip() async {
    final ok = await PipHelper.enter();
    if (ok && mounted) {
      setState(() {
        _wasInPip = true;
        _pipActive = true;
        _controlsVisible = false;
      });
    }
  }

  @override
  void dispose() {
    final lkManager = _lk;
    if (lkManager != null) {
      lkManager.removeListener(_onManagerChanged);
      // 批次 II-j 語意：返回＝通話繼續；畫面 dispose 不 leave。
    }
    WidgetsBinding.instance.removeObserver(this);
    unawaited(PipHelper.unregisterObserver());
    _lk = null;
    super.dispose();
  }

  void _run(Future<void> Function() f) {
    unawaited(
      f().catchError((Object _) {
        // 控制操作失敗以橫幅文字呈現（manager 面已記）；此處不擋畫面。
      }),
    );
  }

  Future<void> _hangup() async {
    await _lk?.leave();
  }

  Future<void> _enterPip() async {
    final ok = await PipHelper.enter();
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('此裝置不支援子母畫面')));
    } else if (mounted) {
      setState(() => _pipActive = true);
    }
  }

  // 第三十二批④：通知（前景服務）生命週期改由 LiveKitCallManager 管理
  // （返回／最小化後 session 仍在、通知也持續）——畫面層不再啟停。

  // ---- 參與者列表（mesh 同款）---------------------------------------------

  void _showParticipants() {
    final lkManager = _lk;
    if (lkManager == null) {
      return;
    }
    final room = lkManager.room;
    final local = room?.localParticipant;
    final remotes = room?.remoteParticipants.values.toList() ?? const [];
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '參與者（${remotes.length + (local != null ? 1 : 0)}）',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            if (local != null)
              ListTile(
                leading: CircleAvatar(child: Text(_initial(local.identity))),
                title: Text(_displayName(local.identity)),
                subtitle: const Text('（我）'), // 文案草案
              ),
            for (final p in remotes)
              ListTile(
                leading: CircleAvatar(child: Text(_initial(p.identity))),
                title: Text(_displayName(p.identity)),
                subtitle: Text(p.identity),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 放音裝置（Discord 式選單；mesh 批次十／十三／二十語意移植）-----------

  /// 內建兩項＝電話（送話器）／喇叭：主路走官方
  /// `AudioManager.setCommunicationDevice`（Android 12+ 既有通道，batch 20
  /// 定案）；fallback 走 livekit 官方 `AudioManager.setSpeakerOutputPreferred`。
  /// 外部裝置（藍牙／有線）沿用既有 `ring/permissions` 溝通裝置枚舉／選擇。
  Future<void> _showAudioOutputSheet() async {
    await requestBluetoothPermission();
    final own = await enumerateCommunicationDevices();
    if (!mounted || _lk == null) {
      return;
    }
    final external = <AudioOutputOption>[];
    if (own != null) {
      for (final d in own) {
        if (d.id == 'builtin_earpiece' ||
            d.id == 'builtin_speaker' ||
            d.id == 'builtin_speaker_safe') {
          continue;
        }
        external.add(d);
      }
    }
    final result = await showModalBottomSheet<Object?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Text('選擇音訊輸出', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '這個電話', // 文案草案
                  style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
            _audioOutputRow(
              sheetContext,
              title: '電話', // 文案草案
              subtitle: '本機', // 文案草案
              icon: Icons.smartphone,
              selected: _speakerPreferred == false && _externalDevice == null,
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            _audioOutputRow(
              sheetContext,
              title: '喇叭', // 文案草案
              subtitle: '本機', // 文案草案
              icon: Icons.volume_up,
              selected: _speakerPreferred == true && _externalDevice == null,
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            if (own != null && external.isEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    '目前沒有偵測到外部放音裝置', // 文案草案
                    style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
            if (external.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Divider(height: 1, indent: 16, endIndent: 16),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '外部裝置', // 文案草案
                    style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
                          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              for (final d in external)
                _audioOutputRow(
                  sheetContext,
                  title: externalAudioTitle(d.id, d.name),
                  subtitle: d.name,
                  icon: d.id.contains('bluetooth') || d.id.contains('ble')
                      ? Icons.headset
                      : Icons.headphones,
                  selected: _externalDevice == d.id || (d.isCurrent && _externalDevice == null),
                  onTap: () => Navigator.pop(sheetContext, d.id),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (result is bool) {
      await _applyBuiltinAudio(result);
    } else if (result is String && result.isNotEmpty) {
      await _applyExternalAudio(result);
    }
  }

  bool _speakerPreferred = false;
  String? _externalDevice;

  Future<void> _applyBuiltinAudio(bool target) async {
    final builtinId = target ? 'builtin_speaker' : 'builtin_earpiece';
    // 主路：音訊管理員溝通裝置（Android 12+；batch 20 定案機制）。
    final verified = await setCommunicationDevice(builtinId);
    if (verified != null) {
      setState(() {
        _speakerPreferred = target;
        _externalDevice = null;
      });
      if (!verified && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('切換放音裝置失敗：裝置可能已斷線')), // 文案草案
        );
      }
      return;
    }
    // fallback：livekit 官方 AudioManager（<Android 12／channel 不可用）。
    await _lk?.setBuiltinSpeaker(target);
    setState(() {
      _speakerPreferred = target;
      _externalDevice = null;
    });
  }

  Future<void> _applyExternalAudio(String kind) async {
    final verified = await setCommunicationDevice(kind);
    if (verified != null) {
      setState(() => _externalDevice = verified ? kind : _externalDevice);
      if (!verified && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('切換放音裝置失敗：裝置可能已斷線')), // 文案草案
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此系統版本暫不支援選擇外部放音裝置')), // 文案草案
      );
    }
  }

  Widget _audioOutputRow(
    BuildContext sheetContext, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: Theme.of(sheetContext).textTheme.labelMedium?.copyWith(
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: selected
          ? Icon(
              Icons.circle,
              size: 20,
              color: Theme.of(sheetContext).colorScheme.primary,
            )
          : Icon(
              Icons.circle_outlined,
              size: 20,
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lkManager = _lk;
    if (lkManager == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return ListenableBuilder(
      listenable: lkManager,
      builder: (context, _) {
        switch (lkManager.phase) {
          case LiveKitCallPhase.joining:
            return _scaffold(
              title: '多人通話', // 文案草案
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(lkManager.statusText ?? '連線中…'), // 文案草案
                  ],
                ),
              ),
            );
          case LiveKitCallPhase.connected:
            return _scaffold(title: '多人通話', body: _connectedBody(lkManager));
          case LiveKitCallPhase.error:
            return _scaffold(
              title: '多人通話',
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        lkManager.errorMessage ?? '發生錯誤',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () => _run(_hangup),
                      child: const Text('關閉'), // 文案草案
                    ),
                  ],
                ),
              ),
            );
          case LiveKitCallPhase.left:
            return _scaffold(
              title: '多人通話',
              body: const Center(child: CircularProgressIndicator()),
            );
        }
      },
    );
  }

  Widget _scaffold({required String title, required Widget body}) {
    // 第三十二批①（人類拍板「改成自動 PiP」）：按返回＝自動縮子母畫面、
    // 通話續行不離開；PiP 不可用（裝置不符／已在 PiP）才真的 pop 回原畫面
    // （session 仍由 manager 持有，可再進入；但背景中擷取不受保護）。
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        await _autoEnterPipOnBack();
      },
      child: Scaffold(
        appBar: _pipActive ? null : AppBar(title: Text(title)),
        body: body,
        backgroundColor: Colors.black87, // 骨架占位，待人類設計
      ),
    );
  }

  /// 返回鍵路徑：成功進 PiP → 保持畫面（PiP 覆蓋）；失敗 → 正常 pop。
  Future<void> _autoEnterPipOnBack() async {
    final lkManager = _lk;
    if (lkManager == null) {
      return;
    }
    if (lkManager.phase == LiveKitCallPhase.connected &&
        !_pipActive &&
        await PipHelper.isSupported()) {
      final ok = await PipHelper.enter();
      if (ok && mounted) {
        setState(() {
          _wasInPip = true;
          _pipActive = true;
          _controlsVisible = false;
        });
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _connectedBody(LiveKitCallManager lkManager) {
    final roomName =
        widget.room.name.isNotEmpty ? widget.room.name : widget.room.id;
    final lkRoom = lkManager.room;
    final local = lkRoom?.localParticipant;
    final remotes = lkRoom?.remoteParticipants.values.toList() ?? const [];
    final n = remotes.length + (local != null ? 1 : 0);
    return Column(
      children: [
        if (!_pipActive)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '多人通話（$n 人）', // 文案草案
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '參與者',
                  onPressed: _showParticipants,
                  icon: const Icon(Icons.people, color: Colors.white),
                ),
              ],
            ),
          ),
        // B｜他人離開倒數橫幅。
        if (lkManager.othersLeftCountdown >= 0)
          _banner('其他人已離開，${lkManager.othersLeftCountdown} 秒後自動結束'), // 文案草案
        // E｜訊號不佳橫幅＋重新加入。
        if (lkManager.qualityPoor)
          _banner(
            '訊號不佳', // 文案草案
            actionLabel: '重新加入', // 文案草案
            onAction: () => _run(lkManager.rejoin),
          ),
        // 階段提示（如麥克風啟用失敗）橫幅。
        if (lkManager.statusText != null) _banner(lkManager.statusText!),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _controlsVisible = !_controlsVisible),
            child: local == null && remotes.isEmpty
                ? const Center(child: Text('等待其他人加入…')) // 文案草案
                : _mediaArea(lkManager, local, remotes),
          ),
        ),
        // 第三十二批⑥：表情符號飄浮（草案樣式，待人類設計）。
        if (lkManager.recentReactions.isNotEmpty)
          _reactionsOverlay(lkManager),
        if (_controlsVisible && !_pipActive) _controls(lkManager),
      ],
    );
  }

  /// 媒體區：有螢幕分享（本機或遠端）→ 大畫面＋縮圖列（mesh 批次 II-e 同款）；
  /// 否則動態磚格（1／2／3 欄）。
  Widget _mediaArea(
    LiveKitCallManager lkManager,
    lk.LocalParticipant? local,
    List<lk.RemoteParticipant> remotes,
  ) {
    final shareProvider = _shareProviderOf(lkManager, local, remotes);
    if (shareProvider == null) {
      final participants = <lk.Participant>[?local, ...remotes];
      final n = participants.length;
      return GridView.count(
        crossAxisCount: n <= 1 ? 1 : (n <= 4 ? 2 : 3),
        padding: const EdgeInsets.all(4),
        children: [
          for (final participant in participants)
            _TileView(participant: participant, manager: lkManager),
        ],
      );
    }
    final shareTrack = shareProvider is lk.LocalParticipant
        ? lkManager.localScreenShareTrack
        : lkManager.screenShareTrackOf(shareProvider);
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: shareTrack != null
              ? lk.VideoTrackRenderer(shareTrack)
              : const Center(
                  child:
                      Icon(Icons.desktop_windows, color: Colors.white54, size: 40),
                ),
        ),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (local != null)
                SizedBox(
                  width: 96,
                  child: _TileView(participant: local, manager: lkManager),
                ),
              for (final p in remotes)
                SizedBox(
                  width: 96,
                  child: _TileView(participant: p, manager: lkManager),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  lk.Participant? _shareProviderOf(
    LiveKitCallManager lkManager,
    lk.LocalParticipant? local,
    List<lk.RemoteParticipant> remotes,
  ) {
    if (local != null && lkManager.isScreenSharing) {
      return local;
    }
    for (final p in remotes) {
      if (lkManager.screenShareTrackOf(p) != null) {
        return p;
      }
    }
    return null;
  }

  Widget _banner(String text, {String? actionLabel, VoidCallback? onAction}) {
    return Container(
      width: double.infinity,
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(text)), // 草案樣式
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  // ---- 第三十二批⑥：通話表情符號（草案 UI，參考 Element X 行為＝點選即
  // 向所有人飄出；Element XFlutter repo 已下架，僅產品行為參照無原始碼）。

  /// 草案 emoji 清單（待人類定稿：日裔常用＋Element Call 常見集合）。
  static const List<String> _reactionEmojis = [
    '👍', '\u2764\ufe0f', '😂', '😮', '😢', '🙏', '🔥', '🎉', '👏', '😅',
  ];

  Future<void> _showReactionSheet() async {
    final lkManager = _lk;
    if (lkManager == null) {
      return;
    }
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('表情符號', style: Theme.of(sheetContext).textTheme.titleMedium), // 文案草案
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _reactionEmojis)
                    IconButton.outlined(
                      tooltip: e,
                      onPressed: () => Navigator.pop(sheetContext, e),
                      icon: Text(
                        e,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || emoji == null) {
      return;
    }
    _run(() => lkManager.sendReaction(emoji));
  }

  /// 表情符號飄浮層（草案：媒體區下緣一列小膠囊「名 emoji」，5 秒自動消失）。
  Widget _reactionsOverlay(LiveKitCallManager lkManager) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final r in lkManager.recentReactions)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _displayName(r.identity),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const TextSpan(text: ' '),
                        TextSpan(text: r.emoji),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(LiveKitCallManager lkManager) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton.filled(
            tooltip: lkManager.isMicOn ? '靜音' : '取消靜音',
            onPressed: () => _run(lkManager.toggleMic),
            icon: Icon(lkManager.isMicOn ? Icons.mic : Icons.mic_off),
          ),
          IconButton.filled(
            tooltip: lkManager.isCamOn ? '關閉攝影機' : '開啟攝影機',
            onPressed: () => _run(lkManager.toggleCam),
            icon: Icon(lkManager.isCamOn ? Icons.videocam : Icons.videocam_off),
          ),
          IconButton.filled(
            tooltip: '切換鏡頭', // 文案草案
            onPressed: () => _run(lkManager.flipCamera),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
          IconButton.filled(
            tooltip: '選擇音訊輸出', // 文案草案
            onPressed: () => _run(_showAudioOutputSheet),
            icon: Icon(_speakerPreferred && _externalDevice == null
                ? Icons.volume_up
                : Icons.phone_in_talk),
          ),
          IconButton.filled(
            tooltip: '表情符號', // 第三十二批⑥；文案草案
            onPressed: _showReactionSheet,
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
          IconButton.filled(
            tooltip: lkManager.isScreenSharing ? '停止分享' : '分享螢幕',
            onPressed: () => _run(lkManager.toggleScreenShare),
            icon: Icon(lkManager.isScreenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share),
          ),
          IconButton.filled(
            tooltip: '子母畫面',
            onPressed: _enterPip,
            icon: const Icon(Icons.picture_in_picture_alt),
          ),
          IconButton.filled(
            tooltip: '離開通話',
            style: IconButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _run(_hangup),
            icon: const Icon(Icons.call_end, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ---- 名稱顯示輔助（identity=`<userId>:<deviceId>` → 本地段）--------------

  static String _displayName(String identity) {
    final colon = identity.indexOf(':');
    if (colon <= 0) {
      return identity.isEmpty ? '…' : identity;
    }
    return identity.substring(1, colon);
  }

  static String _initial(String identity) {
    final name = _displayName(identity);
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}

/// externalAudioTitle：外部溝通裝置型別名 → 中文草案（mesh group_call_screen
/// `_externalAudioTitle` 同款對照；未知回傳原始名稱）。
String externalAudioTitle(String kind, String label) {
  switch (kind) {
    case 'bluetooth':
    case 'bluetooth_sco':
    case 'bluetooth_a2dp':
    case 'ble_headset':
    case 'ble_speaker':
      return '藍牙耳機'; // 文案草案
    case 'wired-headset':
    case 'wired_headset':
    case 'wired_headphones':
    case 'usb_headset':
      return '有線耳機'; // 文案草案
    default:
      return label;
  }
}

/// 單一磚塊：視訊渲染＋名籤＋說話高亮（綠框＋音量表圖示），視訊關閉顯示
/// 頭像占位。骨架樣式，待人類設計。
class _TileView extends StatelessWidget {
  const _TileView({required this.participant, required this.manager});

  final lk.Participant participant;
  final LiveKitCallManager manager;

  @override
  Widget build(BuildContext context) {
    final isLocal = participant is lk.LocalParticipant;
    final track = manager.videoTrackOf(participant);
    final speaking = manager.activeSpeakerIdentities.contains(participant.identity);
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: speaking ? Border.all(color: Colors.greenAccent, width: 3) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.hardEdge,
      color: Colors.black26,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null)
            lk.VideoTrackRenderer(track)
          else
            Center(
              child: CircleAvatar(
                radius: 24,
                child: Text(_TileViewText.initial(participant.identity)),
              ),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black45,
              child: Text(
                isLocal ? '我' : liveKitTileLabel(participant), // 文案草案
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          if (speaking)
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.graphic_eq, color: Colors.greenAccent, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

/// 磚塊頭像首字輔助。
class _TileViewText {
  const _TileViewText._();

  static String initial(String identity) {
    final colon = identity.indexOf(':');
    final name = colon > 0 ? identity.substring(1, colon) : identity;
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}
