# 已知問題

> **未結條目分類速查（第五十七批更新；⬜＝本檔仍未勾選）**
>
> | 條目 | 分類 | 下一步 |
> |---|---|---|
> | 讀取大量資料時 App 無回應／被 Android 判當機 | **主因已修**（第五十七批：訊息列表視覺化＋簽章雜湊改寫），**待實機量測** | 載入 500／2000 則，比對診斷資訊「效能量測」區的 `chat.load`／`chat.plan` |
> | 平板介面需要重新設計 | **人類 2026-11-17 指示：先照原樣，之後再改** | 暫緩（連結構性準備也暫緩） |
> | 多語言：Flutter 內建元件字串 | ✅ **已解決**（第五十八批：`flutter_localizations`＋`intl` 經批准新增，內建元件亦隨語言切換） | 待實機確認 |
> | 多語言 App 字串未補齊 | 🔶 **第六十七批已實機稽核**（仍中文清單見 B17），未修 | 逐頁補 `S.t`＋翻譯 |
> | matrix SDK 16.0.4 升級後的實機回歸 | **升級已完成**（CI analyze/test 全綠），**待實機** | 見 `SDK_UPGRADE_EVAL.md` §七（登入／解密／recovery／貼圖庫／通話） |
> | 無障礙對比未達 WCAG AA（4 組） | **待人類決策**（非程式錯誤） | 調深次要文字 or 調整緊急紅 or 改大字級 |
> | 圖片／附件上傳失敗 | ✅ **已修且實機驗收通過**（第五十一批修／第五十三批驗） | 已收案；影片／一般檔案走同一函式但未逐項實測 |
> | FCM 冷喚醒（App 被殺時）失敗 | **isolate 根因已排除**（與圖片上傳同根，已實測通過）＋**投遞端點已停用** | 仍待：①有 Firebase 憑證且無 UP 接收端的機驗 FCM 背景路徑 ②人類決定閘道 |
> | 推播閘道（Google 舊版 FCM 端點 404） | **已實測確認，待人類決策** | 選 UnifiedPush／自架轉送端／其他閘道 |
> | 群組通話成員變動僵局 | **已知限制**（官方 SDK 層） | 官方已棄 mesh 改 LiveKit；優先走 LiveKit |
> | 通話同撥互接／無法發起 | **已知限制**（1:1 mesh 路徑） | 同上 |
> | 螢幕分享含系統聲音 | **需新依賴／改 plugin**（⛔ 規停下） | 人類選擇 |
> | 外部分享（檔案型） | **待人類決定** | 需 native intent 整線 |
> | 多語言（i18n） | 🔶 主體已遷移（第五十八批：441 處／346 字串／373 譯；`flutter_localizations` 已批准），但第六十七批實機稽核仍發現漏網（詳 B17） | 待補齊後覆核 |
> | 離線可讀的內容快取 | **✅ 方案 A 已實作**（第五十八批：媒體快取＋LRU／上限／清除）；**待實機** | 飛航模式看已快取圖片；待補 PRIVACY 草稿備註 |
| 圖示變數化（主題包換圖示） | ✅ **已全數實作**（第五十九批：130 槽位／249 處全替換＋theme.json `icons`）；**待實機** | — |
| 無障礙：按鈕功能說明 | **✅ 已補**（第五十八批：`a11yButton`＋既有 tooltip→Semantics）；**待實機 TalkBack** | 全盤點仍未開工 |
| SECURITY 信箱 | **人類指示：之後處理** | 暫緩 |
| 手機號碼查詢結論寫入 DESIGN.md | **人類指示：待定** | 暫緩（DESIGN.md 由人類維護） |
> | 離線可讀的內容快取 | ✅ **方案 A 已實作**（第五十八批）；**待實機** | — |
> | LINE → Matrix 橋接 | **已研究**（`BRIDGE_RESEARCH.md`），**維持不接入** | 你決定是否自建橋接作保險（高風險） |
> | CLI 模式 | **待人類定義範圍** | ⬜ |
> | 已讀顯示（跨客戶端） | **協定限制**（private receipt） | 對端 Element X 不可見屬預期 |
> | 創作者主題包（完整化） | **部分完成**（zip 匯入已交） | 待格式規格定案＋圖標變數化 |
> | 緊急現況 v2 已知限制 | **披露**（第六十六批：只看 1:1 房最新一則／純文字無簽章／119·所有人已移除） | 詳見下方專條；防偽涉加密＝必停 |
> | i18n 未完全 | **✅ 第六十七批實機稽核完成，遺漏未修**（首頁下拉／底列／設定標題／日期分隔／聯絡人標題／診斷標籤／a11y 標籤） | 清單見 `PROGRESS.md` 第六十七批；待排程補 `S.t`＋翻譯 |
> | 預約訊息前景限制（第六十九批） | **披露**：Matrix 無預約協定 → 純本機 kv＋前景 Timer；App 被凍結／殺掉時 Timer 不觸發，重開後補送 | 不另做背景服務（平台依賴／維運＝必停）；詳見 `NEXT_GOALS.md` F-2 |
> | 無痕收回邊界（第七十批） | **披露**：Homing 私有旗標放進官方 redaction `reason` → Home 端整列不顯示；其他客戶端（Element 等）仍依自身 UI 顯示收回 | 跨客戶端無痕做不到；非 server 通知控制，屬 client 行為 |
> | 過去訊息卡頓 | **大幅改善（第六十七批）**：真因＝非加密房每次 HTTP 404（7225 ms）→ 負面快取＋訊息快取＋解密快取（無 TTL）→ 首載 1019 ms、重進約 0.5 s | 仍非 0；待更細分項（getTimeline／DB）量測 |

- [x] **收回訊息後本機要重開才更新（第五十四批已修；第五十六批再去掉 1 秒去抖）**
  - **人類回報（2026-11-16）**：「對方收回訊息，本機要重開才會更新」；修正後於
    另一台裝置**端到端確認即時生效**（「喔有了」），但回報「**但好慢／拖了好幾秒**」。
  - **根因（兩個，缺一不可）**：
    ① `chat_screen.dart` 的 `_syncSub` **只在 `room.lastEvent` 改變時**才重載 →
       收回**舊**訊息並不改變 lastEvent → 根本不觸發重畫。
    ② 即使重載也無效：`_defaultLoadMessages` **重用同一 Timeline 實例**（避免丟掉
       `requestHistory` 抓到的歷史窗口，見該方法註解），而記憶體中的舊事件物件不會
       被標記為已收回——官方 SDK 只對 `room.lastEvent` 做 `setRedactionEvent`
       （matrix-14.2.0 `client.dart` L3188），其餘事件的收回狀態只存在 DB 裡，
       要重建 Timeline 才會帶上（但重建會丟歷史窗口）。
  - **修法（第五十四批）**：訂閱官方 `onTimelineEvent`（收回事件走 timeline 通道），
    取 `redacts` 指向的 eventId，**就地**對記憶體中的事件物件呼叫官方
    `Event.setRedactionEvent`（與官方 SDK 對 lastEvent 的同一手法）→ 畫面即時顯示
    「[已收回]」，且**不重建 Timeline**。邏輯抽成公開純函式 `applyRedactionToEvents`
    → 單元測試 `test/redaction_live_update_test.dart`（3 案全過）。
  - **延遲優化（第五十六批）**：收回處理原本走 `_scheduleReload()`（**1000ms 去抖**）
    → 改為**立即**重載。其餘延遲來自 SDK 的 sync 往返（官方機制）。

- [x] **編輯訊息後畫面不動，要等「其他地方有更新」才會變（第五十六批已修）**
  - **人類回報（2026-11-16）**：「啊編輯完怎麼沒動」「靠編輯完要其他地方有更新的
    時候才會變」。
  - **直接原因**：`_load()` 只比對「**筆數** + **最後一則 eventId**」決定要不要換掉
    `_messages`（避免重複 setState 造成閃爍）→ **只有內容變了**（編輯套用）時
    `changed` 為 false → **整份新列表被丟棄** → 畫面完全不動。
  - **更深根因（本地為何拿不到編輯內容）**：① SDK `Timeline._relationRequests`
    成功後**永久保留**（同一則訊息再抓只會拿到舊 future）② App 端
    `_editRelationsChecked` 每個 eventId **只查一次** ③ m.replace **不進 timeline
    的 chunk**（只進 SDK 的 `aggregatedEvents` 聚合樹，而 `buildEditMap` 只掃 chunk）
    ④ m.replace **不改變 `room.lastEvent`** → 重載條件永不觸發。
  - **修法（三層）**：① `_load()` 改用**內容簽章**（eventId＋body＋已編輯記號）
    ② 本機編輯對照 `_localEdits`（**持久化到 kv**）＋公開純函式
    `resolveWithLocalEdits()`（官方真的換了內容才採用官方；官方只標「已編輯」
    但內容沒變 → 用本機對照，避免「有 (已編輯) 記號但內容還是舊的」）
    ③ 用**官方 /relations 原始 API**（`client.getRelatingEventsWithRelType`，不受
    SDK 快取限制）向伺服器確認內容並回寫本機對照。
  - **驗證**：`test/local_edit_applied_test.dart`（4 案）→ 全過。

- [x] **貼圖可被分享／下載（著作權；第五十四批已修）**
  - **人類指示（2026-11-16）**：「貼圖雖然被視為圖片，但似乎不應該能被分享和下載
    （有著作權問題）」。
  - **理由**：貼圖包**自帶授權**（例：`catpack_ok.zip` 內含 `LICENSE.txt`＝CC0-1.0），
    貼圖不應被匯出到 App 之外——「分享至外部」會把解密後的原始檔寫成系統暫存檔
    交給外部 App；「下載」則存進系統相簿／檔案。
  - **修法（3 處）**：① 聊天長按選單的「分享至外部」對貼圖隱藏
    （貼圖事件型別是 `m.sticker`，`isImage` 為 false → 原本會顯示）；② 全屏預覽頁
    對貼圖隱藏整列下載／分享鈕（改顯示「貼圖不提供下載／分享」）；③ `_shareAttachment()`
    與 `ImagePreviewScreen._shareOrSave()` 加防線直接拒絕。
  - **驗證**：`test/sticker_export_restriction_test.dart`（3 案，含「一般文字仍可分享」
    「一般圖片預覽仍有下載／分享」回歸保護）＋**實機覆核**（貼圖長按選單無分享項；
    全屏預覽底部僅顯示說明文字）。

- [ ] **讀取大量資料時 App 無回應，Android 判定當機（2026-11-17 加入目標；**主因已修，待實機量測**）**
  - **第五十七批定位與修正（讀碼確認）**：主因＝`chat_screen.dart` 的訊息列表用
    `ListView(children: [...rows.reversed])` → **無視覺化**，且 `_buildRows()` **逐則
    建立 Widget** → 數百～數千則時每次 rebuild 產生整棵 Widget 樹 → 主執行緒
    壅塞＋記憶體暴增（實測曾被 OOM killer 殺，RSS ≈ 1.05 GB）。
    → 修＝**列計畫**（`chat_row_plan.dart`，純資料）＋ `ListView.builder`（只有可視
    範圍內的列才建 Widget）＋ 簽章雜湊改用 `String.hashCode`＋移除殘留 debug print。
  - **量測工具（並行）**：`app/lib/perf_metrics.dart`（只記耗時與筆數）＋設定 →
    進階 → 診斷資訊「效能量測」區（`chat.load`／`chat.plan`）。
  - **待實機**：載入 500／2000 則，觀察是否仍當機 ＋ 量測數值；若有殘留卡頓再依
    量測結果處理（`_defaultLoadMessages` 全量解密／`_fetchEditRelations` 8 個
    `/relations` 請求／畫面一次性渲染大量項目）。
  - **人類回報（2026-11-16 於 Test in RING，原話）**：「資料太多就載到超卡」「Android
    直接當成沒有回應」（→ 系統跳「App isn't responding／建議強制停止」）。
  - **旁證**：第五十三～五十六批實測期間，App 行程曾被 **OS OOM killer 殺掉**
    （`lowmemorykiller: Kill 'io.github.itsxiaobai' … to free 1097608kB rss`），
    裝置同時處於記憶體壓力 → 與「資料量大 → 記憶體／主執行緒壅塞」同一方向。
  - **候選成因（需實測定位，勿先入為主）**：① `_load()` 每次整份重建列表（解密全部
    事件＋建立編輯／回覆對照）②第五十六批新增的內容簽章每次重載走完整串 list（O(n)）
    ③SDK timeline 單一 chunk（無視窗化）→ `timeline.events` 全量掃描
    ④`_fetchEditRelations` 每次重載最多 8 個 /relations 請求 ⑤畫面一次渲染大量項目
    （無虛擬化）⑥大圖預處理／上傳的排隊擠占主執行緒。
  - **建議**：先量測（載入 N 則的記憶體／主執行緒時間／掉幀）→ 定位瓶頸 → 分項處理
    （視圖化／增量解密／分頁／移出主執行緒）。已記入 PROGRESS.md 待完成 backlog。

- [ ] **平板介面需要重新設計（2026-11-17 加入目標；待人類定稿版面）**
  - **現況（第五十三批實測）**：模擬 Pixel Tablet 10.95"（800×1280 dp）→ 版面**可用**
    （≥600dp 出現左側 NavigationRail＋右側內容區；聊天室訊息列與底部輸入列正常），
    但本质上是**手機版版面直接放大**，未針對大尺寸重新編排。
  - **⚠️ 最終介面由人類設計**（AGENTS.md）→ 本目標只記錄問題與現況，**具體版面待
    人類定稿**後才動工；Agent 只可先做結構性準備（尺寸／斷點參數化）。

- [ ] **無障礙對比未達 WCAG AA（第四十九批量測發現；待人類決策配色）**
  - 量測工具：`app/tool/check_contrast.dart`（`dart run tool/check_contrast.dart`，退出碼 0＝全達 AA）。
    演算法＝WCAG 2.1（相對亮度 L、對比比 CR；AA 一般文字 ≥ 4.5、AAA ≥ 7.0）；
    實作於 `app/lib/contrast.dart`（純函式，有單元測試 `test/contrast_test.dart`）。
  - **未達 AA 的 4 組**（2026-11-16 本機實測）：
    | 組合 | 比值 | 說明 |
    |---|---|---|
    | 次要文字 `#808080` on 白底 | 3.95:1 | `design_tokens.kTextSecondary`；用於搜尋 hint／分區標題 |
    | 次要文字 `#808080` on 搜尋列底 `#E0C1AE` | 2.33:1 | 搜尋 hint 疊在蜜桃色搜尋列上（最差的一組） |
    | 白字 on 緊急紅 `#E8384F` | 4.11:1 | LINE 緊急紅卡片的白字；距 4.5 門檻差 0.39 |
    | 主文字 `#282828` on 緊急紅 `#E8384F` | 3.59:1 | 緊急紅上的深色文字 |
  - **待人類決策**：①調深次要文字（如 `#6B6B6B`）或改搜尋列底色；②緊急紅微調（需同時維持
    「跟 LINE 緊急紅一致」的既定值）或該卡片改用大字級（≥18pt，門檻降為 3.0 → 4.11 即可過）。
  - ⚠️ **注意**：本條**不是程式錯誤**，是配色與無障礙標準的取捨。CI 的對比步驟目前
    以 `continue-on-error: true` 執行並如實輸出報告；人類決策後再改為阻斷式。

