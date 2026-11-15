// 批次 D/E/F（人類指示 2026-11-01）：圖片全屏預覽（點擊聊天泡泡圖片）。
// 全部 UI 為**草案，待人類設計定稿**：黑色全屏 + InteractiveViewer 縮放＋
// 雙擊逐級放大（1x→2x→4x→1x，以螢幕中心為錨逐級填滿）＋「下載／分享至外部」
// 分列，兩者皆走系統分享 sheet（人類 2026-11-01 批准方案 A；sheet 內建
// 「儲存到相册／檔案」目標；`XFile.fromData` 記憶體分享，App 不落本地檔）。
// 批次 F（人類回饋：放大後被原始解析度限制）：
// * viewport 由 Center→**Positioned.fill**（constrained:true 的
//   InteractiveViewer 不自擴展，Center 松約束時 viewport＝Image 原生尺寸
//   → 以原始解析度為基準；滿屏 viewport 一律 contain 填螢幕）。
// * 聊天磚帶入的占位 bytes 是**縮圖**；全尺寸（SDK 官方 API，無 getThumbnail）
//   載入較慢或失敗時，先前會**靜默**停在縮圖解析度 → 現在：載入中顯示提示、
//   成功後重置縮放換上全尺寸、失敗顯示提示（不再靜默；占位仍可基本放大瀏覽）。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';

