// Task 1.8 — joining friends (UI skeleton, design TBD)
//  anthropic/claude
// 1.8 加入好友：Matrix ID / QR code / 邀請連結
// JSON-LD ±<|constrain|>HTTP
// 依 AGENTS.md UI 規則：無樣式／最小樣式；QR 掃描 gracefully optional；
// 不寫加密邏輯；邀請實作由 SDK 提供（matrix-dart-sdk）。
//
// ⚠️ 1.8 涉及 perms 時，需再.split.（phone permissions 由 mobile_scanner 7.x handling cam permissions）。
// 批次 III-c（人類回報「好友邀請無法發送＆接收」）：發送端原本 `_defaultInvite`
// 是空 stub（顯示成功但沒做任何事）→ 改為官方 `Client.startDirectChat(mxid)`
// （建立／複用一對一聊天室並送出邀請；加密與 m.direct 記帳由 SDK 官方處理）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）


/// typedef for test injection
typedef InviteAction = Future<void> Function(String mxid);

typedef QrScanner = Future<String?> Function();

/// 從輸入（Matrix ID / matrix.to 連結／QR 掃描值）解析出 Matrix ID；若無效，回 null。
String? parseMatrixUserId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  // 剝掉 matrix.to prefix （例 matrix.to/#/@alice:example.org）
  var candidate = trimmed;
  final matrixToMatch = RegExp(r'matrix\.to/#/(@[^?]*)', caseSensitive: false).firstMatch(candidate);
  if (matrixToMatch != null) {
    candidate = matrixToMatch.group(1)!;
  }
  // 從 matrix uri parse （matrix:u/alice:example.org）
  if (candidate.startsWith('matrix:')) {
    candidate = candidate
        .replaceFirst(RegExp(r'^matrix:(u/)?'), '')
        .replaceFirst('@', '');
    candidate = '@$candidate';
  }
  candidate = candidate.trim();

  // validate matrix id
  final match = RegExp(r'^@[a-zA-Z0-9._=:/\-]+:\w[\w.-]*$').firstMatch(candidate);
  if (match == null) return null;
  return candidate;
}

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({
    super.key,
    required this.homeserver,
    this.client,
    this.invite,
    this.scanQr,
  });

  final Uri homeserver;

  /// 批次 III-c：SDK client（提供時 `_defaultInvite` 才會實際送出邀請）。
  final Client? client;

  final InviteAction? invite;
  final QrScanner? scanQr;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _controller = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onInvite() async {
    final mxid = parseMatrixUserId(_controller.text);
    if (mxid == null) {
      setState(() => _message = '請輸入有效的 Matrix ID（@user:domain）或 QR code 值');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });

    String? error;
    try {
      await (widget.invite ?? _defaultInvite)(mxid);
    } catch (e) {
      error = '邀請失敗：$e'; // 文案草案
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? '已送出邀請至 $mxid';
    });
  }

  Future<void> _defaultInvite(String mxid) async {
    final client = widget.client;
    if (client == null) {
      // 未提供 client（舊呼叫點／測試）→ 不假裝成功：明確回錯。
      throw StateError('未提供 SDK client，無法送出邀請');
    }
    // 批次 III-c：官方 API——建立（或複用既有）一對一聊天室並邀請對方。
    // 加密房判斷與 m.direct account data 由 SDK 官方 startDirectChat 處理；
    // 本檔零加密邏輯。回傳 roomId（已加入、對方收到邀請）。
    await client.startDirectChat(mxid);
  }

  Future<void> _onScanQr() async {
    setState(() {
      _busy = true;
      _message = null;
    });

    String? scanned;
    try {
      scanned = await (widget.scanQr ?? _defaultScan)();
      if (scanned != null) {
        final mxid = parseMatrixUserId(scanned);
        if (mxid == null) {
          // 掃到的不是 Homing 可解析的好友碼（例：Element X 的裝置驗證 QR、
          // 其他 URL 格式）。仍把原始值填入輸入欄供人判讀，但**明確提示**，
          // 不再「填了字串沒有任何反應」。
          _controller.text = scanned;
          setState(() {
            _message =
                '此 QR 內容不是 Homing 好友碼（需 @user:server 或 matrix.to 連結）'; // 文案草案
          });
          return;
        }
        _controller.text = mxid;
        // 人類批准 2026-11-06：掃出有效好友碼後**先確認再送出**，
        // 避免誤掃直接加好友；未再陷「掃完無反應」。
        if (!mounted) {
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(S.t('加入好友')), // 文案草案
            content: Text('${S.t('要送出邀請給 ')}$mxid？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(S.t('取消')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(S.t('送出邀請')),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _onInvite();
        }
      }
    } catch (e) {
      // 掃碼流程錯誤（相機不可用、pop 後 context 失效等）不再靜默。
      if (mounted) {
        setState(() {
          _message = '掃碼失敗：$e'; // 文案草案
          _busy = false;
        });
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showMyQr() async {
    final mxid = widget.client?.userID;
    if (mxid == null || mxid.isEmpty) {
      setState(() => _message = '尚未登入，無法顯示 QR'); // 文案草案
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('我的 QR（掃碼邀請）')), // 文案草案
        content: SizedBox(
          width: 260,
          child: QrImageView(
            data: mxid,
            version: QrVersions.auto,
            size: 200,
            // 第 18 點：QR 顏色依主題亮度自動對比（淺色主題＝深色模組；深色主題＝淺色模組），
            // 避免全黑 QR 在深色背景下不可掃描。
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Theme.of(ctx).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Theme.of(ctx).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.t('關閉'))), // 文案草案
        ],
      ),
    );
  }

  Future<String?> _defaultScan() async {
    // 預設導航至 MobileScanner wrapper；正面測試會由 injected callback 替代。
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('加入好友'))), // 文案待 UI 定稿
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Matrix ID 或邀請連結（ invite link / QR 值 ）',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: _busy ? null : _onInvite, child: Text(S.t('送出邀請'))),
                TextButton(onPressed: _busy ? null : _onScanQr, child: Text(S.t('掃碼'))),
                // 批次 III-c（人類批准 qr_flutter 2026-11-03）：顯示自己的 QR。
                TextButton(
                  onPressed: _showMyQr,
                  child: Text(S.t('我的 QR')), // 文案草案
                ),
              ],
            ),
            if (_message != null) Text(_message!),
            const SizedBox(height: 8),
            Text(S.t('說明：QR 掃描由 mobile_scanner（人類批准）提供，回调回傳 invite 值。')),
          ],
        ),
      ),
    );
  }
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  /// 連續偵測同一張碼時 onDetect 會多次觸發；第二次 pop 已失效的 context
  /// 會丟例外。改以旗標保證只 pop 一次。
  bool _popped = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('掃描 QR'))),
      body: MobileScanner(
        // 相機權限被拒／鏡頭不可用時給明確提示（原為黑屏靜默）。
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '無法掃描：相機不可用或未授權（${error.errorCode.name}）\n'
                '請於系統設定允許 Homing 使用相機後重試', // 文案草案
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
        onDetect: (capture) {
          if (_popped) {
            return;
          }
          final value = capture.barcodes.firstOrNull?.rawValue;
          if (value != null) {
            _popped = true;
            Navigator.of(context).pop(value);
          }
        },
      ),
      // 最小樣式提示（草案）：對準對方「我的 QR」。
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(S.t('將對方「我的 QR」對準畫面即可加入好友')),
        ),
      ),
    );
  }
}
