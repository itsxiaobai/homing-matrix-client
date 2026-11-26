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
import 'dart:convert' show JsonEncoder, jsonDecode, jsonEncode;
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
import 'package:path_provider/path_provider.dart'; // 語音暫存檔路徑

import '../app_settings.dart';
import '../ui/stt_model_prefs.dart'; // 第九十二批：語音訊息轉文字偏好
import '../chat_layout.dart';
import '../media_upload.dart';
import '../media_cache.dart'; // 第五十七批：本機媒體快取（離線可讀・方案 A）
import 'a11y.dart'; // 第五十七批：無障礙（按鈕功能說明）
import '../message_content.dart'; // 第三十五批 #5：無聲傳送旗標＋content 組裝
import '../album_card.dart'; // 第一百零二批：相簿卡片（m.notice + 自訂欄位）
import '../album_store.dart'; // 第一百零二批：本機相簿分組
import 'album_screen.dart'; // 第一百零二批：點卡片開相簿
import '../missing_key_repair.dart'; // 解密案修法 #2（人類批准 2026-11-13）
import '../markdown_message.dart'; // 第三十五批 #13：Markdown 送出／#14 收訊渲染
import '../message_edits.dart'; // 第四十二批：編輯解析（E2EE 房間亦適用）
import '../offline_queue.dart';
import '../poll_compat.dart';
import '../sticker_suggestions.dart'; // 貼圖關鍵字聯想（backlog #8；純邏輯）
import '../voip/call_manager.dart';
import 'block_user_screen.dart';
import 'emoji_panel.dart';
import 'image_preview_screen.dart';
import 'livekit_call_screen.dart';
import 'poll_create_screen.dart';
import 'group_chat_manage_screen.dart';
import 'message_search_screen.dart';
import 'report_user_screen.dart';
import 'room_info_screen.dart'; // 批次十二③
import 'announcement_banner.dart'; // 第四十六批：一般公告橫幅（中性色）
import 'time_format.dart';
import 'chat_row_plan.dart'; // 第五十七批：訊息列計畫（效能；列表視覺化）
import '../perf_metrics.dart'; // 第五十七批：效能量測記錄（診斷資訊）
import '../read_receipt_prefs.dart'; // 第六十九批：無痕預覽／稍後已讀
import '../scheduled_messages.dart'; // 第六十九批：預約訊息（純 client 側）
import '../silent_redaction.dart'; // 第七十批：無痕收回（content 旗標）
import '../sticker_motion_prefs.dart'; // 第七十三批：GIF 靜態首幀開關
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import '../background_readiness.dart'; // 第八十二批：電源／網路準備度
import '../local_nicknames.dart'; // 第七十九批：本機暱稱
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import 'design_tokens.dart'; // 第六十一批：LINE 近似深色調色（草案）
import '../engine_init.dart' show initRustEngineInIsolate; // 第七十批 a：首入解密引擎就緒
import 'compound_icon.dart'; // 第七十批 c：Compound 圖示
import 'line_style.dart'; // 合併後 Compound 相容層
import 'static_image.dart'; // 第七十三批：GIF 開關（靜態首幀）
import 'voice_message.dart'; // 第七十批 d：語音訊息播放
import 'voice_recorder_sheet.dart'; // 第七十批 e：LINE 式錄音面板

/// 第六十七批（人類指示 2026-11-17「已經載入的所有資料存入 cache，
/// 並嚴禁像 LINE 限時存取」）：**已載入訊息的 session 記憶體快取**
/// （房間 id → 最後一次成功載入的訊息列表）。
/// * **無任何 TTL／到期／限時存取機制**——一經載入，App session 內持續
///   可用，不因時間清理（LINE 式限時存取明令禁止）；只在**登出**時清除。
/// * 用途：重進聊天室立即顯示（不用等整窗重解密＋重掃），過去訊息不再
///   因重複處理而卡頓；背景仍照常 `_load()` 刷新。
final Map<String, List<ChatMessageView>> _loadedMessagesCache = {};

/// 第六十九批：單則訊息解析快取（eventId → 簽章＋view）。
/// 簽章含 body／redacted／edited／回覆／格式，內容一變即重建；無 TTL。
final Map<String, ({int sig, ChatMessageView view})> _messageViewCache = {};

/// 第六十九批：整窗指紋（房間 → timeline 指紋）；未變時整份 cache 直接回傳。
final Map<String, int> _windowFingerprint = {};

/// 第七十批 a：首入解密重試節流——每個房間 session 內只自動重解密一次，
/// 避免「解密失敗→清 cache→每次 sync 又重解密」的無限迴圈。真正拿到新
/// 金鑰的事件會由 SDK onTimelineEvent／sync 觸發的 `_load()` 正常重解。
final Set<String> _firstDecryptRetryDone = {};

/// 第六十九批：本機編輯版本——任何本機編輯／收回後遞增，使整窗 cache 失效
/// （這些變更不改變 timeline.last.body，光靠 eventId/body 指紋偵測不到）。
int _localEditsVersion = 0;

/// 登出時清除已載入訊息快取（無 TTL；僅記憶體）。
void clearLoadedMessagesCache() {
  _loadedMessagesCache.clear();
  _messageViewCache.clear();
  _windowFingerprint.clear();
}

/// 第七十批 f：無痕收回 metadata key（官方 redactEventWithMetadata 的 content）。
/// 另一端 `event.redactedBecause?.content[kHomingStealthKey] == true` 時
/// 自動把該則從列表移除（不顯示 [已收回]）。
const String kHomingStealthKey = 'io.github.itsxiaobai.homing.stealth_redact';

/// 第五十七批：跳轉到「尚未建構」的訊息時，用來粗估 offset 的**平均列高**
/// （邏輯像素；僅為估算，實際定位交給官方 `Scrollable.ensureVisible`）。
const double kEstimatedChatRowHeight = 72;

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
    this.replyToEventId,
    this.hideReplyQuote = false,
    this.event,
    // 第五十五批（2026-11-16）：本機**樂觀**顯示、尚在背景送出的訊息
    // （人類：「傳送訊息是不是應該先顯示在上面，背景繼續傳送？不然使用者
    // 會覺得當機了」）。送出成功後由 `_load()` 以伺服器事件取代；失敗則
    // 移除並把文字還回輸入框。
    this.pending = false,
    // 第七十五批（B8）：Membership 系統事件（Element X 式置中細列）。
    this.isSystemEvent = false,
    // 2026-11-20：被收回的訊息 → 灰框「已收回訊息」（不顯示 SDK 的 unsent 文案）。
    this.isRedacted = false,
    // 第一百零二批：相簿卡片（m.notice + dev.homing.album 自訂欄位）。
    this.isAlbumCard = false,
    this.albumGroupId,
    this.albumName,
    this.albumPhotoIds = const <String>[],
  });

  final String sender;
  final String body;

  /// 第七十五批：membership 系統事件（不畫泡泡／頭像）。
  final bool isSystemEvent;

  /// 2026-11-20：被收回訊息（官方 `Event.redacted`）→ 灰框「已收回訊息」。
  final bool isRedacted;
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

  /// 2026-11-20：被回覆的 event id（點引言跳回原訊息用）。
  final String? replyToEventId;

  /// 2026-11-20：本機隱藏此則的回覆引言（長按選單切換）。
  final bool hideReplyQuote;

  /// 原始 SDK 事件（僅 SDK 來源訊息；測試注入可為 null）。
  /// 此欄位僅供**官方媒體 API**（`Event.downloadAndDecryptAttachment`）與
  /// **官方 receipts**（`Event.receipts`）使用；本檔不寫任何加密／解密邏輯，
  /// 附件解密由 SDK 官方路徑處理。
  final Event? event;

  /// 第五十五批（2026-11-16）：本機**樂觀**顯示（尚未送達伺服器）的訊息。
  /// 送出成功 → 由 `_load()` 以伺服器事件取代；失敗 → 移除並還回輸入框。
  final bool pending;

  /// 第一百零二批：此則是否為「相簿卡片」（點了可開啟本機相簿分組）。
  final bool isAlbumCard;
  final String? albumGroupId;
  final String? albumName;
  final List<String> albumPhotoIds;
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