- [x] **圖片／附件上傳失敗（第五十一批已修；✅ 第五十三批實機驗收通過）**
  - **人類 2026-11-16 實機回報**：聊天室（307_67）送圖片 → 畫面提示
    「已送出 0 個附件，1 個失敗（最後原因： Bad state: flutter_rust_bridge has not
    been initialized. Did you forget to call `await RustLib.init();`? (If you have
    configured a different lib name, change `RustLib` to your name.)）」。
  - **根因（SDK 原始碼查證，非猜測）**：
    - matrix SDK 14.2.0 `encryptFile`（`lib/src/utils/crypto/encrypted_file.dart`）
      呼叫的 `CryptoUtils.aesCtr`／`CryptoUtils.sha256` **不是** SDK 內那份純 Dart
      `crypto.dart`，而是 **vodozemac（rust）** 匯出的 `CryptoUtils`
      （vodozemac-0.9.1 `lib/src/api.dart` L631-652）。
      ⚠️ 舊紀錄（第二十六批）誤判為「純 Dart AES-CTR＋SHA-256，不碰 rust」——本條更正。
    - rust 狀態是 **isolate 區域**的：`flutter_rust_bridge` 2.13.0 的
      `RustLib.instance` 未初始化時**拋** StateError（訊息與實機截圖逐字相符）；
      `RustLib.init()` 在**同一 isolate 內第二次**呼叫會拋
      「Should not initialize flutter_rust_bridge twice」。
    - 本專案 `media_upload.dart` 把 SDK 官方 `encryptFile` 放在
      `Isolate.run`（**背景 isolate**）內執行 → 該 isolate 從未 `RustLib.init()`
      → 必然拋上述錯誤。**所有附件（圖片／影片／檔案）在加密房都會失敗**。
  - **修法（第五十一批）**：新增 `engine_init.dart` 的 `initRustEngineInIsolate()`
    ——在**當前 isolate** 內初始化 vodozemac（冪等：不重複 init）；
    `encryptFileInBackground()` 於背景 isolate 內先呼叫它，失敗則拋明確錯誤
    「加密引擎未就緒（背景 isolate 內 vodozemac 初始化失敗）」。
    官方 SDK 既有同一模式：`NativeImplementationsIsolate(compute,
    vodozemacInit: …)` 會在 isolate 內 `await vodozemacInit?.call()`
    （matrix-14.2.0 `lib/src/utils/native_implementations.dart` L198-281）。
  - **✅ 實機複驗（第五十三批，2026-11-16，APK 2056／裝置 `CQ300191JU` Android 15）**：
    加密房 307_67 送 `ring_engine_test.png`（`room.encrypted`＝true → 走
    `chat_screen.dart` → `encryptFileInBackground()` → `Isolate.run` 背景 isolate
    → vodozemac/rust，**正是本條修復的路徑**）：
    - 上傳中畫面 `上傳中 1/1 · 上傳中`，**無 rust 錯誤**；
    - 完成 Snackbar 實拍：**「已送出 1 個附件」**（**無「個失敗」／無
      「Bad state: flutter_rust_bridge has not been initialized…」**）；
    - 連送 2 次皆成功；房間預覽顯示「傳送了照片 ring_engine_test.png」；
    - logcat `[Matrix] [Key Manager] Uploading 1 room keys...`（E2EE 金鑰分送正常），
      **全程無 `flutter_rust_bridge has not been initialized`／無
      `vodozemac init failed`**。
    → **本條已收案**（✅）。⚠️ 僅驗證**圖片**；影片／一般檔案走同一函式
      （`chat_screen.dart` 同一路徑），但未逐項實測。

- [ ] **FCM 冷喚醒（App 被殺時）失敗（第五十一批已修背景 isolate；✅ isolate 根因已由圖片上傳路徑實測排除，投遞層仍待人類決策）**
  - **人類 2026-11-16 回報**：「FCM 測試失敗」（細節待補：logcat／測試步驟）。
  - **已確認的缺陷（與上條同根）**：`firebase_messaging` 的背景 handler 跑在
    **另一個 isolate**（rust 狀態不跨 isolate）；而 matrix SDK 14.2.0
    `Client.init()` 內部會呼叫 `vod.isInitialized()`，該 getter 在未初始化時
    **拋** StateError → `Client.init()` 直接失敗 → 冷喚醒整條鏈中斷
    → **App 被殺時收不到 FCM 推播**（先前 `catch (_) {}` 全吞＝無跡可尋）。
  - **修法（第五十一批）**：`fcmBackgroundHandler` 內先
    `await initRustEngineInIsolate()`；失敗原因改為 logcat 輸出（不再全吞）。
  - **第五十三批實測狀況（部分收斂）**：
    - ✅ **isolate 根因已排除**：圖片上傳路徑（`Isolate.run` 背景 isolate ＋
      vodozemac/rust）與本條的 FCM 背景 handler 是**同一個 rust／isolate
      根因**；該路徑實測已通過（見上條）→ 「背景 isolate 缺引擎」這個根因
      已被實機證實修好。
    - ⛔ **本條的 FCM 背景路徑本身仍無法在此機實測**：測試機已裝 UnifiedPush
      接收端（`org.unifiedpush.distributor.sunup`）→ 三層優先序走第 1 層，
      **不會進入** `fcmBackgroundHandler`；且本機無 Firebase 憑證 → FCM 通道
      停用。要驗此路徑需一台「**無 UnifiedPush 接收端＋有 Firebase 憑證**」
      的機（B1／B9 仍待人類）。
    - → 本條**維持未結**（拆成：isolate 修復 ✅／FCM 背景路徑實測 ⏳／投遞層
      待人類決策 ⏳）。
  - **仍待查證／待人類**：
    ① **FCM 投遞端點已實測確認（2026-11-16，本機實打 Google 端點）**：
    - `POST https://fcm.googleapis.com/fcm/send` → **HTTP 404**（回應為 Google GSE 的
      "Not Found" 錯誤頁）→ **舊版 FCM HTTP 端點已停用**；
    - `POST https://fcm.googleapis.com/send` → **HTTP 404**（同）；
    - `POST https://fcm.googleapis.com/v1/projects/{id}/messages:send` → **HTTP 401**
      「Request is missing required authentication credential. Expected OAuth 2 access token」
      → v1 **仍存在**，但需 **service account 的 OAuth2 短效 token**；Matrix `http` pusher
      只能帶**靜態** `data.auth` → **無法直接使用 v1**。
    - **後果**：pusher 註冊成功也**投遞不到**（homeserver 會拿到 404）→ 這就是
      「FCM 測試失敗」的**投遞層根因**（與上面的背景 isolate 根因是兩件事）。
    - **第五十二批處置**：①`FCM_GATEWAY_URL` 建置參數（可指定可用閘道，不需改程式）；
      ②設定 → 通知與診斷資訊明確顯示「FCM 閘道無法投遞」＋目前閘道 URL；
      ③README／PRIVACY 同步揭露。
    - **待人類決定**：走 UnifiedPush（不經 Google，建議）／自架 FCM v1 轉送端
      （需 service account 憑證 → **屬需持續維運的系統**，與藍圖限制衝突）／
      其他 Matrix 相容閘道。

- [ ] **緊急現況／求助流程 v2 已知限制（第六十六批；披露，非缺陷）**
  - **好友現況解析只看各 1:1 房「最新一則」訊息**（`Room.lastEvent`）：好友送出
    【緊急現況】／【報平安】後若又聊了其他內容，該狀態會被後續訊息覆蓋而消失
    （時間窗 `sent−5min`～`expires` 內仍可能被聊天蓋掉）→ 待人類決定是否改掃
    時間窗內全部訊息。
  - **純文字比對、無簽章驗證**：解析以 body 含標記字串（【緊急現況】／【報平安】
    ＋示警類別）為準——任何能寫進該 1:1 房的訊息（含轉發／貼上）都會被解析成
    現況；惡意偽造無法防。正式防偽需加密／簽章機制（涉加密邏輯＝必停區，
    待人類決定是否推進）。
  - **119 與「所有人」選項已移除**（人類 2026-11-17 拍板「不要做 119 了」＋本批
    「所有人移除」）：求助對象＝緊急聯絡人（詢問後送出）或手動挑選。
  - **debug build 卡頓**（第六十五批披露延續）：JIT＋assert 本身即有可觀卡頓，
    與本批無關；量測需 profile build（待人類決定）。
  - **示警測試開關**：合成示警僅本機（id 前綴 `homing-test-`、1 小時 TTL、
    重開 App 自動清）——正式示警走 NCDR feed，兩者互不干擾。

- [x] 自訂貼圖無法使用（已接線 m.sticker 收發/渲染，未實機驗證）
- [x] 好友邀請無法發送＆接收（已改 startDirectChat，待測試）
- [x] 好友掃碼沒有對應 QR Code 顯示功能
- [x] 官方裝置管理連結
- [x] 檔案開啟（fallback share_plus；另補 mimetype→副檔名，解決無副檔名附件找不到 App，待實機確認）
- [x] 沒有收回 / 刪除功能
- [x] 表情 reaction 取消（第三輪根因＝SDK `Timeline.addAggregatedEvent` 建構時回填聚合**不過濾 redacted** → DB 殘留的已收回 reaction 讓 chips 永遠顯示自己的反應／取消被打成 M_NOT_FOUND 洗版提示；改 `_reactionsOf` 以官方 `Event.redacted` 過濾＋redact 之 M_NOT_FOUND 視為已取消生效，待實機確認）（第四輪根因＝SDK 收回事件只在「目標＝room.lastEvent」（client.dart L3184-3188）或「目標仍在目前 timeline chunk」（timeline.dart L688-708 `_findEvent` 找不到即跳過、聚合樹**不清除**）兩種情況標記目標；自己的 reaction 幾乎總是早於本 chunk → 官方收回已生效但聚合殘留未標記物件 → `Event.redacted` 永不成立。修正：官方收回成功／M_NOT_FOUND 後以 session 內抑制清單 `_cancelledReactions` 在 `_reactionsOf` 吞掉自己那筆（count−1、不顯示自己已反應），重送同 emoji 即解除；**已知限制：跨 session 的 DB 殘留（重開 App 後）本輪仍未處理**，待人類實測再決定是否 kv 持久化，待實機確認）（**批次十三③完成（人類批准 2026-11-07）**：跨 session 殘留改純官方掃除——`_reactionsOf` 遭遇「自己的反應但非本 session 送出（_myReactionEvents 沒記到、也不在抑制清單）」時，背景走官方 `Timeline.fetchAggregatedEvents(targetId, RelationshipTypes.reaction)`（/relations API）：server 回權威清單、已收回 reaction 依規格被 redact（`m.relates_to` key 剝除）→ `addAggregatedEvent` 的 `_removeEventFromSet` 以新物件替換舊殘留 → `Event.redacted`／缺 key 自然不計入；若其實是仍有效的舊反應則 server 回原件照常顯示（不誤吞）。去重＝每 target 一次；SDK 成功後跳過重抓、失敗允許重試（timeline.dart `_relationRequests`）。**成本披露**：每則有你反應過的訊息每 session 至多一次背景查詢；放棄 kv 持久化方案（b/a 都不採）。APK 2014 起，待實機確認）
- [x] Spaces 仍被視為聊天室，應顯示所有可用 rooms
- [x] 部份過去訊息沒被讀取，且沒有載入更早訊息按鈕，改成只要滑動到更先前訊息，自動抓取先前訊息
- [x] 標準字型：已存舊字級值一次性下移一檔（text_scale_migrated 戳記防重複位移），需人類實機確認
- [x] 聯絡人頭像（direct chat 用 getState(RoomMember) 讀 avatar_url，避免 db LateError）
- [x] 連結到官方裝置管理頁
- [x] 公開聊天室提供搜尋功能
- [x] 首頁中「搜尋對話」應改為「搜尋聊天室」，否則容易混淆
- [x] 搜尋聊天室名稱不區分大小寫（`rooms_screen.dart` `build` 的 `filtered` 比較，`_roomTitle(r)` 與 `r.id` 皆 `.toLowerCase()` 後再 `contains(_search.toLowerCase())`，輸入英文大小寫皆命中；APK 2015 起，待人類確認）（**人類實測 APK 2015（2026-11-07）：成功**）
- [x] 通話時無法切換鏡頭
- [x] 無法更換個人頭像（根因＝無頭像時 fallback 分支沒有相機按鈕；fallback 也統一提供更換入口，待實機確認）
- [x] 螢幕分享閃退（根因＝未取得 MediaProjection 同意即啟動型別服務；改官方 Helper.requestCapturePermission 同意後再啟動＋Service try/catch，需 Android 15 實機驗證）
- [x] QR Code 顏色（QrImageView eyeStyle/dataModuleStyle 依主題亮度自動對比）
- [x] 分享檔案（圖片/貼圖/附件走 SharePlus.share(files:)）
- [x] 已讀標記＋「顯示有新訊息但讀不到先前訊息」（新根因＝本地訊息過少時 ListView 無捲動高度 → onScroll 不觸發；沿用 Room.lastEvent 目標/成功寫 guard；新增進房訊息<20 筆時主動補抓一次＋prev_batch null 時以官方 /context API 重建 timeline，待實機確認）
- [x] 自動到底按鈕（根因＝lazy ListView maxScrollExtent 估估值；改逐 frame 補跳至貼底，待實機確認）
- [x] 過去訊息（根因＝四類事件各自 reverse 串接時序錯亂＋單輪 requestHistory 停手；改單一過濾保序＋連續載 4 輪×100，待實機確認）
- [ ] 開放創作者設計主題（預設聊天室背景、圖標設計、主題色）（只有新增自訂主題色並非開放設計，是整個軟體的背景、顏色、字型、其他裝飾都能套用主題設計，可能會類似貼圖設計做 zip 檔）（批次十二①完成 v0 部分：「我的主題」＝桌布＋種子色的本機命名組合（app_settings.db v4 `themes` 表，分項選取儲存）、 appearance 頁可建立／套用／刪除；「全域聊天室背景」Colors／Your photos 兩入口（kv chat_wallpaper），per-room 背景仍優先； THEME_FORMAT.md＝格式草案（待人類審）。**未做**：圖標設計（Android 系統限制）、字型打包（字型授權待查證）、主題輪播／商店。**第五十批更新**：zip 主題包**匯入已交**（第四十一批：`app/lib/theme_pack_importer.dart`＋`theme_pack_installer.dart`；`archive` 已於第三十八批升為直接依賴，**不再需要新增依賴**），2026-11-15 實機匯入 `theme_ok.zip` 成功（「暮色（測試）#C8A2C8 · 桌布：light.png」）；第四十九批再加「同步主題到貼圖庫房間」（事件型別 `io.github.itsxiaobai.homing.theme`，Homing 自訂）。**仍待人類**：主題包 zip **格式規格定案**（`THEME_FORMAT.md` 待審）→ 對應 backlog #11／B4）
- [x] 聊天頁釘選聊天室應出現在最上方，而不是留在原地（根因＝排序只跑在 changed 分支，pin 從不重排；改 _sortRooms 統一入口＋pin 後立即重排，待實機確認）
- [x] 通話時分享螢幕視窗不一定每次都能自動調整畫面（根因＝tile 用 Cover 裁切＋觀看端本地 share flag 不成立掉進小格；改 Contain＋任一分享串流即大畫面，待實機確認）
- [x] 沒有權限發送訊息的 rooms 不應該出現傳送訊息功能（SDK 官方 `Room.canSendDefaultMessages`：power levels＋membership＋加密判斷；無權限時不渲染輸入列改只讀提示，待實機確認）
- [x] 無法取消釘選、未讀聊天室無法手動已讀（取消釘選根因＝`_writeRemote` 失敗被靜默吞掉後下一輪 sync 聯集合併「復活」釘選；改 pinned_rooms.db v2 加 `unpinned` tombstone 表；已讀＝長按選單新增「標記為已讀」走官方 `setReadMarker`＋`markUnread(false)`，待實機確認）

