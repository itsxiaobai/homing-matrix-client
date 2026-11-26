# SDK_UPGRADE_EVAL.md — `matrix` SDK 14.2.0 → 16.0.4 升級評估

> **狀態（2026-11-17 更新）**：**已升級**（第五十七批；人類指示「SDK 如果不會影響
> 最小支援版本就升上去」＋「SDK 要能支援 Android 7 或更低版本」）。
> 下方 §一～§三 為升級**前**的評估（保留原文），§六 為升級後的補充查證與實測待辦。
> ⚠️ `pubspec.lock` 需在可編譯機器上 `flutter pub get` 後一併更新（本機不可編譯）。

> **原始狀態**：評估報告（**未升級**）。依藍圖 §一「新增依賴須人工決定」＋ AGENTS.md「依賴升級需批准」，
> 本檔只做風險盤點與改動清單，升級動作待人類決定。
> **查證方式**：本機 pub cache 讀取 `matrix-16.0.4` 的原始碼與 `CHANGELOG.md`
> （`dart pub cache add matrix --version 16.0.4`，2026-11-15；未改動 `pubspec.yaml`）。

## 一、版本差異摘要（CHANGELOG.md）

| 版本 | 重點 |
|---|---|
| 16.0.0（2026-11-06） | **多項 BREAKING**：DB 改為單一 `deviceKeysLists` box；`maybeAutoRequest` 改收 `Room`；`prev_content` 處理變更；支援「部分初始化」crypto identity；**規格升級到 Matrix 1.19**；sqlite3 更新 |
| 16.0.1 | 允許 `sdp_transform 0.3.x`（與 `livekit_client` 相容） |
| 16.0.2（2026-11-10） | **解密後聚合事件**（`aggregate events after decryption`）；SSSS cache 複製到 secure storage；olm account 獨立 secure storage key；VoIP 重試改善 |
| 16.0.3（2026-11-10） | **「apply edits that getTimeline decrypts」**（解密後套用編輯） |
| 16.0.4（2026-11-12） | vodozemac 固定 0.9.1（與本專案目前一致 ✅）；soft logout／refresh 競態修正 |

**對本專案最有價值的兩項**：
- 16.0.2「解密後聚合事件」＋ 16.0.3「解密後套用編輯」→ **正是我們第四十二批手動修的編輯顯示問題**
  （SDK 層在解密後才聚合 `m.replace`）；我們的自建對照（`message_edits.dart`）仍可保留作為備援。
- 規格升級到 **Matrix 1.19**（＝藍圖 §十五 的規格基準），與我們的貼圖包／image packs 目標一致。

## 二、本專案需改動的點（已逐處比對原始碼）

| # | 位置 | 現況（14.2.0） | 16.0.4 | 影響 |
|---|---|---|---|---|
| 1 | `app/lib/missing_key_repair.dart` L70 | `keyManager.maybeAutoRequest(room.id, sessionId, senderKey, …)` | `maybeAutoRequest(Room room, String sessionId, String? senderKey, …)`（第一參數改為 `Room`） | **編譯期錯誤** → 改傳 `room`（**第五十七批已修**；此為 16.0.0 changelog 唯一的 **[BREAKING]** 項） |
| 2 | `app/lib/db_repair.dart` L46–56 | 掃描／清理 `box_device_keys_list` | ⚠️ **原評估有誤，已更正（2026-11-17 實查 16.0.4 原始碼）**：box 名**未變**（`matrix_sdk_database.dart` L152 `_deviceKeysListBoxName = 'box_device_keys_list'`，14.2.0 與 16.0.4 **相同**）；16.0.0 並未把三個 box 合併成單一 `deviceKeysLists` → **本項無需改動** | 無（原評估的「表名可能不存在」不成立） |
| 3 | `app/lib/message_edits.dart`（我們自建） | 自建對照 ＋ SDK `getDisplayEvent` fallback | 16.0.2 起 SDK 會在解密後聚合 → fallback 路徑更準 | **可保留**（雙保險），無需移除 |
| 4 | `app/lib/sticker_pack_store.dart` | 官方 `setRoomStateWithKey`／`setAccountData` | 官方 API 未變 | 無影響 |
| 5 | `app/lib/crypto_recovery.dart` | 官方 `restoreCryptoIdentity`／`getCryptoIdentityState` | 16.0.0 新增「部分初始化完成」能力；`initCryptoIdentity` 行為變更 | **需回歸測試**（登入→自動初始化→自我簽章→還原） |
| 6 | `app/lib/crypto_wiring.dart`／`app_settings.dart` | `MatrixSdkDatabase.init('ring', …)` | DB schema 變更（見 #2）→ **既有資料庫遷移** | **需實機驗證**（不能像一般 App 重新登入就好；舊 DB 會受影響） |
| 7 | VoIP（`app/lib/voip/*`） | matrix 官方 VoIP 模組 | 16.0.0 修正 leave/enter 競態、call key 重試 | 行為修正，**正向**；但需回歸通話流程 |
| 8 | `livekit_client 2.13.2` | 需與 SDK 16 相容 | 16.0.1 正是為此放寬 `sdp_transform` | 需重跑解析驗證 |

