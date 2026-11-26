# NEXT_GOALS.md — 待完成目標說明（2026-11-18 盤點更新）

> **用途**：把「尚待完成／待人類決定／只能實機驗收」的項目集中在一處，供之後逐項處理。
> 本檔只做**盤點與提案**，不代表已排定順序；每項動工前仍依 `AGENTS.md` 取得授權。
> 現況以 `PROGRESS.md` 最新批次為準；已知問題細節見 `known_problems.md`。
> CI：push/PR 會觸發 `license-check-and-vulnerability-scan`（analyze/test/license/osv）；
> APK 編譯僅 `workflow_dispatch` **手動**（build-apk job 恢復，但 Agent 不觸發）。

---

## G. 人類決定記錄（2026-11-18；**歷史快照**，最新狀態以 B／H 節為準）

| 項目 | 決定 | 執行狀態 |
|---|---|---|
| 68 系列 UI | **現在重新設計**（68b 聊天室起，逐批照 LINE_ref） | 🔄 進行中（第七十一批） |
| B1 對比 | 「文字已設為黑色，部份訊息仍為白色」→ 68b 統一修正：自己泡泡內文字全黑、對方泡泡全白 | 🔄 68b 處理 |
| B2 FCM | **要進行** | ✅ 已改 opt-in 預設關（見 B 節 B2）；仍缺 Firebase 憑證＋gateway |
| B3 公開化 | 完成再說 | ⬜ 晚點 |
| B4 藍圖增補 | **是**（批准照貼） | ✅ 已貼入 `agent_v1_3.md`（2.15 通話＋Web/desktop 骨架） |
| B6 貼圖整包 | 定義＝**圖片＋詳細資料 json** | ⬜ 晚點 |
| B7 主題包格式 | 晚點 | ⬜ |
| B8 顯示事件 | 「是」（顯示系統事件；具體範圍仍待你列舉） | ⬜ 待你補範圍 |
| B9 CLI | 等要做電腦版再說 | ⬜ |
| B10 分享聲音 | 暫不（晚點） | ⬜ |
| B11 橋接 | 之後獨立處理（晚點） | ⬜ |
| B12 DB 名 | 測試時先不改，**正式發布前改名** | ⬜ 發布前 |
| B13 手機號碼 | 晚點 | ⬜ |
| B14 上架／B15 Web | 晚點 | ⬜ |
| B17 i18n | **修復** | 🔄 與 68b–68f 並行 |
| A2-3 GIF 暫停 | **是**（做） | ✅ 第七十三批已做（貼圖靜態首幀開關） |
| A2-4 反應 chip 加大 | **是**（做） | 🔄 68b 一併 |
| A2-5 即時字幕 | 晚點，**標記優先解決** | ⬜ |
| A2-7 認知文案 | 晚點 | ⬜ |
| 通話錄製 | 晚點，**標記優先解決** | ⬜ |

---

## A. Agent 可完成（不編譯、不需人類決定）

| # | 項目 | 現況 | 動作 |
|---|---|---|---|
| A1 | 無障礙：所有按鈕可朗讀功能說明 | ✅ **已完成**（第五十九批）：35 個 `a11yButton` 包裹（全部有 tooltip 的 IconButton），另補 2 個缺失 tooltip（編輯自訂主題色／刪除主題）＋翻譯 | 待實機 TalkBack 驗收（C 類） |
| A2 | PRIVACY 草稿備註（離線快取明文／已刪訊息媒體） | ✅ **已完成**（第五十九批）：加入待人工覆核備註 | 待人工定稿（B 類） |
| A3 | 文件同步（PROGRESS／known_problems／DEVICE_VERIFY） | ✅ 持續 | 例行 |

> 2026-11-17 人類最終指示「**CI check 還是要走，但不再編譯**」→ CI workflow
> 恢復 push/PR 觸發（analyze/test/license/osv 每次 push 都跑）；build-apk
> 已恢復但**僅手動觸發**（Agent 不觸發）；commit 不加 `[skip ci]`。