- [x] 貼圖以滿版大圖顯示（第四十二批修）：LINE 的貼圖為小尺寸正方圖且**無泡泡底色** → 改為 `SizedBox(110dp)`（`chat_layout.dart`；2026-11-15 實測量測 309px ÷ 2.3625 密度 ≈ 131dp → 再收窄為 110dp），圖片縮圖最大寬 55%、文字泡泡最大寬 68%（人類回饋「靠邊緣太近」）
- [x] 已編輯訊息仍顯示舊內容（第四十二批修，人類 2026-11-15 回報）：根因＝SDK 的聚合樹 `timeline.aggregatedEvents` 只在**未加密**事件加入 timeline 時建立，**E2EE 房間**的編輯事件在 sync 當下仍是 `m.room.encrypted` → 不被聚合 → 永遠顯示舊內容。修＝自建「被編輯 id → 最新編輯」對照（掃描**已解密**事件，`message_edits.dart`）＋ 套用 `m.new_content` ＋ fallback 到 SDK 官方 `getDisplayEvent`；另對最近 20 筆文字訊息抓官方 relations（`Timeline.fetchAggregatedEvents`）涵蓋更早的編輯。單元測試 5 案
- [x] 聊天列表預覽不支援 Markdown（第四十二批修，人類 2026-11-15 回報）：預覽改以官方 timeline 計算（編輯後內容 ＋ `formatted_body`），Markdown 以 `formattedMessageSpans` 渲染成 RichText（粗體等保留）
- [x] 公告與災害示警混用、舊公告永久顯示（第四十二批修，人類 2026-11-15 回報）：①**分流**——公告（聊天室釘選）改中性色 ＋「公告：」，災害示警（PWS RSS）維持紅色警示框；②公告**時效 24 小時**（過期自動消失）；③`pinnedEventIds` 順序未定義 → 改取**最新的文字訊息**（原直接取 `ids.last`）；④示警可點看詳情（原 `onTap: null`）
- [x] Matrix pusher app_id 殘留舊值（第四十一批修）：`kRingPushAppId` 仍是改名前的 `com.example.ring` → 抽到 `push_constants.dart` 的 `kPushAppId = io.github.itsxiaobai`（app_id 必須與 applicationId 一致，否則 homeserver 的推播設定指向錯誤的 App）
- [x] 貼圖包匯入時資料庫缺欄位（第四十批實機修）：`app_settings` 的 `onCreate` 漏建 v6 新欄位（只寫 `onUpgrade`）→ 匯入 INSERT 失敗（`table stickers has no column named mxc_url`）。修＝v7：`onCreate` 補欄位 ＋ 遷移改以 `PRAGMA table_info` 實際檢查（可修既有「版本號已是 6 但欄位缺漏」的資料庫）

---

Issues:

- [x] 對話滑到底時會自動跳到最上層（第四輪根因（人類重現：進房即跳頂＋滑到底被拉回頂部重抓舊訊息）＝舊→新列表「底＝高 offset」全靠估算 extent／補跳／clamp；改 Flutter 官方聊天室標準 ListView(reverse: true)：offset 0＝最新，進房零跳轉、歷史插入不動視覺位置、逐 frame 補跳／offset 補償全數移除，待實機確認）
- [x] 頭像增加移除功能（回饋修正：相機徽章改**點按**→ bottom sheet「變更頭像（相簿）／拍照／移除頭像」，移除僅有頭像時出現；「移除沒有即時更新」根因＝SDK `getUserProfile` 快取最長 1 天（client.dart L1152）→ 變更／移除後立即以官方 `CachedProfileInformation.fromProfile(outdated: true)`＋`storeUserProfile` 標記過期，待實機確認）（移除頭像應同步更新）（另一根因＝`_loadProfile` 在 avatar url==null 時直接 return，舊頭像停在畫面；已改為清空＋session 旗標 `_ownAvatarRemoved` 壓住 server profile 快取回的舊值直至下次成功更換，待實機確認）（仍失敗，如果清掉 cache 重新抓取？）（批次八實測回饋「頭像需要將軟體重開才會消失」；人類確認頭像**只出現在設定頁**。第九次修正＝旗標改**唯一權威**：①`_loadProfile` 不再「server 回 null 就自動清旗標」（Synapse cache 可能先回 null 後又回舊 url，自動清旗標＝鬼影復活破口），只在**成功設定新頭像**時解除；②kv 寫入由 `unawaited(catchError 空吞)` 改 **await＋失敗如實提示**（落盤失敗無從得知＝重開後鬼影的可能成因），待實機確認）（失敗，暫時放棄）（**批次十三重開（人類指示 2026-11-07「處理頭像移除」）＋ 找到真根因**：initState race——移除旗標 kv 載入（fire-and-forget）與 `_loadProfile()` 同時起跑，kv 晚到時 `_ownAvatarRemoved` 仍 false → 舊頭像已畫上畫面，旗標事後就位也不會再清。修＝順序保證：新 `_initAvatarState()` 先 await 旗標就位（含 setState）才抓 profile；APK 2014 起，待實機確認）（**人類實測 APK 2014/2015（2026-11-07）：失敗**——「顯示成功，重開有成功，但當下就應該消失」→ **根因已定（第十七批修）**：`settings_screen.dart` L401 `FutureBuilder(future: _profileAvatar == null ? null : Future.value(...))`——Flutter FutureBuilder 在 future 變 null 時僅把 snapshot 切成 ConnectionState.none、**data 保留**（官方 AsyncSnapshot.inState 行為）→ `snap.hasData` 恆真 → 畫面停留舊頭像；重啟 App 時 snapshot 起始為空才走 fallback 正常。修＝拆 FutureBuilder，`_profileAvatar` 直接渲染（相機徽章抽共用 `_avatarCameraBadge()`）。APK 2018 起，待實機確認）（**人類實測 APK 2018（2026-11-07）：成功**——通話中移除頭像當下即消失，不再需重開 App）
- [x] 增加隱藏 / 刪除對話功能（隱藏＝本機 app_settings.db v2 `hidden_rooms` 表＋列表底部收合區可取消；刪除＝確認後官方 `Room.leave()`＋`Room.forget()`，待實機確認）
- [x] 投票功能自己也要能按（參考 Element X 設計）（移除 `!isOwn` 條件——官方 msc3381 建立者投票無限制，「結束投票」按鈕保留，待實機確認）
- [x] 私人聊天室無法顯示使用者名稱（改官方 `Room.getLocalizedDisplayname()`（room.dart L228：name→alias→direct chat 成員名）；'Empty chat' 時退回 id，待實機確認）（回饋：聯絡人清單同步套用同一官方 API——contacts_screen 舊邏輯仍是 name→id；配上對方成員 state 即顯示好友名稱）（2026-11-05 回饋「room 內的好友名稱沒有修改到」：訊息列渲染仍是 @ID → chat_screen 新增 `_senderName` 走官方 `Room.getState(RoomMember)`→`User.asUser(room).calcDisplayname()`（SDK user.dart L97：displayname→localpart）＋原 ID 回退；訊號名／頭像 label／回覆預覽三處套用，待實機確認）
- [x] 軟體重新開啟時要求重新登入（但前一次已經登入），需要再重開（根因＝冷啟動 `init` 8 秒逾時被當成「無 session」；改逾時重試一次（12s→30s）且僅 `isLogged()==false` 才走登入，待實機確認）
- [x] 未讀訊息不應出現「顯示為未讀」（回饋修正：長按選單已讀／未讀改**互斥**——未讀只顯示「標記為已讀」、已讀只顯示「標記為未讀」（SDK 官方 `isUnread` 判斷），待實機確認）
- [x] 投票結束變成 ```Unknown message format of type "org.matrix.msc3381.poll.end"``` 沒有在原本訊息顯示票數和結果，且 Element X 沒有顯示結束（根因＝end 事件被 editable 納入→自成一行露 SDK body；且 isPoll 含 `!endedPollIds.contains` → 已結束投票退化成純文字「[投票]」。改：end 事件**不進列**（Element X 同樣隱藏 end），start 事件**恆**用 _ChatPollTile 渲染（tile 內官方 `pollEndedCompat` 顯示「已結束」＋票數），待實機確認）（回饋 2026-11-05「票數要放在最右邊」：_ChatPollTile 選項列改 Spacer 布局——選項文字靠左、票數固定行最右，待實機確認）（票數應顯示在最右邊，不是加個 tab 鍵）（批次八已實作：每列包 `SizedBox(width: double.infinity)`——Spacer 在 shrink-to-child 的 Column 收斂成 0 才會像 tab；吃滿氣泡寬後票數貼右緣，APK 2008 起，待實機確認）（恢復原先設計位置，但改成「：(num) 票」）（批次十完成：撤回批次八滿寬列（SizedBox＋Spacer），恢復緊湊排版——票數跟在選項文字後，改顯示「：N 票」（labelSmall），待實機確認）
- [x] 對話內容全部消失（人類回報 2026-11-05：一對一、加密、全部消失、重開不恢復，Element X 上仍在）。第九次根因＝`_load()` 補抓條件多一個 `messages.isNotEmpty` → **0 筆房間永不觸發補抓**；而 `prev_batch==null` 時 SDK `getTimeline()` 不打 server 直接回 0 筆（不打 server），捲動觸發的補抓又因空列表無捲動高度永不觸發 → 空房間卡死。修正（純 timeline 顯示層，不碰解密）：補抓條件改 `messages.length < 20`（0 筆也觸發）→ `_requestHistory` 內既有官方 /context 重建退路由 `room.lastEvent` bootstrap；`messages.first` 空列表取值改防護，待實機確認）（**解密案收案（2026-11-13，APK 2054；零新依賴、零自製加密）**：人類回報「重裝後私人房歷史訊息全部無法解密」（room `!3gzbN7WyrQYfSorGg2UbG_KCrJ2MUnn1lM5ET9D-K6Q`）。根因＝重裝後舊加密事件在 DB 帶 `can_request_session: true` 失敗旗標（實機 8/8），SDK 各解密路徑對帶旗標事件**永不重試**（/context 路徑 room.dart L1775-1776 只解帶旗標者；timeline 載入 timeline.dart L288 實機零解；e 級 log 拼字為 `decrpyt`、實機為零）→ 解密從未被嘗試；而 7 個 megolm session 早已自備份還原成功（7/7 IN-DB、loadFromDB valid=true）＝缺的是最後一環「有人叫用」。修＝①`ensureRoomEncryptionState`：`m.room.encryption` state 缺失時以官方 `getRoomStateWithKey` 補回（個案 state 一直在＝防禦性）；②`decryptUndecryptedEvents`（missing_key_repair.dart，chat_screen `_defaultLoadMessages` 接入）：渲染前以官方 `Encryption.decryptRoomEvent` 對每個 `m.room.encrypted` 事件補解密、**帶旗標事件一併重試**，失敗自動觸發官方 maybeAutoRequest 取鑰；③金鑰備份 `fetchKeys` 強化（backup_restore_screen）：全量端點實測漏 session（全量 5 房/46、逐房對該房另回 7）→ 對「全量缺／空」房間逐房補抓聯集。實機 2053 log `fix4: encrypted=8 ok=8 fail=0`、2054 清理版複驗全文＋圖片可讀、已翻至最早訊息；診斷碼全數移除（verbose level／_diagBackupInventory／fix4 log／fetchKeys log）。附帶定案：sync ~60s 死因＝裝置網路中斷（connection abort→DNS 失敗），非 app 邏輯。**披露**：Test in RING 回歸未截實機圖（風險極低但未複看）；全部變更未 commit）
- [x] 部份訊息抓取失敗，導致對方已經傳送（Element X 已經顯示，但顯示 not verified by its owner，且已經上傳裝置金鑰），但目標沒有收到
- [x] 應在登入成功後即詢問 recovery key 以解密，如果成功即立即解密且不須重開，失敗則顯示錯誤（批次八已實作：登入後官方 `getCryptoIdentityState()`＝initialized 且未 connected → 對話框問 recovery key／密語 → 官方 `restoreCryptoIdentity()`，成功即解密不須重開、失敗顯示錯誤可重試／略過；APK 2008 起，待實機確認）（待測試）
- [x] room 上方名稱仍為 ID，應改為使用者名稱（第九次分析：chat_screen L1402-1404 AppBar 用 `room.name.isNotEmpty ? room.name : room.id`——DM 的 `Room.name` 原始值常為空→退回 ID；修「名稱」應走批次已有官方 `Room.getLocalizedDisplayname()`（room.dart L228：name→alias→direct chat 成員名），待批准後動工）（批次十完成：AppBar 改官方 `getLocalizedDisplayname()`，'Empty chat'／異常回退 room.id 保底，待實機確認）
- [x] 下載進度＋檔案 Size（批次十二④，人類參考 new_ref/chat 162223）：檔案列加 Size 行（官方 `event.infoMap['size']`，KB／MB 人類可讀）；開啟附件＝進度對話框「下載中…／X / Y／進度列＋取消」，進度走官方 `Event.downloadAndDecryptAttachment(onDownloadProgress:)`（SDK event.dart L821/L957，加密檔同發進度）、零新依賴。**披露 v0 行為**：取消＝僅關閉對話框，背景下載照 SDK 續行完成並寫暫存（下次開啟秒開）；無 size 欄位時進度列轉圈不定值，APK 2012 起，待實機確認）
- [x] 聊天室資訊頁（批次十二③）：room_info_screen（骨架草案）＝靜音（官方 `Room.pushRuleState`/`setPushRuleState`，rooms_screen 同款判斷）、成員管理（既有 GroupMemberManageScreen）、邀請（官方 `Room.invite`）、退出聊天室（官方 leave＋forget，同 rooms_screen 刪除對話確認文案）、公告房間旗標（本機開關，⑤用）。封鎖／檢舉／非好友過濾＝程式已有畫面（上輪誤列為新功能已更正），不重複入口，APK 2012 起，待實機確認）
- [x] 緊急訊息橫幅（批次十二⑤，Phase 4.1-4.3 草案）：①聊天室內＝最新官方釘選訊息（`Room.pinnedEventIds`（room.dart L185）→`Room.getEventById`（room.dart L2225）→紅色橫幅，點擊官方 Scrollable.ensureVisible 跳轉＋尾端官方取消釘選 `setPinnedEvents`（room.dart L676））；②首頁＝公告房間（room_info「公告房間」本機開關，app_settings.db `announcement_rooms` 表）的最新官方釘選訊息橫幅，點擊開聊天室。**披露**：跳轉＝訊息在已載入分頁外（太舊）時提示捲動不假跳；Phase 4.4 自動取消釘選＋4.5 官方 bot＝**未做**（藍圖待人工決定）；橫幅觸發條件（公告房間∩最新釘選）為草案可否決，APK 2012 起，待實機確認）

