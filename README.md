# Homing

> **草稿，須人工審閱。**

> Don't be evil.
>
> -- Google, 2004

Homing 是一個開源通訊軟體：基於 **Matrix 協定**與 **Flutter**，首要目的是促進人與人之間的直接互動——重視私聊與小群組的對話品質，不做注意力商業化。

## 專案資訊

| 項目 | 說明 |
|---|---|
| 核心目標 | 提供易用的開源通訊軟體 |
| 專案名稱 | Homing（2026-11-12 由「RING」更名，避開 Amazon Ring LLC 商標；詳 `known_problems.md` 批次 33） |
| 技術基礎 | Matrix 協定 + Flutter（SDK：`matrix` / matrix-dart-sdk） |
| 端對端加密 | 預設開啟（Olm / Megolm） |
| 目標市場 | 台灣為主（繁體中文） |
| 授權 | AGPL-3.0-or-later（詳見 `LICENSE`） |
| v1.0 平台 | Android + iOS（其餘平台見藍圖 Phase 7） |

## 與 LINE 不同之處

1. **繁中／台灣在地 UX**——與 FluffyChat 等既有 Matrix 客戶端相比的差異化核心之一。
2. **貼圖生態**——創作者自行發布 zip 貼圖包，使用者匯入即用；不含廣告或推薦機制。
3. **註冊與裝置驗證的簡化**——新裝置登入 / 金鑰恢復的流程與引導。
4. **沒有注意力商業化的設計**——無廣告、無追蹤碼、無推薦或無限滾動資訊流、無成癮機制（紅點、streak、排行榜）。
5. **資料自主**——使用者可隨時匯出對話紀錄（JSON / HTML），支援自訂 homeserver URL。
6. **互通與 fork 路徑**——基於開放協定，可與其他 homeserver 互通；不鎖定使用者。

## 功能狀態

以藍圖（`agent_v1_3.md`）的分階段計畫為準；逐項進度、實測待辦與驗收證據見 `PROGRESS.md`。

| 階段 | 狀態（2026-11-14） |
|---|---|
| Phase 0 基礎設定 | 大致完成（0.3 倉庫公開化與人工文件項目未結） |
| Phase 1 核心通訊 MVP | 完成（註冊／登入／加密聊天／金鑰備份與還原／裝置管理／通知／多裝置） |
| Phase 2 群組與資料自主 | 進行中（群組、資料匯出、帳號停用、多裝置同步已交） |
| Phase 3 貼圖系統 | 進行中（zip 匯入與發送已交；關鍵字聯想未開工） |
| Phase 5 優化與上線 | 未開工（**AGPL 與 App Store 相容性待專業諮詢**，為上架前置阻礙） |
| Phase 7 桌面／Web | 骨架已交（**Web 版目前不支援 E2EE**，見 `PRIVACY.md`）；正式化待人工決定 |

## 相關文件

| 檔案 | 說明 |
|---|---|
| `agent_v1_3.md` | 專案藍圖（規格與分階段計畫；唯一的權威來源） |
| `THREAT_MODEL.md` | 防誰、不防誰（隱私聲明的前置文件；草稿） |
| `PRIVACY.md` | 隱私聲明（草稿） |
| `SECURITY.md` | 漏洞回報流程（草稿） |
| `DEPENDENCIES.md` | 依賴清單、SPDX 授權、規格基準版本 |
| `DESIGN.md` | 設計決策紀錄（人類定稿維護，Agent 只讀） |
| `ARCHITECTURE.md` | 架構文件（資料模型、同步策略、狀態管理；草稿） |
| `PROGRESS.md` | 工作進度紀錄（批次、實測待辦、驗收輸出） |
| `known_problems.md` | 已知問題與根因紀錄 |
| `DEVICE_VERIFY.md` | 實機驗收清單（43 項，可勾選） |
| `STICKER_FORMAT.md` | 貼圖包格式規格 v1（草案，凍結待人類定稿） |
| `THEME_FORMAT.md` | 主題包格式草案 |

## 開發

- Flutter 專案位於 `app/`（Android + iOS 為 v1.0 範圍；Web／桌面僅骨架）。
- `flutter test`、`flutter analyze`（`app/` 目錄內）。

### 推播（通知）

通道優先序（見 `app/lib/push/push_channel.dart`；設定 → 通知 會顯示目前生效的通道）：

| 順序 | 通道 | 何時使用 | 說明 |
|---|---|---|---|
| 1 | **UnifiedPush** | 優先 | 由你自選的接收端（例如 ntfy）收送，**不經 Google** |
| 2 | **FCM**（Firebase Cloud Messaging） | 沒有 UnifiedPush 接收端時 | **需要你自己的 Firebase 專案**（FCM 是 Google Firebase 的服務）。兩種設定方式任選：① 把 `google-services.json` 放到 `app/android/app/`（**勿提交到版本庫**）；② 以 dart-define 帶入（不需放檔案）：`--dart-define=FCM_PROJECT_ID=… --dart-define=FCM_API_KEY=… --dart-define=FCM_APP_ID=… --dart-define=FCM_SENDER_ID=…` |
| 3 | **App 直接收** | 兩者皆不可用時 | App 在前景時仍會即時收到訊息（SDK 長輪詢）；**App 完全結束時不會收到通知** |

沒有 Firebase 專案時 App **不會崩潰**，會自動落到第 3 層；推播一律採 Matrix 的 `event_id_only` 格式：**推播不含訊息內文**，內容由 App 同步後自行解密顯示。

<!-- 上架條款、捐款連結等：待專業諮詢／待人工決定後補入 -->