---

## B. 需要人類決定（Agent 不自行決定；每項含建議）

| # | 目標 | 現況／阻塞 | 選項 | 建議 |
|---|---|---|---|---|
| B1 | **配色無障礙 4 組未達 WCAG AA** | 次要文字 `#808080` on 白底 3.95:1／on 搜尋列 2.33:1；白字／主文字 on 緊急紅 `#E8384F` 4.11／3.59:1（量測工具 `dart run tool/check_contrast.dart`）；CI 對比步驟為 `continue-on-error`。**第六十四批實機測試（2026-11-17）人類觀察：深色模式文字對比度也不夠**（實機截圖 `s64_*.png` 可見）→ 併入本項與 B5 定稿一起處理，本批不動 UI | ①調深次要文字（如 `#6B6B6B`）②改緊急紅（需維持「LINE 緊急紅」既定值）③大字級（≥18pt 門檻 3.0 → 4.11 可過）④**深色模式全部文字對比重測**（人類 2026-11-17 觀察） | 先處理次要文字兩組（最差 2.33:1），緊急紅維持原值並改大字級；深色重測併入 |
| B2 | **FCM 最終路徑（已改 opt-in：預設關、使用者自啟）** | 人類 2026-11-18 指示「一般人不會裝 UP，**預設 FCM**」→ 第七十七批已改 **FCM 優先（需有效 FCM_GATEWAY_URL）→ UP 備援 → App 直接送**。仍阻塞：Firebase 憑證＋可用閘道（舊 Google 端點 404） | ①你提供 Firebase 專案憑證（google-services.json 或 FCM_* dart-define）＋可用閘道 URL ②維持只有 UP | ①。**一般使用者不需任何設定**（憑證在 APK 內；只需通知權限＋Google Play 服務）；無 GMS 環境需 UP 備援 |
| B3 | **公開化收尾** | LICENSE 版權主體未填；SECURITY 信箱（你說之後）；PRIVACY／THREAT_MODEL／ARCHITECTURE 草稿未定稿；DESIGN.md 為人類維護；repo 仍 private | 逐項提供／定稿 | 先填 LICENSE 版權主體與 SECURITY 信箱（上架前置） |
| B5 | **68 系列 UI＝暫定標準（手機版），可隨時回復** | **人類裁決（2026-11-19）**：①68 系列「先複製沒關係，只是**暫時狀況**，之後會改回來」②「68 當**暫定標準**，隨時會回復」→ **不是最終定稿**；正式定稿仍是 `UI_SPEC.md`／`DESIGN.md` §4 v2（Agent 不改這兩檔）。AGENTS「最終介面由人類設計／不模仿 LINE 品牌識別」**仍有效**，68 僅為暫時覆蓋。人類 2026-11-17 原話「先全部複製…不要侷限在 Material」。分工見 **F 節**（68a 完成，APK 2069 截圖 `b68a_home.png`）；**僅 compact 手機版適用，medium／expanded 平板暫緩（D 節）** | 逐批複製：68a（已完成）→68b 聊天室→68c 聯絡人→68d 設定→68e 次要頁→68f 全域樣式；不匯入 LINE 圖片／logo／角色素材（著作權），改用自繪 path | 依 F 節順序；每批 analyze/test＋實機截圖；人類可隨時要求回復到 v2 定稿 |
| B6 | **貼圖「整包」概念／貼圖包分享 3.7** | 目前「我的貼圖」為單張（有 packId 分組）；「整包」語意未定義 | 定義整包＝可整包匯入／刪除／分享 | 待你定義 |
| B7 | **創作者主題包格式定稿** | `THEME_FORMAT.md` v1 草案（已含 colors／assets／icons 130 槽位）；風格凍結待人類 | 審閱定稿 | 待你審 |
| B8 | **顯示事件範圍** | 聊天頁系統事件（成員加入／改名等）被過濾，顯示範圍未界定 | 定義要顯示哪些 | 待你界定 |
| B9 | **CLI 模式** | 完全未定義 | 定義用途（傳訊？管理？桌面終端？） | 待你定義 |
| B10 | **螢幕分享含系統聲音** | flutter_webrtc 1.6.3 未實作 MediaPlaybackCapture → 需改 plugin／新依賴（必停） | ①維持現狀（麥克風收音）②改 plugin ③桌面版再說 | ① |
| B11 | **LINE → Matrix 橋接** | 已研究 `beeper/line`（`BRIDGE_RESEARCH.md` §一–五）；Homing 端零改動即可對接；自建橋接＝高風險＋維運。**2026-11-19 新增四項目標（BR-1～BR-4，見 `BRIDGE_RESEARCH.md` §六）**：模擬 Windows client（可能抓包）／防止擴充版掛掉的備援／對方搬遷後新帳號與原對話同步／隔離環境 PoC | ①不接入②自架第三方橋接③自建橋接作保險 | ①（你已說「不要急著使用」）；BR-1～4 先記目標，動工前需授權＋專業諮詢 |
| B12 | **DB 名 `ring` → `homing`** | `client_factory.dart` 固定 `ring.db`；改名會孤立既有本機 DB（需重登） | ①維持②改名（需遷移策略） | ①（現有裝置有資料） |
| B13 | **手機號碼查詢結論** | 你說待定；`DESIGN.md` 由你維護 | 建議寫「不做」（matrix.org 2019 起不保存對映，Synapse 不驗證手機） | 待你定 |
| B14 | **Phase 5 發布（APK 優先・F-Droid 首發）** | 人類 2026-11-23 指示：先以 **APK 發布，首發 F-Droid**；iOS／Google Play 排在後面、由人工另行決定。F-Droid 提交要求（原始碼建置、可重現性、非自由依賴等）⚠️待查證；AGPL × App Store 相容性仍**待專業諮詢**，iOS 那條維持阻塞 | ①先備齊 F-Droid 送審資料與簽章②iOS／Google Play 待人工決定 | ①進行中；②暫緩 |
| B15 | **Phase 7 桌面／Web** | Web/desktop 骨架已交；`flutter_vodozemac` 0.9.1 無 Web 實作 → **Web 端 E2EE 無解** | ①Web 不定稿②發 Notice 但不供敏感通訊③等 SDK 支援 | ②③（PRIVACY 已揭露 Web 無 E2EE） |
| B18 | **完整 UI 轉為人類可修改的前端專案** | **人類裁決（2026-11-19）**：選**①靜態 HTML/CSS/JS 原型**（零依賴、可直接改）；且提前與 68b 同步交付 | ✅ **已交付（68b）**：`design/ui_prototype/{index.html,styles.css,app.js}`——含首頁＋聊天室兩頁、可切換；改 `styles.css` 的 `:root` 即改全站色票／間距。後續 68c~f 各頁再補進原型 | 68c~f 完成時同步扩充原型的表单/列表 |
| B17 | **i18n 未完全（第六十七批實機稽核）** | 英文模式下仍中文：首頁下拉「聊天室」／底列三 tab／設定標題「設定」／聊天日期「今天」／聯絡人標題與三節標題／診斷資訊多數標籤／a11y content-desc；靜態 112 處 `Text('中文')` 未包 `S.t` | 逐頁補 `S.t`＋翻譯（詳 `PROGRESS.md` 第六十七批清單） | 依清單分批補；不需新依賴 |
| B16 | **無障礙跨類別完整化** | ✅ 第六十二批：按鈕朗讀補齊（35 a11yButton＋10 處 Semantics）。✅ 第六十三批：前庭＝`a11yReduceMotion` helper（跟隨 OS「移除動畫」，App 目前無自訂動畫＝預防性）；動作＝滑動回覆／小反應 chip 皆有長按選單替代路徑；聽覺＝通話狀態全文字顯示。**未完**見下表 A-類待辦 | 未完項如下 |

