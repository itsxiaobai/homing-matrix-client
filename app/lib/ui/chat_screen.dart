// 任務：Phase 1 / 1.4 — 一對一訊息骨架（草案，待人類設計）
// 依 AGENTS.md UI 規則：無樣式／最小樣式、不寫死寬度、文案與版面待定稿。
// 2026-10-31（人類批准）：加入圖片渲染（SDK 官方媒體 API）與未解密事件占位；
// 2026-11-01（2.8 bugfix）：圖片／影片上傳改用背景 isolate 預處理（SDK 官方 API），
//   並顯示「上傳中」進度橫幅；單檔大小上限改由伺服器 m.upload.size 回報判斷
//   （matrix.org 有限制→檢查；self-host 無設定→不限制）。
// 2026-11-01（UI 重構，人類 LINE_ref 標註）：LINE 版位—泡＋頭像＋時間戳、
//   日期分隔、「已讀」（SDK 官方 receipts，僅顯示既有資料）、
//   底部輸入列 ＋／相機(image_picker，人類批准)／圖片／輸入框(表情)／mic( disabled，
//   語音訊息不在藍圖)；滑到底鈕；頂列＝返回＋標題＋搜尋＋選單（通話／行事曆不做：
//   VoIP 未進藍圖）。
//
// 2026-11-01（批次 E，人類 4 項回饋；依賴與方向經 question 批准）：
//   頭像顯示（房間 m.room.member state 的 avatar_url，Room.getState 純記憶體）、
//   長按訊息動作（反應/回覆/複製/檢舉/分享至外部）＋左右滑動以回覆、
//   投票接收 dual 讀 stable m.poll.*＋unstable（lib/poll_compat.dart）、
//   Homing 端結束投票補 org.matrix.msc1767.text fallback（Element X 行為待實機複測）。
// ⚠️ 加密邊界（依 AGENTS.md，人類決定 2026-10-31：加密協議採 Matrix 官方機制）：
// * 本檔**不寫任何加密／金鑰程式碼**。訊息送出一律呼叫 SDK 的
//   `Room.sendTextEvent`；房間為加密房時，SDK 依 Matrix 官方規格
//   （vodozemac／Megolm）自動加密，App 端不介入。
// * 金鑰備份／裝置驗證屬任務 1.5，本檔不處理。
import 'dart:async';
import 'dart:convert' show JsonEncoder;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';

import '../app_settings.dart';
import '../chat_layout.dart';
import '../media_upload.dart';
import '../message_content.dart'; // 第三十五批 #5：無聲傳送旗標＋content 組裝
import '../missing_key_repair.dart'; // 解密案修法 #2（人類批准 2026-11-13）
import '../markdown_message.dart'; // 第三十五批 #13：Markdown 送出／#14 收訊渲染
import '../message_edits.dart'; // 第四十二批：編輯解析（E2EE 房間亦適用）
import '../offline_queue.dart';
import '../poll_compat.dart';
import '../sticker_suggestions.dart'; // 貼圖關鍵字聯想（backlog #8；純邏輯）
import '../voip/call_manager.dart';
import 'block_user_screen.dart';
import 'call_screen.dart';
import 'emoji_panel.dart';
import 'group_call_screen.dart';
import 'image_preview_screen.dart';
import 'livekit_call_screen.dart';
import 'poll_create_screen.dart';
import 'group_chat_manage_screen.dart';
import 'message_search_screen.dart';
import 'report_user_screen.dart';
import 'room_info_screen.dart'; // 批次十二③
import 'announcement_banner.dart'; // 第四十六批：一般公告橫幅（中性色）
import 'sticker_manager_screen.dart' show kStickerPreviewKey; // 第四十六批：貼圖預覽開關
import 'time_format.dart';

/// 訊息的展示資料（與 SDK Event 解耦，供 widget 測試注入）。
class ChatMessageView {
  const ChatMessageView({
    required this.sender,
    required this.body,
    this.sentAt,
    this.eventId,
    this.formattedBody,
    this.isImage = false,
    this.isSticker = false,
    this.isLocation = false,
    this.isPoll = false,
    // 第二十二批（LINE_ref chat 稿）：通話事件（官方 m.call.invite）以 chip 渲染。
    this.isCallInvite = false,
    // 第二十四批：訊息曾被編輯（官方 m.replace 聚合；送出方 SDK helper）。
    this.isEdited = false,
    // 第四十五批：回覆引言（官方 m.in_reply_to 指到的被回覆訊息）。
    // 兩個欄位皆可為 null（＝非回覆訊息，或被回覆的訊息不在本機 timeline）。
    this.replyToSender,
    this.replyToBody,
    this.event,
  });

  final String sender;
  final String body;
  final DateTime? sentAt;

  /// 最後（最新）訊息的事件 ID；用於已讀標記。可為 null（例如測試注入）。
  final String? eventId;

  /// 該訊息是否為圖片附件（m.image）。
  final bool isImage;

  /// 批次 III-a：該訊息是否為自訂貼圖（官方 `m.sticker` 事件；人類已確認）。
  final bool isSticker;

  /// 批次 III-c：該訊息是否為位置分享（官方 msgtype `m.location`）。
  final bool isLocation;

  /// 該訊息是否為**投票開始事件**（SDK msc_3381_polls 的 startType）。
  /// 批次 D：投票卡片（草案）。
  final bool isPoll;

  /// 第二十二批：該訊息是否為通話事件（官方 `m.call.invite`；Suggestion #8
  /// 既有語意）→ 以 chip 樣式渲染（LINE_ref chat calls_history 構圖）。
  final bool isCallInvite;

  /// 第二十四批：訊息是否曾被編輯（官方 `m.replace` 聚合判定；顯示
  /// 「(已編輯)」記號——僅純文字列，Element X 同款語意）。
  final bool isEdited;

  /// 已套用編輯後的 HTML 內容（`formatted_body`）；無則 null。
  /// 第四十二批：編輯後的 Markdown 也要能正確渲染。
  final String? formattedBody;

  /// 第四十五批：被回覆訊息的寄送者（顯示名稱；查無 member 時為 Matrix ID）。
  /// null ＝ 本訊息不是回覆（或被回覆的訊息不在本機已載入的 timeline 中）。
  final String? replyToSender;

  /// 第四十五批：被回覆訊息的內容摘要（單行截斷於載入時）。
  final String? replyToBody;

  /// 原始 SDK 事件（僅 SDK 來源訊息；測試注入可為 null）。
  /// 此欄位僅供**官方媒體 API**（`Event.downloadAndDecryptAttachment`）與
  /// **官方 receipts**（`Event.receipts`）使用；本檔不寫任何加密／解密邏輯，
  /// 附件解密由 SDK 官方路徑處理。
  final Event? event;
}

/// 載入訊息的抽象（供測試注入；預設從 SDK Timeline 取文字訊息）。
typedef ChatMessagesLoader = Future<List<ChatMessageView>> Function(Room room);

/// 送出動作的 429 退避重試（人類批准 2026-11-06「上傳 429 退避重試」）。
///
/// 背景：matrix.org 限流（429 M_LIMIT_EXCEEDED）常見；SDK 一次拋
/// `MatrixException` 即棄，使用者看到「失敗」但其實只差等一下。
///
/// 只對 **M_LIMIT_EXCEEDED**（伺服器明確拒絕＝事件未落地）重試，重試
/// **不會造成重複訊息**；逾時／斷網等其他錯誤的請求可能已經受理，一律
/// 直接回拋（寧可明確失敗也不冒重複風險）。
/// 退避：優先伺服器 `retry_after_ms`（封頂 15s）；缺值時 1s→2s→4s。
/// 測試注入 [delay] 為同步完成即可不等待真實時間。
const int kRingSendRateLimitAttempts = 3;

Future<T> sendWithRateLimitRetry<T>(
  Future<T> Function() op, {
  int attempts = kRingSendRateLimitAttempts,
  Future<void> Function(Duration) delay = Future<void>.delayed,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      return await op();
    } on MatrixException catch (e) {
      if (e.error != MatrixError.M_LIMIT_EXCEEDED ||
          attempt + 1 >= attempts) {
        rethrow;
      }
      final retryAfterMs = e.retryAfterMs;
      final backoff = retryAfterMs != null && retryAfterMs > 0
          ? Duration(milliseconds: retryAfterMs.clamp(0, 15000))
          : Duration(milliseconds: 1000 << attempt);
      await delay(backoff);
    }
  }
  throw StateError('unreachable'); // 迴圈必在 return 或 rethrow 結束。
}

/// 聊天室背景選色對話框的結果（人類回報 bug 修正）：`color` 為 null
/// 代表選了「預設」（清自訂背景）；外層 `showDialog` 回 null 則是取消，
/// 不得動現有背景。
class _BgColorSelection {
  const _BgColorSelection({this.color});
  final Color? color;
}

/// 送出訊息的抽象（供測試注入；預設 `Room.sendTextEvent`，加密由 SDK 處理）。
typedef ChatMessageSender = Future<void> Function(Room room, String text);

/// 第三十五批 #5＋#13：帶選項送出的抽象（無聲／Markdown；測試注入用）。
/// 實作＝`Room.sendEvent(buildTextMessageContent(...))`（SDK 官方 sendEvent，
/// 回覆經官方 `inReplyTo` 參數）。
typedef ChatRichSender = Future<void> Function(
  Room room,
  String text, {
  bool silent,
  String? formattedBody,
});

/// 已讀標記的抽象（供測試注入；預設呼叫 `Room.setReadMarker`）。
/// read receipts 規則：sentAt 之後只考慮最新一條文字訊息。
/// 注意：本任務（1.6）僅提供 skeleton（標記 read marker），不做多裝置 reconciliation。
typedef ChatMessageReader = Future<void> Function(Room room, ChatMessageView message);

/// 解密案修法 #2：向其他裝置請求缺失金鑰的抽象（供測試注入）。
/// 預設實作＝`missing_key_repair.dart` 的官方 API 流程（maybeAutoRequest，
/// 允許退回 to-device 請求）；回傳請求的 session 數。
typedef MissingKeyRepairAction = Future<int> Function(Room room);

/// 相機拍照抽象（供測試注入；預設 image_picker 系統相機）。
typedef CameraPicker = Future<XFile?> Function();

