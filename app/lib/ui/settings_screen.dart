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

import 'package:url_launcher/url_launcher.dart'; // 第一百零八批：原始碼連結

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'chat_screen.dart' show clearLoadedMessagesCache; // 第六十七批：登出清訊息快取
import '../scheduled_messages.dart'; // 第八十一批：登出清 server 預約
import '../missing_key_repair.dart' show clearDecryptedEventCache; // 第六十七批：登出清解密快取
import 'account_disable_screen.dart';
import 'appearance_screen.dart';
import 'blocked_users_screen.dart'; // 第十八批
import 'emergency_contacts_screen.dart'; // 第三十五批 #6
import 'data_export_screen.dart';
// 頭像移除旗標持久化（kv；0.7 儲存方案）。
import '../app_settings.dart';
import '../crypto_recovery.dart'; // 第三十八批：recovery 錯誤分流與金鑰就緒等待
import '../sticker_pack_store.dart'; // 第三十九批：貼圖庫房間（診斷資訊顯示同步狀態）
import 'hidden_rooms_screen.dart'; // 第四十二批：隱藏的聊天室（可還原）
import '../engine_init.dart' show kRustEngineErrorKey; // 第二十七批：Rust 引擎狀態旗標
import '../push/push_runtime.dart';
import '../push/fcm_runtime.dart'; // 第五十一批：FCM pusher 註冊狀態（診斷資訊）
import '../push/push_constants.dart'; // 第五十二批：FCM 閘道 URL（診斷資訊）
import '../perf_metrics.dart'; // 第五十七批：效能量測記錄（診斷資訊）
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（語言切換）
import '../media_cache.dart'; // 第五十七批：離線快取管理（用量／上限／清除）
import 'design_tokens.dart'; // 第二十二批：分區標題 token 色
import '../save_location.dart'; // 2026-11-21：另存資料夾設定
import 'compound_icon.dart'; // 2026-11-20：Compound icon（人類指示全換）
// 兩個裝置畫面皆定義同名 DeviceView；settings 只用 device_management 的型別。
import 'device_listing_screen.dart' hide DeviceView;
import 'device_management_screen.dart';
import 'device_verification_dialog.dart'; // 第二十五批：官方 SAS 對話框（共用）
import 'backup_restore_screen.dart';
import 'message_search_screen.dart';
import 'multi_device_login_screen.dart';
import 'notification_settings_screen.dart';
import 'scheduled_messages_screen.dart';
import 'notes_screen.dart';
import 'album_screen.dart'; // 第八十八批：相簿
import 'a11y_services_screen.dart'; // 第八十六批：無障礙服務 // 第八十六批：筆記 // 第七十九批：預約訊息管理 // 批次十二②
import 'push_permission_screen.dart';
import 'profile_screen.dart'; // 第四十七批：個人資料頁（獨立頁）
import '../read_receipt_prefs.dart'; // 第六十九批：無痕預覽／稍後已讀

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
      // 第七十五批（68d）：標題 LINE 綠膠囊。
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: kLineGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            S.t('設定'),
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
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

  Future<void> _onLogout() async {
    if (_loggingOut) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('登出')), // 文案待人類定稿
        content: Text(S.t('確定要登出此裝置？')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.t('登出')),
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
    // 第八十一批（#4 server 隔離）：登出清掉 server account data 中的
    // 預約訊息（空清單），避免換帳號後舊預約殘留或误送。
    try {
      final uid = widget.client.userID;
      if (uid != null) {
        await widget.client.setAccountData(
          uid,
          kScheduledAccountDataType,
          <String, Object?>{'messages': <Object?>[]},
        );
      }
      await saveScheduledMessages(const <ScheduledMessage>[]);
    } catch (_) {}
    try {
      await (widget.onLogout ?? (c) => c.logout())(widget.client);
      // 第六十七批：登出清**所有已載入快取**（無 TTL 也須在帳號切換時清，
      // 避免跨帳號殘留；平時不按時間清理＝嚴禁 LINE 式限時存取）。
      clearLoadedMessagesCache();
      clearDecryptedEventCache();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('登出失敗：')}$e')),
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

  /// 第四十二批（LINE 版位）：設定頁頂端搜尋列（LINE：Search settings, help articles）。
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSections = _sections();
    // 搜尋過濾（LINE 版位：輸入關鍵字只顯示符合的設定項）。
    final q = _searchQuery.trim().toLowerCase();
    final sections = q.isEmpty
        ? allSections
        : [
            for (final sec in allSections)
              if (sec.entries.any(
                (e) => e.label.toLowerCase().contains(q),
              ))
                (
                  title: sec.title,
                  entries: sec.entries
                      .where((e) => e.label.toLowerCase().contains(q))
                      .toList(),
                ),
          ];
    // 第二十五批：設定本體只回 ListView——Scaffold 殼由 SettingsScreen（直接
    // 導向用）或首頁頭像面板 bottom sheet 提供（人類指示整合）。
    return ListView(
      children: [
          // 第四十二批（LINE 版位）：頂端搜尋列。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: S.t('搜尋設定'), // 文案草案（LINE：Search settings）
                prefixIcon: CompoundIcon(CompoundIcons.search, size: 22, color: Theme.of(context).colorScheme.onSurface),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? kLineBar
                    : kSearchFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ),
          // 第四十七批（人類續作清單「個人資料頁抽出為獨立頁」）：設定頁的
          // Profile 區改為**一列**（頭像縮圖＋名稱＋chevron），點入獨立頁
          // `ProfileScreen`（第四十七批新增）。設定本體因此不再自己管理頭像
          // 狀態（頭像／顯示名稱的邏輯全部在 ProfileScreen）。
          ListTile(
            leading: _profileAvatar != null
                ? CircleAvatar(
                    radius: 22,
                    backgroundImage: NetworkImage(
                      _profileAvatar!.$1.toString(),
                      headers: _profileAvatar!.$2
                          ? <String, String>{
                              'authorization':
                                  'Bearer ${widget.client.accessToken}',
                            }
                          : null,
                    ),
                  )
                : CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      _initialForFallback(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
            title: Text(
              (_profileDisplayName != null && _profileDisplayName!.isNotEmpty)
                  ? _profileDisplayName!
                  : '個人名稱（未設定）', // 文案草案
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              widget.client.userID ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: CompoundIcon(CompoundIcons.chevronRight, size: 22, color: Theme.of(context).colorScheme.onSurface),
            onTap: () => _open(ProfileScreen(client: widget.client)),
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
                leading: CompoundIcon(
                  entry.icon,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(entry.label),
                onTap: entry.onTap ??
                    (entry.url == null
                        ? null
                        : () => unawaited(launchUrl(
                            entry.url!,
                            mode: LaunchMode.externalApplication,
                          ))),
                // 第四十二批（LINE 版位）：可點入子頁的設定列右側加 chevron。
                trailing: (entry.onTap == null && entry.url == null)
                    ? null
                    : CompoundIcon(CompoundIcons.chevronRight, size: 22, color: Theme.of(context).colorScheme.onSurface),
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
        title: Text(S.t('請重新輸入密碼')), // 文案草案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${S.t('登出裝置「')}$deviceName${S.t('」需要密碼確認（官方安全驗證）。')}'), // 文案草案
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
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(S.t('確認')), // 文案草案
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
  /// 貼圖庫房間的診斷資訊（唯讀）：房間 id、已同步的 pack 數、每個 pack 的
  /// `m.room.image_pack` 狀態事件是否已存在於伺服器。
  Future<String> _stickerLibraryDiagnostic(Client client) async {
    try {
      final roomId = await AppSettings.get(StickerPackStore.kPackRoomIdKey);
      if (roomId == null || roomId.isEmpty) {
        return '尚未建立貼圖庫房間（外觀設定 → 貼圖 → 同步貼圖庫）';
      }
      final metas = await StickerPackStore.loadPackMetas();
      final room = client.getRoomById(roomId);
      final buffer = StringBuffer('房間：$roomId\n');
      buffer.writeln('本機貼圖包：${metas.length} 個');
      for (final meta in metas) {
        final id = meta['id'];
        if (id is! String) continue;
        var written = false;
        try {
          written = room?.getState(StickerPackStore.kPackStateType, id) != null;
        } catch (_) {
          written = false;
        }
        buffer.writeln('  $id → ${written ? '已寫入房間' : '尚未寫入'}');
      }
      return buffer.toString().trimRight();
    } catch (e) {
      return '（讀取失敗：$e）';
    }
  }

  /// 第五十七批：語言選擇（bottom sheet；選完即時套用並持久化）。
  Future<void> _showLanguagePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CompoundIcon(CompoundIcons.translate, size: 24, color: Theme.of(context).colorScheme.onSurface),
                title: Text(S.t('語言')),
              ),
              // ⚠️ 用 ListTile＋勾號而非 RadioListTile：Flutter 3.32+ 已棄用
              // `RadioListTile.groupValue`／`onChanged`（CI analyze 實證為
              // deprecated_member_use → analyze 直接失敗）→ 避免使用新舊 API。
              for (final option in const [
                (AppLocale.zhTW, '繁體中文（台灣）'),
                (AppLocale.en, 'English'),
              ])
                ListTile(
                  title: Text(option.$2),
                  trailing: currentAppLocale == option.$1
                      ? CompoundIcon(CompoundIcons.check, size: 24, color: Theme.of(context).colorScheme.onSurface)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(saveAppLocale(option.$1));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 第五十七批：離線快取管理（用量／上限／立即清除）。
  ///
  /// ⚠️ 方案 A（媒體快取，**明文**、未加密）→ 清除按鈕是隱私相關的唯一出口；
  /// 已於 `known_problems.md` 記錄（待寫入 `PRIVACY.md` 草稿備註）。
  Future<void> _showMediaCacheSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CompoundIcon(CompoundIcons.offline, size: 24, color: Theme.of(context).colorScheme.onSurface),
                title: Text(S.t('離線快取')),
              ),
              FutureBuilder<MediaCacheStats>(
                future: mediaCache().then((c) => c.stats),
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(stats?.format() ?? '（讀取中…）'),
                      ),
                      for (final mb in const [128, 256, 512, 1024])
                        ListTile(
                          dense: true,
                          title: Text('${S.t('上限 ')}$mb MB'),
                          trailing: (stats != null &&
                                  (stats.maxBytes ~/ (1024 * 1024)) == mb)
                              ? CompoundIcon(CompoundIcons.check, size: 24, color: Theme.of(context).colorScheme.onSurface)
                              : null,
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await saveMediaCacheMaxBytes(mb * 1024 * 1024);
                          },
                        ),
                      ListTile(
                        leading: CompoundIcon(CompoundIcons.delete, size: 24, color: Theme.of(context).colorScheme.onSurface),
                        title: Text(S.t('立即清除快取')),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          // 先取得 messenger（**在 await 之前**）→ 避免跨 async gap
                          // 使用 BuildContext（CI analyze：use_build_context_synchronously）。
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await (await mediaCache()).clear();
                          } catch (_) {
                            // 忽略（清除失敗不崩潰）。
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text(S.t('已清除離線快取'))),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 第五十七批：效能量測（記憶體內；設定 → 進階 → 診斷資訊 可看）。
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
        'vodozemac: ${enc != null} (engine present)\n'
        '─── 推播通道（五十一批） ───\n' // 文案草案
        '目前通道：${RingPushRuntime.channelStatus.label}\n'
        'FCM 可用：${FcmRuntime.isAvailable}\n'
        'FCM 錯誤：${FcmRuntime.lastError ?? '（無）'}\n'
        'FCM 閘道：$kFcmPusherUrl\n'
        'FCM pusher：${FcmRuntime.pusherRegistered ? '已註冊' : '未註冊'}'
        '${FcmRuntime.pusherError == null ? '' : '（${FcmRuntime.pusherError}）'}\n'
        '─── 效能量測（五十七批・僅本行程記憶體） ───\n' // 文案草案
        '${PerfLog.dump()}\n'
        '─── 貼圖庫（藍圖 3.11） ───\n'
        '${await _stickerLibraryDiagnostic(client)}';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('診斷資訊')), // 文案草案
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
                    SnackBar(content: Text('${S.t('上傳裝置金鑰：')}${ok == true ? "完成" : "失敗/進行中"}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${S.t('上傳失敗：')}$e')),
                  );
                }
              }
            },
            child: Text(S.t('上傳裝置金鑰')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _selfSignWithRecoveryKey();
            },
            child: Text(S.t('自我簽章（recovery key）')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.t('關閉')),
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
    if (cs == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('加密引擎未就緒；請先讓 sync 跑完再試'))),
        );
      }
      return;
    }
    // 第三十八批（實機根因）：SDK 自我簽章需要**本裝置的 device key**；
    // 未回填時會丟 `Master or user keys not found`（與 key 正確與否無關）。
    if (!hasOwnDeviceKeys(widget.client)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('本裝置金鑰尚未同步完成；請稍候再試'))),
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
          title: Text(S.t('以 recovery key 自我簽章')), // 文案草案
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(hintText: S.t('recovery key 或密碼')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(null),
              child: Text(S.t('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop(controller.text),
              child: Text(S.t('簽章')),
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
          SnackBar(content: Text(S.t('自我簽章完成；重開驗證診斷確認「已簽章鏈」為 true'))), // 文案草案
        );
      }
    } catch (e) {
      // 失敗原因透明顯示（Secrets not cached / Master pubkey 不符等）；
      // 第三十八批：錯誤分流（可重試的時序問題 ≠ key 不正確）。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('自我簽章失敗：')}${describeRecoveryError(e)}')), // 文案草案
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
          SnackBar(content: Text(S.t('加密引擎未啟用（vodozemac 未載入）'))),
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
          SnackBar(
            content: Text(S.t('找不到其他裝置；請確認 Element 已登入同一帳號並完成同步')),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final chosen = await showDialog<DeviceKeys>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.t('選擇要驗證的裝置')),
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
          SnackBar(content: Text('${S.t('啟動驗證失敗：')}$e')),
        );
      }
      return;
    }
    if (!mounted) return;
    // 跨畫面互斥守門（官方對話框重入；邀請監聽同讀 device_verification_dialog
    // 共用旗標）。
    if (deviceVerificationDialogShowing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('已有裝置驗證對話框進行中'))), // 文案草案
      );
      return;
    }
    await showDeviceVerificationDialog(context, request);
  }

  /// 第六十九批：已讀收據偏好 sheet（無痕預覽／稍後標為已讀）。
  Future<void> _openReadReceiptSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(S.t('無痕預覽')),
                subtitle: Text(S.t('開：永遠不自動送已讀（手動「標為已讀」仍會送）')),
                value: ringIncognitoRead.value,
                onChanged: (v) async {
                  // 互斥：無痕預覽＝永遠不自動送；稍後已讀＝延遲後送。
                  // 兩者同時開會讓「稍後」看起來沒作用 → 開其一即關另一。
                  if (v) await setMarkReadDelaySec(0);
                  await setIncognitoRead(v);
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                title: Text(S.t('稍後標為已讀')),
                subtitle: Text(S.t('開：停留 30 秒後自動送已讀；離開聊天室則取消')),
                value: ringMarkReadDelaySec.value > 0,
                onChanged: (v) async {
                  // 互斥：稍後已讀＝延遲 30 秒自動送；開則關掉無痕。
                  if (v) await setIncognitoRead(false);
                  await setMarkReadDelaySec(v ? 30 : 0);
                  setSheetState(() {});
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  ringIncognitoRead.value
                      ? S.t('目前：無痕預覽（完全不自動送已讀）')
                      : ringMarkReadDelaySec.value > 0
                          ? S.t('目前：稍後標為已讀（停留 30 秒後自動送）')
                          : S.t('目前：進入聊天室置底即送出已讀（預設）'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  S.t('兩項預設關閉；手動「標為已讀」仍會立即送出。'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2026-11-21：設定另存資料夾（SAF）。首次選完後所有下載直接寫入該處。
  Future<void> _configureSaveLocation() async {
    final current = await SaveLocation.folderUri;
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('下載位置')),
        content: Text(
          current == null
              ? S.t('尚未設定；下載前會先要求選擇資料夾。')
              : '${S.t('目前的下載位置已設定。')}\n${S.t('下載時不再詢問，直接存入此資料夾。')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(S.t('取消')),
          ),
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: Text(S.t('清除設定')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'pick'),
            child: Text(S.t('選擇資料夾')),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'clear') {
      await SaveLocation.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('已清除下載位置'))),
        );
      }
      return;
    }
    final uri = await SaveLocation.pickFolder();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null ? S.t('未選擇資料夾') : S.t('已設定下載位置'),
          ),
        ),
      );
    }
  }

  List<({String title, List<_SettingsEntry> entries})> _sections() {
    final client = widget.client;
    _SettingsEntry deviceMgmt() => _SettingsEntry(
          icon: CompoundIcons.devices,
          label: S.t('裝置管理'), // 1.14（遠端登出裝置）→「帳號」（人類注記「Account」）
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
      // 第六十九批（F-2/P2）：已讀收據偏好（無痕預覽／稍後標為已讀），
      // 皆為**預設關閉**的 opt-in，不影響一般使用者。
      (
        title: S.t('已讀與訊息'),
        entries: [
          _SettingsEntry(
            icon: CompoundIcons.calendar,
            label: S.t('預約訊息'),
            onTap: () => _open(ScheduledMessagesScreen(client: widget.client)),
          ),
          _SettingsEntry(
            icon: CompoundIcons.document,
            label: S.t('筆記'),
            onTap: () => _open(const NotesScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.image,
            label: S.t('相簿'),
            onTap: () => _open(const AlbumScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.verified,
            label: S.t('無障礙服務'),
            onTap: () => _open(const A11yServicesScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.visibilityOff,
            label: S.t('無痕預覽'),
            onTap: _openReadReceiptSettings,
          ),
          _SettingsEntry(
            icon: CompoundIcons.time,
            label: S.t('稍後標為已讀'),
            onTap: _openReadReceiptSettings,
          ),
        ],
      ),
      (
        title: S.t('個人資訊'),
        entries: [
          deviceMgmt(),
          _SettingsEntry(
            icon: CompoundIcons.key,
            label: S.t('金鑰備份診斷與還原'), // 文案草案（解密案修法 #1，人類批准 2026-11-13）
            onTap: () {
              if (client.encryption == null) {
                // 與 selfSign 相同的引擎就緒守衛（官方狀態欄位，不含金鑰內容）。
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(S.t('加密引擎未就緒；請先讓 sync 跑完再試')), // 文案草案
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
            icon: CompoundIcons.devicePasskey,
            label: S.t('多裝置登入'), // 1.13
            onTap: () => _open(const MultiDeviceLoginScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.computer,
            label: S.t('裝置清單'), // 1.5（SDK 官方裝置中繼資料）
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
          // 第四十二批（人類：外加隱藏／封鎖名單應顯示並可還原；版位參考
          // LINE 設定頁的 icon＋文字＋chevron 版位與分類）。
          title: S.t('封鎖與隱私'),
          entries: [
            _SettingsEntry(
              icon: CompoundIcons.block,
              label: S.t('封鎖名單'),
              onTap: () => _open(BlockedUsersScreen(client: client)),
            ),
            _SettingsEntry(
              icon: CompoundIcons.visibilityOff,
              label: S.t('隱藏的聊天室'),
              onTap: () => _open(HiddenRoomsScreen(client: client)),
            ),
          ],
        ),
      (
        title: S.t('進階'),
        entries: [
          _SettingsEntry(
            icon: CompoundIcons.verified,
            label: S.t('驗證裝置'), // 官方 SAS 流程（SDK 狀態機；UI 駕駛）
            onTap: _startDeviceVerification,
          ),
          _SettingsEntry(
            icon: CompoundIcons.bug,
            label: S.t('診斷資訊'), // 合併診斷（唯讀；同步 XX 等 SDK 官方欄位）
            onTap: () => _showDiagnostics(client),
          ),
        ],
      ),
      (
        title: S.t('一般'),
        entries: [
          _SettingsEntry(
            icon: CompoundIcons.theme,
            label: S.t('外觀設定（主題／字型／文字大小／貼圖匯入）'), // 批次 C/I；人類注記 Themes+Fonts
            onTap: () => _open(AppearanceScreen(client: client)),
          ),
          _SettingsEntry(
            icon: CompoundIcons.search,
            label: S.t('訊息搜尋'), // 2.7
            onTap: () => _open(const MessageSearchScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.notifications,
            label: S.t('推播通知權限'), // 1.10 / 2.5（人類注記 Notifications）
            onTap: () => _open(const PushPermissionScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.notificationsOff,
            label: S.t('通知設定（顯示／內容）'), // 批次十二②（人類指示 all；結構參考 new_ref/settings/notification）
            onTap: () => _open(NotificationSettingsScreen(client: widget.client)),
          ),
          _SettingsEntry(
            icon: CompoundIcons.warning,
            label: S.t('緊急聯絡人'), // 第三十五批 #6（本機儲存；緊急求助流程用）
            onTap: () => _open(EmergencyContactsScreen(client: client)),
          ),
          _SettingsEntry(
            icon: CompoundIcons.download,
            label: S.t('資料匯出'), // 2.9
            onTap: () => _open(const DataExportScreen()),
          ),
          _SettingsEntry(
            icon: CompoundIcons.folder,
            label: S.t('下載位置'), // 2026-11-21：首次選資料夾，之後一律存此
            onTap: _configureSaveLocation,
          ),
          _SettingsEntry(
            icon: CompoundIcons.leave,
            label: S.t('帳號停用'), // 2.10
            onTap: () => _open(const AccountDisableScreen()),
          ),
          // 第五十七批：語言切換（多語言字串層；**零新依賴**；切換即時生效）。
          _SettingsEntry(
            icon: CompoundIcons.translate,
            label: S.t('語言'),
            onTap: _showLanguagePicker,
          ),
          // 第五十七批：離線快取管理（媒體快取・方案 A：用量／上限／清除）。
          _SettingsEntry(
            icon: CompoundIcons.offline,
            label: S.t('離線快取'),
            onTap: _showMediaCacheSheet,
          ),
        ],
      ),
      (
        title: 'App info',
        entries: [
          _SettingsEntry(
            icon: CompoundIcons.code,
            label: S.t('原始碼（GitHub）'),
            // 第一百零八批（人類提供）：公開 repo 網址，點了開外部瀏覽器。
            url: Uri.parse('https://github.com/itsxiaobai/homing-matrix-client'),
          ),
          _SettingsEntry(
            icon: CompoundIcons.signOut,
            label: S.t('登出'),
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
    this.url,
  });

  final String icon; // Compound icon 名稱（CompoundIcons.*）
  final String label;
  final VoidCallback? onTap;

  /// 第一百零八批：有 url 時由 ListTile 直接開外部瀏覽器。
  final Uri? url;
}
