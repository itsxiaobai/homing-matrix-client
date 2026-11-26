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
// 第六十四批②（人類：「點入圖片後可左／右滑看前一個／後一個傳送圖片」）：
// * 新增 **gallery**：`galleryEvents`（房內圖片時間序）＋`galleryInitialIndex`
//   → `PageView` 左右滑切換；`loadGalleryBytes` 為每事件的全尺寸載入縫
//   （測試注入；正式走 SDK 官方 API＋本機媒體快取）。
// * **手勢衝突的 SDK 實證**（本批 flutter 3.47.9 source）：`InteractiveViewer`
//   內建的 `ScaleGestureRecognizer` 對**單指**移動超過 pan slop 即
//   `resolve(accepted)`（gestures/scale.dart `_advanceStateMachine`），
//   `panEnabled:false` 也不影響 arena → IV 內嵌 PageView 必定吃掉左右滑。
//   → 條件式子樹：**1x（未放大）＝純 Image＋雙擊**（PageView 自由滑）；
//   **放大中＝InteractiveViewer**（縮放／平移照舊）。回到 1x 的路徑＝
//   雙擊循環（4x→1x）或 `onInteractionEnd` 時 scale≈1（捏合縮回）。
// * **1x 兩指捏合進入放大**（人類實機回饋「沒辦法兩指放大」2026-11-17）：
//   1x 頁面容器改 **RawGestureDetector**，掛自訂 [_PinchToZoomRecognizer]
//   （僅兩指才搶 arena；單指一律放行給 PageView）＋既有雙擊。第二指落下即
//   `resolve(accepted)` → `onStart` 同步切換到 IV 子樹（**外層 wrapper 存活
//   ＝同一 element／key，手勢不中斷**；批次②前版「兩把 key」的撞號根因即
//   wrapper 不存活，改為單一 wrapper 後自然消失）→ `onUpdate` 以捏合
//   focal／累積 scale（SDK 實證：accept 時 `_initialSpan` 重設，scale 自
//   1.0 起算）直接驅動 TransformationController，邊界夾取與 IV 同語意；
//   手勢結束交棒 IV（矩陣已同步，無跳動）。
// * **放大中換頁**（人類指示 2026-11-17）：放大後拖曳＝移動圖片檢視位置；
//   **拖到圖片邊界還繼續同方向滑**＝回 1x 大小並換下一張／上一張
//   （偵測＝IV 邊界夾取時 tx 不再變化而手指持續同向移動；門檻 96px 草案）。
//   放大模式的外層 wrapper 提供雙擊逐級放大／退回 1x。
// * 逐頁狀態（bytes／載入中／錯誤）以 **page index** 為鍵；貼圖限制
//   （不可下載／分享）**逐頁生效**（第五十四批既有語意不變）。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';

import '../media_cache.dart'; // 第五十七批：本機媒體快取（離線可讀・方案 A）
import '../save_location.dart'; // 2026-11-21：另存資料夾
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化