## A2-類：無障礙未完項（第六十三批盤點；需人類決策或不可現在做）

| # | 項目 | 障礙類別 | 阻塞原因／選項 |
|---|---|---|---|
| A2-1 | 配色對比 4 組未達 WCAG AA | 視覺（低視能） | 你決策（B1 同案）：調深次要文字／改緊急紅／大字級豁免 |
| A2-2 | TalkBack 實機朗讀驗收（J21） | 視覺 | 只能你那台實機 |
| A2-3 | 貼圖 GIF 自動播放的「暫停／靜態首幀」開關 | 前庭 | 需自製 GIF 幀控制（不改動一般使用者預設＝自動播放）；要新邏輯，待你點頭 |
| A2-4 | 反應 chip 觸控目標偏小（高約 24dp） | 動作 | 長按選單已有大鈕替代路徑；若要直接加大 chip＝視覺間距會變（影響一般使用者）→ 你二選一 |
| A2-5 | 視訊通話即時字幕 | 聽覺 | 需語音辨識依賴（必停，需你批准）＋延遲與成本問題；先不做 |
| A2-6 | 外接鍵盤／Switch Access 焦點順序完整盤點 | 動作 | Android 實機才能驗；程式層僅能確保 traversal 順序（Widget 樹順序已自然） |
| A2-7 | 認知：全 App 文案「簡單語言」審查 | 認知 | 文案定稿屬 UI 最終定稿（B5，人類設計）；Agent 不自行改寫定稿文案 |
| A2-8 | 日後任何新動效必須走 `a11yReduceMotion` | 前庭 | 已入規則（`a11y.dart`）；開發規範，非單次任務 |


