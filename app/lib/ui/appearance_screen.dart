// 批次 C（人類指示 2026-11-01）— 外觀設定（草案，待人類設計定稿）。
// 主題種子色、字型匯入、聊天室背景由 AppSettings (sqflite) 儲存。
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:homing/main.dart'
    show
        applyRingFontFromPath,
        kSettingUseDynamicColor,
        ringFontFamily,
        ringSeedColor,
        ringTextScale,
        ringThemeMode,
        ringUseDynamicColor;

import '../app_settings.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setSeedColor(String hex) async {
    await AppSettings.set('theme_seed_color', hex);
    setState(() => _seedColor = hex);
    // Suggestion #4：即時套用（官方 ValueNotifier 通道，同 ringTextScale）。
    ringSeedColor.value = hex;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('種子色已更新')), // 草案文案
      );
    }
  }

  /// 批次第 6 點：自訂主題色十六進位輸入。
  Future<void> _askCustomColor() async {
    final controller = TextEditingController(text: _seedColor ?? '');
    final hex = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自訂主題色'), // 文案草案
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('套用'), // 文案草案
          ),
        ],
      ),
    );
    if (hex == null || hex.isEmpty || !mounted) return;
    final clean = hex.replaceFirst('#', '');
    if (int.tryParse(clean, radix: 16) == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('顏色格式錯誤')), // 文案草案
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
        SnackBar(content: Text('已匯入 ${result.length} 張貼圖')), // 草案文案
      );
    }
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
        title: const Text('建立主題'), // 草案文案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('桌布：${result.first.name}'), // 草案文案
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('建立'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await AppSettings.addTheme(name, seed: _seedColor, wallpaper: result.first.path);
    await _reloadThemes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已建立主題（尚未套用）')), // 草案文案
      );
    }
  }

  /// 批次十二①：套用主題＝記錄選中＋套用種子色＋套用／保留全域桌布。
  /// 無桌布的主題不會清掉現有桌布（v0 行為披露，見 THEME_FORMAT.md）。
  Future<void> _applyTheme(
    ({int id, String name, String? seed, String? wallpaper}) theme,
  ) async {
    await AppSettings.set('selected_theme_id', theme.id.toString());
    if (theme.seed != null) {
      await _setSeedColor(theme.seed!);
    }
    if (theme.wallpaper != null) {
      await AppSettings.setChatWallpaper(theme.wallpaper!);
    }
    if (mounted) {
      setState(() => _selectedThemeId = theme.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已套用主題「${theme.name}」')), // 草案文案
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
        const SnackBar(content: Text('已設定全域聊天室桌布')), // 草案文案
      );
    }
  }

  Future<void> _pickGlobalWallpaperColor() async {
    final color = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('選擇桌布顏色'), // 草案文案
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('外觀設定')), // 草案文案
      body: ListView(
        children: [
          const ListTile(title: Text('主題種子色', style: TextStyle(fontWeight: FontWeight.bold))),
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
            leading: const Icon(Icons.color_lens_outlined),
            title: const Text('自訂主題色（十六進位）'), // 文案草案
            subtitle: Text(
              _seedColor != null ? '#$_seedColor' : '使用預設蜜桃色',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => unawaited(_askCustomColor()),
            ),
          ),
          const Divider(),
          const ListTile(title: Text('字型', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            title: Text(_fontPath == null ? '未匯入字型' : '已匯入：${_fontPath!.split('/').last}'),
            trailing: _fontPath == null
                ? FilledButton(onPressed: _importFont, child: const Text('匯入 ttf/otf'))
                : TextButton(onPressed: _clearFont, child: const Text('清除')),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('跟隨 Android 桌布配色'), // 文案草案，待人類設計定稿
            subtitle: const Text('關閉＝固定使用 Homing 主色（預設）'), // 草案文案
            value: _useDynamic,
            onChanged: (v) => unawaited(_setUseDynamic(v)),
          ),
          const Divider(),
          const ListTile(
            title: Text('文字大小', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('草案（人類設計定稿後調整）'),
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
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () => _setTextScale(entry.value),
            ),
          const Divider(),
          const ListTile(
            title: Text('主題模式', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('草案（人類設計定稿後調整）'),
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
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              onTap: () => _setThemeMode(entry.value),
            ),
          const Divider(),
          ListTile(title: Text('貼圖', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            title: const Text('匯入貼圖圖片'),
            subtitle: const Text('從相簿／檔案選取圖片作為貼圖包（Phase 3 草案）'),
            trailing: FilledButton(onPressed: _importSticker, child: const Text('匯入')),
          ),
          const Divider(),
          // 批次十二①：我的主題（創作者主題 v0＝桌布＋種子色本機組合；
          // zip 打包格式見 THEME_FORMAT.md，需 archive 依賴待批准）。
          const ListTile(
            title: Text('我的主題', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('桌布＋主題色的本機組合（草案；zip 主題包待相依套件批准）'),
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
                    secondary: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => unawaited(_deleteTheme(t)),
                    ),
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
            title: const Text('建立主題（選桌布圖片）'), // 草案文案
            trailing: FilledButton(onPressed: _createTheme, child: const Text('建立')),
          ),
          const Divider(),
          // 批次十二①：全域聊天室桌布（替換批次 C 的靜態說明行）。
          ListTile(
            title: Text(
              '全域聊天室背景',
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
            leading: const Icon(Icons.image),
            title: const Text('選相片（Your photos）'), // 文案草案
            onTap: _pickGlobalWallpaperImage,
          ),
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text('選顏色（Colors）'), // 文案草案
            onTap: _pickGlobalWallpaperColor,
          ),
          if (_chatWallpaper != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('重置全域背景'), // 草案文案
              onTap: _clearGlobalWallpaper,
            ),
        ],
      ),
    );
  }
}
