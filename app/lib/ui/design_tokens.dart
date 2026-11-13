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