---

## C. 只能在你那台（可編譯／實機）做 — Agent 不碰

1. ✅ `pubspec.lock` 已更新（matrix 16.0.4／intl）；release APK 版本已至 `1.0.8+2069`（由你那台建置）。
<!-- 合併結束 -->
2. **效能實測**：載入 500／2000 則 → 是否仍 ANR；讀診斷資訊「效能量測」區 `chat.load`／`chat.plan`。
3. **SDK 升級回歸**：登入／解密／自動初始化＋自我簽章／recovery 還原／貼圖庫／通話（`SDK_UPGRADE_EVAL.md` §七）。
4. **語言切換** ✅ **2026-11-17 第六十七批實機稽核完成**（English↔繁中即時生效；仍中文處清單見 `PROGRESS.md` 第六十七批／`NEXT_GOALS.md` B17）；補翻譯後再覆核。
5. **離線快取**（先看圖→飛航→再看；設定→離線快取：用量／上限／清除）。
6. **圖示覆換**（含 `icons` 的主題包→套用→底列圖示；換回無 icons 主題→還原）。
7. **TalkBack**（聽「滑到底部」「重新整理」等按鈕說明）。

---

## D. 暫緩／不做（已記錄，不主動重啟）

- **平板介面重新設計**：你 2026-11-17 指示「先照原樣，之後再改」。
- **羊和鴿子 IP 重設計**：設計類，待你的人類設計稿。
- **公開 repo push**：0.3 未結；目前 `side-project` 無寫入權限（403）→ 改推 private `homing-tmp` 供審查。
- **FCM 端到端**：無 Firebase 憑證的機無法驗；且端點已 404（見 B2）。
- **橋接**：研究完維持不接入（見 B11）。

---

## H. 後續待辦（第八十二／八十六批）
> 2026-11-20 更新。