/// 貼圖庫載入抽象（供測試注入；預設＝本機 `app_settings.db` 的貼圖庫）。
typedef StickerLibraryLoader = Future<List<StickerLibraryEntry>> Function();

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.room,
    this.loadMessages,
    this.sendMessage,
    this.sendRichMessage,
    this.markRead,
    this.pickCamera,
    this.callManager,
    this.requestMissingKeys,
    this.stickerLibraryLoader,
  });

  final Room room;
  final ChatMessagesLoader? loadMessages;
  final ChatMessageSender? sendMessage;

  /// 第三十五批 #5＋#13：無聲／Markdown 送出抽象（預設走真實 SDK 路徑）。
  final ChatRichSender? sendRichMessage;
  final ChatMessageReader? markRead;
  final CameraPicker? pickCamera;

  /// 通話管理（P2.15 提案）。非 null 且 isSupported 時，頂列顯示通話鈕。
  /// 測試可注入 null（預設）以避免初始化 WebRTC 平台層。
  final CallManager? callManager;

  /// 解密案修法 #2：向其他裝置請求缺失金鑰（預設＝官方 API 流程；
  /// 測試注入 fake）。僅加密房間顯示入口。
  final MissingKeyRepairAction? requestMissingKeys;

  /// 貼圖關鍵字聯想（backlog #8）的貼圖庫來源（預設＝本機貼圖庫）。
  /// 測試可注入 fake 貼圖庫。
  final StickerLibraryLoader? stickerLibraryLoader;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  /// P2.15：通話入口可用（注入 manager 且初始化成功且一對一聊天）。
  bool get _callsAvailable =>
      widget.callManager != null && widget.room.isDirectChat;

  /// 撥打進行中（避免重複點按）。
  bool _calling = false;

  /// 聊天室背景（hex 色碼；null = 預設）。
  String? _roomBackground;

  /// 批次十二⑤（Phase 4.1 草案）：官方釘選最新訊息 → 公告橫幅。
  /// 資料來源＝`Room.pinnedEventIds`（SDK room.dart L185，官方 getter）＋
  /// `Room.getEventById`（room.dart L2225，官方 API）；後續收合等行為待人類定稿。
  String? _pinnedBannerEventId;
  String? _pinnedBannerBody;
  String? _pinnedBannerSender;

  /// 訊息列錨點（橫幅點擊→官方 Scrollable.ensureVisible 跳轉用）。
  final Map<String, GlobalKey> _rowKeys = {};

  /// 貼圖關鍵字聯想（backlog #8；人類 2026-11-03 目標 #8）。
  /// 目前輸入內容對應的建議貼圖——**只存在記憶體**，不持久化輸入內容。
  List<StickerSuggestion> _stickerSuggestions = const [];

  /// 已查過官方 relations（編輯）的事件 id —— 每個事件只查一次，
  /// 避免每次重載都對同一批訊息發請求（第四十二批效能修正）。
  final Set<String> _editRelationsChecked = <String>{};

  /// 貼圖庫快取（記憶體；僅本機貼圖庫，與輸入內容無關）。
  List<StickerLibraryEntry> _stickerLibrary = const [];
  bool _stickerLibraryLoaded = false;

  /// 貼圖建議開關（kv `sticker_suggestions_enabled`，預設開）。
  /// 對應 LINE 貼圖設定頁的「Display suggestions（顯示建議）」開關
  /// （參考 `LINE_ref/new_ref/settings/stickers/Screenshot_20261104-173855_labeled.png`）。
  bool _stickerSuggestionsEnabled = true;

  /// 讀取貼圖建議開關（本機 kv；失敗維持預設值，不阻擋輸入）。
  Future<void> _loadStickerSuggestionSetting() async {
    try {
      final v = await AppSettings.get('sticker_suggestions_enabled');
      if (!mounted) return;
      if (v != null) {
        setState(() => _stickerSuggestionsEnabled = v != '0');
      }
    } catch (_) {
      // 讀取失敗 → 維持預設（顯示建議）。
    }
  }

  /// 載入貼圖庫（預設＝本機 `app_settings.db`；測試可注入 fake）。
  Future<List<StickerLibraryEntry>> _loadStickerLibrary() async {
    if (_stickerLibraryLoaded) return _stickerLibrary;
    try {
      final loader = widget.stickerLibraryLoader ?? AppSettings.listStickers;
      _stickerLibrary = await loader();
    } catch (_) {
      // 讀取失敗（DB 未就緒／測試環境）→ 不建議，不阻擋輸入。
      _stickerLibrary = const [];
    }
    _stickerLibraryLoaded = true;
    return _stickerLibrary;
  }

  /// 依目前輸入內容更新建議貼圖（backlog #8）。
  /// 輸入內容僅用於本次比對，**不寫入任何儲存空間、不記錄、不上傳**。
  Future<void> _updateStickerSuggestions() async {
    final text = _inputController.text;
    if (text.trim().isEmpty || !_stickerSuggestionsEnabled) {
      if (_stickerSuggestions.isNotEmpty) {
        setState(() => _stickerSuggestions = const []);
      }
      return;
    }
    final library = await _loadStickerLibrary();
    if (!mounted) return;
    final next = suggestStickers(text: text, library: library);
    final unchanged = next.length == _stickerSuggestions.length &&
        List<int>.generate(next.length, (i) => i)
            .every((i) => next[i].entry.id == _stickerSuggestions[i].entry.id);
    if (unchanged) return;
    setState(() => _stickerSuggestions = next);
  }


  List<ChatMessageView> _messages = const [];
  String? _message; // 錯誤訊息
  bool _loading = true;
  bool _sending = false;
  bool _initialLoadDone = false; // 第 22 點：追蹤是否已完成初始載入（避免定時 _load 把用戶趕回底部）
  bool _hasUnread = false; // 第 8 點：追蹤聊天室是否有未讀訊息

  /// 批次 D：訊息 timeline（**複用同一實例**，不再每次 _load 重建——
  /// SDK Timeline 保留已抓的歷史窗口；重複 `room.getTimeline()` 亦會多次訂閱）。
  /// 僅在預設 loader（無注入）時使用；測試注入 loader 不建立。
  Timeline? _timeline;

  /// 「載入更早訊息」進行中（批次 D：歷史訊息分頁；手動按鈕觸發，非無限滾動）。
  bool _historyLoading = false;

  /// 第 4 點：「已沒有更早的訊息」提示節流（5 秒內不重複洗 SnackBar）。
  DateTime? _lastNoMoreHistoryShown;

  /// 進房後「訊息過少 → 主動補抓歷史」只做一次（session 內防洗版）。
  bool _autoHistoryAsked = false;

  /// 批次 E：正在回覆的訊息（滑動／長按選單進入；null = 一般輸入）。
  ChatMessageView? _replyTo;

  // ── 第四十八批：訊息批次操作（多選）────────────────────────────────
  /// 多選模式是否開啟。
  bool _selectMode = false;

  /// 多選模式下已選取的訊息（依 event id；測試注入無 id 者以物件身份比對）。
  final Set<String> _selectedEventIds = {};

  /// 多選模式下已選取、但沒有 event id 的訊息（測試注入路徑）。
  final List<ChatMessageView> _selectedWithoutId = [];

  /// 已選取訊息數（批次列的計數）。
  int get _selectedCount =>
      _selectedEventIds.length + _selectedWithoutId.length;

  /// 第三十五批 #5：無聲傳送（本則送出不觸發收訊端 Homing 通知）。
  /// 送出後自動復位（無聲是例外動作；LINE「沉靜傳訊」同款逐次概念，草案）。
  bool _silentSend = false;

  /// 第三十五批 #13：Markdown 送出開關（kv `markdown_enabled`，預設**關**
  /// ＝使用者自行選擇開啟；偏好即時生效不重啟）。
  bool _markdownOn = false;

  /// 第二十四批：正在編輯的訊息（長按選單進入；null = 一般輸入）。
  /// 送出＝官方 `Room.sendTextEvent(editEventId:)`（SDK 編輯 helper）。
  ChatMessageView? _editTarget;

  // 第二十四批：typing 指示（官方 `Room.setTyping`／`Room.typingUsers`）。
  // SDK `Room.setEphemeral` 對 m.typing 有內建超時清空（room.dart
  // _clearTypingIndicatorTimer），該清空**不會**再觸發 onSync → 本地另掛
  // ticker 每 4 秒複驗。發送節流：7 秒內不重複送（server timeout 10s）。
  DateTime? _lastTypingSentAt;
  String? _lastTypingSummary;
  Timer? _typingTicker;

  // UI 重構：表情面板開關。
  bool _emojiOpen = false;

  // UI 重構：可捲動列表是否距底部遠（→ 顯示「滑到底」鈕）。
  bool _showScrollDown = false;

  // 2.8 bugfix：上傳狀態（背景 isolate 預處理 + 上傳）進度橫幅。
  bool _uploading = false;
  int _uploadIndex = 0;
  int _uploadTotal = 0;
  String _uploadName = '';
  String _uploadStage = '';
  DateTime? _uploadStartedAt;
  Duration _uploadElapsed = Duration.zero;
  Timer? _uploadTimer;
  int _batchOk = 0;
  int _batchTooBig = 0;
  int _batchFail = 0;

  /// 最後一個失敗附件的真實錯誤（429 限流／逾時等）；
  /// 過去一律「N 個失敗」看不到原因，人類回報「有時無法傳送圖片」修復。
  String? _batchFailReason;

  // ── 人類回報 2026-11-06 修復四項（批准批次）────────────────────────
  /// 上傳佔位卡的本地預覽（選圖／相機時已取得的原始 bytes 的縮小版；
  /// null＝非圖片附件或尚未取得）。零額外讀檔：僅重用選檔階段的 bytes。
  Uint8List? _uploadPreviewBytes;

  /// 佔位卡進度（0.0–1.0）＝階段權重（SDK uploadContent 為單次 POST、
  /// 官方 API 無 byte 級 onProgress → 以階段近似；draft 樣式）。
  double _uploadProgress = 0;

  /// 送信序列鏈（人類回報「同時傳圖＋傳文字，文字應排在佇列」）：
  /// 文字與附件都經 `_chainTask` 排隊逐一執行；_chainTail 保證 FIFO。
  Future<void> _chainTail = Future<void>.value();

  /// Homing 自查的上傳上限快取（4a）：每個 ChatScreen 生命週期一次；
  /// 避免 SDK 內部 `uploadContent` 的 `getConfig()` 之外再多一個 roundtrip。
  int? _serverUploadLimitCache;
  bool _serverUploadLimitKnown = false;

  /// 圖片縮圖的官方載入（Event.downloadAndDecryptAttachment）快取：
  /// 以 eventId 為鍵；future 只建立一次，tile 重建不重抓。
  final Map<String, Future<MatrixFile?>> _imageLoaders = {};

  StreamSubscription<dynamic>? _syncSub;
  Timer? _reloadTimer;
  String? _lastReadEventId;
  String? _lastRoomEventId;

  /// 已讀 receipt 摘要（Suggestion #9「都沒有看到」根因修正：ephemeral
  /// receipt 不改 lastEvent → 以前永不觸發重畫）。以官方 `Room.receiptState`
  /// 的 global receipts 建構「誰→讀到哪一則」字串；null＝尚未進行過比對。
  String? _lastReceiptSummary;

  /// 成員 state 摘要（人類回報 2026-11-06「頭像無法即時更新」）：m.room.member
  /// state 事件不改 lastEvent、也不是 receipt → 舊兩個分支抓不到（聯絡人
  /// 頭像／名稱會一次改動多處）。以官方 `Room.states[m.room.member]` 的
  /// stateKey＋avatar_url＋displayname 建構輕量字串；null＝尚未比對過。
  String? _lastMemberSummary;

  String _receiptSummary() {
    try {
      final global = widget.room.receiptState.global.otherUsers;
      return [
        for (final e in global.entries) '${e.key}:${e.value.eventId}',
      ].join(',').toString();
    } catch (_) {
      return '';
    }
  }

  /// 成員 state 輕量摘要：任何成員的頭像／名稱／增減都會改變字串。
  String _memberStateSummary() {
    final members = widget.room.states[EventTypes.RoomMember];
    final buf = StringBuffer();
    members?.forEach((stateKey, ev) {
      buf
        ..write(stateKey)
        ..write(':')
        ..write(ev.content['avatar_url'])
        ..write(':')
        ..write(ev.content.tryGet<String>('displayname'))
        ..write(';');
    });
    return buf.toString();
  }

  /// 官方 SDK 媒體 API：縮圖（加密房時 SDK 走官方解密路徑；本檔零加密邏輯）。
  /// 失敗（引擎未啟／網路）回 null，tile 顯示文字占位。
  Future<MatrixFile?> _loadImage(ChatMessageView m) {
    final event = m.event;
    final id = m.eventId ?? 'self_${m.sentAt?.toIso8601String()}';
    if (event == null) {
      _imageLoaders[id] ??= Future<MatrixFile?>.value(null);
      return _imageLoaders[id]!;
    }
    return _imageLoaders[id] ??= () async {
      try {
        return await event.downloadAndDecryptAttachment(getThumbnail: true);
      } catch (_) {
        return null;
      }
    }();
  }

  @override
  void initState() {
    super.initState();
    // 批次十二①：聊天室背景載入——per-room 設定優先；沒有則 fallback
    // 全域桌布（appearance「聊天室背景」，kv chat_wallpaper；格式同 room_bg：
    // '#RRGGBB' 色值或圖片路徑）。
    AppSettings.getRoomBackground(widget.room.id).then((v) async {
      String? bg = v;
      if (bg == null) {
        try {
          bg = await AppSettings.getChatWallpaper();
        } catch (_) {
          // 測試環境／無 sqflite → 無全域桌布。
        }
      }
      if (mounted) setState(() => _roomBackground = bg);
    }).catchError((_) {
      // 測試環境／無 sqflite 時不出錯（預設背景）。
    });
    // Suggestion #7＋#12：載入本畫面草稿（per-room；測試環境無 DB 則忽略）。
    AppSettings.getDraft(widget.room.id).then((v) {
      if (mounted && v != null && v.isNotEmpty && _inputController.text.isEmpty) {
        _inputController.text = v;
      }
    }).catchError((_) {
      // 測試環境／無 sqflite 時不出錯（無草稿）。
    });
    // 貼圖建議開關（backlog #8；LINE 貼圖設定頁「Display suggestions」）。
    unawaited(_loadStickerSuggestionSetting());
    // 第三十五批 #13：載入 Markdown 送出偏好（kv `markdown_enabled`，
    // 預設關；測試環境無 DB → 預設值）。
    AppSettings.get('markdown_enabled').then((v) {
      if (mounted) {
        setState(() => _markdownOn = v == '1');
      }
    }).catchError((_) {
      // 測試環境／無 sqflite：維持預設（關）。
    });
    _syncSub = widget.room.client.onSync.stream.listen((_) {
      // 僅在房間的最後事件變更時才重新載入，避免無意義的 reload。
      final last = widget.room.lastEvent;
      if (last?.eventId != _lastRoomEventId) {
        _lastRoomEventId = last?.eventId;
        _scheduleReload();
      }
      // 「都沒有看到」已讀標記（人類回饋 2026-11-05）根因重分析：
      // read receipt 走 sync **ephemeral** 通道（官方 `m.receipt` →
      // `Room.receiptState`，client.dart `_handleEphemerals` 全自動），
      // **不會**改變 room.lastEvent → 上面分支永不觸發、已讀永不重畫。
      // 修正：比對官方 `Room.receiptState` 摘要（誰讀到哪一則），
      // 有變化才 reload（節流由 _scheduleReload 既有 1000ms 提供）。
      final receiptSummary = _receiptSummary();
      if (receiptSummary != _lastReceiptSummary) {
        _lastReceiptSummary = receiptSummary;
        _scheduleReload();
      }
      // 頭像／名稱即時更新（人類回報 2026-11-06）：m.room.member state 事件
      // 不改 lastEvent 也不是 receipt → 加入成員 state 摘要比對，有變才
      // reload（節流沿用 _scheduleReload 既有 1000ms）。
      final memberSummary = _memberStateSummary();
      if (memberSummary != _lastMemberSummary) {
        _lastMemberSummary = memberSummary;
        _scheduleReload();
      }
      // 第二十四批：typing 指示（官方 ephemerals m.typing）。摘要變化才
      // reload；SDK 內建超時清空不會再觸發 onSync → 另以 ticker 每 4 秒
      // 複驗（見 _syncTypingTicker）。
      final typingSummary = _typingSummary();
      if (typingSummary != _lastTypingSummary) {
        _lastTypingSummary = typingSummary;
        _syncTypingTicker();
        _scheduleReload();
      }
    });
    _scrollController.addListener(_onScroll);
    // 「傳完圖片只看到檔名、重開才見圖」修復（人類回報 2026-11-06）：
    // SDK sendFileEvent 的假 pending 事件被真事件**原地替換**時，列表
    // 長度不變，onSync 指紋（last.eventId）也未必變（替換非房間 lastEvent
    // 更新亦所在多有）——訂閱 SDK 官方 onTimelineEvent（E2EE 房同呼叫內
    // 先解密再 emit，見投票卡同款修復 2026-11-06），只挑「本帳號的媒體
    // 事件」：txid loader（檔名卡）已於 _sendOne 清過，此處再保證真事件
    // 組落到 _imageLoaders 一定取新，並排程一次輕量重載。
    _mediaEventSub = widget.room.client.onTimelineEvent.stream
        .where(
          (ev) =>
              ev.room.id == widget.room.id &&
              ev.senderId == widget.room.client.userID &&
              ((ev.type == EventTypes.Message &&
                      (ev.messageType == 'm.image' ||
                          ev.messageType == 'm.video' ||
                          ev.messageType == 'm.file' ||
                          ev.messageType == 'm.audio')) ||
                  ev.type == EventTypes.Sticker),
        )
        .listen((ev) {
      _imageLoaders.remove(ev.eventId);
      _scheduleReload();
    });
    // 第 8 點：進入聊天室**立即**取一次未讀狀態（不等 _load 完成），
    // 有未讀 →「設為已讀」按鈕馬上出現（是 UI 資料流，官方 Room.isUnread）。
    _hasUnread = widget.room.isUnread;
    _load();
  }

  /// 媒體事件替換訂閱（2026-11-06 修復「重開才見圖」；dispose 同步釋放）。
  StreamSubscription<Event>? _mediaEventSub;

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _syncSub?.cancel();
    _mediaEventSub?.cancel();
    // Suggestion #7＋#12：離開聊天室即保存未送出草稿（本機；fire-and-forget，
    // 失敗不致命）。**在 controller dispose 之前**讀值。
    final draft = _inputController.text;
    unawaited(
      AppSettings.setDraft(widget.room.id, draft).catchError((_) {}),
    );
    _inputController.dispose();
    _scrollController.dispose();
    _uploadTimer?.cancel();
    _typingTicker?.cancel();
    super.dispose();
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) unawaited(_load());
    });
  }

  void _onScroll() {
    // reverse 列表：offset 0 ＝ 最新（底）。
    final atBottom = _scrollController.offset < 120;
    // 距底遠（非 atBottom）→ 顯示「回到底部」鈕。
    final show = !atBottom;
    if (show != _showScrollDown) {
      setState(() => _showScrollDown = show);
    }
    // 第 4 點：過去訊息讀不到——接近視覺最上層（reverse 列表的
    // maxScrollExtent 端）時觸發 _requestHistory（SDK 官方 History API）。
    // maxScrollExtent == 0（短列表）無歷史可載 → 不觸發。
    final position = _scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.maxScrollExtent - position.pixels <= 100) {
      unawaited(_requestHistory());
    }
  }

  /// 預設訊息載入：SDK Timeline 中的文字訊息（m.text）、圖片（m.image）、
  /// 檔案（m.file）、影片（m.video）、音訊（m.audio），以及**未能解密**的訊息
  /// （顯示占位，不悄悄丟掉）。解密由 SDK 官方引擎處理。
  Future<List<ChatMessageView>> _defaultLoadMessages(Room room) async {
    // 批次 D：**複用同一 Timeline 實例**（requestHistory 抓的歷史保留在內；
    // 每次重建會丟掉已抓的歷史窗口，也是「過去訊息消失」的 UI 端根因）。
    // 修法 #3（解密案 2026-11-13 實證）：開房時若 `m.room.encryption`
    // state 缺失（room.encrypted=false），SDK 載入 timeline 完全跳過解密
    // （timeline.dart L288，零 log）＝全部訊息恆為未解密佔位。先以官方
    // API 補回 state；補回成功時強制重建 timeline——舊實例的事件已以
    // 未解密型別載入，不會重新解密。
    final restored = await ensureRoomEncryptionState(room);
    final current = _timeline;
    if (current != null && current.room.id == room.id && !restored) {
      // reuse
    } else {
      _timeline = await room.getTimeline();
    }
    final timeline = _timeline!;
    // 第 4 點根因重寫：舊實作把 undecrypted／plain／poll／sticker 分成
    // **四個各自過濾的清單再串接**，每個清單都是 SDK 的新→舊順序，
    // 串接後時序錯亂（同類事件全部擠在一起，看起來「過去訊息讀不到」）。
    // 改為單一過濾保留 SDK 事件順序，最後統一 reverse（最舊在前）。
    bool editable(Event e) =>
        e.type == EventTypes.Encrypted ||
        e.type == EventTypes.Sticker ||
        kPollStartTypes.contains(e.type) ||
        // Suggestion #8「通話紀錄應同時顯示在聊天室中」：以官方 m.call.invite
        // （SDK EventTypes.CallInvite）為準顯示通話事件（hangup/reject 不另列，
        // 避免洗版；`CallLog` 本機紀錄另可在通話清單查）。
        e.type == EventTypes.CallInvite ||
        (e.type == EventTypes.Message &&
            (e.messageType == 'm.text' ||
                e.messageType == 'm.image' ||
                e.messageType == 'm.file' ||
                e.messageType == 'm.video' ||
                e.messageType == 'm.audio' ||
                e.messageType == 'm.location'));
    final events = timeline.events.where(editable).toList();
    // 修法 #4（解密案 2026-11-13 源碼釘死）：/context 重建路徑 SDK 只解密
    // 帶旗標事件（room.dart L1775-1776）；重裝後舊事件無旗標 → 恆不解密。
    // 以官方 decryptRoomEvent 補解密（見 missing_key_repair.dart）。
    final decrypted = await decryptUndecryptedEvents(room, events);
    // 第四十二批：編輯對照——掃描**已解密**事件建立 target→最新編輯
    // （E2EE 房間的編輯事件在 sync 時仍是 m.room.encrypted，SDK 不會自動
    // 聚合 → 舊內容一直留著）。
    final editMap = buildEditMap(decrypted);
    // 第四十五批：回覆引言對照（eventId → 寄送者／內容摘要）。
    // 官方 `m.relates_to` → `m.in_reply_to` → `event_id`；解密後的內容仍保留
    // `m.relates_to`（SDK encryption.dart：解密時把原始 m.relates_to 帶回）。
    final replyMap = <String, ({String sender, String body})>{};
    for (final e in decrypted) {
      if (e.eventId.isEmpty) continue;
      final editedReply = resolveMessageContent(e, editMap, timeline: timeline);
      replyMap[e.eventId] = (
        sender: e.senderId,
        body: editedReply.edited ? editedReply.body : e.body,
      );
    }
    // 官方 relations（更早的編輯）改為**背景補抓**，不阻塞畫面
    // （第四十二批效能修正：先前同步抓 20 筆 → 首屏要等十幾秒）。
    unawaited(_fetchEditRelations(room, timeline, decrypted));
    final out = <ChatMessageView>[];
    for (final event in decrypted.reversed) {
      // 第二十四批（Matrix 官方編輯語意）：m.replace 編輯事件**自身不渲染**
      //（SDK `Event.relationshipType`；編輯內容經官方聚合回套到原訊息，
      // 見下方 _editedBodyOf——與 Element X 同語意）。
      if (event.relationshipType == RelationshipTypes.edit) {
        continue;
      }
      final edited = resolveMessageContent(event, editMap, timeline: timeline);
      out.add(
        ChatMessageView(
          sender: event.senderId,
          // 批次 III-a：被收回的事件（SDK 官方 `Event.redacted`）顯示占位文字，
          // 不悄悄消失（回收訊息所有人可見此狀態）。
          body: event.redacted
              ? '[已收回]' // 文案草案
              : event.type == EventTypes.Encrypted
                  ? '[加密訊息：無法解密]'
                  : kPollStartTypes.contains(event.type)
                      ? '[投票]' // 文案草案（SDK event.body 對未知型別回 Unknown… 不宜露出）
                      : event.type == EventTypes.CallInvite
                          ? _callInviteLabel(event)
                          // 第四十二批：編輯內容以自建對照解析
                          // （E2EE 房間亦適用）；非編輯則用原 body。
                          : edited.edited
                              ? edited.body
                              : event.body,
          sentAt: event.originServerTs,
          eventId: event.eventId,
          isImage: event.type == EventTypes.Message &&
              event.messageType == 'm.image',
          isSticker: event.type == EventTypes.Sticker,
          isLocation: event.type == EventTypes.Message &&
              event.messageType == 'm.location',
          // 「投票結束」（人類回報 2026-11-03）：end 事件不進列（editable
          // 已排除），start 事件**恆**以 _ChatPollTile 渲染——tile 內部以
          // `pollEndedCompat` 顯示「已結束」＋票數結果（Element X 同樣隱藏
          // end 事件、將結果併入 start 卡片）。
          isPoll: kPollStartTypes.contains(event.type),
          // 第二十二批：通話事件 flag（chip 樣式渲染）。
          isCallInvite: event.type == EventTypes.CallInvite,
          // 第二十四批：該訊息已被編輯過（官方 m.replace 聚合存在）。
          isEdited: edited.edited,
          // 第四十二批：編輯後的 HTML（Markdown）也要能渲染。
          formattedBody: edited.edited
              ? edited.formattedBody
              : _ownFormattedBody(event),
          // 第四十五批：回覆引言（官方 m.in_reply_to；查無被回覆事件則不顯示）。
          replyToSender: _replySenderOf(event, replyMap),
          replyToBody: _replyBodyOf(event, replyMap),
          event: event,
        ),
      );
    }
    return out;
  }

  /// 第四十二批：背景補抓官方 relations（`Timeline.fetchAggregatedEvents`，
  /// 官方 API：分頁取得 `/relations` 並注入聚合樹），涵蓋**更早**的編輯。
  ///
  /// - **不阻塞**畫面：首屏先以本地對照（已解密事件）渲染，抓到新編輯再重載。
  /// - 每個事件 id 只查一次（`_editRelationsChecked`）→ 不重複請求。
  /// - 只抓**最近 8 筆**文字訊息（較早的編輯由使用者在該訊息上長按時
  ///   再補，或待下一輪）。
  Future<void> _fetchEditRelations(
    Room room,
    Timeline timeline,
    List<Event> decrypted,
  ) async {
    try {
      final known = buildEditMap(decrypted);
      final texts = decrypted
          .where((e) =>
              e.type == EventTypes.Message && e.messageType == 'm.text')
          .toList();
      // 取最近 8 筆（decrypted 為新→舊；故取尾端）。
      final recent = texts.length <= 8
          ? texts
          : texts.sublist(texts.length - 8);
      final pending = recent
          .where((e) =>
              !known.containsKey(e.eventId) &&
              !_editRelationsChecked.contains(e.eventId))
          .toList();
      if (pending.isEmpty) {
        return;
      }
      for (final e in pending) {
        _editRelationsChecked.add(e.eventId);
      }
      for (final e in pending) {
        try {
          await timeline.fetchAggregatedEvents(
            e.eventId,
            RelationshipTypes.edit,
          );
        } catch (_) {
          // 官方 API 失敗（離線等）→ 略過該筆（不重試，避開請求風暴）。
        }
      }
      // 抓回的關聯事件：官方聚合樹（E2EE 房間仍是加密 → 解密後判斷）。
      final aggregated = <Event>[];
      for (final e in pending) {
        try {
          aggregated.addAll(
            timeline.aggregatedEvents[e.eventId]?[RelationshipTypes.edit] ??
                const <Event>{},
          );
        } catch (_) {}
      }
      if (aggregated.isEmpty) {
        return;
      }
      final decryptedAgg = await decryptUndecryptedEvents(room, aggregated);
      final newEdits = buildEditMap(decryptedAgg);
      final hasNew = newEdits.keys.any((k) => !known.containsKey(k));
      if (hasNew && mounted) {
        // 有新編輯 → 重載一次（此時本地對照即可套用）。
        unawaited(_load());
      }
    } catch (_) {
      // 任何例外 → 不阻擋訊息顯示。
    }
  }

  /// 第四十二批：事件自身的 `formatted_body`（未編輯時的 Markdown HTML）。
  String? _ownFormattedBody(Event event) {
    try {
      final fb = event.content['formatted_body'];
      if (fb is String && fb.isNotEmpty) {
        return fb;
      }
    } catch (_) {}
    return null;
  }


  /// 「room 內的好友名稱沒有修改到」（人類回饋 2026-11-05）：訊息列沿用
  /// 原始 Matrix ID。改官方鏈路：`Room.getState(RoomMember)` →
  /// `StrippedStateEvent.asUser(room).calcDisplayname()`（SDK user.dart L97：
  /// displayname 優先，缺→localpart 美化；無 state → 回退原 ID，
  /// 不觸發 fire-and-forget requestUser 以避測試環境無 DB 的 LateError）。
  String _senderName(ChatMessageView m) {
    try {
      final member =
          widget.room.getState(EventTypes.RoomMember, m.sender);
      final name = member?.asUser(widget.room).calcDisplayname();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    } catch (_) {
      // 無 member state／client 初始化中 → 顯示原 ID。
    }
    return m.sender;
  }

  /// 第四十五批：回覆引言的寄送者（官方 `m.in_reply_to` → 被回覆事件）。
  ///
  /// 對照表由載入時建立（已解密事件，含 E2EE 房間）；查無則 null（不顯示引言）。
  String? _replySenderOf(
    Event event,
    Map<String, ({String sender, String body})> replyMap,
  ) {
    final target = _replyTargetId(event);
    if (target == null) return null;
    final hit = replyMap[target];
    if (hit == null) return null;
    return _displayNameOf(hit.sender);
  }

  /// 第四十五批：回覆引言的內容摘要（單行，截斷 60 字）。
  String? _replyBodyOf(
    Event event,
    Map<String, ({String sender, String body})> replyMap,
  ) {
    final target = _replyTargetId(event);
    if (target == null) return null;
    final hit = replyMap[target];
    if (hit == null) return null;
    final body = hit.body.replaceAll('\n', ' ').trim();
    if (body.isEmpty) return null;
    return body.length > 60 ? '${body.substring(0, 60)}…' : body;
  }

  /// 官方回覆目標 event id（`m.relates_to` → `m.in_reply_to` → `event_id`）。
  String? _replyTargetId(Event event) {
    final relates = event.content['m.relates_to'];
    if (relates is! Map) return null;
    final inReply = relates['m.in_reply_to'];
    if (inReply is! Map) return null;
    final id = inReply['event_id'];
    if (id is! String || id.isEmpty) return null;
    return id;
  }

  /// 顯示名稱（官方 `RoomMember.calcDisplayname`；查無則原 ID）。
  String _displayNameOf(String mxid) {
    try {
      final member = widget.room.getState(EventTypes.RoomMember, mxid);
      final name = member?.asUser(widget.room).calcDisplayname();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {
      // 無 member state → 顯示原 ID。
    }
    return mxid;
  }

  /// Suggestion #8：官方 m.call.invite 事件顯示為通話紀錄行（草案文案）。
  /// 語音／視訊以事件 content 的官方 `video` 欄位判斷（無自製判斷）。
  String _callInviteLabel(Event event) {
    final video = event.content['video'];
    if (video == true || video == 'true') {
      return '視訊通話'; // 文案草案
    }
    return '語音通話'; // 文案草案
  }

  /// 批次 D：載入更早訊息（SDK 官方 `Timeline.requestHistory`）。
  /// 滑動接近頂部自動觸發（人類指示），**非**無限滾動資訊流。
  /// 第 4 點重寫：一次 requestHistory 可能只前進一輪（先吃 DB 快取，
  /// 再向 server 要），故在 `canRequestHistory` 前提下**連續載到有進展**
  /// 最多 4 輪；完全無進展時提示「已沒有更早的訊息」（節流 5 秒防洗版）。
  /// 頂部插入訊息時保持視覺不移動。
  ///
  /// 「顯示有新訊息但讀不到先前訊息」（人類回報 2026-11-03 三）情境：
  /// SDK `_requestEvents` 源碼——`room.prev_batch == null`（房間久未活動、
  /// 未被 recent sync 涵蓋）時**不打 server 直接退出**，看起來就是「歷史讀不到」。
  /// 退路：官方 `getTimeline(eventContextId:)` 走 /context API 重建
  /// timeline（chunk 自帶正確 prevBatch），之後 requestHistory 即正常。
  Future<void> _requestHistory() async {
    final timeline = _timeline;
    if (timeline == null || _historyLoading || widget.loadMessages != null) {
      // 注入 loader 的測試環境無 timeline（分頁按鈕不顯示）。
      return;
    }
    setState(() => _historyLoading = true);
    try {
      var progress = 0;
      for (var round = 0;
          round < 4 && timeline.canRequestHistory;
          round++) {
        final before = timeline.events.length;
        await timeline.requestHistory(historyCount: 100);
        final gained = timeline.events.length - before;
        progress += gained;
        if (gained == 0) {
          break; // 本輪無進展（多為已到最早訊息）。
        }
      }
      var messages = await _defaultLoadMessages(widget.room);
      // prev_batch null 的 SDK 限制退路（見方法註解）。
      if (progress == 0 && widget.room.prev_batch == null) {
        try {
          _timeline?.cancelSubscriptions();
          // 第九次防護：0 筆房間（人類回饋「全部消失」情境）messages.first
          // 會丟 StateError——改僅以官方 room.lastEvent 為 bootstrap。
          final bootId = messages.isEmpty
              ? widget.room.lastEvent?.eventId
              : (widget.room.lastEvent?.eventId ?? messages.first.eventId);
          if (bootId != null) {
            _timeline = await widget.room.getTimeline(eventContextId: bootId);
            final bootMessages = await _defaultLoadMessages(widget.room);
            if (bootMessages.length > messages.length) {
              progress = bootMessages.length - messages.length;
              messages = bootMessages;
            }
          }
        } catch (_) {
          // context 重建失敗 → 維持現況（progress 0 → 提示）。
        }
      }
      if (mounted) {
        setState(() {
          _messages = messages;
          _historyLoading = false;
        });
        if (progress == 0) {
          final now = DateTime.now();
          if (_lastNoMoreHistoryShown == null ||
              now.difference(_lastNoMoreHistoryShown!) >
                  const Duration(seconds: 5)) {
            _lastNoMoreHistoryShown = DateTime.now();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已沒有更早的訊息')), // 文案草案
            );
          }
        }
        // reverse 列表：歷史插入在高 offset 端（視覺上方），offset（視覺
        // 位置）不受影響——**不需要**任何補償跳。（舊實作的「補償跳」正是
        // 「滑到底後被跳回頂部／重抓舊訊息」的直接來源。）
      }
    } catch (e) {
      if (mounted) {
        setState(() => _historyLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入更早訊息：$e')), // 文案草案
        );
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    final hadMessages = _messages.isNotEmpty;
    if (!hadMessages) {
      setState(() {
        _loading = true;
        _message = null;
      });
    }
    List<ChatMessageView> messages;
    try {
      messages = await (widget.loadMessages ?? _defaultLoadMessages)(
        widget.room,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _message = '無法載入訊息：請檢查網路';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    // 第 8 點：判斷聊天室是否有未讀訊息（SDK 官方 Room.isUnread）。
    if (mounted) {
      setState(() {
        _hasUnread = widget.room.isUnread;
      });
    }

    // 僅在訊息實際變更時更新，避免重複 setState 造成畫面閃爍。
    final changed = _messages.length != messages.length ||
        (_messages.isNotEmpty && messages.isNotEmpty && _messages.last.eventId != messages.last.eventId);
    if (changed && mounted) {
      // reverse 列表：offset 表示由最新（0）往回算的距離——內容增／縮
      // （歷史插入、timeline 重建）只影響高 offset 端，視覺位置穩定，
      // 皆不需要任何保位補償（舊實作的補償即「自動跳頂」來源）。
      setState(() {
        _loading = false;
        _messages = messages;
      });
    } else if (mounted && _loading) {
      // 訊息未變但剛 mount（例如注入 loader 回空列表）→ 只需解除 spinner 一次。
      setState(() => _loading = false);
    }
    // 「顯示有新訊息但讀不到先前訊息」（人類回報 2026-11-03 三）：
    // 未讀徽章來自 server 計數，與本地 loader 無關；本地 timeline 只有
    // 最新數筆時 ListView 沒有捲動高度 → `_onScroll` 不觸發 → 歷史永遠
    // 不被請求。進房後訊息過少時**主動補抓一次**歷史（session 內一次，
    // 防止「已沒有更早的訊息」提示隨 sync 洗版）。
    // 第九次（人類回饋「一對一、加密、對話全部消失且永不恢復，Element X 仍在」）
    // 根因：原條件多一個 `messages.isNotEmpty` → **0 筆的房間永不觸發補抓**；
    // 而 `prev_batch == null` 時 SDK `getTimeline()` 不打 server 直接回 0 筆
    // ——空房間卡死（捲動觸發也不可用：列表無捲動高度）。修正：0 筆也補抓
    // 一次（`_requestHistory` 內含該情境的官方 /context 重建退路）。
    if (!_autoHistoryAsked &&
        widget.loadMessages == null &&
        _timeline != null &&
        messages.length < 20) {
      _autoHistoryAsked = true;
      unawaited(_requestHistory());
    }

    // 批次十二⑤：緊急橫幅刷新（官方釘選 state；id 未變時直接跳過）。
    unawaited(_refreshPinnedBanner());

    // 已讀標記（1.6 skeleton＋第 8 點重寫）。目標 event 改用官方
    // `Room.lastEvent`（比「最後一條訊息」更準：reaction／membership 等
    // 事件也一併覆蓋；Element X 的未讀判斷以最後事件為基準）。
    // `_lastReadEventId` 於**成功後**才寫入——舊實作先寫 guard 再 await，
    // 一旦失敗即永不重試，正是「點入聊天室仍無法已讀」的根因之一。
    final latest = messages.isEmpty ? null : messages.last;
    final latestId = latest?.eventId;
    final target = widget.room.lastEvent?.eventId ?? latestId;
    // 已讀時機對齊 Element X（偏差清單任務 2，人類批准 2026-11-07）：
    // EX TimelinePresenter OnScrollFinished 僅於 firstVisibleIndex == 0
    // （捲到最新）才 markAsRead——Homing reverse 列表同義條件＝offset < 120
    // （與 _onScroll L428、置底判斷同一門檻；看舊訊息時新訊息不偷標）。
    // 首次進房 frame 未建立（hasClients == false）視同在底 → 進房照舊
    // 標已讀；手動「設為已讀」按鈕不受此 gate 影響。
    final atBottom =
        !_scrollController.hasClients || _scrollController.offset < 120;
    if (atBottom && target != null && target != _lastReadEventId) {
      try {
        await (widget.markRead ??
                (r, m) => r.setReadMarker(target, mRead: target))(
            widget.room, latest!);
        _lastReadEventId = target;
        if (mounted) setState(() => _hasUnread = false);
      } catch (_) {
        // 失敗不寫 guard → 下一次 sync 觸發的 _load 會自動重試。
        // 自動路徑不洗版 SnackBar；失敗訊息由手動「設為已讀」按鈕路徑提示。
      }
    }
    // 置底（最新訊息）：reverse 列表 offset 0 ＝ 底。僅於初始載入，或用戶
    // 已在底部附近時才跳回 0；否則保持當前滾動位置（known_problems #22）。
    final alreadyAtBottom = _scrollController.hasClients &&
        _scrollController.offset < 120;
    if (!_initialLoadDone || alreadyAtBottom) {
      _scrollToBottom();
    }
    _initialLoadDone = true;
  }

  /// reverse 列表（人類重現 2026-11-03「進房自動跳頂」根因重構）：
  /// offset 0 ＝ 最新訊息 → 單次 jumpTo(0) 即到最新，**無** lazy ListView
  /// 估算 extent 問題（舊「逐 frame 補跳」一節整體移除）。
  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }
  }

  /// 批次十二⑤：刷新緊急橫幅（＝公告房間／本房間的官方最新釘選訊息）。
  /// 釘選 id 未變不重查（`Room.pinnedEventIds` 為房間 state 的同步 getter，
  /// 讀取零成本；避免每次 sync 重查 DB）。
  Future<void> _refreshPinnedBanner() async {
    List<String> ids;
    try {
      ids = widget.room.pinnedEventIds; // 官方（room.dart L185）
    } catch (_) {
      return;
    }
    final newest = ids.isEmpty ? null : ids.last; // 釘選清單尾＝最新釘選
    if (newest == _pinnedBannerEventId &&
        (newest == null) == (_pinnedBannerBody == null)) {
      return;
    }
    if (newest == null) {
      if (mounted) {
        setState(() {
          _pinnedBannerEventId = null;
          _pinnedBannerBody = null;
          _pinnedBannerSender = null;
        });
      }
      return;
    }
    Event? ev;
    try {
      ev = await widget.room.getEventById(newest); // 官方（room.dart L2225）
    } catch (_) {}
    var body = '（無法載入訊息內容）'; // 文案草案
    var sender = '';
    if (ev != null) {
      body = ev.redacted
          ? '[已收回]' // 文案草案
          : (ev.body.isNotEmpty ? ev.body : '（訊息）'); // 文案草案
      try {
        final member = widget.room.getState(EventTypes.RoomMember, ev.senderId);
        final name = member?.asUser(widget.room).calcDisplayname();
        sender = (name == null || name.isEmpty) ? ev.senderId : name;
      } catch (_) {
        sender = ev.senderId;
      }
    }
    if (mounted) {
      setState(() {
        _pinnedBannerEventId = newest;
        _pinnedBannerBody = body;
        _pinnedBannerSender = sender;
      });
    }
  }

  /// 橫幅點擊＝跳到該訊息（官方 Scrollable.ensureVisible）。訊息在已載入
  /// 分頁之外（太舊未渲染）時 v0 不假跳——SnackBar 說明（骨架披露）。
  void _jumpToPinnedMessage() {
    final id = _pinnedBannerEventId;
    if (id == null) return;
    final ctx = _rowKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('該訊息不在目前載入範圍（太舊）；請往上捲動載入更早訊息'), // 文案草案
      ),
    );
  }

  /// 取消釘選＝官方 `Room.setPinnedEvents`（room.dart L676；伺服器狀態變更）。
  /// Phase 4.4「期限後自動取消釘選」＝藍圖待人工決定，v0 不做。
  Future<void> _unpinPinnedMessage() async {
    final id = _pinnedBannerEventId;
    if (id == null) return;
    try {
      final ids = [...widget.room.pinnedEventIds]..remove(id);
      await widget.room.setPinnedEvents(ids);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消釘選失敗：$e')), // 文案草案
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _pinnedBannerEventId = null;
        _pinnedBannerBody = null;
        _pinnedBannerSender = null;
      });
    }
  }

  /// 第 8 點：手動設為已讀。呼叫 SDK 官方 `setReadMarker` 標記
  /// `Room.lastEvent`（官方最新事件；比「最後一條訊息」涵蓋更廣）。
  Future<void> _markAsRead() async {
    if (!mounted) return;
    final target = widget.room.lastEvent?.eventId ??
        (_messages.isEmpty ? null : _messages.last.eventId);
    if (target == null) {
      return;
    }
    try {
      await widget.room.setReadMarker(target, mRead: target);
      if (mounted) {
        setState(() {
          _hasUnread = false;
          _lastReadEventId = target;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設為已讀失敗：$e')), // 文案草案
        );
      }
    }
  }

  // ── 批次 D：圖片全屏預覽（草案）───────────────────────────────────────

  /// 點擊聊天圖片 → 全屏預覽（ImagePreviewScreen）。縮圖先帶入顯示，
  /// 全尺寸由 preview 內以 SDK 官方 API 載入。
  Future<void> _openImagePreview(ChatMessageView m, Uint8List? bytes) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    // 第四十六批：貼圖**預覽開關**（kv `sticker_preview_enabled`，與「我的貼圖」
    // 頁的選單同一開關）。關閉時點貼圖**不開**全屏預覽（貼圖只是小圖，
    // 放大無實用價值；省下使用者誤觸）。
    if (m.isSticker) {
      final previewEnabled = await AppSettings.get(kStickerPreviewKey)
          .then((v) => v != '0')
          .catchError((_) => true);
      if (!previewEnabled) return;
      if (!mounted) return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ImagePreviewScreen(event: event, initialBytes: bytes),
      ),
    );
  }

  // ── 附件（批次 III-c，依人類注記參考圖 new_ref/…110220_labeled.png）──
  // 「＋」改為**展開面板**：面板開啟時上排鈕變 ×（關閉）／相機／相簿，
  // 輸入框與表情鈕不變；面板下方一排＝Files／Contact／位置。
  // Contact／位置為草案骨架（位置需 flutter_map 依賴批准，未動工）。

  /// 附件面板開關（批次 III-c）。
  bool _attachOpen = false;

  /// Files／Contact／位置 一排（草案骨架；待人類設計定稿）。
  Widget _buildAttachOptions() {
    return Row(
      children: [
        Expanded(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('檔案'), // 文案草案（參考圖 Files）
            onTap: () {
              _setAttachOpen(false);
              unawaited(_startAttach(FileType.any));
            },
          ),
        ),
        Expanded(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('聯絡資訊'), // 文案草案（參考圖 Contact）
            onTap: () {
              // 草稿骨架：把**自己的** Matrix ID 填入輸入框（登入者本人資訊，
              // 不觸碰他人個資）；送出與否由使用者決定。
              final mxid = widget.room.client.userID;
              if (mxid != null) {
                _inputController.text =
                    '${_inputController.text}我的 Matrix ID：$mxid';
                setState(() {});
              }
            },
          ),
        ),
        Expanded(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('位置'), // 文案草案（參考圖 Location）
            enabled: true,
            onTap: () {
              _setAttachOpen(false);
              unawaited(_sendLocation());
            },
          ),
        ),
      ],
    );
  }

  void _setAttachOpen(bool open) {
    setState(() {
      _attachOpen = open;
      if (open) {
        _emojiOpen = false; // 兩面板互斥（草案行為）。
      }
    });
  }

  /// 附件主流程：選檔 → 逐檔背景處理 → sendFileEvent（官方 API）。
  /// 上傳進行中再觸發＝整批排入序列鏈（人類批准 2026-11-06），不再拒絕。
  Future<void> _startAttach(FileType type) async {
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: type);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('選取失敗：$e')),
        );
      }
      return;
    }
    if (picked.isEmpty || !mounted) {
      return;
    }
    // 附件送出整批入序列鏈（同時傳圖＋傳文字時，文字排在附件之後）。
    await _chainTask(() async {
      _beginUpload(picked.length);
      for (var i = 0; i < picked.length; i++) {
        final pf = picked[i];
        _updateUpload(index: i + 1, name: pf.name, stage: '讀取中');
        _updateUploadProgress();
        try {
          final bytes = await pf.readAsBytes();
          await _sendOne(bytes, pf.name, path: pf.path);
        } catch (e) {
          _batchFail++;
          _batchFailReason = '$e';
        }
      }
      _finishBatch();
    });
  }

  /// 相機拍照（image_picker，人類批准 2026-11-01）→ 附件流程同上。
  Future<void> _onCamera() async {
    XFile? shot;
    try {
      shot = await (widget.pickCamera ??
          () => ImagePicker().pickImage(source: ImageSource.camera))();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('相機失敗：$e')),
        );
      }
      return;
    }
    if (shot == null || !mounted) {
      return;
    }
    final shotFile = shot; // 閉包內非空捕獲。
    // 拍照附件同走序列鏈（排隊情境與檔案選取一致）。
    await _chainTask(() async {
      _beginUpload(1);
      _updateUpload(index: 1, name: shotFile.name, stage: '讀取中');
      _updateUploadProgress();
      try {
        final bytes = await shotFile.readAsBytes();
        await _sendOne(bytes, shotFile.name, path: shotFile.path);
      } catch (e) {
        _batchFail++;
        _batchFailReason = '$e';
      }
      _finishBatch();
    });
  }

  /// 逐檔送出（官方 sendFileEvent；加密由 SDK 官方 sendFileEvent 內部處理）。
  /// [path]＝選檔／相機來源真實路徑（離線入佇列用；任務 4，人類批准
  /// 2026-11-07）。
  Future<void> _sendOne(Uint8List bytes, String name, {String? path}) async {
    // 2.8 bugfix：大小上限改由伺服器 m.upload.size 回報判斷
    // （matrix.org 有限制→檢查；self-host 無設定→null→不限制）。
    final limit = await _serverUploadLimit();
    if (limit != null && bytes.lengthInBytes > limit) {
      _batchTooBig++;
      return;
    }

    final isImage = isImageFileName(name);
    final isVideo = isVideoFileName(name);
    ImagePreparation? imagePrep;
    // 佔位卡預覽（批次 2）：先给原始 bytes（選圖當下既有）即早顯示；
    // 預處理完成後若有更小縮圖再換。非圖片附件不顯示縮圖。
    if (mounted) {
      setState(() => _uploadPreviewBytes = isImage ? bytes : null);
    }
    if (isImage) {
      _updateUpload(index: _uploadIndex, name: name, stage: '處理圖片');
      imagePrep = await prepareImageInBackground(bytes: bytes, name: name);
      if (mounted) {
        setState(() {
          _uploadPreviewBytes = imagePrep?.thumbnailBytes ??
              imagePrep?.upload?.bytes ??
              bytes;
        });
      }
    }

    // 慢傳修復（人類批准 2026-11-06）：上傳用 bytes 改為背景 isolate
    // 下採樣後的版本（長寬任一 <= 1920px 時維持原檔）；Element X 快的主
    // 因之一即原圖不上傳前先縮。
    final uploadBytes = imagePrep?.upload?.bytes ?? bytes;
    final uploadWidth = imagePrep?.upload?.width ?? imagePrep?.width;
    final uploadHeight = imagePrep?.upload?.height ?? imagePrep?.height;
    final uploadMime = imagePrep?.upload?.mimeType;

    // 加密房補釘（慢傳修復 2）：過去此處宣告的 `encrypted` 恆為 null，
    // SDK 官方 encryptFile 須在**主 isolate**執行（大檔卡 UI）；改為先在
    // 背景 isolate 呼叫 SDK 官方 encryptFile（純 Dart AES-CTR+SHA-256，
    // App 端零自寫演算法／零金鑰流程），再經 PreEncryptedUpload 官方注入
    // 管道給 sendFileEvent。未加密房＝不加密（與 SDK 行為一致）。
    EncryptedFile? encrypted;
    if (widget.room.encrypted) {
      _updateUpload(index: _uploadIndex, name: name, stage: '加密');
      encrypted = await encryptFileInBackground(uploadBytes);
    }

    _updateUpload(index: _uploadIndex, name: name, stage: '上傳中');
    final file = buildUploadFile(
      bytes: uploadBytes,
      name: name,
      isImage: isImage,
      isVideo: isVideo,
      image: imagePrep,
      imageWidth: uploadWidth,
      imageHeight: uploadHeight,
      imageMimeType: uploadMime,
      encrypted: encrypted,
    );
    try {
      // 429 退避重試（人類批准 2026-11-06）：附件上傳限流時等 retry_after_ms
      // 後整檔重送（事件未落地前重試不會重複；詳見 sendWithRateLimitRetry）。
      // txid 自帶（「傳完只顯示檔名、重開才見圖」修復 2026-11-06）：SDK
      // sendFileEvent 會先插入假 pending 事件（id=txid、body=檔名、無 mxc），
      // 上傳完成後原地替換成真事件——若用 SDK 內部生成的隨機 txid，我們
      // 無法把快取中的 txid loader 失效；自帶 txid 才能對號清除。
      final txid = widget.room.client.generateUniqueTransactionId();
      await sendWithRateLimitRetry(
        () => widget.room.sendFileEvent(
          file,
          thumbnail: imagePrep?.thumbnail,
          txid: txid,
        ),
      );
      _batchOk++;
      // 送完立即刷新（同一批修復）：txid loader 已知是「檔名卡」失敗結果，
      // 先清；再要求重載（真事件 id 的 loader 會新建）。
      _imageLoaders.remove(txid);
      unawaited(_load());
    } on FileTooBigMatrixException {
      _batchTooBig++;
    } catch (e) {
      // 離線佇列（任務 4，人類批准 2026-11-07）：附件送出失敗（非 too-big）
      // → 附件入佇列，連線恢復後由 OfflineQueue.drain 依入列順序自動送出。
      // 文字與附件同一張表、同一條 id 序列 → 「傳檔時送文字」仍照順序完成。
      // too-big 不入列（檔案本來就送不上該伺服器，沒有重試意義）。
      final enqueued = await OfflineQueue.enqueueAttachment(
        roomId: widget.room.id,
        name: name,
        bytes: uploadBytes,
        path: path,
      );
      unawaited(_load());
      if (enqueued >= 0) {
        // 交 off 錯誤說明給批次完成提示（呼叫端 catch 不會觸發——這裡已吞掉）。
        _batchFail++;
        _batchFailReason = '$e（已存離線佇列，連線恢復後自動送出）';
      } else {
        // 無路徑又超過 BLOB 上限（>5MB 且來自 bytes-only 來源）→ 不吞錯，
        // 交由呼叫端 catch 計數＋原因顯示。
        _batchFail++;
        _batchFailReason = '$e（附件過大且無法離線留存，未入佇列）';
        rethrow;
      }
    }
  }

  /// 送信序列鏈（批次：文字排隊）：所有送出動作都排到 [task]，FIFO，
  /// 前一個失敗不阻斷下一個（鏈本身吞錯繼續，錯誤由各 task 內部處理）。
  Future<T> _chainTask<T>(Future<T> Function() task) {
    final run = _chainTail.then((_) => task());
    // 失敗不斷鏈（保持可繼續排隊）。
    _chainTail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// 佔位卡進度（4）＝階段權重近似；上傳中為 indeterminate，UI 端另示。
  void _updateUploadProgress() {
    if (!mounted) {
      return;
    }
    final progress = switch (_uploadStage) {
      '讀取中' => 0.08,
      '處理圖片' => 0.25,
      '加密' => 0.55,
      '上傳中' => 0.70, // 上傳端為單 POST 無 byte 進度，卡片切 indeterminate。
      _ => 0.02,
    };
    setState(() => _uploadProgress = progress);
  }

  /// 伺服器上傳大小上限（m.upload.size）；查詢失敗回 null（不擋，交給 SDK 檢查）。
  /// 4a（人類批准 2026-11-06）：結果快取在本 State 生命週期（同一 homeserver
  /// 同一 session），避免每次附件都多打一個 /config roundtrip。
  Future<int?> _serverUploadLimit() async {
    if (_serverUploadLimitKnown) {
      return _serverUploadLimitCache;
    }
    _serverUploadLimitKnown = true;
    try {
      final config = await widget.room.client.getConfig();
      final max = config.mUploadSize;
      if (max == null || max <= 0) {
        _serverUploadLimitCache = null;
        return null;
      }
      _serverUploadLimitCache = max;
      return max;
    } catch (_) {
      _serverUploadLimitCache = null;
      return null;
    }
  }

  void _beginUpload(int total) {
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final started = _uploadStartedAt;
      if (started == null) {
        return;
      }
      setState(() {
        _uploadElapsed = DateTime.now().difference(started);
      });
    });
    if (mounted) {
      setState(() {
        _uploading = true;
        _uploadIndex = 0;
        _uploadTotal = total;
        _uploadName = '';
        _uploadStage = '準備中';
        _uploadStartedAt = DateTime.now();
        _uploadElapsed = Duration.zero;
        _uploadPreviewBytes = null;
        _uploadProgress = 0.02;
        _batchOk = 0;
        _batchTooBig = 0;
        _batchFail = 0;
        _batchFailReason = null;
      });
    }
  }

  void _updateUpload({required int index, required String name, required String stage}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadIndex = index;
      _uploadName = name;
      _uploadStage = stage;
    });
    _updateUploadProgress(); // 階段進度（佔位卡，2026-11-06 批次 2）。
  }

  void _finishBatch() {
    _endUpload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已送出 $_batchOk 個附件'
            '${_batchTooBig > 0 ? "，$_batchTooBig 個超過伺服器上限" : ""}'
            '${_batchFail > 0 ? "，$_batchFail 個失敗（最後原因：${_batchFailReason ?? ''}）" : ""}',
          ),
        ),
      );
    }
    if (mounted) {
      unawaited(_load());
    }
  }

  void _endUpload() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _uploading = false;
      _uploadStage = '';
      _uploadName = '';
      _uploadStartedAt = null;
      _uploadElapsed = Duration.zero;
      // 佔位卡復位（批次 2）。
      _uploadPreviewBytes = null;
      _uploadProgress = 0;
    });
  }

  String _formatUploadElapsed() {
    final e = _uploadElapsed;
    final m = e.inMinutes.toString().padLeft(2, '0');
    final s = (e.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _onSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    // 第二十四批：編輯狀態 → 走編輯鏈（官方 sendTextEvent(editEventId:)；
    // 編輯不入離線佇列——把編輯文字當新訊息入列會改變語意，失敗僅提示）。
    final editing = _editTarget;
    if (editing != null) {
      await _sendEdit(text, editing);
      return;
    }
    // 批次 E：回覆狀態（滑動／長按選單進入）。注入 loader（測試）時
    // 退回一般送出，維持既有測試契約。
    final reply = _replyTo;
    // 第三十五批 #5＋#13：擷取本則送出的選項（無聲／Markdown 格式）。
    final silent = _silentSend;
    final formattedBody = _markdownOn ? markdownToMessageHtml(text) : null;
    final richPath = silent || formattedBody != null;
    setState(() {
      _sending = true;
      _message = null;
    });
    _inputController.clear(); // 隨即釋放輸入框（排隊中也能繼續打字）。

    String? error;

    // 文字排隊（人類批准 2026-11-06 批次 3）：送出動作入序列鏈——同時
    // 傳圖＋傳文字時，文字在圖片之後依序送出，不出現「文字先到、
    // 圖片後到」亂序。_sending 僅在_實際_送完後釋放（按鈕在排隊期間
    // 保持 disabled，避免把「排隊中」誤讀成已送出）。
    try {
      error = await _chainTask(() async {
        String? inner;
        try {
          if (richPath) {
            // 第三十五批 #5＋#13：無聲／Markdown → 官方 `Room.sendEvent`
            // ＋content 組裝（回覆經官方 inReplyTo 參數；429 退避同既有）。
            // 測試注入 sendRichMessage 時走注入（契約同 sendMessage）。
            final sender = widget.sendRichMessage;
            if (sender != null) {
              await sender(
                widget.room,
                text,
                silent: silent,
                formattedBody: formattedBody,
              );
            } else {
              final content = buildTextMessageContent(
                text,
                silent: silent,
                formattedBody: formattedBody,
              );
              await sendWithRateLimitRetry(
                () => widget.room.sendEvent(content, inReplyTo: reply?.event),
              );
            }
          } else if (reply != null && reply.event != null && widget.sendMessage == null) {
            // SDK 官方：回覆以 m.in_reply_to（Event.getReplyEvent 為讀側）。
            // 429 退避重試（人類批准 2026-11-06）：matrix.org 常見 M_LIMIT_EXCEEDED。
            await sendWithRateLimitRetry(
              () => widget.room.sendTextEvent(text, inReplyTo: reply.event),
            );
          } else {
            await (widget.sendMessage ??
                (room, t) => sendWithRateLimitRetry(() => room.sendTextEvent(t)))(
              widget.room,
              text,
            );
          }
        } catch (e) {
          inner = e.toString();
          rethrow;
        }
        return inner;
      });
      if (error != null) {
        // 佇列 task 內部已標記失敗。
        _inputController.text = text; // 失敗把文字還給輸入框。
      }
    } catch (e) {
      error = '送出失敗：已排入離線佇列';
      try {
        await OfflineQueue.enqueue(widget.room.id, text);
      } catch (_) {}
      _inputController.text = text;
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _message = error;
        _replyTo = null; // 送出後解除回覆狀態
        if (error == null) {
          // 第三十五批 #5：無聲為逐次例外動作 → 送出成功後復位（草案）。
          _silentSend = false;
        }
      });
    }
    // 樂觀更新：送出**成功**才以本地顯示（馬上對帳）；失敗（含已排入
    // 離線佇列）不顯示——既有行為，且離線佇列清楚提示「已排入」。
    if (error == null && mounted) {
      setState(() {
        _messages = [
          ..._messages,
          ChatMessageView(
            sender: widget.room.client.userID ?? '',
            body: text,
            sentAt: DateTime.now(),
          ),
        ];
      });
    }
    // Suggestion #7＋#12：送出成功（或離線入列）後清除草稿（空字串＝刪除）。
    if (error == null) {
      unawaited(AppSettings.setDraft(widget.room.id, '').catchError((_) {}));
      unawaited(_load());
      // 第二十四批：成功送出 → 停止 typing（官方 setTyping(false)）。
      unawaited(_stopTyping());
    }
  }

  // ── UI：頂列選單（LINE_ref 標註位置；通話／行事曆不做）────────────────

  /// 解密案修法 #2：對本房解密失敗的舊事件發出取鑰請求。
  /// 預設＝`missing_key_repair.dart` 官方 API 流程（測試可注入 fake）。
  /// 結果以 SnackBar 顯示；錯誤透明化（修法 #1 同款原則，不遮蔽真實錯誤）。
  Future<void> _requestMissingKeysForRoom(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    try {
      final count =
          await (widget.requestMissingKeys ?? _defaultMissingKeyRequest)(
        widget.room,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? '已向其他裝置請求 $count 個缺失金鑰；金鑰送達後重開聊天室即可解密' // 文案草案
                : '沒有偵測到需要請求的金鑰', // 文案草案
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('請求失敗：$e')), // 文案草案
      );
    }
  }

  Future<int> _defaultMissingKeyRequest(Room room) async {
    final timeline = _timeline;
    if (timeline == null) {
      throw StateError('訊息尚未載入'); // 文案草案
    }
    return requestMissingKeys(room, timeline);
  }

  void _openRoomMenu() {
    final directPartner = widget.room.directChatMatrixID;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                        // 批次十二③：聊天室資訊頁（靜音／成員／邀請／退出／公告房間）。
                        ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('聊天室資訊'), // 草案文案
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RoomInfoScreen(room: widget.room),
                  ),
                ));
              },
            ),
            // 解密案修法 #2（人類批准 2026-11-13）：加密房間才顯示。
            if (widget.room.encrypted)
              ListTile(
                leading: const Icon(Icons.vpn_key),
                title: const Text('向其他裝置請求缺失金鑰'), // 文案草案，待人類設計定稿
                onTap: () => unawaited(_requestMissingKeysForRoom(ctx)),
              ),
                        ListTile(
              leading: const Icon(Icons.wallpaper),
              title: const Text('設定聊天室背景'), // 草案文案
              onTap: () async {
                Navigator.of(ctx).pop();
                final choice = await showDialog<String>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('聊天室背景'), // 文案草案
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.color_lens),
                          title: const Text('選擇顏色'),
                          onTap: () => Navigator.pop(c, 'color'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.image),
                          title: const Text('選擇圖片'),
                          onTap: () => Navigator.pop(c, 'image'),
                        ),
                        if (_roomBackground != null)
                          ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: const Text('重置背景'),
                            onTap: () => Navigator.pop(c, 'reset'),
                          ),
                      ],
                    ),
                  ),
                );
                if (choice == null) return;
                if (choice == 'reset') {
                  await AppSettings.clearRoomBackground(widget.room.id);
                  // 批次十二①：重置 room 背景 → 回退全域桌布（如有）。
                  String? fallback;
                  try {
                    fallback = await AppSettings.getChatWallpaper();
                  } catch (_) {}
                  if (mounted) setState(() => _roomBackground = fallback);
                  return;
                }
                if (choice == 'image') {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1920,
                    imageQuality: 85,
                  );
                  if (picked == null || !mounted) return;
                  await AppSettings.setRoomBackground(widget.room.id, picked.path);
                  if (mounted) setState(() => _roomBackground = picked.path);
                  return;
                }
                // choice == 'color'
                // bug 修正（人類回報「取消會自動刪除背景」）：對話框
                // dismiss（取消）與「選預設（清自訂背景）」過去都回 null、
                // 兩者都執行 clearRoomBackground。改為雙值結果：
                //  - showDialog 回 null（滑掉／關閉）＝取消 → 不動現有背景
                //  - 回 [choose]（color 為 null）＝選「預設」→ 清背景
                if (!mounted) return;
                final color = await showDialog<_BgColorSelection>(
                  context: context,
                  builder: (c) => SimpleDialog(
                    title: const Text('選擇背景色'),
                    children: [
                      for (final entry in const {
                        '預設': null,
                        '蜜桃': 0xFFFFBD9F,
                        '薄荷': 0xFF9FE7C8,
                        '薰衣草': 0xFFC9B6E4,
                        '天空': 0xFF9FC9E7,
                        '深灰': 0xFF303030,
                      }.entries)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(
                          c,
                          _BgColorSelection(
                            color: entry.value == null
                                ? null
                                : Color(entry.value! | 0xFF000000),
                          ),
                        ),
                        child: Text(entry.key),
                      ),
                    ],
                  ),
                );
                if (color == null) {
                  // 取消（dismiss/關閉）→ 不動現有背景。
                  return;
                }
                if (color.color == null) {
                  // 「預設」→ 清除自訂背景（批次十二①：回退全域桌布）。
                  await AppSettings.clearRoomBackground(widget.room.id);
                  String? fallback;
                  try {
                    fallback = await AppSettings.getChatWallpaper();
                  } catch (_) {}
                  if (mounted) setState(() => _roomBackground = fallback);
                  return;
                }
                {
                  final hex = color.color!.toARGB32().toRadixString(16).padLeft(8, '0');
                  await AppSettings.setRoomBackground(widget.room.id, '#$hex');
                  if (mounted) setState(() => _roomBackground = '#$hex');
                }
              },
            ),
            if (directPartner != null) ...[
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('封鎖使用者'), // 1.9（SDK 官方 ignore API）
                onTap: () {
                  Navigator.of(ctx).pop();
                  final client = widget.room.client;
                  unawaited(Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BlockUserScreen(
                        block: (_) => client.ignoreUser(directPartner),
                        unblock: (_) => client.unignoreUser(directPartner),
                        listBlocked: () async => client.ignoredUsers,
                      ),
                    ),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_outlined),
                title: const Text('檢舉'), // 1.9a
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportUserScreen(targetDefault: directPartner),
                    ),
                  ));
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.poll),
              title: const Text('發起投票'), // 批次 D；文案草案
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PollCreateScreen(room: widget.room),
                  ),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('成員管理'), // 2.2
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupMemberManageScreen(
                      loadMembers: () async {
                        final participants = widget.room.getParticipants();
                        return [
                          for (final p in participants) p.id,
                        ];
                      },
                      inviteMember: (mxid) => widget.room.invite(mxid),
                      kickMember: (mxid) => widget.room.kick(mxid),
                    ),
                  ),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 第四十八批：聊天室內的搜尋限定**本房**（`MessageSearchScreen.room`）。
  void _openSearch() {
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageSearchScreen(
          client: widget.room.client,
          room: widget.room,
        ),
      ),
    ));
  }

  // ── 表情面板 ──────────────────────────────────────────────────────────

  void _toggleEmojiPanel() {
    setState(() {
      _emojiOpen = !_emojiOpen;
      // 批次 III-c：表情／附件兩面板互斥（草案行為）。
      if (_emojiOpen) {
        _attachOpen = false;
      }
    });
    if (_emojiOpen) {
      // 開啟面板時收起鍵盤（免得兩者擠在一起）。
      FocusScope.of(context).unfocus();
    }
  }

  void _insertEmoji(String emoji) {
    final selection = _inputController.selection;
    final text = _inputController.text;
    final offset = selection.baseOffset < 0 ? text.length : selection.baseOffset;
    final newText = text.replaceRange(offset, selection.extentOffset < 0 ? offset : selection.extentOffset, emoji);
    _inputController
      ..text = newText
      ..selection = TextSelection.collapsed(offset: offset + emoji.length);
  }

  /// P2.15 提案：撥出一對一通話（SDK 官方 `inviteToCall`，userId 帶
  /// directChatMatrixID 以避免自己的其他裝置誤響），成功後進全螢幕通話畫面。
  /// 失敗（不支援／已有通話進行中／非一對一）以 SnackBar 告知，不 crashes。
  Future<void> _startCall({required bool video}) async {
    final manager = widget.callManager;
    if (manager == null || _calling) {
      return;
    }
    // 批次 II-e：若已有進行中的通話（使用者按返回離開畫面後），點通話按鈕
    // 應回到通話狀態，而非重撥或無反應。
    final active = manager.activeCall;
    if (active != null && !active.callHasEnded && active.room.id == widget.room.id) {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: active, manager: manager),
          fullscreenDialog: true,
        ),
      );
      return;
    }
    // 若已有進行中的來電（同房間），直接加入而非重新撥打。
    final incoming = manager.incomingCall.value;
    if (incoming != null && !incoming.callHasEnded && incoming.room.id == widget.room.id) {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: incoming, manager: manager),
          fullscreenDialog: true,
        ),
      );
      return;
    }
    setState(() => _calling = true);
    try {
      final session = await manager.startCall(widget.room, video: video);
      if (!mounted) {
        await session.hangup(reason: CallErrorCode.userHangup);
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(session: session, manager: manager),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法撥打：$e')), // 文案草案，待人類定稿
        );
      }
    } finally {
      if (mounted) {
        setState(() => _calling = false);
      }
    }
  }

  /// P2.15 提案：發起群組通話（mesh），成功後進全螢幕群組通話畫面。
  Future<void> _startGroupCall() async {
    final manager = widget.callManager;
    if (manager == null || _calling) {
      return;
    }
    // 若已有進行中的群組通話（自己發起或遠端發起），直接加入而非重新發起。
    final existing = manager.activeGroupCall.value ?? manager.incomingGroupCall.value;
    if (existing != null && existing.room.id == widget.room.id) {
      if (mounted) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => GroupCallScreen(groupCall: existing, manager: manager),
            fullscreenDialog: true,
          ),
        );
      }
      return;
    }
    setState(() => _calling = true);
    try {
      final gc = await manager.startGroupCall(widget.room);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('群組通話已發起（mesh）。Element X 使用者將看到「Custom event」，這是協定差異，非錯誤。'), // 草案文案
            duration: Duration(seconds: 4),
          ),
        );
      }
      if (!mounted) {
        await manager.leaveGroupCall();
        return;
      }
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupCallScreen(groupCall: gc, manager: manager),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法發起群組通話：$e')), // 文案草案
        );
      }
    } finally {
      if (mounted) {
        setState(() => _calling = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final me = widget.room.client.userID ?? '';
    final latestOwnIndex = _messages.lastIndexWhere((m) => m.sender == me);
    final rows = _buildRows(me, latestOwnIndex);
    Color? bg;
    if (_roomBackground != null) {
      final hex = _roomBackground!.replaceFirst('#', '');
      final val = int.tryParse(hex, radix: 16);
      if (val != null) bg = Color(val | 0xFF000000);
    }
    final chatBody = Column(
      children: [
        // 第 8 點：有未讀訊息時顯示「設為已讀」按鈕，讓使用者手動標記已讀。
        if (_hasUnread)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: '設為已讀', // 文案草案
                  icon: const Icon(Icons.mark_as_unread),
                  onPressed: () => unawaited(_markAsRead()),
                ),
                const Expanded(
                  child: Text(
                    '此聊天室有未讀訊息', // 文案草案
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        // 第四十六批（人類回報「群組公告還是被當成緊急訊息，應恢復成一般
        // 公告」）：聊天室內的**釘選訊息橫幅**＝一般公告（中性色＋「公告」
        // 前綴），**不再是**紅色緊急框。
        //
        // 分流原則（第四十二批確立、第四十六批落實到聊天室內）：
        // - **一般公告**＝聊天室釘選訊息 → 中性色＋「公告」＋廣播 icon。
        // - **緊急示警**＝PWS RSS 官方災害示警 → LINE 緊急紅卡片（僅首頁）。
        // 兩者資料來源不同（官方釘選 vs 官方 feed），語意不同，不可混用。
        if (_pinnedBannerBody != null)
          AnnouncementBanner(
            text: _pinnedBannerBody!,
            title: _pinnedBannerSender,
            dense: true,
            onTap: _jumpToPinnedMessage,
            trailing: IconButton(
              tooltip: '取消釘選', // 文案草案
              icon: const Icon(Icons.push_pin_outlined),
              onPressed: () => unawaited(_unpinPinnedMessage()),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Text(_message ?? '還沒有訊息'),
                        )
                      : ListView(
                          controller: _scrollController,
                          // Issues「進房自動跳頂／滑到底被拉回頂部重抓舊訊息」
                          // 根因重構（2026-11-03，人類提供重現）：舊→新列表的
                          // 「底＝高 offset」定位仰賴 lazy ListView 的估算 extent
                          // 與逐 frame 補跳／offset clamp，內容異動即失準。
                          // 改 Flutter 官方聊天室標準做法 reverse: true——
                          // **offset 0 ＝ 最新訊息**：進房零跳轉、歷史插入（高
                          // offset 端）不移動視覺位置、新訊息自動在視野內。
                          reverse: true,
                          children: [
                            // rows 為舊→新排序（含日期分隔線）；reverse 顯示
                            // 後視覺上由下（最新）到上（最舊），分隔線相對位置
                            // 正確（在天並的訊息之前）。
                            ...rows.reversed,
                            if (_historyLoading)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
              // 第 21 點：滑到底按鈕改為獨立 Positioned（覆蓋在列表右下角，
              // 不佔用 Column 垂直空間，避免產生「整排空白」遮住訊息）。
              if (_showScrollDown && !_uploading && rows.isNotEmpty)
                Positioned(
                  right: 10,
                  bottom: 78, // 置於輸入列上方，不遮住輸入框
                  child: IconButton.filledTonal(
                    tooltip: '滑到底部', // 文案草案
                    onPressed: _scrollToBottom,
                    icon: const Icon(Icons.arrow_downward, size: 20),
                  ),
                ),
            ],
          ),
        ),
        // 佔位卡（人類批准 2026-11-06 批次 2）：上傳進行中顯示本地預覽
        //＋階段進度（SDK 官方 uploadContent 無 byte 級 onProgress，
        // 進度為階段近似＋上傳階段 indeterminate；草案樣式，待人類定稿）。
        if (_uploading) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxHeight: 132),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_uploadPreviewBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _uploadPreviewBytes!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '上傳中 $_uploadIndex/$_uploadTotal · $_uploadStage',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$_uploadName（已用 ${_formatUploadElapsed()}）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // 上傳階段無 byte 級進度 → indeterminate；其餘為階段比例。
                      _uploadStage == '上傳中'
                          ? const SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(),
                            )
                          : SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                value: _uploadProgress,
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        // 批次 E：回覆狀態 → 預覽列（輸入列上方）。
        // 第二十四批：typing 指示（官方 Room.typingUsers；Element X 同款
        // 語意，置於輸入列上方；草案文案）。純記憶體讀取（同步）。
        if (_typingLabelRow() != null) _typingLabelRow()!,
        if (_replyTo != null) _buildReplyBar(_replyTo!),
        // 第二十四批：編輯狀態 → 編輯預覽列（輸入列上方；回覆／編輯互斥）。
        if (_editTarget != null) _buildEditBar(_editTarget!),
        _buildInputRow(),
        if (_emojiOpen)
          Container(
            color: Theme.of(context).colorScheme.surface,
            height: 300,
            child: EmojiPanel(
              onEmojiSelected: _insertEmoji,
              // 批次 III-b：自訂貼圖可用（發送 m.sticker，人類已確認）。
              onStickerSelected: (entry) async {
                // 選擇貼圖後收起面板（草案行為，待人類定稿）。
                if (_emojiOpen) {
                  _toggleEmojiPanel();
                }
                await _sendSticker(entry);
              },
            ),
          ),
      ],
    );

    // 批次第 7 點：聊天室背景（支援十六進位顏色或使用者上傳的圖片路徑）。
    // 若設定值為圖片路徑，以 DecorationImage 繪製；否則使用純色背景。
    final hasImageBg = _roomBackground != null && bg == null;
    // 第二十二批：房名計算抽成區域變數（頂列「頭像＋房名」共用同一路徑）。
    final roomTitle = () {
      try {
        final name = widget.room.getLocalizedDisplayname();
        if (name.isNotEmpty && name != 'Empty chat') {
          return name;
        }
      } catch (_) {}
      return widget.room.id;
    }();
    return Scaffold(
      backgroundColor: hasImageBg ? null : bg,
      appBar: _selectMode
          // 第四十八批：多選模式 → 頂列換成**批次列**（關閉＋已選數＋動作）。
          ? AppBar(
              leading: IconButton(
                tooltip: '取消多選', // 文案草案
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectMode,
              ),
              title: Text('已選 $_selectedCount 則'), // 文案草案
              actions: [
                IconButton(
                  tooltip: '轉寄', // 文案草案
                  onPressed: () => unawaited(_batchForwardSelected()),
                  icon: const Icon(Icons.forward),
                ),
                IconButton(
                  tooltip: '收回', // 文案草案
                  onPressed: () => unawaited(_batchRedactSelected()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : AppBar(
        title: Row(
          children: [
            // 第二十二批（LINE_ref chat 稿）：頂列＝頭像＋房名。
            // 成員數 (N)：屬「Q1」待人類確認後補（一對一不顯示）。
            // 頭像資料＝官方：一對一＝對方 m.room.member avatar_url；
            // 群組＝Room.avatar；渲染同 _SenderAvatar（回退首字圓圈）。
            _SenderAvatar(
              label: roomTitle,
              avatarUri: _roomAvatarUri(),
              client: widget.room.client,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: roomTitle,
                  // 第二十四批（Q1 人類拍板「是」）：非一對一頂列房名旁顯示
                  // 成員數 (N)（LINE「群名(成員數)」語意）。官方來源＝
                  // RoomSummary.mJoinedMemberCount（SDK 房間摘要）；缺值
                  // 或例外 → 不顯示。
                  children: [
                    if (_topBarMemberSuffix().isNotEmpty)
                      TextSpan(
                        text: _topBarMemberSuffix(),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ), // 文案／視覺待 UI 定稿
        actions: [
          // P2.15＋批次 G（人類批准）：通話入口合併為**一鈕＋選單**
          // （音訊／視訊／mesh／LiveKit 全保留；條件不變：direct→_startCall、
          // 非 direct→mesh/LiveKit）。併入後條件 Retro = callManager != null。
          // 併入前：進行中以 disabled 表達（mesh）；合併後統一以 spinner 取代。
          if (widget.callManager != null)
            if (_calling)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              PopupMenuButton<String>(
                tooltip: '通話', // 文案草案，待人類設計定稿
                icon: const Icon(Icons.call_outlined),
                onSelected: (value) {
                  switch (value) {
                    case 'audio':
                      unawaited(_startCall(video: false));
                    case 'video':
                      unawaited(_startCall(video: true));
                    case 'mesh':
                      unawaited(_startGroupCall());
                    case 'livekit':
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LiveKitCallScreen(
                            room: widget.room,
                            manager: widget.callManager!,
                          ),
                        ),
                      );
                  }
                },
                itemBuilder: (ctx) => [
                  if (_callsAvailable) ...[
                    const PopupMenuItem(value: 'audio', child: Text('音訊通話')), // 文案草案
                    const PopupMenuItem(value: 'video', child: Text('視訊通話')), // 文案草案
                  ],
                  if (widget.callManager != null && !widget.room.isDirectChat) ...[
                    const PopupMenuItem(
                      value: 'mesh',
                      child: Text('群組通話（mesh）'),
                    ),
                    const PopupMenuItem(
                      value: 'livekit',
                      child: Text('多人通話（測試）'), // 文案草案（不含技術名詞），待人類設計定稿
                    ),
                  ],
                ],
              ),
          IconButton(
            tooltip: '搜尋',
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: _openRoomMenu,
            icon: const Icon(Icons.menu),
          ),
        ],
      ),

      body: hasImageBg
          ? Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: FileImage(File(_roomBackground!)),
                  fit: BoxFit.cover,
                ),
              ),
              child: chatBody,
            )
          : chatBody,
    );
  }

  List<Widget> _buildRows(String me, int latestOwnIndex) {
    final rows = <Widget>[];
    String? previousDayLabel;
    // 第二十二批（LINE_ref chat 泡泡稿）：同一發送者連續訊息合併為一組——
    // 頭像＋名字只在組頭，時間只在組尾。僅樣式分組，訊息資料不動。
    String? previousSender;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day = m.sentAt == null ? null : daySeparatorLabel(m.sentAt!);
      if (day != null && day != previousDayLabel) {
        // 第四十五批（LINE 版位）：日期分隔＝**圓角膠囊 chip**（淺色底、
        // 小字），取代原先的純文字；位置（訊息之間）不變。
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Align(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  day,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        );
        previousDayLabel = day;
      }
      final own = m.sender == me;
      final showRead = own && i == latestOwnIndex && _isReadByOthers(m);
      // 組頭＝發送者切換（日分隔 chip 已在上方另列，亦屬新組）。
      final showSender = previousSender == null || previousSender != m.sender;
      // 組尾＝下一則換人／換日／沒有下一則 → 顯示時間。
      final next = i + 1 < _messages.length ? _messages[i + 1] : null;
      final nextDay =
          (next == null || next.sentAt == null) ? null : daySeparatorLabel(next.sentAt!);
      final showTime = next == null ||
          next.sender != m.sender ||
          (nextDay != null && day != null && nextDay != day);
      previousSender = m.sender;
      // 批次十二⑤：訊息列掛 GlobalKey 錨點（橫幅點擊 → ensureVisible 跳轉）。
      if (m.eventId != null) {
        final key = _rowKeys[m.eventId!] ??= GlobalKey();
        rows.add(
          KeyedSubtree(
            key: key,
            child: _messageRow(
              m,
              own: own,
              showRead: showRead,
              showSender: showSender,
              showTime: showTime,
            ),
          ),
        );
      } else {
        rows.add(_messageRow(
          m,
          own: own,
          showRead: showRead,
          showSender: showSender,
          showTime: showTime,
        ));
      }
    }
    return rows;
  }

  Widget _messageRow(
    ChatMessageView m, {
    required bool own,
    required bool showRead,
    bool showSender = true,
    bool showTime = true,
  }) {
    final time = m.sentAt == null ? '' : formatChatTime(m.sentAt!);
    final bubbleColor = own
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    // 批次 E：長按 → 動作選單；左右滑動（速度門檻 500px/s，草案）→ 回覆。
    // 未註冊 onTap → 圖片 tile 既有點擊開預覽不受影響。
    // 第四十一批（LINE 版位）：貼圖與圖片**不帶泡泡底色**（LINE 的貼圖是小尺寸
    // 正方圖、照片是圓角縮圖，皆不滿版）；文字泡泡最大寬度＝視窗寬 × 係數。
    final windowWidth = MediaQuery.sizeOf(context).width;
    final isMedia = m.isImage || m.isSticker;
    final mediaWidth = isMedia
        ? maxBubbleWidth(windowWidth, kImageBubbleWidthFactor)
        : double.infinity;
    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 第四十八批：多選模式下點按＝切換選取（長按仍是動作選單）。
      onTap: _selectMode ? () => _toggleSelect(m) : null,
      onLongPress: () => unawaited(_showMessageActions(m, own)),
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() >= 500) {
          _openReply(m);
        }
      },
      child: isMedia
          ? ConstrainedBox(
              constraints: BoxConstraints(maxWidth: mediaWidth),
              child: m.isSticker
                  // 貼圖：LINE 慣例＝小尺寸正方圖（無圓角遮罩、無泡泡）。
                  ? SizedBox(
                      width: stickerDisplaySize(windowWidth),
                      height: stickerDisplaySize(windowWidth),
                      child: _ChatImageTile(
                        message: m,
                        loadImage: _loadFullImage,
                        onOpenImage: _openImagePreview,
                        // 無障礙：螢幕閱讀器以 alt text（貼圖 body）朗讀。
                        semanticLabel: '貼圖：'
                            '${m.body.isNotEmpty ? m.body : '未命名貼圖'}',
                      ),
                    )
                  : _ChatImageTile(
                      message: m,
                      loadImage: _loadImage,
                      onOpenImage: _openImagePreview,
                      semanticLabel: '圖片：'
                          '${m.body.isNotEmpty ? m.body : '未命名圖片'}',
                    ),
            )
          : Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          // 第四十八批：多選模式下，被選取的訊息加**主色外框**。
          border: _selectMode && _isSelected(m)
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
              : null,
        ),
        child: m.isCallInvite
            // 第二十二批（LINE_ref chat calls_history 構圖；Element 稿同構）：
            // 通話事件＝描邊 chip（圖示＋文案）。資料來源同舊版（官方
            // m.call.invite；Suggestion #8 既有語意）。
            ? _callInviteChip(m)
            // 第四十五批（LINE 版位：mx-reply 引言）：回覆訊息的泡泡頂端顯示
            // 「寄送者＋被回覆內容」的引言方塊（含左側色條），下方才是本文。
            : (m.replyToBody != null || m.replyToSender != null)
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReplyQuote(
                        sender: m.replyToSender,
                        body: m.replyToBody,
                      ),
                      const SizedBox(height: 4),
                      m.isPoll && m.event != null
                          ? _ChatPollTile(message: m, timeline: _timeline)
                          : m.isImage
                              ? _ChatImageTile(
                                  message: m,
                                  loadImage: _loadImage,
                                  onOpenImage: _openImagePreview,
                                )
                              : m.isSticker
                                  ? _ChatImageTile(
                                      message: m,
                                      loadImage: _loadFullImage,
                                      onOpenImage: _openImagePreview,
                                    )
                                  : m.isLocation
                                      ? _ChatLocationTile(
                                          message: m,
                                          onOpen: () => unawaited(_openLocation(m)),
                                        )
                                      : _isAttachment(m)
                                          ? _ChatFileTile(
                                              message: m,
                                              onOpen: () =>
                                                  unawaited(_openAttachment(m)),
                                            )
                                          : _formattedBodyWidget(m),
                    ],
                  )
            : m.isPoll && m.event != null
            ? _ChatPollTile(message: m, timeline: _timeline)
            : m.isImage
                ? _ChatImageTile(
                    message: m,
                    loadImage: _loadImage,
                    onOpenImage: _openImagePreview,
                  )
                // 批次 III-a：自訂貼圖（m.sticker）以圖片方式渲染；點擊進預覽。
                : m.isSticker
                    ? _ChatImageTile(
                        message: m,
                        loadImage: _loadFullImage,
                        onOpenImage: _openImagePreview,
                      )
                    // 批次 III-c：位置分享（m.location 官方事件）→ 圖示＋座標，可點開啟地圖。
                    : m.isLocation
                        ? _ChatLocationTile(
                            message: m,
                            onOpen: () => unawaited(_openLocation(m)),
                          )
                    // 批次 III-a：檔案／影片／音訊 → 圖示＋名稱，可點擊開啟。
                    : _isAttachment(m)
                        ? _ChatFileTile(
                            message: m,
                            onOpen: () => unawaited(_openAttachment(m)),
                          )
                        // 第三十五批 #14：formatted_body（Element X 式有限
                        // 白名單渲染；解析不適用退回純文字路徑）。
                        : _formattedBodyWidget(m),
      ),
    );
    // 文字泡泡最大寬度（LINE 版位）：自己與他人皆限制，避免長文滿版。
    final textBubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxBubbleWidth(windowWidth, kTextBubbleWidthFactor),
      ),
      child: content,
    );
    final reactions = _reactionsOf(m);

    if (own) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showRead)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '已讀', // 文案待定稿；資料來源：SDK 官方 receipts（僅顯示既有資料）
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showTime && time.isNotEmpty)
                  Text(time, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 6),
                Flexible(child: isMedia ? content : textBubble),
              ],
            ),
            // 第二十四批：已編輯記號（僅純文字列；官方 m.replace 聚合）。
            if (m.isEdited && _isPlainTextRow(m)) ...[
              const SizedBox(height: 2),
              Text('(已編輯)', style: Theme.of(context).textTheme.labelSmall), // 文案草案
            ],
            if (reactions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.topRight,
                child: _reactionChips(m, reactions),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 批次 E：發送者頭像（官方 avatar mxc；無頭像 → 首字圓圈）。
          // 第二十二批：同一發送者連續訊息 → 組頭才顯示頭像，其餘留白對位。
          if (showSender)
            _SenderAvatar(
              label: _senderName(m),
              avatarUri: _senderAvatarUri(m),
              client: widget.room.client,
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSender) ...[
                  Text(
                    // 「room 內好友名稱」：官方 calcDisplayname（見 _senderName）。
                    _senderName(m),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 2),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: isMedia ? content : textBubble),
                    if (showTime && time.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(time, style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ],
                ),
                // 第二十四批：已編輯記號（僅純文字列；官方 m.replace 聚合）。
                if (m.isEdited && _isPlainTextRow(m)) ...[
                  const SizedBox(height: 2),
                  Text('(已編輯)', style: Theme.of(context).textTheme.labelSmall), // 文案草案
                ],
                if (reactions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.topLeft,
                    child: _reactionChips(m, reactions),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 第二十二批：通話事件 chip（LINE_ref chat calls_history／Element 稿構圖；
  /// 只換樣式，語意維持 Suggestion #8）。
  Widget _callInviteChip(ChatMessageView m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call, size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              m.body,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// 第二十二批：頂列頭像 Uri（官方資料；純記憶體讀取、無副作用）。
  /// 一對一＝對方 m.room.member avatar_url（同 _senderAvatarUri 鏈路）；
  /// 群組＝Room.avatar（官方 canonical alias 頭像欄）。無 → null 回退首字。
  Uri? _roomAvatarUri() {
    try {
      if (widget.room.isDirectChat) {
        final mxid = widget.room.directChatMatrixID;
        if (mxid == null || mxid.isEmpty) {
          return null;
        }
        final member = widget.room.getState(EventTypes.RoomMember, mxid);
        final url = member?.content['avatar_url'];
        if (url is String && url.isNotEmpty) {
          return Uri.tryParse(url);
        }
        return null;
      }
      return widget.room.avatar;
    } catch (_) {
      return null;
    }
  }

  /// 批次 E：發送者頭像 Uri。官方資料來源：房間 `m.room.member` state 的
  /// `avatar_url`（SDK `Room.getState`，**純記憶體讀取、無副作用**）。
  /// 不用 `Event.senderFromMemoryOrFallback`：它會 fire-and-forget
  /// `requestUser`（觸碰 DB；注入測試環境未開啟 → 非同步錯誤）。
  /// 無 state／無例外 → null → 頭像磚退回首字圓圈。
  Uri? _senderAvatarUri(ChatMessageView m) {
    final event = m.event;
    if (event == null) {
      return null;
    }
    try {
      final member = widget.room.getState(EventTypes.RoomMember, event.senderId);
      final url = member?.content['avatar_url'];
      if (url is String && url.isNotEmpty) {
        return Uri.tryParse(url);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 批次 III-a：表情反應聚合（含**自己**的反應事件 ID）。
  /// 取消 reaction ＝ 官方 API 收回自己那筆 m.reaction 事件（見 _toggleReaction）。
  Map<String, ({int count, String? myEventId})> _reactionsOf(ChatMessageView m) {
    final timeline = _timeline;
    final eventId = m.event?.eventId;
    if (timeline == null || eventId == null) {
      return const {};
    }
    try {
      final set = timeline.aggregatedEvents[eventId]?[RelationshipTypes.reaction];
      if (set == null) {
        return const {};
      }
      final me = widget.room.client.userID;
      final out = <String, ({int count, String? myEventId})>{};
      for (final e in set) {
        // 第三輪重分析（2026-11-03）：SDK `Timeline.addAggregatedEvent`
        //（timeline.dart L507）在**建構時回填**聚合，且不過濾 `redacted`
        // 事件——DB 殘留的已收回 reaction 物件會讓 chips 一直顯示自己
        // 的反應（紅框）→ 送出重複反應／取消永不生效。此處官方
        // `Event.redacted`（event.dart L58）過濾已收回事件。
        if (e.redacted) {
          continue;
        }
        final key = (e.content['m.relates_to'] as Map<String, dynamic>?)?['key'];
        if (key is String && key.isNotEmpty) {
          // 第九次：官方收回成功（或 server 已無該 reaction）→ session 抑制
          // 清單命中自己那筆 → 不計入 count、不顯示自己已反應（＝取消生效；
          // SDK 聚合樹對「早於本 chunk」的收回不會清除物件，見欄位註解）。
          if (me != null &&
              e.senderId == me &&
              _cancelledReactions.contains('$eventId|$key')) {
            continue;
          }
          // 第十三批③：自己的反應＝本 session 有送出（_myReactionEvents
          // 記得）才算「同步中」；沒記到（跨 session 殘留／其他裝置）→ 起動
          // 一次官方 /relations 重掃（見 _scheduleReactionResidueRefresh）。
          if (me != null &&
              e.senderId == me &&
              _myReactionEvents['$eventId|$key'] != e.eventId) {
            _scheduleReactionResidueRefresh(eventId);
          }
          // SDK 聚合會排除已收回的事件；特殊情況（收回不同步）由 server 丟錯。
          final existing = out[key];
          if (existing != null && existing.myEventId != null) continue;
          out[key] = (
            count: existing == null ? 1 : existing.count + 1,
            myEventId: e.senderId == me ? e.eventId : existing?.myEventId,
          );
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// 本 session 內自己已送出的 reaction（'$targetId|$emoji' → 自己那筆
  /// m.reaction 的 eventId）。SDK `Room.sendReaction` 回傳 server 產生的
  /// eventId（官方 API），因此送出後立即記住，不依賴 timeline 聚合同步。
  final Map<String, String> _myReactionEvents = {};

  /// 第九次（人類回饋 2026-11-05「reaction 仍無法取消」）第四輪根因＝SDK
  /// 官方源碼：收回事件只在兩種情況把目標事件標記為已收回——目標＝
  /// `room.lastEvent`（client.dart L3184-3188）或目標**仍在目前 timeline
  /// chunk**（timeline.dart L688-708 `_findEvent` 找不到即整段跳過，
  /// 聚合樹**不清除**）。自己的 reaction 幾乎總是「早於目前 chunk 的舊
  /// 事件」→ 官方收回已生效，但聚合殘留未標記的物件 → `Event.redacted`
  /// 永不成立、chips 永遠顯示（第三輪的 redacted 過濾救不到此情境）。
  /// SDK 無「清除聚合樹」官方介面 → 依官方收回**成功**為據，session 內
  /// 抑制自己那筆（UI 資料層過濾；重送同一 emoji 時解除）。已知限制：
  /// 跨 session 的 DB 殘留（重開 App 後）本輪仍可能出現，待人類實測再启 kv。
  final Set<String> _cancelledReactions = {};

  /// 第十三批③：已請求官方 /relations 重掃的 target（一次為限，防止每次
  /// rebuild 重複發請求）。
  final Set<String> _reactionResidueRefreshed = {};

  /// 批次十三③（人類實測「上一 session 加的反應重開 App 後仍顯示」）根因
  /// ＝SDK 聚合樹建構回填**不過濾** redacted（timeline.dart addAggregated
  /// Event），且歷史事件（早於本 chunk）的收回不會標記聚合樹物件 → 任何
  /// session 內抑制清單都救不了「重開 App 後的舊殘留」。修＝純官方：
  /// `Timeline.fetchAggregatedEvents(targetId, RelationshipTypes.reaction)`
  ///（/relations API）——server 回的是權威清單；已收回的 reaction 依規格被
  /// 收回（`m.relates_to` key 一併被剝除）→ `addAggregatedEvent` 的
  /// `_removeEventFromSet` 以新物件**替換**舊殘留 → `Event.redacted`／缺 key
  /// 自然不計入。成型行為：殘留消失；若其實是**仍有效的舊反應**，server 回
  /// 原件 → 照常顯示（不會誤吞）。去重：每 target 一次（`_relation
  /// ResidueRefreshed`）；SDK 對同一 relation 成功後跳過重抓（_relation
  /// Requests 留 key）、失敗自動允許重試。**成本披露**：每則「有你這台
  /// 設備反應過」的訊息進房最多一次背景查詢。
  void _scheduleReactionResidueRefresh(String targetId) {
    if (!_reactionResidueRefreshed.add(targetId)) {
      return;
    }
    final timeline = _timeline;
    unawaited(() async {
      try {
        await timeline?.fetchAggregatedEvents(
          targetId,
          RelationshipTypes.reaction,
        );
      } catch (_) {
        // 網路失敗：靜默（聚合樹維持現狀，下次觸發可再試——set 已擋重複，
        // 本 session 這則不再重試，可接受）。
      }
      if (mounted) {
        setState(() {});
      }
    }());
  }

  /// 批次 III-a：表情反應**切換**（人類指示「reaction 無法取消」）：
  /// 未反應 → 官方 `Room.sendReaction`；已反應（自己）→ 官方
  /// `Room.redactEvent(自己那筆 m.reaction 的 eventId)`＝取消。
  ///
  /// 根因重寫（人類回報 2026-11-03 第 2 點）：`Timeline.aggregatedEvents`
  /// 僅含**目前 timeline chunk 內**的事件；自己的 reaction 若落在較早的
  /// 歷史窗口（滑回舊訊息再加反應）或聚合尚未同步，`_reactionsOf` 會回報
  /// 「自己尚無反應」→ 點擊變成再送一個重複 reaction 而**永遠無法取消**。
  /// 修正：先用官方 `Timeline.fetchAggregatedEvents`（/relations API）補抓，
  /// 再退回 raw timeline 掃描，兩者都無才視為「未反應」送出。
  Future<void> _toggleReaction(ChatMessageView m, String emoji) async {
    final event = m.event;
    final targetId = event?.eventId;
    if (event == null || targetId == null) {
      return;
    }
    void redraw() {
      if (mounted) setState(() {}); // chips 由聚合在新幀取數。
    }

    var mine = _myReactionId(m, emoji);
    if (mine == null) {
      // 官方 API：/relations 補抓「目前 chunk 外」的相關事件到聚合
      // （連續同請求會 coalesce，不會重複打網路）。
      try {
        await _timeline?.fetchAggregatedEvents(
          targetId,
          RelationshipTypes.reaction,
        );
        mine = _reactionsOf(m)[emoji]?.myEventId;
      } catch (_) {
        // 失敗 → 繼續退到 raw 掃描。
      }
    }
    try {
      if (mine != null) {
        try {
          await widget.room.redactEvent(mine);
          _myReactionEvents.remove('$targetId|$emoji');
          // 第九次：官方收回成功 → session 抑制（聚合樹不清除「早於本
          // chunk」的事件；見 _cancelledReactions 註解）。
          _cancelledReactions.add('$targetId|$emoji');
        } catch (e) {
          // 第三輪重分析：memo／聚合可能指向「已收回但本機殘留」的事件
          // ——server 對重複收回官方回 M_NOT_FOUND；此時取消**已生效**
          //（chips 由 `_reactionsOf` 的 redacted 過濾正確顯示），
          // 不再視為失敗洗版提示。其他錯誤仍走退路／提示。
          final msg = e.toString().toLowerCase();
          final alreadyGone = msg.contains('m_not_found') ||
              msg.contains('not found') ||
              msg.contains('404');
          if (!alreadyGone) {
            rethrow;
          }
          _myReactionEvents.remove('$targetId|$emoji');
          // 第九次：server 已無此 reaction（先前已收回）→ 同樣抑制。
          _cancelledReactions.add('$targetId|$emoji');
        }
      } else {
        // 官方 sendReaction 回傳 server 產生的 reaction eventId。
        final sentId = await widget.room.sendReaction(targetId, emoji);
        if (sentId != null) {
          _myReactionEvents['$targetId|$emoji'] = sentId;
          // 第九次：重新反應 → 解除 session 抑制（否則自己那筆被吞）。
          _cancelledReactions.remove('$targetId|$emoji');
        }
      }
      redraw();
    } catch (e) {
      // 聚合補抓後仍判定「未反應」但送出失敗 → 最後一次 raw 掃描再確認
      // （可能剛剛的 redact 事件尚未進 chunk）。
      try {
        mine = _myReactionId(m, emoji);
        if (mine != null) {
          await widget.room.redactEvent(mine);
          _myReactionEvents.remove('$targetId|$emoji');
          _cancelledReactions.add('$targetId|$emoji'); // 第九次：抑制
          redraw();
          return;
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('反應失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 找出「自己對 targetId $emoji 的 reaction event id」。依序：
  /// session 內記憶（sendReaction 回傳值）→ timeline 聚合 → raw timeline 掃描。
  String? _myReactionId(ChatMessageView m, String emoji) {
    final targetId = m.event?.eventId;
    if (targetId != null) {
      final key = '$targetId|$emoji';
      final memo = _myReactionEvents[key];
      if (memo != null) {
        return memo;
      }
    }
    final direct = _reactionsOf(m)[emoji]?.myEventId;
    if (direct != null) {
      return direct;
    }
    return _scanOwnReaction(targetId, emoji);
  }

  /// raw timeline 掃描（聚合失效時的官方資料退路；無自製協定邏輯）。
  String? _scanOwnReaction(String? targetId, String emoji) {
    final timeline = _timeline;
    if (timeline == null || targetId == null) {
      return null;
    }
    final me = widget.room.client.userID;
    for (final e in timeline.events) {
      if (e.redacted ||
          e.type != EventTypes.Reaction ||
          (me != null && e.senderId != me)) {
        continue;
      }
      final rel =
          (e.content['m.relates_to'] as Map<String, dynamic>?);
      if (rel?['key'] == emoji && rel?['event_id'] == targetId) {
        return e.eventId;
      }
    }
    return null;
  }

  /// 第三十五批 #14：formatted_body 渲染（Element X 式有限白名單；
  /// markdown_message.dart 純函式）。無 format 欄位／解析不適用 → 既有
  /// `_linkifiedBody` 純文字路徑。連結點擊＝既有 url_launcher 外部瀏覽器。
  Widget _formattedBodyWidget(ChatMessageView m) {
    final content = m.event?.content;
    final formattedBody = content?['formatted_body'];
    if (content?['format'] != 'org.matrix.custom.html' ||
        formattedBody is! String ||
        formattedBody.isEmpty) {
      return _linkifiedBody(m.body);
    }
    try {
      final theme = Theme.of(context);
      final base = theme.textTheme.bodyMedium ??
          const TextStyle(fontSize: 14);
      final w = formattedMessageWidget(
        formattedBody,
        baseStyle: base,
        linkStyle: TextStyle(
          color: theme.colorScheme.primary, // 連結色草案（主題色）
          decoration: TextDecoration.underline,
        ),
        onLinkTap: (url) async {
          final uri = Uri.tryParse(url);
          if (uri == null) {
            return;
          }
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            // 開啟失敗靜默（v0；草案行為）。
          }
        },
      );
      return w ?? _linkifiedBody(m.body);
    } catch (_) {
      return _linkifiedBody(m.body); // 渲染異常 → 退回純文字（fail-open）
    }
  }

  /// 批次十（人類指示「訊息偵測是否有 URL 並可點選」）：純文字訊息內偵測
  /// URL（http/https）→ 該段以可點 TextStyle 呈現，點按以官方
  /// `url_launcher`（既有依賴；login_screen 已用）開外部瀏覽器。
  /// 失敗靜默（不洗版）；URL 認不出／解析失敗仍是純文字。無第三方 linkify。
  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  Widget _linkifiedBody(String body) {
    final matches = _urlPattern.allMatches(body).toList();
    if (matches.isEmpty) {
      return Text(body);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, match.start)));
      }
      // 去除結尾標點（中英文標點黏在 URL 後是常見誤判）。
      var url = match.group(0)!;
      while (url.isNotEmpty && '.,;:!?)】）」』、'.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
      }
      final trailing = match.group(0)!.substring(url.length);
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(url);
              if (uri == null) {
                return;
              }
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                // 開啟失敗靜默（v0；草案行為）。
              }
            },
        ),
      );
      cursor = match.start + url.length;
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
        cursor += trailing.length;
      }
    }
    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: spans),
      // 未偵測到 URL 的純段落仍走原 selectable/預設行為之外觀一致。
    );
  }

  // ── 第四十八批：訊息批次操作（多選）────────────────────────────────

  /// 開／關多選模式（長按訊息 → 「多選」）。
  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) {
        _selectedEventIds.clear();
        _selectedWithoutId.clear();
      }
    });
  }

  /// 切換某則訊息的選取狀態（多選模式下點按訊息）。
  void _toggleSelect(ChatMessageView m) {
    if (!_selectMode) return;
    setState(() {
      final id = m.eventId;
      if (id != null) {
        if (!_selectedEventIds.remove(id)) {
          _selectedEventIds.add(id);
        }
      } else {
        if (!_selectedWithoutId.remove(m)) {
          _selectedWithoutId.add(m);
        }
      }
    });
  }

  /// 某則訊息是否已被選取。
  bool _isSelected(ChatMessageView m) {
    final id = m.eventId;
    if (id != null) return _selectedEventIds.contains(id);
    return _selectedWithoutId.contains(m);
  }

  /// 取得目前已選取的訊息清單（依畫面順序）。
  List<ChatMessageView> get _selectedMessages => _messages
      .where((m) => _isSelected(m))
      .toList(growable: false);

  /// 批次收回（刪除）已選取訊息——官方 `Room.redactEvent`（伺服器端收回，
  /// 所有人都會看到「已收回」）。只收回**自己**的訊息（他人訊息需權限，
  /// 失敗如實提示）。
  Future<void> _batchRedactSelected() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('收回 ${selected.length} 則訊息？'), // 文案草案
        content: const Text(
          '所有人都會看到這些訊息已被收回。\n此操作無法復原。',
        ), // 文案草案
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('收回'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var ok = 0;
    var failed = 0;
    for (final m in selected) {
      final event = m.event;
      if (event == null) {
        failed++;
        continue;
      }
      try {
        // 官方 `Room.redactEvent`（伺服器端收回；需權限）。
        await widget.room.redactEvent(event.eventId);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selectedEventIds.clear();
      _selectedWithoutId.clear();
    });
    unawaited(_load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已收回 $ok 則訊息' // 文案草案
              : '已收回 $ok 則，$failed 則失敗（可能是他人訊息）', // 文案草案
        ),
      ),
    );
  }

  /// 批次轉寄（分享）已選取訊息到其他聊天室——重用官方分享流程
  /// （`ShareToRoomScreen`）。只轉寄**文字**內容（媒體附件逐則轉寄較複雜，
  /// 不在本批範圍）。
  Future<void> _batchForwardSelected() async {
    final selected = _selectedMessages;
    if (selected.isEmpty) return;
    final text = selected
        .map((m) => m.body)
        .where((b) => b.isNotEmpty)
        .join('\n');
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('選取的訊息沒有可轉寄的文字')), // 文案草案
      );
      return;
    }
    setState(() {
      _selectMode = false;
      _selectedEventIds.clear();
      _selectedWithoutId.clear();
    });
    await _shareMessageText(text);
  }

  /// 批次 E：進入回覆狀態（滑動訊息／長按選單回覆）。
  void _openReply(ChatMessageView m) {
    setState(() {
      _replyTo = m;
      _editTarget = null; // 第二十四批：回覆／編輯互斥。
    });
  }

  /// 批次 E／III-a：表情反應 chips（草案 UI；點擊 → 切換：未反應則送出、
  /// 已反應則取消；已表示者外框加粗）。
  Widget _reactionChips(
      ChatMessageView m, Map<String, ({int count, String? myEventId})> reactions) {
    return Wrap(
      spacing: 6,
      children: [
        for (final entry in reactions.entries)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(_toggleReaction(m, entry.key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Container(
                decoration: entry.value.myEventId != null
                    ? BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.value.count}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 批次 E：長按訊息 → 動作選單（草案；全 UI 文案待人類設計定稿）。
  /// 表情反應（預設 6 emoji 列）／回覆／複製文字／檢舉／分享至外部。
  /// 條件：無 event（注入測試環境）→ 無反應列；圖片／投票 → 無複製與分享
  /// （圖片分享在預覽畫面已有；投票 body 為協定 fallback 文字、無意義）；
  /// 本人訊息 → 無檢舉。
  Future<void> _showMessageActions(ChatMessageView m, bool own) async {
    final hasEvent = m.event != null;
    final preview = m.body.isEmpty
        ? '(無文字)'
        : (m.isPoll ? '[投票]' : m.body);
    // 動作先由 sheet 回傳代號，回到 State context（sheet 已關）再執行，
    // 避免 pop 後仍觸碰 builder context。
    final action = await showModalBottomSheet<String>(
      context: context,
      // 第三十五批 #14：項目變多 → 允許 sheet 用較高高度（內容 min-size
      // 自適應；SingleChildScrollView 保底可捲動）。
      isScrollControlled: true,
      builder: (context) => SafeArea(
        // 第三十五批 #14：選單項目變多（含「查看原始訊息」）→ 小視窗
        // 會溢出，改可捲動（草案；樣式待人類定稿）。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    '${_senderName(m)}：$preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (hasEvent) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        // 預設 emoji 組為草案，待人類設計定稿。
                        for (final emoji in const ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                          TextButton(
                            onPressed: () => Navigator.of(context).pop('react:$emoji'),
                            child: Text(emoji),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('回覆'), // 文案草案
                onTap: () => Navigator.of(context).pop('reply'),
              ),
              // 第四十八批：多選（批次收回／轉寄）。
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('多選'), // 文案草案
                onTap: () => Navigator.of(context).pop('multiselect'),
              ),
              // 第二十四批：編輯自己的文字訊息（官方 m.replace；SDK helper
              // `sendTextEvent(editEventId:)`）。長按選單進入，送出走編輯鏈。
              if (own &&
                  hasEvent &&
                  !(m.event?.redacted ?? false) &&
                  m.event?.messageType == 'm.text')
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('編輯'), // 第二十四批；文案草案
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
              if (own && hasEvent && !(m.event?.redacted ?? false))
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('收回（刪除訊息）'), // 文案草案
                  subtitle: const Text('所有人都會看到此訊息已被收回'), // 文案草案
                  onTap: () => Navigator.of(context).pop('redact'),
                ),
              if (!m.isImage && !m.isPoll)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('複製文字'), // 文案草案
                  onTap: () => Navigator.of(context).pop('copy'),
                ),
              if (!own)
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const Text('檢舉'), // 文案草案
                  onTap: () => Navigator.of(context).pop('report'),
                ),
              if (!m.isImage && !m.isPoll)
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('分享至外部'), // 文案草案
                  onTap: () => Navigator.of(context).pop('share'),
                ),
              // 第三十五批 #14：查看原始訊息（事件 content 原樣；Element
              // view-source 式；注入測試無 event 時不顯示）。
              if (hasEvent)
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: const Text('查看原始訊息'), // 文案草案
                  onTap: () => Navigator.of(context).pop('raw'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action.startsWith('react:')) {
      unawaited(_toggleReaction(m, action.substring('react:'.length)));
      return;
    }
    switch (action) {
      case 'raw':
        _showRawMessage(m);
      case 'reply':
        setState(() {
          _replyTo = m;
          _editTarget = null; // 第二十四批：回覆／編輯互斥（同為輸入列前狀態）。
        });
      case 'edit':
        // 第二十四批：進入編輯狀態；輸入框先填入原文字（送出＝官方
        // sendTextEvent(editEventId:)，見 _onSend）。
        setState(() {
          _editTarget = m;
          _replyTo = null;
          // 第三十五批 #5：編輯沿用原事件語意 → 無聲旗標不套用（復位）。
          _silentSend = false;
        });
        _inputController.text = m.body;
        _inputController.selection = TextSelection.collapsed(
          offset: m.body.runes.length,
        );
      case 'multiselect':
        // 第四十八批：進入多選模式並選取該則。
        setState(() {
          _selectMode = true;
          _selectedEventIds.clear();
          _selectedWithoutId.clear();
        });
        _toggleSelect(m);
      case 'redact':
        unawaited(_redactMessage(m));
      case 'copy':
        unawaited(Clipboard.setData(ClipboardData(text: m.body)));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已複製')), // 文案草案
        );
      case 'report':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReportUserScreen(targetDefault: m.sender),
          ),
        );
      case 'share':
        if (m.event != null &&
            (m.isImage || m.isSticker || _isAttachment(m))) {
          unawaited(_shareAttachment(m));
        } else {
          await _shareMessageText(m.body);
        }
    }
  }

  /// 第三十五批 #14：查看原始訊息（事件 content 原樣 JSON；Element
  /// view-source 式；SelectableText 可複製；草案 UI）。
  void _showRawMessage(ChatMessageView m) {
    final event = m.event;
    if (event == null) {
      return;
    }
    String raw;
    try {
      raw = const JsonEncoder.withIndent('  ').convert(event.content);
    } catch (_) {
      raw = event.content.toString();
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('原始訊息'), // 文案草案
        content: SingleChildScrollView(
          child: SelectableText(raw),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('關閉'), // 文案草案
          ),
        ],
      ),
    );
  }

  /// 批次 III-a：收回訊息（官方 `Room.redactEvent`；無自製協定邏輯）。
  /// 收回後由 SDK 官方 redaction 機制標記事件；本畫面重撈會顯示『[已收回]』。
  Future<void> _redactMessage(ChatMessageView m) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    try {
      await widget.room.redactEvent(event.eventId);
      if (mounted) {
        unawaited(_load());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收回失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 批次 E：把訊息文字經系統分享 sheet 分享到外部 App（share_plus，
  /// 人類 2026-11-01 批准的分享路徑）。
  Future<void> _shareMessageText(String text) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 第 19 點：分享檔案（圖片／貼圖／附件）而非只傳送標題。
  /// 下載解密後暫存到系統臨時目錄，再經 share_plus 分享給外部 App。
  Future<void> _shareAttachment(ChatMessageView m) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    final eventId = m.eventId ?? '';
    final cached = _openedFiles[eventId];
    if (cached != null && File(cached).existsSync()) {
      unawaited(_shareFile(File(cached), m.body));
      return;
    }
    try {
      final file = await event.downloadAndDecryptAttachment();
      final dir = await Directory.systemTemp.createTemp('ring_share');
      final outFile = File('${dir.path}/${_attachmentFileName(event, file)}');
      await outFile.writeAsBytes(file.bytes);
      if (eventId.isNotEmpty) {
        _openedFiles[eventId] = outFile.path;
      }
      unawaited(_shareFile(outFile, m.body));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享檔案失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 分享單一檔案到系統分享 sheet。
  Future<void> _shareFile(File f, String name) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path, name: name)], text: name),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('開啟失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 批次 E：回覆預覽列（輸入列上方；點 X 解除回覆狀態）。草案 UI。
  Widget _buildReplyBar(ChatMessageView reply) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${reply.sender}：${reply.isPoll ? '[投票]' : reply.body}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: '解除回覆', // 文案草案
            onPressed: () => setState(() => _replyTo = null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// 第二十四批：編輯狀態預覽列（輸入列上方；回覆／編輯互斥，同構圖）。
  Widget _buildEditBar(ChatMessageView target) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '編輯訊息：${target.body.isEmpty ? '(無文字)' : target.body}', // 文案草案
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: '解除編輯', // 文案草案
            onPressed: () async {
              setState(() => _editTarget = null);
              _inputController.clear();
              await _stopTyping();
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// 第二十四批：送出編輯（官方 `Room.sendTextEvent(editEventId:)`，SDK
  /// 內建組出 m.replace／m.new_content 規格事件；429 退避重試同一般送出）。
  /// **不入離線佇列**：編輯文字入 OfflineQueue 會變成新訊息，語意不對 →
  /// 失敗僅提示並保留編輯狀態（還原文字於輸入框，重按送出仍是編輯）。
  Future<void> _sendEdit(String text, ChatMessageView target) async {
    final eventId = target.event?.eventId;
    if (eventId == null || eventId.isEmpty) {
      // 注入測試／無事件來源 → 無可編輯目標，不發送（不靜默吞）。
      if (mounted) {
        setState(() {
          _message = '此訊息無法編輯'; // 文案草案
        });
      }
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    _inputController.clear();
    String? error;
    try {
      await sendWithRateLimitRetry(
        () => widget.room.sendTextEvent(text, editEventId: eventId),
      );
    } catch (e) {
      error = '編輯失敗：$e（離線時暫不支援編輯，稍後重試）'; // 文案草案
      _inputController.text = text; // 還原文字；_editTarget 保留 → 重送仍是編輯。
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _message = error;
        _editTarget = error == null ? null : _editTarget;
      });
    }
    if (error == null) {
      await _stopTyping();
      // 第四十二批（人類回報「已編輯訊息仍然還顯示過去訊息」）：
      // 編輯成功後**必須重載訊息列表**——舊實作沒有重載 → 畫面仍停在舊內容，
      // 直到下一次 sync 才會更新。重載時 `_resolveEditMap` 會以自建對照
      // （或官方 relations）套用新內容。
      unawaited(_load());
    }
  }

  /// 第二十四批：typing 發送（官方 `Room.setTyping`；空白＝停止）。
  /// 節流：7 秒內不重複送 true（server timeout 10 秒遮蓋中間送出的窗口）。
  Future<void> _maybeSendTyping() async {
    try {
      if (widget.room.membership != Membership.join) {
        return;
      }
      final typing = _inputController.text.trim().isNotEmpty;
      if (!typing) {
        await _stopTyping();
        return;
      }
      final now = DateTime.now();
      if (_lastTypingSentAt != null &&
          now.difference(_lastTypingSentAt!) < const Duration(seconds: 7)) {
        return;
      }
      _lastTypingSentAt = now;
      await widget.room.setTyping(true, timeout: 10000);
    } on Object {
      // typing 為告知性資訊：失敗不影響送訊（不阻擋、不提示）。
    }
  }

  /// 第二十四批：停止 typing（送出／清空輸入／解除編輯時；例外靜默）。
  Future<void> _stopTyping() async {
    if (_lastTypingSentAt == null) {
      return;
    }
    _lastTypingSentAt = null;
    try {
      await widget.room.setTyping(false);
    } on Object {
      // 同上：告知性資訊，失敗不影響。
    }
  }

  /// 第二十四批：typing id 清單（官方通路：`Room.ephemerals['m.typing']`
  /// 的 content.user_ids——`Room.typingUsers` getter 會對無 member state 的
  /// 使用者 fire-and-forget `requestUser`（觸碰 DB；本檔慣例避免任何告知性
  /// UI 觸發副作用），故直讀官方 ephemerals map，純記憶體、零副作用）。
  List<String> _typingIds() {
    try {
      final raw = widget.room.ephemerals['m.typing']?.content['user_ids'];
      if (raw is! List) {
        return const [];
      }
      final me = widget.room.client.userID;
      return List<String>.of([
        for (final id in raw)
          if (id is String && id.isNotEmpty && id != me) id,
      ]);
    } on Object {
      return const [];
    }
  }

  /// 第二十四批：typing 摘要（排除自己；純記憶體字串，供 onSync 指紋與
  /// ticker 複驗共用）。回傳可變清單副本（呼叫端需要 sort）。
  String _typingSummary() {
    final ids = _typingIds();
    if (ids.isEmpty) {
      return '';
    }
    ids.sort();
    return ids.join(',');
  }

  /// 第二十四批：SDK 內建超時清空 m.typing（room.dart
  /// _clearTypingIndicatorTimer）**不觸發 onSync** → 本地 ticker 每 4 秒
  /// 複驗一次，清空後自動取消。只在顯示中（摘要非空）時持續運作。
  void _syncTypingTicker() {
    final hasTyping = _lastTypingSummary?.isNotEmpty ?? false;
    if (hasTyping) {
      _typingTicker ??= Timer.periodic(const Duration(seconds: 4), (_) {
        if (_typingSummary().isEmpty) {
          _typingTicker?.cancel();
          _typingTicker = null;
          _lastTypingSummary = '';
          if (mounted) {
            setState(() {});
          }
        }
      });
      return;
    }
    _typingTicker?.cancel();
    _typingTicker = null;
  }

  /// 第二十四批：typing 指示列（成員名稱；與既有 `_senderName` 同一非 DB
  /// 鏈路：getState(RoomMember) → asUser.calcDisplayname()；無 state →
  /// 顯示原 ID，**不觸發 requestUser**——見 _typingIds）。無人輸入 → null。
  Widget? _typingLabelRow() {
    final summary = _typingSummary();
    if (summary.isEmpty) {
      return null;
    }
    try {
      final room = widget.room;
      final ids = _typingIds();
      if (ids.isEmpty) {
        return null;
      }
      final names = <String>[];
      for (final id in ids) {
        String name = id;
        try {
          final member = room.getState(EventTypes.RoomMember, id);
          final n = member?.asUser(room).calcDisplayname();
          if (n != null && n.isNotEmpty) {
            name = n;
          }
        } catch (_) {
          // 無 member state → 顯示原 ID。
        }
        names.add(name);
      }
      final who = names.first;
      // 文案草案（Element「X is typing…」同語意）。
      final label = names.length == 1
          ? '$who 正在輸入…'
          : '$who 等 ${names.length} 人正在輸入…';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    } on Object {
      return null;
    }
  }

  /// 第二十四批（Q1 人類拍板「是」）：頂列成員數後綴（LINE「群名(成員數)」
  /// 語意）。一對一不顯示；官方來源＝`RoomSummary.mJoinedMemberCount`
  /// （SDK 房間摘要，純記憶體）；缺值／例外 → 空字串不顯示。
  String _topBarMemberSuffix() {
    if (widget.room.isDirectChat) {
      return '';
    }
    try {
      // `Room.summary` 非 null（未同步時為空摘要，成員數為 null）。
      final joined = widget.room.summary.mJoinedMemberCount;
      if (joined != null && joined > 0) {
        return ' ($joined)';
      }
    } on Object {
      // 摘要未同步 → 不顯示。
    }
    return '';
  }

  /// 第三十五批 #13：Markdown 送出開關（kv `markdown_enabled` 持久化；
  /// 即時生效不重啟；無 DB 環境僅 session 內生效）。
  Future<void> _toggleMarkdown() async {
    final next = !_markdownOn;
    setState(() => _markdownOn = next);
    try {
      await AppSettings.set('markdown_enabled', next ? '1' : '0');
    } catch (_) {
      // 測試環境／無 sqflite：靜默。
    }
  }

  /// 批次 III-b：貼圖 mimetype 由副檔名判斷。**第三十五批 #4 改白名單**：
  /// 僅接受圖片類（含動圖 GIF／動圖 WebP——Flutter `Image` 原生動畫渲染、
  /// 支援透明背景，且圖片類本無音軌＝天然靜音）；影片／音訊／未知回 null
  /// （呼叫端拒收），**不再** fallthrough 到 webp（舊行為會把影片當 webp 傳）。
  String? _stickerMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'jpg' || 'jpeg' => 'image/jpeg',
      'bmp' => 'image/bmp',
      'webp' => 'image/webp',
      _ => null, // 第三十五批 #4：不放聲音——影片／音訊一律不是貼圖
    };
  }

  /// 批次 III-b（人類回報「自訂貼圖無法使用」）：送出自訂貼圖。
  /// 官方路徑：`Client.uploadContent` 上傳 → `m.sticker` 事件
  /// （標準規格 content：url／info{w,h,mimetype}／body；人類已確認用
  /// m.sticker 於 Element 等客戶端互相渲染）。無自製協定邏輯。
  ///
  /// 第三十八批：zip 貼圖包匯入者**已上傳 homeserver**（`mxcUrl`）→ 直接沿用，
  /// 不重複上傳；`body` 用貼圖包的 alt text。
  Future<void> _sendSticker(StickerLibraryEntry entry) async {
    try {
      final path = entry.path;
      final name = path.split('/').last;
      // 第三十五批 #4（人類「動圖 stickers 不放聲音」＋問答拍板 GIF 路線）：
      // 貼圖僅接受圖片類；影片／音訊拒收並提示。
      final mime = _stickerMime(name);
      if (mime == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('貼圖僅支援圖片（含動圖 GIF／WebP），不支援影片或聲音'), // 文案草案
            ),
          );
        }
        return;
      }
      final bytes = await File(path).readAsBytes();
      final dims = await _imageDimensions(bytes);
      final mxc = entry.mxcUrl ??
          (await widget.room.client.uploadContent(
            bytes,
            filename: name,
            contentType: mime,
          )).toString();
      await widget.room.sendEvent(
        <String, dynamic>{
          'body': entry.body ?? name,
          'url': mxc,
          'info': <String, dynamic>{
            'mimetype': mime,
            'size': bytes.length,
            // ...? 分量為 null-aware spread（use_null_aware_elements 清理；Dart 支援此語法）。
            ...?dims,
          },
        },
        type: EventTypes.Sticker,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('貼圖傳送失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 批次 III-b：以官方 image 套件（flutter 內建圖解碼器）讀取貼圖寬高。
  Future<Map<String, int>?> _imageDimensions(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      return {'w': descriptor.width, 'h': descriptor.height};
    } catch (_) {
      return null;
    }
  }

  /// 批次 III-c：開啟位置（官方 geo URI → url_launcher）。
  Future<void> _openLocation(ChatMessageView m) async {
    final event = m.event;
    final geo = (event?.content['geo_uri'] as String?) ??
        (event?.content['org.matrix.msc3488.location'] as Map<String, dynamic>?)
            ?['uri'] as String?;
    if (geo == null || geo.isEmpty) {
      return;
    }
    final url = Uri.tryParse(geo);
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法開啟地圖：$e')), // 文案草案
        );
      }
    }
  }

  /// 批次 III-c：位置分享（官方 `Room.sendLocation`）。
  /// 點位置 → 顯示 FlutterMap（OpenStreetMap tile）讓使用者選點（草案）→
  /// 送出 geo URI。無自製協定邏輯。 attribution：© OpenStreetMap contributors。
  Future<void> _sendLocation() async {
    if (!mounted) return;
    final picked = await showDialog<(double, double)?>(
      context: context,
      builder: (ctx) => _LocationPickerDialog(),
    );
    if (picked == null || !mounted) return;
    final (lat, lon) = picked;
    try {
      await widget.room.sendLocation(
        '位置 ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}', // 文案草案
        'geo:$lat,$lon',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('位置分享失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 批次 III-a：此訊息為附件（官方 msgtype m.file／m.video／m.audio）。
  /// 第二十四批：純文字訊息列（已編輯記號與「編輯」動作的適用範圍）。
  /// 附件／圖片／貼圖／投票／位置／通話事件不套用文字編輯記號。
  bool _isPlainTextRow(ChatMessageView m) =>
      !m.isImage &&
      !m.isSticker &&
      !m.isLocation &&
      !m.isPoll &&
      !m.isCallInvite &&
      !_isAttachment(m);

  bool _isAttachment(ChatMessageView m) {    final t = m.event?.messageType;
    return t == 'm.file' || t == 'm.video' || t == 'm.audio';
  }

  /// 批次 III-a：貼圖使用**原始尺寸**（非縮圖）。
  final Map<String, Future<MatrixFile?>> _fullImageLoaders = {};

  Future<MatrixFile?> _loadFullImage(ChatMessageView m) {
    final event = m.event;
    final id = m.eventId ?? 'self_${m.sentAt?.toIso8601String()}';
    if (event == null) {
      _fullImageLoaders[id] ??= Future<MatrixFile?>.value(null);
      return _fullImageLoaders[id]!;
    }
    return _fullImageLoaders[id] ??= () async {
      try {
        return await event.downloadAndDecryptAttachment();
      } catch (_) {
        return null;
      }
    }();
  }

  // 批次 III-a：已下載待分享檔案（eventId → 臨時檔路徑），避免重複下載。
  final Map<String, String> _openedFiles = {};

  /// 第 3 點（人類回報「只有部份檔案能找到相關支援格式的 Apps」）根因：
  /// 附件以 `file.name` 存檔；**上傳者沒有副檔名**（或 server filename
  /// 無副檔名）時，Android 無法由副檔名判斷 mimetype → 找不到能開的 App
  /// （odp／docx／mp3 等皆同）。修正：官方 `content['info']['mimetype']`
  /// → 常見副檔名對照補齊；檔名有副檔名則照舊使用。
  String _attachmentFileName(Event event, MatrixFile file) {
    var name = file.name.isNotEmpty ? file.name : 'attachment';
    final mime = (event.content['info'] is Map<String, dynamic>
            ? (event.content['info'] as Map<String, dynamic>)['mimetype']
            : null) as String?;
    if (!name.contains('.') && mime != null) {
      const extMap = <String, String>{
        // 文件／ODF（人類回報的 odp 即此類）
        'application/pdf': 'pdf',
        'application/vnd.oasis.opendocument.presentation': 'odp',
        'application/vnd.oasis.opendocument.spreadsheet': 'ods',
        'application/vnd.oasis.opendocument.text': 'odt',
        'application/vnd.ms-powerpoint': 'ppt',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
        'application/msword': 'doc',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
        'application/vnd.ms-excel': 'xls',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
        'application/zip': 'zip',
        // 圖片
        'image/png': 'png',
        'image/jpeg': 'jpg',
        'image/gif': 'gif',
        'image/webp': 'webp',
        // 音訊／影片
        'audio/mpeg': 'mp3',
        'audio/ogg': 'ogg',
        'audio/wav': 'wav',
        'video/mp4': 'mp4',
        'video/webm': 'webm',
        'video/x-matroska': 'mkv',
      };
      final ext = extMap[mime] ?? mime.split('/').last;
      if (ext.isNotEmpty) {
        name = '$name.$ext';
      }
    }
    return name;
  }

  /// 批次 III-a（人類回報「檔案只會以檔案名稱顯示，無法點選」）：
  /// 官方 `Event.downloadAndDecryptAttachment` 下載（加密由 SDK 官方處理）→
  /// 寫入系統臨時目錄 → **開啟**（使用 `open_file` 呼叫系統，讓使用者
  /// 選擇開啟支援該格式的軟體；不再走系統分享 sheet）。
  Future<void> _openAttachment(ChatMessageView m) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    final eventId = m.eventId ?? '';
    final cached = _openedFiles[eventId];
    if (cached != null && File(cached).existsSync()) {
      unawaited(_openFile(cached));
      return;
    }
    // 批次十二④（human 參考 new_ref/chat 162223 對話框）：下載不再靜默——
    // 「下載中…／X / Y／進度列」＋取消。進度走官方
    // `Event.downloadAndDecryptAttachment(onDownloadProgress:)`
    // （SDK event.dart L821/L957，加密檔同樣發進度）；取消＝僅關閉 UI，
    // 背景下載照 SDK 續行完成（完成後寫暫存、下次開啟秒開；v0 行為披露）。
    final progress = ValueNotifier<int>(0);
    int? total;
    try {
      total = event.infoMap.tryGet<int>('size');
    } catch (_) {}
    int? dlTotal = total;
    var dialogClosed = false;
    final dlFuture = event.downloadAndDecryptAttachment(
      onDownloadProgress: (b) {
        progress.value = b;
        final t = dlTotal;
        if (t == null || t < b) {
          // 無 size 欄位時以最後讀到的進度當分母（骨架；size 正式值仍優先）。
          dlTotal = b;
        }
      },
    );
    if (mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dctx) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('下載中…'), // 文案草案
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: progress,
                  builder: (cctx, downloaded, _) {
                    final t = dlTotal ?? downloaded;
                    final denom = total ?? 0;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_formatBytes(downloaded)} / ${_formatBytes(t)}', // 文案草案
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: denom > 0 && downloaded <= denom
                              ? downloaded / denom
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  dialogClosed = true;
                  Navigator.of(dctx).pop();
                },
                child: const Text('取消'), // 文案草案
              ),
            ],
          ),
        ).whenComplete(() => dialogClosed = true),
      );
    }
    try {
      final file = await dlFuture;
      final dir = await Directory.systemTemp.createTemp('ring_open');
      final outFile = File('${dir.path}/${_attachmentFileName(event, file)}');
      await outFile.writeAsBytes(file.bytes);
      if (eventId.isNotEmpty) {
        _openedFiles[eventId] = outFile.path;
      }
      if (!dialogClosed && mounted) {
        dialogClosed = true;
        Navigator.of(context).pop(); // 關掉進度對話框（download 完成自動收起）
      }
      if (!mounted) {
        return;
      }
      await _openFile(outFile.path);
    } catch (e) {
      if (!dialogClosed && mounted) {
        dialogClosed = true;
        Navigator.of(context).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法開啟檔案：$e')), // 文案草案
        );
      }
    }
  }

  /// 批次第 1 點：使用 `open_file` 開啟本地檔案（系統會彈出可開啟該格式
  /// 的 App 供使用者選擇），而非系統分享 sheet。
  Future<void> _openFile(String path) async {
    try {
      final result = await OpenFile.open(path);
      if (result.type == ResultType.done) {
        return;
      }
      // open_file 失敗 → 嘗試 share_plus 作為 fallback，
      // 讓使用者自行選擇安裝的 App 開啟該檔案（第 3 點）。
      if (!mounted) return;
      final name = path.split('/').last;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path, name: name)]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('開啟失敗：$e')), // 文案草案
        );
      }
    }
  }

  /// 「已讀」顯示：官方 receipts 中是否有**他人**已讀本則事件
  /// （SDK `Event.receipts`；App 端不自行實作 receipt 協定）。
  /// 已讀判定③（人類實測 APK 2015「完全無顯示」，2026-11-07）：官方
  /// `event.receipts`（event.dart L315+）＝**他人 receipt 的 eventId 與本
  /// 訊息 eventId 完全相等**才命中；但對端 markAsRead 的 target＝其房間
  /// `lastEvent`（本檔 L715-740 同款官方判準），夾帶任何後到事件（對端自己
  /// 的回覆／reaction 等）就永不相等 → 真實流程幾乎永不顯示。修＝兩段
  /// （資料皆官方 SDK：receiptState＝sync ephemeral m.receipt 自動彙整，
  /// client.dart L2859-2883；零新依賴、不碰加密）：
  ///   1) 快路：eventId 完全相等（官方 getter）；
  ///   2) 兜底：`Room.receiptState.global.otherUsers` 任一他人 receipt 的
  ///      **ts ≥ 本訊息 originServerTs**（兩者皆 server 時鐘；receipt 時點
  ///      晚於本訊息送出 ⟺ 對端讀取時已在看本訊息或更後 → 已讀涵蓋）。
  bool _isReadByOthers(ChatMessageView m) {
    final event = m.event;
    if (event == null) {
      return false;
    }
    try {
      final me = widget.room.client.userID;
      if (event.receipts.any((r) => r.user.id != me)) {
        return true;
      }
      final sentMs = event.originServerTs.millisecondsSinceEpoch;
      final global = widget.room.receiptState.global.otherUsers;
      for (final e in global.entries) {
        if (e.key == me) {
          continue; // 保險（otherUsers 本應不含自己）。
        }
        if (e.value.ts >= sentMs) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 「沒有權限發送訊息的 rooms 不應該出現傳送訊息功能」：
  /// SDK 官方 `Room.canSendDefaultMessages`（room.dart L2402 ＝
  /// membership／加密／m.room.power_levels 官方判斷）。UI 不讀自製判斷。
  bool get _canSend {
    try {
      return widget.room.canSendDefaultMessages;
    } catch (_) {
      // 判斷不到（如測試環境缺 state）→ 維持舊行為（顯示輸入列）。
      return true;
    }
  }

  Widget _buildInputRow() {
    if (!_canSend) {
      // 草案文案：只讀列——無發送權限時**不渲染**傳送功能。
      return const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('此聊天室僅供讀取（沒有發送權限）')), // 文案待定稿
            ],
          ),
        ),
      );
    }
    final hasText = _inputController.text.trim().isNotEmpty;
    // 批次 III-c：面板展開時，「＋」位置改顯示「×」＋相機＋相簿
    // （依人類注記參考圖）；面板收起時維持單一「＋」。
    final leading = _attachOpen
        ? <Widget>[
            IconButton(
              tooltip: '關閉附件面板', // 文案草案
              onPressed: () => _setAttachOpen(false),
              icon: const Icon(Icons.close),
            ),
            IconButton(
              tooltip: '相機', // 文案草案
              onPressed: _uploading ? null : () => unawaited(_onCamera()),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
            IconButton(
              tooltip: '相簿', // 文案草案
              onPressed: _uploading ? null : () => unawaited(_startAttach(FileType.media)),
              icon: const Icon(Icons.image_outlined),
            ),
            // 第三十五批 #13：Markdown 送出開關（預設關；kv 持久化）。
            IconButton(
              tooltip: _markdownOn ? 'Markdown：開' : 'Markdown：關', // 文案草案
              onPressed: () => unawaited(_toggleMarkdown()),
              icon: const Icon(Icons.code),
              color: _markdownOn ? Theme.of(context).colorScheme.primary : null,
            ),
            // 第三十五批 #5：無聲傳送（本則送出後自動復位）。
            IconButton(
              tooltip: _silentSend ? '無聲傳送：開（本則不通知）' : '無聲傳送：關', // 文案草案
              onPressed: () => setState(() => _silentSend = !_silentSend),
              icon: const Icon(Icons.notifications_off),
              color: _silentSend ? Theme.of(context).colorScheme.primary : null,
            ),
          ]
        : <Widget>[
            IconButton(
              tooltip: '新增附件', // 文案草案
              onPressed: _uploading ? null : () => _setAttachOpen(true),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 貼圖關鍵字聯想（backlog #8）：輸入列**上方**的水平建議列
          // （參考 LINE：輸入文字時於輸入框上方出現建議貼圖；樣式草案待人類定稿）。
          if (_stickerSuggestions.isNotEmpty)
            _StickerSuggestionStrip(
              suggestions: _stickerSuggestions,
              onSelected: (entry) => unawaited(_sendSticker(entry)),
            ),
          Row(
            children: [
              ...leading,

              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_sending,
                  onChanged: (_) {
                    setState(() {});
                    // 第二十四批：輸入中 → 官方 setTyping(true)（節流 7s）；
                    // 清空 → setTyping(false)。告知性資訊，失敗靜默。
                    unawaited(_maybeSendTyping());
                    // 貼圖關鍵字聯想（backlog #8）：依目前輸入建議貼圖。
                    unawaited(_updateStickerSuggestions());
                  },
                  onSubmitted: (_) => unawaited(_onSend()),
                  decoration: InputDecoration(
                    hintText: '輸入訊息…', // 文案待定稿
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _emojiOpen ? '收起表情面板' : '表情',
                      onPressed: _toggleEmojiPanel,
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        color: _emojiOpen
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              // 右下角：有文字 → 送出；無文字 → mic（disabled）。
              // 語音訊息功能不在藍圖（人類決定 disabled，僅佔位）。
              if (hasText)
                IconButton(
                  tooltip: '送出',
                  onPressed: _sending ? null : () => unawaited(_onSend()),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                )
              else
                IconButton(
                  tooltip: '語音訊息（尚未提供）',
                  onPressed: null,
                  icon: const Icon(Icons.mic_none),
                ),
            ],
          ),
          // 批次 III-c：面板展開 → 下方補 Files／聯絡資訊／位置 一排（草案）。
          if (_attachOpen) _buildAttachOptions(),
        ],
      ),
    );
  }
}

