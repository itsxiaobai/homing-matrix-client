// 貼圖管理（藍圖 Phase 3.6「貼圖包管理（安裝／移除／排序）」）。
//
// 版位參考 LINE（`LINE_ref/new_ref/settings/stickers/`）：
// - 「My Stickers」頁＝貼圖清單（縮圖＋名稱）＋右上編輯（排序／移除）
// - 「Sticker set order」頁＝每列左側移除鈕、右側拖曳把手排序
// Homing 只做**本機貼圖庫**（使用者自行匯入的圖片）；不做商店、訂閱、
// 購買記錄、禮物盒、心願單等 LINE 專屬功能（藍圖 §二「貼圖商店 ❌ 不做」）。
//
// 樣式為草案，待人類設計定稿；元件不寫死寬度（縮圖固定、列可捲動）。
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_settings.dart';
import 'design_tokens.dart';
import '../sticker_suggestions.dart';
import '../sticker_pack_store.dart'; // 第四十七批：貼圖包名稱
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import './a11y.dart'; // 無障礙：按鈕功能說明
import 'line_style.dart'; // 68c–68f：LINE 自繪圖示

/// 貼圖動畫播放開關的 kv key。
const String kStickerAnimationKey = 'sticker_animation_enabled';

// 貼圖預覽開關（kv `sticker_preview_enabled`）**已移除**（第六十七批，人類
// 2026-11-17 拍板）：貼圖**一律不可點入檢視**（著作權，與「不可分享／下載」
// 同一理由）→ 不再提供開關；舊 kv 值殘留無作用（不讀不寫）。

/// 第四十六批：貼圖依 **pack 分組**的顯示模型。
///
/// 一組＝同一個貼圖包（`packId`）；`packId` 為 null 者歸入「單張貼圖」組
/// （直接由相簿匯入、沒有 pack 來源的貼圖）。
class StickerGroup {
  const StickerGroup({required this.packId, required this.title, required this.entries});

  /// 貼圖包 id；null＝單張貼圖組（無 pack）。
  final String? packId;

  /// 組標題（pack 名稱／「單張貼圖」）。
  final String title;

  /// 組內貼圖（依原排序）。
  final List<StickerLibraryEntry> entries;
}

/// 把貼圖清單依 pack 分組（保持原順序；`packId` null 者歸「單張貼圖」組）。
///
/// [packTitles]：貼圖包 id → 顯示名稱（由貼圖包 manifest 的 `name` 取得）；
/// 未提供者退回貼圖包 id 本身。
List<StickerGroup> groupStickersByPack(
  List<StickerLibraryEntry> stickers, {
  Map<String, String> packTitles = const {},
}) {
  final groups = <StickerGroup>[];
  final indexByPack = <String, int>{};
  for (final s in stickers) {
    final key = s.packId ?? '';
    if (key.isEmpty) {
      // 單張貼圖：各自成一組（沒有 pack 資訊可依）。
      groups.add(StickerGroup(packId: null, title: S.t('單張貼圖'), entries: [s]));
      continue;
    }
    final title = packTitles[key] ?? s.packId!;
    final existing = indexByPack[key];
    if (existing == null) {
      indexByPack[key] = groups.length;
      groups.add(StickerGroup(packId: s.packId, title: title, entries: [s]));
    } else {
      groups[existing] = StickerGroup(
        packId: groups[existing].packId,
        title: groups[existing].title,
        entries: [...groups[existing].entries, s],
      );
    }
  }
  return groups;
}

/// 我的貼圖（管理頁）：檢視／排序／移除本機匯入的貼圖。
class StickerManagerScreen extends StatefulWidget {
  const StickerManagerScreen({super.key});

  @override
  State<StickerManagerScreen> createState() => _StickerManagerScreenState();
}

