# SDK_UPGRADE_EVAL.md — `matrix` SDK 14.2.0 → 16.0.4 升級評估

> **狀態**：評估報告（**未升級**）。依藍圖 §一「新增依賴須人工決定」＋ AGENTS.md「依賴升級需批准」，
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
| 1 | `app/lib/missing_key_repair.dart` L70 | `keyManager.maybeAutoRequest(room.id, sessionId, senderKey, …)` | `maybeAutoRequest(Room room, String sessionId, String? senderKey, …)`（第一參數改為 `Room`） | **編譯期錯誤** → 改傳 `room` |
| 2 | `app/lib/db_repair.dart` L46–56 | 掃描／清理 `box_device_keys_list` | 16.0.0「三個 box 合併為單一 `deviceKeysLists` box」 | **功能失效**（表名可能不存在）→ 需重新確認表名與清理準則 |
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
