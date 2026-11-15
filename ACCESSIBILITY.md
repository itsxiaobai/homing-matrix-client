# ACCESSIBILITY.md — 無障礙功能盤點

> **狀態**：盤點 + 第一批修正（2026-11-15）。目標：Homing 的核心流程（聊天／貼圖／設定）對
> **螢幕閱讀器**與**大字級**可用，並維持藍圖 §設計原則（無成癱機制、觸控目標明確）。
> 對應人類目標 #17「確保無障礙功能仍友善（Fix needed）」。

## 一、盤點結果（2026-11-15）

| # | 項目 | 現況（盤點前） | 本批處置 | 狀態 |
|---|---|---|---|---|
| A1 | 圖示按鈕的無障礙名稱 | 28 個 `IconButton` **全部**有 `tooltip`（Flutter 會以 tooltip 作為 semantics label） | 已符合 | ✅ |
| A2 | 圖片／貼圖訊息 | `Image.memory`／`Image.file` **無** semantics label → 螢幕閱讀器只會說「圖片」 | 聊天室圖片／貼圖、貼圖面板、貼圖管理頁加入 `Semantics(label: …)`（含 alt text／shortcode） | ✅ |
| A3 | 貼圖建議列 | 已有 `Semantics(button, label: '建議貼圖：xxx')` | 已符合 | ✅ |
| A4 | 大字級 | 文字大小可調（預設 0.9＝人類決策），且不寫死任何版面寬度（`chat_layout.dart` 以視窗寬度比例計算） | 已符合 | ✅ |
| A5 | 觸控目標 | Flutter 預設最小 48dp；自訂按鈕（圖示列、chevron、拖曳把手）沿用預設 | 已符合 | ✅ |
| A6 | 深／淺色對比 | 主題色 `#FFBD9F` ＋ Material `fromSeed` 產生色階；深色模式純黑 | **部分量測**（第四十九批：淺色 token 固定組合已工具化量測，**4 組未達 AA**——見 `known_problems.md` 首條；深色模式（Material 派生）**未量測**） | 🔶 部分 |
| A7 | 動效與依賴動畫 | 無自動播放動畫（貼圖 GIF 由使用者主動送出後播放）；無紅點／streak | 已符合 | ✅ |
| A8 | 朗讀順序 | 訊息由新到舊（`reverse: true`）→ 螢幕閱讀器需反向瀏覽 | 可接受（LINE 同） | ⬜ 待人工確認 |
| A9 | 聊天列表／聯絡人項目的朗讀 | 名稱／摘要／時間以文字呈現，語意順序合理 | 已符合 | ✅ |
| A10 | 錯誤訊息 | Snackbar 與對話框皆為文字（可被朗讀） | 已符合 | ✅ |

## 二、本批修正的程式碼

| 檔案 | 處置 |
|---|---|
| `app/lib/ui/chat_screen.dart` | `_ChatImageTile` 新增 `semanticLabel` 參數；圖片＝「圖片：{alt}」、貼圖＝「貼圖：{alt}」 |
| `app/lib/ui/emoji_panel.dart` | 貼圖格 `Semantics(button, label: '貼圖：{shortcode 或名稱}')` |
| `app/lib/ui/contacts_screen.dart` | 頂列改 LINE 版位（大標題「好友」＋右側「新增好友／掃碼」icon）＋搜尋列改膠囊圓角 24dp |

## 三、仍待處理（可自行完成，但需逐頁人工確認）

1. **對比度量測**（A6）：
   - ✅ **已工具化（第四十九批）**：`app/tool/check_contrast.dart`
     （`dart run tool/check_contrast.dart`，退出碼 0＝全達 AA）＋純函式
     `app/lib/contrast.dart`（WCAG 2.1 演算法）＋單元測試 `test/contrast_test.dart`。
     淺色 token 的 10 組固定組合已量測；**4 組未達 AA**（次要文字 on 白底 3.95、
     次要文字 on 搜尋列底 2.33、白字 on 緊急紅 4.11、主文字 on 緊急紅 3.59）
     → 已記於 `known_problems.md` 首條，**待人類決策配色**。
   - ⬜ **仍待人工**：
     ① **深色模式**（Material `fromSeed` 派生的色階）尚未納入工具量測；
     ② **動態／狀態組合**（例如登入鈕的停用態、SnackBar 底色）需逐頁檢查；
     ③ 量測只是數值，**最終可讀性仍需人工判讀**（真實螢幕 × 真實字級 × 大量文字）。
2. **圖示語意化**：部分圖示（置頂、靜音、未讀徽章）目前靠鄰近文字說明，未獨立標籤。
3. **自訂對話框焦點**：Dialog 開啟時焦點落在第一個可互動元件（Flutter 預設）→ 需逐頁確認。
4. **TalkBack 實機走查**：本批僅做靜態盤點與語意標籤補齊，**未做 TalkBack 語音實聽**
   （需人工或螢幕閱讀器自動化；本環境可做靜態檢查）。

## 四、維持原則

- 新增任何圖片元件時**必須**附 `Semantics` label（alt text 或 shortcode）。
- 新增 IconButton 時**必須**附 `tooltip`（作為螢幕閱讀器名稱）。
- 版面尺寸**不寫死寬度**（`DESIGN.md` §1 斷點策略）；大字級下不得截斷或重疊。
- 不以顏色作為唯一資訊傳達（靜音／置頂／未讀都另有文字或圖示）。