| 項目 | 說明 | 狀態 |
|---|---|---|
| 預約訊息附件 | 第八十二批已做：本機路徑 kv＋server metadata；到期官方 sendFileEvent | ✅ |
| 預約訊息背景準點 | 仍前景 Timer＋進殼補送；App 內提供「電源／網路設定」引導；離線等連上才送。真正背景精準需 OS Alarm/WorkManager（新依賴＋維運＝必停） | 🔶 部分 |
| **自訂通知音效（人類 2026-11-20 指示）** | 人類日後想自己做聲音：**系統音效先當其中一種設定**，不是唯一。現況只有開／關（用 Android 系統現成音效）→ 需改成「音效選擇器」：①系統預設音效（現況）②靜音 ③使用者自選本機音效檔（需檔案挑選＋原生 setSound(uri)＋SQLite/kv 存路徑＋舊裝置相容）④日後 Human 自己製作的音效包（需定義格式／授權／匯入流程）。 neutrals：不強制換音效、不影響一般使用者；隱私：音效檔只在本機 | ⬜ 待辦（寫入目標，未動工） |
| 相簿 | ✅ 已做（第八十八批：`album_store.dart`＋`ui/album_screen.dart`，本機沙箱、不要求讀取所有照片權限、與記事本同在設定選單）；點選預覽／長按刪除 | ✅ |
| Homing own server | 自建 homeserver（Synapse 等）部署指引／一鍵設定；涉及維運，與藍圖限制衝突，需人類例外授權 | ⬜ 待辦 |
| 重點功能 | 「重點功能」清單內容待人類定義（目前 MVP 見 F-4） | ⬜ 待人類定義 |
| **Messenger 聊天大頭貼（許願）** | 外部回饋 2026-11-24：懷念以前 Messenger 的「聊天大頭貼」。**需求未定義**——可能是每則都顯示的大頭像／浮動 Chat Heads／頭像裝飾框，已請對方再描述；目前聊天室已有發送者頭像（同人連續只顯示一次，組頭才可點開成員資訊），頂列頭像在 LINE 版移除 | ⬜ 待需求定義（未動工） |
| **外部回饋項目（2026-11-24）** | ①測試打包／部署：已寫 `SELF_HOSTED_RUNNER.md`（日常 v8a／正式四包 SOP）②**OIDC／SSO 登入** ✅ 第一百零三批（SDK 官方 OIDC＋deep link 分流）③多帳號切換 ✅ 第一百零四批（legacy `ring.db` 保留、新帳號獨立 DB／SDK name）④QR 登入：MSC4108 草案＋SDK 16.0.4 無 API → 歡迎頁按鈕如實顯示未支援說明 | ✅／⬜ QR 待規格穩定 |

### 第一百零五～一百零七批（2026-11-25 完成）

| 項目 | 說明 | 狀態 |
|---|---|---|
| Element X 式歡迎頁 | 自繪 Homing 'H' 標誌＋標語＋QR／手動登入兩大按鈕＋建立帳號＋版本號；不抄 Element 品牌 | ✅ |
| 測試示警橫幅即時刷新 | `emergencyRefreshNotifier` → 開關後首頁立即刷新，不必等 15 分鐘輪詢 | ✅ |
| i18n 補齊 | 30 處 `Text` 包 `S.t`、19 個新英文翻譯、零重複 key | ✅ |
| 出包規則 | 日常只建 arm64-v8a；正式公開前才出三 ABI 分包＋通用整合版 | ✅ |
| 新功能測試 | OIDC callback／帳號序列化／歡迎頁／新增英譯单元测试 | ✅ |

## F. 68 系列 UI 重新設計與功能移植盤點（人類 2026-11-17／18 指示）

### F-1. 單一主題：68 系列 UI 重新設計（照 LINE_ref 複製；**暫定標準，僅手機版**）