- [ ] 通話容易出錯（無法發起通話、兩邊同時發起，無法互接）（筆記清單第 16 條；**第二十八批根因調查＋修**，人類拍板範圍「連③一起進本批」，零新依賴）：①同撥無法互接根因（本專案 bug，已定位）＝SDK 官方 glare 健全（voip call_session.dart L208-240：兩端同撥以 callId 字典序自動取捨勝出方向），但我們 `CallManager._onNewCall` 舊版在既有去電未結束時**直接丟棄新來電** → glare 勝出方向的來電 UI 永不浮現；修＝新 `pendingIncoming` 暫存，`activeCall` 清空後 microtask 浮現（官方 `callHasEnded` 判斷，無 Timer）。②無法發起通話根因（批次 II-c 已註記 SDK `onCallEnded` 偶不觸發）＝殘留 `activeCall` 卡死 startCall（擲「已有通話進行中」）；修＝官方 `client.onSync.stream` 掃除（每輪 sync 檢查終態即 `clearCall`／棄過期 pending，登出解除監聽）＋錯誤訊息帶狀態標籤。③來電只在 App 近活躍運作（與№14 同根）：`m.call.invite` 是房間事件要靠 sync；`push_runtime.dart` `onMessage` 原為**空實作**＝成因之一，改官方 `client.oneShotSync(timeout:10s)` 補一輪 sync（**披露：僅 App 行程仍活時有效**；行程凍結／被殺的背景冷喚醒＝第二十九批併№14 推播檢修，需對端 logcat）。④TURN 風險（SDK 官方行為，非本專案 bug）：`getIceServers()` 失敗回**空陣列**無 STUN 兜底 → 跨 NAT 可能連不上；本批以 call_screen 臨時診斷列顯示 ICE 數量＋最近通話終態（樣式草案、**下批除役**，批次十九模式）。⑤麥克風／相機 runtime 權限硬化＝人類範圍決定**未納入**（manifest 已宣告但從無 runtime 請求；已授權的舊安裝不受影響，新安裝者會踩，排後續批次）。APK 2029 起，待實機確認（glare／互接需兩端實證）
- [ ] 群組通話成員變動後僵局（兩人 mesh：實測「雙方都只看得到自己、對方畫面短暫出現幾秒後消失、兩邊鏡頭都開著、**沒有掛斷過**」；人類回報 2026-11-10 21:0x，A 端 assistant 驅動 APK 2029＋B 端 @itsxiaobai:EIXY3DdfRY；A 端全量 logcat 留存 /tmp/opencode/ring_2029_full.logcat＋截圖 /tmp/opencode/ring_2029_gc*.png）：時間線＝21:06 加入成功（kCreateAnswer→kConnecting、頂列「群組通話（2 人）」、TURN relay 候選成功 94.237.57.x＝ICE 伺服器有供且可用）、但接收統計 total_bps/recv_bw=0；**21:07:23 我端收到憑空的 kEnded＋kHangup（人類確認無人掛斷）**→ 引擎通話物件結束，UI 仍顯示 2 人＋控制列（畫面與引擎脫鉤）；SDK 反覆 `[VOIP] Waiting for @itsxiaobai:<device> to send call invite.`（官方 mesh_backend.dart L985——等既有成員送 m.call.invite）；21:08+ 成員重談判事件全被「Ignoring call event … because we do not have the call」丟棄；我方 21:11:13 手動掛斷退出乾淨（app 不崩、PID 不變）；退出後官方 SDK 於 `_onActiveSpeakerLoop`（mesh_backend.dart L343）炸 `Unhandled Exception: RTCPeerConnection::getStats: peerConnection is null`（官方 SDK 缺陷＝已 null 的 pc 上週期 getStats）。判讀＝成員 state churn（B 端 21:01/21:03 兩次成員事件＋21:07 變動）讓 mesh 兩邊互相等待：A 端等邀請、B 端對已無通話的成員續談判；媒體引擎本身（含 TURN relay/IP 路徑）通。**此為群組通話（MeshBackend）路徑，非二十八批改動的 1:1 鏈**——下批對策方向（官方 SDK 只能 App 端繞）：①kEnded 收到即同步關閉通話 UI；②成員變動後重談判的狀態顯示＋逾時引導重進；③_activeSpeakerLoop 週期 getStats 風險。及 B 端 versionCode 與 logcat 佐證。（**第二輪乾淨重跑實證 2026-11-10 21:27-21:50，雙機同版 2029、雙機 force-stop 冷啟、雙機 ADB assistant 同步驅動；截圖 /tmp/opencode/ring_A_incall2.png（雙 tile 正常）、ring_B_novideo.png（B 掉流）等**）：第一輪 A 發起＋B 加入＝兩端 kConnected（21:27:26/27）且雙向 tile 都曾正常；**約 4-5 分鐘後 B（加入端）遠端 tile 掉成灰色頭像 placeholder（21:32），A 端影像仍正常**＝單向接收掉流，且雙端 logcat **無任何 kEnded／stream removed／異常記錄**（信號層無感知，媒體層單向斷——與第一輪「recv bps=0」同型，肇因在官方 SDK 資料通道層）。第二輪 B 發起＋A 加入＝兩端 kConnected（21:49:08/09），截至 21:50 雙向 tile 正常（持續觀察中）。**「遠端掛斷後 UI 不退」二次重現**＝21:34 B 端真實掛斷（人類按紅鈕），A 端 21:34:23.692 正常收到 kEnding→kEnded→kHangup 事件鏈，**但 A 端通話 UI 仍掛全螢幕 self tile＋控制列不退出**（第二次重現；上次 21:07 為 spurious kEnded 同症狀）——首次判定此非 spurious 特異現象，而是官方 MeshBackend／call_screen 在「收到 kEnded」路徑（非「自己按掛斷」路徑）UI 不閉合的常態缺陷；自己按掛斷（call_screen 內部 pop 路徑）則乾淨退出。附帶症狀＝掛斷後聊天室頂列出現殘留「群組通話（0 人）」tile（B 端 21:37）、頂列電話 icon 因 session 殘留被吃掉（需 force-stop 才復原）、B 端 adb 座標 tap「加入通話」無效（人類手動可按——手勢／座標判讀溫差待釐清），均列入下批修。（**第三輪換邊重跑 21:44-21:57+**：B 強停冷啟後發起（音都比第一輪多一個「頂列 session 殘留」前置症狀）、A 加入＝兩端 kConnected（21:49:08/09），**截至 21:57 雙 tile 持續正常 8 分鐘、兩端零 kEnded／零掉流記錄**；人類體感「**前面卡有點久，後面有恢復**」（建立初段媒體卡頓後自恢復，logcat 無異常可對照——待 logcat 細部定時對照）；每 1-2 分鐘反覆的「Not updating _participants（member churn）」兩端皆有，**第三輪未掀翻僵局**＝churn 頻率本就存在，僵局觸發與其他條件耦合（可能＝成員實際變動／重談判路徑，非僅 churn 事件）。**人類新增需求：通話中避免關閉螢幕（wake lock 缺）**——列下批。實證 logcat 全量留存 /tmp/opencode/ring_A_round3.logcat／ring_B_round3.logcat。）