## 三、風險與成本

- **成本**：改動點不多（已知 2 處編譯期錯誤＋1 處 DB 邏輯失效＋數處需回歸），
  但**涉及加密與資料庫遷移**（AGENTS.md 必停區：涉及金鑰／驗證流程的修改）。
- **風險**：
  1. **DB 遷移**：`deviceKeysLists` box 合併 → 既有使用者的本機 DB 需 SDK 遷移；
     本專案另有 `db_repair.dart`（自製修復）需同步調整，且**既有解鎖的歷史訊息**能否仍解密需實機確認。
  2. **crypto identity 行為變更**：`initCryptoIdentity` 可「完成部分初始化」→ 我們的
     `ensureFirstLoginCryptoIdentity()`（登入後自動初始化＋顯示 recovery key）行為需重新驗證。
  3. **時間點**：16.0.4 是 2026-11-12 的版本（距今 3 天），上游仍活躍（每日多個 fix）。
     建議等 1–2 週再升，或升到 16.0.4 後密切觀察。
- **前置條件**：升級屬「依賴變更」→ 需你一句批准；建議另開一個批次、單獨驗收。

## 四、建議升級步驟（待批准後執行）

1. `flutter pub add matrix:^16.0.4`（升級後 `flutter pub get` 解析結果需檢查 `livekit_client` 相容性）。
2. 修 `missing_key_repair.dart`（`maybeAutoRequest(room, …)`）。
3. 重寫 `db_repair.dart` 的目標表名（先讀 16.0.4 的 DB 實作確認）。
4. `flutter analyze` → 0 問題；`flutter test` 全綠（既有 281 案）。
5. **實機升級驗收**（不可覆蓋安裝）：先用舊版登入並備份 session → 升級安裝 → 確認
   ① 能登入 ② 加密房歷史可解密 ③ 自動初始化／自我簽章 ④ recovery 還原 ⑤ 貼圖／貼圖庫 ⑥ 通話。
6. 把結果寫回 `PROGRESS.md` 與 `known_problems.md`。

## 五、查證來源

- `~/.pub-cache/hosted/pub.dev/matrix-16.0.4/CHANGELOG.md`（2026-11-12 版 16.0.4；讀取日期 2026-11-15）。
- `~/.pub-cache/hosted/pub.dev/matrix-16.0.4/lib/encryption/key_manager.dart` L220（`maybeAutoRequest` 簽名）。
- 本專案呼叫點：`app/lib/missing_key_repair.dart` L70、`app/lib/db_repair.dart` L46–56。

## 六、第五十二批補充查證（2026-11-16；pub.dev 原始碼直讀）

| 事項 | 結果 | 對升級決策的意義 |
|---|---|---|
| matrix **16.0.4** 的 image pack 支援 | **仍只有舊草案名** `im.ponies.user_emotes`／`im.ponies.emote_rooms`／`im.ponies.room_emotes`（`lib/src/utils/image_pack_extension.dart` L49／L51／L64／L73，與 14.2.0 **完全相同**） | 升級**不會**讓 SDK 支援 v1.19 穩定名 → 我們「以官方 `setRoomStateWithKey`／`setAccountData` 寫穩定名」的作法**升級後仍需保留** |
| matrix **16.0.4** 的 `encryptFile` | 仍 `import 'package:vodozemac/vodozemac.dart'` 並呼叫 `CryptoUtils.aesCtr`／`sha256`（`lib/src/utils/crypto/encrypted_file.dart` L8／L29-30） | **檔案加密仍走 rust** → 「背景 isolate 內必須先 init vodozemac」的修法在 16.x **同樣必要**（第五十一批的修法可直接沿用） |
| `flutter_vodozemac` 最新版本 | **0.9.1 就是最新版**（pub.dev 版本清單：0.5.0 → 0.9.1，無更新版） | **Web 端 E2EE 在現行官方套件下無解**（0.9.1 無 web 目錄／runtime）→ 藍圖 Phase 7.7 的結論應為「Web 不支援 E2EE（維持現狀，SDK 支援前不做）」，非「待驗證」 |