/// 第一百零二批：相簿卡片送出抽象（供測試注入；預設走 SDK `Room.sendEvent`
/// 的 m.notice + 自訂欄位）。回傳 event id。
typedef ChatAlbumCardSender = Future<String?> Function(
  Room room,
  String body,
  String groupId,
  String name,
  List<String> photoIds,
);

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
    this.sendAlbumCard,
    this.onOpenAlbum,
    // 第六十四批①：首頁公告橫幅點擊帶入的釘選訊息 id——進房後**自動**
    // 跳到該訊息（人類：「公告自動找過去訊息，不要讓使用者自己找」）。
    // 不在已載入窗口時以有界 `requestHistory` 補抓（見 `_performAutoJump`）。
    this.jumpToEventId,
  });

  final Room room;

  /// 第六十四批①：進房自動定位的訊息 id（公告釘選）；null＝不自動跳。
  final String? jumpToEventId;
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

  /// 第一百零二批：送出相簿卡片訊息（預設＝官方 Room.sendEvent）。
  final ChatAlbumCardSender? sendAlbumCard;

  /// 第一百零二批：點卡片開啟本機相簿分組（預設 Navigator.push AlbumScreen）。
  final void Function(String groupId, String name)? onOpenAlbum;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  /// 2026-11-20：本機隱藏回覆引言的 event id（長按選單切換，不寫 kv）。
  final Set<String> _hiddenReplyIds = {};

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

  /// 第六十四批①：`jumpToEventId` 自動跳轉是否已處理（一次；避免每次
  /// sync 重載後重複跳走，把使用者拉離目前位置）。
  bool _autoJumpDone = false;

  /// 第五十七批：最近一次 build 算出的**列計畫**（供跳轉時粗估 offset 用）。
  List<ChatRowPlan> _rowPlan = const [];

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
  /// 第六十七批：佇列中可繼續送出（多則並行排隊）→ `_sending` 語意改為
  /// 「有任一送出仍在進行」＝進行中計數器（歸零＝false）。spinner／指示用途
  /// 不變；**不再禁用輸入與送出**（見 _onSend／輸入框註解）。
  int _activeSends = 0;
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

  /// 第五十五批：仍在背景送出的 pending 訊息（`_load()` 重載時要保留）。
  final List<ChatMessageView> _pendingSends = [];

  // ── 第七十批 e：語音訊息播放 cache（錄音狀態在 voice_recorder_sheet.dart）──

  /// 第五十六批：本機**自己送出且成功**的編輯（target eventId → 新 body）。
  ///
  /// 為何需要這張表：編輯（`m.replace`）的取得在 SDK 與本專案各有一層
  /// 「只查一次」的快取——SDK `Timeline._relationRequests`（成功後永久保留）
  /// 與本專案 `_editRelationsChecked`（每個 eventId 只查一次）→ **對同一則
  /// 訊息的「後續編輯」永遠抓不到** → 編輯完畫面不動，要等下一則其他事件
  /// 帶來重載才會變（人類回報 2026-11-16：「靠編輯完要其他地方有更新的
  /// 時候才會變」）。
  ///
  /// → 本機自己送出的編輯直接記入本表（並持久化到 kv），渲染時由公開純函式
  /// `resolveWithLocalEdits()` 併入解析（**官方真的換了內容才採用官方**；
  /// 官方只標「已編輯」但內容沒變 → 以本機對照為準）。
  final Map<String, String> _localEdits = {};

  /// 第五十六批：本機編輯對照的持久化 key（`app_settings.db` kv；JSON map）。
  static const String kLocalEditsKey = 'local_edits';

  /// 第五十六批：還原持久化的本機編輯對照（重啟後仍顯示已編輯的內容）。
  Future<void> _restoreLocalEdits() async {
    try {
      final raw = await AppSettings.get(kLocalEditsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, String>{};
      decoded.forEach((k, v) {
        if (k is String && v is String) map[k] = v;
      });
      if (map.isEmpty) return;
      _localEdits.addAll(map);
      if (mounted) unawaited(_load());
    } catch (_) {
      // 讀取失敗（資料損毀等）→ 忽略（本機對照只是加速／兜底）。
    }
  }

  /// 第五十六批：持久化本機編輯對照。
  Future<void> _persistLocalEdits() async {
    try {
      await AppSettings.set(kLocalEditsKey, jsonEncode(_localEdits));
    } catch (_) {
      // 寫入失敗不阻擋（顯示仍可用記憶體中的值）。
    }
  }

  /// 第五十六批：以**官方 /relations 原始 API**確認伺服器端的編輯內容。
  ///
  /// 官方 API（`getRelatingEventsWithRelType`）**不受** SDK
  /// `Timeline._relationRequests` 的「只查一次」快取限制 → 能拿到事後的編輯。
  Future<void> _refreshLocalEditFromServer(Room room, String targetId) async {
    try {
      final resp = await room.client.getRelatingEventsWithRelType(
        room.id,
        targetId,
        RelationshipTypes.edit,
        limit: 20,
      );
      for (final e in resp.chunk) {
        final nc = e.content['m.new_content'];
        if (nc is Map && nc['body'] is String) {
          _localEdits[targetId] = nc['body'] as String;
        }
      }
      await _persistLocalEdits();
    } catch (_) {
      // 抓不到（離線等）→ 保留送出時寫入的本機值。
    }
  }

  /// 第五十六批：把本機編輯**注入 SDK 的聚合樹**（`timeline.aggregatedEvents`）。
  ///
  /// 為什麼要注入：官方 `Event.getDisplayEvent(timeline)` 是**所有**顯示路徑
  /// （聊天室泡泡、房間列表預覽）的共同來源；SDK 只把**它自己收到**的 m.replace
  /// 放進聚合樹，而本機自己送出的編輯在 SDK 兩層 relations 快取下抓不到
  /// → `getDisplayEvent` 套用不到 → 畫面與預覽都停在舊內容。
  /// → 直接把本機的編輯事件放進聚合樹 → 官方路徑自然套用（泡泡、預覽一致）。
  void _injectLocalEditIntoTimeline(String targetId, String body) {
    final timeline = _timeline;
    if (timeline == null) return;
    try {
      Event? target;
      for (final e in timeline.events) {
        if (e.eventId == targetId) {
          target = e;
          break;
        }
      }
      if (target == null) return;
      final edit = Event(
        type: EventTypes.Message,
        content: {
          'msgtype': 'm.text',
          'body': '* $body',
          'm.new_content': {'msgtype': 'm.text', 'body': body},
          'm.relates_to': {
            'rel_type': RelationshipTypes.edit,
            'event_id': targetId,
          },
        },
        senderId: target.senderId,
        eventId: '~localedit-$targetId',
        originServerTs: DateTime.now(),
        room: timeline.room,
      );
      timeline.aggregatedEvents
          .putIfAbsent(targetId, () => <String, Set<Event>>{})[RelationshipTypes.edit] =
          {edit};
    } catch (_) {
      // 注入失敗不阻擋（仍可由 `_localEdits` 兜底顯示）。
    }
  }

  StreamSubscription<dynamic>? _syncSub;
  Timer? _reloadTimer;

  /// 第六十九批（F-2/P2 稍後標為已讀）：延遲送 receipt 的 Timer。
  Timer? _readDelayTimer;
  String? _lastReadEventId;

  /// 第七十批：無痕收回的 eventId（本機記憶＋紅action content 旗標雙軌）。
  final Set<String> _silentRedactionIds = <String>{};
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
  ///
  /// ⚠️ 第五十七批：**先查本機媒體快取**（離線可讀・方案 A）→ 未命中才下載，
  /// 下載後寫入快取（LRU＋容量上限見 `media_cache.dart`）。
  /// 第一百零九批：從本文解析 mxc:// URI（常见于別的 client 貼上來的媒體連結）。
  ({String server, String mediaId})? _mxcFromBody(String body) {
    final match = RegExp(r'^mxc://([^/\s]+)/(\S+)').firstMatch(body.trim());
    if (match == null) return null;
    return (server: match.group(1)!, mediaId: match.group(2)!);
  }

  /// 直接以官方 media endpoint 下載 mxc（不解密 E2EE 附件；此類 mxc 連結
  /// 本來就是明文媒體 URI）。失敗回 null，_ChatImageTile 會顯示本文。
  final Map<String, Future<MatrixFile?>> _mxcLoaders = {};

  Future<MatrixFile?> _loadMxcImage(ChatMessageView m) {
    final mxc = _mxcFromBody(m.body);
    final id = m.eventId ?? m.body;
    if (mxc == null) {
      return Future<MatrixFile?>.value(null);
    }
    return _mxcLoaders[id] ??= () async {
      try {
        // 第一百一十一批：Element X 用 authenticated media 端點（MSC3916），
        // 舊的免登入 /media/v3/download 對較新的媒體會回 404。
        final uri = _authenticatedMediaUri(mxc.server, mxc.mediaId);
        final response = await widget.room.client.httpClient.get(
          uri,
          headers: _mediaAuthHeaders(),
        );
        if (response.statusCode != 200) return null;
        return MatrixFile(
          bytes: response.bodyBytes,
          name: m.body,
        );
      } on Object {
        return null;
      }
    }();
  }

  /// 第一百一十一批：authenticated media URI（自家 homeserver 代理抓取）。
  Uri _authenticatedMediaUri(String server, String mediaId) {
    final hs = widget.room.client.homeserver ?? Uri.parse('https://matrix.org');
    return Uri.parse(
      '${hs.origin}/_matrix/client/v1/media/download/$server/$mediaId',
    );
  }

  /// access token 只放在 request header，不寫 log／不落地。
  Map<String, String> _mediaAuthHeaders() {
    final token = widget.room.client.accessToken;
    return token == null ? const {} : {'Authorization': 'Bearer $token'};
  }

  /// 第一百一十批：reaction key 為 mxc:// 時的下載（依 mxc 字串快取）。
  final Map<String, Future<MatrixFile?>> _reactionImageLoaders = {};

  Future<MatrixFile?> _loadReactionImage(String body) {
    final mxc = _mxcFromBody(body);
    if (mxc == null) return Future<MatrixFile?>.value(null);
    return _reactionImageLoaders[body] ??= () async {
      try {
        final uri = _authenticatedMediaUri(mxc.server, mxc.mediaId);
        final response = await widget.room.client.httpClient.get(
          uri,
          headers: _mediaAuthHeaders(),
        );
        if (response.statusCode != 200) return null;
        return MatrixFile(bytes: response.bodyBytes, name: body);
      } on Object {
        return null;
      }
    }();
  }

  Future<MatrixFile?> _loadImage(ChatMessageView m) {
    final event = m.event;
    final id = m.eventId ?? 'self_${m.sentAt?.toIso8601String()}';
    if (event == null) {
      _imageLoaders[id] ??= Future<MatrixFile?>.value(null);
      return _imageLoaders[id]!;
    }
    return _imageLoaders[id] ??= () async {
      try {
        return await loadMediaFileWithCache(event, thumbnail: true);
      } catch (_) {
        return null;
      }
    }();
  }

  @override
  void initState() {
    super.initState();
    // 第七十批：讀回本機「無痕收回」eventId 集合（跨重開仍不顯示）。
    unawaited(loadSilentRedactions().then((ids) {
      if (mounted && ids.isNotEmpty) {
        // 只有確實有無痕收回過的房間才補一次重載；一般使用者（空集合）
        // 不增加任何 load／markRead（避免影响既有測試與行為）。
        _silentRedactionIds.addAll(ids);
        unawaited(_load());
      }
    }).catchError((_) {}));
    // 第六十七批：進房**先用已載入快取**（無 TTL）立即顯示，背景照常
    // `_load()` 刷新（新訊息／pending 等仍會更新）。
    final cached = _loadedMessagesCache[widget.room.id];
    if (cached != null) {
      _messages = List<ChatMessageView>.of(cached);
    }
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
    // 2026-11-20：Markdown 改為「本則訊息開關」——不再從 kv 載入全域偏好，
    // 每則新訊息都從預設（關）開始，送出成功後自動復位。
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
    // 第五十四批（2026-11-16）：**收回（m.room.redaction）即時更新**。
    //
    // 根因（人類回報 2026-11-16：「對方收回訊息，本機要重開才會更新」）：
    // ① `_syncSub` 只在 `room.lastEvent` 改變時重載 → 收回**舊**訊息並不改變
    //    lastEvent → 根本不觸發重畫。
    // ② 即使重載也無效：`_defaultLoadMessages` **重用同一 Timeline 實例**（避免
    //    丟掉 requestHistory 抓到的歷史窗口），而記憶體中的事件物件不會被標記
    //    為已收回——官方 SDK 只對 `room.lastEvent` 做 `setRedactionEvent`
    //    （matrix client.dart L3188），其餘事件靠 DB 重建才會帶上收回狀態。
    //
    // 修法：訂閱官方 `onTimelineEvent`（收回事件走 timeline 通道），取 `redacts`
    // 指向的 eventId，**就地**對記憶體中的事件物件呼叫官方
    // `Event.setRedactionEvent`（與官方 SDK 對 lastEvent 的同一手法）→
    // 畫面即時顯示「[已收回]」，且**不重建 Timeline**（已抓的歷史窗口不丟）。
    // 已在當前 chunk 之外的更舊訊息：捲動重新載入時伺服器會回傳已收回版本。
    _relationEventSub = widget.room.client.onTimelineEvent.stream
        .where(
          (ev) =>
              ev.room.id == widget.room.id &&
              ev.type == EventTypes.Redaction,
        )
        .listen((ev) {
      // ① 收回（m.room.redaction）→ 就地標記記憶體中的事件 → 立即重載。
      // 第七十批：若帶無痕旗標 → 記憶目標 id，該列直接不渲染。
      if (isSilentRedactionContent(ev.content) && ev.redacts != null) {
        unawaited(addSilentRedactionId(_silentRedactionIds, ev.redacts!));
      }
      final events = _timeline?.events;
      if (events != null && applyRedactionToEvents(events, ev)) {
        // 第六十九批：收回是 in-place 標記（不改 last.body）→ 手動讓整窗
        // cache 失效，否則下一次 _load 會直接回傳舊內容（看不到收回）。
        _windowFingerprint.remove(widget.room.id);
        // 第五十六批：收回**立即**重載（不再走 `_scheduleReload()` 的 1000ms
        // 去抖）——人類回報「拖了好幾秒」，去抖是其中一段可省掉的延遲。
        unawaited(_load());
        return;
      }
      // ② 編輯（m.replace）→ 該事件**不改變 `room.lastEvent`** → `_syncSub`
      // 的重載條件永不觸發 → 畫面停在舊內容，直到「其他地方有更新」才會變
      // （人類回報 2026-11-16：「靠編輯完要其他地方有更新的時候才會變」）。
      // → 這裡補一次重載（與 `_sendEdit` 的強制同步雙保險）。
      if (ev.relationshipType == RelationshipTypes.edit) {
        // 2026-11-21（人類「不重開就不更新」根因）：_fetchEditRelations 對每個
        // eventId 只查一次（_editRelationsChecked）；若首次查詢時編輯尚未抵達，
        // 之後的 m.replace 永遠不會再抓 → 畫面卡在舊內容直到重開。
        // 編輯事件抵達時移除該 id 的「已查」標記，下一次 _load 才會重新抓。
        final target = ev.relationshipEventId;
        if (target != null) {
          _editRelationsChecked.remove(target);
        }
        // 第六十九批：編輯也改內容 → 讓整窗 cache 失效。
        _windowFingerprint.remove(widget.room.id);
        unawaited(_load());
      }
    });
    // 第 8 點：進入聊天室**立即**取一次未讀狀態（不等 _load 完成），
    // 有未讀 →「設為已讀」按鈕馬上出現（是 UI 資料流，官方 Room.isUnread）。
    _hasUnread = widget.room.isUnread;
    // 第五十六批：還原持久化的本機編輯對照（重啟後仍顯示已編輯的內容）。
    unawaited(_restoreLocalEdits());
    _load();
  }

  /// 第六十七批：失敗文字還原——佇列中可繼續打字後，輸入框可能已有新內容；
  /// 失敗還原**不覆蓋**：空＝直接還原；非空＝失敗內容**加在新內容之前**
  ///（失敗的較舊）＋ SnackBar 提示（資料一律不丟）。
  void _restoreFailedText(String text) {
    final existing = _inputController.text;
    _inputController.text = existing.isEmpty ? text : '$text\n$existing';
  }

  /// **收回（m.room.redaction）／編輯（m.replace）**即時更新訂閱
  /// （第五十四批收回、第五十六批編輯；dispose 同步釋放）。
  StreamSubscription<Event>? _relationEventSub;

  /// 媒體事件替換訂閱（2026-11-06 修復「重開才見圖」；dispose 同步釋放）。
  StreamSubscription<Event>? _mediaEventSub;

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _readDelayTimer?.cancel(); // 第六十九批：稍後已讀（離開即取消）
    _syncSub?.cancel();
    _mediaEventSub?.cancel();
    _relationEventSub?.cancel();
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
    // 第六十九批（人類 2026-11-19「讀取更新太慢」）：去抖 1000ms → 100ms。
    // 新訊息／已讀／member state／typing 更即時反映；收回／編輯早已走
    // 立即 `_load()`（第五十六批），不受此影響。overlay 不致一直轉——
    // `_load()` 僅在首次（無 cache）顯示 spinner，重載全程静默用 cache。
    _reloadTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) unawaited(_load());
    });
  }

  /// 第六十九批（F-2/P2 稍後標為已讀）：延遲送官方 receipt。
  /// 同一聊天室只保留最後一個 Timer；離開畫面即取消（dispose）。
  void _scheduleDelayedReadMarker(String eventId, ChatMessageView message) {
    _readDelayTimer?.cancel();
    _readDelayTimer = Timer(
      Duration(seconds: ringMarkReadDelaySec.value),
      () async {
        if (!mounted) return;
        try {
          await (widget.markRead ??
                  (r, m) => r.setReadMarker(eventId, mRead: eventId))(
              widget.room, message);
          _lastReadEventId = eventId;
          if (mounted) setState(() => _hasUnread = false);
        } on Object {
          // 失敗不寫 guard → 下一次 sync 可重試。
        }
      },
    );
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
    // 第六十九批（效能）：**整窗快取**——timeline 事件數＋最後 eventId＋
    // 最後事件本體未變時，直接回傳上次解析結果（跳過 decrypt／editMap／
    // replyMap／每則 resolve 全掃）。有收回／編輯／新訊息時指紋才變。
    // 單則 view cache 仍保留（指紋變時只重解析新事件）。
    final probeTimeline = _timeline;
    if (probeTimeline != null && probeTimeline.room.id == room.id) {
      final probe = probeTimeline.events;
      if (probe.isNotEmpty) {
        final fp = Object.hash(
            probe.length, probe.last.eventId, probe.last.body, _localEditsVersion);
        final cachedAll = _loadedMessagesCache[room.id];
        final lastFp = _windowFingerprint[room.id];
        if (lastFp == fp && cachedAll != null && cachedAll.isNotEmpty) {
          return List<ChatMessageView>.of(cachedAll);
        }
      }
    }
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
        // 第七十五批（B8 人類「系統事件參考 Element X」）：membership 事件
        // 也進 timeline，轉成「誰加入／退出／邀請／踢出／封鎖」系統列。
        e.type == EventTypes.RoomMember ||
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
                e.messageType == 'm.location' ||
                // 第一百零二批：相簿卡片走 m.notice（其他 client 看一般通知）。
                e.messageType == 'm.notice'));
    // 第七十批 f：無痕收回——被標 stealth 的事件**不進列表**（自動消失）。
    // 第八十五批（2b 相容）：同時辨識我方舊 Homing reason 旗標
    // （由 silent_redaction.dart 的 isSilentRedactionContent 判斷）。
    final events = timeline.events.where(editable).where((e) {
      final rb = e.redactedBecause;
      if (rb == null) return true;
      if (rb.content[kHomingStealthKey] == true) return false;
      return !isSilentRedactionContent(rb.content);
    }).toList();
    // 第六十九批：單則解析快取
    // 修法 #4（解密案 2026-11-13 源碼釘死）：/context 重建路徑 SDK 只解密
    // 帶旗標事件（room.dart L1775-1776）；重裝後舊事件無旗標 → 恆不解密。
    // 以官方 decryptRoomEvent 補解密（見 missing_key_repair.dart）。
    var decrypted = await decryptUndecryptedEvents(room, events);
    // 第七十批 a（人類回報「首入顯示無法解密、重進才顯示」）：開房首輪
    // vodozemac 引擎可能尚未就緒 → 首批事件 decrypt 失敗。確保引擎就緒
    // （官方 init，冪等）後**在原次 loader 再解密一次**，不必等使用者重進房。
    // 只呼叫官方 API，不寫任何加密邏輯。
    if (decrypted.any((e) => e.type == EventTypes.Encrypted) &&
        !_firstDecryptRetryDone.contains(room.id)) {
      _firstDecryptRetryDone.add(room.id); // 只自動重試一次（節流）。
      try {
        final ready = await initRustEngineInIsolate();
        if (ready) {
          decrypted = await decryptUndecryptedEvents(room, events);
        }
      } catch (_) {
        // 引擎 initialization 失敗 → 維持原解密結果（顯示佔位），不擲出。
      }
    }
    // 若仍失敗（真的缺 key）→ 顯示「無法解密」佔位是正確的，不偽裝已解密。
    // 不寫「清 cache」邏輯——那會讓每次 sync 都重解密＝無限重新載入。
    // 日後金鑰到達時 SDK 會 in-place 解密事件（type/body 改變）→ 指紋自動失效重載。
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
      // 第七十批（無痕收回）：帶 Homing 私有旗標的收回 → **整列不渲染**。
      // 一般收回仍照舊顯示「[已收回]」（所有人可見收回狀態）。
      if (event.redacted &&
          (isSilentRedactionContent(event.redactedBecause?.content) ||
              _silentRedactionIds.contains(event.eventId))) {
        continue;
      }
      // 第七十五批（B8）：membership 系統事件（Element X 式）。
      if (event.type == EventTypes.RoomMember) {
        final systemText = _membershipSystemText(event);
        if (systemText != null) {
          out.add(ChatMessageView(
            sender: event.senderId,
            body: systemText,
            sentAt: event.originServerTs,
            eventId: event.eventId,
            event: event,
            isSystemEvent: true,
          ));
        }
        continue;
      }
      // 第二十四批（Matrix 官方編輯語意）：m.replace 編輯事件**自身不渲染**
      //（SDK `Event.relationshipType`；編輯內容經官方聚合回套到原訊息，
      // 見下方 _editedBodyOf——與 Element X 同語意）。
      if (event.relationshipType == RelationshipTypes.edit) {
        continue;
      }
      // 第六十九批（效能）：單則解析快取——已解析過且內容簽章未變的事件
      // 直接重用 view（避免每輪 _load 重跑 resolveWithLocalEdits／官方
      // relations fallback）。簽章含 body／redacted／型別／format；無 TTL。
      final sig = Object.hash(
        event.eventId,
        event.body,
        event.redacted,
        event.type,
        event.messageType,
        event.content['format'],
        event.content['m.relates_to']?.toString(),
        // 第一百零二批：相簿卡片欄位也要進簽章（改內容才會重建 view）。
        event.content[kAlbumCardFlag]?.toString(),
      );
      final cachedView = _messageViewCache[event.eventId];
      if (cachedView != null && cachedView.sig == sig) {
        out.add(cachedView.view);
        continue;
      }
      // ignore: avoid_print
      final edited = resolveWithLocalEdits(
        event,
        editMap,
        timeline: timeline,
        localEdits: _localEdits,
      );
      // 第一百零二批：相簿卡片（只帶 id／名稱／照片 id，不含本機路徑）。
      final albumCard = parseAlbumCardEvent(event);
        final view = ChatMessageView(
          sender: event.senderId,
          // 第一百零八批：收回訊息走一般訊息版位，本文直接放「已收回訊息」。
          body: event.redacted
              ? S.t('已收回訊息')
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
          // 2026-11-20：收回訊息（官方 `Event.redacted`）→ 灰框「已收回訊息」。
          isRedacted: event.redacted,
          // 第二十四批：該訊息已被編輯過（官方 m.replace 聚合存在）。
          isEdited: edited.edited,
          // 第四十二批：編輯後的 HTML（Markdown）也要能渲染。
          formattedBody: edited.edited
              ? edited.formattedBody
              : _ownFormattedBody(event),
          // 第四十五批：回覆引言（官方 m.in_reply_to；查無被回覆事件則不顯示）。
          replyToSender: _replySenderOf(event, replyMap),
          replyToBody: _replyBodyOf(event, replyMap),
          replyToEventId: _replyTargetId(event),
          hideReplyQuote: _hiddenReplyIds.contains(event.eventId),
          event: event,
          isAlbumCard: albumCard != null,
          albumGroupId: albumCard?.id,
          albumName: albumCard?.name,
          albumPhotoIds: albumCard?.photoIds ?? const <String>[],
        );
        _messageViewCache[event.eventId] = (sig: sig, view: view);
        out.add(view);
    }
    // 第六十九批：記錄整窗指紋（供下次同 timeline 直接回傳 cache）。
    if (timeline.events.isNotEmpty && room.id.isNotEmpty) {
      _windowFingerprint[room.id] = Object.hash(
        timeline.events.length,
        timeline.events.last.eventId,
        timeline.events.last.body,
        _localEditsVersion,
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
      // 2026-11-21：同一則的**第二次**編輯也要觸發重載（原本只比 key，
      // 舊 key 存在就當沒更新 → 後續編輯不即時顯示）。
      final hasNew = newEdits.entries.any((entry) {
        final old = known[entry.key];
        return old == null ||
            old.eventId != entry.value.eventId ||
            old.body != entry.value.body;
      });
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
        return localDisplayName(m.sender, name);
      }
    } catch (_) {
      // 無 member state／client 初始化中 → 顯示原 ID。
    }
    return localDisplayName(m.sender, m.sender);
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
  Future<void> _requestHistory({bool quiet = false}) async {
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
        if (progress == 0 && !quiet) {
          final now = DateTime.now();
          if (_lastNoMoreHistoryShown == null ||
              now.difference(_lastNoMoreHistoryShown!) >
                  const Duration(seconds: 5)) {
            _lastNoMoreHistoryShown = DateTime.now();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.t('已沒有更早的訊息'))), // 文案草案
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
          SnackBar(content: Text('${S.t('無法載入更早訊息：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 訊息列表的**內容簽章**（第五十六批）。
  ///
  /// 舊判定只比「筆數 + 最後一則 eventId」→ 只有**內容**變了（編輯套用、
  /// 收回占位）時視為「沒變」→ 新列表被整份丟棄 → 畫面不動。這裡把
  /// eventId／body／已編輯記號一起納入（滾動雜湊，不建大字串）。
  ///
  /// ⚠️ 第五十七批（效能）：舊版逐字元混合（O(總字元數)；訊息多時每次重載
  /// 都要掃完全部文字）→ 改用 **`String.hashCode`**（Dart 會快取每個字串的
  /// hash → 第二次起 O(1)）＋ 固定乘數滾動 → 維持「內容變了偵測得到」的
  /// 語意，成本大幅下降。
  static int _messagesSignature(List<ChatMessageView> list) {
    var h = 0x811c9dc5;
    for (final m in list) {
      h = (h ^ (m.eventId?.hashCode ?? 0)) & 0x1fffffff;
      h = (h * 31) & 0x1fffffff;
      h = (h ^ m.body.hashCode) & 0x1fffffff;
      h = (h * 31) & 0x1fffffff;
      h = (h ^ (m.isEdited ? 1 : 0)) & 0x1fffffff;
    }
    return h;
  }

  Future<void> _load() async {    if (!mounted) {
      return;
    }
    // 第五十七批（效能）：量測本次重載耗時（**只記耗時與筆數，不記內容**）。
    final loadWatch = Stopwatch()..start();
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
      // 第六十九批（人類指示「載入時／無網路先用 cache 替代，不要顯示無訊息」）：
      // 重載失敗時**降級到已載入 cache**——畫面維持舊訊息，不閃「無訊息」、
      // 不顯示 spinner；只有在完全沒有 cache（從未載入成功過）才顯示錯誤。
      final cached = _loadedMessagesCache[widget.room.id];
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _loading = false;
          _messages = List<ChatMessageView>.of(cached);
        });
        return; // 静默降級；下次 sync 會再試（不洗版）。
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
    // 第五十六批：保留**仍在背景送出**的 pending 訊息——`_load()` 以伺服器事件
    // 重建列表（pending 尚不在伺服器事件裡）→ 否則會把**其他仍在排隊**的
    // pending 訊息一併清掉（連續送兩則時會少一則）。→ 重載後補回。
    final stillPending = _pendingSends
        .where((p) => !messages.any((m) => identical(m, p)))
        .toList();
    if (stillPending.isNotEmpty) {
      messages = [...messages, ...stillPending];
    }
    // 第七十批 b：cache **只存伺服器事件**——pending 由 `_pendingSends` 即時
    // 附加（L1407）；若把 pending 也寫進 cache，送出成功移除 pending 後，
    // 下一次 _load 命中整窗 cache 會把舊 pending 再帶回（「送出後又出現
    // 相同訊息傳送中」的根因）。
    final cacheable = messages
        .where((m) => !m.pending && !_pendingSends.any((p) => identical(p, m)))
        .toList();
    _loadedMessagesCache[widget.room.id] = List<ChatMessageView>.of(cacheable);
    // 第 8 點：判斷聊天室是否有未讀訊息（SDK 官方 Room.isUnread）。
    if (mounted) {
      setState(() {
        _hasUnread = widget.room.isUnread;
      });
    }

    // 僅在訊息實際變更時更新，避免重複 setState 造成畫面閃爍。
    //
    // ⚠️ 第五十六批（2026-11-16）：舊判定只看「筆數 + 最後一則 eventId」→
    // **只有內容變了**（編輯套用、收回占位）時 `changed` 為 false → **整份新
    // 列表被丟棄** → 畫面不動（人類回報「編輯完怎麼沒動」「靠編輯完要其他
    // 地方有更新的時候才會變」）。→ 改用**內容簽章**比對（含 body／已編輯
    // 記號／eventId）。
    final oldSignature = _messagesSignature(_messages);
    final newSignature = _messagesSignature(messages);
    final changed = oldSignature != newSignature;
    // 第五十七批（效能）：量測本次重載耗時（**只記耗時與筆數，不記內容**）。
    loadWatch.stop();
    PerfLog.record(
      'chat.load',
      loadWatch.elapsedMicroseconds,
      {'訊息': messages.length, '有變': changed ? 1 : 0},
    );
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

    // 第六十四批①：首頁公告橫幅點入 → 自動定位該釘選訊息（一次；詳見
    // `_performAutoJump`）。放 `_load()` 末段＝首載與後續重載都會檢查，
    // 但 `_autoJumpDone` 保證只執行一次。
    if (widget.jumpToEventId != null) {
      unawaited(_performAutoJump());
    }

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
      // 第六十九批（F-2/P2）：①無痕預覽＝完全不自動送 receipt（手動
      // 「標為已讀」仍可送）②稍後標為已讀＝延遲 N 秒後送（離開即取消）；
      // 兩者皆**預設關閉**，一般使用者行為不變。
      if (ringIncognitoRead.value) {
        // 不送，也不寫 guard（關掉開關後下一次 sync 仍可補標）。
      } else if (ringMarkReadDelaySec.value > 0) {
        _scheduleDelayedReadMarker(target, latest!);
      } else {
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
    }
    // 第九十九批：置底**只在初始載入執行一次**。
    // 舊邏輯「!_initialLoadDone || alreadyAtBottom」在滑到最舊時，
    // 內容更新瞬間 reverse 列表 offset 可能短暫回到 0 → alreadyAtBottom
    // 誤判為 true → 強制 jumpTo(0) 跳回最新（人類實機回報）。
    // 平時置底交給「回到底部」鈕（_scrollToBottom 仍然存在）與新訊息自身可見性。
    if (!_initialLoadDone) {
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
          ? '${S.t('You unsent a message.')}\n${S.t('How to unsend discreetly')}' // 第八十九批：LINE 式
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
  ///
  /// ⚠️ 第五十七批（列表視覺化後）：**未進入可視範圍的列尚未建構** →
  /// `currentContext` 為 null。此時：
  /// 1. 先用**列計畫**粗估目標 offset 跳一次（平均列高估算，可能有偏差），
  /// 2. 下一幀若該列已建構 → 官方 `Scrollable.ensureVisible` 精準定位；
  /// 3. 仍找不到 → 顯示原本的「太舊，請往上捲」提示。
  /// ⚠️ Flutter 3.47 框架**已無** `ItemScrollController`／`scrollUntilVisible`
  /// （CI analyze 實證）→ 只能走上述「估算＋ensureVisible」路徑。
  void _jumpToPinnedMessage() {
    final id = _pinnedBannerEventId;
    if (id == null) return;
    unawaited(_jumpToEventIdWithHistory(id));
  }

  /// 第九十三批（人類指示）：按公告 → **自動載入更早訊息直到目標出現**，
  /// 再精準定位；不再只顯示「請上滑」。
  /// - 已載入 → 直接 `_jumpToEventId`
  /// - 未載入 → 有界 requestHistory（最多 6 輪），每輪後重試；
  /// - 仍找不到 → 才如實提示（已到最早可及處）。
  Future<void> _jumpToEventIdWithHistory(String id) async {
    if (_messages.any((m) => m.eventId == id)) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _jumpToEventId(id);
      return;
    }
    if (widget.loadMessages != null || _timeline == null) {
      _jumpToEventId(id); // 走既有粗估/提示路徑
      return;
    }
    for (var round = 0; round < 6 && mounted; round++) {
      await _requestHistory(quiet: true);
      if (!mounted) return;
      if (_messages.any((m) => m.eventId == id)) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        _jumpToEventId(id);
        return;
      }
      if (!(_timeline?.canRequestHistory ?? false)) break;
    }
    _showJumpOutOfRange(message: S.t('已載入到最早訊息，仍找不到公告所指的訊息'));
  }

  /// 第六十四批①：跳到指定訊息（原 `_jumpToPinnedMessage` 一般化）。
  void _jumpToEventId(String id) {
    // 視覺化後 key 可能尚未建立（該列還沒被建構）→ 先補建，讓 builder 用同一把。
    final key = _rowKeys[id] ??= GlobalKey();
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
      return;
    }
    // 粗估：計畫中較新的列數 × 平均列高（reverse 清單：offset 0＝最新）。
    var targetIndex = -1;
    for (var i = 0; i < _rowPlan.length; i++) {
      final row = _rowPlan[i];
      if (row.kind != ChatRowKind.message) continue;
      if (_messages[row.messageIndex].eventId == id) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0 || !_scrollController.hasClients) {
      _showJumpOutOfRange();
      return;
    }
    final newerRows = _rowPlan.length - 1 - targetIndex;
    final estimated =
        (newerRows * kEstimatedChatRowHeight).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(estimated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx2 = _rowKeys[id]?.currentContext;
      if (ctx2 != null) {
        Scrollable.ensureVisible(
          ctx2,
          duration: const Duration(milliseconds: 300),
          alignment: 0.3,
        );
      } else {
        _showJumpOutOfRange();
      }
    });
  }

  /// 跳轉失敗（太舊／不在本機 timeline）→ 提示（沿用舊文案）。
  /// 第六十四批①：[message] 可覆寫文案（公告自動定位失敗另有說明）。
  void _showJumpOutOfRange({String? message}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message ??
              S.t('該訊息不在目前載入範圍（太舊）；請往上捲動載入更早訊息'), // 文案草案
        ),
      ),
    );
  }

  /// 第六十四批①（人類：「公告自動找過去訊息，不要讓使用者自己找」）：
  /// 進房後自動定位首頁公告橫幅帶入的釘選訊息 [widget.jumpToEventId]。
  ///
  /// * 訊息已在已載入窗口 → 直接跳（`_jumpToEventId`，與房內釘選橫幅同路徑）。
  /// * 不在窗口 → 以官方 `Timeline.requestHistory` **有界**補抓（最多 3 次
  /// 調用；官方每次內部至多 4 輪 ×100）→ 找到即跳；仍找不到＝如實提示，
  /// **不**無限捲動（AGENTS.md：不做無限滾動資訊流）。
  /// * `loadMessages` 注入（測試環境）無 timeline → 直接提示，不假跳。
  Future<void> _performAutoJump() async {
    final id = widget.jumpToEventId;
    if (id == null || _autoJumpDone || !mounted) {
      return;
    }
    if (_messages.any((m) => m.eventId == id)) {
      _autoJumpDone = true;
      // 等本幀建構完成再跳（`_rowPlan`／row key 於 build 產生）。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _jumpToEventId(id);
      return;
    }
    if (widget.loadMessages != null || _timeline == null) {
      _autoJumpDone = true;
      _showJumpOutOfRange(
        message: S.t('公告訊息太舊，無法自動定位'), // 文案草案
      );
      return;
    }
    for (var i = 0; i < 6 && mounted; i++) { // 第九十三批：3→6 輪（與房內公告同）
      await _requestHistory(quiet: true);
      if (!mounted) return;
      if (_messages.any((m) => m.eventId == id)) {
        _autoJumpDone = true;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        _jumpToEventId(id);
        return;
      }
      if (!(_timeline?.canRequestHistory ?? false)) {
        break; // 已到本機／伺服器可及的最早處。
      }
    }
    _autoJumpDone = true;
    _showJumpOutOfRange(
      message: S.t('已載入到最早訊息，仍找不到公告所指的訊息'),
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
          SnackBar(content: Text('${S.t('取消釘選失敗：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('設為已讀失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  // ── 批次 D：圖片全屏預覽（草案）───────────────────────────────────────

  /// 點擊聊天圖片 → 全屏預覽（ImagePreviewScreen）。縮圖先帶入顯示，
  /// 全尺寸由 preview 內以 SDK 官方 API 載入。
  ///
  /// 第六十四批②（人類：「點入圖片後可左／右滑看前一個／後一個傳送圖片」）：
  /// 一併傳入**房內圖片清單**（`_messages` 中所有帶 event 的圖片，時間序）
  /// 與被點圖片的 index → 預覽頁 PageView 左右滑切換。單圖房間不傳
  /// 清單（維持原單圖模式）。人類 2026-11-17：**貼圖不入清單**（見下）。
  Future<void> _openImagePreview(ChatMessageView m, Uint8List? bytes) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    // 第四十六批：貼圖**預覽開關**（kv `sticker_preview_enabled`，與「我的貼圖」
    // 頁的選單同一開關）。關閉時點貼圖**不開**全屏預覽（貼圖只是小圖，
    // 放大無實用價值；省下使用者誤觸）。
    // **第六十七批（人類拍板 2026-11-17）：貼圖一律不可點入檢視（著作權，
    // 與「不可分享／下載」同一理由）——改為硬性限制，kv 開關移除。**
    if (m.isSticker) {
      return;
    }
    // 第六十四批②：房內圖片 gallery（時間序；pending（無 event）不入列）。
    // 人類 2026-11-17：**貼圖不入圖片檢視**——gallery 只收 m.image；
    // 點貼圖本身維持單圖模式（第四十六批貼圖預覽開關語意不變）。
    final gallery = <Event>[];
    var initialIndex = 0;
    if (!m.isSticker) {
      for (final g in _messages) {
        if (!g.isImage) continue;
        final ev = g.event;
        if (ev == null) continue;
        if (g.eventId != null && g.eventId == m.eventId) {
          initialIndex = gallery.length;
        }
        gallery.add(ev);
      }
    }
    final hasGallery = !m.isSticker && gallery.length > 1;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ImagePreviewScreen(
          event: event,
          initialBytes: bytes,
          galleryEvents: hasGallery ? gallery : null,
          galleryInitialIndex: hasGallery ? initialIndex : null,
        ),
      ),
    );
  }

  // ── 附件（批次 III-c，依人類注記參考圖 new_ref/…110220_labeled.png）──
  // 「＋」改為**展開面板**：面板開啟時上排鈕變 ×（關閉）／相機／相簿，
  // 輸入框與表情鈕不變；面板下方一排＝Files／Contact／位置。
  // Contact／位置為草案骨架（位置需 flutter_map 依賴批准，未動工）。

  /// 第一百零一批（人類定稿）：點「+」彈出**小型文字選單**（在 + 附近，
  /// 不佔滿寬度、不另開一大片面板）。所有原功能入口都保留：
  /// 相機／相簿／檔案／聯絡資訊／位置／無聲／Markdown。
  /// 預約鍵依人類指示留在送出鍵旁邊，不重複放進選單。
  List<PopupMenuEntry<String>> _quickMenuItems() {
    return [
      PopupMenuItem(value: 'camera', child: Text(S.t('相機'))),
      PopupMenuItem(value: 'gallery', child: Text(S.t('相簿'))),
      PopupMenuItem(value: 'file', child: Text(S.t('檔案'))),
      PopupMenuItem(value: 'contact', child: Text(S.t('聯絡資訊'))),
      PopupMenuItem(value: 'location', child: Text(S.t('位置'))),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'silent',
        child: Text(
          _silentSend ? '無聲傳送：開（本則不通知）' : '無聲傳送：關',
        ),
      ),
      PopupMenuItem(
        value: 'markdown',
        child: Row(
          children: [
            MarkdownMarkIcon(
              color: Theme.of(context).colorScheme.onSurface,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              _markdownOn ? 'Markdown：開（本則）' : 'Markdown：關（本則）',
            ),
          ],
        ),
      ),
    ];
  }

  /// 選單項目 → 原本的動作（功能完全不變，只是入口從面板改到文字選單）。
  void _onQuickMenuSelected(String value) {
    switch (value) {
      case 'camera':
        if (!_uploading) unawaited(_onCamera());
        break;
      case 'gallery':
        if (!_uploading) unawaited(_openGallerySheet());
        break;
      case 'file':
        unawaited(_startAttach(FileType.any));
        break;
      case 'contact':
        // 把**自己的** Matrix ID 填入輸入框（不觸碰他人個資）；
        // 送出與否由使用者決定（原附件列行為不變）。
        final mxid = widget.room.client.userID;
        if (mxid != null) {
          _inputController.text =
              '${_inputController.text}我的 Matrix ID：$mxid';
          setState(() {});
        }
        break;
      case 'location':
        unawaited(_sendLocation());
        break;
      case 'silent':
        setState(() => _silentSend = !_silentSend);
        break;
      case 'markdown':
        _toggleMarkdown();
        break;
    }
  }

  // ── 第一百零二批：相簿卡片 ─────────────────────────────────────────────

  /// 問相簿名稱（取消回 null）。
  Future<String?> _askAlbumName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('建立相簿')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(hintText: S.t('相簿名稱')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(ctx, name);
            },
            child: Text(S.t('建立')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// 送出相簿卡片訊息（m.notice + 自訂欄位；其他 client 會顯示一般通知）。
  Future<void> _sendAlbumCard(AlbumGroup group) async {
    final body = '${S.t('相簿')}：${group.name}（${group.photoIds.length}）';
    final injected = widget.sendAlbumCard;
    if (injected != null) {
      await injected(widget.room, body, group.id, group.name, group.photoIds);
      return;
    }
    await sendWithRateLimitRetry(
      () => widget.room.sendEvent(buildAlbumCardContent(
        body: body,
        id: group.id,
        name: group.name,
        photoIds: group.photoIds,
      )),
    );
  }

  /// 長按圖片 → 加入相簿 → 建立分組 → 送出卡片。
  Future<void> _addImageToAlbum(ChatMessageView m) async {
    final file = await _loadFullImage(m);
    if (file == null || !mounted) return;
    final name = await _askAlbumName();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final photo = await importPhotoBytes(file.bytes, title: name);
      final group = await createAlbumGroup(name, <String>[photo.id]);
      await _sendAlbumCard(group);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('加入相簿失敗'))),
        );
      }
    }
  }

  /// 點卡片 → 開本機相簿（可注入 callback 供測試）。
  void _openAlbumFromCard(ChatMessageView m) {
    final injected = widget.onOpenAlbum;
    if (injected != null) {
      injected(m.albumGroupId ?? '', m.albumName ?? S.t('相簿'));
      return;
    }
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumScreen(initialGroupName: m.albumName),
      ),
    ));
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
          SnackBar(content: Text('${S.t('選取失敗：')}$e')),
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
          await _sendOne(bytes, pf.name, path: pf.path, inReplyTo: _replyTo?.event);
        } catch (e) {
          _batchFail++;
          _batchFailReason = '$e';
        }
      }
      _finishBatch();
    });
  }

  /// 2026-11-20：相簿（image_picker 既有依賴）——系統相簿多選 → 預覽格、
  /// 原始畫質開關、送出。非原畫質以 dart:ui 縮至 1600px（零新依賴）。
  Future<void> _openGallerySheet() async {
    List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('選取失敗：')}$e')),
        );
      }
      return;
    }
    if (picked.isEmpty || !mounted) return;

    final selected = List<bool>.filled(picked.length, true);
    var original = true;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${S.t('選擇照片')}（${selected.where((s) => s).length}）',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              SizedBox(
                height: 220,
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: picked.length,
                  itemBuilder: (c, i) => GestureDetector(
                    onTap: () => setSheet(() => selected[i] = !selected[i]),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(picked[i].path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.image),
                        ),
                        if (selected[i])
                          const Positioned(
                            right: 2,
                            top: 2,
                            child: Icon(Icons.check_circle,
                                color: Colors.green, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              ListTile(
                title: Text(S.t('原始畫質')),
                subtitle: Text(S.t('關閉則縮至 1600px 以減少上傳量')),
                trailing: Switch(
                  value: original,
                  onChanged: (v) => setSheet(() => original = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    '${S.t('送出')}（${selected.where((s) => s).length}）',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final files = <XFile>[
      for (var i = 0; i < picked.length; i++)
        if (selected[i]) picked[i],
    ];
    if (files.isEmpty) return;
    await _chainTask(() async {
      _beginUpload(files.length);
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        _updateUpload(
          index: i + 1,
          name: f.name,
          stage: original ? S.t('讀取中') : S.t('壓縮中'),
        );
        _updateUploadProgress();
        try {
          var bytes = await f.readAsBytes();
          if (!original) bytes = await _downscaleImage(bytes);
          await _sendOne(bytes, f.name, path: f.path, inReplyTo: _replyTo?.event);
        } catch (e) {
          _batchFail++;
          _batchFailReason = '$e';
        }
      }
      _finishBatch();
    });
  }

  /// 將圖片縮至最長邊 1600px（dart:ui，無需新依賴）。
  Future<Uint8List> _downscaleImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 1600, targetHeight: 1600);
    final frame = await codec.getNextFrame();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      frame.image.width,
      frame.image.height,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
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
          SnackBar(content: Text('${S.t('相機失敗：')}$e')),
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
        await _sendOne(bytes, shotFile.name, path: shotFile.path, inReplyTo: _replyTo?.event);
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
  Future<void> _sendOne(
    Uint8List bytes,
    String name, {
    String? path,
    Event? inReplyTo,
  }) async {
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
    // 改為先在**背景 isolate** 呼叫 SDK 官方 encryptFile，再經
    // PreEncryptedUpload 官方注入管道給 sendFileEvent（App 端零自寫演算法／
    // 零金鑰流程）。未加密房＝不加密（與 SDK 行為一致）。
    //
    // ⚠️ **第五十一批（2026-11-16）更正本段舊註解的兩處誤判**：
    // ①「encryptFile 須在**主 isolate**執行」——錯。SDK 官方 encryptFile 可在
    //    背景 isolate 執行（大檔不卡 UI），但**該 isolate 必須自行初始化
    //    vodozemac 引擎**（rust 狀態不跨 isolate）。
    // ②「encryptFile 是**純 Dart AES-CTR+SHA-256**」——錯。matrix SDK 14.2.0
    //    `encryptFile` → `CryptoUtils.aesCtr`／`sha256` 走 **vodozemac
    //    （rust）**（vodozemac-0.9.1 `lib/src/api.dart` L631-652），非 SDK
    //    內那份純 Dart `crypto.dart`。
    // → 未在背景 isolate 內先 `initRustEngineInIsolate()` 就呼叫，必然拋
    //   StateError「flutter_rust_bridge has not been initialized…」
    //   （= 人類 2026-11-16 實機回報的「圖片上傳失敗」根因）。
    //   修法與官方 SDK 的 isolate 模式一致（`NativeImplementationsIsolate`
    //   的 `vodozemacInit` 回呼），詳見 `engine_init.dart` 與
    //   `known_problems.md`（第五十一批條目）。
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
          // 第一百零八批：附件也支援回覆（回覆放圖片）。
          inReplyTo: inReplyTo,
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
    if (_replyTo != null) {
      _replyTo = null; // 第一百零八批：附件送出後清回覆。
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已送出 $_batchOk 個附件'
            // 第一百零八批：Homing 自己不擋大小；matrix.org 等伺服器有預設上限。
            '${_batchTooBig > 0 ? "，$_batchTooBig 個超過伺服器上限（Homing 不擋；伺服器可能有預設限制）" : ""}'
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

  /// 第七十批 e：錄音面板送出回呼——把本機錄音檔用官方 `sendFileEvent` 送出
  /// （加密房 SDK 自動 crypto），「跟一般訊息一樣」。不碰任何加密邏輯。
  Future<String?> _sendVoiceFromFile(
    BuildContext sheetContext, {
    required String path,
    required int durationMs,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      try { await file.delete(); } catch (_) {}
      return null;
    }
    // Matrix 語音訊息：官方 MatrixAudioFile（msgType 固定 m.audio，且帶 duration
    // 中繼資料）——用一般 MatrixFile 時，本機 pending 預覽會被當純檔名顯示。
    final matrixFile = MatrixAudioFile(
      bytes: bytes,
      name: '語音訊息.m4a',
      mimeType: 'audio/mp4',
      duration: durationMs,
    );
    try {
      await _chainTask(() async {
        await sendWithRateLimitRetry(
          () => widget.room.sendFileEvent(
            matrixFile,
            // duration 由房间事件 content.info.duration 承載；SDK sendFileEvent
            // 會把 MatrixFile mimeType 寫入 m.audio（官方行為）。
          ),
        );
      });
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('語音送出失敗')}：$e')),
        );
      }
    }
    try { await file.delete(); } catch (_) {}
    return path;
  }

  Future<void> _onSend() async {
    final text = _inputController.text.trim();
    // 第六十七批（人類指示「訊息在傳送佇列時應該要能打字並按傳送鍵進佇列」）：
    // 移除 `_sending` 禁止——佇列在送時**仍可打字、按送出＝再排入一則**。
    // 原註解「按鈕在排隊期間保持 disabled，避免把『排隊中』誤讀成已送出」
    // 當初寫錯（人類 2026-11-17 指正），作廢。
    if (text.isEmpty) {
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
      _activeSends++; // 第六十七批：計數制（多則並行排隊）。
      _message = null;
    });
    _inputController.clear(); // 隨即釋放輸入框（排隊中也能繼續打字）。

    // 第五十五批（2026-11-16）：**先顯示、背景繼續送**（人類回報：「傳送訊息
    // 是不是應該先顯示在上面，背景繼續傳送？不然使用者會覺得當機了」）。
    // 舊行為＝**等伺服器回應成功後**才把訊息放進列表（該處原註解自稱「樂觀
    // 更新」，實際是樂觀的相反）→ 等待期間畫面毫無變化＝使用者以為當機。
    // 現在：按下送出**立刻**插入一則 pending 訊息（半透明＋「傳送中」記號），
    // 實際送出在**背景**進行；成功 → `_load()` 以伺服器事件取代；失敗 → 移除
    // pending 並把文字還回輸入框（既有失敗行為不變）。
    final pendingView = ChatMessageView(
      sender: widget.room.client.userID ?? '',
      body: text,
      sentAt: DateTime.now(),
      pending: true,
    );
    if (mounted) {
      setState(() {
        _messages = [..._messages, pendingView];
      });
    }
    _pendingSends.add(pendingView);

    String? error;

    // 文字排隊（人類批准 2026-11-06 批次 3）：送出動作入序列鏈——同時
    // 傳圖＋傳文字時，文字在圖片之後依序送出，不出現「文字先到、
    // 圖片後到」亂序。**第六十七批（人類 2026-11-17 指正）**：排隊期間
    // **不禁用輸入與送出**——原「按鈕保持 disabled」的註解當初寫錯，作廢；
    // 排隊中按送出＝再排入一則（各自的 pending 訊息即「排隊中」的呈現）。
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
                // 只有開了 Markdown 的這則才帶渲染要求旗標（中繼資料）。
                markdownRender: formattedBody != null,
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
        _restoreFailedText(text); // 失敗把文字還給輸入框（佇列多則下不覆蓋）。
      }
    } catch (e) {
      error = '送出失敗：已排入離線佇列';
      try {
        await OfflineQueue.enqueue(widget.room.id, text);
      } catch (_) {}
      _restoreFailedText(text);
    }
    if (mounted) {
      setState(() {
        _activeSends = (_activeSends - 1).clamp(0, 1 << 30); // 第六十七批：計數制。
        _message = error;
        _replyTo = null; // 送出後解除回覆狀態
        if (error == null) {
          // 無聲與 Markdown 皆為「本則例外動作」→ 送出成功後復位。
          _silentSend = false;
          _markdownOn = false;
        }
      });
    }
    // 第五十五批：移除 pending 樣本。
    // * 成功 → 隨後的 `_load()` 會帶回伺服器事件（取代 pending）。
    // * 失敗（含已排入離線佇列）→ pending 消失、文字已還回輸入框。
    if (mounted) {
      setState(() {
        _messages = _messages.where((m) => !identical(m, pendingView)).toList();
      });
    }
    _pendingSends.removeWhere((p) => identical(p, pendingView));
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
        SnackBar(content: Text('${S.t('請求失敗：')}$e')), // 文案草案
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

  /// 第七十五批（B8）：把官方 m.room.member 事件轉成 Element X 式系統文字。
  /// 只處理「狀態真的改變」的事件（重複 state 不顯示）。
  String? _membershipSystemText(Event event) {
    final content = event.content;
    final prev = event.prevContent ?? const <String, Object?>{};
    final membership = content['membership'];
    final previous = prev['membership'];
    if (membership is! String) return null;
    if (membership == previous) return null;
    final target = event.stateKey ?? event.senderId;
    final actor = _memberDisplayName(event.senderId);
    final who = _memberDisplayName(target);
    switch (membership) {
      case 'join':
        return '$who ${S.t('加入聊天室')}';
      case 'leave':
        if (target == event.senderId) return '$who ${S.t('退出聊天室')}';
        return '$actor ${S.t('將')} $who ${S.t('踢出聊天室')}';
      case 'invite':
        return '$actor ${S.t('邀請')} $who ${S.t('加入聊天室')}';
      case 'ban':
        return '$actor ${S.t('封鎖了')} $who';
      case 'unban':
        return '$actor ${S.t('解除封鎖')} $who';
      default:
        return null;
    }
  }

  /// 第七十五批：系統事件顯示用的成員名（官方 state → calcDisplayname）。
  String _memberDisplayName(String mxid) {
    try {
      final state = widget.room.getState(EventTypes.RoomMember, mxid);
      final name = state?.asUser(widget.room).calcDisplayname();
      if (name != null && name.isNotEmpty) return name;
    } on Object {
      // 查無 state／SDK 例外 → 退回原始 Matrix ID（系統事件不能因此消失）。
    }
    return mxid;
  }

  /// 第八十二批（#6）：選本機檔案＋時間 → 排程附件送出。
  /// 路徑只存本機 kv；server account data 只存檔名／MIME（metadata）。
  Future<void> _scheduleAttachment() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty || picked.first.path == null || !mounted) return;
    final pf = picked.first;
    final path = pf.path!;
    final now = DateTime.now();
    final initial = now.add(const Duration(minutes: 5));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (due.difference(DateTime.now()) < const Duration(minutes: 1)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('預約時間需晚於一分鐘後'))),
        );
      }
      return;
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    await setAttachmentPath(id, path);
    await addScheduledMessage(widget.room.client, ScheduledMessage(
      id: id,
      roomId: widget.room.id,
      text: pf.name,
      dueAt: due.millisecondsSinceEpoch,
      attachmentName: pf.name,
      attachmentMime: pf.extension,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('附件已加入預約'))),
      );
    }
  }

  /// 第八十二批：背景設定 sheet（電源／網路）。
  Future<void> _openBackgroundSettings() async {
    final ignoring = await isIgnoringBatteryOptimizations();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.t('預約訊息背景設定'),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: Icon(ignoring ? AllIcons.check : AllIcons.warningAmberRounded),
              title: Text(S.t('電源使用限制')),
              subtitle: Text(ignoring
                  ? S.t('已忽略電池最佳化（可背景準點送）')
                  : S.t('尚未忽略；點此請求關閉')),
              onTap: () async {
                final navigator = Navigator.of(ctx);
                await requestIgnoreBatteryOptimizations();
                navigator.pop();
              },
            ),
            ListTile(
              leading: Icon(AllIcons.cloudOutlined),
              title: Text(S.t('網路')),
              subtitle: Text(S.t('沒網路時保留預約，連上才送；點此開網路設定')),
              onTap: () async {
                final navigator = Navigator.of(ctx);
                await openNetworkSettings();
                navigator.pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 第六十九批（F-2/P1 預約訊息）：把目前輸入的文字排程到指定時間送出。
  /// Matrix 無此協定 → 只存本機 kv；前景 Timer 由 MainShell 負責送。
  Future<void> _scheduleDraft() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final initial = now.add(const Duration(minutes: 5));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (due.difference(DateTime.now()) < const Duration(minutes: 1)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('預約時間需晚於一分鐘後'))),
        );
      }
      return;
    }
    await addScheduledMessage(widget.room.client, ScheduledMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      roomId: widget.room.id,
      text: text,
      dueAt: due.millisecondsSinceEpoch,
      silent: _silentSend,   // #2：帶無聲旗標
      markdown: _markdownOn, // #2：帶 Markdown 開關
    ));
    _inputController.clear();
    // 預約也屬「本則」：帶完旗標即復位，不影響下一則。
    if (mounted) setState(() => _markdownOn = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('已加入預約訊息（需保持 App 運行，否則下次開啟才送）'))),
      );
    }
  }

  /// 本房預約清單（可取消）。
  Future<void> _openScheduledListSheet() async {
    final all = await loadScheduledMessages();
    final mine = all.where((m) => m.roomId == widget.room.id).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(S.t('預約訊息'), style: Theme.of(ctx).textTheme.titleMedium),
              ),
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(S.t('此聊天室沒有預約訊息')),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in mine)
                        ListTile(
                          title: Text(m.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatListTime(DateTime.fromMillisecondsSinceEpoch(m.dueAt))),
                          trailing: IconButton(
                            tooltip: S.t('取消預約'),
                            icon: Icon(AllIcons.close),
                            onPressed: () async {
                              await removeScheduledMessage(widget.room.client, m.id);
                              mine.removeWhere((x) => x.id == m.id);
                              setSheetState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRoomMenu() {
    final directPartner = widget.room.directChatMatrixID;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // 第八十二批：預約附件（選本機檔案＋時間；路徑只存本機）。
            ListTile(
              leading: Icon(AllIcons.insertDriveFileOutlined),
              title: Text(S.t('預約傳送附件')),
              subtitle: Text(S.t('需保持 App 運行並開啟網路；離線時連上才送')),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_scheduleAttachment());
              },
            ),
            // 第八十二批：背景設定（電源／網路）。
            ListTile(
              leading: Icon(AllIcons.bugReportOutlined),
              title: Text(S.t('預約訊息背景設定')),
              subtitle: Text(S.t('關閉電源限制並保持網路，預約才會準點送')),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_openBackgroundSettings());
              },
            ),
            // 第六十九批（F-2/P1）：預約訊息清單（查看／取消本房預約）。
            ListTile(
              leading: Icon(AllIcons.schedule),
              title: Text(S.t('預約訊息')),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_openScheduledListSheet());
              },
            ),
                        // 批次十二③：聊天室資訊頁（靜音／成員／邀請／退出／公告房間）。
                        ListTile(
              leading: CompoundIcon(CompoundIcons.info, size: 24, color: Theme.of(context).colorScheme.onSurface),
              title: Text(S.t('聊天室資訊')), // 草案文案
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
                leading: CompoundIcon(CompoundIcons.key, size: 24, color: Theme.of(context).colorScheme.onSurface),
                title: Text(S.t('向其他裝置請求缺失金鑰')), // 文案草案，待人類設計定稿
                onTap: () => unawaited(_requestMissingKeysForRoom(ctx)),
              ),
                        ListTile(
              leading: CompoundIcon(CompoundIcons.image, size: 24, color: Theme.of(context).colorScheme.onSurface),
              title: Text(S.t('設定聊天室背景')), // 草案文案
              onTap: () async {
                Navigator.of(ctx).pop();
                final choice = await showDialog<String>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(S.t('聊天室背景')), // 文案草案
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: CompoundIcon(CompoundIcons.settings, size: 24, color: Theme.of(context).colorScheme.onSurface),
                          title: Text(S.t('選擇顏色')),
                          onTap: () => Navigator.pop(c, 'color'),
                        ),
                        ListTile(
                          leading: CompoundIcon(CompoundIcons.image, size: 24, color: Theme.of(context).colorScheme.onSurface),
                          title: Text(S.t('選擇圖片')),
                          onTap: () => Navigator.pop(c, 'image'),
                        ),
                        if (_roomBackground != null)
                          ListTile(
                            leading: CompoundIcon(CompoundIcons.delete, size: 24, color: Theme.of(context).colorScheme.onSurface),
                            title: Text(S.t('重置背景')),
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
                    title: Text(S.t('選擇背景色')),
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
                leading: CompoundIcon(CompoundIcons.block, size: 24, color: Theme.of(context).colorScheme.onSurface),
                title: Text(S.t('封鎖使用者')), // 1.9（SDK 官方 ignore API）
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
                leading: CompoundIcon(CompoundIcons.error, size: 24, color: Theme.of(context).colorScheme.onSurface),
                title: Text(S.t('檢舉')), // 1.9a
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
              leading: CompoundIcon(CompoundIcons.poll, size: 24, color: Theme.of(context).colorScheme.onSurface),
              title: Text(S.t('發起投票')), // 批次 D；文案草案
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
              leading: CompoundIcon(CompoundIcons.group, size: 24, color: Theme.of(context).colorScheme.onSurface),
              title: Text(S.t('成員管理')), // 2.2
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
    setState(() => _emojiOpen = !_emojiOpen);
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

  @override
  Widget build(BuildContext context) {
    final me = widget.room.client.userID ?? '';
    final latestOwnIndex = _messages.lastIndexWhere((m) => m.sender == me);
    // 第五十七批（效能）：**只算列計畫**（輕量資料），Widget 交給
    // `ListView.builder` 視覺化時才建立（見下方 itemBuilder）。
    final planWatch = Stopwatch()..start();
    final plan = _buildRowPlan(me, latestOwnIndex);
    planWatch.stop();
    // 供「跳到釘選訊息」粗估 offset 用（第五十七批）。
    _rowPlan = plan;
    PerfLog.record(
      'chat.plan',
      planWatch.elapsedMicroseconds,
      {'訊息': _messages.length, '列': plan.length},
    );
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
                a11yButton(label: S.t('設為已讀'), child: IconButton(
                  tooltip: S.t('設為已讀'), // 文案草案
                  icon: CompoundIcon(CompoundIcons.markUnread, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  onPressed: () => unawaited(_markAsRead()),
                )),
                Expanded(
                  child: Text(S.t('此聊天室有未讀訊息'), // 文案草案
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
            trailing: a11yButton(label: S.t('取消釘選'), child: IconButton(
              tooltip: S.t('取消釘選'), // 文案草案
              icon: CompoundIcon(CompoundIcons.pin, size: 24, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => unawaited(_unpinPinnedMessage()),
            )),
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
                      : ListView.builder(
                          controller: _scrollController,
                          // Issues「進房自動跳頂／滑到底被拉回頂部重抓舊訊息」
                          // 根因重構（2026-11-03，人類提供重現）：舊→新列表的
                          // 「底＝高 offset」定位仰賴 lazy ListView 的估算 extent
                          // 與逐 frame 補跳／offset clamp，內容異動即失準。
                          // 改 Flutter 官方聊天室標準做法 reverse: true——
                          // **offset 0 ＝ 最新訊息**：進房零跳轉、歷史插入（高
                          // offset 端）不移動視覺位置、新訊息自動在視野內。
                          reverse: true,
                          // 第五十七批（效能）：改 **ListView.builder** 視覺化——
                          // 舊實作是 `ListView(children: [...rows.reversed])`
                          // → **逐則建立 Widget**（數百～數千則時＝整棵 Widget
                          // 樹 → 主執行緒壅塞／記憶體暴增／被 Android 判當機）。
                          // itemCount ＝ 列數＋（歷史載入中指示器 1 個）。
                          itemCount: plan.length + (_historyLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            // reverse:true → index 0 ＝ 最底（最新）。
                            // 計畫為舊→新 → 取 index 反轉。
                            if (index >= plan.length) {
                              // 最舊端（列表頂端）＝「載入更早訊息」指示器。
                              return const Padding(
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
                              );
                            }
                            final row = plan[plan.length - 1 - index];
                            return _buildRowWidget(row, me);
                          },
                        ),
              // 第 21 點：滑到底按鈕改為獨立 Positioned（覆蓋在列表右下角，
              // 不佔用 Column 垂直空間，避免產生「整排空白」遮住訊息）。
              if (_showScrollDown && !_uploading && plan.isNotEmpty)
                Positioned(
                  right: 10,
                  bottom: 78, // 置於輸入列上方，不遮住輸入框
                  child: a11yButton(
                    label: S.t('滑到底部'),
                    child: IconButton.filledTonal(
                      tooltip: S.t('滑到底部'), // 文案草案
                      onPressed: _scrollToBottom,
                      icon: lineIconOverMaterial(
                        materialIcon: AllIcons.arrowDownward,
                        lineIcon: LineIcon.chevronDown,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 20,
                      ),
                    ),
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
                    child: Semantics(
                      label: S.t('上傳預覽'),
                      child: Image.memory(
                        _uploadPreviewBytes!,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                      ),
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
          final partner = widget.room.directChatMatrixID;
          return (partner != null && partner.isNotEmpty)
              ? localDisplayName(partner, name)
              : name;
        }
      } catch (_) {}
      return widget.room.id;
    }();
    return Scaffold(
      // 第六十一批（LINE_ref chat 截圖）：深色＝聊天室底 #1A1A1A（與列表 #111111
      // 略不同）；房間自訂背景色／背景圖優先於主題底色。
      backgroundColor: hasImageBg
          ? null
          : (bg ??
              (Theme.of(context).brightness == Brightness.dark
                  ? kLineChatBg
                  : null)),
      appBar: _selectMode
          // 第四十八批：多選模式 → 頂列換成**批次列**（關閉＋已選數＋動作）。
          ? AppBar(
              leading: a11yButton(label: S.t('取消多選'), child: IconButton(
                tooltip: S.t('取消多選'), // 文案草案
                icon: CompoundIcon(
                  CompoundIcons.close,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: _toggleSelectMode,
              )),
              title: Text('${S.t('已選 ')}$_selectedCount${S.t(' 則')}'), // 文案草案
              actions: [
                a11yButton(label: S.t('轉寄'), child: IconButton(
                  tooltip: S.t('轉寄'), // 文案草案
                  onPressed: () => unawaited(_batchForwardSelected()),
                  icon: CompoundIcon(CompoundIcons.forward, size: 24, color: Theme.of(context).colorScheme.onSurface),
                )),
                a11yButton(label: S.t('收回'), child: IconButton(
                  tooltip: S.t('收回'), // 文案草案
                  onPressed: () => unawaited(_batchRedactSelected()),
                  icon: CompoundIcon(CompoundIcons.delete, size: 24, color: Theme.of(context).colorScheme.onSurface),
                )),
              ],
            )
          : AppBar(
        // 第六十一批（LINE_ref chat 截圖）：頂列＝**返回＋房名（含成員數）**，
        // 不放頭像（LINE 構圖）；底色深色＝聊天室底 #1A1A1A（融為一條）。
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? kLineChatBg
            : null,
        // 第七十一批（68b）：頂列自繪 LINE 圖示（返回／搜尋／通話／更多）。
        leading: a11yButton(
          label: S.t('返回'),
          child: IconButton(
            tooltip: S.t('返回'),
            onPressed: () => Navigator.of(context).pop(),
            icon: lineIconWithTestFallback(
              Icons.arrow_back,
              LineIcon.chevronLeft,
              size: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        title: Row(
          children: [
            // 第二十二批（LINE_ref chat 稿）：頂列＝頭像＋房名。
            // 第六十一批改為 LINE 構圖：頭像移除（僅房名＋成員數）。
            // 成員數 (N)：屬「Q1」待人類確認後補（一對一不顯示）。
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
          if (widget.callManager != null)
            // 2026-11-20：電話圖示＋語音／視訊兩選項，一律走 LiveKit
            // （LINE_ref/new_ref/chat/call/ 版位；移除 mesh 與舊 WebRTC 路徑）。
            PopupMenuButton<String>(
                tooltip: S.t('通話'),
                icon: CompoundIcon(CompoundIcons.voiceCall,
                    size: 24, color: Theme.of(context).colorScheme.onSurface),
                onSelected: (value) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LiveKitCallScreen(
                        room: widget.room,
                        manager: widget.callManager!,
                        video: value == 'video',
                      ),
                    ),
                  );
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'audio', child: Text(S.t('語音通話'))),
                  PopupMenuItem(value: 'video', child: Text(S.t('視訊通話'))),
                ],
              ),
          a11yButton(label: S.t('搜尋'), child: IconButton(
            tooltip: S.t('搜尋'),
            onPressed: _openSearch,
            icon: lineIconOverMaterial(
              materialIcon: AllIcons.search,
              lineIcon: LineIcon.search,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          )),
          a11yButton(label: S.t('更多'), child: IconButton(
            tooltip: S.t('更多'),
            onPressed: _openRoomMenu,
            icon: lineIconOverMaterial(
              materialIcon: AllIcons.menu,
              lineIcon: LineIcon.menu,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          )),
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

  /// 第五十七批（效能）：**列計畫**（輕量資料；O(N) 但不建 Widget）。
  ///
  /// 舊實作 `_buildRows()` 在此處**逐則建立 Widget**（含日期分隔 chip），
  /// 再整份塞進 `ListView(children: …)` → **無視覺化**（數百～數千則時＝
  /// 每次 rebuild 產生整棵 Widget 樹 → 主執行緒壅塞／記憶體暴增／被 Android
  /// 判當機；人類 2026-11-16 原話「資料太多就載到超卡」「Android 直接當成
  /// 沒有回應」）。→ 現在：**計畫**在此算，**Widget** 交給 `ListView.builder`
  /// 只在進入可視範圍時才建立。
  ///
  /// 分組規則與舊實作**完全一致**（日期分隔 chip 位置、組頭／組尾、已讀位置）；
  /// 純邏輯已抽到 `chat_row_plan.dart`（可直接單元測試）。
  List<ChatRowPlan> _buildRowPlan(String me, int latestOwnIndex) {
    return buildChatRowPlan(
      messageCount: _messages.length,
      senderOf: (i) => _messages[i].sender,
      dayLabelOf: (i) {
        final at = _messages[i].sentAt;
        return at == null ? null : daySeparatorLabel(at);
      },
      myId: me,
      latestOwnIndex: latestOwnIndex,
    );
  }

  /// 依列計畫建立該列的 Widget（**只有可視範圍內的列會走到這裡**）。
  Widget _buildRowWidget(ChatRowPlan row, String me) {
    if (row.kind == ChatRowKind.daySeparator) {
      return _daySeparatorRow(row.label ?? '');
    }
    final m = _messages[row.messageIndex];
    final own = m.sender == me;
    final showRead = row.isLatestOwn && _isReadByOthers(m);
    final widget = _messageRow(
      m,
      own: own,
      showRead: showRead,
      showSender: row.showSender,
      showTime: row.showTime,
    );
    final eventId = m.eventId;
    if (eventId == null) {
      return widget;
    }
    // 批次十二⑤：訊息列掛 GlobalKey 錨點（橫幅點擊 → 跳轉）。
    // ⚠️ 第五十七批：視覺化後**只有已建構的列**才有 element → 跳轉時若 key
    // 尚未建立，由 `_jumpToPinnedMessage()` 補建（見該處）。
    final key = _rowKeys[eventId] ??= GlobalKey();
    return KeyedSubtree(key: key, child: widget);
  }

  /// 日期分隔膠囊（第四十五批 LINE 版位：圓角 chip、小字）。
  /// 第六十一批（LINE_ref chat 截圖）：深色＝深灰膠囊 #161616＋灰字。
  Widget _daySeparatorRow(String day) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isDark
                ? kLineDateChip
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            day,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark ? kLineTimeText : null,
                ),
          ),
        ),
      ),
    );
  }

  Widget _messageRow(
    ChatMessageView m, {
    required bool own,
    required bool showRead,
    bool showSender = true,
    bool showTime = true,
  }) {
    // 第七十五批（B8）：membership 系統事件＝Element X 式置中細列。
    if (m.isSystemEvent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Center(
          child: Text(
            m.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? kLineTimeText
                      : null,
                ),
          ),
        ),
      );
    }
    final time = m.sentAt == null
        // 第六十七批（人類 2026-11-17 指正）：**佇列（pending）訊息也要顯示
        // 傳送時間**——原第五十六批「傳送完之前先不要顯示」的註解當初寫錯，
        // 作廢。時間＝送出當下（排入佇列）的時間。
        ? ''
        : formatChatTime(m.sentAt!);
    final bubbleColor = own
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    // 批次 E：長按 → 動作選單；左右滑動（速度門檻 500px/s，草案）→ 回覆。
    // 未註冊 onTap → 圖片 tile 既有點擊開預覽不受影響。
    // 第四十一批（LINE 版位）：貼圖與圖片**不帶泡泡底色**（LINE 的貼圖是小尺寸
    // 正方圖、照片是圓角縮圖，皆不滿版）；文字泡泡最大寬度＝視窗寬 × 係數。
    final windowWidth = MediaQuery.sizeOf(context).width;
    // 第一百零九批：收回列一律純文字（不殘留原本的圖片／貼圖版位）；
    // mxc:// 開頭的本文直接當圖片渲染。
    final mxc = m.isRedacted ? null : _mxcFromBody(m.body);
    final imageLoader = mxc != null ? _loadMxcImage : _loadImage;
    final isMedia = !m.isRedacted && (m.isImage || m.isSticker || mxc != null);
    final mediaWidth = isMedia
        ? maxBubbleWidth(windowWidth, kImageBubbleWidthFactor)
        : double.infinity;
    final rawContent = GestureDetector(
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
                        displayWidthDp: stickerDisplaySize(windowWidth),
                        // 無障礙：螢幕閱讀器以 alt text（貼圖 body）朗讀。
                        semanticLabel: S.t('貼圖：') +
                            (m.body.isNotEmpty ? m.body : '未命名貼圖'),
                      ),
                    )
                  : _ChatImageTile(
                      message: m,
                      loadImage: imageLoader,
                      onOpenImage: _openImagePreview,
                      displayWidthDp: mediaWidth,
                      semanticLabel: S.t('圖片：') +
                          (m.body.isNotEmpty ? m.body : '未命名圖片'),
                    ),
            )
          : Stack(
        clipBehavior: Clip.none,
        children: [
          // 2026-11-20：泡泡尾巴已移除（人類指示），保留 Stack 以最小改動。
          Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          // 第四十八批：多選模式下，被選取的訊息加**主色外框**。
          border: _selectMode && _isSelected(m)
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
              : null,
        ),
        // 第六十六批（人類指示）：泡泡文字對比——**亮色泡泡用黑字、暗色
        // 泡泡用白字**（依泡泡底色亮度計算；明亮度 > 0.5＝亮底）。
        // DefaultTextStyle 僅為「未自訂顏色的文字」兜底：本文／回覆引言／
        // chip 等自帶 style 的元素不受影響。
        child: DefaultTextStyle(
          style: (Theme.of(context).textTheme.bodyMedium ??
                  const TextStyle(fontSize: 14))
              .copyWith(
            color: bubbleColor.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white,
          ),
          child: m.isCallInvite
            // 第二十二批（LINE_ref chat calls_history 構圖；Element 稿同構）：
            // 通話事件＝描邊 chip（圖示＋文案）。資料來源同舊版（官方
            // m.call.invite；Suggestion #8 既有語意）。
            ? _callInviteChip(m)
            // 第一百零二批：相簿卡片——點了開啟本機相簿分組。
            : m.isAlbumCard
                ? _ChatAlbumCard(
                    name: m.albumName ?? S.t('相簿'),
                    photoCount: m.albumPhotoIds.length,
                    onTap: () => _openAlbumFromCard(m),
                  )
            // 第四十五批（LINE 版位：mx-reply 引言）：回覆訊息的泡泡頂端顯示
            // 「寄送者＋被回覆內容」的引言方塊（含左側色條），下方才是本文。
            : (!m.hideReplyQuote &&
                    (m.replyToBody != null || m.replyToSender != null))
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReplyQuote(
                        sender: m.replyToSender,
                        body: m.replyToBody,
                        onTap: m.replyToEventId == null
                            ? null
                            : () => _jumpToEventId(m.replyToEventId!),
                      ),
                      const SizedBox(height: 4),
                      m.isPoll && m.event != null
                          ? _ChatPollTile(message: m, timeline: _timeline)
                          : m.isImage
                              ? _ChatImageTile(
                                  message: m,
                                  loadImage: imageLoader,
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
                                      : _isVoiceMessage(m)
                                          ? FutureBuilder<String?>(
                                              future: _loadVoicePath(m),
                                              builder: (context, snap) {
                                                final path = snap.data;
                                                if (path == null) {
                                                  return _ChatFileTile(
                                                    message: m,
                                                    onOpen: () => unawaited(
                                                        _openAttachment(m)),
                                                  );
                                                }
                                                return VoiceMessageTile(
                                                  url: path,
                                                  fileName: m.body,
                                                  enableTranscript: ringVoiceMessageTranscript.value,
                                                  color: bubbleColor.computeLuminance() >
                                                          0.5
                                                      ? Colors.black
                                                      : Colors.white,
                                                );
                                              },
                                            )
                                      : _isAttachment(m)
                                          ? _ChatFileTile(
                                              message: m,
                                              onOpen: () =>
                                                  unawaited(_openAttachment(m)),
                                            )
                                          : _formattedBodyWidget(
                                            m,
                                            textColor:
                                                bubbleColor.computeLuminance() >
                                                        0.5
                                                    ? Colors.black
                                                    : Colors.white,
                                          ),
                    ],
                  )
            : m.isPoll && m.event != null
            ? _ChatPollTile(message: m, timeline: _timeline)
            : m.isImage
                ? _ChatImageTile(
                    message: m,
                    loadImage: imageLoader,
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
                    : _isVoiceMessage(m)
                        ? FutureBuilder<String?>(
                            future: _loadVoicePath(m),
                            builder: (context, snap) {
                              final path = snap.data;
                              if (path == null) {
                                return _ChatFileTile(
                                  message: m,
                                  onOpen: () => unawaited(_openAttachment(m)),
                                );
                              }
                              return VoiceMessageTile(
                                url: path,
                                fileName: m.body,
                                enableTranscript: ringVoiceMessageTranscript.value,
                                color: bubbleColor.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                              );
                            },
                          )
                    : _isAttachment(m)
                        ? _ChatFileTile(
                            message: m,
                            onOpen: () => unawaited(_openAttachment(m)),
                          )
                        // 第三十五批 #14：formatted_body（Element X 式有限
                        // 白名單渲染；解析不適用退回純文字路徑）。
                        : _formattedBodyWidget(
                              m,
                              textColor: bubbleColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            ),
          ),
        ),
        ],
      ),
    );
    // 2026-11-20：泡泡尾巴已移除（人類指示）；直接以 rawContent 作為內容。
    final content = rawContent;
    // 文字泡泡最大寬度（LINE 版位）：自己與他人皆限制，避免長文滿版。
    final textBubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxBubbleWidth(windowWidth, kTextBubbleWidthFactor),
      ),
      child: content,
    );
    final reactions = _reactionsOf(m);
    // 第六十一批（LINE_ref chat 截圖）：時間／已讀／已編輯等小字＝灰
    // #8C8C8C（深色）；淺色走主題預設。
    final metaStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(
          color: Theme.of(context).brightness == Brightness.dark
              ? kLineTimeText
              : null,
        );

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
                  S.t('已讀'), // 文案待定稿；資料來源：SDK 官方 receipts（僅顯示既有資料）
                  style: metaStyle,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (showTime && time.isNotEmpty)
                  Text(time, style: metaStyle),
                // 第五十五批：pending（本機樂觀顯示、尚未送達）→ 標示「傳送中」。
                if (m.pending) ...[
                  const SizedBox(width: 6),
                  Text(S.t('傳送中'), style: metaStyle), // 文案草案
                ],
                const SizedBox(width: 6),
                Flexible(
                  child: m.pending
                      // 第五十五批：半透明＝尚未送達（一眼看出「還在送」）。
                      ? Opacity(
                          opacity: 0.55,
                          child: isMedia ? content : textBubble,
                        )
                      : (isMedia ? content : textBubble),
                ),
              ],
            ),
            // 第二十四批：已編輯記號（僅純文字列；官方 m.replace 聚合）。
            if (m.isEdited && _isPlainTextRow(m)) ...[
              const SizedBox(height: 2),
              Text(S.t('(已編輯)'), style: metaStyle), // 文案草案
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
          // 第一百零九批：收回訊息不畫頭像，但保留 36px 對位空白，
          // 讓泡泡水平位置與同一人的一般訊息對齊（人類「位置要調整」）。
          if (showSender && !m.isRedacted)
            _SenderAvatar(
              label: _senderName(m),
              avatarUri: _senderAvatarUri(m),
              client: widget.room.client,
              onTap: own
                  ? null
                  : () => unawaited(_showSenderInfoSheet(m)),
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSender && !m.isRedacted) ...[
                  Text(
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
                      Text(time, style: metaStyle),
                    ],
                  ],
                ),
                // 第二十四批：已編輯記號（僅純文字列；官方 m.replace 聚合）。
                if (m.isEdited && _isPlainTextRow(m)) ...[
                  const SizedBox(height: 2),
                  Text(S.t('(已編輯)'), style: metaStyle), // 文案草案
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
          CompoundIcon(CompoundIcons.group, size: 16, color: Theme.of(context).colorScheme.outline),
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
  /// 第六十一批（LINE 構圖）：頂列改為僅房名＋成員數（頭像移除）→ 本方法
  /// 暫無使用處；保留供日後頭像回歸（如 room menu 頂部）使用。
  // Uri? _roomAvatarUri() { … }  ← 註解停用（避免 unused_element 告警）。

  /// 批次 E：發送者頭像 Uri。官方資料來源：房間 `m.room.member` state 的
  /// `avatar_url`（SDK `Room.getState`，**純記憶體讀取、無副作用**）。
  /// 不用 `Event.senderFromMemoryOrFallback`：它會 fire-and-forget
  /// `requestUser`（觸碰 DB；注入測試環境未開啟 → 非同步錯誤）。
  /// 無 state／無例外 → null → 頭像磚退回首字圓圈。
  /// 第六十四批③：改以 **senderId** 查（`m.sender` 即 Matrix ID；不依賴
  /// `m.event` → 測試注入訊息也可顯示頭像／資訊 sheet）。
  Uri? _senderAvatarUri(ChatMessageView m) {
    return _senderAvatarUriById(m.sender);
  }

  /// 第六十四批③：以 Matrix ID 查成員頭像（member state；純記憶體）。
  /// **第六十六批**（實機回報「個人頭貼消失」）：SDK 重啟後 partial 房間缺
  /// m.room.member state（同 contacts_screen 第二十六批 join_rules 情形）→
  /// 記憶體查不到 → 頭像磚退回首字圓圈。兜底：查**官方 profile API**
  ///（`Client.getProfileFromUserId`，getFromRooms: false＝homeserver 直查；
  /// 失敗靜默），結果快取 `_avatarFallback` 並 setState 刷新頭像磚。
  /// 測試環境（FLUTTER_TEST）不打網路（與 main_shell 同款 guard）。
  Uri? _senderAvatarUriById(String senderId) {
    Uri? fromMemory;
    try {
      final member = widget.room.getState(EventTypes.RoomMember, senderId);
      final url = member?.content['avatar_url'];
      if (url is String && url.isNotEmpty) {
        fromMemory = Uri.tryParse(url);
      }
    } catch (_) {
      fromMemory = null;
    }
    if (fromMemory != null) {
      return fromMemory;
    }
    if (_avatarFallback.containsKey(senderId)) {
      return _avatarFallback[senderId];
    }
    _scheduleAvatarFallback(senderId);
    return null;
  }

  /// 第六十六批：頭像兜底快取（senderId → Uri／null＝已查過無頭像）。
  final Map<String, Uri?> _avatarFallback = {};
  final Set<String> _avatarFallbackInFlight = {};

  Future<void> _scheduleAvatarFallback(String senderId) async {
    // 測試環境不打網路（main_shell 同款 guard）。
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (_avatarFallbackInFlight.contains(senderId) ||
        _avatarFallback.containsKey(senderId)) {
      return;
    }
    _avatarFallbackInFlight.add(senderId);
    Uri? resolved;
    try {
      final profile = await widget.room.client.getProfileFromUserId(
        senderId,
        timeout: const Duration(seconds: 10),
      );
      final url = profile.avatarUrl;
      resolved = url == null ? null : Uri.tryParse(url.toString());
    } on Object {
      resolved = null; // 失敗靜默（離線／無頭像）；頭像磚維持首字圓圈。
    }
    _avatarFallbackInFlight.remove(senderId);
    if (!mounted || _avatarFallback.containsKey(senderId)) {
      return;
    }
    setState(() => _avatarFallback[senderId] = resolved);
  }

  /// 第六十四批③（人類：「聊天室點他人頭像可顯示對方資訊」）：他人頭像
  /// 點擊 → 成員資訊 bottom sheet（**草案，待人類設計定稿**）。內容最小集：
  /// 頭像／顯示名稱／Matrix ID。資料＝房間 `m.room.member` state（官方，
  /// 純記憶體）；缺顯示名時 best-effort `getProfileFromUserId` 補（失敗靜默）。
  Future<void> _showSenderInfoSheet(ChatMessageView m) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _SenderInfoSheet(
        room: widget.room,
        senderId: m.sender,
        displayName: _senderName(m),
        avatarUri: _senderAvatarUri(m),
      ),
    );
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
          SnackBar(content: Text('${S.t('反應失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 第一百零八批：選擇更多 emoji 或輸入自訂文字 reaction。
  /// SDK 官方 `sendReaction` 本就接受任意字串 key（含文字），此處只提供 UI。
  Future<void> _askCustomReaction(
    ChatMessageView m, {
    required bool emojiOnly,
  }) async {
    if (!mounted) return;
    final controller = TextEditingController();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(emojiOnly ? S.t('更多 emoji') : S.t('文字 reaction')),
        content: emojiOnly
            ? SizedBox(
                width: 280,
                child: Wrap(
                  children: [
                    for (final emoji in kRingCommonEmoji)
                      IconButton(
                        tooltip: emoji,
                        onPressed: () => Navigator.pop(ctx, emoji),
                        icon: Text(emoji),
                      ),
                  ],
                ),
              )
            : TextField(
                controller: controller,
                autofocus: true,
                maxLength: 32,
                decoration: InputDecoration(labelText: S.t('reaction 文字')),
              ),
        actions: [
          if (!emojiOnly)
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(S.t('確定')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (chosen != null && chosen.isNotEmpty && mounted) {
      unawaited(_toggleReaction(m, chosen));
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
  Widget _formattedBodyWidget(
    ChatMessageView m, {
    required Color textColor,
  }) {
    final content = m.event?.content;
    final formattedBody = content?['formatted_body'];
    // 2026-11-20：只有帶 Homing 渲染要求旗標的訊息才用 Markdown 渲染；
    // 沒有旗標（含舊訊息、其他客戶端）一律純文字。
    if (content?[kMarkdownRenderFlag] != true ||
        content?['format'] != 'org.matrix.custom.html' ||
        formattedBody is! String ||
        formattedBody.isEmpty) {
      return _linkifiedBody(m.body);
    }
    try {
      final theme = Theme.of(context);
      // 第七十一批：formatted_body（Markdown/HTML 渲染）的文字與連結色必須
      // 跟泡泡亮度——亮底黑字、暗底白字（第六十六批規則）；原本只設在
      // DefaultTextStyle，但 formattedMessageWidget 用顯式 baseStyle 覆蓋 →
      // 白色刪除線出現在亮綠泡泡上（對比不足）。
      // 第七十二批：連 decorationColor 一起覆寫——深色主題的 textTheme 由
      // Material Typography 帶入 decorationColor＝白（只改 color 的話，
      // 刪除線／底線仍是白，亮綠泡泡上幾乎看不見）。
      final base = (theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14))
          .copyWith(color: textColor, decorationColor: textColor);
      final w = formattedMessageWidget(
        formattedBody,
        baseStyle: base,
        linkStyle: TextStyle(
          color: textColor,
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
    // 第一百零八批：與單則收回一致——移除三選項，直接確認（一般收回）。
    // 第八十六批：收回前再次確認（不可復原）。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.t('確定收回')} ${selected.length} ${S.t('則')}？'),
        content: Text(S.t('收回後無法復原；無痕收回只對 Homing 使用者生效。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('確定收回')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final m in selected) {
      final event = m.event;
      if (event == null) {
        continue;
      }
      try {
        // 第八十六批：統一用官方 redactEventWithMetadata（與單則一致）。
        await widget.room.client.redactEventWithMetadata(
          widget.room.id,
          event.eventId,
          widget.room.client.generateUniqueTransactionId(),
          metadata: const <String, Object?>{},
        );
      } catch (_) {
        // 單則失敗靜默（收回前已再次確認，不再事後提示）。
      }
    }
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selectedEventIds.clear();
      _selectedWithoutId.clear();
    });
    unawaited(_load());
    // 2026-11-20：收回前有再次確認對話框，不再於事後彈「已收回 N 則」提示。
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
        SnackBar(content: Text(S.t('選取的訊息沒有可轉寄的文字'))), // 文案草案
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
            // 第七十一批（A2-4 人類「是」）：加大觸控目標（上下 padding 8）。
            onTap: () => unawaited(_toggleReaction(m, entry.key)),
            child: Semantics(
              button: true,
              label: S.t('表情反應：') +
                  (_mxcFromBody(entry.key) != null ? S.t('貼圖') : entry.key),
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    // 第一百一十批：別的 client 用自訂貼圖當 reaction key（mxc://）
                    // → 直接渲染小圖，不要印出原始 URI。
                    if (_mxcFromBody(entry.key) != null)
                      FutureBuilder<MatrixFile?>(
                        future: _loadReactionImage(entry.key),
                        builder: (ctx, snap) {
                          final file = snap.data;
                          if (file == null) {
                            return const SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(Icons.emoji_emotions_outlined, size: 20),
                            );
                          }
                          return Image.memory(
                            file.bytes,
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.emoji_emotions_outlined,
                              size: 20,
                            ),
                          );
                        },
                      )
                    else
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
          ),
      ],
    );
  }

  /// 批次 E：長按訊息 → 動作選單（草案；全 UI 文案待人類設計定稿）。
  /// 表情反應（預設 6 emoji 列）／回覆／複製文字／檢舉／分享至外部。
  /// 條件：無 event（注入測試環境）→ 無反應列；圖片／投票 → 無複製與分享
  /// （圖片分享在預覽畫面已有；投票 body 為協定 fallback 文字、無意義）；
  /// 本人訊息 → 無檢舉。
  /// 第八十九批：LINE 式動作格（深色圓角卡＋圖示＋標籤）。
  Widget _actionCell(
    BuildContext ctx, {
    required String label,
    required Widget icon,
    required String action,
  }) {
    return SizedBox(
      width: 80,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(ctx).pop(action),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(ctx).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                        // 第一百零八批：全部常用 emoji（kRingCommonEmoji）可選。
                        for (final emoji in kRingCommonEmoji.take(24))
                          TextButton(
                            onPressed: () => Navigator.of(context).pop('react:$emoji'),
                            child: Text(emoji),
                          ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop('react_more'),
                          child: Text(S.t('更多 emoji')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop('react_custom'),
                          child: Text(S.t('文字 reaction')),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
              // 第八十九批：LINE 式動作網格（深色圓角卡 4 欄）。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _actionCell(context, label: S.t('回覆'), icon: CompoundIcon(CompoundIcons.reply, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'reply'),
                    _actionCell(context, label: S.t('多選'), icon: CompoundIcon(CompoundIcons.check, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'multiselect'),
                    // 第一百零二批：圖片可加入本機相簿 → 建立分組 → 送卡片。
                    if (m.isImage)
                      _actionCell(context, label: S.t('加入相簿'), icon: CompoundIcon(CompoundIcons.image, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'add_to_album'),
                    // 2026-11-20：回覆引言可本機隱藏／顯示（點引言亦可跳原訊息）。
                    if (m.replyToEventId != null)
                      _actionCell(
                        context,
                        label: m.hideReplyQuote
                            ? S.t('顯示回覆引言')
                            : S.t('隱藏回覆引言'),
                        icon: CompoundIcon(CompoundIcons.reply,
                            size: 26,
                            color: Theme.of(context).colorScheme.onSurface),
                        action: 'toggle_reply_quote',
                      ),
                    if (own && hasEvent && !(m.event?.redacted ?? false) && m.event?.messageType == 'm.text')
                      _actionCell(context, label: S.t('編輯'), icon: CompoundIcon(CompoundIcons.edit, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'edit'),
                    if (own && hasEvent && !(m.event?.redacted ?? false)) ...[
                      _actionCell(context, label: S.t('收回'), icon: CompoundIcon(CompoundIcons.delete, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'redact'),
                      _actionCell(context, label: S.t('無痕收回'), icon: CompoundIcon(CompoundIcons.visibilityOff, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'stealth_redact'),
                    ],
                    if (!m.isImage && !m.isPoll)
                      _actionCell(context, label: S.t('複製文字'), icon: CompoundIcon(CompoundIcons.copy, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'copy'),
                    // 第一百零八批：選取訊息文字（對話框內 SelectableText）。
                    _actionCell(context, label: S.t('選取文字'), icon: CompoundIcon(CompoundIcons.edit, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'select_text'),
                    if (!own)
                      _actionCell(context, label: S.t('檢舉'), icon: CompoundIcon(CompoundIcons.error, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'report'),
                    if (!m.isImage && !m.isPoll && !m.isSticker)
                      _actionCell(context, label: S.t('分享至外部'), icon: CompoundIcon(CompoundIcons.share, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'share'),
                    if (hasEvent)
                      _actionCell(context, label: S.t('查看原始訊息'), icon: CompoundIcon(CompoundIcons.info, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'raw'),
                    // 第一百零八批：展開訊息選單底部放「取消釘選」（僅釘選的訊息）。
                    if (m.eventId != null && m.eventId == _pinnedBannerEventId)
                      _actionCell(context, label: S.t('取消釘選'), icon: CompoundIcon(CompoundIcons.close, size: 26, color: Theme.of(context).colorScheme.onSurface), action: 'unpin'),
                  ],
                ),
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
    if (action == 'react_more' || action == 'react_custom') {
      unawaited(_askCustomReaction(
        m,
        emojiOnly: action == 'react_more',
      ));
      return;
    }
    switch (action) {
      case 'select_text':
        _showSelectableText(m);
        break;
      case 'unpin':
        unawaited(_unpinPinnedMessage());
        break;
      case 'add_to_album':
        unawaited(_addImageToAlbum(m));
        break;
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
      case 'toggle_reply_quote':
        final id = m.replyToEventId;
        if (id != null) {
          setState(() {
            if (_hiddenReplyIds.contains(id)) {
              _hiddenReplyIds.remove(id);
            } else {
              _hiddenReplyIds.add(id);
            }
          });
          _messageViewCache.clear(); // 讓該則重新以新旗標建立 view
          unawaited(_load());
        }
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
      case 'stealth_redact':
        unawaited(_redactMessage(m, stealth: true));
      case 'cancel':
        break; // 取消＝不做任何事
      case 'copy':
        unawaited(Clipboard.setData(ClipboardData(text: m.body)));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('已複製'))), // 文案草案
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
        title: Text(S.t('原始訊息')), // 文案草案
        content: SingleChildScrollView(
          child: SelectableText(raw),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.t('關閉')), // 文案草案
          ),
        ],
      ),
    );
  }

  /// 第一百零八批：長按「選取文字」→ 對話框內可選取／複製本文。
  /// 不把泡泡改成 SelectableText，避免吃掉長按動作選單手勢。
  void _showSelectableText(ChatMessageView m) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('選取文字')),
        content: SingleChildScrollView(
          child: SelectableText(m.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.t('關閉')),
          ),
        ],
      ),
    );
  }

  /// 批次 III-a：收回訊息（官方 `Room.redactEvent`；無自製協定邏輯）。
  /// 收回後由 SDK 官方 redaction 機制標記事件；本畫面重撈會顯示『[已收回]』。
  /// 第八十五批合併：無痕收回以 Compound 版的官方 redactEventWithMetadata
  /// （kHomingStealthKey）為準；接收端同時辨識舊 Homing reason 旗標（2b 相容）。
  Future<void> _redactMessage(ChatMessageView m, {bool stealth = false}) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    // 2026-11-20：收回（含無痕）一律再次確認，不再按了就執行／事後提示。
    final bool useSilent;
    if (stealth) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.t('確定無痕收回？')),
          content: Text(S.t('收回後無法復原；無痕收回只對 Homing 使用者生效。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t('確定收回')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      useSilent = true;
    } else {
      // 第一百零八批（人類指示）：移除「三選項」對話框，直接確認。
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.t('確定收回此訊息？')),
          content: Text(S.t('收回後無法復原；所有人都能看見收回狀態。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t('確定收回')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      useSilent = false;
    }
    try {
      if (useSilent) {
        // 第八十五批：官方 redactEventWithMetadata＋metadata（Compound 版做法）。
        await widget.room.client.redactEventWithMetadata(
          widget.room.id,
          event.eventId,
          widget.room.client.generateUniqueTransactionId(),
          metadata: const {kHomingStealthKey: true},
        );
      } else {
        await widget.room.redactEvent(event.eventId);
      }
      if (mounted) {
        unawaited(_load());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('收回失敗：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('分享失敗：')}$e')), // 文案草案
        );
      }
    }
  }

  /// 第 19 點：分享檔案（圖片／貼圖／附件）而非只傳送標題。
  /// 下載解密後暫存到系統臨時目錄，再經 share_plus 分享給外部 App。
  ///
  /// ⚠️ **第五十四批（2026-11-16）**：貼圖（`m.sticker`）**拒絕分享**
  /// （著作權：貼圖包自帶授權，不應被匯出到 App 之外）。長按選單已不顯示
  /// 「分享至外部」；此處再加一道防線（防未來新增的呼叫端繞過選單）。
  Future<void> _shareAttachment(ChatMessageView m) async {
    final event = m.event;
    if (event == null) {
      return;
    }
    if (m.isSticker) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('貼圖不提供分享'))), // 文案草案
        );
      }
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
          SnackBar(content: Text('${S.t('分享檔案失敗：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('開啟失敗：')}$e')), // 文案草案
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
          CompoundIcon(CompoundIcons.reply, size: 18, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${reply.sender}：${reply.isPoll ? '[投票]' : reply.body}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          a11yButton(label: S.t('解除回覆'), child: IconButton(
            tooltip: S.t('解除回覆'), // 文案草案
            onPressed: () => setState(() => _replyTo = null),
            icon: CompoundIcon(CompoundIcons.close, size: 24, color: Theme.of(context).colorScheme.onSurface),
          )),
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
          CompoundIcon(CompoundIcons.edit, size: 18, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '編輯訊息：${target.body.isEmpty ? '(無文字)' : target.body}', // 文案草案
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          a11yButton(label: S.t('解除編輯'), child: IconButton(
            tooltip: S.t('解除編輯'), // 文案草案
            onPressed: () async {
              setState(() => _editTarget = null);
              _inputController.clear();
              await _stopTyping();
            },
            icon: CompoundIcon(CompoundIcons.close, size: 24, color: Theme.of(context).colorScheme.onSurface),
          )),
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
      _activeSends++; // 第六十七批：計數制（編輯同計）。
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
        _activeSends = (_activeSends - 1).clamp(0, 1 << 30);
        _message = error;
        _editTarget = error == null ? null : _editTarget;
      });
    }
    if (error == null) {
      // 第五十六批：編輯成功 → **立即**套用（樂觀更新）。
      //
      // ⚠️ **順序很重要**：`_load()` 必須在同步**之前**。
      // 舊序（先 `await client.oneShotSync()` 再 `_load()`）會被 SDK 的長輪詢
      // 阻塞（可能數十秒）→ 畫面看起來「編輯完沒動」＝人類回報的現象。
      // 現在：先記入本機對照 → **立即**重載（畫面馬上變）→ 與伺服器的確認
      // 放到**背景**（不阻塞畫面）。
      unawaited(_stopTyping());
      _localEdits[eventId] = text;
      _localEditsVersion++; // 第六十九批：使整窗 cache 失效（編輯內容已變）。
      unawaited(_persistLocalEdits());
      // 注入 SDK 聚合樹 → 官方 getDisplayEvent 套用 → 泡泡與房間列表預覽一致。
      _injectLocalEditIntoTimeline(eventId, text);
      unawaited(_load());
      // 以官方 /relations 原始 API 確認伺服器端的編輯內容（SDK 的 relations
      // 快取抓不到「後續編輯」）；背景執行，不阻塞畫面。
      unawaited(_refreshLocalEditFromServer(widget.room, eventId));
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

  /// 2026-11-20：Markdown 為「本則訊息開關」——只影響目前正在打這則是否帶
  /// formatted_body；不寫 kv，送出成功／預約後自動復位。
  void _toggleMarkdown() {
    setState(() => _markdownOn = !_markdownOn);
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
            SnackBar(
              content: Text(S.t('貼圖僅支援圖片（含動圖 GIF／WebP），不支援影片或聲音')), // 文案草案
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
          SnackBar(content: Text('${S.t('貼圖傳送失敗：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('無法開啟地圖：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('位置分享失敗：')}$e')), // 文案草案
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
      !m.isAlbumCard && // 第一百零二批：相簿卡片不套用文字編輯記號
      !_isAttachment(m);

  bool _isAttachment(ChatMessageView m) {    final t = m.event?.messageType;
    return t == 'm.file' || t == 'm.video' || t == 'm.audio';
  }

  /// 第七十批 d：是否語音訊息（m.audio）。
  bool _isVoiceMessage(ChatMessageView m) =>
      m.event?.type == EventTypes.Message && m.event?.messageType == 'm.audio';

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
        // 第五十七批：先查本機媒體快取（離線可讀・方案 A）。
        return await loadMediaFileWithCache(event);
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
  /// 第七十批 d：語音訊息解密並存本機暫存（E2EE 檔走官方
  /// downloadAndDecryptAttachment；不寫任何加密邏輯）。回傳本機 path 供播放。
  final Map<String, Future<String?>> _voicePaths = {};

  Future<String?> _loadVoicePath(ChatMessageView m) {
    final id = m.eventId ?? '';
    if (id.isEmpty) return Future.value(null);
    return _voicePaths[id] ??= () async {
      final event = m.event;
      if (event == null) return null;
      try {
        final matrixFile = await event.downloadAndDecryptAttachment();
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/voice_play_$id.m4a';
        final f = File(path);
        if (!await f.exists()) await f.writeAsBytes(matrixFile.bytes);
        return path;
      } catch (_) {
        return null;
      }
    }();
  }

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
                Text(S.t('下載中…')), // 文案草案
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
                child: Text(S.t('取消')), // 文案草案
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
          SnackBar(content: Text('${S.t('無法開啟檔案：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('開啟失敗：')}$e')), // 文案草案
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
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CompoundIcon(CompoundIcons.visibilityOn, size: 18, color: Theme.of(context).colorScheme.onSurface),
              SizedBox(width: 8),
              Expanded(child: Text(S.t('此聊天室僅供讀取（沒有發送權限）'))), // 文案待定稿
            ],
          ),
        ),
      );
    }
    // 第一百零一批（人類定稿）：左側只有一個「+」，點它彈出小型文字選單。
    // 不再是整列攤開的面板；所有功能入口都在選單內，預約仍在送出鍵旁邊。
    final leading = <Widget>[
      a11yButton(
        label: S.t('展開輸入列'),
        child: PopupMenuButton<String>(
          tooltip: S.t('展開輸入列'),
          icon: CompoundIcon(CompoundIcons.plus, size: 24,
              color: Theme.of(context).colorScheme.onSurface),
          padding: EdgeInsets.zero,
          itemBuilder: (_) => _quickMenuItems(),
          onSelected: _onQuickMenuSelected,
        ),
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
              // 第一百批：左側只有「+／×」；無聲／Markdown 移入「+」選單，
              // 預約仍在送出鍵旁邊（人類指示），全部原功能保留。
              Row(mainAxisSize: MainAxisSize.min, children: leading),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  // 第一百零八批（人類指示）：輸入列可換行；送出只由右側送出鈕觸發。
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  // 第九十八批：移除「點輸入框自動展開」——避免與附件列互相干擾。
                  // 第六十七批：佇列中**不禁用**（人類指示「排隊時要能打字並
                  // 按傳送進佇列」）；原 `enabled: !_sending` 作廢。
                  onChanged: (_) {
                    // 第九十五批：不在此 setState（避免打字時重建整個輸入列
                    // 影響 IME／游標）。左側按鈕與右側動作改用
                    // ValueListenableBuilder(_inputController) 跟隨文字變化。
                    unawaited(_maybeSendTyping());
                    // 貼圖關鍵字聯想（backlog #8）：依目前輸入建議貼圖。
                    unawaited(_updateStickerSuggestions());
                  },
                  // 換行模式下不再由 onSubmitted 送出（避免 Enter 誤送）。
                  decoration: InputDecoration(
                    hintText: S.t('Message'),
                    isDense: true,
                    filled: true,
                    // 第六十一批（LINE_ref chat 截圖）：深色＝輸入框 pill
                    // #2A2A2A（＝對方氣泡同色）；淺色走主題預設。
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? kLineBubbleIncoming
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: a11yButton(label: _emojiOpen ? '收起表情面板' : '表情', child: IconButton(
                      tooltip: _emojiOpen ? '收起表情面板' : '表情',
                      onPressed: _toggleEmojiPanel,
                      icon: lineIconOverMaterial(
                        materialIcon: AllIcons.emojiEmotionsOutlined,
                        lineIcon: LineIcon.emoji,
                        color: _emojiOpen
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    )),
                  ),
                ),
              ),
              // 第九十五批：右側動作隨文字變化（ValueListenableBuilder，
              // 不重建 TextField）；打字時展開「預約＋送出」，清空還原 mic。
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _inputController,
                builder: (context, value, _) {
                  final has = value.text.trim().isNotEmpty;
                  if (!has) {
                    return a11yButton(label: S.t('語音訊息'), child: IconButton(
                      tooltip: S.t('語音訊息'),
                      onPressed: () => unawaited(showVoiceRecorderSheet(
                        context,
                        onSend: _sendVoiceFromFile,
                      )),
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(opacity: 0, child: Icon(AllIcons.micNone, size: 24)),
                          CompoundIcon(
                            CompoundIcons.micOn,
                            size: 24,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ],
                      ),
                    ));
                  }
                  // 第一百批（人類確認）：沒打字＝mic；有打字＝送出，
                  // 且送出旁邊保留預約鍵（原功能不變，只精簡左側開關）。
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      a11yButton(label: S.t('預約送出'), child: IconButton(
                        tooltip: S.t('預約送出'),
                        onPressed: () => unawaited(_scheduleDraft()),
                        icon: lineIconOverMaterial(materialIcon: Icons.schedule, lineIcon: LineIcon.clock, color: Theme.of(context).colorScheme.onSurface),
                      )),
                      a11yButton(label: S.t('送出'), child: SizedBox(
                        width: 40,
                        height: 40,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => unawaited(_onSend()),
                          child: const Icon(Icons.send, size: 20),
                        ),
                      )),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 第五十四批（2026-11-16）：把**收回**（`m.room.redaction`）套用到記憶體中的
