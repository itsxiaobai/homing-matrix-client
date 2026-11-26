// UI 重構（依人類 LINE_ref 標註，2026-11-01）— 輸入框右側「表情」面板。
// * emoji 為純文字符號（Unicode），非任何平台之圖示／貼圖素材；
//   未複製（也不得複製）LINE 貼圖（見人類標註「DO NOT COPY STICKER」）。
// * 貼圖 tab 僅為骨架殼：貼圖系統屬藍圖 Phase 3（貼圖包匯入，未開工）；
//   本 tab 無任何資料來源，顯示說明文字，待人類定稿後接 Phase 3。
// 草案，待人類設計定稿。
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../sticker_suggestions.dart';
import 'a11y.dart'; // 無障礙：按鈕功能說明

/// 常用 emoji（純 Unicode 文字）；怎樣的集合／順序待人類定稿。
const List<String> kRingCommonEmoji = <String>[
  '😀', '😄', '😊', '😉', '😍', '😘', '😜', '🤔',
  '😎', '😅', '😂', '🤣', '😢', '😭', '😡', '🥺',
  '😇', '🥳', '😴', '🤒', '👍', '👎', '🙏', '👏',
  '💪', '🤝', '✅', '❌', '⭐', '🌟', '🎉', '🎁',
  '❤️', '💔', '🔥', '💯', '🤗', '🤩', '🙌', '🙄',
];

/// 輸入框右側「表情」面板（草案）：
/// Tab 1「表情」＝ emoji 網格；Tab 2「貼圖」＝ 本機自訂貼圖網格。
/// 批次 III-b（人類回報「自訂貼圖無法使用」）：貼圖 tab 接上
/// AppSettings.listStickers 資料＋onStickerSelected 回呼（ChatScreen 發送）。
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, this.onEmojiSelected, this.onStickerSelected});

  final ValueChanged<String>? onEmojiSelected;

  /// 選中自訂貼圖（來源：外觀設定匯入／zip 貼圖包，AppSettings.stickers）。
  final ValueChanged<StickerLibraryEntry>? onStickerSelected;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              tabs: const [
                Tab(text: '表情'), // 文案待人類定稿
                Tab(text: '貼圖'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _EmojiGrid(onEmojiSelected: onEmojiSelected),
                _StickerPlaceholder(onStickerSelected: onStickerSelected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({this.onEmojiSelected});

  final ValueChanged<String>? onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    // 網格：不寫死寬度（由可用寬度除以固定 grid 縮排數決定），高度由 phones 安全。
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
      ),
      itemCount: kRingCommonEmoji.length,
      itemBuilder: (context, index) {
        final emoji = kRingCommonEmoji[index];
        return a11yButton(label: emoji, child: IconButton(
          tooltip: emoji,
          onPressed: () => onEmojiSelected?.call(emoji),
          icon: Text(emoji, style: const TextStyle(fontSize: 24)),
        ));
      },
    );
  }
}

/// 貼圖 tab：顯示使用者匯入的貼圖（Phase 3 骨架，資料來源為 AppSettings）。
/// 不複製任何 LINE 貼圖素材；僅顯示使用者自行匯入的圖片。
class _StickerPlaceholder extends StatefulWidget {
  const _StickerPlaceholder({this.onStickerSelected});

  final ValueChanged<StickerLibraryEntry>? onStickerSelected;

  @override
  State<_StickerPlaceholder> createState() => _StickerPlaceholderState();
}

class _StickerPlaceholderState extends State<_StickerPlaceholder> {
  List<StickerLibraryEntry> _stickers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppSettings.listStickers();
    if (mounted) setState(() { _stickers = list; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stickers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '貼圖（尚未提供）\n請至「設定 → 外觀設定」匯入貼圖圖片',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
      itemCount: _stickers.length,
      itemBuilder: (context, index) {
        final s = _stickers[index];
        // 批次 III-b：顯示貼圖本體（本機檔）＋點擊送出（回呼由 ChatScreen 接）。
        final label = stickerStem(s.name).isEmpty ? '貼圖' : stickerStem(s.name);
        return Semantics(
          button: true,
          label: '貼圖：$label',
          child: GestureDetector(
            onTap: () => widget.onStickerSelected?.call(s),
            child: Image.file(
              File(s.path),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
            ),
          ),
        );
      },
    );
  }
}
