// 貼圖庫房間（藍圖 3.11「個人貼圖庫」——**人類 2026-11-15 決定：專用私密
// 貼圖庫房間**）。
//
// 作用：把使用者本機的貼圖包（`m.room.image_pack` 房間狀態事件）**寫到一個
// 只有自己的私密房間**，使其他裝置／其他客戶端能取得同一份貼圖庫。
//
// 規格對映（`STICKER_FORMAT.md` §7，Matrix v1.19 image packs）：
// - 房間狀態事件：`m.room.image_pack`，`state_key`＝貼圖包 id，content＝
//   `{images: {shortcode: {url, body?, info?}}, pack: {display_name?, attribution?, usage?}}`
// - account data：`m.image_pack.rooms` → `{rooms: {roomId: {packId: {}}}}`
//   ⚠️ 穩定規格原文**未能對照**（本環境無網頁查證工具）→ 結構沿用 SDK 舊草案
//   `im.ponies.emote_rooms` 的形狀（`lib/src/utils/image_pack_extension.dart`
//   L51-61 的讀取方式），並標記為待查證。
//
// 實作一律走**官方 API**：`Client.createRoom`／`Client.setRoomStateWithKey`／
// `Client.setAccountData`；App 端不自寫任何加密或協定邏輯。
import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'app_settings.dart';
import 'sticker_pack_importer.dart';

/// 貼圖包寫入粒度（人類 2026-11-15 決定：**兩種都提供**）。
enum StickerPackGranularity {
  /// 整包：一個 zip ＝ 一個 `m.room.image_pack` 事件（state_key＝pack id）。
  bundle,

  /// 每張獨立：每張貼圖各一個事件（state_key＝shortcode）。
  perSticker,
}

/// 貼圖庫房間的識別與常數。
class StickerPackStore {
  StickerPackStore._();

  /// 本機保存「貼圖庫房間 id」的 kv key。
  static const String kPackRoomIdKey = 'sticker_pack_room_id';

  /// 貼圖庫房間名稱（使用者可於房內改名）。
  static const String kPackRoomName = '貼圖庫';

  /// 房間狀態事件型別（Matrix v1.19 穩定名）。
  static const String kPackStateType = 'm.room.image_pack';

  /// account data 型別（Matrix v1.19 穩定名）。
  static const String kPackAccountDataType = 'm.image_pack.rooms';

  /// 貼圖包中繼資料的 kv key 前綴（每個 pack 一筆 JSON）。
  static const String kPackMetaPrefix = 'sticker_pack_meta_';

  /// pack 事件的寫入粒度設定（kv）。
  static const String kGranularityKey = 'sticker_pack_granularity';

  /// 目前粒度（預設整包）。
  static Future<StickerPackGranularity> granularity() async {
    try {
      final v = await AppSettings.get(kGranularityKey);
      return v == 'per_sticker'
          ? StickerPackGranularity.perSticker
          : StickerPackGranularity.bundle;
    } catch (_) {
      return StickerPackGranularity.bundle;
    }
  }

  /// 設定粒度（kv）。
  static Future<void> setGranularity(StickerPackGranularity g) async {
    await AppSettings.set(kGranularityKey, g.name);
  }

  /// 取得（或建立）**專用私密貼圖庫房間**。
  ///
  /// - 已存在且仍可見 → 直接沿用（不重複建房）。
  /// - 否則 → 官方 `Client.createRoom` 建立**私密**房間（不邀請任何人、
  ///   不設公開可見性），並把 id 存在本機 kv。
  static Future<String> ensurePackRoom(Client client) async {
    try {
      final saved = await AppSettings.get(kPackRoomIdKey);
      if (saved != null && saved.isNotEmpty) {
        final room = client.getRoomById(saved);
        if (room != null) {
          return saved;
        }
      }
    } catch (_) {
      // 讀取失敗 → 往下走建立流程。
    }
    final roomId = await client.createRoom(
      name: kPackRoomName,
      isDirect: false,
      visibility: Visibility.private, // 私密房間（不進公開目錄）
      preset: CreateRoomPreset.privateChat,
    );
    try {
      await AppSettings.set(kPackRoomIdKey, roomId);
    } catch (_) {
      // 存 kv 失敗不影響本次寫入（下次會另建房）。
    }
    return roomId;
  }

  /// 儲存貼圖包的中繼資料（含每張貼圖的 shortcode／body／mxc／圖片資訊），
  /// 供後續寫 pack 事件用（不需重新推導）。
  static Future<void> savePackMeta(
    StickerPack pack,
    List<Map<String, dynamic>> items,
  ) async {
    final meta = <String, dynamic>{
      'id': pack.id,
      'name': pack.name,
      'author': pack.author,
      'license': pack.license,
      'attribution': pack.attribution,
      'usage': pack.usage,
      'description': pack.description,
      'items': items,
    };
    await AppSettings.set('$kPackMetaPrefix${pack.id}', jsonEncode(meta));
  }

