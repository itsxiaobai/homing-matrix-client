// 第四十七批（人類續作清單：「個人資料頁抽出為獨立頁」）——個人資料頁。
//
// 版位參考 LINE（`LINE_ref/new_ref/settings/`）：設定裡的「個人資料」列
// 點入後是一個**獨立頁**，頁內放頭像（大圖）、顯示名稱、Matrix ID 與
// 相關動作。本頁只做**自己的**個人資料（不對應 LINE 的商業化功能）。
//
// 資料來源全部為 **Matrix 官方 API**：
// - `Client.fetchOwnProfile()` → 顯示名稱／頭像 URL
// - `Client.setAvatar(MatrixFile?)` → 更換／移除頭像
// - `Client.setProfileField(...)` → 設定顯示名稱
// - `Client.database.storeUserProfile(...)` → 使 profile 快取失效
//
// ⚠️ 頭像移除旗標（`AppSettings.ownAvatarRemovedFlag`）：Synapse 的 profile
// 快取在 `setAvatar(null)` 後可能仍回舊 avatar_url；旗標期間 UI 恆不畫舊
// 頭像，唯一解除時機＝**成功設定新頭像**。此旗標與首頁頭像共用同一 key。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import 'design_tokens.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化

/// 個人資料頁（獨立頁；由設定頁的「個人資料」列進入）。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.client});

  final Client client;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// 自己的頭像縮圖（官方 fetchOwnProfile→getThumbnailUri＋認證媒體）。
  (Uri, bool)? _avatar;

  /// 顯示名稱（官方 profile.displayName）；null＝未設定。
  String? _displayName;

  /// 頭像移除旗標（持久化於 kv；見檔頭說明）。
  bool _avatarRemoved = false;

  static const String _kAvatarRemovedFlag = AppSettings.ownAvatarRemovedFlag;

  @override
  void initState() {
    super.initState();
    // 順序保證：旗標**先**就位，再抓 profile（否則舊頭像會先被畫上去）。
    unawaited(_initAvatarState());
  }

  Future<void> _initAvatarState() async {
    try {
      final v = await AppSettings.get(_kAvatarRemovedFlag);
      if (mounted && v != null && v.isNotEmpty) {
        setState(() => _avatarRemoved = true);
      }
    } on Object {
      // 無 DB 環境（測試）／讀取失敗：忽略。
    }
    if (mounted) unawaited(_loadProfile());
  }

  /// 官方 fetchOwnProfile → 取得 avatar 與 displayName。
  Future<void> _loadProfile() async {
    try {
      final profile = await widget.client.fetchOwnProfile();
      if (mounted) setState(() => _displayName = profile.displayName);
      final url = profile.avatarUrl;
      if (url == null) {
        // server 已回「無頭像」→ 立即清空顯示（旗標**不**自動清除）。
        if (mounted) setState(() => _avatar = null);
        return;
      }
      if (_avatarRemoved) {
        if (mounted) setState(() => _avatar = null);
        return;
      }
      final thumb = await url.getThumbnailUri(widget.client, width: 192, height: 192);
      final auth = await widget.client.authenticatedMediaSupported();
      if (mounted) setState(() => _avatar = (thumb, auth));
    } on Object {
      // 失敗 → 保持現值（不臆造）。
    }
  }

  /// 更換頭像（相簿／相機；官方 `Client.setAvatar(MatrixFile)`）。
  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      await widget.client.setAvatar(MatrixFile(bytes: bytes, name: picked.name));
      if (!mounted) return;
      // 成功更換 → 解除移除旗標（讓 server 真值回到畫面）。
      _avatarRemoved = false;
      await AppSettings.remove(_kAvatarRemovedFlag).catchError((_) {});
      await _markOwnProfileOutdated();
      if (!mounted) return;
      unawaited(_loadProfile());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('頭像已更新'))), // 文案草案
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('更換頭像失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 移除頭像（官方 `Client.setAvatar(null)`；SDK 對 Synapse 相容送空字串）。
  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('移除頭像？')), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('移除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.client.setAvatar(null);
      if (!mounted) return;
      _avatarRemoved = true;
      await AppSettings.set(_kAvatarRemovedFlag, '1');
      await _markOwnProfileOutdated();
      if (!mounted) return;
      setState(() => _avatar = null);
      unawaited(_loadProfile());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('頭像已移除'))), // 文案草案
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('移除頭像失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 三選項（變更頭像／拍照／移除頭像）。
  Future<void> _showAvatarActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(AllIcons.photoLibraryOutlined),
              title: Text(S.t('變更頭像')), // 文案草案
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: Icon(AllIcons.photoCameraOutlined),
              title: Text(S.t('拍照')), // 文案草案
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (_avatar != null)
              ListTile(
                leading: Icon(AllIcons.personRemoveOutlined),
                title: Text(S.t('移除頭像')), // 文案草案
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'gallery':
        await _pickAvatar(ImageSource.gallery);
      case 'camera':
        await _pickAvatar(ImageSource.camera);
      case 'remove':
        await _removeAvatar();
    }
  }

  /// 使 server profile 快取失效（官方 `storeUserProfile`＋`outdated: true`）。
  Future<void> _markOwnProfileOutdated() async {
    try {
      await widget.client.database.storeUserProfile(
        widget.client.userID ?? '',
        CachedProfileInformation.fromProfile(
          ProfileInformation(displayname: null, avatarUrl: null),
          outdated: true,
          updated: DateTime.now(),
        ),
      );
    } catch (_) {
      // 快取失效失敗不阻擋主流程（下次 sync 仍會修正）。
    }
  }

  /// 設定顯示名稱（官方 `setProfileField`）。
  Future<void> _changeDisplayName() async {
    final controller = TextEditingController(text: _displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('設定顯示名稱')), // 文案草案
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '顯示名稱'), // 文案草案
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.t('儲存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName == _displayName || !mounted) return;
    try {
      await widget.client.setProfileField(
        widget.client.userID!,
        'displayname',
        {'displayname': newName.isEmpty ? null : newName},
      );
      if (!mounted) return;
      unawaited(_loadProfile());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('顯示名稱已更新'))), // 文案草案
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('更新顯示名稱失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 無頭像 fallback 的首字（顯示名稱 → userID 略過 '@' → '?'）。
  String _initial() {
    final name = _displayName;
    if (name != null && name.isNotEmpty && name.runes.isNotEmpty) {
      return String.fromCharCode(name.runes.first);
    }
    final id = widget.client.userID ?? '';
    final runes = id.runes.skip(1);
    if (runes.isEmpty) return '?';
    return String.fromCharCode(runes.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('個人資料'))), // 文案草案
      body: ListView(
        children: [
          // 大頭像（點擊 → 三選項）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Center(
              child: GestureDetector(
                onTap: () => unawaited(_showAvatarActions()),
                child: Semantics(
                  button: true,
                  label: S.t('更換頭像'),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      if (_avatar != null)
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: NetworkImage(
                            _avatar!.$1.toString(),
                            headers: _avatar!.$2
                                ? <String, String>{
                                    'authorization':
                                        'Bearer ${widget.client.accessToken}',
                                  }
                                : null,
                          ),
                        )
                      else
                        CircleAvatar(
                          radius: 48,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            _initial(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 32,
                            ),
                          ),
                        ),
                      // 相機徽章。
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AllIcons.photoCameraOutlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 顯示名稱（點擊修改）。
          ListTile(
            title: Text(S.t('顯示名稱')), // 文案草案
            subtitle: Text(
              (_displayName != null && _displayName!.isNotEmpty)
                  ? _displayName!
                  : '未設定', // 文案草案
            ),
            trailing: Icon(AllIcons.chevronRight),
            onTap: () => unawaited(_changeDisplayName()),
          ),
          ListTile(
            title: const Text('Matrix ID'),
            subtitle: Text(
              widget.client.userID ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(),
          // 頭像動作（明確入口，不必點頭像猜）。
          ListTile(
            leading: Icon(AllIcons.photoLibraryOutlined),
            title: Text(S.t('從相簿選擇')), // 文案草案
            onTap: () => unawaited(_pickAvatar(ImageSource.gallery)),
          ),
          ListTile(
            leading: Icon(AllIcons.photoCameraOutlined),
            title: Text(S.t('拍照')), // 文案草案
            onTap: () => unawaited(_pickAvatar(ImageSource.camera)),
          ),
          if (_avatar != null)
            ListTile(
              leading: Icon(AllIcons.personRemoveOutlined),
              title: Text(S.t('移除頭像')), // 文案草案
              onTap: () => unawaited(_removeAvatar()),
            ),
          const Divider(),
          // 說明小字（版本與授權；非功能項）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'Homing 是開源通訊軟體（AGPL-3.0-or-later）。\n'
              '你的頭像與顯示名稱儲存在你的 homeserver 上。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
