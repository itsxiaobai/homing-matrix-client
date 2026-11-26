// 無障礙（第五十七批・人類指示「最少要讓使用者在點選按鈕的時候能聽到按鈕
// 功能說明」）。
//
// Flutter 的 `IconButton.tooltip` 本身會轉成 Semantics label（TalkBack 會在
// 聚焦／啟動時讀出）→ 本檔在此之上再補一層**明確**的 `Semantics(button: true)`
// 包裹，確保即使tooltip 因主題或樣式被拿掉仍能朗讀功能說明。
//
// ⚠️ 不重複接管 onTap（避免與子按鈕的 onPressed 雙觸發）→ 只加語意標籤。
library;

import 'package:flutter/material.dart';

/// 把按鈕包成「可朗讀功能說明」的語意按鈕。
///
/// [label] 應為**已翻譯**的字串（通常來自 `S.t(...)`）。
Widget a11yButton({
  required String label,
  required Widget child,
}) {
  return MergeSemantics(
    child: Semantics(
      button: true,
      label: label,
      child: child,
    ),
  );
}

/// 前庭障礙／動作敏感使用者：跟隨 **OS「移除動畫」設定**
/// （Android「移除動畫」／iOS「減少動作」→ Flutter `MediaQuery.disableAnimations`）。
///
/// 第六十三批（人類指示「無障礙服務對象包含視覺、聽覺、動作、前庭（、認知）
/// 障礙者，但使用體驗不可影響一般使用者」）：App 目前**沒有自訂動畫**
/// （掃描無 AnimationController／AnimatedXxx）→ 本 helper 為預防性 API：
/// 日後新增任何動效（橫幅入場／表情飄浮／轉場等）**必須**用本旗標
/// 短路成靜態呈現；一般使用者（未開啟該 OS 設定）完全不受影響。
bool a11yReduceMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;