/// 訊息頭像圓（草案）。
/// 批次 E：訊息發送者頭像（官方 avatar mxc → `Uri.getDownloadUri` →
/// NetworkImage；與 rooms_screen `_RoomAvatar` 同模式）。無頭像或
/// 注入測試（event 為 null → avatarUri 為 null）→ 首字圓圈 fallback，
/// 與原本 `_InitialAvatar` 顯示一致。草案 UI（頭像尺寸／樣式待人類定稿）。
/// 第四十五批：回覆引言方塊（LINE 版位 `mx-reply`）。
///
/// 版位慣例（可觀察的排版事實，非品牌識別）：引言在**同一個泡泡內**的上緣，
/// 左側有一條直立色條，右側是「寄送者名稱（彩色）＋被回覆內容（截斷）」。
/// 內容皆為**純文字**，不使用任何品牌字型／圖示。
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({this.sender, this.body});

  final String? sender;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: scheme.primary, width: 3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sender != null && sender!.isNotEmpty)
            Text(
              sender!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
            ),
          if (body != null && body!.isNotEmpty)
            Text(
              body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.label, required this.client, this.avatarUri});

  final String label;
  final Client client;

  /// 已由呼叫端 try/catch 提取的頭像 Uri（可能為 null）。
  final Uri? avatarUri;

  @override
  Widget build(BuildContext context) {
    final text = label.runes.isEmpty
        ? '?'
        : String.fromCharCode(label.runes.first);
    if (avatarUri == null) {
      return CircleAvatar(child: Text(text));
    }
    return FutureBuilder<(Uri, bool)>(
      future: () async {
        final uri = await avatarUri!.getThumbnailUri(client, width: 64, height: 64);
        final auth = await client.authenticatedMediaSupported();
        return (uri, auth);
      }(),
      builder: (context, snap) {
        if (snap.hasData) {
          final (uri, auth) = snap.data!;
          return CircleAvatar(
            backgroundImage: NetworkImage(
              uri.toString(),
              headers: auth
                  ? <String, String>{'authorization': 'Bearer ${client.accessToken}'}
                  : null,
            ),
          );
        }
        return CircleAvatar(child: Text(text));
      },
    );
  }
}

