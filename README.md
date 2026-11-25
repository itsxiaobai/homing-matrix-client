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
| v1.0 平台 | **Android 優先**：以 **APK** 發布，**首發 F-Droid**；iOS／Google Play 排名在後，由人工另行決定（其餘平台見藍圖 Phase 7） |

## 與 LINE 不同之處

1. **繁中／台灣在地 UX**——與 FluffyChat 等既有 Matrix 客戶端相比的差異化核心之一。
2. **貼圖生態**——創作者自行發布 zip 貼圖包，使用者匯入即用；不含廣告或推薦機制。
3. **註冊與裝置驗證的簡化**——新裝置登入 / 金鑰恢復的流程與引導。
4. **沒有注意力商業化的設計**——無廣告、無追蹤碼、無推薦或無限滾動資訊流、無成癮機制（紅點、streak、排行榜）。
5. **資料自主**——使用者可隨時匯出對話紀錄（JSON / HTML），支援自訂 homeserver URL。
6. **互通與 fork 路徑**——基於開放協定，可與其他 homeserver 互通；不鎖定使用者。

## 功能狀態

以藍圖（`agent_v1_3.md`）的分階段計畫為準；逐項進度、實測待辦與驗收證據見 `PROGRESS.md`。

| 階段 | 狀態（2026-11-16） |
|---|---|
| Phase 0 基礎設定 | 大致完成（0.3 倉庫公開化與人工文件項目未結；**CI 已真實執行一次**，見下） |
| Phase 1 核心通訊 MVP | 完成（註冊／登入／加密聊天／金鑰備份與還原／裝置管理／通知／多裝置；另有追加的通話功能） |
| Phase 2 群組與資料自主 | 進行中（群組、資料匯出、帳號停用、多裝置同步已交；同步競態與跨 homeserver 冒煙待實機） |
| Phase 3 貼圖系統 | 進行中（zip 匯入與發送、關鍵字聯想、管理頁已交；貼圖「整包」概念與格式規格待人工定案） |
| Phase 4 緊急訊息 | 4.1–4.4 已交（釘選 API／橫幅／點擊跳轉／自動取消釘選；公告與災害示警已分流）；4.5 官方 bot ⛔ 待人工決定 |
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

- Flutter 專案位於 `app/`（Android 為 v1.0 優先範圍、APK 首發 F-Droid；iOS／Google Play 排在後；Web／桌面僅骨架）。
- `flutter test`、`flutter analyze`（`app/` 目錄內）。

### 推播（通知）

通道優先序（見 `app/lib/push/push_channel.dart`；設定 → 通知 會顯示目前生效的通道）：

| 順序 | 通道 | 何時使用 | 說明 |
|---|---|---|---|
| 1 | **UnifiedPush** | 優先 | 由你自選的接收端（例如 ntfy）收送，**不經 Google** |
| 2 | **FCM**（Firebase Cloud Messaging） | 沒有 UnifiedPush 接收端時 | **需要你自己的 Firebase 專案**（FCM 是 Google Firebase 的服務）。兩種設定方式任選：① 把 `google-services.json` 放到 `app/android/app/`（**勿提交到版本庫**）；② 以 dart-define 帶入（不需放檔案）：`--dart-define=FCM_PROJECT_ID=… --dart-define=FCM_API_KEY=… --dart-define=FCM_APP_ID=… --dart-define=FCM_SENDER_ID=…` |
| 3 | **App 直接收** | 兩者皆不可用時 | App 在前景時仍會即時收到訊息（SDK 長輪詢）；**App 完全結束時不會收到通知** |

沒有 Firebase 專案時 App **不會崩潰**，會自動落到第 3 層；推播一律採 Matrix 的 `event_id_only` 格式：**推播不含訊息內文**，內容由 App 同步後自行解密顯示。

> ⚠️ **FCM 舊版端點已停用（2026-11-16 實測）**
> `POST https://fcm.googleapis.com/fcm/send` 回 **HTTP 404**（Google 已停用舊版 FCM HTTP API）；
> FCM HTTP v1（`/v1/projects/{id}/messages:send`）仍存在但需 service account 的 OAuth2
> 短效 token，Matrix `http` pusher 只能帶靜態 `data.auth`，無法直接使用。
> 因此 **FCM 通道需一個可用的轉送端**：以 `--dart-define=FCM_GATEWAY_URL=https://<你的轉送端>`
> 指定（不需改程式）；未指定時 App 會在「設定 → 通知」明確顯示「FCM 閘道無法投遞」。
> **目前最省事的路徑是 UnifiedPush**（例如安裝 ntfy 作為接收端，不需 Google 帳號、不經 Google）。
> 詳見 `known_problems.md` 與 `PROGRESS.md`（第五十二批）。

### 取得可安裝的 APK（CI 出包）

**發布優先順序（人類 2026-11-23 指示）**：先以 **APK 發布，首發平台 F-Droid**。
iOS／Google Play 與其他平台（藍圖 Phase 7）皆排在 APK 之後，由人工另行決定。
目前 CI artifact 的 APK 仍以 debug 金鑰簽章，**僅供內部實機測試，不可上架**；
F-Droid 提交要求（原始碼建置、可重現性、非自由依賴等）⚠️待查證，
現階段尚未提交至 F-Droid。