/// 全屏看圖畫面。資料只有一條來源：SDK 官方
/// `Event.downloadAndDecryptAttachment()`（加密房由 SDK 解密；App 零加密邏輯）。
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.event,
    /// 先以聊天泡泡已有的縮圖 bytes 顯示，避免重載空白（可為 null）。
    this.initialBytes,
    /// 全尺寸載入的注入縫（僅測試用；正式走 SDK 官方 API）。
    /// 回傳 null＝視同失敗（顯示提示不靜默）。**只作用於 [event]**（相容
    /// 舊測試）；gallery 其他頁走 [loadGalleryBytes]／快取路徑。
    this.loadFullBytes,
    /// 第六十四批②：房內圖片清單（時間序；可左右滑）。null／空＝單圖模式
    /// （行為與批次 F 完全一致）。
    this.galleryEvents,
    /// 第六十四批②：[event] 在 [galleryEvents] 中的 index（初始頁）。
    this.galleryInitialIndex,
    /// 第六十四批②：gallery 每事件的全尺寸載入縫（測試注入；正式路徑不傳）。
    this.loadGalleryBytes,
  });

  final Event event;
  final Uint8List? initialBytes;
  final Future<Uint8List?> Function()? loadFullBytes;
  final List<Event>? galleryEvents;
  final int? galleryInitialIndex;
  final Future<Uint8List?> Function(Event event)? loadGalleryBytes;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  /// 全部頁面（gallery；單圖模式＝[event] 一頁）。
  late final List<Event> _events;

  /// 目前頁 index（PageView 同步）。
  late int _index;

  late final PageController _pageController;

  /// 逐頁已載入 bytes（占位縮圖 → 全尺寸原始檔；鍵＝page index）。
  final Map<int, Uint8List> _bytesByIndex = {};

  /// 逐頁「全尺寸已到齊」（批次 F 語意：占位縮圖仍要**繼續**載入全尺寸；
  /// 有了才停止——不能用「已有 bytes」當完成標記，否則帶縮圖進來的頁面
  /// 永遠停在縮圖解析度）。
  final Set<int> _fullLoaded = {};

  /// 逐頁錯誤（無 bytes → 畫面中央提示；有占位 bytes → 頂部條提示）。
  final Map<int, String> _errors = {};

  /// 逐頁全尺寸載入進行中。
  final Set<int> _loading = {};

  /// 第六十四批②：是否處於**放大模式**（true＝InteractiveViewer 子樹；
  /// false＝純 Image，PageView 可左右滑）。進入＝雙擊或**兩指捏合**
  /// （[_PinchToZoomRecognizer]）；退出＝雙擊循環回 1x、捏合縮回（scale≈1）
  /// 或 `onInteractionEnd` 時 scale≈1。詳見檔頭說明。
  bool _zoomed = false;

  /// TransformationController 驅動雙擊逐級放大（1x→2x→4x→1x）。
  final _transform = TransformationController();
  double _zoomStage = 1; // 目前雙擊放大級數（1/2/4），逐級（草案）。

  /// 量測 viewer 實際 RenderBox（錨點＝viewer 中心，含 AppBar 排版偏移）。
  /// 第六十四批②（scratch 實證）：同一把 GlobalKey 掛在 1x 的 GestureDetector
  /// 與放大模式的子樹上，切換瞬間「key used by multiple widgets」→ 手勢
  /// 全失效。→ 改為**單一 wrapper**（RawGestureDetector，兩種模式共用同一
  /// element／key，僅 child 子樹切換）逐頁一把——wrapper 不因模式切換換手，
  /// 撞號情境自然消失，且捏合手勢可跨模式存活（見檔頭）。
  final Map<int, GlobalKey> _pageKeys = {};

  GlobalKey _pageKeyFor(int index) => _pageKeys[index] ??= GlobalKey();

  /// 雙擊錨點 RenderBox（＝當前頁 wrapper；兩種模式下尺寸相同＝頁面滿屏）。
  RenderBox? get _anchorBox {
    final obj = _pageKeys[_index]?.currentContext?.findRenderObject();
    if (obj is RenderBox) {
      return obj;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final gallery = widget.galleryEvents;
    _events = (gallery != null && gallery.isNotEmpty)
        ? List<Event>.unmodifiable(gallery)
        : <Event>[widget.event];
    var initial = widget.galleryInitialIndex ?? 0;
    if (initial < 0 || initial >= _events.length) {
      initial = 0;
    }
    _index = initial;
    _pageController = PageController(initialPage: initial);
    if (widget.initialBytes != null) {
      _bytesByIndex[initial] = widget.initialBytes!;
    }
    // 全尺寸載入（`_loadFull` 自行掛「載入中」標記；同步段落先執行，
    // 首幀即顯示「載入中」狀態）。
    unawaited(_loadFull(initial));
  }

  @override
  void dispose() {
    _transform.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 目前頁的事件（AppBar 標題／分享／貼圖判斷皆用它）。
  Event get _currentEvent => _events[_index];

  /// 第五十四批（2026-11-16）：目前頁是否為**貼圖**（官方 `m.sticker`）。
  /// 貼圖不提供下載／分享（著作權）——見 [_shareOrSave]；**逐頁生效**。
  bool get _isSticker => _currentEvent.type == EventTypes.Sticker;

  /// 全尺寸載入來源：注入縫優先（`loadGalleryBytes` 全頁；舊縫
  /// `loadFullBytes` 僅初始事件，相容既有測試）；正式＝SDK 官方 API＋快取。
  Future<Uint8List?> _loaderFor(Event event) {
    if (widget.loadGalleryBytes != null) {
      return widget.loadGalleryBytes!(event);
    }
    if (identical(event, widget.event) && widget.loadFullBytes != null) {
      return widget.loadFullBytes!();
    }
    // 第五十七批：先查本機媒體快取（離線可讀・方案 A）→ 未命中才下載。
    return loadMediaBytesWithCache(event);
  }

  /// 載入**全尺寸**圖片（官方 API；不帶 getThumbnail）。逐頁；重複呼叫安全。
  /// 批次 F：載入狀態全程可見（占位縮圖只是臨時畫面）。
  Future<void> _loadFull(int index) async {
    if (index < 0 || index >= _events.length) return;
    if (_loading.contains(index) || _fullLoaded.contains(index)) {
      return;
    }
    _loading.add(index);
    if (mounted) {
      setState(() {});
    }
    final event = _events[index];
    Uint8List? bytes;
    String? error;
    try {
      bytes = await _loaderFor(event);
      error = bytes == null ? '（載入回傳 null）' : null;
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading.remove(index);
      if (bytes != null) {
        _fullLoaded.add(index);
        _errors.remove(index);
        _bytesByIndex[index] = bytes;
        // 全尺寸到齊：重置縮放（縮圖占位時若被放大過，換原始檔後基準不同）。
        if (index == _index) {
          _resetZoom();
        }
      } else {
        _errors[index] = error ?? '全尺寸載入失敗'; // 文案草案
      }
    });
  }

  /// 重置到 1x（換頁／全尺寸到齊／翻頁退場時）。
  void _resetZoom() {
    _zoomStage = 1;
    _zoomed = false;
    _lastTx = null;
    _edgeOverflow = 0;
    _transform.value = Matrix4.identity();
  }

  /// 雙擊逐級放大（草案：1x→2x→4x→1x；平移拖曳不重置）。
  /// 批次 F：以 **viewer 幾何中心**為錨（原點錨會向左上放大，體感劣化；
  /// viewer ＝ AppBar 以下的全畫面，錨自真實 RenderBox 量出）。
  /// 第六十四批②：級數回 1x 時一併退出放大模式（回到可左右滑的純圖子樹）。
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
    var cx = MediaQuery.sizeOf(context).width / 2;
    var cy = MediaQuery.sizeOf(context).height / 2;
    final box = _anchorBox;
    if (box is RenderBox) {
      cx = box.size.width / 2;
      cy = box.size.height / 2;
    }
    if (next == 1) {
      setState(_resetZoom);
      return;
    }
    _zoomStage = next;
    // scale-about-point：T(c) · S(next) · T(-c)，中心點不動。
    final target = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(next, next, next, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
    // 直接套用（草案：無動畫微調；動效待人類設計定稿）。
    setState(() {
      _zoomed = true;
      _transform.value = target;
    });
  }

  /// 第六十四批②：放大模式下手勢結束 → scale 已回到 ≈1（捏合縮回）→
  /// 退出放大模式（回到可左右滑的純圖子樹）。
  void _onInteractionEnd(ScaleEndDetails _) {
    _lastTx = null;
    _edgeOverflow = 0;
    if (!_zoomed) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    if (scale <= 1.001) {
      setState(_resetZoom);
    }
  }

  // ── 第六十四批②：1x 兩指捏合進入放大（人類實機回饋 2026-11-17）──────
  // 手勢由頁面 wrapper 的 [_PinchToZoomRecognizer] 接住：第二指落下即搶下
  // arena → `onStart` 起切換到 IV 子樹（wrapper 存活，手勢不中斷）→
  // `onUpdate` 以捏合累積 scale（SDK 實證：自 1.0 起算）與「focal 固定」
  // 直接驅動 TransformationController；邊界夾取＝IV 同語意（child 覆蓋
  // viewport：tx ∈ [size·(1−s), 0]）。手勢結束交棒 IV（矩陣已同步）。

  /// 捏合級數上限（與 IV `maxScale` 相同；草案）。
  static const double _kMaxZoom = 8.0;

  /// 上一個 `onScaleUpdate` 的 focal（local 座標；focal 固定平移用）。
  Offset? _pinchFocal;

  void _onPinchStart(ScaleStartDetails details) {
    if (_zoomed) return; // 防線：enabled 已擋，不應發生。
    _pinchFocal = details.localFocalPoint;
    setState(() {
      _zoomed = true;
      _transform.value = Matrix4.identity(); // 由 1x 起步（scale 自 1.0 累積）。
    });
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    if (!_zoomed) return;
    var scale = details.scale;
    if (scale.isNaN || scale <= 0) {
      return;
    }
    scale = scale.clamp(1.0, _kMaxZoom);
    final prev = _transform.value;
    final sPrev = prev.getMaxScaleOnAxis();
    final f = details.localFocalPoint;
    final fPrev = _pinchFocal ?? f;
    _pinchFocal = f;
    // 上一刻 focal 下的 child 座標（screen = T + s·p → p = (f − T)/s）。
    final px = (fPrev.dx - prev[12]) / sPrev;
    final py = (fPrev.dy - prev[13]) / sPrev;
    var tx = f.dx - scale * px;
    var ty = f.dy - scale * py;
    // 邊界夾取（IV 同語意：s ≥ 1 時 tx/ty ∈ [size·(1−s), 0]）。
    var viewport = MediaQuery.sizeOf(context);
    final box = _anchorBox;
    if (box != null && box.hasSize) {
      viewport = box.size;
    }
    tx = tx.clamp(viewport.width * (1 - scale), 0.0);
    ty = ty.clamp(viewport.height * (1 - scale), 0.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _onPinchEnd(ScaleEndDetails _) {
    _pinchFocal = null;
    if (!_zoomed) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    if (scale <= 1.001) {
      setState(_resetZoom); // 未實際放大（誤觸兩指）：退回可滑的純圖子樹。
      return;
    }
    // 對齊雙擊循環級數（草案）：捏合倍率最近的級數，供之後雙擊續跑。
    setState(() {
      _zoomStage = scale > 3 ? 4 : 2;
    });
  }

  // ── 第六十四批②（人類指示 2026-11-17）：放大中的「到底翻頁」──────
  // 行為：放大後拖曳＝移動圖片（IV 平移，既有）；**拖到圖片邊界還繼續
  // 同方向滑**＝視為換頁意圖 → 回到 1x 大小並換下一張／上一張。
  //
  // 偵測原理（SDK 實證）：`InteractiveViewer._matrixTranslate` 在拖曳
  // **當下**就把平移夾在圖片邊界 → 邊界上 `tx` 不再變化而手指還在動。
  // → 逐次 `onInteractionUpdate` 比對 tx：手指有水平移動但 tx 不動
  // ＝累積「翻頁意圖」量；超過門檻即翻頁（草案門檻 96px）。
  //
  // 翻頁時依人類指示**回 1x**（退出放大子樹）再 animate 換頁——不是
  // 「帶著縮放換頁」。已在最前／最後一頁時維持放大（不翻）。

  /// 翻頁意圖門檻（logical px；草案，待人類設計定稿）。
  static const double _kEdgeFlipOverflow = 96;

  /// 上一次 `onInteractionUpdate` 的 tx（偵測「夾在邊界」用）。
  double? _lastTx;

  /// 本輪手勢累積的翻頁意圖量（logical px）。
  double _edgeOverflow = 0;

  void _onInteractionStart(ScaleStartDetails _) {
    _lastTx = null;
    _edgeOverflow = 0;
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (!_zoomed) return;
    // 只認**單指**拖曳（雙指捏合是在縮放，不視為翻頁意圖）。
    if (details.pointerCount != 1) {
      _edgeOverflow = 0;
      return;
    }
    final dx = details.focalPointDelta.dx;
    if (dx.abs() < 0.5) {
      return;
    }
    final tx = _transform.value[12];
    final last = _lastTx;
    _lastTx = tx;
    if (last != null && (tx - last).abs() < 0.1) {
      // 手指有水平移動但 tx 不變＝被 IV 夾在圖片邊界。
      _edgeOverflow += dx.abs();
      if (_edgeOverflow >= _kEdgeFlipOverflow) {
        _flipFromZoom(dx < 0 ? 1 : -1); // 向左滑＝下一張；向右＝上一張。
      }
    } else {
      _edgeOverflow = 0;
    }
  }

  /// 放大中「到底翻頁」：回到 1x（人類指示）並換到 [direction] 鄰頁。
  void _flipFromZoom(int direction) {
    _edgeOverflow = 0;
    _lastTx = null;
    final target = _index + direction;
    if (target < 0 || target >= _events.length) {
      return; // 已在第一張／最後一張：維持放大狀態（草案）。
    }
    setState(_resetZoom); // 回 1x＝退出放大子樹。
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// 系統分享 sheet（人類批准方案 A）：[mode] 只影響主題文字（下載／分享）。
  ///
  /// ⚠️ **第五十四批（2026-11-16）**：**貼圖（`m.sticker`）拒絕下載／分享**
  /// （著作權：貼圖包自帶授權，如 CC0-1.0，不應被匯出到 App 之外；分享會把
  /// 解密後的原始檔寫成暫存檔交給外部 App）。畫面上的下載／分享鈕亦已隱藏
  /// （見 build），此處為防線。第六十四批②：**逐頁**以當前事件判斷。
  Future<void> _shareOrSave(String modeText) async {
    final event = _currentEvent;
    if (_isSticker) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('貼圖不提供下載／分享'))), // 文案草案
        );
      }
      return;
    }
    MatrixFile loaded;
    try {
      // 第五十七批：先查本機媒體快取（離線可讀・方案 A）→ 未命中才下載。
      final cached = await loadMediaBytesWithCache(event);
      if (cached == null) {
        throw StateError('無法取得圖片');
      }
      loaded = MatrixFile(
        bytes: cached,
        name: 'homing_cached_media',
        mimeType: 'image/jpeg',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('無法取得圖片：')}$e')), // 文案草案
        );
      }
      return;
    }
    try {
      final mime = loaded.mimeType;
      final ext = mime == 'image/png' ? 'png' : 'jpg';
      final name = (event.body.isNotEmpty ? event.body : 'image')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName = name.endsWith('.$ext') ? name : '$name.$ext';
      // 2026-11-21：「下載」直接存入設定資料夾（未設定先要求選擇）；
      // 「分享」維持系統分享 sheet。
      if (modeText == '下載') {
        await _saveToConfiguredFolder(loaded.bytes, safeName, mime);
        return;
      }
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
          SnackBar(content: Text('${S.t('分享失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 2026-11-21：存入設定資料夾；未設定時先要求選擇（選完才下載）。
  Future<void> _saveToConfiguredFolder(
    Uint8List bytes,
    String name,
    String mime,
  ) async {
    final configured = await SaveLocation.isConfigured;
    if (!mounted) return;
    if (!configured) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.t('尚未設定下載位置')),
          content: Text(S.t('請先選擇一個資料夾，之後的下載會直接存入該處。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t('選擇資料夾')),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      final uri = await SaveLocation.pickFolder();
      if (uri == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.t('未選擇資料夾，已取消下載'))),
          );
        }
        return;
      }
    }
    final result = await SaveLocation.saveBytes(
      name: name,
      mime: mime,
      bytes: bytes,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? '${S.t('已存入下載位置：')}${result.name}'
                : S.t('儲存失敗'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _index;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          _currentEvent.body, // 檔名／說明；草案 UI
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          // 第六十四批②：PageView 左右滑（gallery；單圖模式僅一頁＝原行為）。
          // 批次 F 的滿屏 viewport 移到每頁內（PageView 頁面本身即滿屏）。
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _events.length,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  _resetZoom(); // 換頁重置縮放（逐頁獨立縮放；草案）。
                });
                unawaited(_loadFull(i));
              },
              itemBuilder: (context, i) => _pageContent(i),
            ),
          ),
          // 批次 F：狀態提示層（草案）——不攔手勢（IgnorePointer）。
          // 有占位 bytes 時：載入中 → spinner 提示；失敗 → 頂部條（不再靜默）。
          // 第六十四批②：只看**當前頁**。
          if (_bytesByIndex.containsKey(currentIndex) &&
              (_loading.contains(currentIndex) ||
                  _errors.containsKey(currentIndex)))
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
                    child: _loading.contains(currentIndex)
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Text(S.t('僅顯示縮圖（原始檔載入失敗）'), // 文案草案
                            style: const TextStyle(color: Colors.white70),
                          ),
                  ),
                ),
              ),
            ),
          // 底部動作列（下載／分享至外部；皆走系統 sheet，草本標註待人類設計）。
          //
          // ⚠️ **第五十四批（2026-11-16）**：**貼圖不提供下載／分享**（著作權）
          // → 貼圖時整列隱藏，改顯示一行說明（避免使用者誤以為功能壞掉）。
          // 第六十四批②：**逐頁**判斷（滑到貼圖頁即隱藏動作列）。
          if (_isSticker)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(S.t('貼圖不提供下載／分享'), // 文案草案
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filled(
                        tooltip: S.t('下載'), // 文案草案（經系統 sheet 儲存）
                        onPressed: () => _shareOrSave('下載'),
                        icon: Icon(AllIcons.download),
                      ),
                      IconButton.filled(
                        tooltip: S.t('分享至外部'), // 文案草案
                        onPressed: () => _shareOrSave('分享'),
                        icon: Icon(AllIcons.share),
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

  /// 單頁內容（第六十四批②）：無 bytes → 載入中／錯誤；有 bytes →
  /// **條件式子樹**（檔頭說明）：未放大＝純 Image（PageView 可滑）；
  /// 放大中＝InteractiveViewer（縮放／平移；左右滑被 IV 接管＝預期）。
  /// 兩種模式**共用同一 wrapper**（RawGestureDetector，雙擊＋自訂兩指捏合；
  /// 見 [_PinchToZoomRecognizer]）——wrapper 不因模式切換換手，既有
  /// 「key used by multiple widgets」撞號情境消失，且捏合可跨切換存活。
  Widget _pageContent(int index) {
    final bytes = _bytesByIndex[index];
    if (bytes == null) {
      final error = _errors[index];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            Text(
              '[圖片：無法載入] $error',
              style: const TextStyle(color: Colors.white70),
            )
          else
            const CircularProgressIndicator(),
        ],
      );
    }
    final image = Image.memory(
      bytes,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      // 第六十二批（無障礙盤點）：全屏預覽也給朗讀標籤。
      semanticLabel: S.t('圖片預覽（雙擊放大）'),
    );
    return RawGestureDetector(
      key: _pageKeyFor(index), // 雙擊／捏合錨點量測（單一 wrapper＝單把 key）。
      gestures: <Type, GestureRecognizerFactory>{
        // 雙擊逐級放大／退回 1x（兩種模式皆有效；草案）。
        DoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
          DoubleTapGestureRecognizer.new,
          (instance) => instance.onDoubleTap = _onDoubleTap,
        ),
        // 1x 兩指捏合進入放大（見檔頭；enabled gate：放大模式完全不參與）。
        _PinchToZoomRecognizer:
            GestureRecognizerFactoryWithHandlers<_PinchToZoomRecognizer>(
          () => _PinchToZoomRecognizer(enabled: () => !_zoomed),
          (instance) {
            instance
              ..onStart = _onPinchStart
              ..onUpdate = _onPinchUpdate
              ..onEnd = _onPinchEnd;
          },
        ),
      },
      child: _zoomed
          ? InteractiveViewer(
              transformationController: _transform,
              panEnabled: true, // 放大後可平移到圖片各處（逐漸填滿）
              scaleEnabled: true,
              maxScale: _kMaxZoom,
              minScale: 1.0, // 不允許縮小於 1（回 1x 即退出放大模式，見 _onInteractionEnd）
              onInteractionStart: _onInteractionStart,
              onInteractionUpdate: _onInteractionUpdate,
              onInteractionEnd: _onInteractionEnd,
              child: image,
            )
          : image,
    );
  }
}