/// 圖片訊息磚（骨架，無樣式／不寫死寬度，版面待人類設計定稿）。
/// 批次 D：投票卡片（草案；待人類設計定稿）。
/// 採 SDK 官方 msc_3381_polls extension：`parsedPollEventContent`（問題/選項）、
/// `getPollResponses(timeline)`（票數）、`answerPoll`（投票）、`endPoll`（結束）。
/// 零加密邏輯（事件由房間加密機制處理）。
class _ChatPollTile extends StatefulWidget {
  const _ChatPollTile({required this.message, required this.timeline});

  final ChatMessageView message;
  final Timeline? timeline; // 注入 loader 的測試環境為 null（僅顯示內容）

  @override
  State<_ChatPollTile> createState() => _ChatPollTileState();
}

class _ChatPollTileState extends State<_ChatPollTile> {
  bool _voting = false;
  Map<String, Set<String>> _responses = {};
  bool _ended = false;

  /// 「投票要重新進聊天室才看得到（別人投票）」根因修復（2026-11-06）：
  /// 票數過去只在 initState 算一次；外層 _load 的變更判定（列表長度／
  /// 最末事件 id）抓不到被過濾掉的 poll.response──卡面永不重畫。
  /// 修法：訂閱 SDK 官方 `client.onTimelineEvent`（已驗證 E2EE 房先解密
  /// 再 emit，事件型別即 `org.matrix.msc3381.poll.response`／`m.poll.response`
  /// 等），只挑「回應或結束**本投票**」的事件重算票數。本檔零加密邏輯
  /// （後期解密 queued 的暫態由 SDK 官方 decryptedTimelineQueue 盡量覆蓋）。
  StreamSubscription<Event>? _timelineEventSub;