> 查證方式：2026-11-16 由 pub.dev 取 `matrix-16.0.4.tar.gz`／`flutter_vodozemac` 版本 API 實查
> （與第五十一批同法：直接讀官方原始碼，不依賴記憶）。

## 七、第五十七批：升級執行與「最低支援版本」相容性查證（2026-11-17）

### 相容性查證（人類條件：「SDK 要能支援 Android 7 或更低版本」）

| 查證項 | 結果 | 來源 |
|---|---|---|
| matrix 14.2.0 → 16.0.4 的**依賴增減** | **無新增、無移除**（22 → 22 個）；僅兩處約束變動：`sdp_transform` `^0.3.2` → `>=0.3.2 <0.5.0`（放寬上限；本專案 lock 仍解析為 0.3.2）、`vodozemac` `^0.9.0` → `^0.9.1`（已是 0.9.1） | 兩版 `pubspec.yaml` 逐條比對（pub.dev 原始碼） |
| matrix 是否為 Flutter 套件（影響 minSdk） | **純 Dart 套件**（16.0.4 與 14.2.0 的套件內**皆無 `android/` 目錄**）→ 不帶任何 Android manifest／minSdk 宣告 | 套件結構實查 |
| Dart／Flutter 工具鏈需求 | 不變（`environment: sdk: ">=3.11.0 <4.0.0"`）→ 本專案 `^3.13.7` 相容 | 兩版 `pubspec.yaml` |
| 16.0.0 的 BREAKING 項 | **只有一項**：`maybeAutoRequest` 第一參數由 `roomId` 改為 `Room`（changelog 原文：「[BREAKING] pass Room to maybeAutoRequest so it works for archived rooms too」）→ 已修（`missing_key_repair.dart`） | 16.0.0 CHANGELOG |
| 我們用到的 SDK 成員 | 以腳本比對 **161 個**成員（`client.*`／`room.*`／`encryption.*`／`keyManager.*`／`olmManager.*`／`crossSigning.*` 等）在 16.0.4 原始碼中是否存在 → 僅 5 個命中不到的皆為 **livekit 端**（`e2eeManager`／`speakers`／`connectionQuality`）或本案自訂字串，**無 SDK API 缺漏** | 腳本比對 16.0.4 原始碼 |
| 本專案 minSdk | **明確釘住 24（Android 7.0）**（`android/app/build.gradle.kts`；原為 `flutter.minSdkVersion` → 會隨 Flutter 版本漂移）→ 升級前後**皆支援 Android 7.0** | 本專案 gradle 設定 |
| `box_device_keys_list` 表名 | **未變**（14.2.0 與 16.0.4 同名）→ `db_repair.dart` **不需改動**（更正本檔 §二 #2 的舊判斷） | 兩版 `matrix_sdk_database.dart` L152 |

### 已執行的變更（第五十七批）

1. `app/pubspec.yaml`：`matrix: ^14.2.0` → `^16.0.4`（**人類批准**）。
2. `app/lib/missing_key_repair.dart`：`maybeAutoRequest(room.id, …)` → `maybeAutoRequest(room, …)`。
3. `app/android/app/build.gradle.kts`：`minSdk` 明確釘住 **24（Android 7.0）**。

### 升級後待驗收（需可編譯機器）

- [ ] `flutter pub get` → `pubspec.lock` 更新（`matrix 16.0.4`；`sdp_transform` 仍 0.3.2；`vodozemac` 0.9.1）→ **lock 檔需一併 commit**。
- [ ] `flutter analyze` → 0 問題；`flutter test` 全綠（既有 319 ＋新增 6 案）。
- [ ] `flutter build apk --release` → versionCode 遞增（2056 → 2057）、簽章與 2056 **相同**（可 `install -r` 原地升級）。
- [ ] **實機回歸（加密／DB 遷移為重點）**：① 能登入 ② 加密房歷史可解密 ③ 自動初始化＋自我簽章 ④ recovery key 還原 ⑤ 貼圖／貼圖庫 ⑥ 通話（VoIP leave/enter 競態在 16.0.0 有多項修正 → 需回歸群組通話）⑦ 本機 DB 遷移（`box_device_keys_list` 資料是否完好）。
- [ ] 16.0.2／16.0.3 新增「解密後聚合事件」「解密後套用編輯」→ 與我們第五十六批的**自建本機編輯對照**（`_localEdits` 注入 SDK 聚合樹）可能**功能重疊** → 實機確認編輯顯示仍正確（不重複套用）。