/// 第六十四批②（人類實機回饋「1x 沒辦法兩指放大」）：**僅兩指才參與**的
/// 自訂 scale recognizer（掛在 1x 頁面 wrapper；放大模式完全不參與）。
///
/// SDK 實證（flutter 3.47.9 source）：
/// * 基底 `ScaleGestureRecognizer._advanceStateMachine` 對**單指**移動超過
///   pan slop 也會 `resolve(accepted)`（gestures/scale.dart L749）——這正是
///   IV 內嵌 PageView 卡死單指左右滑的根因 → 覆寫 [resolve] 攔下：
///   追蹤指數 <2 時不准搶 arena（PageView 拖曳照常贏）。
/// * 第二指落下即 `resolve(accepted)`（早於任何移動）→ 基底 `acceptGesture`
///   同步 `_state = started` → `onStart` 立即觸發，且 `DragStartBehavior.start`
///   下 `_initialSpan` 重設為當下 span → `ScaleUpdateDetails.scale` 自 1.0
///   起算累積（gestures/scale.dart L806-821）→ State 端直接拿來當倍率。
class _PinchToZoomRecognizer extends ScaleGestureRecognizer {
  _PinchToZoomRecognizer({required this.enabled});

  /// 回傳 false＝完全不參與 arena（放大模式：捏合／平移交 IV 接管）。
  final bool Function() enabled;

  final Set<int> _pointers = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!enabled()) {
      return;
    }
    _pointers.add(event.pointer);
    super.addAllowedPointer(event);
    if (_pointers.length >= 2) {
      resolve(GestureDisposition.accepted); // 兩指即搶 arena（早於任何移動）。
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  /// 單指不准搶 arena（PageView 左右滑優先）；放行其餘 disposition。
  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && _pointers.length < 2) {
      return;
    }
    super.resolve(disposition);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}