  Event? get _event => widget.message.event;
  bool get _interactive => _event != null && widget.timeline != null;

  @override
  void initState() {
    super.initState();
    _refreshResponses();
    _subscribeTimelineEvents();
  }

  @override
  void didUpdateWidget(covariant _ChatPollTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.eventId != widget.message.eventId ||
        oldWidget.message.event != widget.message.event) {
      _refreshResponses();
      _subscribeTimelineEvents();
    }
  }

  void _subscribeTimelineEvents() {
    _timelineEventSub?.cancel();
    _timelineEventSub = null;
    final event = _event;
    if (event == null) {
      return; // 注入測試（event null）不訂閱。
    }
    _timelineEventSub = event.room.client.onTimelineEvent.stream
        .where(
          (ev) =>
              ev.room.id == event.room.id &&
              (kPollResponseTypes.contains(ev.type) ||
                  kPollEndTypes.contains(ev.type)),
        )
        .listen((_) {
      if (mounted) {
        setState(_refreshResponses);
      }
    });
  }

  @override
  void dispose() {
    _timelineEventSub?.cancel();
    super.dispose();
  }

  void _refreshResponses() {
    final event = _event;
    final timeline = widget.timeline;
    if (event == null || timeline == null) {
      return;
    }
    try {
      // 批次 E：dual 前綴相容（unstable SDK 官方＋stable；接收端也認
      // Element 系發出的穩定型別事件）。
      _responses = pollResponsesCompat(timeline, event.eventId);
      _ended = pollEndedCompat(timeline, event.eventId);
    } catch (_) {
      // timeline 尚未聚合（首次 sync）；保守顯示為未投。
    }
  }

  Future<void> _vote(String answerId) async {
    final event = _event;
    if (event == null || _voting || _ended) {
      return;
    }
    setState(() => _voting = true);
    try {
      await event.answerPoll([answerId]);
      if (mounted) {
        setState(() {
          _voting = false;
          _refreshResponses();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _voting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法投票：$e')), // 文案草案
        );
      }
    }
  }

  Future<void> _endPoll() async {
    final event = _event;
    if (event == null) {
      return;
    }
    try {
      // 批次 E：結束事件補 org.matrix.msc1767.text fallback 文字
      //（人類批准方向；Element X 端顯示「已結束」待實機複測 ⚠️待查證）。
      await endPollWithFallback(event.room, event);
      if (mounted) {
        setState(() {
          _refreshResponses();
          _ended = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法結束投票：$e')), // 文案草案
        );
      }
    }
  }

  /// 我票（開放投票的 responses 含我；匿名投票一律不顯示——草案）。
  bool _iVoted(String? userID) {
    return userID != null && _responses.containsKey(userID);
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    if (event == null) {
      return Text(widget.message.body); // 注入測試無 event：退回文字
    }
    // 批次 E：dual 前綴解析（SDK `parsedPollEventContent` 只認 unstable 鍵，
    // 且回側強制要求 msc1767 fallback 欄位；穩定型別事件會直接 throw）。
    final poll = pollStartContentCompat(event);
    if (poll == null) {
      return Text(widget.message.body);
    }
    final myId = event.room.client.userID;
    final question = poll.question.mText;
    final options = poll.answers;
    final isOwn = event.senderId == myId;
    final voted = _iVoted(myId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '投票 ${_ended ? '（已結束）' : ''}', // 文案草案
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Text(question, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        // Issues「投票功能自己也要能按」（參考 Element X）：建立者**也可以投**
        //（官方 msc3381 建立者取樣自己的 response 沒有任何限制）。
        if (!_ended && _interactive && !voted)
          for (final option in options)
            TextButton(
              onPressed: _voting ? null : () => _vote(option.id),
              child: Text(option.mText),
            )
        else
          // 已投／已結束／非互動：顯示選項＋票數（若可聚合）。
          // 人類回饋批次九「恢復原先設計位置，但改成「：(num) 票」」：撤回
          // 批次八的滿寬列（SizedBox(width: double.infinity)＋Spacer 貼右
          // 緣），恢復緊湊排版——票數跟在選項文字後，格式統一「：N 票」。
          for (final option in options)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  voted && _isMyChoice(myId, option.id) ? '☑ ' : '☐ ',
                ),
                const SizedBox(width: 2),
                Flexible(child: Text(option.mText)),
                if (_responses.isNotEmpty)
                  Text(
                    '：${_countVotes(option.id)} 票', // 文案草案
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
        if (isOwn && !_ended && _interactive)
          TextButton(
            onPressed: _endPoll,
            child: const Text('結束投票'), // 文案草案
          ),
        // 範圍限制（草案）：SDK 走 unstable `org.matrix.msc3381.*`，
        // Element 可能僅顯示 fallback 文字、看不到本投票卡片。
      ],
    );
  }

  bool _isMyChoice(String? userID, String answerId) {
    return userID != null && _responses[userID]?.contains(answerId) == true;
  }

  int _countVotes(String answerId) {
    var n = 0;
    _responses.forEach((_, votes) {
      if (votes.contains(answerId)) {
        n++;
      }
    });
    return n;
  }
}

/// 批次 III-a：檔案附件 tile（官方 msgtype m.file／m.video／m.audio）。
/// 圖示依型別；點擊 → onOpen（下載＋系統分享開啟）。DOM 無樣式骨架，待人類定稿。
/// 批次十二④：位元組人類可讀（檔案 tile 與下載進度共用；草案文案）。
String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} kB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _ChatFileTile extends StatelessWidget {
  const _ChatFileTile({required this.message, required this.onOpen});

  final ChatMessageView message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final type = message.event?.messageType;
    final icon = type == 'm.video'
        ? Icons.movie_outlined
        : type == 'm.audio'
            ? Icons.graphic_eq
            : Icons.insert_drive_file_outlined;
    // 批次十二④（human 參考 new_ref/chat 162223）：檔案列加 Size 行
    // （官方 event.infoMap['size']； rooms_screen 同一 infoMap 用法）。
    int? size;
    try {
      size = message.event?.infoMap.tryGet<int>('size');
    } catch (_) {}
    final subtitle = size != null ? 'Size: ${_formatBytes(size)} · 點擊開啟' : '點擊開啟'; // 文案草案
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.body.isNotEmpty ? message.body : '檔案', // 文案草案
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }
}

