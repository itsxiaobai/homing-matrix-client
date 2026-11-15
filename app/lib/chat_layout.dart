// 聊天室版面尺寸常數——**依 LINE 實機版位慣例**（參考 `LINE_ref/new_ref/chat/`）。
//
// ⚠️ 這些是**版位比例與尺寸**（可觀察的排版事實），不是 LINE 的品牌識別：
// 顏色、圖示、字型、logo 仍為 Homing 自己的（藍圖 §十二：可沿用產業通用版位，
// 必須自創品牌識別）。
//
// 依據（實機稿對照）：
// - 貼圖（sticker）在 LINE 是**小尺寸正方圖、無泡泡底色**（不像照片那樣滿版）；
// - 圖片訊息在 LINE 以**圓角縮圖**呈現，最大寬度約為畫面的六成，**不滿版**；
// - 文字泡泡最大寬度約為畫面的七成多（自己與他人皆同），圓角較大、無尖角。
//
// 元件一律**不寫死寬度**：以視窗寬度 × 係數計算，符合 DESIGN.md §1 的斷點策略。

/// 貼圖顯示邊長上限（dp）。
///
/// **2026-11-15 人類實測回饋：132dp「靠邊緣太近」→ 收到 110dp**
/// （貼圖是小圖，不應貼著對話邊緣；LINE 的貼圖也明顯小於對話寬度）。
const double kStickerMaxSizeDp = 110;

/// 圖片訊息最大寬度＝視窗寬度 × 此係數（不滿版；2026-11-15 由 0.60 收到 0.55）。
const double kImageBubbleWidthFactor = 0.55;

/// 文字泡泡最大寬度＝視窗寬度 × 此係數（2026-11-15 由 0.74 收到 0.68
/// ——「靠邊緣太近」，收窄讓對話左右留白更一致）。
const double kTextBubbleWidthFactor = 0.68;

/// 由視窗寬度與係數算出最大寬度（dp）。
///
/// [windowWidth] 取自 `MediaQuery.sizeOf(context).width`；元件不直接依賴
/// 具體裝置尺寸，故同一份 UI 在平板／桌面皆適用。
double maxBubbleWidth(double windowWidth, double factor) =>
    windowWidth * factor;

/// 貼圖的顯示邊長上限（dp；不超過視窗寬度的一定比例，避免大螢幕過小）。
double stickerDisplaySize(double windowWidth) {
  final byWindow = windowWidth * 0.42;
  return byWindow < kStickerMaxSizeDp ? byWindow : kStickerMaxSizeDp;
}