/// 事件物件，讓聊天室**即時**顯示「[已收回]」（不必重開 App）。
///
/// 背景（人類回報 2026-11-16：「對方收回訊息，本機要重開才會更新」）：
/// 官方 SDK 只對 `room.lastEvent` 做 `Event.setRedactionEvent`（matrix
/// client.dart L3188）；**其餘**事件的收回狀態只存在 DB 裡，而本專案
/// `_defaultLoadMessages` 會**重用同一 Timeline 實例**（避免丟掉 requestHistory
/// 抓到的歷史窗口）→ 記憶體中的舊事件物件永遠不會被標記 → 畫面不更新。
///
/// 本函式就地套用（與官方 SDK 對 lastEvent 的同一手法），**不重建 Timeline**。
///
/// 回傳 `true`＝有事件被標記為已收回（呼叫端應重載畫面）；`false`＝本 chunk
/// 內找不到目標（更舊的訊息捲動重新載入時會由伺服器回傳已收回版本）。
///
/// 純函式（不碰 UI／DB）→ 可單元測試。
bool applyRedactionToEvents(List<Event> events, Event redaction) {
  final target = redaction.content.tryGet<String>('redacts');
  if (target == null || target.isEmpty) {
    return false;
  }
  for (final e in events) {
    if (e.eventId == target) {
      e.setRedactionEvent(redaction);
      return true;
    }
  }
  return false;
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
  const _ReplyQuote({this.sender, this.body, this.onTap});

  final String? sender;
  final String? body;

  /// 2026-11-20：點引言跳回原訊息（無 event id＝不可點）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                  ?.copyWith(
                    color: DefaultTextStyle.of(context).style.color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          if (body != null && body!.isNotEmpty)
            Text(
              body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: DefaultTextStyle.of(context).style.color),
            ),
        ],
      ),
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({
    required this.label,
    required this.client,
    this.avatarUri,
    // 第六十四批③：他人頭像 tap → 成員資訊 sheet；null＝不可點。
    this.onTap,
  });

  final String label;
  final Client client;

  /// 已由呼叫端 try/catch 提取的頭像 Uri（可能為 null）。
  final Uri? avatarUri;

  /// 第六十四批③：點擊動作（他人頭像 → 資訊 sheet）；null＝不可點。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = label.runes.isEmpty
        ? '?'
        : String.fromCharCode(label.runes.first);
    Widget avatar;
    if (avatarUri == null) {
      avatar = CircleAvatar(child: Text(text));
    } else {
      avatar = FutureBuilder<(Uri, bool)>(
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
    if (onTap == null) {
      return avatar;
    }
    // 第六十四批③：可點頭像包 tooltip（a11y＋測試定位沿用 byTooltip 模式）。
    return Tooltip(
      message: S.t('顯示成員資訊'), // 文案草案
      child: GestureDetector(onTap: onTap, child: avatar),
    );
  }
}