/// 圖片位元組皆來自 SDK 官方 `downloadAndDecryptAttachment`（加密由 SDK 處理）；
/// 失敗時顯示文字占位，不出現自製解密／下載邏輯。
/// 批次 D：點擊進全屏預覽（ImagePreviewScreen，草案）。
class _ChatImageTile extends StatelessWidget {
  const _ChatImageTile({
    required this.message,
    required this.loadImage,
    required this.onOpenImage,
    this.semanticLabel,
  });

  final ChatMessageView message;
  final Future<MatrixFile?> Function(ChatMessageView) loadImage;
  final void Function(ChatMessageView, Uint8List? bytes) onOpenImage;

  /// 無障礙標籤（螢幕閱讀器朗讀用；空白＝沿用內容推導）。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MatrixFile?>(
      future: loadImage(message),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Text('[圖片：載入中…]');
        }
        final file = snapshot.data;
        if (file == null) {
          return Text(
            message.body.isNotEmpty ? message.body : '[圖片：無法載入]',
          );
        }
        // 無固定寬高：由父層條件約束（螢幕寬）自然限制，
        // 超寬圖依 BoxFit.contain 縮放。
        return Semantics(
          button: true,
          label: semanticLabel ??
              (message.body.isNotEmpty
                  ? message.body
                  : (message.isSticker ? '貼圖' : '圖片')),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenImage(message, file.bytes),
            child: Image.memory(
              file.bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
            ),
          ),
        );
      },
    );
  }
}