  /// 讀出本機所有貼圖包的中繼資料（依 kv 掃描；純本機）。
  static Future<List<Map<String, dynamic>>> loadPackMetas() async {
    final out = <Map<String, dynamic>>[];
    try {
      final keys = await AppSettings.keysWithPrefix(kPackMetaPrefix);
      for (final k in keys) {
        final raw = await AppSettings.get(k);
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            out.add(decoded.cast<String, dynamic>());
          }
        } catch (_) {
          // 壞值 → 略過。
        }
      }
    } catch (_) {
      // DB 不可用 → 空清單。
    }
    return out;
  }

  /// 依 `STICKER_FORMAT.md` §7 的對映組出 pack 事件 content（純函式）。
  ///
  /// [packMeta]：貼圖包中繼資料（id／name／author／attribution／usage／items）。
  /// items 每張＝`{shortcode, body?, url, info?}`（url＝mxc URI）。
  static Map<String, dynamic> buildPackContentForRoom({
    required Map<String, dynamic> packMeta,
    required List<Map<String, dynamic>> stickers,
  }) {
    final images = <String, dynamic>{};
    for (final s in stickers) {
      final shortcode = s['shortcode'];
      final url = s['url'];
      if (shortcode is! String ||
          shortcode.isEmpty ||
          url is! String ||
          url.isEmpty) {
        continue;
      }
      images[shortcode] = <String, dynamic>{
        'url': url,
        if (s['body'] is String && (s['body'] as String).isNotEmpty)
          'body': s['body'],
        if (s['info'] is Map) 'info': s['info'],
      };
    }
    final usage = packMeta['usage'];
    final author = packMeta['author'];
    final attribution = packMeta['attribution'];
    final authorPart = author is String && author.isNotEmpty ? author : '';
    final attributionPart =
        attribution is String && attribution.isNotEmpty ? attribution : '';
    final attributionText = [
      authorPart,
      attributionPart,
    ].where((e) => e.isNotEmpty).join(' — ');
    return <String, dynamic>{
      'images': images,
      'pack': <String, dynamic>{
        if (packMeta['name'] is String) 'display_name': packMeta['name'],
        if (attributionText.isNotEmpty) 'attribution': attributionText,
        if (usage is List && usage.isNotEmpty) 'usage': usage,
      },
    };
  }

  /// 把本機某個貼圖包的 pack 事件寫進貼圖庫房間（＋啟用 account data）。
  ///
  /// 粒度（人類 2026-11-15：**兩種都提供**）：
  /// - [Granularity.bundle]（預設）：整包 → **一個**事件，`state_key`＝pack id。
  /// - [Granularity.perSticker]：每張貼圖 → **各一個**事件，`state_key`＝shortcode。
  static Future<void> publishPack(
    Client client, {
    required String roomId,
    required Map<String, dynamic> packMeta,
    StickerPackGranularity granularity = StickerPackGranularity.bundle,
  }) async {
    final packId = packMeta['id'];
    if (packId is! String || packId.isEmpty) {
      return;
    }
    final rawItems = packMeta['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    if (granularity == StickerPackGranularity.perSticker) {
      for (final item in items) {
        final shortcode = item['shortcode'];
        if (shortcode is! String || shortcode.isEmpty) continue;
        final content = buildPackContentForRoom(
          packMeta: packMeta,
          stickers: <Map<String, dynamic>>[item],
        );
        await client.setRoomStateWithKey(
          roomId,
          kPackStateType,
          shortcode,
          content,
        );
        await _enablePack(client, roomId, shortcode);
      }
      return;
    }
    final content = buildPackContentForRoom(
      packMeta: packMeta,
      stickers: items,
    );
    await client.setRoomStateWithKey(roomId, kPackStateType, packId, content);
    await _enablePack(client, roomId, packId);
  }

  /// 把**本機所有貼圖包**同步到貼圖庫房間（建立房間＋逐包寫事件＋account data）。
  ///
  /// 回傳：房間 id、已同步的包數、已同步的貼圖數。
  static Future<({String roomId, int packs, int stickers})> syncAll(
    Client client,
  ) async {
    final roomId = await ensurePackRoom(client);
    final metas = await loadPackMetas();
    final granularity = await StickerPackStore.granularity();
    var packs = 0;
    var stickers = 0;
    for (final meta in metas) {
      try {
        await publishPack(
          client,
          roomId: roomId,
          packMeta: meta,
          granularity: granularity,
        );
        packs++;
        final items = meta['items'];
        if (items is List) {
          stickers += items.length;
        }
      } catch (_) {
        // 單一 pack 失敗不影響其他 pack。
      }
    }
    return (roomId: roomId, packs: packs, stickers: stickers);
  }

  /// account data：把此房間的 pack 設為啟用（`m.image_pack.rooms`）。
  static Future<void> _enablePack(
    Client client,
    String roomId,
    String packId,
  ) async {
    final userId = client.userID;
    if (userId == null) {
      return;
    }
    try {
      final raw = await client.getAccountData(userId, kPackAccountDataType);
      final content = <String, dynamic>{...raw};
      final rooms = content['rooms'];
      final roomsMap = rooms is Map
          ? Map<String, dynamic>.from(rooms)
          : <String, dynamic>{};
      final packs = roomsMap[roomId];
      final packsMap = packs is Map
          ? Map<String, dynamic>.from(packs)
          : <String, dynamic>{};
      packsMap[packId] = <String, dynamic>{};
      roomsMap[roomId] = packsMap;
      content['rooms'] = roomsMap;
      await client.setAccountData(userId, kPackAccountDataType, content);
    } catch (_) {
      // account data 寫入失敗不影響 pack 狀態事件（可稍後重試）。
    }
  }
}
