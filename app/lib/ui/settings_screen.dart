// UI 重構（依人類 LINE_ref 標註，2026-11-01／批次 III-b 2026-11-03）— 設定頁。
// 依人類注記參考圖（new_ref/…210223_labeled.png）分區：
//   Profile 區（頭像＋更換頭像）／個人資訊／一般／App info（原始碼 GitHub）。
// 人類注記中**劃掉不採用**的項目（Premium／轉移 QR／帳號轉移／App icon／
// Coins／Home／Labs／About）不複製。LINE 品牌識別不模仿；顏色一律 Homing seed。
// 只列**既有**任務畫面；人類保留了但 Homing 尚無實作的項目（隱私／語言／通話），
// 以「尚未提供」骨架殼標示草案，不灌水假功能。
// 第二十五批（人類四項整合指示）：設定功能整合進首頁左上頭像——本檔抽出
// `SettingsBody`（無 Scaffold 殼的設定本體）供首頁頭像面板 bottom sheet 內嵌；
// `SettingsScreen` 改為薄 Scaffold 包裝（保留直接導向用法）。底列設定 tab 移除
// （人類拍板「是」）。進階區①裝置驗證＝官方 SAS 流程（rooms_screen 原樣搬入；
// SDK `KeyVerification.startVerification`→官方對話框）②診斷＝合併版（帳號
// 資訊＋加密狀態，含上傳裝置金鑰／自我簽章官方動作）；**無作用 skeleton
// `DeviceVerificationScreen` 移除**（官方沒有這個東西——人類指示）。
// 草案，待人類設計定稿。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'account_disable_screen.dart';
import 'appearance_screen.dart';
import 'blocked_users_screen.dart'; // 第十八批
import 'emergency_contacts_screen.dart'; // 第三十五批 #6
import 'data_export_screen.dart';
// 頭像移除旗標持久化（kv；0.7 儲存方案）。
import '../app_settings.dart';
import '../engine_init.dart' show kRustEngineErrorKey; // 第二十七批：Rust 引擎狀態旗標
import '../push/push_runtime.dart';
import 'design_tokens.dart'; // 第二十二批：分區標題 token 色
// 兩個裝置畫面皆定義同名 DeviceView；settings 只用 device_management 的型別。
import 'device_listing_screen.dart' hide DeviceView;
import 'device_management_screen.dart';
import 'device_verification_dialog.dart'; // 第二十五批：官方 SAS 對話框（共用）
import 'backup_restore_screen.dart';
import 'message_search_screen.dart';
import 'multi_device_login_screen.dart';
import 'notification_settings_screen.dart'; // 批次十二②
import 'push_permission_screen.dart';

/// 登出出口（供測試注入；預設 SDK `Client.logout`，成功後 popUntil 首頁）。
typedef SettingsLogout = Future<void> Function(Client client);

/// 第二十五批：設定頁薄殼（Scaffold＋AppBar）。
/// 設定本體＝[SettingsBody]；首頁頭像面板內嵌同本體（人類指示整合）。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.client, this.onLogout});

  final Client client;
  final SettingsLogout? onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')), // 文案待人類定稿
      body: SettingsBody(client: client, onLogout: onLogout),
    );
  }
}