> **主題定義**：把全 App 的視覺收斂到「乾淨的 LINE」——自繪線條 icon、LINE 色票
> 與幾何（膠囊／圓角／間距）、各頁配置照 `LINE_ref/` 對齊。一次一個子批次，
> 每批 analyze＋test＋release 實機截圖。以下為**全部**待改 UI 部位（68a 已完成）。
>
> **⚠️ 定位（人類 2026-11-19 裁決）**：68 系列只是**暫時狀況／暫定標準**，日後會改回來；
> 正式定稿仍是 `UI_SPEC.md`／`DESIGN.md` §4 v2（本主題不改那兩檔）。**僅 compact 手機版
> 需遵守；medium／expanded 平板暫緩**（D 節）。人類可隨時要求回復到 v2。

#### 已完成
| 批次 | 範圍與檔案 | 狀態 |
|---|---|---|
| **68a** | 首頁＋導覽殼：`line_style.dart`（13 自繪 icon）、`rooms_screen.dart`（頂列／搜尋膠囊／房間列字級＋未讀綠徽章）、`main_shell.dart`（compact 底列／wide Rail 自繪 icon） | ✅ 2026-11-18，APK 2069；analyze 0 issues／test 380 全過／截圖 `b68a_home.png` |

#### 待辦子批次（68b–68f）
| 批次 | 範圍 | 待改部位（檔案／元件） | 對應 LINE_ref |
|---|---|---|---|
| **68b** | 聊天室核心 | **已完成（2026-11-19）**：泡泡尾巴（`LineBubbleTail` 自繪、自己右下／他人左上）；輸入列＋頂列 icon 自繪（底層 Material icon 透明度 0 保留供 widget 測試定位）；analyze 0 issues／test 380 全過。**並同步交付 B18 原型**：`design/ui_prototype/`（首頁＋聊天室，零依賴）。其餘：頂列時鐘／日曆 icon 未換（保留 call/search/menu）、時間位置／sender 配置微調待人類目視回饋 | `new_ref/chat/`、`chat/image_preview/`、`chat/calls_history/`、`chat/poll_EX/`、`chat/sent_data_management/`、`chat/member/`、`chat/draw_pics/` |
| **68c** | 聯絡人 | ✅ 已完成（標題綠膠囊／深色搜尋／Space 4-tab／本機暱稱長按）；`contacts_screen.dart`：標題／搜尋列／四節 tab（收藏·好友·群組·公開）／分節標題與計數／好友列／FAB／Space 群組列／長按 sheet。相關 `add_friend_screen.dart`、`group_chat_create_screen.dart`、`group_chat_manage_screen.dart`、`block_user_screen.dart`、`report_user_screen.dart`、`room_info_screen.dart` | `new_ref/friends/` |
| **68d** | 設定面板 | ✅ 已完成（標題綠膠囊／FCM opt-in 開關／預約管理頁入口）；`settings_screen.dart`：標題／搜尋列／Profile 卡／分區標題與列／登出／語言 picker sheet。子頁：`appearance_screen.dart`（theme／font／wallpaper／sticker）、`notification_settings_screen.dart`、`blocked_users_screen.dart`、`hidden_rooms_screen.dart`、`profile_screen.dart`；Homing 自有子頁沿用同套語彙：`emergency_contacts_screen.dart`、`data_export_screen.dart`、`account_disable_screen.dart`、`device_management_screen.dart`、`device_listing_screen.dart`、`device_verification_dialog.dart`、`backup_restore_screen.dart`、`key_backup_recovery_screen.dart`、`multi_device_login_screen.dart`、`push_permission_screen.dart` | `new_ref/settings/`（含 blocked_account／font／hidden_account／hidden_chat／notification／privacy／profile／stickers／theme／wallpapaer） |
| **68e** | 次要頁 | 🔶 部分完成（錄製中狀態／ Compound 圖示已覆蓋；其餘外觀待目視回饋）；通話：`call_screen.dart`、`group_call_screen.dart`、`livekit_call_screen.dart`、`mute_badge_screen.dart`、`media_attach_screen.dart`；圖片預覽：`image_preview_screen.dart`；分享挑選器：`share_to_room_screen.dart`（三節分組已有，外觀待改）；搜尋：`message_search_screen.dart`、`search_filters.dart`；貼圖：`sticker_manager_screen.dart`；投票：`poll_create_screen.dart`；緊急訊息：`emergency_flow_screen.dart`、`announcement_banner.dart`、`rooms_screen.dart` 內 `_EmergencyAlertCard`（紅卡）；建立／加入房間 sheet：`room_actions.dart` | `new_ref/calls/`、`chat/call/`、`chat/image_preview/`、`share_EX/`、`chat/poll_EX/`、`dc/`（Discord 音訊選單） |
| **68f** | 登入／引導／全域樣式 | 🔶 部分完成（標題共用語彙／圖示）；`login_screen.dart`、`connect_screen.dart`、`group_encrypted_room_screen.dart`；`design_tokens.dart`（淺色 token 換 LINE 系）；`main.dart` `ringTheme` 淺色分支／字級／字型 notifier；`app_icons.dart`／`app_icons_generated.dart`（圖示槽位是否全換 `LineIconWidget`，須權衡主題包覆換）；`a11y.dart`＋全 App Semantics label 補英文（B17）；i18n 清單（底列／標題／日期／診斷標籤）隨頁補 `S.t` | 無直接 LINE 稿，沿用前幾批建立的視覺語彙 |

