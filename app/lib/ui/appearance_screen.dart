// 批次 C（人類指示 2026-11-01）— 外觀設定（草案，待人類設計定稿）。
// 主題種子色、字型匯入、聊天室背景由 AppSettings (sqflite) 儲存。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:homing/main.dart'
    show
        applyRingFontFromPath,
        kSettingUseDynamicColor,
        ringFontFamily,
        ringSeedColor,
        ringTextScale,
        ringThemeMode,
        ringUseDynamicColor;
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import '../sticker_motion_prefs.dart'; // 第七十三批：GIF 開關
import '../sticker_pack_importer.dart';
import '../sticker_pack_installer.dart';
import '../sticker_pack_store.dart';
import '../theme_library_store.dart'; // 第四十九批：主題同步到貼圖庫房間
import '../theme_pack_importer.dart';
import '../theme_pack_installer.dart';
import 'sticker_manager_screen.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import 'app_icons.dart'; // 第五十七批：圖示變數化（主題包可覆換）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import './a11y.dart'; // 無障礙：按鈕功能說明

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key, this.client});

  /// homeserver client（zip 貼圖包匯入需上傳媒體；未提供則不顯示匯入入口）。
  final Client? client;

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  String? _seedColor;
  String? _fontPath;
  bool _loading = true;

  // 批次十二①：我的主題（創作者主題 v0）＋全域聊天室背景。
  List<({int id, String name, String? seed, String? wallpaper})> _themes = [];
  int? _selectedThemeId;
  String? _chatWallpaper;

  /// 批次 H：跟隨 Android 桌布配色（預設關＝Homing 種子色；人類決定）。
  bool _useDynamic = false;

  /// 批次 I①：文字大小與深淺模式（草案）。
  double _textScale = 1.0;
  ThemeMode _themeMode = ThemeMode.system;

  /// 貼圖（backlog #8／Phase 3.6）：本機貼圖庫數量＋貼圖建議開關。
  int _stickerCount = 0;
  bool _stickerSuggestionsEnabled = true;
  bool _staticStickers = false; // 第七十三批：GIF 靜態首幀（前庭）

  /// 貼圖包寫入粒度（人類 2026-11-15：**兩種都提供**）。
  StickerPackGranularity _packGranularity = StickerPackGranularity.bundle;

  static const _presetColors = <String, Color>{
    '蜜桃（預設）': Color(0xFFFFBD9F),
    '薄荷': Color(0xFF9FE7C8),
    '薰衣草': Color(0xFFC9B6E4),
    '天空': Color(0xFF9FC9E7),
    '玫瑰': Color(0xFFE79FC9),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _seedColor = await AppSettings.get('theme_seed_color');
    _fontPath = await AppSettings.get('font_path');
    // 批次十二①：主題清單＋選中主題＋全域桌布（無 DB（測試）＝空清單）。
    try {
      _themes = await AppSettings.listThemes();
      final sel = await AppSettings.get('selected_theme_id');
      _selectedThemeId = sel == null ? null : int.tryParse(sel);
      _chatWallpaper = await AppSettings.getChatWallpaper();
    } catch (_) {
      _themes = [];
    }
    _useDynamic = await AppSettings.get(kSettingUseDynamicColor).then((v) => v == '1')
        .catchError((_) => false); // sqflite 不可用（測試）→ 預設關。
    _textScale = await AppSettings.get('text_scale').then((v) {
      final d = double.tryParse(v ?? '');
      return d ?? 1.0;
    }).catchError((_) => 1.0);
    _themeMode = await AppSettings.get('theme_mode').then((v) {
      switch (v) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        default:
          return ThemeMode.system;
      }
    }).catchError((_) => ThemeMode.system);
    // 貼圖（backlog #8／Phase 3.6）：貼圖庫數量＋「顯示貼圖建議」開關
    // （對應 LINE 貼圖設定頁的 Display suggestions）。
    try {
      _stickerCount = (await AppSettings.listStickers()).length;
    } catch (_) {
      _stickerCount = 0;
    }
    _stickerSuggestionsEnabled =
        await AppSettings.get('sticker_suggestions_enabled')
            .then((v) => v != '0')
            .catchError((_) => true);
    await loadStickerMotionPref().catchError((_) {});
    _staticStickers = ringStaticStickers.value;
    // 貼圖包粒度（整包／每張獨立）。
    _packGranularity = await StickerPackStore.granularity();
    if (mounted) setState(() => _loading = false);
  }

  /// 切換「顯示貼圖建議」（kv `sticker_suggestions_enabled`）。
  Future<void> _setStickerSuggestionsEnabled(bool v) async {
    await AppSettings.set('sticker_suggestions_enabled', v ? '1' : '0');
    if (mounted) setState(() => _stickerSuggestionsEnabled = v);
  }

  /// 開啟「我的貼圖」管理頁（LINE「My Stickers」）。
  Future<void> _openStickerManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StickerManagerScreen()),
    );
    try {
      _stickerCount = (await AppSettings.listStickers()).length;
    } catch (_) {
      _stickerCount = 0;
    }
    if (mounted) setState(() {});
  }

  /// 匯入 zip 貼圖包（藍圖 Phase 3.2／3.3；格式規格見 STICKER_FORMAT.md）。
  /// 先做**全部**安全驗證（中央目錄掃描、路徑安全、白名單、檔頭預檢），
  /// 通過後才解壓與上傳 homeserver（官方 `Client.uploadContent`）。
  Future<void> _importStickerPack() async {
    final client = widget.client;
    if (client == null) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (result.isEmpty) return;
    final path = result.first.path;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final pack = parseStickerPack(bytes);
      final libraryDir = await _stickerLibraryDir();
      final install = await installStickerPack(
        client: client,
        pack: pack,
        libraryDir: libraryDir,
      );
      try {
        _stickerCount = (await AppSettings.listStickers()).length;
      } catch (_) {
        _stickerCount = 0;
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已匯入「${install.packName}」${install.imported} 張貼圖'
            '（上傳 homeserver ${install.uploaded} 張）',
          ), // 草案文案
        ),
      );
    } on StickerPackException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('貼圖包無法匯入：')}${e.message}')), // 草案文案
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('貼圖包匯入失敗：')}$e')), // 草案文案
      );
    }
  }

  /// 匯入主題包（zip；規格草案見 `THEME_FORMAT.md` v1，**待人類審閱**）。
  ///
  /// 驗證 → 解壓資產 → 登錄主題（名稱／種子色／桌布）→ 使用者可手動套用。
  Future<void> _importThemePack() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (result.isEmpty) return;
    final path = result.first.path;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final pack = parseThemePack(bytes);
      final base = await getApplicationDocumentsDirectory();
      final themesDir = Directory('${base.path}/themes');
      await themesDir.create(recursive: true);
      final install = await installThemePack(
        pack: pack,
        zipBytes: bytes,
        themesDir: themesDir,
      );
      await _reloadThemes();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${S.t('已匯入主題「')}${install.packName}${S.t('」（可於「我的主題」套用）')}'),
        ), // 草案文案
      );
    } on ThemePackException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('主題包無法匯入：')}${e.message}')), // 草案文案
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('主題包匯入失敗：')}$e')), // 草案文案
      );
    }
  }

  /// 切換貼圖包寫入粒度（整包／每張獨立）。
  Future<void> _setPackGranularity(bool perSticker) async {
    final g = perSticker
        ? StickerPackGranularity.perSticker
        : StickerPackGranularity.bundle;
    await StickerPackStore.setGranularity(g);
    if (mounted) setState(() => _packGranularity = g);
  }

  /// 藍圖 3.11（人類 2026-11-15 決定：專用私密貼圖庫房間）：
  /// 把本機貼圖包寫進**貼圖庫房間**（`m.room.image_pack` 房間狀態事件 ＋
  /// `m.image_pack.rooms` account data）→ 其他裝置／客戶端可取得同一份貼圖庫。
  ///
  /// ⚠️ 首次執行會在你的帳號**建立一個私密房間**（無成員、不可見於公開目錄）。
  Future<void> _syncStickerLibrary() async {
    final client = widget.client;
    if (client == null) return;
    try {
      final result = await StickerPackStore.syncAll(client);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已同步 ${result.packs} 個貼圖包（${result.stickers} 張）到貼圖庫房間',
          ), // 草案文案
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('貼圖庫同步失敗：')}$e')), // 草案文案
      );
    }
  }

  /// 本機貼圖庫資料夾（zip 貼圖包解壓副本）。
  Future<Directory> _stickerLibraryDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sticker_library');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _setSeedColor(String hex) async {
    await AppSettings.set('theme_seed_color', hex);
    setState(() => _seedColor = hex);
    // Suggestion #4：即時套用（官方 ValueNotifier 通道，同 ringTextScale）。
    ringSeedColor.value = hex;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('種子色已更新'))), // 草案文案
      );
    }
  }

  /// 批次第 6 點：自訂主題色十六進位輸入。
  Future<void> _askCustomColor() async {
    final controller = TextEditingController(text: _seedColor ?? '');
    final hex = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('自訂主題色')), // 文案草案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: '顏色（例如 FFFFBD9F）',
                hintText: 'FFFFBD9F',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.t('套用')), // 文案草案
          ),
        ],
      ),
    );
    if (hex == null || hex.isEmpty || !mounted) return;
    final clean = hex.replaceFirst('#', '');
    if (int.tryParse(clean, radix: 16) == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('顏色格式錯誤'))), // 文案草案
        );
      }
      return;
    }
    await _setSeedColor(clean);
  }

  Future<void> _importFont() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
    );
    if (result.isEmpty || result.first.path == null) return;
    final path = result.first.path!;
    await AppSettings.set('font_path', path);
    // 批次 H（人類批准「導入即生效」）：骨架版只存不讀 → 補 FontLoader 渲染
    // 接線（官方 services API）；啟動時由 main.dart 從 font_path 還原。
    final ok = await applyRingFontFromPath(path);
    setState(() => _fontPath = path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? '字型已匯入並套用' // 草案文案
              : '字型匯入失敗（檔案無法讀取或格式不支援）'), // 草案文案
        ),
      );
    }
  }

  Future<void> _clearFont() async {
    await AppSettings.remove('font_path');
    // 批次 H：移除渲染即時生效（回到平台預設字型）。
    ringFontFamily.value = null;
    setState(() => _fontPath = null);
  }

  /// 批次 H（人類決定）：動態取色預設關；開關切換**即時生效**＋本機儲存。
  Future<void> _setUseDynamic(bool value) async {
    ringUseDynamicColor.value = value; // MaterialApp 立即重建主題
    await AppSettings.set(kSettingUseDynamicColor, value ? '1' : '0');
    if (mounted) setState(() => _useDynamic = value);
  }

  /// 批次 I①：文字大小（即時生效）。
  Future<void> _setTextScale(double value) async {
    ringTextScale.value = value;
    await AppSettings.set('text_scale', value.toString());
    if (mounted) setState(() => _textScale = value);
  }

  /// 批次 I①：深淺模式（即時生效）。
  Future<void> _setThemeMode(ThemeMode value) async {
    ringThemeMode.value = value;
    final str = value == ThemeMode.light
        ? 'light'
        : value == ThemeMode.dark
            ? 'dark'
            : 'system';
    await AppSettings.set('theme_mode', str);
    if (mounted) setState(() => _themeMode = value);
  }

  Future<void> _importSticker() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (result.isEmpty) return;
    for (final f in result) {
      if (f.path != null) {
        await AppSettings.addSticker(f.path!, name: f.name);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('已匯入 ')}${result.length}${S.t(' 張貼圖')}')), // 草案文案
      );
    }
    try {
      _stickerCount = (await AppSettings.listStickers()).length;
    } catch (_) {
      _stickerCount = 0;
    }
    if (mounted) setState(() {});
  }

  /// 批次十二①：建立主題（創作者主題 v0）＝選桌布圖＋命名；
  /// 種子色沿用建立當下的主題色（分項選取，zip 打包待 archive 依賴批准）。
  Future<void> _createTheme() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty || result.first.path == null) return;
    if (!mounted) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('建立主題')), // 草案文案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${S.t('桌布：')}${result.first.name}'), // 草案文案
            TextField(
              controller: controller,
              maxLength: 20,
              decoration: const InputDecoration(labelText: '主題名稱'), // 草案文案
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.t('建立')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await AppSettings.addTheme(name, seed: _seedColor, wallpaper: result.first.path);
    await _reloadThemes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('已建立主題（尚未套用）'))), // 草案文案
      );
    }
  }

  /// 批次十二①：套用主題＝記錄選中＋套用種子色＋套用／保留全域桌布。
  /// 無桌布的主題不會清掉現有桌布（v0 行為披露，見 THEME_FORMAT.md）。
  Future<void> _applyTheme(
    ({int id, String name, String? seed, String? wallpaper}) theme,
  ) async {
    await AppSettings.set('selected_theme_id', theme.id.toString());
    // 第五十七批：圖示變數化——套用該主題的圖示覆寫（沒有則還原預設）。
    try {
      final rawIcons = await AppSettings.get('theme_icons_${theme.id}');
      final decoded = rawIcons == null ? null : jsonDecode(rawIcons);
      applyThemeIconOverrides(
        decoded is Map
            ? decoded.map((k, v) => MapEntry(k.toString(), v.toString()))
            : const {},
      );
    } catch (_) {
      clearAppIconOverrides();
    }
    if (theme.seed != null) {
      await _setSeedColor(theme.seed!);
    }
    if (theme.wallpaper != null) {
      await AppSettings.setChatWallpaper(theme.wallpaper!);
    }
    if (mounted) {
      setState(() => _selectedThemeId = theme.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('已套用主題「')}${theme.name}」')), // 草案文案
      );
    }
  }

  Future<void> _deleteTheme(
    ({int id, String name, String? seed, String? wallpaper}) theme,
  ) async {
    await AppSettings.removeTheme(theme.id);
    if (_selectedThemeId == theme.id) {
      await AppSettings.remove('selected_theme_id');
      _selectedThemeId = null;
    }
    await _reloadThemes();
  }

  Future<void> _reloadThemes() async {
    try {
      _themes = await AppSettings.listThemes();
    } catch (_) {
      _themes = [];
    }
    if (mounted) setState(() {});
  }

  /// 批次十二①：全域聊天室桌布（Colors／Your photos 兩入口；per-room 最優先）。
  Future<void> _setGlobalWallpaper(String value) async {
    await AppSettings.setChatWallpaper(value);
    if (mounted) setState(() => _chatWallpaper = value);
  }

  Future<void> _pickGlobalWallpaperImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty || result.first.path == null) return;
    await _setGlobalWallpaper(result.first.path!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('已設定全域聊天室桌布'))), // 草案文案
      );
    }
  }

  Future<void> _pickGlobalWallpaperColor() async {
    final color = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.t('選擇桌布顏色')), // 草案文案
        children: [
          for (final entry in _presetColors.entries)
            ListTile(
              leading: CircleAvatar(backgroundColor: entry.value, radius: 12),
              title: Text(entry.key),
              onTap: () =>
                  Navigator.pop(ctx, '#${entry.value.toARGB32().toRadixString(16).substring(2)}'),
            ),
        ],
      ),
    );
    if (color == null) return;
    await _setGlobalWallpaper(color);
  }

  Future<void> _clearGlobalWallpaper() async {
    await AppSettings.clearChatWallpaper();
    if (mounted) setState(() => _chatWallpaper = null);
  }

  /// 第四十六批（LINE 版位）：外觀設定改為**分頁**（TabBar）。
  ///
  /// LINE 的對應（版位慣例，非品牌識別）：設定底層的分類頁——顏色／桌布／
  /// 字型／貼圖／主題，各自獨立捲動。本實作只改**導覽結構**，設定項本身不變。
  static const _tabs = <String>['顏色', '桌布', '字型', '貼圖', '主題'];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.t('外觀設定')), // 草案文案
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final t in _tabs) Tab(text: t),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildColorTab(),
            _buildWallpaperTab(),
            _buildFontTab(),
            _buildStickerTab(),
            _buildThemeTab(),
          ],
        ),
      ),
    );
  }

  /// 分頁：顏色（種子色／自訂色／桌布配色／文字大小／主題模式）。
  Widget _buildColorTab() {
    return ListView(
      children: [
        ListTile(
          title: Text(S.t('主題種子色'), style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        // RadioGroup 依官方建議統一管理 group value（deprecated_member_use 清理）。
        RadioGroup<String>(
          groupValue: _seedColor ?? 'ffffbd9f',
          onChanged: (v) => v == null ? null : _setSeedColor(v),
          child: Column(
            children: [
              for (final entry in _presetColors.entries)
                RadioListTile<String>(
                  title: Text(entry.key),
                  value: entry.value.toARGB32().toRadixString(16).padLeft(8, '0'),
                ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: Icon(AllIcons.colorLensOutlined),
          title: Text(S.t('自訂主題色（十六進位）')), // 文案草案
          subtitle: Text(
            _seedColor != null ? '#$_seedColor' : '使用預設蜜桃色',
          ),
          trailing: a11yButton(label: S.t('編輯自訂主題色'), child: IconButton(
            icon: Icon(AllIcons.edit),
            tooltip: S.t('編輯自訂主題色'),
            onPressed: () => unawaited(_askCustomColor()),
          )),
        ),
        const Divider(),
        SwitchListTile(
          title: Text(S.t('跟隨 Android 桌布配色')), // 文案草案
          subtitle: Text(S.t('關閉＝固定使用 Homing 主色（預設）')), // 草案文案
          value: _useDynamic,
          onChanged: (v) => unawaited(_setUseDynamic(v)),
        ),
        const Divider(),
        ListTile(
          title: Text(S.t('文字大小'), style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final entry in const <MapEntry<String, double>>[
          // 第 5 點：人類主觀「標準仍過大，稍小（0.9）應為正常大小」。
          // 調整：0.9 為新標準（預設），加入 0.75 更小，最大加大至 2.0。
          MapEntry('更小', 0.75),
          MapEntry('標準', 0.9),
          MapEntry('稍大', 1.0),
          MapEntry('大', 1.15),
          MapEntry('最大', 1.3),
          MapEntry('特大', 2.0),
        ])
          ListTile(
            title: Text(entry.key),
            leading: Icon(
              _textScale == entry.value
                  ? AllIcons.radioButtonChecked
                  : AllIcons.radioButtonOff,
            ),
            onTap: () => _setTextScale(entry.value),
          ),
        const Divider(),
        ListTile(
          title: Text(S.t('主題模式'), style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final entry in const <MapEntry<String, ThemeMode>>[
          MapEntry('跟隨系統', ThemeMode.system),
          MapEntry('淺色', ThemeMode.light),
          MapEntry('深色', ThemeMode.dark),
        ])
          ListTile(
            title: Text(entry.key),
            leading: Icon(
              _themeMode == entry.value
                  ? AllIcons.radioButtonChecked
                  : AllIcons.radioButtonOff,
            ),
            onTap: () => _setThemeMode(entry.value),
          ),
      ],
    );
  }

  /// 分頁：桌布（全域聊天室背景；per-room 優先）。
  Widget _buildWallpaperTab() {
    return ListView(
      children: [
        ListTile(
          title: Text(S.t('全域聊天室背景'),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _chatWallpaper == null
                ? '未設定（聊天室長按可設定 per-room 背景，優先於此）'
                : _chatWallpaper!.startsWith('#')
                    ? '目前：${_chatWallpaper!}'
                    : '目前：${_chatWallpaper!.split('/').last}', // 文案草案
          ),
        ),
        ListTile(
          leading: Icon(AllIcons.image),
          title: Text(S.t('選相片（Your photos）')), // 草案文案
          onTap: _pickGlobalWallpaperImage,
        ),
        ListTile(
          leading: Icon(AllIcons.colorLens),
          title: Text(S.t('選顏色（Colors）')), // 草案文案
          onTap: _pickGlobalWallpaperColor,
        ),
        if (_chatWallpaper != null)
          ListTile(
            leading: Icon(AllIcons.deleteOutline),
            title: Text(S.t('重置全域背景')), // 草案文案
            onTap: _clearGlobalWallpaper,
          ),
      ],
    );
  }

  /// 分頁：字型（匯入 ttf/otf；不使用任何品牌字型）。
  Widget _buildFontTab() {
    return ListView(
      children: [
        ListTile(
          leading: Icon(AllIcons.fontDownloadOutlined),
          title: Text(
            _fontPath == null ? '未匯入字型' : '已匯入：${_fontPath!.split('/').last}',
          ),
          subtitle: Text(S.t('支援 ttf／otf；字檔僅存於本機')),
          trailing: _fontPath == null
              ? FilledButton(onPressed: _importFont, child: Text(S.t('匯入')))
              : TextButton(onPressed: _clearFont, child: Text(S.t('清除'))),
        ),
      ],
    );
  }

  /// 分頁：貼圖（匯入／我的貼圖／粒度／同步貼圖庫／貼圖建議）。
  Widget _buildStickerTab() {
    return ListView(
      children: [
        ListTile(
          title: Text(S.t('貼圖'), style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ListTile(
          title: Text(S.t('匯入貼圖圖片')),
          subtitle: Text(S.t('從相簿／檔案選取圖片作為貼圖包')),
          trailing: FilledButton(onPressed: _importSticker, child: Text(S.t('匯入'))),
        ),
        // 我的貼圖（LINE「My Stickers」；Phase 3.6 管理／排序／移除）。
        ListTile(
          title: Text(S.t('我的貼圖')),
          subtitle: Text('$_stickerCount${S.t(' 張（可排序、移除）')}'), // 草案文案
          trailing: Icon(AllIcons.chevronRight),
          onTap: () => unawaited(_openStickerManager()),
        ),
        // 貼圖包粒度（人類 2026-11-15：兩種都提供）。
        if (widget.client != null)
          SwitchListTile(
            title: Text(S.t('每張貼圖各自獨立')),
            subtitle: Text(S.t('關＝整包匯入（一個貼圖包事件）｜開＝每張貼圖各一個事件'),
            ),
            value: _packGranularity == StickerPackGranularity.perSticker,
            onChanged: (v) => unawaited(_setPackGranularity(v)),
          ),
        // 藍圖 3.11（人類決定：專用私密貼圖庫房間）→ 跨裝置共用貼圖庫。
        if (widget.client != null)
          ListTile(
            title: Text(S.t('同步貼圖庫（跨裝置）')),
            subtitle: Text(S.t('把本機貼圖包寫進「貼圖庫」私密房間（其他裝置可取得同一份）'),
            ),
            trailing: FilledButton(
              onPressed: () => unawaited(_syncStickerLibrary()),
              child: Text(S.t('同步')),
            ),
          ),
        // 匯入 zip 貼圖包（藍圖 Phase 3.2／3.3；規格見 STICKER_FORMAT.md）。
        if (widget.client != null)
          ListTile(
            title: Text(S.t('匯入貼圖包（zip）')),
            subtitle: Text(S.t('依 Homing 貼圖包格式 v1 匯入；匯入前會做安全驗證')),
            trailing: FilledButton(
              onPressed: () => unawaited(_importStickerPack()),
              child: Text(S.t('匯入')),
            ),
          ),
        // 貼圖建議（backlog #8；LINE「Display suggestions」）。
        SwitchListTile(
          title: Text(S.t('顯示貼圖建議')),
          subtitle: Text(S.t('輸入文字時，依貼圖關鍵字建議可用的貼圖')),
          value: _stickerSuggestionsEnabled,
          onChanged: (v) => unawaited(_setStickerSuggestionsEnabled(v)),
        ),
        // 第七十三批（A2-3 人類「是」）：GIF 靜態首幀開關（預設關）。
        SwitchListTile(
          title: Text(S.t('貼圖只顯示靜態首幀')),
          subtitle: Text(S.t('開啟後不播放貼圖動畫（減少動態刺激）')),
          value: _staticStickers,
          onChanged: (v) async {
            await setStaticStickers(v);
            if (mounted) setState(() => _staticStickers = v);
          },
        ),
      ],
    );
  }

  /// 分頁：主題（我的主題／主題包匯入）。
  Widget _buildThemeTab() {
    return ListView(
      children: [
        ListTile(
          title: Text(S.t('我的主題'), style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(S.t('桌布＋主題色的本機組合')),
        ),
        // 主題包匯入（zip；規格草案 THEME_FORMAT.md v1）。
        ListTile(
          title: Text(S.t('匯入主題包（zip）')),
          subtitle: Text(S.t('依 Homing 主題包格式 v1 匯入；匯入前會做安全驗證')),
          trailing: FilledButton(
            onPressed: () => unawaited(_importThemePack()),
            child: Text(S.t('匯入')),
          ),
        ),
        RadioGroup<int>(
          groupValue: _selectedThemeId ?? -1,
          onChanged: (v) {
            for (final t in _themes) {
              if (t.id == v) {
                unawaited(_applyTheme(t));
                break;
              }
            }
          },
          child: Column(
            children: [
              for (final t in _themes)
                RadioListTile<int>(
                  value: t.id,
                  secondary: a11yButton(label: S.t('刪除主題'), child: IconButton(
                    icon: Icon(AllIcons.deleteOutline),
                    tooltip: S.t('刪除主題'),
                    onPressed: () => unawaited(_deleteTheme(t)),
                  )),
                  title: Text(t.name),
                  subtitle: Text(
                    [
                      if (t.seed != null) '#${t.seed}',
                      if (t.wallpaper != null) '桌布：${t.wallpaper!.split('/').last}',
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
        ListTile(
          title: Text(S.t('建立主題（選桌布圖片）')), // 草案文案
          trailing: FilledButton(onPressed: _createTheme, child: Text(S.t('建立'))),
        ),
        const Divider(),
        // 第四十九批：主題同步到**貼圖庫房間**（與貼圖庫共用同一私密房間，
        // 使其他裝置能取得同一份主題）。事件型別為 Homing 自訂
        // （`io.github.itsxiaobai.homing.theme`；Matrix 規格無主題標準型別）。
        if (widget.client != null) ...[
          ListTile(
            title: Text(S.t('同步主題到貼圖庫房間')),
            subtitle: Text(S.t('把本機主題寫進貼圖庫私密房間（其他裝置可匯入同一份）'),
            ),
            trailing: FilledButton(
              onPressed: () => unawaited(_syncThemes()),
              child: Text(S.t('同步')),
            ),
          ),
          ListTile(
            title: Text(S.t('從貼圖庫房間匯入主題')),
            subtitle: Text(S.t('讀取貼圖庫房間內已同步的主題（同名者跳過）')),
            trailing: FilledButton(
              onPressed: () => unawaited(_importThemes()),
              child: Text(S.t('匯入')),
            ),
          ),
        ],
      ],
    );
  }

  /// 第四十九批：同步本機主題到貼圖庫房間。
  Future<void> _syncThemes() async {
    final client = widget.client;
    if (client == null) return;
    try {
      final result = await ThemeLibraryStore.syncAll(client);
      if (!mounted) return;
      await _reloadThemes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${S.t('已同步 ')}${result.themes}${S.t(' 個主題到貼圖庫房間')}'), // 草案文案
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('主題同步失敗：')}$e')), // 草案文案
      );
    }
  }

  /// 第四十九批：從貼圖庫房間匯入主題到本機。
  Future<void> _importThemes() async {
    final client = widget.client;
    if (client == null) return;
    try {
      final count = await ThemeLibraryStore.importRemoteThemes(client);
      if (!mounted) return;
      await _reloadThemes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? '沒有可匯入的新主題（同名者已略過）' // 草案文案
                : '已匯入 $count 個主題', // 草案文案
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('主題匯入失敗：')}$e')), // 草案文案
      );
    }
  }
}
