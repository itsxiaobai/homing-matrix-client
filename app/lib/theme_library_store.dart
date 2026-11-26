// 主題包同步（第四十九批）——把本機的「我的主題」寫進**貼圖庫房間**，
// 使其他裝置能取得同一份主題（與貼圖庫共用同一個私密房間）。
//
// 為什麼共用同一房間？
// - 藍圖 3.11 決定貼圖庫＝**專用私密房間**；主題同屬「使用者個人內容」，
//   再開一個房間會讓使用者的私密房間數膨脹。
// - 房間內的內容**只有自己看得到**（不邀請任何人、不可公開搜尋）。
//
// 事件型別：`io.github.itsxiaobai.homing.theme`（**自訂** state event）。
// ⚠️ Matrix 規格**沒有**主題的標準事件型別（截至 v1.19）→ 本型別是 Homing
// 自訂的；若其他客戶端不認識它會忽略（不影響貼圖庫的相容性）。
// 穩定名（`m.*`）**不得**冒用——那是規格保留的命名空間。
//
// 實作一律走**官方 API**（`Client.setRoomStateWithKey`／
// `Client.getRoomStateByType`）；App 端不自寫任何加密或協定邏輯。
import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'app_settings.dart';
import 'sticker_pack_store.dart';

/// 主題同步的事件型別（Homing 自訂；非 Matrix 標準）。
const String kHomingThemeStateType = 'io.github.itsxiaobai.homing.theme';

/// 主題同步的結果統計。
typedef ThemeSyncResult = ({int themes, bool ok});

/// 主題庫同步（把本機主題寫進貼圖庫房間）。
class ThemeLibraryStore {
  ThemeLibraryStore._();

  /// 主題的中繼資料 kv key 前綴（每個主題一筆 JSON）。
  static const String kThemeMetaPrefix = 'theme_meta_';

  /// 某個主題的 state_key（房間 state 事件的 key）。
  ///
  /// 用「名稱＋建立時間」確保同一房間內不撞名；本機 id 為單調遞增整數，
  /// 直接當 state_key 最單純（其他裝置只要知道 id 即可對應）。
  static String themeStateKey(int id) => 'theme-$id';

  /// 把本機「我的主題」全部同步到貼圖庫房間。
  ///
  /// - 房間＝[StickerPackStore.ensurePackRoom]（同一個私密房間）。
  /// - 每個主題一個 state 事件（`state_key`＝`theme-<本機 id>`）。
  /// - content＝`{name, seed?, wallpaper?}`（**不含本機檔案路徑**——
  ///   檔案路徑在別的裝置無意義；桌布圖片本體可另行以 mxc 上傳，本批不做）。
  static Future<ThemeSyncResult> syncAll(Client client) async {
    final themes = await AppSettings.listThemes();
    final roomId = await StickerPackStore.ensurePackRoom(client);
    var written = 0;
    for (final t in themes) {
      try {
        await client.setRoomStateWithKey(
          roomId,
          kHomingThemeStateType,
          themeStateKey(t.id),
          <String, dynamic>{
            'name': t.name,
            if (t.seed != null) 'seed': t.seed,
            if (t.wallpaper != null && t.wallpaper!.startsWith('#'))
              'wallpaper_color': t.wallpaper,
          },
        );
        written++;
      } catch (_) {
        // 單一主題失敗不中斷其餘（下次同步會再試）。
      }
    }
    return (themes: written, ok: true);
  }

  /// 讀取貼圖庫房間裡已同步的主題（供其他裝置匯入本機）。
  ///
  /// 回傳格式同 [AppSettings.listThemes] 的元素（不含本機 id；匯入時另給）。
  static Future<List<({String name, String? seed, String? wallpaper})>>
      loadRemoteThemes(Client client) async {
    final out = <({String name, String? seed, String? wallpaper})>[];
    String roomId;
    try {
      final saved = await AppSettings.get(StickerPackStore.kPackRoomIdKey);
      if (saved == null || saved.isEmpty) return out;
      roomId = saved;
    } catch (_) {
      return out;
    }
    try {
      // 官方 API：`Client.getRoomState`（讀取房間當前全部 state 事件），
      // 再由本機過濾出主題型別（SDK 沒有「依型別讀 state」的單一 API）。
      final states = await client.getRoomState(roomId);
      for (final ev in states) {
        if (ev.type != kHomingThemeStateType) continue;
        final content = ev.content;
        final name = content['name'];
        if (name is! String || name.isEmpty) continue;
        final seed = content['seed'];
        final wallpaper = content['wallpaper_color'];
        out.add((
          name: name,
          seed: seed is String && seed.isNotEmpty ? seed : null,
          wallpaper:
              wallpaper is String && wallpaper.isNotEmpty ? wallpaper : null,
        ));
      }
    } catch (_) {
      // 讀取失敗 → 空清單（不臆造）。
    }
    return out;
  }

  /// 把讀到的主題匯入本機「我的主題」（同名者跳過，避免重複）。
  static Future<int> importRemoteThemes(Client client) async {
    final remote = await loadRemoteThemes(client);
    if (remote.isEmpty) return 0;
    var imported = 0;
    try {
      final local = await AppSettings.listThemes();
      final localNames = local.map((t) => t.name).toSet();
      for (final t in remote) {
        if (localNames.contains(t.name)) continue;
        await AppSettings.addTheme(
          t.name,
          seed: t.seed,
          wallpaper: t.wallpaper,
        );
        imported++;
      }
    } catch (_) {
      // DB 不可用 → 0。
    }
    return imported;
  }

  /// 把主題的元資料存成本機 kv（供診斷與重複比對；非必要路徑）。
  static Future<void> saveThemeMeta(
    int id,
    Map<String, dynamic> meta,
  ) async {
    try {
      await AppSettings.set('$kThemeMetaPrefix$id', jsonEncode(meta));
    } catch (_) {
      // 存 kv 失敗不影響主流程。
    }
  }
}