#### 限制（人類指示＋既有規則取交集）
- 不匯入 LINE 圖片／logo／角色貼圖（著作權）；自繪 path 取代 Material 圖示以避免 Google Chat 觀感。
- 遵守 DESIGN.md 三斷點（compact<600／medium 600–839／expanded≥840）、元件不寫死寬度。
- i18n 新字串補翻譯（B17）。
- LINE 的 Discover／Wallet／Premium／購物／音樂紅利／好友推薦／資訊流／廣告**不做假殼**（D 節／UI_SPEC 不做清單）。
- 功能面（F-2～F-4）與 UI 面的對應：P0 三項已完成，僅需 UI 強調「LINE 收錢的我們永遠免費」。
- **僅 compact 手機版套用 68 系列**；medium／expanded（平板）暫緩（D 節），68b 聊天室
  不做雙欄重構。
- 68a 新增的 LINE 綠未讀徽章 `#4CC764` 白字、**未納入 B1 的 4 組對比量測** →
  68 系列完成後須以 `dart run tool/check_contrast.dart` 重測（併入 B1）。

### F-2. 應移植到 Matrix 第三方客戶端的功能（人類 2026-11-17 提供優先序）

| 功能 | 優先 | Matrix 現況（人類提供，⚠️待查證項目照標） | Homing 現況 | 動作 |
|---|---|---|---|---|
| 收回訊息（24h+） | P0 | ✅ 原生 `redact`（無時間限制 ⚠️待查證） | ✅ 已做（收回即時更新，第五十四／五十六批） | UI 強調「無時間限制」 |
| 編輯訊息 | **P0** | ⚠️ MSC3391（draft，部分實作 ⚠️待查證） | ✅ 已做（送出＋本機立即套用，第四十二／五十六批） | 維持；UI 強調 |
| 無聲訊息 | **P0** | ❌ 不存在（custom event flag／room-level mute ⚠️待查證） | ✅ 已做（第三十五批 #5：逐次 silent 旗標） | 維持；UI 強調「永遠免費」 |
| 預約訊息 | **P1** | ❌ 不存在 | ✅ 已做（第六十九批：純 client kv＋前景 Timer；App 凍結／殺掉時不觸發，重開補送） | 純 client timer＋延遲送出；⚠️ App 前景限制（Dart timer 背景會凍結，同 RSS 輪 polling）需评估 |
| 跨平台備份 | — | ✅ 原生（E2EE key backup＋跨裝置 sync） | ✅ 已做（SSSS／cross-signing／recovery，診斷實機全 true） | 無 |
| 群組／檔案／媒體 | — | ✅ 原生（大小取決 server） | ✅ 已做 | UI 打磨（68 系列） |
| 無痕預覽（不發已讀） | P2 | ⚠️ read receipt 有，無「隱藏已讀」選項（⚠️待查證） | ✅ 已做（opt-in「無痕預覽」，預設關閉；手動標已讀仍可送） | 待實機確認（開關的路徑） |
| 稍後標為已讀 | P2 | ⚠️ 同上 | ✅ 已做（第六十九批：opt-in，延遲 30 秒，離開取消；預設關閉） | 同上 |
| 無痕收回（對方不知） | P2 | ⚠️ redact 會通知對方；需 server 端不發／client 不顯示（⚠️待查證） | ✅ 已做 **Homing 間無痕**（第七十批：Homing 私有旗標放進官方 redaction `reason`；`Event.redactedBecause` 辨識→整列不 render；本機 kv 記憶）。⛔ 其他客戶端（Element 等）**仍會顯示收回**＝跨客戶端無痕做不到 | 已在收回時提供「一般收回／無痕收回」二選一；限制如實揭露 |
| 通話錄製 | P3 | ⚠️ MatrixRTC 無錄製（⚠️待查證） | ⛔ **不能做**：需新增錄音依賴（必停）＋錄音同意／隱私判斷 | 待你取捨 |
<!-- 合併結束 -->