### 第二十九批前置研究（人類指示 2026-11-10「參考 Element X 和 FluffyChat 原始碼設計，不要瞎猜」）
 *(研究筆記，屬映射層外部事實；本節零程式碼變更。原始碼對照摘錄存 `/tmp/opencode/fc_legacy/`（FluffyChat legacy voip 檔案 5 個，自 GitHub raw 親抓））*

- **Element X Flutter 已下架**：element-hq org 已無 element-x-flutter（GitHub 404；Element X 現僅 Android/iOS＝native（matrix-rust-sdk＋embedded Element Call webview），與我方 Flutter/官方 dart SDK stack 不同——**只剩產品行為可參照，非程式碼參照**。"Earlier" flutter 版問世已被 Elemental 摘除（×）。Element X Android issue #4583 顯示其 webview 路徑的 keep-screen-on 也有自身缺陷）
- **FluffyChat（krille-chan/fluffychat）也已棄 mesh voip**：2026-08 `refactor: remove legacy calls`（commit c83cd72，-1300 行，改造 LiveKit MVP PR #3417已 merge）——即與我方同 SDK 路徑的 FluffyChat 也長期受 bond（#1313 Calls doesn't work／#2329）困擾，最後整段拋棄 mesh 改投 LiveKit。**意義：mesh 路徑的深層修復在官方 SDK 資料通道層，App 端只能 mitigation——與我方二十八批已知判讀一致，非猜測**
- **FluffyChat legacy 的 kEnded→UI 閉合架構**（`lib/utils/voip_plugin.dart`，parent commit e905e87）：delegate 實作 SDK `WebRTCDelegate`；`handleCallEnded(session)` 內 `overlayEntry.remove()`（1:1 通話 UI 用 OverlayEntry 而非 Navigator route，結束即拆）；1:1 的 ended 由 SDK `call_session.dart:1015` 呼叫 `delegate.handleCallEnded`（可靠）。**`handleGroupCallEnded` FluffyChat 留 TODO 空殼**（他們在 group 路徑也沒能守住）——SDK 事實（14.2.0）：`handleGroupCallEnded` **唯一呼叫點＝本端主動 `leave()`**（group_call_session.dart:166）；遠端成員離開只走 mesh_backend `_removeCall`（對外僅 `callsChanged`＋`CallRemovedEvent`，且內部 `call.hangup(shouldEmit:false)` 註解「no need to emit individual handleCallEnded on group calls」＝**SDK 永不為群組 session 對外發 ended 事件**。我方 `ring_delegate.dart` 已完整實作上述全部 delegate 入口（onCallEnded→`_onCallEnded` 清 state；onGroupCallEnded→`_onGroupCallEnded` 清 value），但**群組 session 因 SDK 無 ended 事件而永遠不觸發**＝上次 B 掛斷後 A UI 不退的根因鏈）
- **Wake lock 對照**：Android 官方文件「phone-call UI」推薦 `FLAG_KEEP_SCREEN_ON` window flag（**無需 permission、無需 plugin**，Activity 離開自動失效；telecom framework 为特殊用途 API 我方不走）＝零新依賴可行（Kotlin MainActivity＋MethodChannel）；FluffyChat legacy 用 `flutter_foreground_task`（`wakeUpScreen()`＝点亮一次非保持；另有 `wakelock_plus` 作 pubspec bump）＝**新增依賴路徑，需人類批准**

### 第二十九批草案（依據上述研究；零新依賴；草案，待人類設計／拍板）**【暫緩：人類 2026-11-10 指示「先做 LiveKit 評估」，本段保留待攻】**
1. **A｜kEnded→UI 閉合（1:1 修）**：call_screen 已訂 `session.onCallStateChanged`（1:1 路徑理應 pop；本批加 guard／log 驗證）；群組路徑＝下列 B
2. **B｜群組 lifecycle watchdog**：call_manager 增（或 call_screen 訂閱）官方欄位檢查——`activeGroupCall.value.participants`（官方 getter）／`Room.getCallMembershipsForUser`；**偵測「只剩自己／全空／membership 全部過期（isExpired 官方欄位）」→ 顯示狀態"其他人已離開"（樣式草案）→ 經批准後自動呼叫官方 `GroupCallSession.leave()`（官方唯一正常拆解路徑，會觸發 handleGroupCallEnded→UI 自清）**
3. **F｜殘留 session 清除**：同 B 之 watchdog 掃除：開 App／進房時對 `voip.groupCalls` 官方 Map 做 expired membership 判別，殘留者 hint「上通未結束」＋官方 leave() 清理（頂列電話 icon 不再被吃掉）
4. **E｜掉流偵測（臨診工具下批實作版）**：二十八批臨診列（ICE count）除役，改`RTCPeerConnection.getStats`（官方 API）每 N 秒取 inbound-rtp bytesReceived delta；0/near-0 達 5 秒 → 顯示「對方訊號不佳」提示（草案樣式）＋「重新加入」按鈕（App 端官方 hangup＋re-join）。SDK 無 App 端 renegotiation API（披露：FluffyChat/SDK 無恢復機制，無法自動修流）；二十九批不做「自動重連」，只做偵測＋引導
5. **D｜wake lock（待人類拍板二選一）**：D-1＝Kotlin MainActivity＋MethodChannel（FLAG_KEEP_SCREEN_ON，零新依賴、~10 行 native；推薦）／D-2＝wakelock_plus plugin（FluffyChat 同款，**新增依賴須批准**）
6. **spurious kEnded 記錄透明化**：diagnosticLastCallEnd 已記終態，本批加 hangupReason（官方欄位）顯示（供「憑空掛斷」事後判讀）；SDK 內部根因不動（mesh_backend 錯接）

**本批不動**：№14 推播檢修＋背景喚醒（延後）、LiveKit 支線（FluffyChat 已以此為主線，但我方 mesh 修優先）、掉流 SDK 層根因（上層不可修）。

### 第二十九批（改向，人類 2026-11-10 拍板「先做 LiveKit 評估」＋「媒體伺服器傾向第三方公益伺服器；帳戶現掛 Matrix.org」）— LiveKit 評估報告（零程式碼變更）
- **方向**：mesh 修（上方 A/B/F/E/D 草案）暫緩；群組通話評估改走 MatrixRTC/LiveKit（MSC4143＋MSC4195）。原 mesh 草案保留，何時回攻待拍板。
- **①公益伺服器（查證日 2026-11-10，實抓）**：`https://matrix.org/.well-known/matrix/client` 現公告 `org.matrix.msc4143.rtc_foci` → `{type: livekit, livekit_service_url: https://livekit-jwt.call.matrix.org}`。Element 官方 blog（2025-04 "End-to-end encrypted voice and video for self-hosted community users"）：Element 曾開放免費公共 MatrixRTC 後端已不再可持續；**matrix.org homeserver 帳號由 Matrix.org 基金會提供專用節點（LiveKit 贊助）持續可用**。→ 帳戶掛 matrix.org ＝**免自架、免家人部署維運**；媒體流經第三方（matrix.org 基金會／LiveKit 贊助基建）＝人類已知並選定的隱私決策。⚠️待查證：該公益服務長期承諾／政策細節。
- **②發現機制注意**：新通道＝MSC4519 `GET _matrix/client/unstable/org.matrix.msc4143/rtc/transports`；well-known `rtc_foci` 鍵已自 MSC4143 移除（Element Call ≥0.24 只讀 transports，Element Web 1.12.32 僅作 fallback）。matrix.org **兩者目前皆有值**；我方 `livekit_config.dart` 走 well-known（legacy 路徑）短期可用。SDK 14.2.0 **無** transports 端點（本機 grep 0 hits）——實作批建議補 transports 端點為準＋well-known 兜底。⚠️待查證：matrix.org transports 端點實際回傳（需登入 token）。
- **③SDK 14.2.0 官方整合面（本機源碼）**：`LiveKitBackend`（voip/backend/livekit_backend.dart）＝MatrixRTC 成員事件＋**E2EE 金鑰輪替全由 SDK 官方處理**（secureRandomBytes 32B key、keyRing 輪轉、ratchet、`voip.delegate.keyProvider`）；且 **e2eeEnabled 預設 true**（mesh 是 false 寫死）＝LiveKit 群組媒體為真 E2EE，比 mesh 更符合威脅模型。媒體連線本身 SDK 明文不接（`UnimplementedError('Use livekit sdk for this')`）→ **App 端必須用 livekit_client 套件**完成 Room connect／track 發布訂閱／渲染。
- **④依賴相容性（pub.dev 2.13.2 pubspec 親查）**：`livekit_client` Apache-2.0、verified publisher livekit.io；**pinned `flutter_webrtc: 1.6.3`** ＝與我方 pubspec `flutter_webrtc: ^1.6.3` 同版 → 零衝突機率高（最終以 `dart pub resolve` 實證）。環境需求 dart ≥3.10／Flutter ≥3.38，我方 sdk ^3.13.7 過關。直依 1 套＋傳遞若干（connectivity_plus／protobuf／dart_jsonwebtoken／device_info_plus 等）→ **pubspec 變更＝必須停下等批准**＋`ci/license_check.py` 清單增補。
- **⑤App 端規模參照**：FluffyChat livekit MVP（commit e1ca8ae）＝68 檔 +1354 行（含 callkit／音效／多語 i18n 全套）；Homing 既有骨架已有（`livekit_config.dart` foci 解析、`livekit_call_screen.dart` 95 行草案、聊天頁 fold menu 入口），差距集中在：JWT 取得 → livekit Room connect → tile 渲染 → 掛斷事件鏈（callkit／通知可後續批）。
- **⑥加密紅線提醒（AGENTS）**：接線 `keyProvider`／啟用 E2EE 屬「加密邏輯＋金鑰交換」必須停下區——即便全用 SDK 官方 LiveKitBackend，**動工前需人類明確批准接線方式**。
- **下一步（待拍板）**：①批准新依賴 `livekit_client`；②批准 E2EE 接線方案（SDK 官方 keyProvider 機制）；③通話 UI 設計（tile 佈局／控制列待人類設計，骨架草案先行）；④mesh 修（A/B/F/E/D，越走越遠前先修的「UI 不退／殘留 session／wake lock」）何時回攻——單獨批或併入。

### 第三十批（人類批准 2026-11-10「批准動工」）— LiveKit v0 實作（versionCode 2029→2030）
- **批准範圍**：依賴零新增（`livekit_client` 2.13.2／`wakelock_plus` 均在 pubspec，已記錄 DEPENDENCIES.md）；E2EE＝SDK 官方路徑（`LiveKitBackend`＋官方 `EncryptionKeyProvider` 介面，App 端**零自製演算法**＝純儲存↔轉發薄殼）；v0 不含來電通知／callkit／背景接聽／螢幕分享。
- **新檔 `app/lib/voip/livekit_call_manager.dart`**：JWT 官方流程（`requestOpenIdToken` → `POST {livekit_service_url}/sfu/get` body `{room, openid_token, device_id}` → `{url, jwt}`，fluffychat e1ca8ae 已證先例）→ `lk.Room(roomOptions: encryption: E2EEOptions(BaseKeyProvider))` → `connect` → `setMicrophoneEnabled/setCameraEnabled` → lk 事件驅動 UI；`RingLiveKitKeyProvider implements EncryptionKeyProvider`：`onSetEncryptionKey`→`BaseKeyProvider.setRawKey(participantId:'<userId>:<deviceId>')`＋`e2eeManager.setKeyIndex`（fluffychat 模式）、`onRatchetKey`→回空（SDK 官方 fallback 改生成新 key，上游 L146-180）、`onExportKey`→`exportKey`。
- **groupCallId 定 'lk:<room.id>'**（新）：famedly 成員 state 是同通道（`com.famedly.call.member`），mesh 端 groupCallId=room.id 會互搶 session；加入端先從房內既有 livekit membership 抽 call_id（純函式 `deriveLiveKitGroupCallIdFromContent`，有單元測試）保兩端同 id。lk 房名＝room.id（兩端一致）。
- **UI 圍欄（`call_manager.dart` `_onNewGroupCall`）**：`gc.backend is LiveKitBackend` → 不進 mesh 的 ValueNotifier（否則 main_shell 會自動彈出 mesh 群組畫面，兩套打架）。
- **`ring_delegate.dart`**：`keyProvider` 由硬寫 null 改可注入槽位（CallManager.ensureInit 注入）；mesh／1:1 行為不變。
- **`livekit_call_screen.dart`** 重寫：joining（進度）→ connected（磚格 `lk.VideoTrackRenderer`＋mic/cam 掛斷控制列）→ error／left；骨架樣式待人類設計；UI 文案無技術名詞（fold menu 標籤改「多人通話（測試）」）。
- **驗證（原文見批次報告）**：analyze 0 issue／test 164 全過＋新 11 測試／license_check exit 0／build apk 134.5MB versionCode 2030（aapt2 確認嚴格遞增）。
- **⚠️待實機驗證（APK 2030，A/B 兩機）**：①matrix.org lk-jwt-service 回應 `{url, jwt}` 實際形狀（若缺欄位會停不猜）；②lk identity 是否＝`<userId>:<deviceId>`（若 JWT identity 格式不同，媒體可連但解密失敗——資料會以磚塊黑畫面＋無聲音呈現，回報即刻修）；③famedly 成員 state 需要 `foci_active` 欄位，SDK enter 自動寫，B 端能否循 state 加入 A 端 session；④Element X 看不到這類群通（famedly flavor 恆定，已披露）。

### 第三十一批（人類批准「全部，原本的音訊裝置、螢幕分享等功能也要」＋倒數 20 秒；versionCode 2030→2031）— LiveKit 全功能移植
- **映射總表（皆官方 API／既有零依賴通路，本機源碼親查）**：說話高亮＝`ActiveSpeakersChangedEvent`；連線品質＝`ParticipantConnectionQualityUpdatedEvent`（enum unknown/lost/poor/good/excellent）；wake lock＝`wakelock_plus`；螢幕分享＝`Hardware.requestCapturePermission`（官方 MediaProjection 同意框）＋既有 `ring/screen_capture` 前景服務＋`setScreenShareEnabled`；鏡頭切換＝`LocalVideoTrack.setCameraPosition(CameraPosition)`；內建放音 fallback＝livekit `AudioManager.setSpeakerOutputPreferred(preferred,{force})`；外部裝置＝既有 `ring/permissions` 溝通裝置通道；殘留檢查＝官方 membership `isExpired` 觀察＋log；通話紀錄＝`CallLog.add`；PiP／前景服務＝既有 `PipHelper`＋`ring/call_service`；「按返回＝通話繼續」＝session 由 CallManager 持有（`getOrCreateLiveKit`/`clearLiveKit`）。
- **B（批 29 草案移植＋火種）**：「其他人已離開」倒數 **20 秒**（人類拍板）自動退出；觸發條件＝曾至少有 1 位遠端參與者加入過＋此刻 lk 遠端全空＋SDK 成員狀態查無其他人（避免發起人獨自等待誤掛）；期間有人加入即取消；自動退出後畫面 pop＋snackbar「其他人已離開，已自動結束通話」＋寫通話紀錄。
- **E**：訊號不佳（poor/lost）→ 橫幅＋「重新加入」＝官方 `leave(userTerminate:false)`＋`join()` 重跑（成員 state 由 SDK 官方 enter/leave 包辦重寫）。
- **D**：wake lock 連線中啟用、任何離場（掛斷／自動退出／rejoin）停用。
- **不移植**：批 29 草案 A（kEnded→UI 閉合）與 spurious kEnded 屬 1:1 mesh 路徑，本兩批未碰 1:1。
- **本批已知披露**：①內建放音主路走 `ring/permissions` `setCommunicationDevice`（Android 12+），fallback 才走 livekit AudioManager——兩套音訊路由可能打架（batch 20 同款回拉風險）⚠️待實機；②官方 `requestCapturePermission` 標 experimental（上游變動跟隨調整；已在碼內註明）；③螢幕分享未含系統聲音擷取（flutter_webrtc 1.6.3 上限，同摘要既有披露）；④UI 全部草案樣式待人類設計定稿。
- **交叉批註：本批未解的既有問題**：來電通知／自動彈畫面、背景接聽（v1 待辦）、transports 端點補強（批次三十 ② 建議，本批未做——仍走 well-known legacy 路徑）；mesh／1:1 路徑本批未動。

### 第三十二批（人類批准 2026-11-10「是」＋實測回饋六項；versionCode 2031→2032）— LiveKit 通話回饋修
- **回饋與映射**：①「按返回應繼續且可繼續使用（最小化後麥克風和鏡頭斷開）」＋澄清「返回後／最小化後開始卡」＝根因定案 `CallForegroundService` 型別僅 dataSync——Android 平台規則＝進背景後攝影機／麥克風擷取須掛 camera／microphone 型別前景服務，否則被停擷取（對端「全卡住」＝本端發布停擷取）。修＝manifest `FOREGROUND_SERVICE_CAMERA`＋`FOREGROUND_SERVICE_MICROPHONE`＋service multi-type（Android 14+ `FOREGROUND_SERVICE_*` 宣告＋API30+ startForeground 型別位元遮罩）；返回鍵＝自動縮 PiP（人類拍板「改成自動 PiP」——原 auto 邏輯只聽 Home lifecycle，返回鍵不觸發；PiP 期間算前台媒體續行；不可用才 pop，session 仍持有）。②「20 秒倒數沒有出現」＝原第二重確認（SDK gc.participants）被 famedly delayed-leave 殘留擋死 → 移除、lk 端單一事實來源＋`othersLeftShouldCountdown` 純函式＋4 個新測試。③「前次記憶選前後鏡頭」＝kv `lk_camera_front`（app_settings，本機 only）＋join 時載入＋flip 時寫回。④「通話進行中／正在分享螢幕通知即時、結束消失、點入可回通話」＝通知生命週期移入 manager（原畫面層 pop 後斷管）＋service 重寫（status extra／update method／contentIntent 深鏈 open_call→main_shell push LiveKitCallScreen 重用 session）。⑤「私人通話是否也用 LiveKit」＝建議是（mesh 不穩與記錄一致；E2EE 預設開），**排批 33 待另行批准**。⑥「通話表情符號」＝官方 `publishData`（topic `ring.reaction`）＋`DataReceivedEvent`；emoji 清單／飄浮樣式為草案（Element X Flutter repo 已下架＝僅產品行為參照）。
- **本批已知披露**：①表情符號走 lk 資料通道**未經 E2EE 幀加密**（v0；內容僅 emoji 非敏感；加密需求屬必停區待另案批准）；②multi-type 前景服務在 Android 14+ 部分裝置可能於系統對 camera 服務嚴格管理時受限（⚠️待實機）；③點入回通話尚未處理 PiP 中點入的展開（僅通知點入路徑）（草案待人類設計）；④通知樣式沿用系統樣板（草案，待人類設計）。
- **驗證**：analyze No issues；test 172＋1 skip（164＋新增 8）；license_check exit 0；build 134.7MB；aapt2 `versionCode='2032'`（2031→2032）。
- **⚠️待實機驗證（APK 2032）**：①回饋①：返回／最小化後對端不卡、聲畫續行；②返回自動縮 PiP；③掛斷對端 20 秒倒數；④通知即時狀態切換＋消失＋點入回通話；⑥表情雙端即時飄浮；③鏡頭記憶跨通話。實機清單已列 PROGRESS.md 批 32 節。

### 第三十三批（人類拍板 2026-11-12「改名為 Homing」＋applicationId 選 A「從 git 抓」；versionCode 2032→2033）— 全域改名 RING→Homing
- **動機（查證事實，非法律意見）**：「RING」＝Amazon（Ring LLC）註冊商標（USPTO Reg.4724984／5289328，類 9/38/42，商品敘述涵蓋 mobile 通訊 app），且執法活躍（TTAB 2020 對 RINGCHAT 異議、2021 RINGLIGHTBABY、2026 WIPO ringmexico.com.mx 域名仲裁勝）→ 人類拍板可能上架故改名 **Homing**。Homing 初查：無撞名通訊 app；USPTO 首查無 HOMING 通訊軟體註冊（命中皆尋標器／追蹤標籤等描述性片段，類別不同）。**正式商標 clearance 待商標代理人（⚠️待專業諮詢）**。
- **改名範圍**：Dart 套件名 `ring`→`homing`（42 檔 import 跟改）；namespace＋applicationId `com.example.ring`→`io.github.itsxiaobai`；Kotlin 三檔 package＋目錄搬移；iOS `PRODUCT_BUNDLE_IDENTIFIER` 同步；manifest label "Homing"；**MethodChannel 全組 `ring/`→`homing/`**（permissions/call_service/local_notifications/screen_capture/share；通知 channel id `ring_call`→`homing_call`、`ring_screen_capture`→`homing_screen_capture`；Dart＋Kotlin 兩側同步 0 殘留）——人類拍板「名稱也一起改掉」；UI 文案 8 處＋App title；根層 docs 品牌名（README/PRIVACY/SECURITY/DESIGN/THREAT_MODEL/ARCHITECTURE/DEPENDENCIES/UI_*/THEME_FORMAT）；測試一處文案跟改。
- **未改**：內部 intent extra `ring_notif_action`／`ring_call_status`（內部代號不對外）；lk 資料 topic `ring.reaction`（資料通路非品牌）。**補記（2026-11-13，人類指示「所有說明檔案的軟體名稱和其他文件也一併更新」）**：`agent*.md` 藍圖（v1.1／v1.2／v1_3）、`agent.md`、`AGENTS.md` 標題與本檔／PROGRESS 中指 app 本身的 RING 敘述已改 Homing；技術字串、批次 33 商標查證事實、人類原話引用（如「對端＝RING」）保留原樣。
- **重大影響（披露）**：**applicationId 變更＝與舊 APK 無法原地升級**——A/B 兩機須解除安裝 2032 再裝 2033，本機 app DB（聊天紀錄／本機設定）清除；homeserver 帳號在伺服器端不受影響（重新登入即可）。
- **驗證**：`flutter analyze` No issues；`flutter test` `00:31 +172 ~1: All tests passed!`（初輪 1 測試文案未跟改名，已修）；`python3 ci/license_check.py` exit 0（清單 25 項不變）；build＋aapt2 `versionCode='2033'` 見批次報告。
- **⚠️待實機驗證（APK 2033）**：全新身分安裝後全鏈回歸——登入、基本訊息收發、通知（點入／已讀／回覆）、通話（含批 32 各修）、螢幕分享、外部分享、藍牙放音；各改名 MethodChannel 兩側仍通。

### 第三十五批（人類需求清單 #1/#4/#5/#6/#13/#14；新依賴 markdown＋sqflite_common_ffi_web 經人類批准；versionCode 2034→2035）— Web/desktop＋側欄＋聊天四功能＋緊急求助流程；org 換定＋批次 33 Kotlin 缺口修復
- **#1 Web/desktop**：新平台目錄 web/linux/windows/macos；main.dart `kIsWeb` → `databaseFactoryFfiWeb`（官方 IndexedDB 後端；`web/sqflite_sw.js`＋`sqlite3.wasm` 已生成）；MainShell ≥600dp＝NavigationRail 側欄（草案待人類設計定稿）、<600 維持膠囊列（DESIGN.md §1）。**Web 白屏根因＝flutter_vodozemac 0.9.1 未宣告 web 平台、runtime `pkg/vodozemac_bindings_dart.js` 404 → `vod.init()` 卡住不返回**；修＝kIsWeb 跳過引擎初始化；**披露：Web 目前無加密**；修後瀏覽器實證：登入畫面渲染＋`sqflite_sw.js` 載入＋error 歸零。
- **#4 動圖貼圖（無聲）**：`_stickerMime` nullable 白名單（png/gif/jpg/jpeg/bmp/webp）；影片／音訊／未知型別拒收（video_player 不支援透明渲染故走 GIF 路線，經拍板）。
- **#5 無聲傳送**：content 旗標 `dev.homing.silent: true`（送出／編輯後復位）；Homing 端 `_maybeNotify` 跳過。
- **#6 緊急求助流程**：feed 主端點 `https://cbs.tw/files/rssatomfeed.xml`＋官方 `RssAtomFeeds.ashx` fallback（雙形狀相容）；地震速報／地震報告／颱風 → 輪詢偵測自動跳出三步驟求助流程（新檔 emergency_flow_screen／emergency_contacts_screen；kv `emergencyContacts`）；**119＝發訊息不撥號**、發到哪由使用者決定。
- **#13 Markdown**：kv `markdown_enabled` 預設關；送出 `format: org.matrix.custom.html`＋`formatted_body`（SDK 官方 sendEvent；HTML 不二次清毒）；新檔 markdown_message.dart 自寫白名單 parser（與 #14 共用）。
- **#14 查看原始訊息**：長按選單「查看原始訊息」→ content JSON dialog。
- **org 換定（人類拍板）**：android/iOS＝`io.github.itsxiaobai`；macOS/Linux＝`io.github.itsxiaobai.homing`；windows CompanyName＝`io.github.itsxiaobai`；manifest label「Homing」。**影響＝App 身分變更：Android 無法原地升級（解除安裝重裝、本機資料不遷移需重登）；iOS/macOS 重新簽署**。
- **批次 33 缺口修復（查證發現）**：Kotlin 端 5 個 MethodChannel 漏改（HEAD 仍 `ring/...`＝與 Dart 端 `homing/...` **原本就全斷**）＋call_service extras 不對齊（Dart 傳 `'status'`/`'room_id'`、Kotlin 讀 `ring_call_status`/`ring_call_room_id`）→ 已修；Kotlin 內部自洽 `ring_*` intent extras 不動（零風險）。flutter create 副作用（以 git remote 推導擅自改 android/ios org＋channel 字串）已逐 byte 還原、經人類確認後有意識重新套用。
- **依賴（人類批准）**：markdown（BSD-3-Clause）＋sqflite_common_ffi_web（BSD-2-Clause，連帶 transitive dev_build/pool/process_run；sqflite_common_ffi 升格 direct）。**lock 連帶刷新（人類拍板「保留 0.9.1」）**：flutter_vodozemac/vodozemac 0.9.0→0.9.1＝官方 security fix（vodozemac 0.11.2：GHSA-pqp6-f7wc-6498＋GHSA-v27v-f96q-qhjq）＋19 組 transitive 次版號（皆 constraint 內）。
- **驗證**：`flutter analyze` No issues；`flutter test` `00:35 +200 ~1: All tests passed!`（批 34 基準 175＋本批 25）；`python3 ci/license_check.py` exit 0（直接依賴 28 項）；`flutter build web` ✓（118.7s）；`flutter build apk` ✓（183.7s，135.2MB）；aapt2 `package: name='io.github.itsxiaobai' versionCode='2035'`＋label `'Homing'`（2034 跳號——批 34 APK 未出；2034 版驗證 build 亦成功＝Kotlin 搬移＋channel 修復編譯通過）。
- **⚠️待實機／待驗證**：Web 無加密＋加密房行為未驗證；Web 正式部署需 COOP/COEP headers（現僅 SharedArrayBuffer 警告）；桌面 build 工具鏈未驗證（linux 需 cmake/ninja；windows/macos 本機不可）；#5/#6/#13/#14 實機行為；APK 2035 全鏈回歸（含 Kotlin channel 修復後的通知／分享／權限／螢幕分享／來電）。

### 第三十四批（人類需求清單 #2＋#7；解讀已確認「是」；versionCode 2033→2034）— 來電側邊橫幅＋登入伺服器選項收合
- **#2 來電橫幅**：舊「來電自動彈全螢幕 route」改**右上側邊橫幅**（root overlay，透明點擊穿透不擋底下畫面）——可接聽（官方 `answerCurrent` 後展開 `CallScreen`）／拒接（官方 `rejectCurrent`）／點擊展開全螢幕；群組邀請＝加入／忽略（mesh 無拒接協定，對方逾時自收）。設定頁「通話→來電顯示」開關（kv `incoming_call_banner` 預設開）；**關＝不彈橫幅僅系統通知欄提示**。
- **附帶 bug 修復（披露）**：舊 `_onIncomingChange` 的 `activeCall == session` guard 恆真（`_onNewCall` 先設 activeCall 才設 incomingCall.value）＝**1:1 來電從未自動彈出**——橫幅重寫順帶移除。
- **#7 登入收合**：`login_screen.dart` 預設只顯示 matrix.org（預設）＋「如果有自己的伺服器，請按這裡！」（人類指定文案）連結；點開才展開自訂 homeserver 欄位與三選項 radio（註冊／登入共用同一選擇；展開後仍走既有流程）。
- **本批 v0 披露**：①橫幅僅 App 前景運作（背景 FCM 不在本批，既有披露）；②偏好關閉時的來電通知與訊息通知**共用同一通知 id**（roomKey.hashCode）＝後到覆蓋先到；③通知「開啟」＝進聊天室再由通話鈕回通話（無橫幅點入直連）；④單一橫幅不疊第二則；⑤樣式草案待人類設計定稿。
- **驗證**：analyze No issues（初輪舊 `_incomingOpen` unused 已清）；test `00:29 +175 ~1: All tests passed!`（172＋新增 3：登入收合 2＋橫幅出現/消失/偏好分流 1；`widget_test.dart` 收合斷言同步）；license_check exit 0。
- **⚠️待實機驗證（APK 2034）**：1:1 來電橫幅三鍵與點擊展開；群組邀請橫幅；偏好關閉＝通知欄提示；通知點擊進聊天室；登入收合↔展開全流程；root overlay 在聊天室／通話中畫面之上顯示正常。




Suggestions:

- [x] 第一次登入時自動上傳裝置金鑰（**人類批准 2026-11-05，範圍＝「只更動進行順序與自動化」**；零自製加密邏輯：auth.dart 新增 `ensureFirstLoginCryptoIdentity()`——官方 `getCryptoIdentityState()` 判態 → 未初始化且無既有 cross-signing／金鑰備份 account 資料 → 官方 `initCryptoIdentity()`（SDK crypto_setup_extension.dart 官方入口，自動生成 SSSS／cross-signing＋自簽；olm 裝置金鑰 SDK 內建自動上傳 olm_manager.dart L57-73）；已初始化／部份建立 → 不動避免 wipe；失敗回 null 不阻擋登入。新帳號生成的 recovery key 登入後**立即畫面顯示一次**（SelectableText＋複製鈕，human 決定），待實機確認）
- [x] 驗證裝置、診斷功能放在進階設定選項（設定頁新增「進階」分區：裝置驗證移入＋唯讀「診斷資訊」（帳號／homeserver／裝置 ID／登入狀態，SDK client 官方欄位；不含任何金鑰資料），待實機確認）
- [x] Homing 註冊完成應自動跳回登入頁，並在開始前提醒使用者需要保管好帳號密碼與 recovery key（前往網頁註冊前彈提醒「保管帳密＋recovery key」確認後才開啟瀏覽器；從瀏覽器返回 App（官方 WidgetsBindingObserver resumed）自動顯示「註冊完成後請在此頁登入」並聚焦輸入欄，待實機確認；測試契約已同步：3 個註冊測試先確認 dialog）
- [x] 主題色應要能即時改變（同既有 ringTextScale 官方 ValueNotifier 模式：main.dart 新增 ringSeedColor notifier，外觀頁選色即時套用，移除「重啟 App 後生效」，待實機確認）
- [ ] 通知功能支援（可走 FCM，沒有則 fallback，如 FCM 需要額外依賴則用軟體直接通知）（**第五十批更新**：三層通道已交（第四十一／四十二批）——①UnifiedPush（優先，不經 Google）②FCM（**需你自己的 Firebase 專案**；`google-services.json` 或 dart-define）③App 直接收（前景即時收訊；App 完全結束時**不會**有通知）。程式端已就緒：無 Firebase 專案時 App **不崩潰**、自動落到第 3 層（2026-11-15 實機確認）；2026-11-15 實機 UnifiedPush 端到端已通（偵測到 `org.unifiedpush.distributor.sunup`、取得 endpoint 並註冊 pusher，設定頁顯示「推播通道：UnifiedPush」）。**仍開**：FCM 端到端需人類提供 Firebase 專案憑證；推播一律 `event_id_only`（不含內文））（走 local）（批次八已實作 local v0 零依賴：MethodChannel→原生 NotificationManager，App 非前景才通知、去重、Android 13+ 未授權即停；**限制：無 FCM → 進程被殺無推播**；APK 2008 起，待實機確認）（待測試）（批次十二②：新增「通知設定」分區（notification_settings_screen，設定頁一般區入口）＝「顯示通知」總開關＋「顯示訊息內容」開關（關＝通知只顯示「新訊息」），偏好存 app_settings.db kv（notifications_enabled／notification_preview）；main_shell `_maybeNotify` 依總開關先擋、body 依內容開關分流。**未做**：Mentions／相簿／邀請分區＝SDK notificationCount 未分提及類型，待 SDK 官方條件；LINE 同頁的其餘區塊＝LINE 專屬不投射，APK 2012 起，待實機確認）（**修（同日，人類實測「通知功能沒辦法啟動」）**：根因＝全 App 從無 runtime 權限請求路徑——「推播通知權限」頁鈕是 `return false` 空殼、原生 show 遇未授權回 false、且 Dart 端把輪詢 `_notifSync` **永久 cancel**。修＝原生 channel 新增 `request_permission`／`check_permission`（框架 Activity.requestPermissions，零新依賴）；通知設定頁開總開關＝先請求權限（拒絕→退回＋提示系統設定路徑）＋權限狀態列；main_shell 改 `_notifyPermDenied` 旗標＋權限執行緒授予即解除（不再永久 cancel）；push_permission_screen 空殼改接同一 channel，APK 2013 起，待實機確認）（**批次十四（人類批准 2026-11-07）**：`main_shell.dart` `_notifiedCounts` 寫入即持久化到 app_settings.db kv（`notif_count_<roomId>`），initState 讀回，避免重開 App 後把「靜音前已收、未彈過」的舊訊息重新彈出（即「軟體重開後一直跳出靜音前收到的通知」的根因）；原生通知新增「已讀」（官方 `room.setReadMarker(last.eventId)`，每 read 恆送 public+private receipt）＋「回覆」（官方 `Room.sendTextEvent`，加密房 SDK 自動加密）兩個 action 按鈕，點開直接 `push` 對應 `ChatScreen`，不須先進軟體首頁；動作後自動 cancel 該房間通知＋清 kv。`MainActivity.kt` 新增 `cancel`／`notification_action` method ＋ `onCreate`/`onNewIntent` 讀取 PendingIntent extra，`pendingIntentFlags` 相容 Android 12+ `FLAG_IMMUTABLE`；APK 2015 起，待實機確認）
- [x] 支援通話放音裝置調整（參考 Discord）（通話控制列新增揚聲器／送話器切換鈕，走 flutter_webrtc 官方 `Helper.setSpeakerphoneOn`（media_stream_track_impl.dart L83 官方取代已棄用 enableSpeakerphone）；接聽後自動套用偏好，待實機確認）（參考 /LINE_ref/dc/1793614407662.jpg）（沒有專門控制的按鈕）（批次十根因＝按鈕早已在 **1:1 通話**控制列（call_screen L544-548），但**群組通話**（group_call_screen）控制列漏掉——你實測的是群組通話。補上同款按鈕：`_speakerOn` 狀態＋官方 `Helper.setSpeakerphoneOn`（加入通話後即套用偏好；切換失敗如實提示、回退 UI），位於「切換鏡頭」與「分享螢幕」之間，待實機確認）（**請依照 Discord 設計修改**）![Reference from DC](./LINE_ref/dc/1793614407662.jpg)（批次十一次完成：1:1 與群組通話的按鈕都改開 **Discord 式輸出選單**——底部 sheet「選擇音訊輸出」＋分組「這個電話」＝電話（聽筒）／喇叭兩項、radio 顯示當前選擇（骨架樣式：主題色；文案照 DC 範本格式待人類定稿）；點選後走同一官方 `Helper.setSpeakerphoneOn`，失敗提示＋UI 回退。披露：DC 分組內另有藍牙／耳機項目——官方 Helper 無裝置清單來源，現階段僅兩項，待實機確認）（待處理外部裝置）（**批次十三①完成（人類批准 2026-11-07）**：Discord sheet 新增「外部裝置」分組——官方 `navigator.mediaDevices.enumerateDevices()`（包 getSources，原生回 `AudioSwitchManager.availableAudioDevices()` 含藍牙／有線輸出）過濾 kind=audiooutput、剔除內建 speaker/earpiece，列為 radio 項；選取走官方 `Helper.selectAudioOutput(kind)`，聽筒／喇叭兩項維持 `Helper.setSpeakerphoneOn`；選內建裝置即清外部選擇；無外部裝置／查詢失敗→維持原兩項。1:1 與群組通話兩份 sheet 同步修改。**披露**：deviceId＝套件 `AudioDeviceKind` 種類名（bluetooth／wired-headset…，AudioDeviceKind.java L8-12），非特定耳機 unique id → 兩支藍牙耳機在清單同名，選擇＝「切到這一類」＝套件 1.6.3 上限；APK 2014 起，待實機確認）**（人類實測 APK 2014/2015（2026-11-07）：**失敗**——「偵測不到外部裝置＆未發揮實際作用」。根因分析（本機源碼）：①偵測——套件 Android `getSources` 的 audiooutput 條目全部來自 `AudioSwitchManager.instance.availableAudioDevices()`（MethodCallHandlerImpl.java L1849），而 AudioSwitch 的裝置清單要等 `audioSwitch.start()` 的**非同步掃描回調**後才有值，我們在 sheet 開啟當下同步呼叫 → 常回空清單；②選擇無效——`selectAudioOutput(Class)` 先檢查 `audioSessionManagementEnabled`，未啟用時**直接 no-op**（AudioSwitchManager.java L217-219）。修法方向：進通話後（引擎已啟）開 sheet，讀取失敗時 wait/重試 1–2 次＋按鈕處加 `AudioSwitchManager` 啟動確認（如套件提供）；**附帶 bug（註記同批）**：麥克風關閉時對端顯示「攝影機關閉」（指示錯置）——疑與我們批次 II⑥在 SDK `updateMuteStatus()` 之外又自行翻 `track.enabled` 的雙寫有關（call_session.dart L1235-1256 SDK 已自動 `track.enabled` 翻轉＋發 sdp_stream_metadata），待人端 App 名稱以定位 Homing↔Homing 或 Homing↔Element**（人類補答 2026-11-07：對端＝Homing（人類原話「對端＝RING」，2026-11-12 改名前））**。**第十七批修（APK 2018）**：①偵測——`_externalAudioOutputs` 空清單重試至多 5 次×600ms（原生清單要等 `AudioSwitch.start()` 非同步掃描回調就緒，AudioSwitchManager.java L163-169）＋抽出 `_enumerateAudioOutputsOnce`；②選擇——套用後單次枚舉二次驗證（選 kind 已不在清單→提示「找不到所選放音裝置，可能已斷線」＋回退），call_screen／group_call_screen 兩份 sheet 同步；③（同批同因家族）`_toggleMic`／`_toggleCamera` 移除批次 II⑥ 的手動 track.enabled 翻轉——SDK `setMicrophoneMuted`（call_session.dart L826-829）／`setLocalVideoMuted`（L749-754）經 `updateMuteStatus()`（L1235-1256）已統一翻轉 track enabled＋送 `m.call.sdp_stream_metadata`，原註解「SDK 僅設旗標」為誤判、雙寫屬多餘 desync 面。**②-B 續查（待人類 logcat）**：Homing 兩端都無任何「遠端靜音」顯示（grep 無 remoteSDPStreamMetadata／videocam_off 用法）→「攝影機被關掉」＝B 端畫面黑掉；可修缺口＝遠端流只綁一次、不響應 kFeedsChanged → 第十七批已訂閱官方 `onCallEventChanged`（kFeedsChanged→`_attachStreams()` 重查重綁）。若 APK 2018 仍復現，請對端手機 `adb logcat -d | grep -iE "voip|mute"`——SDK 會印 `Stream purpose update: ... audio_muted = true, video_muted = ...`，該行 video_muted 值可二分：true→A 端包裝旗標／track 異常；false→B 端渲染鏈（重綁修即針對此類））（**人類實測 APK 2018（2026-11-07 同日第二輪）：②-A 仍失敗、②-B 仍失敗但樣貌更新**——兩台 Homing 手機**同一分鐘（22:57）**互通同一 2 人 mesh 群組通話：手機 A 正常收到 itsxiaobai 影像（兩格皆有畫面）；手機 B 自己影像正常、遠端 tile＝灰人形 placeholder（group_call_screen.gridView L891-901：renderer 未綁或 `_hasVideo`(s)=false 二擇一）→ **單向**（A 收得到 B、B 收不到 A）。**②-A 新根因候選（本機 manifest 已查證）**：`AndroidManifest.xml` 僅有 `BLUETOOTH`＋`maxSdkVersion="30"`，**完全缺 `BLUETOOTH_CONNECT`**（Android 12+/API 31 起藍牙改 runtime 權限）→ AudioSwitch 無權限建立 BluetoothHeadset profile → `availableAudioDevices()` 永不含藍牙類 → 第十七批的重試救不了（截圖中內建兩項在列＝AudioSwitch 掃描已完成、非時序問題；藍牙是被系統擋掉這一類。中段機制 ⚠️待實機驗證）。**即時驗證（待人類執行）**：設定→應用程式→Homing→權限→「附近裝置」允許 → 重新進通話開 sheet 看是否出現藍牙項；輔以 `adb logcat -d | grep -iE "audioswitch|bluetooth"`。**②-B 判別問題（待人類回答）**：①B 聽得到 A 的聲音嗎（分「全媒體斷」vs「僅影像斷」）；②失敗時對方攝影機確定開著（A 端 22:57 截圖顯示開著）；③B 端 `adb logcat -d | grep -iE "voip|mute|audioswitch|bluetooth"`（SDK 印 `Stream purpose update: ... video_muted = true/false` 二分 A 端旗標異常 vs B 端渲染鏈）；④對端 versionCode（與已讀 ③ 共用同一答案））（**第十八批修（APK 2019；人類批准 2026-11-07「是」）——②-A 根因已定＝缺 `BLUETOOTH_CONNECT`**：`AndroidManifest.xml` 原僅 `BLUETOOTH`＋`maxSdkVersion="30"`，Android 12+（人類 dumpsys：targetSdk=36）藍牙為 runtime 權限 → AudioSwitch 無權限建立 BluetoothHeadset profile → `availableAudioDevices()` 永不含藍牙 → 重試無效（機制中段 ⚠️待實機驗證）。修＝①manifest 新增 `BLUETOOTH_CONNECT`；②MainActivity.kt `ring/permissions` channel（check/request，框架 requestPermissions，零新依賴，requestCode 4712）；③新檔 `lib/bluetooth_permission.dart`（非 Android／channel 異常不擋通話流程）；④兩份 sheet 開啟先請求再枚舉（已授權不彈框；拒絕→僅內建）；⑤空清單顯示提示「目前沒有偵測到外部放音裝置」（原樣貌靜默）。**披露**：授權前已存在的 AudioSwitch 實例不重掃——藍牙可能需重進通話一次才出現（套件無重新掃描 API）；永久拒絕時每次通話僅請求一次。**即時驗證法（不用等新 APK）**：設定→應用程式→Homing→權限→允許「附近裝置」→重進通話開 sheet）（**第十九批（人類批准 2026-11-08「是」）——②-A 排除法收斂**：人類補測證實「**有**強制停止 Homing 再重進通話」且 sheet 仍空 →「陳舊實例」理論**出局**（全新進程＋系統權限已授仍缺藍牙）；本機整檔核對 fork `AudioDeviceScanner.kt`——映射**無漏洞**（`TYPE_BLUETOOTH_SCO`＝7／`TYPE_BLUETOOTH_A2DP`＝8／Android 12+ `TYPE_BLE_HEADSET`＝26／`TYPE_BLE_SPEAKER`＝27 皆映射為 BluetoothHeadset；`registerAudioDeviceCallback` 註冊即回傳完整清單）→ 剩唯一未知數＝**Homing 進程內實際看到的系統裝置清單**。logcat 路線到此為止：`/tmp/ring_bt.log`（00:07）＝0 bytes 屬預期（fork `loggingEnabled=false`＋PID 過濾錯過重開後的新進程；AudioSwitch 全程沈默）。**診斷修（本批，APK 2020）**：`ring/permissions` channel 新增 `audio_diagnostics`（唯讀）——回傳 BLUETOOTH_CONNECT 授權狀態＋`AudioManager.getDevices(GET_DEVICES_OUTPUTS)` 原始清單＋Android 12+ 當前溝通裝置／可用溝通裝置候選／音訊模式；兩份 sheet 底部臨時診斷除錯列（草案，**根因定案後的下批移除**）。**判讀樹**：perm=granted 且原始清單有藍牙 → fork 清單維護問題 → 第二十批自建枚舉＋選擇通道；perm=granted 但原始清單無藍牙 → 框架層藏（依型別對症下藥）；perm=not-granted → 查 Gradle manifest merge。**②-B 觀察更新（2026-11-08 00:01）**：群組通話（2 人）兩格 tile 都有即時影像＋人類回報「手機端看起來正常，最多中間卡住一下」→ 記為**已修復（觀察值）**；「中間偶爾卡一下」列小註記（第十七批 kFeedsChanged 重綁修有效；持續觀察）。**對端 versionCode＝2019**（人類 2026-11-08 dumpsys；targetSdk=36）→ 已讀 ③ 的版本疑慮解除（兩端同版）；排②-A 收尾後處理）（**第二十批定案（人類批准 2026-11-08「是」）——②-A 根因確定＝fork AudioSwitch 清單維護與系統脫節；修＝自建溝通裝置枚舉＋選擇（APK 2021）**：①決定性證據＝APK 2020 診斷列（2026-11-08 00:26 截圖）——`perm=granted`＋`comm 候選: Pixel 9a (builtin_earpiece) · Pixel 9a (builtin_speaker) · user-ThinkPad-P1-Gen-3 (bluetooth_sco)`：**系統溝通裝置清單有該耳機**（同進程）而 fork 列舉常缺 → 框架沒藏藍牙，「權限」假說全排除，壞的是 fork `AudioDeviceScanner` 的 callback 狀態維護（糾纏三批）；②修（零新依賴、零新權限——BLUETOOTH_CONNECT 既有）：`ring/permissions` 新增 `list_audio_outputs`（官方 `AudioManager.getAvailableCommunicationDevices()`，Android 12+，含 isCurrent；<S supported=false）與 `set_communication_device`（官方 `setCommunicationDevice`＋**套用後回讀溝通裝置型別二次驗證**，裝置斷線 → false）；兩份 sheet「外部裝置」分組改吃自建枚舉（kind＝官方型別名 bluetooth_sco／ble_headset／wired_headset…；內建 earpiece/speaker/safe 過濾，連耳機時列出真名「user-ThinkPad-P1-Gen-3」）；`_setSpeaker`（電話／喇叭）Android 12+ 一律也走 setCommunicationDevice（builtin_earpiece／builtin_speaker）——單一路由權威，避免 fork speakerphone 旗標與系統溝通裝置兩套機制互打架；false／channel 異常 → 1.6.3 Helper 舊路徑（批次十七驗證邏輯保留）。第十九批臨時診斷除錯列**已移除**（audio_diagnostics 通道保留一輪 field 診斷工具，下批除）。③第十九批**自首 bug**：`audio_diagnostics` 漏 `diag["outputDevices"]` 賦值 → 截圖顯示「原始輸出清單: 無資料」——本批已補回（不影響當時結論，診斷主鏈＝perm＋comm 候選）。**披露（v0 上限）**：選擇以「型別」為單位（兩支同名藍牙選到同一類，批次十三慣例）；<Android 12 維持 fork 舊路徑（該機族群不受本修惠及，⚠️待有實機再驗證）；通話音訊走 HFP（bluetooth_sco），A2DP↔SCO 切換瞬間可能 0.5–1 秒停頓；**fork AudioSwitch 仍在進程內運行**——若實測出現「選完又被帶回聽筒」的回拉，下一槓桿＝AudioSwitchManager 的 audioMode／activate 時序設定（⚠️待實機）。APK 2021 起，待實機確認）（**✅ 已確認修復（人類實測 APK 2021，2026-11-08「成功」）**：sheet 列出筆電耳機、點選路由即生效——②-A 收口。轉為日常紀錄；第二十一批將 audio_diagnostics 診斷通道＋Dart helper 全段移除（兌現臨時工具承諾，不影響功能））
- [x] 訊息支援草稿功能（app_settings.db v3 新增 `drafts` 表（per-room 本機持久化）：進入聊天室還原草稿、離開自動保存、送出成功即清除，待實機確認）
- [x] 通話紀錄應同時顯示在聊天室中（timeline 過濾加入官方 `EventTypes.CallInvite`（event_types.dart L28），以 content 的官方 `video` 欄位顯示「語音／視訊通話」行；hangup/reject 不另列避免洗版；本機 call_log 另存完整紀錄，待實機確認）
- [ ] 應有顯示已讀功能（**程式碼已有**：chat_screen L1430 `_isReadByOthers`＝官方 receipts、自己的最新訊息顯示「已讀」——請人類實測若看不到，回報場合（1對1／群組）與對方 App（Element X 是否回傳／receipt 訊息），再依 SDK receipts 顯示條件修正）（都沒有看到）（批次八已實作：receipt 走 sync ephemeral 不改 lastEvent → 原只在 lastEvent 變更才 reload＝已讀永不重畫；現 `_syncSub` 比對官方 `Room.receiptState` 摘要，有變即重畫；APK 2008 起，待實機確認）（沒有看到，暫時放棄）（**批次十三重開複驗（人類指示 2026-11-07）**：唯讀重查全鏈（SDK receipts ephemeral → `LeastReceiptState` update 分 ownPrivate/ownPublic；Homing `_receiptSummary` 比對→reload；`setReadMarker` 恆送 public+private，client.dart `receiptsPublicByDefault=true`、room.dart L1751-52）＝無缺陷可修。**最可疑成因＝對方端發 private receipt**（m.read.private 依規格不對其他使用者可見 ⚠️待查證——Homing 發的是双 receipt，ELEMENT X 是否同樣待其實作）。本批無碼改；請用 APK 2013/2014 實測，若仍看不到：①回報對方 App 名稱；②`adb logcat -d | grep -iE "olm|megolm|decrypt|verify"` 貼回，再定位）（**批次十四**：`main_shell.dart` `_onNotifAction` `read` 分支走官方 `room.setReadMarker(last.eventId)`（每 read 恆送 public+private receipt，client.dart `receiptsPublicByDefault=true`、room.dart L1751-52）；通知欄「已讀」按鈕即可觸發，不須進軟體；APK 2015 起，待實機確認）**（人類實測 APK 2015（2026-11-07）：**失敗**。程式碼走的是官方 `Room.receiptState.global.otherUsers`（僅 `m.read` public receipts；**協定限制：`m.read.private` 只對同一使用者的其他裝置可見，其他使用者永遠看不到**——若對端客戶端只送 private read receipt（部分 Element 客戶端行為），Homing 無法也無法合法顯示其已讀）；仍需：①對方 App 名稱；②`adb logcat -d | grep -iE "olm|megolm|decrypt|verify|receipt"` 貼回）**（人類補答 2026-11-07：對端＝Homing（人類原話「對端＝RING」，2026-11-12 改名前）；「沒有任何已讀顯示文字或符號」；versionName=1.0.2（各批相同不可判），**versionCode 待補**——若對端 < 2015 可能根本不送 receipt，本修救不了→需先升對端 APK）。**根因重讀＋第十七批修**：發送（`setReadMarker` room.dart L1743-1756＝m.fully_read＋public receipt（`receiptsPublicByDefault` 預設 true，Homing 未覆蓋）＋private）與收受（sync ephemeral `_handleEphemerals` client.dart L2859-2883→`LatestReceiptState`；SDK sync filter 預設不排除 ephemeral）皆官方正常；缺口在**顯示側判準**——官方 `event.receipts`（event.dart L315+）要求他人 receipt eventId 與本訊息 eventId **完全相等**，但對端 markAsRead target＝其房間 lastEvent，夾帶任何後到事件（對端自己的回覆等）就永不相等→真實流程幾乎永不顯示。修＝`_isReadByOthers` 兩段判定：快路 eventId 相等＋兜底「任一他人 global receipt 的 ts ≥ 本訊息 originServerTs」（兩者皆 server 時鐘；receipt 晚於本訊息送出⟺對端讀到本訊息或更後）；receiptSummary 重畫節流沿用。APK 2018 起，待實機確認）
- [ ] 多語言支援（🔶 **第六十七批已實機稽核**：EN↔繁中即時生效，但仍中文處已盤點——首頁下拉／底列 tab／設定標題／聊天日期／聯絡人標題／診斷標籤／a11y label；靜態 112 處 `Text('中文')` 未包 `S.t` → 見 `NEXT_GOALS.md` B17。**待翻譯補齊**，非「待定義範圍」）
  - **第五十二批盤點（供人類決定範圍用；僅統計，未動工）**：`app/lib` 內含中文字面值的字串
    **1144 處、涉及 56 個 .dart 檔**（最多者：`ui/chat_screen.dart` 160、`ui/appearance_screen.dart` 101、
    `ui/settings_screen.dart` 74、`ui/rooms_screen.dart` 65、`ui/login_screen.dart` 47）。
    **目前未引入任何 i18n 框架**（`pubspec.yaml` 無 `intl`／`flutter_localizations`）→ 若要支援多語言，
    需**新增依賴**（＝**必須停下等批准**）；建議範圍選項：
    ①繁中／英文雙語全量抽取（工作量大：上述 1144 處）②先做可切換語言的骨架
    （新增 l10n 設定＋少量示範頁）③維持繁中單語（目標市場台灣）。
- [x] 修改軟體 icon（/design/drawing_icon.svg or drawing_icon_update.png）（以人類提供 design/drawing_icon.svg 經本機 inkscape 生成 5 密度啟動圖示 mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png（48/72/96/144/192px），manifest 既指 @mipmap/ic_launcher 無需改；零新依賴，待實機確認）（改成滿版 icon）（批次九修正：批次八用 `--export-area-drawing` 裁到「繪圖邊界」把**頁面下方被切掉的半圓**也裁進圖＝整顆圓＋下方露白（即「改壞」）；改 `--export-area-page` 以完整 512×512 頁面匯出＝桃底滿版、Ring 弧貼底邊（原設計），5 密度已重生成並目視驗證，待實機確認）（使用者 如果在 Android icon 圖形用方形以外的圖形就會沒辦法滿版）（批次十一次根因＝Android 8+ launcher 會遮罩（圓形／squircle），方形 PNG 永遠露不出滿版。修法＝官方 **Adaptive Icon**（零新依賴）：①新增 `mipmap-anydpi-v26/ic_launcher.xml`（背景＝`drawable/ic_launcher_background.xml` 桃色 #FFBD9F 全滿版——遮罩裁到哪都填滿＝滿版）；②前景＝Ring 圖形**去背縮入官方安全區**（108dp 畫布中央 66dp 圓＝61%），生成 5 密度 ic_launcher_foreground.png（108/162/216/324/432px，四角透明已驗證）；③舊方形 PNG 保留作 API 25- fallback，manifest 免改。**注意：Ring 在圓形遮罩下會被裁——前景擺位已縮進安全區，實機看遮罩後由你調整**，待實機確認）（**第二十一批（人類 2026-11-08「是」）——換人類新拍板 icon**：`design/drawing_icon_revert.png`（512×512；量測＝白 89.0%＋#FFBD9E 桃色 10.7%，構圖＝白底＋從畫布底升起的桃色半環）→ 本機 ImageMagick 重生成 5 密度 legacy（48/72/96/144/192，源稿構圖直譯）＋adaptive 前景 5 密度（108/162/216/324/432；圖形縮入官方 66dp 安全區、底緣貼安全區下緣）＋背景層改白 #FFFFFF（`drawable/ic_launcher_background.xml`；與前景白底無縫相接）；**iOS 未動**（人類拍板僅 Android）。待實機確認）
- [x] 新增草稿功能（未發訊息）（與「訊息支援草稿功能」同一功能：app_settings.db v3 `drafts` 表 per-room，待實機確認）
- [ ] CLI 模式（**待人類定義範圍**：CLI 要做什麼——傳訊？管理？跑在桌面終端機？）（For 電腦版終端機，後續再執行）
- [x] 訊息偵測是否有 URL 並可點選（批次十完成：純文字訊息 body 以 `_linkifiedBody` 偵測 http/https（RegExp、零新依賴）→ URL 段以可點樣式（主題色＋底線）呈現，點按走既有依賴 url_launcher `launchUrl(externalApplication)` 開外部瀏覽器；行尾標點自動剝離；解析／開啟失敗靜默；待實機確認）
- [ ] 外部分享到聊天室（任務第 2 點；**批次十三完成（人類批准 2026-11-07，參考 EX 截圖 share_EX/Screenshot_20261102-222200_labeled.png）**：舊 stub（dialog 只顯示 type／data、無房間選擇無送出）改 EX 式「Send to」：新 share_to_room_screen.dart（搜尋列＋房間列表 avatar／名稱／alias ＝官方 `getLocalizedDisplayname`／`canonicalAlias`／`avatar`＋**多選 checkbox**＋右上送出（含數量）），main_shell `_listenShareReceiver` 改 push 全頁 picker；送出＝官方 `Room.sendTextEvent(content)` 逐一送、部分失敗不中斷並回報。**披露 v0**：接收端 app_links 只帶連結／文字 uri——**檔案型分享**（圖片／檔案意圖）需 native intent 整線＝後續待人類決定；fragment 無 connection 技術已備；骨架 UI（草案樣式待人類定稿），APK 2014 起，待實機確認）
- [x] 好友控制功能（人類新增需求 2026-11-07，第十五批；**批次十五完成**：聯絡人頁好友長按 → bottom sheet 動作選單「聊天／語音通話／收藏／隱藏／刪除好友／封鎖（或解除封鎖）」（結構參考 LINE_ref/new_ref/friends/Screenshot_20261107-203147_labeled.png 截圖語意；**零新依賴**）：①收藏＝本機 kv `favorite_contacts`（JSON 收藏房間清單）+ 好友分區內收藏置頂＋尾端星形圖示；②隱藏＝沿用本機 `hidden_rooms` 表（rooms_screen 同源；聯絡人頁自此也過濾該清單）；③刪除好友＝確認對話框「要解除好友並刪除『name』嗎？」→ 官方 `Room.leave()+Room.forget()`（同 rooms_screen._deleteRoom 模式）；④封鎖／解除封鎖＝官方 `Client.ignoreUser()`／`unignoreUser()`（matrix 14.2.0 client.dart L3954/L3991，寫入官方 `m.ignored_user_list` account data；封鎖確認對話框「封鎖『name』？」＋「您將不會再收到此帳號的訊息。您可以在『封鎖名單』中解除封鎖。」→ 已封鎖好友尾端禁止符圖示），官方 getter `Client.ignoredUsers`；⑤語音通話＝官方 `CallManager.startCall(room, video: false)` → push `CallScreen`（同 chat_screen._startCall 模式，含既有通話／來電回入判定；manager 級不可用時提示「通話功能不可用」）**注意：v0 無獨立「封鎖名單」管理頁（解除封鎖＝同一好友長按選單的「解除封鎖」；獨立管理頁待後續批次）；APK 2016 起，待實機確認）（**第十八批（人類批准 2026-11-07「是，介面根據 LINE 重新設計」）**：v0 無獨立「封鎖名單」頁的缺口補上——settings_screen「一般」分區新增入口「封鎖名單」＋新檔 `blocked_users_screen.dart`，結構參考 LINE_ref/new_ref/settings/blocked_account 截圖語意（計數＋說明段落＋清單列：頭像＋名稱＋右側解除）；清單＝官方 `Client.ignoredUsers`（client.dart L3945）；解除＝官方 `Client.unignoreUser()`（第十五批同款確認框模式）；名稱／頭像＝官方 `getProfileFromUserId`（client.dart L1197，內含 1 天快取）＋官方 `Uri.getThumbnailUri`（uri_extension.dart L63）＋`authenticatedMediaSupported()` → Bearer header（批次 I 官方認證媒體路徑）；profile 查不到（離線等）→ 顯示 mxid＋首字頭像。骨架樣式／文案草案待人類定稿。LINE 專屬項不投射：Friends／Official accounts 分頁（僅使用者清單）、Select all 多選（v0 逐列解除）、「刪除後仍封鎖」LINE 特有語意（Matrix：清單即封鎖事實）。APK 2019 起，待實機確認）
- [x] 緊急訊息用 PWS 通知（人類新增需求 2026-11-07，第十六批；**批次十六 v0 完成（人類批准「先 RSS」＋三項範圍決定：僅高風險類別／僅首頁橫幅不彈通知／15 分鐘前景輪詢）**：官方 NCDR「民生示警公開資料平台」聚合 Atom feed `https://alerts.ncdr.nat.gov.tw/RssAtomFeeds.ashx`（2026-11-07 實測 HTTP 200、無需登入與金鑰；feed 自帶 `rights=Public Domain`；**查證同日：cbs.tw 第三方 mirror 停在 11-02 共 5 天未更新，官方端點為當日新鮮 → 棄 mirror 用官方**）。新檔 `app/lib/emergency_feed.dart`（dart:io HttpClient＋手寫迷你 Atom 剝析，**零新依賴**）；官方規則依循：僅取 `cap:status=Actual`（test 勿用於對外產品）＋`cap:msgType≠Cancel`＋以 entry id 去重指紋無變化不 setState＋解析 `cap:expires`（zh 本地化格式「2026/11/8 下午 11:00:00」自訂解析）過濾已過期條目；輪詢在 `main_shell.dart` `_startEmergencyPolling`（進殼即抓一次＋Timer 15 分鐘、僅前景會運行（後台 Dart timer 受系統凍結）、widget 測試環境 FLUTTER_TEST 不啟動）；顯示在 `rooms_screen.dart` 首頁緊急橫幅座（批次十二⑤機制擴充；類別＋發布機關＋時間＋摘要；僅首頁橫幅不彈通知）。**顯名＋免責（依政府資料開放授權條款第 3 條(二)顯名義務）**：橫幅下方小字「資料來源：國家災害防救科技中心 民生示警公開資料平台（政府資料開放授權條款）／示警可能延遲或不完整；緊急時請以中央氣象署及地方政府原發布管道為準」。**限制披露**：①無 FCM＝App 未開啟時收不到（無法在 App 被殺時推播）；②僅 App 前景輪詢（15 分鐘間隔，非推播即時）；③高風險白名單（v0 草案清單＝地震速報／地震報告／海嘯／颱風／淹水／土石流／疏散避難；同日 feed 實抓亦含 水庫放流/降雨/強風 類——是否納入待人類決定）為草案常數待人類增修；④完全不涉及中央氣象署 API 與授權碼；⑤聚合 feed 目前僅含中央與事業單位（檢視地方單位示警官方 FAQ 稱需會員——決定不申請會員以維持零設定）；⑥官方端點格式若改版則需同步調整（無 SLA 承諾）。APK 2017 起，待實機確認）
- [ ] 螢幕分享加入聲音分享（人類新增需求 2026-11-07；**查證（本機 flutter_webrtc 1.6.3 源碼）**：Android 端 plugin 的 `getDisplayMedia`（GetUserMediaImpl.java L584-614）只建 display video track，`audioTracks` 一律空陣列——**系統聲音擷取（MediaPlaybackCapture，API 29+）在現套件未實作**（grep playbackCapture/audioCapture 零命中）→ 要在 Android 做聲音分享必須改 plugin／引入新依賴（**依規停下待人類批准**）。可選：a) 維持現狀（螢幕影像＋手機麥克風拾音聲，披露聲音＝麥克風非系統輸出）；b) 批准 fork/改 plugin（工程量大，碰撞版控）；c) 桌面版（Phase 7）時改原生 shell 擷取（⚠️桌面端 audio 支援待查證）。人類選項：＿＿）