/// 全屏看圖畫面。資料只有一條來源：SDK 官方
/// `Event.downloadAndDecryptAttachment()`（加密房由 SDK 解密；App 零加密邏輯）。
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.event,
    /// 先以聊天泡泡已有的縮圖 bytes 顯示，避免重載空白（可為 null）。
    this.initialBytes,
    /// 全尺寸載入的注入縫（僅測試用；正式走 SDK 官方 API）。
    /// 回傳 null＝視同失敗（顯示提示不靜默）。
    this.loadFullBytes,
  });

  final Event event;
  final Uint8List? initialBytes;
  final Future<Uint8List?> Function()? loadFullBytes;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  /// 目前顯示的 bytes（占位縮圖 → 全尺寸原始檔）。
  Uint8List? _bytes;

  /// 錯誤：無 bytes → 畫面中央提示；有占位 bytes → 頂部條提示（不再靜默）。
  String? _error;

  /// 全尺寸載入進行中（占位縮圖時顯示提示，讓使用者知道正在換上原始檔）。
  bool _fullBusy = false;

  /// TransformationController 驅動雙擊逐級放大（1x→2x→4x→1x）。
  final _transform = TransformationController();
  double _zoomStage = 1; // 目前雙擊放大級數（1/2/4），逐級（草案）。

  /// 量測 viewer 實際 RenderBox（錨點＝viewer 中心，含 AppBar 排版偏移）。
  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    // 初 build 前直接設欄位（initState 內不用 setState）；首幀即可見「載入中」。
    _fullBusy = true;
    unawaited(_loadFull());
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// 載入**全尺寸**圖片（官方 API；不帶 getThumbnail）。
  /// 批次 F：載入狀態全程可見（占位縮圖只是臨時畫面）。
  /// `_fullBusy` 已於 initState 直接設 true（避免 initState 內 setState）。
  Future<void> _loadFull() async {
    Uint8List? bytes;
    String? error;
    try {
      if (widget.loadFullBytes != null) {
        bytes = await widget.loadFullBytes!();
        error = bytes == null ? '（測試注入回傳 null）' : null;
      } else {
        bytes = (await widget.event.downloadAndDecryptAttachment()).bytes;
      }
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _fullBusy = false;
      if (bytes != null) {
        _error = null;
        _bytes = bytes;
        // 全尺寸到齊：重置縮放（縮圖占位時若被放大過，換原始檔後基準不同）。
        _zoomStage = 1;
        _transform.value = Matrix4.identity();
      } else {
        _error = error ?? '全尺寸載入失敗'; // 文案草案
      }
    });
  }

  /// 雙擊逐級放大（草案：1x→2x→4x→1x；平移拖曳不重置）。
  /// 批次 F：以 **viewer 幾何中心**為錨（原點錨會向左上放大，體感劣化；
  /// viewer ＝ AppBar 以下的全畫面，錨自真實 RenderBox 量出）。
  void _onDoubleTap() {
    double next;
    switch (_zoomStage) {
      case 1:
        next = 2;
      case 2:
        next = 4;
      default:
        next = 1;
    }
    _zoomStage = next;
    var cx = MediaQuery.sizeOf(context).width / 2;
    var cy = MediaQuery.sizeOf(context).height / 2;
    final box = _viewerKey.currentContext?.findRenderObject();
    if (box is RenderBox) {
      cx = box.size.width / 2;
      cy = box.size.height / 2;
    }
    // scale-about-point：T(c) · S(next) · T(-c)，中心點不動。
    final target = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(next, next, next, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
    // 直接套用（草案：無動畫微調；動效待人類設計定稿）。
    _transform.value = target;
  }

  /// 系統分享 sheet（人類批准方案 A）：[mode] 只影響主題文字（下載／分享）。
  Future<void> _shareOrSave(String modeText) async {
    MatrixFile loaded;
    try {
      loaded = await widget.event.downloadAndDecryptAttachment();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法取得圖片：$e')), // 文案草案
        );
      }
      return;
    }
    try {
      final mime = loaded.mimeType;
      final ext = mime == 'image/png' ? 'png' : 'jpg';
      final name = (widget.event.body.isNotEmpty ? widget.event.body : 'image')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName = name.endsWith('.$ext') ? name : '$name.$ext';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              loaded.bytes,
              name: safeName,
              mimeType: mime,
            ),
          ],
          // 文案草案：下載引導使用者選「儲存」目標。
          text: modeText == '下載'
              ? '請選擇相冊／檔案 app 以儲存圖片'
              : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失敗：$e')), // 文案草案
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          widget.event.body, // 檔名／說明；草案 UI
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          // 批次 F：滿屏 viewport（Positioned.fill 給緊約束 → 子 widget 恰為
          // 螢幕大小；1x 一律 contain 填螢幕，放大不再受原生尺寸基準影響）。
          Positioned.fill(
            child: _bytes != null
                ? GestureDetector(
                    onDoubleTap: _onDoubleTap, // 雙擊逐級放大（草案）
                    child: InteractiveViewer(
                      key: _viewerKey,
                      transformationController: _transform,
                      panEnabled: true, // 放大後可平移到圖片各處（逐漸填滿）
                      maxScale: 8.0,
                      child: Image.memory(
                        _bytes!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null)
                        Text(
                          '[圖片：無法載入] $_error',
                          style: const TextStyle(color: Colors.white70),
                        )
                      else
                        const CircularProgressIndicator(),
                    ],
                  ),
          ),
          // 批次 F：狀態提示層（草案）——不攔手勢（IgnorePointer）。
          // 有占位 bytes 時：載入中 → spinner 提示；失敗 → 頂部條（不再靜默）。
          if (_bytes != null && (_fullBusy || _error != null))
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _fullBusy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Text(
                            '僅顯示縮圖（原始檔載入失敗）', // 文案草案
                            style: const TextStyle(color: Colors.white70),
                          ),
                  ),
                ),
              ),
            ),
          // 底部動作列（下載／分享至外部；皆走系統 sheet，草本標註待人類設計）。
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      tooltip: '下載', // 文案草案（經系統 sheet 儲存）
                      onPressed: () => _shareOrSave('下載'),
                      icon: const Icon(Icons.download),
                    ),
                    IconButton.filled(
                      tooltip: '分享至外部', // 文案草案
                      onPressed: () => _shareOrSave('分享'),
                      icon: const Icon(Icons.share),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
