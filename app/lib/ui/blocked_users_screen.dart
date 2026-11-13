// 封鎖名單（第十八批；人類指示「介面根據 LINE 重新設計」——結構參考
// LINE_ref/new_ref/settings/blocked_account/Screenshot_20261104-174137_labeled.png
// 截圖語意：頁首計數＋說明文字＋清單列（頭像／名稱＋解除封鎖）。
// 骨架樣式（主題預設元件，無自訂配色／間距；文案草案待人類定稿）。
//
// 資料與操作零自製協定，全部官方 SDK API：
// - 清單＝`Client.ignoredUsers` getter（client.dart L3945，`m.ignored_user_list`）
// - 解除＝`Client.unignoreUser()`（同第十五批 contacts_screen 模式）
// - 名稱／頭像＝`Client.getProfileFromUserId()`（client.dart L1197；內部
//   `getUserProfile` 含官方 1 天快取）；縮圖走官方 `Uri.getThumbnailUri`
//   （uri_extension.dart L63）＋`authenticatedMediaSupported()` → Bearer
//   header（批次 I 於 rooms_screen 建立的官方認證媒體路徑）。查不到（離線 /
//   無此使用者 profile）→ 顯示 mxid＋首字頭像，不出錯。
//
// LINE 專屬項不投射（同 repo pattern）：Friends／Official accounts 分頁
// （Homing 僅有使用者清單）、Select all 多選（v0 逐列解除）、
// 「刪除後仍維持封鎖」的 LINE 特有語意（Matrix 语义：清單即封鎖事實）。
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key, required this.client});

  final Client client;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  // 官方 ignoredUsers 快照（讀取時即時取，無 db 依賴）。
  List<String> _users = const <String>[];
  // 名稱／頭像（官方 profile；查得即填，失敗顯示 mxid）。
  final Map<String, Profile> _profiles = <String, Profile>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _users = List<String>.from(widget.client.ignoredUsers)..sort();
      _profiles.removeWhere((key, _) => !_users.contains(key));
    });
    for (final mxid in _users) {
      if (!_profiles.containsKey(mxid)) {
        _loadProfile(mxid);
      }
    }
  }

  /// 官方 `getProfileFromUserId`（含快取）；失敗（離線／404 等）→ 靜默，
  /// 以 mxid 呈現。
  Future<void> _loadProfile(String mxid) async {
    try {
      final p = await widget.client
          .getProfileFromUserId(mxid, timeout: const Duration(seconds: 10));
      if (!mounted) {
        return;
      }
      if (_users.contains(mxid)) {
        setState(() => _profiles[mxid] = p);
      }
    } on Object {
      // 失敗靜默——名稱以 mxid 呈現。
    }
  }

  String _name(String mxid) {
    final dn = _profiles[mxid]?.displayName;
    return (dn != null && dn.isNotEmpty) ? dn : mxid;
  }

  /// 解除封鎖＝官方 `Client.unignoreUser()`（第十五批同款確認框結構）。
  Future<void> _unblock(String mxid) async {
    final name = _name(mxid);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解除封鎖「$name」？'), // 文案草案（第十五批確認框同型）
        content: const Text('解除後，您將重新收到此帳號傳來的訊息。'), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除封鎖'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.client.unignoreUser(mxid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已解除封鎖「$name」')), // 文案草案
        );
      }
      _refresh();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解除封鎖失敗：$e')), // 文案草案
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('封鎖名單'), // 文案草案
      ),
      body: _users.isEmpty
          ? Center(
              child: Text(
                '沒有封鎖任何使用者', // 文案草案
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          : Column(
              children: [
                // LINE 結構：計數標題＋灰色說明段落（語意對映，文案草案）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '封鎖名單 ${_users.length} 人', // 文案草案
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '解除封鎖後，此帳號將能再次傳送訊息與通話給您。', // 文案草案
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) => _row(_users[index]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String mxid) {
    final title = _name(mxid);
    return ListTile(
      leading: _Avatar(client: widget.client, url: _profiles[mxid]?.avatarUrl, name: title),
      title: Text(title),
      // 顯示名稱時附 mxid 小字（v0；避免同名誤解）。
      subtitle: title == mxid ? null : Text(mxid),
      trailing: TextButton(
        onPressed: () => _unblock(mxid),
        child: const Text('解除封鎖'), // 文案草案
      ),
    );
  }
}

/// 頭像（官方縮圖路徑；查得 profile 有 avatarUrl 才走網路，否則首字。
/// 樣式同 contacts_screen 的 CircleAvatar 骨架）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.client, required this.url, required this.name});

  final Client client;
  final Uri? url;
  final String name;

  Future<(Uri, bool)>? _thumb() {
    if (url == null || !url!.isScheme('mxc')) {
      return null;
    }
    try {
      return () async {
        final uri = await url!.getThumbnailUri(
          client,
          width: 64,
          height: 64,
        );
        final auth = await client.authenticatedMediaSupported();
        return (uri, auth);
      }();
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() => CircleAvatar(child: Text(_initial(name)));
    final future = _thumb();
    if (future == null) {
      return fallback();
    }
    return FutureBuilder<(Uri, bool)>(
      future: future,
      builder: (context, snap) {
        if (snap.hasData) {
          final (uri, auth) = snap.data!;
          // getThumbnailUri 對非 mxc 回 Uri()（空白）——回退首字，不再畫。
          if (uri.toString().isEmpty) {
            return fallback();
          }
          return CircleAvatar(
            backgroundImage: NetworkImage(
              uri.toString(),
              headers: auth
                  ? <String, String>{'authorization': 'Bearer ${client.accessToken}'}
                  : null,
            ),
          );
        }
        return fallback();
      },
    );
  }

  String _initial(String name) {
    final runes = name.runes;
    return runes.isEmpty ? '?' : String.fromCharCode(runes.first);
  }
}