本機若不便建置，`itsxiaobai/homing-alpha` 的 CI 會建置 release APK
並上傳為 artifact（工作流程：`license-check-and-vulnerability-scan` → `build-apk` job）。
該 APK 以 **debug 金鑰**簽章（`android/app/build.gradle.kts` 的 release 仍指向
`signingConfigs.debug`）→ **僅供內部實機測試，不可上架**。
FCM 憑證可放在該倉庫的 secrets（`FCM_PROJECT_ID`／`FCM_API_KEY`／`FCM_APP_ID`／
`FCM_SENDER_ID`／`FCM_GATEWAY_URL`）→ CI 會帶入 dart-define 重建。

> **2026-11-16 更新（歷史）**：暫存倉庫的 11 個 commit 已合併回本倉庫
> （fast-forward `892698b → 7a17526`）。**2026-11-23 起 CI 與发布目標皆為
> `itsxiaobai/homing-alpha`，`homing-tmp` 不再是出包目標。** 具備 Flutter 與
> Android SDK 的機器可直接建置：`cd app && flutter build apk --release`
> （release 仍以 debug 金鑰簽章，僅供內部測試）。

> 📦 **正式出包提醒（2026-11-20）**：正式輸出時要一次建立**四種** APK：
>
> ```sh
> cd app
> flutter build apk --release --split-per-abi   # arm64-v8a / armeabi-v7a / x86_64 各一
> flutter build apk --release                    # 通用（三種 ABI 全包）
> ```
>
> 日常測試可只建 v8a：`flutter build apk --release --split-per-abi --target-platform android-arm64`。
> 通用 APK 因同時打包三種 ABI（native lib ×3）約 242MB；per-ABI 約為其 1/3。
> release 仍以 debug 金鑰簽章，僅供內部測試；R8/shrinkResources 已明確關閉
> （`google_mlkit_text_recognition` 缺語言模組 class，開 R8 會建置失敗）。

<!-- 上架條款、捐款連結等：待專業諮詢／待人工決定後補入 -->

## 抖內 / 特別感謝

如果你想抖內我的話，這裡給你加密貨幣地址，暫時還沒辦法現金或信用卡付款：

比特幣 Bitcoin: bc1qf5kxvy8wt6hq3kggm55cp4pw3a7hnpdzr2lswf

以太幣 Ethereum: 0x7123507b1cb8963fb0176dcbc5305f84d1ea7319

門羅幣 Monero: 88FAHjzCWDvgDz4eMvDJMBd45xmWNxohk5F4aqJt2TUvATi14FoASzB7T2jHd4ekrQUvJXq2psMRFcAqT3k5ZTE1MdK6iWP

雖然你可以用加密貨幣抖內我，但我更希望你能直接支持（金錢、物質或心理上（？））這個專案的以下基礎建設們，幫助大家繼續運作！

### 軟硬體運作

- [Matrix.org](https://matrix.org/)：整個軟體的通訊架構 ~~，沒有它就完蛋了~~。
- [NCSE Network 社會公益計畫](https://ncse.tw/zh/csr/)：提供 VPS 作為 Matrix 伺服器和 CI/CD runner  

<a href="https://matrix.org/"><img src="https://matrix.org/images/matrix-logo-white.svg" alt="Matrix.org" width="180"></a>
&emsp;
<a href="https://ncse.tw/zh/csr/"><img src="https://cdn-file.ncse.tw/image/Logo_NCSE_Network_Banner.svg" alt="NCSE Network" width="180"></a>

### 好朋朋們

- XJD：啟發和支持我開始這個專案的一位格友（[部落格連結](https://ordinarykuma.bearblog.dev/)）
- 龍女 nudoragon：提供技術支援和一大堆好點子的格友（[所有連結](https://nudoragon.com/)）
- 創崴：願意幫忙測試軟體的好朋朋

### 我的精神糧食（？

就幾個喜歡的創作者。對，支持優質創作者也能幫忙專案運作，我就是不要臉 XD

- 吾橋有水：[YT](https://www.youtube.com/channel/UCt-RcL1eeLqXC1UHDjDJCQQ) | [街聲 StreetVoice](https://streetvoice.com/FloodingBridge/)
- 莊蕎嫣：[YT](https://www.youtube.com/channel/UCx0wtFhxZjLBaBAM0fooxfw) | [街聲 StreetVoice](https://streetvoice.com/rule1230/) | [抖內（歐付寶）](https://payment.opay.tw/Broadcaster/Donate/A3185B6772964C3EC1113C4EC8378553)
- 林貓 Zeko Lin：[官網](https://zeko.studio/) | [街聲 StreetVoice](https://streetvoice.com/zeko/) | [Odysee](https://open.lbry.com/@zeko:b) | [部落格](https://wancat.cc/)
- Maya Clars：[官網](https://mayaclars.com/) | [Odysee](https://odysee.com/@mayaclars:4) | [Bandcamp](https://mayaclars.bandcamp.com/) | [抖內](https://mayaclars.com/donations.html)