### F-3. 不該移植（人類清單，維持不做）

- LINE 購物／旅遊／禮物／Music 優惠：商業生態回饋，與通訊無關。
- App 字型／圖示客製化：純外觀（既有主題包已足夠，不列離場理由）。
- 100GB 雲端空間：儲存服務，非通訊功能（改用外部雲端）。

### F-4. MVP 功能集與核心賣點（人類定義，供驗收對照）

```
必做（P0）：無聲訊息 / 編輯訊息 / 收回訊息（無時間限制） → Homing 三項皆已完成 ✅
應做（P1）：預約訊息 ✅（server account data＋附件＋週期） / 群組・檔案・跨平台（已完成 ✅，只需 UI 打磨）
加分（P2）：無痕預覽 ✅ / 稍後已讀 ✅（皆 opt-in 預設關）/ 無痕收回 ✅（官方 metadata＋舊旗標 2b 相容，Homing 間）
核心賣點：「LINE 收錢的功能，我們永遠免費。」
```

### F-5. 收尾交付：完整 UI → 人類可修改的前端專案（人類 2026-11-18 指示）

- **時機**：68b～68f 全部完成、最終介面定稿**之後**才做（B18）。
- **內容**：把 68 系列成品（版面／元件階層／色票／間距／icon path／狀態）整理成
  人類可直接修改的前端專案，使「最終介面由人類設計」能實際操作，不必再透過
  Agent 改 Dart 原始碼。
- **形式（人類 2026-11-19 裁決）**：①靜態 HTML/CSS/JS 原型（已選、已交付首頁＋聊天室）。
- **地點**：`design/ui_prototype/`（零依賴，瀏覽器直接開 `index.html`；改 `styles.css`
  的 `:root` 即改色票／間距；`app.js` 控制分頁切換）。
- **限制**：沿用既有規則——不匯入 LINE 圖片／logo／角色素材；68 系列為暫定標準，
  原型亦標暫定，日後人類可回復到 v2 定稿。

---

## E. 已完成的近期目標（供對照，不必再做）

效能視覺化／量測工具、matrix SDK 16.0.4 升級（minSdk 24＝Android 7.0 釘住）、
i18n 全量（441 處／346 字串／373 譯）、離線快取方案 A（LRU／512MB／清除）、
圖示 130 槽位全部替換、無障礙按鈕朗讀、貼圖不可分享（著作權）、收回即時更新、
樂觀送出、本機編輯立即套用、FCM 端點查證、藍圖 §十五多項查證收案。