/// 第二十五批：設定本體（底下各分區＋Profile 區，無 App 代管自己的殼）。
/// 首頁頭像點擊 → bottom sheet 內嵌本體（建立入口一次、樣式由人類定稿）。
class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key, required this.client, this.onLogout});

  final Client client;
  final SettingsLogout? onLogout;

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  bool _loggingOut = false;
  // 批次 III-b：自己頭像縮圖（官方 fetchOwnProfile→getThumbnailUri＋認證媒體）。
  (Uri, bool)? _profileAvatar;
  // 「移除頭像應同步更新」（人類回饋 2026-11-03／05「仍失敗」）：移除旗標——
  // server（Synapse profile 快取）可能在 setAvatar(null) 後數分鐘甚至到重啟
  // 前後仍回舊 avatar_url；本旗標保證 UI 端不再把舊頭像畫回來，直到
  // **server 明確回 null** 才清除。旗標**持久化**於 AppSettings kv
  // （`own_avatar_removed`），session 旗標僅作記憶體鏡像（v1 世代僅
  // session 級 → 重啟後失效，即人類回報「仍失敗」的成因之一）。
  bool _ownAvatarRemoved = false;
  // 批次第 3 點：自訂顯示名稱。
  String? _profileDisplayName;

  /// 本機 kv（與 remove/clear 邏輯同值；key 由 app_settings.dart 共用常數提供，
  /// 首頁頭像讀同一旗標——第二十五批，勿隨意改字面值）。
  static const String _kAvatarRemovedFlag = AppSettings.ownAvatarRemovedFlag;

  @override
  void initState() {
    super.initState();
    // 批次十三（頭像移除重開）：原寫法＝旗標 kv 與 _loadProfile() 同時起跑
    //（fire-and-forget）→ kv 讀取晚於 profile 回應時 `_ownAvatarRemoved`
    // 仍 false → 舊頭像已畫上畫面，旗標事後就位也**不會再清它**（人類實測
    // 「移除頭像重開後舊頭像又出現」成因）。修＝順序保證：旗標就位**先**
    // 於 profile 抓取（見 _initAvatarState）。
    unawaited(_initAvatarState());
  }

  /// 第十三批：先載入持久化移除旗標，就位後才抓 profile——消除 initState race。
  Future<void> _initAvatarState() async {
    try {
      final v = await AppSettings.get(_kAvatarRemovedFlag);
      if (mounted && v != null && v.isNotEmpty && !_ownAvatarRemoved) {
        setState(() => _ownAvatarRemoved = true);
      }
    } on Object {
      // 無 DB 環境（測試）／讀取失敗：照舊忽略。
    }
    // 旗標已就位 → 再抓 profile（此時 _loadProfile 內的旗標判斷為真值）。
    if (mounted) {
      unawaited(_loadProfile());
    }
  }

  /// 批次 III-b＋第 3 點：官方 fetchOwnProfile → 取得 avatar 與 displayName。
  Future<void> _loadProfile() async {
    try {
      final profile = await widget.client.fetchOwnProfile();
      if (mounted) {
        setState(() {
          _profileDisplayName = profile.displayName;
        });
      }
      final url = profile.avatarUrl;
      // 「移除頭像應同步更新」根因（人類回饋 2026-11-03）：原本 url == null
      // 直接 return，**舊頭像停在畫面上**。改：
      //  a) fetch 已取到 null avatar → 立即清空顯示；
      //  b) session 旗標 `_ownAvatarRemoved`：setAvatar(null) 後 server
      //     profile 快取可能短時間仍回舊值，旗標期間 UI 恆不畫舊頭像
      //    （下次成功更換時旗標清除、不再壓住真值）。
      if (url == null) {
        // server 已回「無頭像」→ 立即清空顯示。
        // 第九次（人類回饋「頭像需要將軟體重開才會消失」）：**不再自動清
        // 移除旗標**——Synapse profile 快取會在新舊值之間來回（先回 null
        // 之後又回舊 url），自動清旗標＝鬼影復活的破口。旗標＝使用者意圖
        // （「已移除」），唯一解除時機＝**成功設定新頭像**（見 _pickAvatar）。
        if (mounted) {
          setState(() => _profileAvatar = null);
        }
        return;
      }
      if (_ownAvatarRemoved) {
        if (mounted) {
          setState(() => _profileAvatar = null);
        }
        return;
      }
      final thumb = await url.getThumbnailUri(widget.client, width: 96, height: 96);
      final auth = await widget.client.authenticatedMediaSupported();
      if (mounted) {
        setState(() => _profileAvatar = (thumb, auth));
      }
    } on Object {
      // 失敗→保持 null
    }
  }

  /// 更換頭像（gallery/camera 二路共用；官方 `Client.setAvatar(MatrixFile)`）。
  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      await widget.client.setAvatar(
        MatrixFile(bytes: bytes, name: picked.name),
      );
      if (mounted) {
        // 下次成功更換 → 解除移除旗標（含持久化；讓 server 真值回到畫面）。
        _ownAvatarRemoved = false;
        unawaited(AppSettings.remove(_kAvatarRemovedFlag).catchError((_) {}));
        await _markOwnProfileOutdated();
        if (!mounted) return;
        setState(() => _loadProfile());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('頭像已更新')), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更換頭像失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 人類回饋 2026-11-03：長按移除反直覺 → 點按徽章出現三選項
  /// 「變更頭像（相簿）／拍照／移除頭像」（草案 UI，待人類定稿）。
  Future<void> _showAvatarActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('變更頭像'), // 文案草案
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'), // 文案草案
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (_profileAvatar != null)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined),
                title: const Text('移除頭像'), // 文案草案
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'gallery':
        await _pickAvatar(ImageSource.gallery);
      case 'camera':
        await _pickAvatar(ImageSource.camera);
      case 'remove':
        await _removeAvatar();
    }
  }

  /// Issues「頭像增加移除功能」：官方 `Client.setAvatar(null)` —— SDK 源碼
  ///（client.dart L1673-1680）對 Synapse 相容以**空字串**送出 avatar_url
  ///（送 null 不被 Synapse 接受）。移除後 `_loadProfile()` 刷新。
  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除頭像？'), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.client.setAvatar(null);
      if (mounted) {
        // session 旗標＋**持久化**旗標（重啟後仍有效；第九次起旗標＝唯一
        // 權威，`_loadProfile` 期間 UI 恆不畫舊頭像，直到成功設定新頭像）。
        // 寫入改 **await**：原先 `unawaited(...catchError((_) {}))` 靜默空吞，
        // 落盤失敗無從得知（重開後旗標不存在＝鬼影「需要重開才消失」的可能
        // 成因）→ 失敗如實提示。
        _ownAvatarRemoved = true;
        try {
          await AppSettings.set(_kAvatarRemovedFlag, '1');
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('移除旗標未能保存：$e')), // 文案草案
            );
          }
        }
        await _markOwnProfileOutdated();
        if (!mounted) return;
        setState(() => _profileAvatar = null);
        unawaited(_loadProfile());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('頭像已移除')), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除頭像失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 相機徽章（頭像右下角；兩分支共用，點擊即 `_showAvatarActions`）。
  Widget _avatarCameraBadge() {
    return Positioned(
      right: 0,
      bottom: 0,
      child: InkWell(
        // 人類回饋 2026-11-03：點按 → 三選項 sheet
        //（無頭像時 sheet 不顯示「移除頭像」）。
        onTap: () => unawaited(_showAvatarActions()),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.photo_camera, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  /// 標記自己 profile 快取過期（SDK 官方 API；client.dart L1180
  /// `storeUserProfile`）。變更／移除頭像後立即呼叫，`fetchOwnProfile`
  /// 即不再回 1 天快取的舊值——修「頭像移除沒有即時更新」。
  Future<void> _markOwnProfileOutdated() async {
    final uid = widget.client.userID;
    if (uid == null) {
      return;
    }
    try {
      // 官方 `CachedProfileInformation.fromProfile`：`outdated: true` 使
      // `getUserProfile`（client.dart L1152-1163）跳過快取直接向 server 抓。
      await widget.client.database.storeUserProfile(
        uid,
        CachedProfileInformation.fromProfile(
          ProfileInformation(displayname: null, avatarUrl: null),
          outdated: true,
          updated: DateTime.now(),
        ),
      );
    } catch (_) {
      // 標記失敗不致命：最終仍會由 m.room.member 同步事件 mark outdated。
    }
  }

  /// 批次第 3 點：自訂顯示名稱（官方 `setProfileField` 設定 display_name）。
  Future<void> _changeDisplayName() async {
    final controller = TextEditingController(text: _profileDisplayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('設定顯示名稱'), // 文案草案
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '顯示名稱'), // 文案草案
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('儲存'), // 文案草案
          ),
        ],
      ),
    );
    if (newName == null || newName == _profileDisplayName || !mounted) {
      return;
    }
    try {
      await widget.client.setProfileField(
        widget.client.userID!,
        'displayname',
        {'displayname': newName.isEmpty ? null : newName},
      );
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('顯示名稱已更新')), // 文案草案
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新顯示名稱失敗：$e')), // 文案草案
        );
      }
    }
  }

  Future<void> _onLogout() async {
    if (_loggingOut) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登出'), // 文案待人類定稿
        content: const Text('確定要登出此裝置？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _loggingOut = true);
    // 任務 3 批次 A（人類批准 2026-11-07）：登出先清推播註冊（UP
    // unregister＋homeserver pusher 刪除）；失敗靜默，不擋登出。
    try {
      await RingPushRuntime.teardown();
    } catch (_) {}
    try {
      await (widget.onLogout ?? (c) => c.logout())(widget.client);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登出失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    // 第二十五批：設定本體只回 ListView——Scaffold 殼由 SettingsScreen（直接
    // 導向用）或首頁頭像面板 bottom sheet 提供（人類指示整合）。
    return ListView(
      children: [
          // 批次 III-b：Profile 區（依人類注記參考圖；頭像＋ID＋更換頭像）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                // 「頭像移除 → 當下就消失」（人類回饋 2026-11-07）：根因＝
                // Flutter FutureBuilder 在 future 變 null 時僅把 snapshot 切成
                // ConnectionState.none，**data 保留**（官方 AsyncSnapshot.inState
                // 行為）→ snap.hasData 恆真、舊頭像停留；重開 App 才正常。改為
                // 直接以 State 的 `_profileAvatar` 渲染（`_removeAvatar`／
                // `_loadProfile` 的 setState 即時刷新；資料＝官方 SDK）。
                if (_profileAvatar != null)
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: NetworkImage(
                          _profileAvatar!.$1.toString(),
                          headers: _profileAvatar!.$2
                              ? <String, String>{
                                  'authorization':
                                      'Bearer ${widget.client.accessToken}',
                                }
                              : null,
                        ),
                      ),
                      _avatarCameraBadge(), // 共用徽章（下方抽出）。
                    ],
                  )
                else
                  Stack(
                    children: [
                      // 第 6 點根因：沒有頭像（或抓取失敗）時走 fallback；
                      // fallback 一樣提供相機徽章（點擊即 `_showAvatarActions`）。
                      // 第二十五批（人類指示「沒有頭像才用名稱第一個字母」）：
                      // fallback＝顯示名稱／userID 首字（無資料 → '?'）。
                      CircleAvatar(
                        radius: 28,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          _initialForFallback(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _avatarCameraBadge(),
                    ],
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 批次第 3 點：顯示自訂名稱（顯示名稱），無則顯示 userID。
                      InkWell(
                        onTap: () => unawaited(_changeDisplayName()),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profileDisplayName != null &&
                                      _profileDisplayName!.isNotEmpty
                                  ? _profileDisplayName!
                                  : '個人名稱（未設定）', // 文案草案
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.client.userID ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                section.title,
                // 第二十二批：分區標題＝token 次要色（樣式草案，待定稿）。
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: kTextSecondary),
              ),
            ),
            for (final entry in section.entries)
              ListTile(
                leading: Icon(entry.icon),
                title: Text(entry.label),
                onTap: entry.onTap,
              ),
          ],
      ],
    );
  }

  /// 第二十五批：無頭像 fallback 的首字（顯示名稱 → userID 略過 '@' → '?'）。
  String _initialForFallback() {
    final name = _profileDisplayName;
    if (name != null && name.isNotEmpty && name.runes.isNotEmpty) {
      return String.fromCharCode(name.runes.first);
    }
    final id = widget.client.userID ?? '';
    final runes = id.runes.skip(1); // 略過 '@'
    if (runes.isEmpty) {
      return '?';
    }
    return String.fromCharCode(runes.first);
  }

  /// 批次 III-c：密碼輸入框（遮罩；僅當 server 要求 UIA 重認證時顯示）。
  Future<String?> _askPassword(String deviceName) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('請重新輸入密碼'), // 文案草案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('登出裝置「$deviceName」需要密碼確認（官方安全驗證）。'), // 文案草案
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密碼（本機，不儲存）'), // 文案草案
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('確認'), // 文案草案
          ),
        ],
      ),
    );
  }

  /// 批次 III-c：官方 UIA 密碼重認證（SDK `uiaRequestBackground`＋
  /// `onUiaRequest` waitForUser → `UiaRequest.completeStage`）。
  /// spec：type m.login.password ＋ identifier(m.id.user)＋password。
  /// 只處理密碼型 stage；SSO 等其他 stage 不支援（會失敗並顯示訊息）。
  Future<void> _deleteDeviceWithUia(Client client, String deviceId, String password) async {
    final sub = client.onUiaRequest.stream.listen((uia) async {
      if (uia.state != UiaRequestState.waitForUser) {
        return;
      }
      try {
        await uia.completeStage(
          AuthenticationData(
            type: AuthenticationTypes.password,
            session: uia.session,
            additionalFields: <String, Object?>{
              'identifier': <String, Object?>{
                'type': AuthenticationIdentifierTypes.userId,
                'user': client.userID ?? '',
              },
              'password': password,
            },
          ),
        );
      } catch (_) {
        // completeStage 失敗會由 uiaRequestBackground 以 fail 結束 → caller 顯示。
      }
    });
    try {
      await client.uiaRequestBackground<void>(
        (auth) => client.deleteDevice(deviceId, auth: auth),
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Suggestion #2「診斷功能」＋第二十五批合併：唯讀顯示 SDK 官方 client 狀態
  ///（帳號／homeserver／裝置 ID／登入狀態——原設定頁簡版）＋ 加密狀態
  ///（rooms_screen「驗證診斷」原樣搬入；SDK 官方欄位，不含任何金鑰內容）。
  /// 動作＝官方 `olmManager.uploadKeys`／`crossSigning.selfSign`（官方 API，
  /// 零自製協定）。
  Future<void> _showDiagnostics(Client client) async {
    if (client.userDeviceKeysLoading != null) {
      await client.userDeviceKeysLoading!
          .timeout(const Duration(seconds: 5))
          .catchError((_) {});
    }
    if (client.accountDataLoading != null) {
      await client.accountDataLoading!
          .timeout(const Duration(seconds: 5))
          .catchError((_) {});
    }
    // 第二十七批（人類拍板）：Rust 引擎本 session 初始化狀態（engine_init
    // 記錄；成功即清旗標 → 無旗標＝本 session 初始化成功）。唯讀記錄，
    // 不觸引擎、不涉任何金鑰內容。
    final rustEngineError = await AppSettings.get(kRustEngineErrorKey)
        .timeout(const Duration(seconds: 3))
        .catchError((_) => null as String?);
    final enc = client.encryption;
    final cs = enc?.crossSigning;
    final selfDevice = client.userDeviceKeys[client.userID]
        ?.deviceKeys[client.deviceID];
    final status = '帳號：${client.userID ?? '（未登入）'}\n' // 文案草案
        'Homeserver：${client.homeserver}\n'
        '裝置 ID：${client.deviceID ?? '（未知）'}\n'
        '登入狀態：${client.isLogged() ? '正常' : '未登入'}\n' // 文案草案
        '─── Rust 引擎（二十七批） ───\n' // 文案草案
        '初始化：${rustEngineError == null ? '成功（無失敗記錄）' : '失敗：$rustEngineError'}\n'
        '─── 加密狀態 ───\n' // 文案草案
        'encryption: ${enc != null}\n'
        'crossSigning.enabled: ${cs?.enabled}\n'
        'isSelfSigned: ${cs?.isSelfSigned}\n'
        'userDeviceKeys 載入: ${client.userDeviceKeys.isNotEmpty}\n'
        'self device 在快取: ${selfDevice != null}\n'
        'self device 已簽章鏈: ${selfDevice?.hasValidSignatureChain(verifiedByTheirMasterKey: true)}\n'
        'accountData master secret: ${client.accountData[EventTypes.CrossSigningMasterKey]?.content['encrypted'] is Map}\n'
        'accountData self_signing secret: ${client.accountData[EventTypes.CrossSigningSelfSigning]?.content['encrypted'] is Map}\n'
        'vodozemac: ${enc != null} (engine present)';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('診斷資訊'), // 文案草案
        content: SingleChildScrollView(child: Text(status)),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final ok = await enc?.olmManager.uploadKeys(
                  uploadDeviceKeys: true,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('上傳裝置金鑰：${ok == true ? "完成" : "失敗/進行中"}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('上傳失敗：$e')),
                  );
                }
              }
            },
            child: const Text('上傳裝置金鑰'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _selfSignWithRecoveryKey();
            },
            child: const Text('自我簽章（recovery key）'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  /// 以 recovery key（或密碼）做自我簽章。rooms_screen 原樣搬入（人類批准
  /// 2026-11-06 任務 5）：對應「上傳後已簽章鏈仍 false」——SDK 官方
  /// `CrossSigning.selfSign(keyOrPassphrase:)`（自動先按 recovery key 解；
  /// 失敗再按密碼解），本檔不寫任何演算法。
  Future<void> _selfSignWithRecoveryKey() async {
    final cs = widget.client.encryption?.crossSigning;
    final keyCache = widget.client.userDeviceKeys[widget.client.userID];
    if (cs == null || keyCache == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加密引擎或金鑰快取未就緒；請先讓 sync 跑完再試')),
        );
      }
      return;
    }
    if (!mounted) return;
    final input = await showDialog<String>(
      context: context,
      builder: (c) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('以 recovery key 自我簽章'), // 文案草案
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'recovery key 或密碼'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop(controller.text),
              child: const Text('簽章'),
            ),
          ],
        );
      },
    );
    if (input == null || !mounted) return;
    try {
      await cs.selfSign(keyOrPassphrase: input);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自我簽章完成；重開驗證診斷確認「已簽章鏈」為 true')), // 文案草案
        );
      }
    } catch (e) {
      // 失敗原因透明顯示（Secrets not cached / Master pubkey 不符等）。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自我簽章失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 第二十五批（人類指示「驗證裝置移入設定進階區」）：官方裝置驗證——
  /// rooms_screen `_startDeviceVerification` 原樣搬入：等 SDK 金鑰/帳號資料
  /// 載入 → 列出本使用者**其他裝置**的官方 DeviceKeys → 選擇 → 官方
  /// `DeviceKeys.startVerification`（SDK 狀態機）→ 官方 SAS 對話框
  ///（`showDeviceVerificationDialog`）。本檔不接觸任何加密演算。
  Future<void> _startDeviceVerification() async {
    final client = widget.client;
    if (client.encryption == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加密引擎未啟用（vodozemac 未載入）')),
        );
      }
      return;
    }
    if (client.userDeviceKeysLoading != null) {
      await client.userDeviceKeysLoading!
          .timeout(const Duration(seconds: 8))
          .catchError((_) {});
    }
    if (client.accountDataLoading != null) {
      await client.accountDataLoading!
          .timeout(const Duration(seconds: 8))
          .catchError((_) {});
    }

    final self = client.userDeviceKeys[client.userID];
    final candidates = (self?.deviceKeys ?? <String, DeviceKeys>{})
        .entries
        .where((e) => e.key != client.deviceID)
        .toList();

    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('找不到其他裝置；請確認 Element 已登入同一帳號並完成同步'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final chosen = await showDialog<DeviceKeys>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('選擇要驗證的裝置'),
        children: [
          for (final e in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(e.value),
              child: Text(
                '${e.value.deviceDisplayName ?? e.key} (${e.key})',
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    KeyVerification request;
    try {
      request = await chosen.startVerification();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('啟動驗證失敗：$e')),
        );
      }
      return;
    }
    if (!mounted) return;
    // 跨畫面互斥守門（官方對話框重入；邀請監聽同讀 device_verification_dialog
    // 共用旗標）。
    if (deviceVerificationDialogShowing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已有裝置驗證對話框進行中')), // 文案草案
      );
      return;
    }
    await showDeviceVerificationDialog(context, request);
  }

  List<({String title, List<_SettingsEntry> entries})> _sections() {
    final client = widget.client;
    _SettingsEntry deviceMgmt() => _SettingsEntry(
          icon: Icons.devices,
          label: '裝置管理', // 1.14（遠端登出裝置）→「帳號」（人類注記「Account」）
          onTap: () => _open(
            DeviceManagementScreen(
              loadDevices: () async {
                // 官方 API：getDevices() 回傳可為 null → 以空清單保底。
                final devices = await client.getDevices() ?? const <Device>[];
                return [
                  for (final d in devices)
                    DeviceView(
                      id: d.deviceId,
                      displayName: d.displayName ?? d.deviceId,
                      lastSeen: (d.lastSeenTs != null)
                          ? DateTime.fromMillisecondsSinceEpoch(d.lastSeenTs!)
                              .toLocal()
                              .toString()
                          : '',
                      // 批次 III-c：SDK `client.deviceID` → 本裝置徽章。
                      isCurrent: d.deviceId == client.deviceID,
                    ),
                ];
              },
              // 批次 III-c：遠端登出＋官方 UIA（Synapse 要求密碼重認證時，
              // 提示輸入密碼後以 `uiaRequestBackground` 重試；無自製協定邏輯，
              // 密碼只隨官方 UIA 流程送 homeserver、不落地儲存）。
              onDeleteDevice: (dev) async {
                try {
                  await client.deleteDevice(dev.id);
                  return;
                } on MatrixException catch (e) {
                  if (!e.requireAdditionalAuthentication) {
                    // 其它錯誤（403／網路等）直接回拋，UI 顯示原因。
                    rethrow;
                  }
                }
                final password = await _askPassword(dev.displayName);
                if (password == null) {
                  throw StateError('已取消'); // 文案草案
                }
                await _deleteDeviceWithUia(client, dev.id, password);
              },
              // 批次 III-c：官方 updateDevice PUT 重新命名裝置。
              onRenameDevice: (dev, newName) async {
                await client.updateDevice(dev.id, displayName: newName);
              },
            ),
          ),
        );
    return [
      (
        title: '個人資訊',
        entries: [
          deviceMgmt(),
          _SettingsEntry(
            icon: Icons.key,
            label: '金鑰備份診斷與還原', // 文案草案（解密案修法 #1，人類批准 2026-11-13）
            onTap: () {
              if (client.encryption == null) {
                // 與 selfSign 相同的引擎就緒守衛（官方狀態欄位，不含金鑰內容）。
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('加密引擎未就緒；請先讓 sync 跑完再試'), // 文案草案
                  ),
                );
                return;
              }
              _open(
                BackupRestoreScreen(
                  deps: BackupRestoreDeps.fromClient(client),
                ),
              );
            },
          ),
          _SettingsEntry(
            icon: Icons.phone_iphone,
            label: '多裝置登入', // 1.13
            onTap: () => _open(const MultiDeviceLoginScreen()),
          ),
          _SettingsEntry(
            icon: Icons.device_hub,
            label: '裝置清單', // 1.5（SDK 官方裝置中繼資料）
            onTap: () => _open(
              DeviceListingScreen(
                // 官方 API：getDevices() 回傳可為 null → 以空清單保底。
                deviceSource: () async =>
                    (await client.getDevices()) ?? <Device>[],
              ),
            ),
          ),
        ],
      ),
      // Suggestion #2「驗證裝置、診斷功能放在進階設定選項」（人類回饋
      // 2026-11-03）＋第二十五批（人類指示「驗證裝置、診斷功能移入設定中的
      // 進階區域」；無作用 skeleton 裝置驗證＝官方沒有的東西，依指示移除）：
      // 進階區＝官方 SAS 裝置驗證（rooms_screen 原樣搬入）＋合併診斷（帳號
      // ＋加密狀態、含官方動作）。
      (
        title: '進階',
        entries: [
          _SettingsEntry(
            icon: Icons.verified_user,
            label: '驗證裝置', // 官方 SAS 流程（SDK 狀態機；UI 駕駛）
            onTap: _startDeviceVerification,
          ),
          _SettingsEntry(
            icon: Icons.bug_report_outlined,
            label: '診斷資訊', // 合併診斷（唯讀；同步 XX 等 SDK 官方欄位）
            onTap: () => _showDiagnostics(client),
          ),
        ],
      ),
      (
        title: '一般',
        entries: [
          _SettingsEntry(
            icon: Icons.palette_outlined,
            label: '外觀設定（主題／字型／文字大小／貼圖匯入）', // 批次 C/I；人類注記 Themes+Fonts
            onTap: () => _open(const AppearanceScreen()),
          ),
          _SettingsEntry(
            icon: Icons.search,
            label: '訊息搜尋', // 2.7
            onTap: () => _open(const MessageSearchScreen()),
          ),
          _SettingsEntry(
            icon: Icons.block,
            label: '封鎖名單', // 第十八批（結構參考 new_ref/settings/blocked_account；人類指示「介面根據 LINE」）
            onTap: () => _open(BlockedUsersScreen(client: client)),
          ),
          _SettingsEntry(
            icon: Icons.notifications_active,
            label: '推播通知權限', // 1.10 / 2.5（人類注記 Notifications）
            onTap: () => _open(const PushPermissionScreen()),
          ),
          _SettingsEntry(
            icon: Icons.notifications_outlined,
            label: '通知設定（顯示／內容）', // 批次十二②（人類指示 all；結構參考 new_ref/settings/notification）
            onTap: () => _open(const NotificationSettingsScreen()),
          ),
          _SettingsEntry(
            icon: Icons.emergency_outlined,
            label: '緊急聯絡人', // 第三十五批 #6（本機儲存；緊急求助流程用）
            onTap: () => _open(EmergencyContactsScreen(client: client)),
          ),
          _SettingsEntry(
            icon: Icons.file_download_outlined,
            label: '資料匯出', // 2.9
            onTap: () => _open(const DataExportScreen()),
          ),
          _SettingsEntry(
            icon: Icons.person_off,
            label: '帳號停用', // 2.10
            onTap: () => _open(const AccountDisableScreen()),
          ),
        ],
      ),
      (
        title: 'App info',
        entries: [
          _SettingsEntry(
            icon: Icons.code,
            label: '原始碼（GitHub）', // 人類注記；URL 待 Phase 0 建立後提供
            onTap: null, // 尚未有 repo URL（Phase 0 待辦）→ 暫不可點
          ),
          _SettingsEntry(
            icon: Icons.logout,
            label: '登出',
            onTap: _onLogout,
          ),
        ],
      ),
    ];
  }
}

class _SettingsEntry {
  const _SettingsEntry({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}