/// 第六十四批③（人類：「聊天室點他人頭像可顯示對方資訊」）：成員資訊
/// bottom sheet（**草案 UI，待人類設計定稿**）。最小資訊集：
/// 頭像／顯示名稱／Matrix ID（可選取複製）。
///
/// 資料來源：房間 `m.room.member` state（官方；由呼叫端帶入）。
/// 顯示名缺漏時 best-effort `getProfileFromUserId`（官方 API；失敗靜默——
/// 離線／跨 home server 慢皆不阻塞 sheet 開啟）。
class _SenderInfoSheet extends StatefulWidget {
  const _SenderInfoSheet({
    required this.room,
    required this.senderId,
    required this.displayName,
    this.avatarUri,
  });

  final Room room;
  final String senderId;
  final String displayName;
  final Uri? avatarUri;

  @override
  State<_SenderInfoSheet> createState() => _SenderInfoSheetState();
}

class _SenderInfoSheetState extends State<_SenderInfoSheet> {
  String _displayName = '';
  Uri? _avatarUri;

  /// 已嘗試 best-effort profile 補抓（每個 sheet 一次）。
  bool _profileAsked = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
    _avatarUri = widget.avatarUri;
    // member state 缺顯示名／頭像 → best-effort 補（非同步、失敗靜默）。
    if (_displayName == widget.senderId || _avatarUri == null) {
      unawaited(_loadProfile());
    }
  }

  Future<void> _loadProfile() async {
    if (_profileAsked) return;
    _profileAsked = true;
    Profile? profile;
    try {
      // 官方 API（blocked_users_screen 同款；逾時 10s 不阻塞 sheet）。
      profile = await widget.room.client
          .getProfileFromUserId(widget.senderId, timeout: const Duration(seconds: 10));
    } catch (_) {
      return; // 離線／查無 → 維持現有顯示（不阻塞）。
    }
    if (!mounted) return;
    final newName = profile.displayName;
    final newAvatar = profile.avatarUrl;
    if ((newName == null || newName.isEmpty) && newAvatar == null) return;
    setState(() {
      if (_displayName == widget.senderId &&
          newName != null &&
          newName.isNotEmpty) {
        _displayName = newName;
      }
      _avatarUri ??= newAvatar;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _displayName.runes.isEmpty
        ? '?'
        : String.fromCharCode(_displayName.runes.first);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 大頭像（與訊息列同一官方縮圖路徑；僅尺寸不同——草案）。
                FutureBuilder<(Uri, bool)>(
                  future: () async {
                    final uri = _avatarUri;
                    if (uri == null) return (Uri(), false);
                    final thumb =
                        await uri.getThumbnailUri(widget.room.client, width: 128, height: 128);
                    final auth =
                        await widget.room.client.authenticatedMediaSupported();
                    return (thumb, auth);
                  }(),
                  builder: (context, snap) {
                    ImageProvider? provider;
                    if (snap.hasData && _avatarUri != null) {
                      final (uri, auth) = snap.data!;
                      provider = NetworkImage(
                        uri.toString(),
                        headers: auth
                            ? <String, String>{
                                'authorization':
                                    'Bearer ${widget.room.client.accessToken}',
                              }
                            : null,
                      );
                    }
                    return CircleAvatar(
                      radius: 40,
                      backgroundImage: provider,
                      child: provider == null ? Text(text) : null,
                    );
                  },
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      // Matrix ID（可選取複製；會議室成員本可見的資訊）。
                      SelectableText(
                        widget.senderId,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 圖片訊息磚（骨架，無樣式／不寫死寬度，版面待人類設計定稿）。
/// 批次 D：投票卡片（草案；待人類設計定稿）。
/// 採 SDK 官方 msc_3381_polls extension：`parsedPollEventContent`（問題/選項）、
/// `getPollResponses(timeline)`（票數）、`answerPoll`（投票）、`endPoll`（結束）。
/// 零加密邏輯（事件由房間加密機制處理）。
/// 第一百零二批：相簿卡片（草案，最小樣式；最終視覺待人類定稿）。
/// 點了由 ChatScreen 的 `_openAlbumFromCard` 開啟本機相簿分組。
class _ChatAlbumCard extends StatelessWidget {
  const _ChatAlbumCard({
    required this.name,
    required this.photoCount,
    required this.onTap,
  });

  final String name;
  final int photoCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_album_outlined, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$photoCount ${S.t('張照片')}・${S.t('開啟相簿')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
          SnackBar(content: Text('${S.t('無法投票：')}$e')), // 文案草案
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
          SnackBar(content: Text('${S.t('無法結束投票：')}$e')), // 文案草案
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
            child: Text(S.t('結束投票')), // 文案草案
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
        ? CompoundIcons.files
        : type == 'm.audio'
            ? CompoundIcons.reaction
            : CompoundIcons.document;
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
      child: Semantics(
        button: true,
        label: S.t('檔案：') + (message.body.isNotEmpty ? message.body : S.t('未命名檔案')),
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompoundIcon(icon,
              size: 24, color: Theme.of(context).colorScheme.onSurface),
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
    this.displayWidthDp,
  });

  final ChatMessageView message;
  final Future<MatrixFile?> Function(ChatMessageView) loadImage;
  final void Function(ChatMessageView, Uint8List? bytes) onOpenImage;

  /// 無障礙標籤（螢幕閱讀器朗讀用；空白＝沿用內容推導）。
  final String? semanticLabel;

  /// 第六十四批⑤（卡頓巡查）：顯示寬度上限（dp）。提供時 `Image.memory`
  /// 以 `cacheWidth` 限制**解碼解析度**（顯示寬 × devicePixelRatio）——
  /// 貼圖＝原始尺寸（批次 III-a），大圖若全解析度解碼（如 2000×2000，
  /// 點陣約 16MB）會拖慢捲動與快取命中。顯示寬度不超過此上限 → 品質不變。
  final double? displayWidthDp;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MatrixFile?>(
      future: loadImage(message),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(S.t('[圖片：載入中…]'));
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
            // 第六十四批⑤（卡頓巡查）：限制解碼寬度（見 displayWidthDp 註解）。
            // 注意：貼圖點開預覽走 `onOpenImage`（拿到的是原始 bytes），
            // 預覽畫面另開全解析度，不受此限制。
            child: ValueListenableBuilder<bool>(
              valueListenable: ringStaticStickers,
              builder: (context, staticFrame, _) {
                // 第七十三批（GIF 開關）：僅貼圖受影響，且需使用者主動開啟。
                if (message.isSticker && staticFrame) {
                  return StaticImage(bytes: file.bytes);
                }
                return Image.memory(
                  file.bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                  cacheWidth: displayWidthDp == null
                      ? null
                      : (displayWidthDp! *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                );
              },
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
      child: Semantics(
        button: true,
        label: S.t('位置分享（點按開啟地圖）'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CompoundIcon(CompoundIcons.locationPin, size: 24, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.body.isNotEmpty ? message.body : '位置'), // 文案草案
                Text(S.t('點擊開啟地圖'), // 文案草案
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
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
      title: Text(S.t('選擇位置')), // 文案草案
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
                  child: CompoundIcon(
                    CompoundIcons.locationPin,
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
          child: Text(S.t('取消')), // 文案草案
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_point.latitude, _point.longitude)),
          child: Text(S.t('送出')), // 文案草案
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
                    // 第六十四批⑤（卡頓巡查）：56dp 縮圖限解碼寬度。
                    cacheWidth: (56 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    semanticLabel: label,
                    errorBuilder: (_, _, _) => CompoundIcon(
                      CompoundIcons.image,
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

/// 第一百批：Markdown Mark（M↓）圖示。
///
/// 樣式來源（人類要求「查 Markdown 圖樣」）：Dustin Curtis 的
/// `markdown-mark`（github.com/dcurtis/markdown-mark），public domain；
/// CommonMark 官網亦以其標示 Markdown 支援。官方規格：圓角方框內含
/// 「M」與向下箭頭，三元素同色、維持比例。
/// 以 CustomPainter 自繪——**零新依賴**（AGENTS.md 必停區不踩）。
class MarkdownMarkIcon extends StatelessWidget {
  const MarkdownMarkIcon({
    super.key,
    required this.color,
    this.size = 22,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkdownMarkPainter(color: color)),
    );
  }
}

class _MarkdownMarkPainter extends CustomPainter {
  _MarkdownMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 外框（圓角方框）。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.18),
      ),
      stroke,
    );

    // M：兩條豎線 + 中間 V（Gill Sans Bold 風格的粗 M）。
    final left = size.width * 0.20;
    final right = size.width * 0.47;
    final top = size.height * 0.27;
    final bottom = size.height * 0.73;
    final mid = size.height * 0.52;
    canvas.drawLine(Offset(left, bottom), Offset(left, top), stroke);
    canvas.drawLine(Offset(left, top), Offset((left + right) / 2, mid), stroke);
    canvas.drawLine(Offset((left + right) / 2, mid), Offset(right, top), stroke);
    canvas.drawLine(Offset(right, top), Offset(right, bottom), stroke);

    // 向下箭頭（右）。
    final ax = size.width * 0.72;
    final ay1 = size.height * 0.32;
    final ay2 = size.height * 0.70;
    final head = size.height * 0.13;
    final wing = size.width * 0.12;
    canvas.drawLine(Offset(ax, ay1), Offset(ax, ay2), stroke);
    canvas.drawLine(Offset(ax - wing, ay2 - head), Offset(ax, ay2), stroke);
    canvas.drawLine(Offset(ax + wing, ay2 - head), Offset(ax, ay2), stroke);
  }

  @override
  bool shouldRepaint(covariant _MarkdownMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