/// 批次 III-c：位置分享 tile（草案）。
class _ChatLocationTile extends StatelessWidget {
  const _ChatLocationTile({required this.message, required this.onOpen});

  final ChatMessageView message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on_outlined),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.body.isNotEmpty ? message.body : '位置'), // 文案草案
                Text(
                  '點擊開啟地圖', // 文案草案
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 批次 III-c：傳送位置前的選點 picker (OpenStreetMap tile via flutter_map)。
/// 草案 UI； attorney credit © OpenStreetMap contributors。
class _LocationPickerDialog extends StatefulWidget {
  const _LocationPickerDialog();

  @override
  State<_LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<_LocationPickerDialog> {
  LatLng _point = const LatLng(23.9739, 120.9820);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('選擇位置'), // 文案草案
      content: SizedBox(
        width: 320,
        height: 320,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: _point,
            initialZoom: 9,
            onTap: (tapPosition, latLng) => setState(() => _point = latLng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ring',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _point,
                  child: const Icon(
                    Icons.location_pin,
                    size: 36,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'), // 文案草案
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_point.latitude, _point.longitude)),
          child: const Text('送出'), // 文案草案
        ),
      ],
    );
  }
}

/// 貼圖關鍵字聯想條（backlog #8；人類 2026-11-03 目標 #8）。
///
/// 版位參考 LINE：輸入文字時，建議貼圖以**水平列**出現在輸入框**上方**；
/// 點擊縮圖即送出該貼圖（沿用既有 `_sendSticker` 官方上傳路徑）。
/// 樣式為草案，待人類設計定稿；元件不寫死寬度（縮圖尺寸固定、列可橫向捲動）。
class _StickerSuggestionStrip extends StatelessWidget {
  const _StickerSuggestionStrip({required this.suggestions, required this.onSelected});

  final List<StickerSuggestion> suggestions;

  /// 點選建議（傳入該貼圖；由呼叫端送出）。
  final ValueChanged<StickerLibraryEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = suggestions[index].entry;
          final label = stickerStem(entry.name).isEmpty
              ? '貼圖'
              : stickerStem(entry.name); // alt text（無障礙標籤）
          return Semantics(
            button: true,
            label: '建議貼圖：$label',
            child: Tooltip(
              message: label,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(entry),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  padding: const EdgeInsets.all(4),
                  child: Image.file(
                    File(entry.path),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.image_not_supported_outlined,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