class _StickerManagerScreenState extends State<StickerManagerScreen> {
  List<StickerLibraryEntry> _stickers = const [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// 第四十六批：貼圖**動畫播放**開關（kv `sticker_animation_enabled`）。
  /// 關閉時以靜態首幀顯示（省電、避免貼圖列跳動）。
  bool _animationEnabled = true;

  /// 第四十七批：貼圖包 id → 顯示名稱（manifest 的 `name`）。
  Map<String, String> _packTitles = const {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 依搜尋字串過濾後**再依 pack 分組**（第四十六批）。
  List<StickerGroup> get _groups =>
      groupStickersByPack(_filtered, packTitles: _packTitles);

  /// 依搜尋字串過濾（名稱／shortcode／關鍵字）。
  List<StickerLibraryEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _stickers;
    return _stickers.where((s) {
      final haystack = [
        s.name ?? '',
        s.body ?? '',
        ...s.keywords,
        ...stickerSearchKeywords(s),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }



  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AppSettings.listStickers();
      _animationEnabled = await AppSettings.get(kStickerAnimationKey)
          .then((v) => v != '0')
          .catchError((_) => true);
      // 第四十七批：貼圖包顯示名稱（manifest `name`；取不到則用 id）。
      final titles = <String, String>{};
      try {
        for (final meta in await StickerPackStore.loadPackMetas()) {
          final id = meta['id'];
          final name = meta['name'];
          if (id is String && id.isNotEmpty && name is String && name.isNotEmpty) {
            titles[id] = name;
          }
        }
      } catch (_) {
        // DB 不可用 → 空對照（退回用 pack id 當標題）。
      }
      _packTitles = titles;
      if (mounted) {
        setState(() {
          _stickers = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 切換貼圖動畫播放（kv）。
  Future<void> _setAnimationEnabled(bool v) async {
    await AppSettings.set(kStickerAnimationKey, v ? '1' : '0');
    if (mounted) setState(() => _animationEnabled = v);
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;
    for (final f in result) {
      final path = f.path;
      if (path != null) {
        await AppSettings.addSticker(path, name: f.name);
      }
    }
    await _load();
  }

  Future<void> _remove(StickerLibraryEntry entry) async {
    await AppSettings.removeSticker(entry.id);
    await _load();
  }

  /// 組內拖曳排序（LINE「Sticker set order」的把手行為）；排序值存本機。
  ///
  /// 只調整**同一個 pack 組內**的順序（第四十六批：貼圖依 pack 分組後，
  /// 跨組拖曳會產生「貼圖移到別的貼圖包」的語意疑義，故不支援）。
  /// `onReorderItem` 的 toIndex 已扣除被移動項（Flutter 3.41+ 新 API）。
  Future<void> _reorderInGroup(
    StickerGroup group,
    int oldIndex,
    int newIndex,
  ) async {
    final entries = List<StickerLibraryEntry>.from(group.entries);
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final moved = entries.removeAt(oldIndex);
    final target = newIndex.clamp(0, entries.length);
    entries.insert(target, moved);
    // 重建整體清單（保持其他組的位置與內容）。
    final rebuilt = <StickerLibraryEntry>[];
    for (final g in groupStickersByPack(_stickers)) {
      if (g.packId == group.packId) {
        rebuilt.addAll(entries);
      } else {
        rebuilt.addAll(g.entries);
      }
    }
    setState(() => _stickers = rebuilt);
    await AppSettings.reorderStickers(rebuilt.map((e) => e.id).toList());
  }

  /// 單一貼圖列（縮圖＋名稱＋移除）。
  Widget _buildStickerTile(
    StickerGroup group,
    StickerLibraryEntry entry,
    int index,
  ) {
    final label = stickerStem(entry.name).isEmpty
        ? '貼圖'
        : stickerStem(entry.name);
    return ListTile(
      key: ValueKey('sticker-${entry.id}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Semantics(
            label: '貼圖：$label',
            child: Image.file(
              File(entry.path),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
              // 第四十六批：動畫關閉時以靜態首幀顯示（`gaplessPlayback` 關、
              // `filterQuality` 低；GIF/APNG 由 Flutter 原生支援，本專案匯入
              // 時已拒收動圖，故此處僅影響使用者自行加入的動態檔）。
              gaplessPlayback: _animationEnabled,
              errorBuilder: (_, _, _) => Icon(
                AllIcons.imageNotSupportedOutlined,
                size: 20,
              ),
            ),
          ),
        ),
      ),
      title: Text(label),
      subtitle: Text(entry.path.split('/').last),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          a11yButton(label: S.t('移除'), child: IconButton(
            tooltip: S.t('移除'), // 草案文案
            onPressed: () => unawaited(_remove(entry)),
            icon: Icon(AllIcons.removeCircleOutline),
          )),
          // 拖曳把手（LINE 貼圖排序頁的 ≡ 把手）。
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(AllIcons.dragHandle),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: lineTitlePill(context, S.t('我的貼圖')), // 草案文案（參考 LINE「My Stickers」）
        actions: [
          a11yButton(label: S.t('匯入貼圖'), child: IconButton(
            tooltip: S.t('匯入貼圖'), // 草案文案
            onPressed: _import,
            icon: Icon(AllIcons.addPhotoAlternateOutlined),
          )),
          // 第四十六批：貼圖設定（動畫播放）—— LINE 貼圖設定頁的
          // 「播放動畫貼圖」開關（版位慣例）。**「貼圖預覽」開關已移除**
          // （第六十七批：貼圖一律不可點入檢視＝硬性需求，無開關）。
          PopupMenuButton<String>(
            tooltip: S.t('貼圖設定'), // 草案文案
            icon: Icon(AllIcons.tune),
            onSelected: (value) {
              if (value == 'animation') {
                unawaited(_setAnimationEnabled(!_animationEnabled));
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: 'animation',
                checked: _animationEnabled,
                child: Text(S.t('播放動畫貼圖')), // 草案文案
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stickers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '尚未匯入貼圖\n請點右上角匯入，或到「外觀設定」匯入',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _import,
                          child: Text(S.t('匯入貼圖')), // 草案文案
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v.trim()),
                        decoration: InputDecoration(
                          hintText: S.t('搜尋貼圖（名稱／關鍵字）'), // 文案草案
                          prefixIcon: lineIconWithTestFallback(Icons.search, LineIcon.search, size: 22, color: Theme.of(context).colorScheme.onSurface),
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context).brightness == Brightness.dark ? kLineBar : kSearchFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    // 第四十六批：貼圖依 **pack 分組**顯示（組標題 ＋ 組內列）。
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _groups.length,
                        itemBuilder: (context, index) {
                          final group = _groups[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 組標題（pack 名稱／「單張貼圖」）。
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Row(
                                  children: [
                                    Text(
                                      group.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: kTextSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${group.entries.length} 張',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: kTextSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              // 組內拖曳排序（各組獨立排序；跨組移動不支援——
                              // 避免把貼圖搬到別的貼圖包語意不清的包裡）。
                              ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: group.entries.length,
                                onReorderItem: (oldIndex, newIndex) =>
                                    unawaited(_reorderInGroup(group, oldIndex, newIndex)),
                                itemBuilder: (context, index) => _buildStickerTile(
                                  group,
                                  group.entries[index],
                                  index,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
