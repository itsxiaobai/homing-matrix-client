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
| 授權 | AGPL-3.0-or-later（詳見 `LICENSE`，待 Phase 0.4 設定） |
| v1.0 平台 | Android + iOS（其餘平台見藍圖 Phase 7） |

## 與 LINE 不同之處

1. **繁中／台灣在地 UX**——與 FluffyChat 等既有 Matrix 客戶端相比的差異化核心之一。
2. **貼圖生態**——創作者自行發布 zip 貼圖包，使用者匯入即用；不含廣告或推薦機制。
3. **註冊與裝置驗證的簡化**——新裝置登入 / 金鑰恢復的流程與引導。
4. **沒有注意力商業化的設計**——無廣告、無追蹤碼、無推薦或無限滾動資訊流、無成癮機制（紅點、streak、排行榜）。
5. **資料自主**——使用者可隨時匯出對話紀錄（JSON / HTML），支援自訂 homeserver URL。
6. **互通與 fork 路徑**——基於開放協定，可與其他 homeserver 互通；不鎖定使用者。

## 功能狀態

以藍圖（`agent_v1_3.md`）的分階段計畫為準；目前進度見 `PROGRESS.md`。

## 相關文件

| 檔案 | 說明 |
|---|---|
| `THREAT_MODEL.md` | 防誰、不防誰（隱私聲明的前置文件；草稿） |
| `PRIVACY.md` | 隱私聲明（草稿） |
| `SECURITY.md` | 漏洞回報流程（草稿） |
| `DEPENDENCIES.md` | 依賴清單、SPDX 授權、規格基準版本 |
| `PROGRESS.md` | 工作進度紀錄 |

## 開發

- Flutter 專案位於 `app/`（Android + iOS）。
- `flutter test`（`app/` 目錄內）。

<!-- 上架條款、捐款連結等：待專業諮詢／待人工決定後補入 -->
