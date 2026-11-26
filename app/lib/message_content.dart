// 第三十五批（人類需求 #5「無聲傳送」）：訊息內容組裝與無聲旗標判讀。
//
// Matrix 規格**沒有**官方「無聲／不通知」機制（查證：預設 push rule 依
// msgtype 觸發，無排除欄位）——本檔採 **App 層約定**：m.room.message 的
// content 自由欄位 `dev.homing.silent: true`（規格容忍未知欄位，Element 等
// 其他客戶端會忽略不顯示）。
//
// **披露（已知限制）**：靜音效果僅 **Homing 端**生效（Homing 收訊端在
// 通知路徑跳過該房間輪次）；對端若用 Element 等其他客戶端，仍會照常通知。
// 加密房若 lastEvent 尚未解密（content＝m.encrypted），旗標讀不到＝
// fail-open 照常通知。
import 'package:matrix/matrix.dart';

/// 無聲訊息旗標（App 層約定；勿隨意改名——發送端與通知端共用同一常數）。
const String kSilentMessageFlag = 'dev.homing.silent';

/// 2026-11-20：Markdown 渲染要求（App 層約定）。只有帶此旗標的訊息才用
/// `formatted_body` 渲染 Markdown；沒有旗標（含舊訊息與其他客戶端）一律純文字。
/// 其他客戶端會忽略未知欄位（Matrix 規格容忍）。
const String kMarkdownRenderFlag = 'dev.homing.markdown';

/// 判讀訊息是否要求 Markdown 渲染（讀不到＝false）。
bool isMarkdownRenderRequested(Event? event) {
  if (event == null) return false;
  return event.content[kMarkdownRenderFlag] == true;
}

/// 判讀事件是否為無聲訊息（讀不到＝false；加密未解密 fail-open）。
bool isSilentMessage(Event? event) {
  if (event == null) {
    return false;
  }
  return event.content[kSilentMessageFlag] == true;
}

/// 第三十五批 #5＋#13：文字訊息 content 組裝（純函式，供測試）。
///
/// * [formattedBody] 非空＝依 Matrix 官方格式帶
///   `format: org.matrix.custom.html` ＋ `formatted_body`（規格欄位；
///   #13 Markdown 送出端使用）。
/// * [silent] ＝帶無聲旗標（#5；收訊端 Homing 跳過通知）。
/// * 回覆（m.in_reply_to）不在此組——SDK `Room.sendEvent` 有官方
///   `inReplyTo` 參數（room.dart L1263），直接使用。
Map<String, dynamic> buildTextMessageContent(
  String text, {
  bool silent = false,
  String? formattedBody,
  bool markdownRender = false,
}) {
  final content = <String, dynamic>{
    'msgtype': 'm.text',
    'body': text,
  };
  if (formattedBody != null && formattedBody.isNotEmpty) {
    content['format'] = 'org.matrix.custom.html';
    content['formatted_body'] = formattedBody;
    if (markdownRender) {
      content[kMarkdownRenderFlag] = true;
    }
  }
  if (silent) {
    content[kSilentMessageFlag] = true;
  }
  return content;
}
