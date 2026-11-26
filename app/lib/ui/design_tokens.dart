// 第二十一批（UI 重設計第一段；人類 2026-11-08 拍板）——design/ mockup 轉譯。
// 唯一樣式來源（design/README.md 流程）：值**直譯**自人類 SVG
// （design/drawing_defaulthome_UI_v0_2.svg、design/drawing_defaultcontact_UI_v0_1.svg
// ，PNG 採樣對照核可）。樣式草案，待人類定稿；換視覺原則上只動本檔＋tokens.md。
//
// 範圍（本批）：首頁／聯絡人結構、底列與 tab 膠囊、搜尋列、FAB、頭像圓。
// 主題色**不**在本檔：人類 2026-11-08 拍板「淺色＝預設或使用者調整（既有種子色
// 系統）」「深色＝純黑」→ 主題構建在 main.dart `ringTheme`（dark 底色引用
// 本檔常量）。mockup 的頁面底色 #E6C8B8 不作全域覆寫（跟隨種子系統派生）。

import 'package:flutter/material.dart';

/// 主文字（mockup 主字色；SVG fill #282828）。
const Color kTextPrimary = Color(0xFF282828);

/// 次要文字（搜尋 hint 等；SVG fill #808080）。
const Color kTextSecondary = Color(0xFF808080);

/// 分隔線（Spaces 下劃線；SVG #737373）。
const Color kDivider = Color(0xFF737373);

/// 強調色——頭像圓（SVG fill #FFB381）。
const Color kAccent = Color(0xFFFFB381);

/// 搜尋列底色（SVG fill #E0C1AE）。
const Color kSearchFill = Color(0xFFE0C1AE);

/// 底列／聯絡人 tab 膠囊底（SVG fill #ECECEC；PNG 探點亦近）。
const Color kPillSurface = Color(0xFFECECEC);

/// 選中項 chip 底（SVG fill #B2B2B2；人類 2026-11-08 指示「調白一點」→
/// 草案調至 #C4C4C4，待定稿）。
const Color kChipSurface = Color(0xFFC4C4C4);

/// FAB 底（聯絡人頁；SVG fill #EBD4C8）。
const Color kFabFill = Color(0xFFEBD4C8);

/// 深色主題頁面底（人類 2026-11-08「深色用純黑」；main.dart 引用）。
/// 草案：僅頁面底／Scaffold 純黑，其他 M3 容器維持種子派生深灰。
const Color kDarkSurface = Color(0xFF000000);

// ─── 第六十一批（人類 2026-11-17 指示「重新設計 UI，參考 LINE_ref，先盡量
// 第九十一批（人類「將主題回復」）─── 回復到 v2 定稿配色。
// 常數名保留（避免大量重構）但值改為 UI_SPEC.md §一 的 v2 定稿語意：
// 純黑 surface、Homing 種子色派生、LINE 綠→種子桃色、次要文字 #808080。
// 注意：不複製 LINE 角色 IP／貼圖／logo；圖示（Compound）與版面不受影響。

/// 頁面底（T3 純黑）。
const Color kLineBg = Color(0xFF000000);

/// 聊天室頁底（回復純黑）。
const Color kLineChatBg = Color(0xFF000000);

/// 頂列／搜尋列底（貼近純黑）。
const Color kLineBar = Color(0xFF1F1F1F);

/// 對方訊息氣泡（T5 #3A3A3A；也用作輸入框 pill）。
const Color kLineBubbleIncoming = Color(0xFF3A3A3A);

/// 自己訊息氣泡（T4 主題淡桃；theme 已走種子派生，此值供寫死引用一致）。
const Color kLineBubbleOutgoing = Color(0xFFFFBD9F);

/// 自己氣泡上的文字（T6 深色 #1A1A1A）。
const Color kLineOnBubbleOutgoing = Color(0xFF1A1A1A);

/// 主色／膠囊（回復 Homing 種子桃色 #FFBD9F，非 LINE 綠）。
const Color kLineGreen = Color(0xFFFFBD9F);

/// 日期分隔膠囊底。
const Color kLineDateChip = Color(0xFF1F1F1F);

/// 時間／次要文字（T8 #808080）。
const Color kLineTimeText = Color(0xFF808080);

/// 未讀徽章（T17 #FF5C5C 白字）。
const Color kLineUnreadBadge = Color(0xFFFF5C5C);

/// 底部導航列底（純黑）。
const Color kLineNavBg = Color(0xFF000000);

/// 底部導航未選中項色（#808080）。
const Color kLineNavUnselected = Color(0xFF808080);
