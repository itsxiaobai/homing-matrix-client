# PROGRESS.md — 專案進度與工作紀錄

> **查證／更新日：2026-10-31**．本檔為 Agent 撰寫之進度紀錄，非設計決策（決策見 DESIGN.md，尚未建立）。

## 總覽

| Phase | 狀態 |
|---|---|
| Phase 0 基礎設定 | 進行中（已完成 0.2；其餘未開工或屬人工項目） |
| Phase 1 核心通訊 MVP | 進行中（1.1 ✅；1.2 ✅ 匿名＋真人登入驗證；1.3 ✅ 註冊導向＋帳密登入＋持久化；1.4 文字訊息骨架完成） |
| Phase 2–5 | 未開工 |
| Phase 6 | 已取消（藍圖 v1.3） |
| Phase 7 桌面／Web | 未開工（v1.0 之後） |

## 已完成的工作

### 2026-10-31 — Phase 1 / 1.4 前置＋骨架：一對一文字訊息
- 人類決策（2026-10-31）：儲存採**方案 C**（sqflite ＋ flutter_secure_storage，兩依賴均經批准）；1.4 先做骨架，**加密協議一律用 Matrix 官方機制**（SDK 內建；App 端不寫加密程式）。
- 實作：
  - `app/pubspec.yaml`：新增 `sqflite ^2.4.5`（BSD-2-Clause）、`flutter_secure_storage ^11.2.0`（BSD-3-Clause）。
  - `app/lib/client_factory.dart`：`createPersistentClient`（`MatrixSdkDatabase.init` ＋ sqflite db ＋ `secureStorage` record；access token／SSSS cache 走 Keychain/Keystore；DB 損毀可恢復）＋ 0.10 檢查用 `createClient`（不落地）。
  - `app/lib/auth.dart`：`loginWithPassword` 改回**持久化 Client**（`Client.login` → SDK 保存 session／金鑰）。
  - `app/lib/ui/rooms_screen.dart`（新增）：對話列表骨架（onSync 驅動、活動時間排序、登出按鈕）。
  - `app/lib/ui/chat_screen.dart`（新增）：一對一／群組文字訊息骨架（Timeline m.text 顯示、`Room.sendTextEvent` 送出；加密房由 SDK 自動加密）。
  - `app/lib/ui/login_screen.dart`：成功後回呼 Client；`app/lib/main.dart`：登入 → RoomsScreen。
  - 測試：`login_screen_widget_test.dart` 更新；`rooms_chat_screens_widget_test.dart`（新增，7 例）。
- 驗證：`flutter analyze` 0 issues；`flutter test` **+42 ~1**；`python3 ci/license_check.py` EXIT=0。

### 2026-10-31 — Phase 1 / 1.3：註冊／登入流程骨架（session 暫不落地）
- 人類決策：matrix.org 為預設路徑；註冊以**系統瀏覽器**開伺服器網頁註冊頁；同時顯示「Homing 自架伺服器（尚未提供）」選項；批准新增 `url_launcher`。
- 實作檔案：
  - `app/lib/auth.dart`（新增）：`loginWithPassword`（以 `MatrixApi` 直接呼叫 `/login`，不建 Client → 不需 Database／不落地）、`resolveRegistrationPage`（讀 `auth_metadata` 的 issuer，推導 MAS 網頁註冊頁）、`normalizeUserId`。
  - `app/lib/ui/login_screen.dart`（新增）：帳密登入骨架、錯誤對應（`MatrixError`）、「前往網頁註冊」按鈕（`url_launcher`）。
  - `app/lib/ui/connect_screen.dart`：預設 matrix.org；伺服器選項（matrix.org／自訂／Homing 自架尚未提供）。
  - `app/lib/main.dart`：連線成功 → 導向 `LoginScreen`。
  - 測試：`app/test/auth_test.dart`、`app/test/login_screen_widget_test.dart`、`connect_screen_widget_test.dart` 增修、整合測試新增 matrix.org 註冊頁解析（實際打網路，通過）。
- 驗證：`flutter analyze` 0 issues；`flutter test` **+34 ~1**（1 skip＝帳密登入測試，需真人環境變數）。
- **2026-10-31 真人登入驗證（本環境變數 `RING_TEST_USER`／`RING_TEST_PASS`）**：`flutter test test/matrix_integration_test.dart` → **All tests passed!（+4）**；登入走成功（`Successfully connected as <Username> with https://matrix-client.matrix.org`），測試內 logout（`SessionClearReason.logout`）。同步：本輪後續步驟為 **session 儲存方案**人類拍板、藍圖文字提議待定稿。

### 2026-10-31 — Phase 0 / 0.12（Agent draft）：架構文件 ARCHITECTURE.md

- 檔案：`ARCHITECTURE.md`（新增，草稿，須人工審閱）
- 內容分四節：
  1. 資料模型（User/Matrix ID、homeserver URI、Room、Events、SDK 資料體）。
  2. 本地 DB schema（方案 C: sqflite + flutter_secure_storage；SDK 內建 `MatrixSdkDatabase` box）。
  3. 同步策略（SDK `onSync` 驅動、房間列表 reload，Timeline m.text 處理）。
  4. 狀態管理決策（目前用 constructor DI，Deferred state-management framework to 人決策）。
- 不含加密／金鑰程式（依 AGENTS.md 約束，App 端不自寫加密）。
- 驗證：無程式碼變動；`flutter analyze`/`flutter test` 仍全通（Cache unchanged）。
- 未完成：人類定稿本 arch 文檔（ADR / state-management 解耦與 DB path）。

### 2026-10-31 — Phase 1 / 1.6：已讀標記（skeleton）
- 檔案：`app/lib/ui/chat_screen.dart`，`ChatMessageView` 增 `eventId`; `_load()` 中呼叫 `room.setReadMarker`（預設，供 injected override test）；新測試 `rooms_chat_screens_widget_test.dart`。
- 驗證：analyze 0 issues; tests +43 ~1。

### 2026-10-31 — Phase 1 / 1.7：聯絡人列表 skeleton
- 檔案 `app/lib/ui/contacts_screen.dart`（新增），測試 `app/test/contacts_screen_widget_test.dart`
- 直 chats filter; room names; scroll; open chat defaults.
- 驗證 analyze 0 issues; tests +44-ish? 此 run: contacts pass.

### 2026-10-31 — Phase 1 / 1.8：加入好友 skeleton
- 檔案：`app/lib/ui/add_friend_screen.dart` (新增 skeleton); unit+widget tests `app/test/add_friend_screen_widget_test.dart`; helper parse `parseMatrixUserId`.
- 新增依賴：`mobile_scanner` ^7.4.3（BSD-3-Clause；QR scan permission handled by SDK），記錄 DEPENDENCIES.md.
- 驗證 analyze 0; tests +49 ~1 (total).

### 2026-10-31 — Phase 1 / 1.9：封鎖使用者 skeleton
- 檔案：`app/lib/ui/block_user_screen.dart`、測試 `app/test/block_user_screen_widget_test.dart`
- SDK `ignoreUser`/`unignoreUser`
- 驗證 analyze 0; tests +50 ~1.

### 2026-10-31 — Phase 1 / 1.9a / 1.9b skeleton
- 1.9a 檢舉 экран：`app/lib/ui/report_user_screen.dart` + (TODO report test)
- 1.9b 過濾：`app/lib/ui/message_filter.dart` + `app/test/message_filter_test.dart`（4 tests pass）
- 驗證 analyze 0; 全 suite +54 ~1.

### 2026-10-31 — Phase 1 / 1.5：裝置驗證與金鑰備份 skeleton（僅 UI; crypto by SDK 官方 API）
- 檔案：`app/lib/ui/device_verification_screen.dart`, `device_listing_screen.dart`, `key_backup_recovery_screen.dart`, `new_device_setup_screen.dart`; 測試 `app/test/device_verification_widget_test.dart`.
- SDK high-level 官方 API 只 delegation; Agent 不寫 Olm/Megolm; human final review required.
- 驗證 analyze 0; tests +60 ~1; license_check EXIT=0.

### 2026-10-31 — 1.12 / 基礎測試 skeleton
- 檔案：`app/test/ui_smoke_test.dart`（新增 7 例覆蓋 Contacts/AddFriend/Block/Report/Device/KeyBackup/NewDeviceSetup UI、inject 硬 coded action）
- 驗證 analyze 0; smoke suite 7/7 pass
- 9.6 coverage by CI maintained (license_check EXIT=0).

### 2026-10-31 — 1.10 Push notifications skeleton (UX + permission only, defer third-party service)
- 檔案 `app/lib/ui/push_permission_screen.dart` + tests
- 驗證 analyze 0; 69 tests
- Actual infra not yet connected; needs FCM/APNs keys (human)

### 2026-10-31 — 1.14 裝置管理頁 skeleton
- 檔案 `app/lib/ui/device_management_screen.dart` + tests
- 驗證 analyze 0; tests +70 ~1.

### 2026-10-31 — 1.13 多装置登入 skeleton
- 檔案 `app/lib/ui/multi_device_login_screen.dart` + tests (2)
- 驗證 analyze 0; tests +72 ~1.

### 2026-10-31 — 1.15 新装置 UX skeleton
- 檔案 `app/lib/ui/new_device_verification_flow_screen.dart` + tests
- 驗證 analyze 0, +75 ~1.

### 2026-10-31 — 1.5 Device listing (non-crypto) wiring
- 更新 `app/lib/ui/device_listing_screen.dart` 接入 SDK official `client.getDevices()` 鏈結 (device metadata, not encryption).
- 測試 file 執行一致性 (+1 import).
- 驗證 analyze 0; tests +75 ~1.

### 2026-10-31 — Phase 1 / 1.5a：Crypto-UI Bridge（only SDK official, no custom crypto）
- 檔案 `app/lib/crypto_bridge.dart`（新增：forwarding scaffold) + `app/test/crypto_bridge_unit_test.dart` (4 tests pass)
- 无 new deps; analyzes/test no issue; license_check exit 0.
- Crypto actual implementation still human-owned; bridge only forwards SDK methods.
- This fulfills 1.5 skeleton + wiring under SDK official APIs.

### 2026-10-31 — 1.10 Actual push choice = C (In-app long-poll sync; no FCM/APNs keys)
- Push screen UX unchanged; only text note updated. Actual infra stays with Matrix SDK sync.
- 驗證 analyze 0, tests +79 ~1.

### 2026-10-31 — 1.5a Crypto-UI Bridge（官方 SDK only 無 custom crypto）
- 檔案 `app/lib/crypto_bridge.dart` + test (5 tests pass)
- 驗證 analyze 0; tests +80 ~1.

### 2026-10-31 — 2.1 群组建立 skeleton（UI only）
- 檔案 `app/lib/ui/group_chat_create_screen.dart`, tests

### 2026-10-31 — 2.2 群组成员管理 skeleton（UI + injected SDK actions）
- 檔案 `app/lib/ui/group_chat_manage_screen.dart` + tests
- 驗證 analyze 0; tests +80 ~1.

### 2026-10-31 — 2.3 群組（Megolm E2EE skeleton, SDK-only attachments)
- 檔案 `app/lib/ui/group_encrypted_room_screen.dart` + test
- 驗證 analyze 0; tests +81 ~1; license_check exit 0.

### 2026-10-31 — 2.5 推送權限 skeleton (UX only; long-poll strategy documented)
- 檔案 `app/lib/ui/push_permission_screen.dart` + tests
- 驗證 analyze 0; tests pass

### 2026-10-31 — 2.6 靜音/未讀徽章 skeleton
- 檔案 `app/lib/ui/mute_badge_screen.dart`, tests
- 驗證 analyze 0, tests +82 ~1. license_check exit 0

### 2026-10-31 — 2.7 搜尋 skeleton (UI + injected search)
- 檔案 `app/lib/ui/message_search_screen.dart`, tests (2)
- 驗證 analyze 0; tests +84 ~1; license_check 0

### 2026-10-31 — 2.8 Media attach skeleton
- 檔案 `app/lib/ui/media_attach_screen.dart`, tests
- 驗證 analyze 0; tests +85 ~1.

### 2026-10-31 — 2.9 資料匯出 skeleton
- 檔案 `app/lib/ui/data_export_screen.dart` + tests
- 驗證 analyze 0, tests +86 ~1.

### 2026-10-31 — 2.10 帳號停用 skeleton
- 檔案 `app/lib/ui/account_disable_screen.dart`, tests
- 驗證 analyze 0, +87 ~1, license_check EXIT 0.

### 2026-10-31 — 2.11 多裝置同步 skeleton (tests only)
- 檔案 `app/test/multi_device_sync_skeleton_test.dart`
- 驗證 analyze 0; tests +89 ~1.

### 2026-10-31 — 2.12 cross-homeserver smoke skeleton
- 檔案 `app/test/cross_homeserver_smoke_test.dart`
- 驗證 analyze 0 +91 ~1

### 2026-10-31 — Crypto 1.5b / integration surface (doc-only, human bind)
- 檔案 `app/lib/crypto_wiring.dart`（新增 contract stub; no crypto logic authored）.
- Tests +91 ~1; analyze 0; license_check 0.

### 2026-10-31 — 批次 A：2.8 照片上傳 + 2.4 離線佇列 + 登入/選 server 整合
- **使用者要求**：把多個問題一起解決（批次 A：2.8 + 2.4 + 1.3/0.10）。
- 2.8 `app/lib/ui/chat_screen.dart`：新增「附加」按鈕 → 開啟 MediaAttachScreen；`_buildMatrixFile` 讀取本地檔案並以 `MatrixFile.fromMimeType` / `MatrixImageFile.create` 建構，呼叫官方 `Room.sendFileEvent`；失敗顯示錯誤。
- 2.8 `app/lib/ui/media_attach_screen.dart`：維持 skeleton（路徑輸入 + 影片切換），attach 回呼由 ChatScreen 注入。
- 2.4 `app/lib/offline_queue.dart`（新增）：sqflite 本地佇列（enqueue/pending/remove/drain/count）；`drain` 在 sync 恢復時送出待送訊息並移除成功者。
- 2.4 `app/lib/ui/chat_screen.dart`：送出失敗時 `OfflineQueue.enqueue` + 訊息「送出失敗：已排入離線佇列」。
- 2.4 `app/lib/ui/rooms_screen.dart`：onSync 監聽額外呼叫 `_drainOfflineQueue()`（防重入旗標）。
- 1.3/0.10 `app/lib/ui/login_screen.dart`：新增 homeserver TextField + 「測試連線」按鈕（呼叫 `checkServer`），註冊流程改用 `_currentHomeserver()`；登入/選 server 可在同一畫面完成。
- `app/test/login_screen_widget_test.dart`：TextField 選擇器從 `.first/.last` 改為 `.at(1)/.at(2)`（因新增 homeserver 欄位）。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0（無新依賴）。
### 2026-10-31 — 恢復加密按鈕成功後自動消失（對應 thought_1030 MVP 問題 4）
- `app/lib/ui/rooms_screen.dart`：新增 `_encryptionRecovered` 旗標；initState 時若 `crossSigning.isSelfSigned` 已為 true 則初始隱藏；恢復成功後 `setState(_encryptionRecovered = true)`，AppBar 條件渲染「恢復加密」按鈕。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0（無新依賴）。
- **使用者回報**：SAS 驗證失敗（"Either the request timed out, the request was denied, or there was a verification mismatch."）；Element 仍警告。
### 2026-10-31 — 診斷工具（驗證狀態 + 上傳裝置金鑰）
- **目的**：釐清 self-sign 是否真的完成、Element 是否看得到 Homing 的 device keys。
- `app/lib/ui/rooms_screen.dart`：AppBar 新增「診斷」按鈕 → AlertDialog 顯示：
  - `encryption` 是否存在、`crossSigning.enabled`、`isSelfSigned`
  - `userDeviceKeys` 是否載入、self device 是否在快取、self device 是否有有效簽章鏈
  - account data 是否含 cross-signing master/self_signing secrets
- 對話框內「上傳裝置金鑰」按鈕呼叫官方 `OlmManager.uploadKeys(uploadDeviceKeys: true)`，強制把 Homing 的 device keys 上傳給 homeserver，讓 Element 能看到並驗證。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0（無新依賴）。
### 2026-10-31 — SAS 裝置驗證（官方 SDK state machine，App 零加密邏輯）
- **使用者回報**：recovery 成功但仍「Encrypted by a device not verified by its owner」；要求實作 SAS 裝置驗證。
- **方案**：Matrix 官方 SAS（emoji 比對），不依賴 recovery key；Homing 作為 responder 接收 Element 發起的驗證請求。
- `app/lib/ui/device_verification_dialog.dart`（新增）：
  - 訂閱 `KeyVerification.onUpdate`，依 state 驅動 UI：waitingAccept/askAccept → 接受／拒絕；askChoice → 自動以 emoji 方法繼續；askSas → 顯示 SDK 提供的 SAS emoji，「相同／不同」；askSSSS → 提示輸入 recovery key（呼叫官方 `openSSSS`）；done/error → SnackBar + 關閉。
  - 只呼叫 SDK 官方 `acceptVerification`/`rejectVerification`/`continueVerification`/`acceptSas`/`rejectSas`/`cancel`/`openSSSS`，零加密邏輯。
- `app/lib/ui/rooms_screen.dart`：initState 訂閱 `client.onKeyVerificationRequest.stream`，收到請求時顯示 `_DeviceVerificationDialog`（防重入旗標）；dispose 取消訂閱。
- 新增「驗證裝置」AppBar 按鈕：列出帳號下其他裝置（排除自身），選擇後呼叫 `DeviceKeys.startVerification()` 啟動驗證，再顯示同一個 SAS 對話框；無其他裝置時提示確認 Element 已同步。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0（無新依賴）。
- 後續：裝機測試——在 Element 觸發「Verify this device」→ Homing 彈出 emoji 對話框 → 比對 → 完成後 Homing 變成已驗證，Element 不再警告、傳送速度恢復。
- **使用者回報**：Element 顯示「The authenticity of this encrypted message can't be guaranteed on this device」，且影響 Element 傳送速度。
- **根因**：Homing 裝置恢復後仍被 Element 視為未驗證——`init(waitUntilLoadCompletedLoaded: false)` 未等 cross-signing 裝置金鑰載入，導致 `initCryptoIdentity` 的 `selfSign` 被跳過（`encryption.crossSigning.enabled` 為 false）。
- `app/lib/main.dart`：`_tryRestoreSession` 在 `init` 後 await `client.userDeviceKeysLoading`（8s timeout），確保 cross-signing 狀態就緒。
- `app/lib/ui/rooms_screen.dart`：`_defaultRecoverEncryption` 在呼叫 `initCryptoIdentity` 前同樣 await `userDeviceKeysLoading`；恢復成功 SnackBar 提醒「請在 Element 重新整理頁面以同步驗證狀態」。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0。
- 後續：重裝 APK → 重新執行「恢復加密」→ 在 Element 重新整理頁面；Element 應不再顯示未驗證警告，傳送速度應恢復。

### 2026-11-01 — 2.8 bugfix：上傳 ANR + 上傳中進度提示（背景 isolate + server 上限）

- **使用者回報**：Homing 上傳等太久，Android 一度認為沒有回應（ANR）。
- **根因**：`Room.sendFileEvent` 在**主 isolate** 對整個檔案做 AES-CTR 加密，並對圖片做解碼／縮圖／blurhash；大檔會卡住 UI >5 秒 → Android ANR。僅加 spinner 不足（主 isolate 被卡住，畫面不會重繪）。
- **修正**：
  - `app/lib/media_upload.dart`（新增）：背景 isolate 預處理——圖片 `MatrixImageFile.calcMetadataImplementation`／`resizeImplementation` 與檔案 `encryptFile` 全部移到 `Isolate.run`；只呼叫 SDK 官方 API，App 端不寫加密邏輯；`PreEncryptedUpload` mixin + `UploadImageFile`／`UploadVideoFile`／`UploadPlainFile` 讓 `sendFileEvent` 直接用預先加密結果（不重複加密）。
  - `app/lib/ui/chat_screen.dart`：`_onAttach` 改用背景 isolate 預處理 → `sendFileEvent`（附 thumbnail）；新增上傳狀態（`_uploading`／`_uploadIndex`／`_uploadStage`／`_uploadTimer`）與「上傳中 i/N · 階段 / 檔名（已用 mm:ss）」橫幅；附加鈕在上傳中 disabled。
  - 大小上限改由伺服器回報：`client.getConfig().mUploadSize`（matrix.org 有 `m.upload.size`→檢查；self-host 無設→null→不限制），不手寫常數上限；超過直接 `FileTooBigMatrixException` → 計為「超過伺服器上限」。
  - `_defaultLoadMessages` 補上 `m.file`／`m.video`／`m.audio`，附件送出後才會在 timeline 顯示（影片等事件此前不會顯示）。
- **驗證**：`flutter analyze` No issues found；`flutter test` **+97 ~1**（新增 4 筆）；`python3 ci/license_check.py` EXIT=0（無新依賴）。
- **結案（2026-11-01，人類實機驗證通過）**：人類安裝 arm64 release APK（含 `libvodozemac_bindings_dart.so`，BUILD_EXIT=0）並完成驗證，回報「沒有問題」——上傳無 ANR／進度提示與 E2EE 往返確認。本項結束。

### 2026-10-31 — 修正「Element: authenticity can't be guaranteed」+ Element 傳送變慢
- **使用者回報**：Element 顯示「The authenticity of this encrypted message can't be guaranteed on this device」，且影響 Element 傳送速度。
- **根因**：Homing 裝置恢復後仍被 Element 視為未驗證——`init(waitUntilLoadCompletedLoaded: false)` 未等 cross-signing 裝置金鑰載入，導致 `initCryptoIdentity` 的 `selfSign` 被跳過（`encryption.crossSigning.enabled` 為 false）。
- `app/lib/main.dart`：`_tryRestoreSession` 在 `init` 後 await `client.userDeviceKeysLoading`（8s timeout），確保 cross-signing 狀態就緒。
- `app/lib/ui/rooms_screen.dart`：`_defaultRecoverEncryption` 在呼叫 `initCryptoIdentity` 前同樣 await `userDeviceKeysLoading`；恢復成功 SnackBar 提醒「請在 Element 重新整理頁面以同步驗證狀態」。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0。
- 後續：重裝 APK → 重新執行「恢復加密」→ 在 Element 重新整理頁面；Element 應不再顯示未驗證警告，傳送速度應恢復。

### 2026-10-31 — 自動登入 + 即時接收 + 傳送速度（人類批准 C 批次）
- **使用者回報**：每次啟動都要重新登入；訊息傳送慢；無法即時收到訊息。
- **根因**：
  1. `main.dart` 每次從 ConnectScreen 開始，從未呼叫 `createPersistentClient()` 還原 session（方案 C 已實作但未接線）。
  2. `chat_screen._onSend` 在 `sendTextEvent` 後 `await _load()` 整個重抓 timeline，且 `_sending` 要等 `_load()` 完成才解除。
  3. `ChatScreen` 從未訂閱 `client.onSync`，incoming 訊息只在 init/send 後才刷新；SDK 背景 sync 其實在跑。
- `app/lib/main.dart`：`main()` async → vodozemac init → `_tryRestoreSession()`（`createPersistentClient` + `init(waitUntilLoadCompletedLoaded:false)` + 8s timeout）；成功直接進 `RoomsScreen`，失敗走原 Connect/Login 流程。`RingApp` 新增 `restoredClient`。
- `app/lib/ui/rooms_screen.dart`：登出成功後 `Navigator.popUntil(first)` 回 ConnectScreen。
- `app/lib/ui/chat_screen.dart`：
  - 訂閱 `client.onSync`（debounce 200ms）→ `_load()`，實現即時接收。
  - `_load()` 在已有訊息時不再閃爍 loading spinner。
  - `_onSend()`：樂觀 append 訊息、清空輸入、先解除 `_sending`，背景 `unawaited(_load())` 對帳；失敗時保留錯誤訊息（不被 `_load` 清掉）。
  - 讀取標記邏輯保留。
- `UI_PROTOTYPE.md`：更新 §3.1 認證流程（自動還原、登出回 Connect、Chat 即時訂閱、樂觀傳送）。
- 驗證：analyze 0 issues；tests **+93 ~1**；license_check EXIT=0（無新依賴）。
- **UI 視覺定稿仍由人類負責**（本批 UI 僅為 unstyled 骨架 + 架構草案）。

### 2026-10-31 — 1.5 恢復加密身分流程（人類有 recovery key，批准實作）
- **使用者回報**：Homing 內「[加密訊息：無法解密]」＋ Element「Encrypted by a device not verified by its owner」→ Homing 新裝置尚未被帳號 cross-signing 簽章。
- **根因**：引擎雖啟用（vodozemac 已載入），但 Homing 裝置未復原既有的 cross-signing 身分，故 SDK 拒絕解密並標記為 unverified。
- `app/lib/ui/rooms_screen.dart`：
  - 新增 `EncryptionRecovery` typedef + `recoverEncryption` 注入點（預設呼叫官方 `Client.initCryptoIdentity(reuseExistingStorageRecoveryKeyOrPassphrase:)`，reuse 模式、不 wipe 既有 cross-signing）。
  - AppBar「恢復加密」按鈕 → Dialog 輸入 recovery key → 呼叫官方 API → `client.sync()` → 重新載入；失敗顯示錯誤 SnackBar。
  - 仍為骨架：文案／版面待 UI 定稿；不寫任何加密邏輯。
- `app/lib/ui/rooms_screen.dart` import `package:matrix/encryption.dart`（官方擴充方法 `initCryptoIdentity`）。
- 驗證：analyze 0 issues；tests **+93 ~1**（1 skip＝無環境變數登入測試）；license_check EXIT=0。
- 後續：裝機測試；若訊息仍無法顯示，建議重新啟動 App 讓 sync 重新解密；若 recovery key 不正確，SDK 會丟 BootstrapBadStateException，UI 顯示錯誤。

### 2026-10-31 — 1.5 收尾＋media 修正（人類批准「是」）：加密引擎啟用＋圖片渲染＋併批重建
- **根因確定**：APK 內無 `libvodozemac_bindings_dart.so`（unzip 驗證）→ SDK `vod.isInitialized()` false → `client.encryption` 恆為 null（client.dart:2169）→ 整個加密引擎未啟動（無法加密／無法解密）。此為「can't load/encrypt encrypted messages」之根因。
- `app/pubspec.yaml`：**新增 `flutter_vodozemac ^0.9.0`（AGPL-3.0，人類批准 2026-10-31）**；transitive：`vodozemac` 0.9.0（AGPL-3.0）、`flutter_rust_bridge` 2.13.0（MIT）。
- `app/lib/main.dart`：啟動時呼叫官方 `vod.init()`（SDK 官方引擎初始化；失敗不阻擋 App，僅無加密）；`RingApp` 增加 `vodozemacReady` 旗標（診斷用）。
- `app/lib/ui/chat_screen.dart`：①訊息載入加入 `m.image`；②未解密事件（type `m.room.encrypted`）顯示占位「[加密訊息：無法解密]」，不再悄悄丟掉；③圖磚以官方 `Event.downloadAndDecryptAttachment(getThumbnail: true)` 載入（加密房由 SDK 官方解密路徑處理；App 零加密邏輯），失敗顯示文字占位；不寫死寬度。
- `app/test/widget_test.dart`：配合 `RingApp(vodozemacReady:)` 必填參數。
- `DEPENDENCIES.md`：flutter_vodozemac（含 transitive）記錄；license_check EXIT=0（清單自動比對通過）。
- 驗證：analyze 0 issues；tests **+93 ~1**（1 skip＝無環境變數之登入測試）。
- 圖片上傳仍屬 2.8（未實作）；`proguard-rules.pro` 已停用（R8 minify 已回退），保留檔案待 Phase 5 人工策略。

### 2026-10-31 — 1.5 完成版：CryptoBridge 綁定 SDK 官方 API（人類授權動工）
- 人類授權範圍：「OK to write code, but don't touch SDK source code」→ Agent 僅改 Homing 檔案，SDK（.pub-cache）零修改。
- `app/lib/crypto_bridge.dart`：由 `Object?` 占位改為**逐字轉發** SDK 公開 API 並使用真實型別：
  - `beginCrossSigning()` → `encryption.bootstrap(onUpdate:)`（官方 Bootstrap 狀態機，狀態轉移由呼叫端/人類驅動）
  - `secretStorageHandle()` → `encryption.ssss.open()`；`openSecretStorage(recoveryKey)` → `OpenSSSS.unlock(recoveryKey:)`
  - `startVerification(userId, deviceId)` → `client.userDeviceKeys[...].deviceKeys[...].startVerification()`
  - `devices()` → `client.getDevices()`；`deleteDevice()` → `client.deleteDevice()`（非加密的裝置中繼資料 API）
  - 引擎未初始化時一律 `StateError`，不自創任何加密行為。
- `app/lib/crypto_wiring.dart`：文件契約更新（剩餘人工事項＝以 bridge hooks 具現化畫面、驅動官方 Bootstrap 狀態機）。
- `app/test/crypto_bridge_unit_test.dart`：配合真實型別改寫（未登入路徑 4 測試）。
- 驗證：analyze 0 issues；tests **+93 ~1**（1 skip＝無環境變數之登入測試）；license_check EXIT=0。
- **尚未做（人工 crypto 審核範圍）**：以 bridge hooks 具現化畫面（device_verification/key_backup_recovery）、Bootstrap 狀態機之狀態驅動策略、實機 E2EE 收送驗證。

### 2026-10-31 — Phase 0 / 0.2：DEPENDENCIES.md
- 檔案：`DEPENDENCIES.md`（新增）
- 內容：記錄依賴 SPDX 授權（當時僅 `matrix`，版本記為藍圖查證之 12.0.0）。

### 2026-10-31 — Phase 1 / 1.1：Flutter + matrix 整合測試（無帳號部分）
- 環境安裝（人類授權「開始安裝」）：
  - Flutter SDK **3.47.9 stable / Dart 3.13.7** → `/home/user/flutter/`（來源官方 stable 套件包 `flutter_linux_3.47.9-stable.tar.xz`，安裝包留在 `/home/user/` 未刪）
  - `~/.bashrc` 附加 1 行 `export PATH="$PATH:/home/user/flutter/bin"`
- 專案骨架：建立指令 `flutter create --project-name ring --platforms android,ios` → `app/`（Android + iOS；Web／桌面依藍圖排除於 v1.0）
- 依賴（兩條均經人類授權）：
  | 套件 | 範圍 | 版本 | SPDX |
  |---|---|---|---|
  | `matrix` | direct main | ^14.2.0（lock 14.2.0） | AGPL-3.0-or-later |
  | `sqflite_common_ffi` | direct dev（僅測試） | ^2.4.5（lock 2.4.5） | BSD-2-Clause |
  - `sqflite_common_ffi` 加入原因：matrix 14.2.0 起的 `Client` 建構子必須提供 sqflite `Database`；測試用 in-memory sqlite 不落檔。
- 測試檔：`app/test/matrix_integration_test.dart`
  1. homeserver 連線與相容性（無需帳號）＋ 登入流程檢查
  2. 帳密登入（僅在有 `RING_TEST_USER`／`RING_TEST_PASS` 環境變數時執行，否則 skip；帳密不寫入任何檔案）
- 驗證輸出（真實執行）：
  - `flutter analyze` → `No issues found!`
  - `flutter test test/matrix_integration_test.dart` → `00:01 +2: All tests passed!`（測試 2 因無帳號 skip）
- 同步更新：`DEPENDENCIES.md`（版本 12.0.0 → 14.2.0、加入 sqflite_common_ffi）

### 2026-10-31 — Phase 0 / 0.14：規格基準版本記錄
- 檔案：`DEPENDENCIES.md`（新增「規格基準版本」節）
- 內容：Matrix 規格基準 **v1.19**（2026-07-08，前一版 v1.18 2026-03-25；皆藍圖 §十五 已查證）＋ SDK 版本 **14.2.0**（`app/pubspec.lock`／pub.dev）。

### 2026-10-31 — Phase 0 / 0.10：客戶端支援自訂 homeserver URL（骨架）
- 位置：`app/lib/`（`homeserver_url.dart` 輸入解析、`client_factory.dart`、`ui/connect_screen.dart` 骨架＝草案待人類設計）＋ `app/lib/main.dart` 改為入口。
- 驗證：`flutter analyze`（0 issues）＋ `flutter test`（**16 passed**，含 Homeserver 位址解析單元測試、骨架 widget 測試、對 matrix.org 的整合測試）。
- 註記：client 的正式本地儲存（sqflite 等依賴）標註**待人工決定**於 `client_factory.dart`；0.13 斷點策略凍結前僅產出無樣式骨架（不寫死寬度）。

### 2026-10-31 — 主題／配色（人類拍板後由 Agent 實作，附屬 0.10 骨架）
- 決策：預設種子色 **#FFBD9F**＋支援 dynamic color（`dynamic_color` 1.8.1，Apache-2.0；人類批准該依賴，依 AGENTS.md「新增依賴須人工審核」已授權 pubspec 變更）。
- 發現：`dynamic_color` **2.1.0** 的 `DynamicColorBuilder` builder 簽名指向其新依賴 `material_ui` 的 ColorScheme，與 flutter/material ColorScheme 不相容 → 固定 1.8.1（記入 DEPENDENCIES.md）。
- 實作：`app/lib/main.dart`（`DynamicColorBuilder` + `ColorScheme.fromSeed` fallback；dark theme 同步）；驗證：analyze 0 issues、test **16 passed**。
- 另外：主題／種子色也同時記入人類維護檔 `DESIGN.md` §3。

### 2026-10-31 — Phase 0 / 0.4 ＋ 0.11（合併，人類交辦）
- 0.4：`LICENSE`（GNU AGPL-3.0 官方全文，from gnu.org/licenses/agpl-3.0.txt；661 行）。版權行待人工填寫。
- 0.11：
  - `.github/workflows/license_check.yml`（analyze／非網路測試／license check；osv 弱點掃描 v2.7.0；動作版本以 GitHub API 查證：checkout v7.0.1、flutter-action v2.23.0）
  - `app/ci/license_check.py`：檢查 pubspec.lock 全部第三方直接依賴皆記錄於 DEPENDENCIES.md（SDK source 豁免）。本地實測通過（EXIT=0）。
  - 同步將 `cupertino_icons 1.0.9`（MIT）、`flutter_lints 6.0.0`（BSD-3-Clause）依 pub cache LICENSE 核對後記入 DEPENDENCIES.md。

### 2026-11-01 — UI 重構（依人類 `LINE_ref/` 標註，附屬 1.11）＋ 2.8 bugfix 同批交付
- 人類決定（2026-11-01 問答）：① 底部導航＝3 tab（聊天／聯絡人／設定；無 Wallet＝無金流，無 Calls＝VoIP 未進藍圖僅提案 2.15）；② 輸入列相機鈕＝新增 `image_picker 1.2.4`（依賴經人類批准，BSD-3-Clause 系列，列入 DEPENDENCIES.md），mic 為 disabled 占位（語音訊息不在藍圖）；③ 表情面板＝emoji 網格＋貼圖 tab 骨架殼（Phase 3 後接；不複製 LINE 貼圖）。
- 檔案：
  - 新增：`app/lib/ui/main_shell.dart`、`app/lib/ui/settings_screen.dart`、`app/lib/ui/emoji_panel.dart`、`app/lib/ui/time_format.dart`（純函式）
  - 重寫：`app/lib/ui/rooms_screen.dart`（搜尋列＋QR 鈕＋預覽/時間/靜音/未讀徽章＝SDK lastEvent/latestEventReceivedTime/pushRuleState/notificationCount）、`app/lib/ui/contacts_screen.dart`（好友/群組兩小節＋自己列）、`app/lib/ui/chat_screen.dart`（LINE 式泡泡＋日期分隔＋已讀＝SDK Event.receipts、輸入列 ＋／相機／圖片／表情、滑到底鈕）
  - 接線：`app/lib/main.dart` 兩處導向改 `MainShell`
  - 依賴：`app/pubspec.yaml`（image_picker ^1.2.1；BSD-3-Clause 註解定稿）、`DEPENDENCIES.md`（image_picker＋7 個 transitive 全 BSD-3-Clause，pub-cache LICENSE 覆核 2026-11-01）
  - 測試：`app/test/rooms_chat_screens_widget_test.dart`（送出改 `Icons.send`＋空輸入案例改 mic disabled）、`app/test/contacts_screen_widget_test.dart`（重寫）、`app/test/ui_smoke_test.dart`（文案）、新增 `app/test/ui_redesign_test.dart`（tab 切換／設定流程＋登出對話框／表情插入／mic disabled／日期分隔／滑到底鈕）
- 未實作（LINE_ref 叉掉區域）：Services、Recommended stickers、AD banner、Select music、story ＋、圖片/貼圖 save-star、LINE STORE；通話／行事曆（VoIP 未進藍圖）。
- 事實引用（SDK 14.2.0 源碼，本機 pub cache）：`Room.lastEvent`、`Room.latestEventReceivedTime`（非空）、`Room.notificationCount`、`Room.pushRuleState`、`Event.receipts`、`Room.directChatMatrixID`、`Client.homeserver`（Uri?）、`Client.getDevices()`（回 `Future<List<Device>?>`）、`Room.getParticipants()`（非 Future）。
- 驗證（真實執行）：`flutter analyze` → `No issues found!`；`flutter test` → `+103 ~1: All tests passed!`；`python3 ci/license_check.py` → EXIT=0。
- 註記：完整版面仍為**草案，待人類設計定稿**（UI_PROTOTYPE.md 已同步）；上傳大小規則不變（m.upload.size）。ARM64 release APK 建置成功（BUILD_EXIT=0，`libvodozemac_bindings_dart.so` 已入 APK）。
- **結案（2026-11-01）**：人類實機驗證（含 2.8 上傳、UI 三 tab、往返解密）回報「沒有問題」——本批交付（UI 重構＋2.8 bugfix）結束。

### 2026-11-01 — P2.15 通話功能（人類指示「先完成通話功能」；實機驗證前，狀態＝待驗證）
- 依賴（人類批准 2026-11-01）：`flutter_webrtc 1.6.3`（MIT）、`webrtc_interface 1.5.1`（MIT；由 transitive 轉直接）；transitive `dart_webrtc 1.8.2`（MIT）— 全數記入 DEPENDENCIES.md（pub-cache LICENSE 覆核同日）。
- 新增檔案：
  - `app/lib/voip/ring_delegate.dart`：SDK `WebRTCDelegate` 官方介面的 App 端實作（組接 flutter_webrtc）；來電／結束／未接以廣播 Stream 暴露；鈴聲占位＝系統提示音＋震動（不內建音檔）；E2EE keyProvider 一律 null（不啟用加密擴充，SDK 預設）；group call 回呼 no-op（群組通話暫緩）。
  - `app/lib/voip/call_manager.dart`：`CallManager extends ChangeNotifier`（ensureInit 可捕獲的 callSupportError、activeCall、incomingCall ValueNotifier、startCall／answerCurrent／rejectCurrent／hangupCurrent）＋純函式 `callStateLabel`／`formatCallDuration`。
  - `app/lib/ui/call_screen.dart`：全螢幕通話畫面（草案）：來電（接聽／拒接）→ 通話中（遠端大畫面＋本機小畫面；靜音／攝影機／掛斷）；kEnded 後 700ms 自動退頁。`WrappedMediaStream` 未被 SDK 匯出（不可命名），以 `Object?` 參照判斷免重綁。
- 修改檔案：
  - `app/lib/ui/main_shell.dart`：注入／自建 CallManager；來電時以 rootNavigator 全螢幕 route 彈出 CallScreen。
  - `app/lib/ui/chat_screen.dart`：頂列新通話入口（語音 `Icons.call_outlined`／視訊 `Icons.videocam`）；僅在 direct chat 且 manager 可用時顯示；失敗以 SnackBar 告知。
  - `app/lib/ui/rooms_screen.dart`／`contacts_screen.dart`：`callManager` 參數透傳至 ChatScreen。
  - `app/android/app/src/main/AndroidManifest.xml`：RECORD_AUDIO／CAMERA／INTERNET／MODIFY_AUDIO_SETTINGS（人類批准 2026-11-01；藍牙權限限 SDK≤30）。
  - `app/ios/Runner/Info.plist`：NSMicrophoneUsageDescription／NSCameraUsageDescription（草案文案；iOS 需專業諮詢未開放，僅同步權限鍵）。
- SDK 事實（matrix 14.2.0 源碼，本機 pub cache）：一對一來電掛點＝`delegate.handleNewCall`（`onIncomingCallSetup`／`onIncomingCallStart` 僅在 confId≠null 群組通話觸發）；`hangup({required CallErrorCode reason})`（reject 之 reason 可選）；`RTCRenderer.mirror` 屬 web-only，原生請以 `RTCVideoView(mirror:)`。
- 測試：新增 `app/test/call_helpers_test.dart`（純函式層：callStateLabel 映射、formatCallDuration 格式）。**範圍限制**：CallManager／CallScreen／MainShell 的 widget 級通話測試在本環境不可行（flutter_webrtc 需要 Android/iOS 原生平台層，widget test 無 WebRTC platform 通道）——通話行為需人類實機驗證。
- 驗證（真實執行）：`flutter analyze` → `No issues found!`；`flutter test` → `+109 ~1: All tests passed!`。
- 範圍限制（記錄）：①僅一對一 P2P（mesh）；群組通話（LiveKit）暫緩；②來電偵測僅前景；背景 FCM 推播不在本批（未接來電僅走 SDK `handleMissedCall`，App 未接清單 UI 未做）；③無內建鈴聲音檔（授權待人類決定）；④ TURN/STUN 憑證由 SDK `getIceServers()` 自 homeserver 取得，不寫死任何伺服器位址。

### 2026-11-01 — P2.15b 群組通話（mesh；人類指示「群組通話也要支援」→ 選 MeshBackend）
- 依賴：無新增（重用 flutter_webrtc；LiveKit E2EE 群組通話另批處理）。
- SDK 事實（matrix 14.2.0 源碼，本機 pub cache）：`MeshBackend.e2eeEnabled` 寫死 `false`（群組媒體不 E2EE，與 1:1 通話一致）；`VoIP.createGroupCallFromRoomStateEvent` 在 member state 事件到達時建立 GroupCallSession 並呼叫 `delegate.handleNewGroupCall`；`GroupCallSession.enter()`／`leave()`；`MeshBackend.onStreamAdd`／`onStreamRemoved`／`localUserMediaStream`／`userMediaStreams`。
- 新增檔案：`app/lib/ui/group_call_screen.dart`（草案：加入按鈕 → 參與者網格 + 靜音／攝影機／離開）。
- 修改檔案：
  - `app/lib/voip/ring_delegate.dart`：`handleNewGroupCall`／`handleGroupCallEnded` 改為廣播 Stream（取代 no-op）；標頭註解更新。
  - `app/lib/voip/call_manager.dart`：`activeGroupCall`／`incomingGroupCall` ValueNotifier、`startGroupCall`／`leaveGroupCall`、`_onNewGroupCall`／`_onGroupCallEnded`、ensureInit 訂閱、dispose 關閉 delegate。
  - `app/lib/ui/main_shell.dart`：訂閱 incomingGroupCall，彈出 GroupCallScreen 全螢幕 route。
  - `app/lib/ui/chat_screen.dart`：非 direct chat 聊天室頂列新增「群組通話」鈕（`Icons.groups`）。
- 範圍限制：mesh 僅適合少人數房間；群組媒體無 E2EE（UI 已標示草案，待人類定稿文案）；LiveKit E2EE 群組通話（MatrixRTC）仍暫緩。
- 驗證（真實執行）：`flutter analyze` → `No issues found!`；`flutter test` → `+109 ~1: All tests passed!`。

### 2026-11-01 — P2.15c LiveKit（MatrixRTC）狀態報告（人類指示「實作 LiveKit」）
- 依賴：`livekit_client 2.13.2`（Apache-2.0）已加入 pubspec.yaml + DEPENDENCIES.md（人類批准 2026-11-01）。
- 已完成：`app/lib/voip/livekit_config.dart`（MSC4143 foci 發現：讀 `.well-known/matrix/client` 的 `org.matrix.msc4143.rtc_foci`，回傳 livekit service URL + alias）。
- **未完成／阻塞**：LiveKit 完整橋接需要：
  1. JWT 取得流程（lk-jwt-service 端點格式未在 SDK 內建；matrix 14.2.0 無 token 方法）。
  2. LiveKit 房間連線／track 發布訂閱（livekit_client API 已可查，但需實際 SFU 端點測試）。
  3. E2EE 金鑰橋接（matrix SDK keyProvider ↔ livekit_client E2EE），需可查證的參考實作。
- 結論：LiveKit E2EE 群組通話是「研究導向」批次，需要 (a) 可測試的 MatrixRTC 後端（matrix.org 帳號 + .well-known 已公告 foci）、(b) JWT 端點格式驗證。在無測試環境下硬實作會產出無法驗證的程式碼。
- 建議：先以 mesh 群組通話（P2.15b，已交付）作為可用功能；LiveKit 批次待測試環境就緒後再開工。

### 2026-11-01 — P2.15c PiP + LiveKit best-effort（人類指示「實作 LiveKit + PiP」）
- 依賴：無新增 PiP 套件（pip 0.0.4 BSD-3-Clause，pubspec 已加入）；livekit_client 2.13.2 已加入。
- PiP（Android）：
  - `app/android/app/src/main/AndroidManifest.xml`：MainActivity 加 `android:supportsPictureInPicture="true"`。
  - 新增 `app/lib/pip_helper.dart`：PipHelper（isSupported / enter）。
  - `app/lib/ui/call_screen.dart` 與 `app/lib/ui/group_call_screen.dart`：控制列新增 PiP 按鈕（Icons.picture_in_picture_alt）。
  - iOS PiP 尚未實作（WebRTC platform view 整合複雜，後補）。
- LiveKit best-effort：
  - 新增 `app/lib/ui/livekit_call_screen.dart`：foci 發現 + 診斷資訊顯示（JWT 流程與 E2EE 橋接待驗證）。
  - `app/lib/ui/chat_screen.dart`：非 direct chat 聊天室頂列新增「LiveKit 群組通話（實驗）」按鈕。
- 驗證（真實執行）：`flutter analyze` → `No issues found!`；`flutter test` → `+109 ~1: All tests passed!`。

### 2026-11-01 — 批次 B 聊天室釘選置頂（人類指示「B」，儲存：Matrix account data + 本機 sqflite）
- 依賴：無新增（sqflite 已在）。
- 新增檔案：`app/lib/pinned_rooms.dart`（PinnedRoomsStore：本機 sqflite 快取 + Matrix account data `com.ring.pinned_rooms` 同步；pin/unpin/sync/isPinned）。
- 修改檔案：
  - `app/lib/ui/rooms_screen.dart`：初始化 PinnedRoomsStore、_load 時 sync 並釘選置頂排序、long-press bottom sheet（靜音／釘選）、釘選圖示、dispose 關閉 db。
- 範圍限制：釘選清單以 account data 為準（跨裝置同步），本機 sqflite 為快取；homeserver 不支援 account data 時僅本機有效。
- 驗證（真實執行）：`flutter analyze` → `No issues found!`；`flutter test` → `+109 ~1: All tests passed!`；APK 45.5MB。

### 2026-11-01 — 批次 C 外觀設定（人類指示「全部」，含貼圖 Phase 3 提前）
- 依賴：無新增（file_picker 已在；sqflite 已在）。
- 新增檔案：
  - `app/lib/app_settings.dart` — AppSettings（sqflite kv + room_bg + stickers 表）
  - `app/lib/ui/appearance_screen.dart` — 外觀設定畫面（種子色預設、字型匯入 ttf/otf、貼圖圖片匯入、聊天室背景說明）
- 修改檔案：
  - `app/lib/main.dart` — 啟動時讀 AppSettings theme_seed_color 套用種子色
  - `app/lib/ui/settings_screen.dart` — 新增「外觀設定」入口
  - `app/lib/ui/chat_screen.dart` — _roomBackground 狀態 + Scaffold backgroundColor；「更多」選單新增「設定聊天室背景」（色碼）
  - `app/lib/ui/emoji_panel.dart` — 貼圖 tab 改為載入 AppSettings 貼圖清單（Phase 3 骨架）
- 範圍限制：字型需重啟生效；聊天室背景僅色碼（圖片路徑後續）；貼圖顯示為占位 icon（Image.file 渲染待人類設計）；全部為草案待人類設計定稿。
- 驗證（真實執行）：`flutter analyze` → `No issues found!`；`flutter test` → `+109 ~1: All tests passed!`；APK 45.6MB。

### 2026-11-01 — mesh 通話掛斷改善 + Element X 相容性說明
- 修改檔案：
  - `app/lib/voip/call_manager.dart`：leaveGroupCall 記錄錯誤（不再靜默吞掉）。
  - `app/lib/ui/group_call_screen.dart`：_leave 顯示錯誤 SnackBar。
  - `app/lib/ui/call_screen.dart`：_hangup 顯示錯誤 SnackBar。
  - `app/lib/ui/chat_screen.dart`：發起群組通話時顯示 SnackBar 說明 Element X 相容性。
- 說明：Element X 不支援 famedly mesh calls（com.famedly.call.member），會顯示「Custom event com.famedly.call.member」，這是協定差異，非 Homing bug。Element X 僅支援 MatrixRTC（LiveKit）。mesh 通話掛斷在 Homing-to-Homing 之間應正常運作；若失敗，SnackBar 會顯示具體錯誤。
- 驗證（真實執行）：`flutter analyze` → 無 error；`flutter test` → `+109 ~1: All tests passed!`；APK 45.6MB。

### 2026-11-01 — 群組通話畫面 7 項功能（人類指示）
- 修改檔案：`app/lib/ui/group_call_screen.dart`（重寫）。
- 功能：
  1. 音量表：輪詢 backend.activeSpeaker（500ms），說話人 tile 高亮綠框 + volume_up 圖示。
  2. 視訊關閉時顯示頭像：_hasVideo 檢查 videoMuted + video track；關閉時顯示 CircleAvatar 首字。
  3. 參加者名稱：每個 tile 左下角疊加名稱標籤。
  4. 動態排版：_crossAxisCount 依參與者數（1→1 欄、2-4→2 欄、5+→3 欄）。
  5. 螢幕分享：backend.setScreensharingEnabled 切換按鈕。
  6. PiP 模式隱藏按鈕：_pipActive 時隱藏控制列與參與者按鈕。
  7. 參與者按鈕：頂列 people 按鈕 → bottom sheet 顯示參與者列表。
- 驗證（真實執行）：`flutter analyze` → 無 error；`flutter test` → `+109 ~1: All tests passed!`；APK 45.6MB。

### 2026-11-01 — backlog 批次 D（人類指示「讀取 PROGRESS.md 目標，完成目前能完成」＋ question 批准）
- 範圍（人類 question 回答核准）：①未讀管理 ②歷史訊息分頁 ③圖片全屏預覽＋分享/下載 ④投票；**「分享」經人類批准新增 share_plus**。
- 依賴（記 DEPENDENCIES.md）：`share_plus 13.3.1`（BSD-3-Clause，人類批准 2026-11-01）；本批新增 transitive：`share_plus_platform_interface` 7.2.0（BSD-3）、`file` 7.0.1（BSD-3）；`cross_file` 0.3.5+5 既有已記錄。license_check EXIT=0。
- 新增檔案：
  - `app/lib/ui/image_preview_screen.dart`：全屏預覽（草案）：InteractiveViewer 縮放；「下載／分享」走系統分享 sheet（`SharePlus.instance.share`＋`XFile.fromData`，記憶體分享不落本地檔）；全尺寸經 SDK `Event.downloadAndDecryptAttachment()`（官方 API）。
  - `app/lib/ui/poll_create_screen.dart`：發起投票（草案）：問題＋2–10 選項＋公開/匿名；送出走 SDK 官方 `Room.startPoll`（`msc_extensions/msc_3381_polls`；PollKind disclosed/undisclosed；單選 maxSelections=1 草案）。
  - `app/test/batch_d_features_test.dart`：3 測試（投票注入啟動參數／圖片預覽渲染＋分享入口／長按選單含「標記為未讀」）。
- 修改檔案：
  - `app/lib/ui/chat_screen.dart`：
    - 歷史訊息：`_timeline` **複用同一 Timeline 實例**（過往每次 `_load` 都 `room.getTimeline()` 重建 → 丟掉已在的歷史窗口，為「過去訊息消失」UI 端根因）；頂部「載入更早訊息」手動按鈕（`Timeline.canRequestHistory`／`requestHistory(historyCount:50)`；**非無限滾動**，藍圖禁止資訊流式自動載入）；頂部插入內容時跳點補償（保持視覺位置）。
    - 投票渲染：`ChatMessageView.isPoll`；`_ChatPollTile`（草案）：問題＋選項按鈕；投票＝SDK 官方 `Event.answerPoll`，票數＝`Event.getPollResponses(timeline)`，結束＝`Event.endPoll`／`getPollHasBeenEnded`；`_defaultLoadMessages` 把 `m.poll.start`（SDK 常數 PollEventContent.startType）列入載入。
    - 圖片 tile 點擊 → ImagePreviewScreen（帶入縮圖 bytes 顯示）。
    - **真 bug 修正（由本批測試發現）**：`_load` 對空列表結果不解除 `_loading` → 空聊天室 spinner 轉不停（上批防閃爍改動留下）；補 `else if (_loading) setState(_loading=false)`。
    - initState `AppSettings.getRoomBackground` 補 `.catchError`（測試環境無 sqflite 時不炸；真機行為不變）。
  - `app/lib/ui/rooms_screen.dart`：長按選單新增「標記為未讀」（SDK 官方 `Room.markUnread(true)`，account data `m.marked_unread`）；未讀徽章改 `Room.isUnread`（= notificationCount>0 ‖ markedUnread），手動未讀而計數 0 時顯示圓點。
- 驗證（真實執行）：`flutter analyze` → 0 error（11 既有 info/warning）；`flutter test` → **+112 ~1: All tests passed!**（新增 3）；`python3 ci/license_check.py` → EXIT=0；APK 45.9MB（Gradle 135.4s），`libvodozemac_bindings_dart.so` 仍在。
- 範圍限制／相容性（SDK 本機源碼事實）：SDK 投票走 **unstable 前綴 `org.matrix.msc3381.poll.*`**（PollEventContent.startType 靜態常數）——Element 等支援穩定 `m.poll.*` 的客戶端可能只顯示 fallback 文字、無法互操作投票；Homing↔Homing 之間可用。投票 UI 全為草案、「仍待人類設計定稿」。
- 未做（依 question 結果）：「圖片分享」已完成（share_plus）；「存在相冊」不寫本機檔案邏輯，交由系統分享 sheet 的儲存目標完成（草案）。

### 2026-11-01 — backlog 批次 E（人類 4 項回饋；方向經 question 批准）
- 範圍（人類回饋 2026-11-01）：①圖片放大逐級填滿＋下載/外部分享 ②訊息發送者頭像
  ③訊息選取（長按選單：反應/回覆/複製文字/檢舉/分享至外部＋左右滑動回覆）④投票 Element X
  相容修復。批准記錄：「下載」＝方案 A 系統 sheet（零新依賴）；投票 dual 前綴接收＋end 補
  msc1767 fallback 文字；訊息選取四項全做。
- 依賴：**無新增**（license_check EXIT=0；本批全部走既有 SDK/share_plus 官方 API）。
- 新增檔案：
  - `app/lib/poll_compat.dart`：MSC3381 雙前綴讀取相容層 —— `pollStartContentCompat`
    （unstable `org.matrix.msc3381.poll.start`＋stable `m.poll.start` 皆解）、
    `pollResponsesCompat`（unstable＋stable response 皆計；每人最新一次；**結束事件之後
    的回應不計**，SDK `getPollResponses` 同規則）、`pollEndedCompat`、
    `endPollWithFallback`（end 事件＋`org.matrix.msc1767.text` 文字 fallback；文案草案）。
    為何要自製：SDK `Event.parsedPollEventContent` 只認 unstable 鍵且強制要求
    msc1767 text 欄位（缺則 throw）；`getPollResponses` 只認 unstable response 型別。
  - `app/test/batch_e_features_test.dart`：5 測試（stable start 解析＋非投票不誤判／
    回應掃描 dual＋每人最新／結束偵測＋結束後回應不計／長按選單＋回覆預覽列＋解除／
    穩定型別投票磚渲染）。測試以 `Timeline(room, TimelineChunk(events))` 離線構造
    （`TimelineChunk` SDK 未由 barrel 導出，測試檔引用 src 路徑；app 不用）。
- 修改檔案：
  - `app/lib/ui/image_preview_screen.dart`：雙擊逐級放大 1x→2x→4x→1x（TransformationController；
    動效草案）＋平移；底部「下載」「分享至外部」分列（**皆走系統分享 sheet＝方案 A**；
    sheet 內建儲存目標；`XFile.fromData` 記憶體分享不落本地檔；下載引導文字草案）。
  - `app/lib/ui/rooms_screen.dart`：`_roomPreview` 投票事件（dual 前綴）顯示「投票」／
    「投票已結束」——修人類實測「Unknown message format of type …」的 rooms 預覽
    （SDK `Event.body` 對未知型別回該字串，event.dart:301）。
  - `app/lib/ui/chat_screen.dart`：
    - 訊息磚手勢（草案）：長按 → `_showMessageActions` bottom sheet（動作 sheet 回傳代號後
      在 State context 執行，避免 pop 後觸 builder context）；左右滑動（速度 ≥500px/s 草案）
      → 回覆。條件：無 event（注入測試）→ 無反應列；圖片/投票 → 無複製＋無分享（圖片分享
      在預覽畫面已有）；本人訊息 → 無檢舉。預設 emoji 組草案：👍❤️😂😮😢🙏。
    - 表情反應：SDK 官方 `Room.sendReaction`（m.annotation）；chips 顯示來源
      `Timeline.aggregatedEvents[eventId][RelationshipTypes.reaction]` 聚合鍵
      （timeline.dart:24 構造）。**草案限制**：chips 隨下一次重建更新（未訂閱 timeline
      onChange 即時刷新）。
    - 回覆：狀態 `_replyTo`；送出走 SDK 官方 `Room.sendTextEvent(text, inReplyTo:)`；
      回覆預覽列在輸入列上方（X 解除）；送出後解除。回覆讀側官方
      `Event.getReplyEvent`（本批未做泡泡內引用預覽）。
    - 頭像：`_SenderAvatar` 替代 `_InitialAvatar`（首字 fallback 相同）；頭像 Uri 來源＝
      房間 `m.room.member` state 的 `avatar_url`（官方 `Room.getState`，純記憶體）→
      `Uri.getDownloadUri` → NetworkImage。**不用 `senderFromMemoryOrFallback`**：
      它 fire-and-forget `requestUser` → DB box（測試環境未開啟 → 非同步 LateError）。
    - `_ChatPollTile`：改 dual 相容（pollResponsesCompat/pollEndedCompat/
      pollStartContentCompat；結束走 `endPollWithFallback`）。
    - `_defaultLoadMessages`：投票納入改 `kPollStartTypes`／endedPollIds 掃描改
      `kPollEndTypes`；投票 body 顯示「[投票]」（SDK body=Unknown… 不宜露出，草案文案）。
    - **真 bug 修正 1**：「載入更早訊息」按鈕在批次 D 隨後編輯中脫落（build 樹無接線；
      analyzer unused_element `_historyButtonVisible`/`_requestHistory` 為證）→ 本批補回
      （載入中 spinner、批次 D 的視覺位置補償邏輯不變）。
- 驗證（真實執行）：`flutter analyze` → **0 error**，issues 11→**9**（補回按鈕使 2 個
  unused_element 消失；其餘皆既有）；`flutter test` → **00:28 +117 ~1: All tests passed!**
  （批次 E +5）；`python3 ci/license_check.py` → EXIT=0；
  `flutter build apk --release --target-platform=android-arm64 --split-per-abi` →
  ✓ Built app-arm64-v8a-release.apk **46.0MB**（Gradle 76.9s）；
  APK 內 `lib/arm64-v8a/libvodozemac_bindings_dart.so` 存在 ✓。
- Element X 互通（⚠️待查證）：Homing 發送端仍走 SDK 官方 unstable API（未動）；
  接收端已 dual；結束事件補 msc1767.text fallback 文字。Element X 端 Homing 結束後仍
  顯示「未結束」是否改善，需人類實機複測；若 X 仍不認，記錄為 X 端協定差異。
- 未做／草案限制：回覆泡泡內的原始訊息預覽（只有輸入列預覽列）；反應 chips 非即時；
  滑動動效無動畫（草案）；頭像只在他人訊息（own 不顯示頭像，現狀版面不作）

### 2026-11-02 — backlog 批次 F（人類回報：圖片「放大後被原始解析度限制」）
- 診斷（兩個根因，皆在預覽畫面，人類批准後修）：
  ① 聊天磚載入的是**縮圖**（`downloadAndDecryptAttachment(getThumbnail: true)`，
     chat_screen.dart:201），預覽以它當 initialBytes 占位；全尺寸（無 getThumbnail）
     載入**較慢或失敗時被靜默吞掉**（舊碼只在 `_bytes == null` 時顯示錯誤）→
     停在縮圖解析度上放大＝人類看到的「被原始解析度限制」。
  ② 版面：InteractiveViewer（constrained:true 預設）**不自擴展**（Flutter
     interactive_viewer.dart 源碼證實：僅 ClipRect>Transform>child、無 fill 包裝），
     在 Center 松約束下 viewport＝Image 原生尺寸（constraints.constrain(自然尺寸)），
     且舊的雙擊矩陣以**原點（左上）**為錨 → 放大體感＝「把原始解析度的圖撐大」。
- 修改檔案：
  - `app/lib/ui/image_preview_screen.dart`：
    * viewport 改 **Positioned.fill**（緊約束 → 子 widget 恰為 body 滿幅；1x 一律
      contain 填滿可視區域）。
    * 雙擊錨點改 **viewer 幾何中心**（GlobalKey 量 RenderBox 實際尺寸；矩陣
      `T(c)·S(next)·T(-c)`；1x→2x→4x→1x 循環不變）。
    * 全尺寸載入狀態**可見化**（對應 ①）：載入中→頂部 spinner 提示層；成功→重置
      縮放（占位時可能已放大）＋換上原始 bytes；失敗→頂部條「僅顯示縮圖（原始檔
      載入失敗）」（文案草案；不再靜默，可見錯誤便於回報根因）。
    * 新增測試注入縫 `loadFullBytes`（僅測試；正式走 SDK 官方 API）。
  - `app/test/batch_e_features_test.dart`：+4 測試（viewer＝滿 body／雙擊中心錨
    1x→2x→4x→1x 矩陣斷言／成功換圖＋重置縮放／失敗顯示提示）。注意：本地
    函式／常數不得用底線開頭（lint no_leading_underscores_for_local_identifiers）。
- 驗證（真實執行）：`flutter analyze` → issues **9**（回批次 E 時的同水位；本批
  修掉 2 個 translate() deprecation）；`flutter test` → **00:25 +121 ~1: All tests
  passed!**（批次 F +4）；APK 46.0MB（Gradle 118.7s）＋`libvodozemac_bindings_dart.so`
  存在 ✓。
- 實機複測重點：點圖 → 立刻可放大瀏覽（縮圖占位）；全尺寸到齊後自動重置 1x 並變清晰；
  若頂部出現「僅顯示縮圖（原始檔載入失敗）」＝全尺寸下載在裝置上失敗（請貼該畫面，
  須再查 homeserver/media 端點，屬另一問題）。

### 2026-11-02 — 批次 G：UI 結構定位（依人類批准的 draft_buttons_map 提案＋Element X 底列參考）
- 結構決定（皆人類拍板，詳 design/pages/_draft_buttons_map.md）：
  ① 底部導覽 4 tab：聊天／聯絡人／**通話（空骨架）**／設定；
  ② 底列改 Element X 式**膠囊列**（icon-only＋tooltip；圓角 32、margin 16/bottom 12、
     `Scaffold.bottomNavigationBar` 不 extendBody）；
  ③ 底列**不含 FAB**：「＋新增」改置頂列右側（LINE 版面位置）→ 三項合一 sheet；
  ④ 聊天頁通話鈕**四合一**為一鈕＋選單（音訊／視訊／mesh／LiveKit 全保留）；
  ⑤ 輸入列附件**三鈕合一**為單一「＋」（相機／照片／影片／檔案）。
- 修改檔案：
  - `app/lib/ui/chat_screen.dart`：AppBar 通話入口 PopupMenuButton（條件合併為
    `callManager != null`；`_calling` 時 spinner 取代鈕，併入前 mesh 為 disabled＝
    行為語意相同）；輸入列 3 直連鈕 → 1「＋」（tooltip 新增附件）；
    `_showAttachPicker` 改回傳字串三項＋路由到 `_onCamera`／`_startAttach`。
  - `app/lib/ui/rooms_screen.dart`：頂列「＋」IconButton（tooltip 新增）→
    新 `_showAddSheet()`（建立聊天室／加入公開聊天室／加入好友 QR；pop 回調交由
    既有 `_createRoom`／`_joinPublicRoom`／`_openAddFriend`）；⋮ 選單移除
    create/join（保留 驗證裝置／診斷／登出）；**恢復加密按鈕保持原樣**。
  - `app/lib/ui/main_shell.dart`：IndexedStack 4 children（_CallsTab 空骨架
    index 2，設定→3）；NavigationDestination → 膠囊列 IconButton(isSelected:)；
    顏色取主題 `surfaceContainerHighest`（**不採 Element 綠／品牌色**）。
  - `app/test/ui_redesign_test.dart`：MainShell 契約更新（膠囊列 icon-only →
    以 `find.byTooltip` 定位；設定 index 3；新增通話 tab 斷言）；＋2 測試
    （頂列＋三項合一 sheet／輸入列單「＋」選單三項）＝**123 tests**。
- 已知限制（待人類設計定稿）：① 圖示沿用 Material 內建（自訂圖示後續委製）；
  ② 膠囊列為「不遮擋內容」版（extendBody=false；真正懸浮疊內容需 extendBody＋
  列表 padding，屬視覺定稿範圍）；③ 通話選單未在 widget 測試涵蓋（CallManager
  widget 級測試在本環境不可行，同 call_helpers_test 註解）；需實機驗證。
- 驗證（真實執行）：`flutter analyze` → issues **9**（既有水位；0 error）；
  `flutter test` → **00:24 +123 ~1: All tests passed!**；license_check EXIT=0；
  APK **45.9MB**（Gradle 68.6s）＋`libvodozemac_bindings_dart.so` 存在 ✓。
- 實機複測重點：底列 4 tab 切換、「＋新增」sheet 三項入口、通話選單四項、
  輸入列「＋」三項選單。

### 2026-11-02 — 批次 H：實機回饋三修（膠囊可見＋標籤／顏色被 Android 吃掉／字型未套用）
- 人類實機回報（批次 G 後）：①膠囊沒出現＋仍需文字標籤；②顏色被 Android 設定
  吃掉；③字型沒有套用。人類拍板修法（question 確認）：**保留 dynamic_color＋
  App 內開關（預設關）**／**深色膠囊＋標籤**／**字型導入即生效**。
- 根因（皆本機代碼查證）：
  ① 膠囊底色 surfaceContainerHighest 在淺色種子下≈白底白膠囊（對比不足＝肉眼
     不可見）；且批次 G 為 icon-only。
  ② `main.dart` `DynamicColorBuilder`：Android 12+ 桌布動態取色**預設開啟**，
     Homing 種子色被系統色取代。
  ③ 外觀骨架**只存不讀**：`font_path` 寫進 DB 後無任何渲染接線
     （grep FontLoader／fontFamily＝0 處）＝骨架未完成項，非運行故障。
- 修改檔案：
  - `app/lib/main.dart`：動態取色**預設關**（外觀頁開關開啟才採系統桌布色；
    Homing 種子色恆為預設）；新增外觀執行緒 `ringFontFamily`／`ringUseDynamicColor`
    （ValueNotifier，零依賴）＋ `ringTheme()` 純函式；自訂字型＝FontLoader
    （官方 services API）啟動還原＋匯入即時（**MaterialApp 內建 AnimatedTheme
    過渡 200ms** — 測試需 pumpAndSettle 才能讀到新字型，非 bug）。
  - `app/lib/ui/main_shell.dart`：膠囊底色改 **inverseSurface**（主題自我對立
    表面：淺色＝深膠囊、深色＝亮膠囊，保證對比；非固定色值，最終待人類
    tokens 定稿）；每項加 **icon＋文字標籤**（選中全彩／未選 60% 透明度）。
  - `app/lib/ui/appearance_screen.dart`：匯入字型 → FontLoader 立即套用
    （成功/失敗 SnackBar 文案草案）；清除字型即時回平台預設；新增開關
    「跟隨 Android 桌布配色」（預設關，切換即時生效＋儲存）。
  - `app/test/ui_redesign_test.dart`：+2（ringTheme 純函式 fontFamily 帶入／
    外觀 notifier 變動 → 主題即時重建）；MainShell 測試補膠囊標籤可見斷言。
  - 本 Flutter 版本注意：`ThemeData` **無 fontFamily getter**（僅建構參數，套用
    進 textTheme）→ 斷言改讀 `textTheme.bodyLarge!.fontFamily`。
- 驗證（真實執行）：`flutter analyze` → issues **9**（既有水位；0 error）；
  `flutter test` → **00:29 +125 ~1: All tests passed!**（批次 H +2）；
  license_check EXIT=0；APK **45.9MB**（Gradle 72.1s）＋vodozemac .so ✓。
- 實機複測重點：①膠囊深底可見＋每項 icon/標籤；②顏色＝Homing 種子色（不再被
  桌布吃掉；外觀頁開關可開回系統色）；③外觀頁匯入 ttf/otf → 全 App 字型立即
  生效、重開 App 仍保留。

### 2026-11-02 — 批次 I：①②③⑤（人類實機回饋後的零依賴批次）
- ① 文字大小＋Light/Night：`main.dart` 新增 `ringTextScale`（TextScaler.linear）
  ／`ringThemeMode`（ThemeMode）notifier；MaterialApp `themeMode`＋`builder` MediaQuery
  套用；外觀頁 RadioListTile（草案）切換即時生效＋儲存（`text_scale`／`theme_mode`）。
- ② 登入頁整合：`LoginScreen` 內建伺服器預設選項（matrix.org／自訂／Homing 自架）＋
  帳密；送出**一站式**：先 `checkServer`，成功才 `loginWithPassword`，失敗顯示
  「連線測試失敗」且不登入；`main.dart` 流程不再經 `ConnectScreen`（ConnectScreen
  保留供骨架測試）；成功路徑補 `_busy` 重置（修 element 重用導致按鈕卡在登入中）。
- ③ Spaces：聊天列表 Spaces 區塊改**預設收合**（點標題展開，保留「知道有哪些房間」）。
- ⑤ 頭像：`_RoomAvatar`／`_SenderAvatar` 改 `getThumbnailUri`＋`authenticatedMediaSupported`
  時帶 `authorization: Bearer <accessToken>`，修 matrix.org authenticated media
  導致的頭像不顯示。
- 修改檔案：`app/lib/main.dart`、`app/lib/ui/login_screen.dart`、
  `app/lib/ui/rooms_screen.dart`、`app/lib/ui/chat_screen.dart`、
  `app/lib/ui/appearance_screen.dart`、`app/test/login_screen_widget_test.dart`（+1 測試）、
  `app/test/ui_redesign_test.dart`（+1 Spaces 測試＋RingApp 文字大小/主題測試）、
  `app/test/widget_test.dart`（煙霧測試更新為登入骨架）。
- 驗證：`flutter analyze` → issues **5**（既有水位以下）；`flutter test` →
  **00:37 +128 ~1: All tests passed!**（批次 I +3）；license_check EXIT=0；
  APK **45.9MB**（Gradle 72.8s）＋vodozemac .so ✓。
- 未完成：④ 位置分享（人類拍板「完整地圖」＝需新依賴，Batch III 待批准）；
  ⑥⑦ 通話（人類拍板「只收合控制列」；⑥ 不穩定現象待人類補描述＋logcat）。

### 2026-11-02 — 批次 II：通話（⑦ 控制列收合；⑥ 麥克風/攝影機強化）
- ⑦（人類拍板「只收合控制列」）：`call_screen.dart` 新增 `_controlsVisible`；媒體區左上
  浮動鈕切換「收合/顯示」；收合時隱藏整列並保留「顯示＋掛斷」小列，**不需最小化
  App 即可切換控制列可見性**（人類指示「按一下消失或跳出，而不是最小化再跳回」）。
- ⑥（麥克風/攝影機不穩定）：`_toggleMic`／`_toggleCamera` 加入 try/catch＋
  race guard（`_togglingMic`／`_togglingCam`）＋失敗 SnackBar；切換後以 SDK 真值
  `session.isMicrophoneMuted`／`isLocalVideoMuted` 更新本地旗標；`onCallStateChanged`
  監聽器同步更新旗標；掛斷／已結束時禁用切換。
- 未完成：⑥ 根因仍待人類提供**具體不穩定現象＋logcat**（目前以防禦性強化為主；
  SDK 官方 `setMicrophoneMuted`／`setLocalVideoMuted` 本身可能延遲生效，需裝置驗證）。
- 修改檔案：`app/lib/ui/call_screen.dart`。
- 驗證：`flutter analyze` → issues **5**；`flutter test` → **00:26 +128 ~1: All
  tests passed!**（widget 級通話測試在本環境不可行，同 call_helpers_test 註解）；
  license_check EXIT=0；APK **45.9MB**（Gradle 75.1s）＋vodozemac .so ✓。

### 2026-11-02 — 批次 II-b：通話強化（麥克風/攝影機真控＋螢幕分享前景服務）
- ⑥ 麥克風/攝影機仍無法控制（根因）：
  * SDK `WrappedMediaStream.setAudioMuted`／`setVideoMuted` **僅設旗標**（audioMuted/
    videoMuted）並 fire onMuteStateChanged，**不翻轉 MediaStreamTrack.enabled**；
    且 1:1 的 `CallSession.setMicrophoneMuted` 不設 track.enabled → 本地麥克風仍
    持續擷取、對方仍聽得到；group_call_screen 原本直接呼叫
    `local.setAudioMuted`（只設旗標，**不通知 peers、不設 track.enabled**）。
  * 修法：1:1 `_toggleMic`／`_toggleCamera` 在 SDK 呼叫後**直接翻轉**
    `track.enabled`；group 呼叫改用 `backend.setDeviceMuted(...)`（設旗標＋
    setTracksEnabled＋通知所有 peer call）。
- 螢幕分享閃退（根因）：Android 14+ (targetSdk 36) 的 MediaProjection 要求前景
  服務持有 `mediaProjection` 類型；flutter_webrtc 1.6.3 不會自行啟動 → 原生
  SecurityException 導致閃退。
  * 修法：新增 `ScreenCaptureForegroundService`（Kotlin）＋ MainActivity
    MethodChannel `ring/screen_capture`（start/stop）＋ manifest `<service
    foregroundServiceType="mediaProjection">`；group_call_screen 在啟動分享前先
    啟動前景服務、分享結束/失敗/dispose 時關閉。
- 修改檔案：`app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/android/app/src/main/kotlin/com/example/ring/ScreenCaptureForegroundService.kt`
  （新）、`.../MainActivity.kt`、`app/android/app/src/main/AndroidManifest.xml`。
- 驗證：`flutter analyze` → issues **5**；`flutter test` → **00:30 +128 ~1: All
  tests passed!**；license_check EXIT=0；APK **45.9MB**（Gradle 179.7s）＋vodozemac .so ✓。
- 待實機驗證：⑥ 麥克風/攝影機切換（應立即生效）；螢幕分享不再閃退並正常分享；
  若仍有不穩請貼 logcat。

### 2026-11-03 — 批次 II-c：通話收尾（⑥ 真控＋⑧ 前景服務；身份殘留/雙視窗）
- 人類實機回報：①前一次通話身份仍留在通話中、沒掛斷、有時自己出現兩個視窗；
  ②麥克風/鏡頭按鍵嚴重延遲，且關閉任一者可能斷線。
- 根因：
  ① SDK `onCallEnded` 有時不觸發 → CallManager.activeCall/incomingCall 殘留 →
    「前一次通話的身份還留在通話中」；MainShell `_incomingOpen` 旗標若路由未 pop
    也殘留 → 後續來電被忽略或重疊 →「兩個視窗」。call_screen 結束 pop 用
    `Navigator.of(context)`（非 rootNavigator）且 700ms delay 後 `canPop` 可能為
    false（PiP/背景）→ 不 pop。
  ② `setMicrophoneMuted`/`setLocalVideoMuted` **await `updateMuteStatus()`**（送
    Matrix 事件）→ UI 嚴重延遲；`WrappedMediaStream.setAudioMuted` 只設旗標不翻轉
    track.enabled → 本地仍擷取；group 原本直接 `local.setAudioMuted`（不通知 peer、
    不設 track.enabled）→ 關閉時對方仍收得到、本地 track 仍開 → 可能斷線。
- 修法：
  - `call_manager.dart` 新增 `clearCall`／`clearGroupCall`（identical 時清除＋notify）。
  - `call_screen.dart`：kEnded → `manager.clearCall(session)`＋用 rootNavigator
    可靠 pop；麥克風/鏡頭切換改 **UI 先行反應**（optimistic setState）＋SDK 呼叫後
    設 track.enabled；失敗回滾＋SnackBar。
  - `group_call_screen.dart`：麥克風/鏡頭改用 `backend.setDeviceMuted`（設旗標＋
    setTracksEnabled＋通知所有 peer call）。
- 修改檔案：`app/lib/voip/call_manager.dart`、`app/lib/ui/call_screen.dart`、
  `app/lib/ui/group_call_screen.dart`。
- 驗證：`flutter analyze` → issues **5**；`flutter test` →
  **00:35 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 72.0s）＋vodozemac .so ✓。
- 待實機驗證：⑥ 切換即時生效且不再斷線；⑧ 身份殘留/雙視窗消失。

### 2026-11-03 — 批次 II-d：通話收尾（⑧ 身份殘留/雙視窗、⑩ 通話紀錄、⑪ 群組名稱/圖示）
- ⑧ 根因（實機）：SDK `onCallEnded` 不觸發 → CallManager 狀態殘留；call_screen
  pop 用 `Navigator.of(context)`（非 root）且 700ms delay 後 `canPop` 可能 false；
  MainShell `_incomingOpen` 若路由未 pop 也殘留 → 後續來電被忽略或重疊。
  修法：call_screen kEnded → `manager.clearCall(session)` + rootNavigator 可靠 pop；
  `_hangup`/`dispose` 也 clearCall；MainShell 既有 `_incomingOpen` 旗標維持。
- ⑩ 通話紀錄從未留下過：新增 `lib/call_log.dart`（SQLite `call_log` 表，零新依賴）；
  call_screen/group_call_screen 在 kEnded/leave/hangup 寫入（方向、對象、房間、
  開始時間、時長、結果）；`_CallsTab` 改為紀錄列表（頭像首字、名稱、方向、
  時間、時長、未接標記）＋重新整理。
- ⑪ 群組通話通知顯示哪個群組：GroupCallScreen 頂部改顯示房間名稱＋頭像
  （`_GroupAvatar`，含認證媒體 header）＋參與者數；通話紀錄群組列標「群組」。
- 修改檔案：`app/lib/voip/call_manager.dart`、`app/lib/ui/call_screen.dart`、
  `app/lib/ui/group_call_screen.dart`、`app/lib/ui/main_shell.dart`、
  `app/lib/call_log.dart`（新）。
- 驗證：`flutter analyze` → issues **5**；`flutter test` →
  **00:25 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 73.3s）＋vodozemac .so ✓。
- 待實機驗證：⑧ 身份殘留/雙視窗消失；⑩ 紀錄是否留下；⑪ 群組名稱/圖示顯示。

### 2026-11-03 — 批次 II-e：通話收尾（⑧⑩⑪ 後續回饋六項）
- 人類實機回報：①殘留身份未解決；②通話時點擊其他地方按鈕應自動隱藏/顯示；
  ③每個人自己視窗出現兩個；④PiP 模式應看得到自己和另一位、畫面不被切；
  ⑤視窗應能自行調整大小、多使用者時分享畫面優先；⑥除非掛斷，按退出應繼續
  接通並退到聊天室，按通話按鈕應能回到通話狀態。
- 修法：
  * ① dispose 不再 clearCall（避免使用者按返回時掛斷）；clearCall 僅在 kEnded/
    _hangup；MainShell `_incomingOpen` 守衛維持。
  * ② call_screen/group_call_screen 媒體區以 GestureDetector (translucent) 包裹，
    點擊切換 `_controlsVisible`（隱藏/顯示控制列）。
  * ③ group_call_screen：onStreamAdd 跳過 `isLocal()` 串流；build 時以 id 去重，
    避免自己出現兩次。
  * ④ PiP：進入 PiP 時 `_controlsVisible=false`；本地畫面保持 overlay。
  * ⑤ group_call_screen：螢幕分享時優先佈局（分享大面積 + 參與者縮圖列）。
  * ⑥ chat_screen `_startCall`/`_startGroupCall`：若已有進行中通話且同房間，
    直接 push CallScreen/GroupCallScreen（回到通話狀態），不重撥。
- 修改檔案：`app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/lib/ui/chat_screen.dart`。
- 驗證：`flutter analyze` → issues **5**；`flutter test` →
  **00:24 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 74.4s）＋vodozemac .so ✓。
- 待實機驗證：①②③④⑤⑥。

### 2026-11-03 — 批次 II-f：通話收尾（按鍵隱藏/顯示、相機麥克風重開轉圈、螢幕分享後控制列）
- 人類實機回報：①按鍵顯示在分享畫面最小化後回到通話無法顯示；②相機/麥克風關閉後重新開啟會變成轉圈。
- 根因：
  ① 螢幕分享停止時 `_screenSharing` 翻轉但 `_controlsVisible` 未恢復（使用者在分享期間
     收合控制列後，分享結束仍隱藏）；媒體區 GestureDetector 已包住分享畫面，但
     `_controlsVisible` 仍為 false → 控制列不顯示。
  ② 相機/麥克風關閉後重新開啟：SDK `setLocalVideoMuted(false)` →
     `insertVideoTrackToAudioOnlyStream()` 新增視訊 track 並 fire `onStreamChanged`；
     但 call_screen/group_call_screen 的 `_localRenderer` 仍綁舊 stream，渲染器不更新
     → 本地畫面卡在舊狀態/轉圈。`onStreamChanged` 是 `CachedStreamController`，需
     `.stream.listen`。
- 修法：
  - `call_screen.dart`／`group_call_screen.dart`：監聽 `localUserMediaStream.onStreamChanged.stream`，
    重新綁定 `_localRenderer`（dispose 舊、initialize 新、srcObject=new stream）。
  - `group_call_screen.dart`：分享停止/失敗時 `setState(() => _controlsVisible = true)`。
- 修改檔案：`app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`。
- 驗證：`flutter analyze` → issues **7**（既有水位）；`flutter test` →
  **00:32 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 72.7s）＋vodozemac .so ✓。
- 待實機驗證：相機/麥克風重開不再轉圈；分享結束後控制列恢復顯示。

### 2026-11-03 — 批次 II-g：通話收尾（控制列隱藏/顯示、相機麥克風轉圈、PiP/分享畫面）
- 人類實機回報：①按鍵顯示在分享畫面最小化後回到通話無法顯示；②相機/麥克風關上後
  重新開啟會變成轉圈。
- 根因：
  ① 螢幕分享停止時 `_screenSharing` 翻轉但 `_controlsVisible` 未恢復（使用者在分享
     期間收合控制列後，分享結束仍隱藏）。
  ② SDK `setLocalVideoMuted(false)` → `insertVideoTrackToAudioOnlyStream()` 新增視訊
     track 並 fire `onStreamChanged`；但 Homing 未監聽 → 渲染器不更新 → 卡轉圈。
     `onStreamChanged` 是 `CachedStreamController`，需 `.stream.listen`。
  ③ PiP 返回後 `_pipActive` 未重置 → 控制列持續隱藏、畫面被切。
  ④ 遠端串流渲染器為 null 時顯示永久 spinner → 改為靜態圖示。
- 修法：
  - `call_screen.dart`／`group_call_screen.dart`：監聽
    `localUserMediaStream.onStreamChanged.stream`，重新綁定 `_localRenderer`。
  - `group_call_screen.dart`：分享停止/失敗時 `setState(() => _controlsVisible = true)`；
    遠端渲染器為 null 時顯示靜態 Icon（不再轉圈）；`_ensureRenderer` 在 stream 為
    null 時監聽 onStreamChanged 重試；加入 WidgetsBindingObserver，resumed 時重置
    `_pipActive=false`。
- 修改檔案：`app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`。
- 驗證：`flutter analyze` → issues **7**；`flutter test` →
  **00:32 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 72.7s）＋vodozemac .so ✓。
- 待實機驗證：相機/麥克風重開不再轉圈；分享結束後控制列恢復；PiP 返回正常。

### 2026-11-03 — 批次 II-h：通話收尾（關閉軟體斷線、最小化 PiP、PiP 全螢幕按鈕、按 Homing 開聊天室）
- 人類實機回報：①設定軟體一旦關閉或當機就直接斷線；②最小化就直接進入 PiP 模式，
  PiP 按全螢幕回到通話，PiP 時按 Homing 開啟聊天室、通話繼續；③PiP 進全螢幕後按鈕
  仍無法出現。
- 修法：
  - 關閉/當機斷線：新增 `CallForegroundService`（Kotlin，phoneCall 類型）＋
    MainActivity MethodChannel `ring/call_service`（start/stop）＋ manifest 註冊；
    call_screen/group_call_screen 在通話接通時啟動前景服務、結束/掛斷/dispose 時關閉，
    避免最小化時 App 被回收導致通話斷線（當機仍無法避免，屬 OS 行為）。
  - 最小化自動 PiP：call_screen/group_call_screen 加入 WidgetsBindingObserver，
    `AppLifecycleState.paused` 時自動 `PipHelper.enter()` 並設 `_wasInPip`/`_pipActive`。
  - PiP 狀態回呼：`PipHelper.registerObserver` 註冊 `PipStateChangedObserver`，
    started/stopped 時更新 `_pipActive`/`_controlsVisible`（PiP 進全螢幕後按鈕恢復）。
  - PiP 時按 Homing：resumed 時 `_wasInPip` 重置旗標，通話繼續；使用者可按返回退到
    聊天室（通話不中斷），再按通話按鈕回到通話狀態（批次 II-e 已支援）。
- 修改檔案：`app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/lib/pip_helper.dart`、`app/android/app/src/main/kotlin/.../CallForegroundService.kt`
  （新）、`.../MainActivity.kt`、`app/android/app/src/main/AndroidManifest.xml`。
- 驗證：`flutter analyze` → issues **9**；`flutter test` →
  **00:36 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 75.1s）＋vodozemac .so ✓。
- 待實機驗證：最小化自動 PiP、PiP 全螢幕按鈕恢復、按 Homing 開聊天室通話繼續、
  前景服務是否避免最小化斷線。

### 2026-11-03 — 批次 II-i：通話前景服務 SecurityException 修復（phoneCall → dataSync）
- 人類實機回報：App 啟動通話前景服務時**直接崩潰**（SecurityException）。
- 根因：Android 14+ 的 `phoneCall` 前景服務類型要求 `MANAGE_OWN_CALLS`／DIALER
  角色等特殊權限（一般 App 不具備）；`FOREGROUND_SERVICE_PHONE_CALL` 單獨不足。
- 修法：前景服務類型改為 `dataSync`（通用類型，僅需 `FOREGROUND_SERVICE_DATA_SYNC`，
  已加入 manifest）；Kotlin 端在 API 34+ 明確傳入
  `FOREGROUND_SERVICE_TYPE_DATA_SYNC`。
- 修改檔案：`app/android/app/src/main/AndroidManifest.xml`、
  `app/android/app/src/main/kotlin/com/example/ring/CallForegroundService.kt`。
- 驗證：`flutter analyze` → issues **9**；`flutter test` →
  **00:36 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 69.8s）＋vodozemac .so ✓。

### 2026-11-03 — 批次 II-j：依人類指示「重新檢視所有檔案」後的全面修復
- 全案唯讀審查發現 2 個嚴重問題（皆為 II-f～II-i 快速修補時字串替換靜默未命中）：
  A. AndroidManifest.xml 遺失 ScreenCaptureForegroundService 註冊（II-h 編輯誤刪）
     → 群組通話螢幕分享會 ServiceNotFoundException 崩潰。已補回（mediaProjection）。
  B. call_screen.dart dispose 缺 removeObserver＋unregisterObserver →
     已返回退出的 State 仍掛 WidgetsBindingObserver，於其他畫面最小化時會觸發
     auto-PiP（整個 App 從非通話畫面進 PiP）。已補。
- 其餘修復（人類批准，除 F 語意外全部）：
  C. group_call_screen 補 PipHelper.registerObserver（原靜默未套用；
     unused_import lint 即證據）。
  D. call_screen 補 resumed → 恢復 _controlsVisible（與 group 相同兜底）。
  E. 通話紀錄不再於 dispose 寫入（原「返回後通話繼續」會多寫一筆 completed/failed；
     改僅 kEnded／_hangup／_leave 寫入）。
  F.（人類拍板）群組通話「返回」＝與一對一相同：通話繼續。dispose 不再
     clearGroupCall／關前景服務；改於 ended 狀態時關前景服務＋寫紀錄＋pop。
  G. group _ensureRenderer 的 onStreamChanged 訂閱改存 _pendingStreamSubs
     （同一 stream 只掛一次，移除/離開時取消）。
  H. local stream 晚到時補註冊 onStreamChanged（call_screen._attachStreams、
     group._attachLocal）→ 避免麥克風/相機重開轉圈問題在「來電剛接聽」場景復發。
  I. 清掉 3 個 unnecessary_null_comparison＋unused_import lint。
  J. call_screen PiP 回調 pipStateStarted 的 _pipActive 統一為 true。
- 驗證：flutter analyze → issues **5**（回降至既有水位以下）；flutter test →
  **00:36 +128 ~1: All tests passed!**；license_check EXIT=0；APK **45.9MB**
  （Gradle 298.6s）＋vodozemac .so ✓（manifest 兩個前景服務均已註冊）。
- 已知限制／後續提案：使用者按返回（通話繼續）後若在**其他畫面**等對方掛斷，
  畫面監聽已解除 → ①該通話紀錄不會寫入；②通話前景服務通知不會自動關閉
  （須待 CallManager 層統一處理；此為後續批次提案，尚未授權）。

### 2026-11-03 — 批次 III-a：known_problems 已 soluble 8 項（人類全核准全批次 III，零新依賴）
- 授權來源：`known_problems.md` 1-8 ＋ `LINE_ref/new_ref/` 人類注記；批次切分 humans 同意 III-a~c 全核准。
- 修改檔案（III-a）：`app/lib/ui/chat_screen.dart`、`app/lib/ui/rooms_screen.dart`、`app/lib/ui/contacts_screen.dart`。
- ① 收回訊息：長按 sheet 新增「收回（刪除訊息）」→ `Room.redactEvent`；SDK 官方 `Event.redacted` → 顯示『[已收回]』。
- ② 表情 reaction 取消：`_reactionsOf` 聚合改回 `(count, myEventId)` tuple；
  `_addReaction` 改 `_toggleReaction`（未反應→sendReaction；已反應→redact 自己那筆 m.reaction）；自己 chips 加主色外框。
- ③ 滑到上方自動載入更早訊息：`_onScroll` 於 pixels<=60 觸發 `_requestHistory()`；手動按鈕＋`_historyButtonVisible` getter 移除。
- ④ 檔案/影片/音訊可點：新增 `_ChatFileTile`（圖示＋『點擊開啟』）；`_openAttachment`＝`downloadAndDecryptAttachment`→temp→`SharePlus`；
  eventId-keyed `_openedFiles` cache。
- ⑤ Spaces 顯示所有可用 rooms：`_buildSpaceTile`＋`_showSpaceRooms` bottom sheet
  用 SDK 官方 `Client.getSpaceHierarchy`（SpaceRoomsChunk$2）；點未加入 → 公式加入後開啟。
- ⑥ 搜尋文案『搜尋對話』→『搜尋聊天室』。
- ⑦ 公開聊天室搜尋：升 `SimpleDialog`→`StatefulBuilder`，客戶端過濾＋onSubmitted 伺服器端 `PublicRoomQueryFilter(genericSearchTerm)`。
- ⑧ 聯絡人頭像：direct chat 走 `getState(RoomMember, directChatMatrixID)` avatar_url（避免 db LateError）；
  `_avatarThumbnail` 走 getThumbnailUri＋authenticatedMediaSupported Bearer。
- 驗證：`flutter analyze` → issues 5；`flutter test` → **00:36 +128 ~1: All tests passed!**。

### 2026-11-03 — 批次 III-b：貼圖
- 修改檔案：`app/lib/ui/emoji_panel.dart`、`app/lib/ui/chat_screen.dart`、
  `app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/lib/ui/appearance_screen.dart`、`app/lib/ui/settings_screen.dart`、`app/test/ui_redesign_test.dart`。
- ⑩ 自訂貼圖接線：`EmojiPanel.onStickerSelected` 已接（先前未接）；
  `_sendSticker`＝`uploadContent`→`m.sticker`（url/info{w,h,mimetype}/body；
  `_stickerMime` 擴展名 mapping；`_imageDimensions` 用 dart:ui ImmutableBuffer）；
  sticker tile 用 `_loadFullImage` 渲染，receive 端於 III-a 已 render EventTypes.Sticker。
- ⑪ 通話切換鏡頭：`Helper.switchCamera` 按鈕於兩通話畫面（僅視訊顯示）。
- ⑫ 更換使用者頭像：設定頁 Profile header＋`ImagePicker`→`Client.setAvatar(MatrixFile)`；
  fetchOwnProfile→getThumbnailUri。
- ⑨ 文字大小校準：加入『稍小』0.9，最大加大 1.7（其余 1.0/1.15/1.3）。
- 設定頁依人類注記參考圖重構：Profile header／個人資訊／一般／App info（GitHub）；
  划掉項不複製；Homing 缺項（隱私/語言/通話）未實作則不列。
- 驗證：`flutter analyze` → issues 5；`flutter test` → **00:35 +128 ~1: All tests passed!**。

### 2026-11-03 — 批次 III-c：附件面板／好友邀請／裝置管理強化（部分完成）
- 修改檔案：`app/lib/ui/chat_screen.dart`（`emoji_panel.dart` 含）、
  `app/lib/ui/add_friend_screen.dart`、`app/lib/ui/contacts_screen.dart`、
  `app/lib/ui/rooms_screen.dart`、`app/lib/ui/device_management_screen.dart`、
  `app/test/*.dart`。
- 輸入列附件：『＋』改**展開面板**（上排 ×／相機／相簿＋輸入框；下方 Files／聯絡資訊／位置 option row）；
  Contact、位置為草案骨架（位置仍卡 flutter_map 依賴，停用）。
- 好友邀請修復：`_defaultInvite` 原為空 stub → 改 SDK 官方 `Client.startDirectChat`；
  `_showInviteDialog`（受邀房間 → 接受 `Room.join`／拒絕 `Room.leave`）。
- 裝置管理強化：本裝置徽章、遠端登出確認＋失敗原因、重新命名（官方 updateDevice）、
  遠端登出走官方 UIA（密碼重認證）；recovery key 仍為 crypto 範疇→未動。
- 決議（人類 2026-11-03）：qr_flutter／flutter_map／latlong2 已批准並接入；
  GitHub source code URL 尚未提供（Phase 0 阻塞，onTap 保留佔位）；
  recovery key 控制屬 crypto 範疇 → 仍暫不實作，key_backup_recovery_screen 維持 UI-only skeleton。
- 驗證：`flutter analyze` → issues 5；`flutter test` → **00:35 +128 ~1: All tests passed!**。

### 2026-11-03 — 第 7 點需求（人類授權全部，允許新增依賴）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/settings_screen.dart`、
  `app/lib/ui/appearance_screen.dart`、`app/lib/ui/main_shell.dart`、`app/lib/main.dart`、
  `app/android/app/src/main/AndroidManifest.xml`、`app/pubspec.yaml`、`app/DEPENDENCIES.md`。
- 新增依賴（人類已授權）：`open_file: ^4.0.0`（MIT）、`app_links: ^7.2.2`（MIT）。
- 第 1 點：檔案開啟改用 `open_file.open(path)`，系統彈出可開啟該格式的 App，
  不再走 `SharePlus.share` 系統分享 sheet。
- 第 2 點：AndroidManifest 加入 `android.intent.action.SEND` intent-filter；
  `app_links` 監聽傳入 uri；MainShell 訂閱 `shareReceiverStream`，彈出
  「外部分享」對話框（草案：顯示類型＋內容，取消/確認）。
- 第 3 點：設定頁 Profile header 顯示自訂顯示名稱（`fetchOwnProfile` 的
  `displayName`，無則顯示「個人名稱（未設定）」）；點擊可編輯顯示名稱，
  走官方 `setProfileField(displayname)`；頭像更換已有（`ImagePicker` →
  `Client.setAvatar`）。
- 第 4 點：聊天室抓取更早訊息的轉圈動畫改為 32×32，置中顯示，不被壓縮。
- 第 5 點：長按選單「收回（刪除訊息）」新增條件 `!(m.event?.redacted ?? false)`，
  已收回訊息不再顯示收回選項。
- 第 6 點：外觀設定加入「自訂主題色（十六進位）」輸入框，走 `AppSettings`
  `theme_seed_color`；重啟 App 後生效（草案）。
- 第 7 點：聊天室長按選單「設定聊天室背景」新增「選擇圖片」
  (`ImagePicker` → `AppSettings.setRoomBackground` 儲存路徑) 及「重置背景」；
  聊天室畫面支援 `DecorationImage` (`FileImage`) 圖片背景或純色背景。
- 驗證：`flutter analyze` → 0 error（6 個既有 info）；`flutter test` →
  **00:19 +128 ~1: All tests passed!**；`license_check` → EXIT=0；
  `flutter build apk --release` → **102.4MB** ✓。
- 未決：第 2 點「選擇聊天室」目前僅彈出對話框顯示內容，尚未實作
  真正轉發到選定聊天室（需人類定稿 UI 流程）；第 6/7 點為 UI 骨架，
  最終介面由人類定稿。

### 2026-11-03 — known_problems.md 剩餘 [x] 全部處理（人類授權全部，允許新增依賴）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/add_friend_screen.dart`、
  `app/lib/ui/settings_screen.dart`、`app/lib/ui/rooms_screen.dart`、
  `app/android/app/src/main/AndroidManifest.xml`、`app/pubspec.yaml`、
  `DEPENDENCIES.md`、`known_problems.md`。
- 新增依賴（人類已授權）：`open_file: ^4.0.0`（MIT）、`app_links: ^7.2.2`（MIT）。
- 第 1 點（自訂貼圖）：m.sticker 收發/渲染已實作（`_sendSticker` → `uploadContent` + `sendEvent(type: EventTypes.Sticker)`；接收端 `EventTypes.Sticker` 已渲染）。
- 第 2 點（好友邀請發送＆接收）：`_defaultInvite` 改為 SDK 官方 `Client.startDirectChat(mxid)`；受邀房間加入 `_showInviteDialog`（`Room.join`/`leave`）。
- 第 5 點（檔案無法點選開啟）：`_openAttachment` 改用 `open_file.open(path)`，系統彈出支援該格式的 App。
- 第 7 項（表情 reaction 取消）：`_toggleReaction`（未反應→`sendReaction`；已反應→`redact` 自己那筆 m.reaction 事件）。
- 第 10 項（標準字型過大）：文字大小校準為 0.9/1.0/1.15/1.3/1.7。
- 第 11 項（聯絡人頭像）：`_avatarUriFor` direct chat 用 `getState(RoomMember, mxid)` 讀 `avatar_url`。
- 第 17 項（螢幕分享閃退）：AndroidManifest 加入 `POST_NOTIFICATIONS` 權限（Android 13+ 前景服務通知需求）。
- 第 18 項（QR 黑色無對比）：`QrImageView` 依 `Theme.of(ctx).brightness` 自動設定 `eyeStyle`/`dataModuleStyle` 顏色。
- 第 19 項（分享檔案應傳檔案而非標題）：`case 'share':` 依訊息類型分流；圖片/貼圖/附件走 `_shareAttachment`（下載解密→`SharePlus.share(files:)`）。
- 第 20 項（點入聊天室已讀）：`_load()` 結尾呼叫 `room.setReadMarker(eventId)`（SDK 官方）。
- 第 21 項（滑到底按鈕空白/遮住/卡空中）：按鈕改為 `Stack` + `Positioned`（不佔 Column 空間），動畫從 200ms/easeOut 改為 350ms/decelerate。
- 第 22 項（過去訊息無法讀取）：新增 `_initialLoadDone`，僅初始載入或用戶已在底部時才 `jumpTo(maxScrollExtent)`，避免定時 `_load()` 把用戶趕回底部。
- 驗證：`flutter analyze` → 0 error（6 個既有 info）；`flutter test` → **00:27 +128 ~1: All tests passed!**；`license_check` → EXIT=0；`flutter build apk --release` → **102.4MB** ✓。
- 未決：reaction「反應過慢」可能是 `setState` 導致整頁重建（Flutter 正常行為，非 bug）；螢幕分享原生閃退可能與 MediaProjection 用戶授權有關，需實機驗證。

### 2026-11-03 — known_problems.md 8 項用戶回報修正（人類授權全部）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/appearance_screen.dart`、`app/lib/ui/settings_screen.dart`、`app/lib/main.dart`、`app/android/app/src/main/AndroidManifest.xml`、`known_problems.md`。
- 無新增依賴（open_file、app_links 等已在前一批次加入）。
- 問題 1（滑到底按鈕卡在空中）：按鈕改為 Stack+Positioned（不佔 Column 空間），動畫從 animateTo(350ms/decelerate) 改為 jumpTo 直接到底。
- 問題 2（reaction 無法取消）：_toggleReaction 在 sendReaction 失敗時，先 _load() 重新載入訊息，再次檢查 _reactionsOf 中的 myEventId，若有則 redactEvent 取消。
- 問題 3（部分檔案無開啟 App）：_openFile 在 open_file 失敗後，回退到 SharePlus.share(files:)，讓使用者選擇安裝的 App。
- 問題 4（過去訊息讀不到）：_onScroll 觸發條件從 pixels<=60 放寬為 <=100，確保滑動到頂部時可靠觸發 requestHistory。
- 問題 5（標準字型過大）：appearance_screen 選項調為 0.75/0.9/1.0/1.15/1.3/2.0，預設值從 1.0 改為 0.9；main.dart ringTextScale 預設值改為 0.9。
- 問題 6（修改個人頭像）：settings_screen 已有 _changeAvatar（ImagePicker → Client.setAvatar(MatrixFile)）＋_loadProfile 刷新。
- 問題 7（Android 15 分享當機）：AndroidManifest.xml 加入 POST_NOTIFICATIONS 權限（Android 13+ foreground service 通知需求）。
- 問題 8（點入聊天室無法已讀）：_load() 結尾呼叫 setReadMarker 並顯示錯誤 SnackBar；新增 _hasUnread 狀態，有未讀訊息時顯示手動「設為已讀」按鈕（_markAsRead 呼叫 setReadMarker）。
- 驗證：flutter analyze → 0 error（6 個既有 info）；flutter test → 00:25 +128 ~1: All tests passed!；license_check → EXIT=0；flutter build apk --release → 102.4MB ✓。
- 未決：reaction 反應速度屬 Flutter setState 正常行為；螢幕分享閃退需 Android 15 實機驗證；文字大小需人類實機確認 0.9 是否合適。

### 2026-11-03（第二次）— 8 項仍失效的根因重分析（人類指示「重新分析完整程式碼後修正」）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/lib/ui/settings_screen.dart`、`app/lib/main.dart`、
  `app/android/app/src/main/kotlin/com/example/ring/ScreenCaptureForegroundService.kt`、
  `app/pubspec.yaml`（僅 version bump）、`known_problems.md`、`PROGRESS.md`。
- 無新增依賴。SDK 事實來源：matrix 14.2.0 `Timeline.fetchAggregatedEvents`
  （/relations API）、`Room.sendReaction` 回傳 audience 產生的 eventId、
  `Room.isUnread = notificationCount>0 || markedUnread`、flutter_webrtc 1.6.3
  `Helper.requestCapturePermission`（官方 consent 流程）。
- 第 1 點（滑到底卡空中）：root cause＝lazy ListView maxScrollExtent 為估估值，
  單次 jumpTo 後新 item build → extent 又變大。改 `_scrollToBottom()` 逐 frame 補跳（上限 10）。
- 第 2 點（reaction 無法取消）：root cause＝自己的 reaction 落在聚合窗口外 →
  `_reactionsOf` 判「自己未反應」→ 再送重複 reaction。改：
  session 記憶 sendReaction 回傳 id → 官方 `fetchAggregatedEvents` 補抓 → raw timeline 掃描。
- 第 3 點（只有部份檔案能開）：root cause＝上傳檔名無副檔名 → 系統判不出 mimetype。
  改 `_attachmentFileName`：官方 `content['info']['mimetype']` → 副檔名（含 odp/doc/xlsx 等對照表）。
- 第 4 點（過去訊息讀不到）：root cause ① `_defaultLoadMessages` 四類清單各自 reverse 後
  串接 → 時序錯亂；② requestHistory 單輪 50 筆遇 DB 邊界無進展即停。改：
  單一過濾保 SDK 事件時序＋最多 4 輪 ×100 筆連續載入＋「已沒有更早訊息」提示（5 秒節流）。
- 第 5 點（標準字型仍過大）：root cause＝裝置已持久化舊字級值，改預設無效。
  一次性遷移：舊字階下移一檔（1.7→1.3/1.3→1.15/1.15→1.0/1.0→0.9/0.9→0.75），
  戳記 `text_scale_migrated` 防使用者重選後每次啟動再位移。
- 第 6 點（更換頭像）：root cause＝相機徽章只在「已有頭像」時渲染；無頭像 fallback
  分支無點擊目標。fallback 統一提供 `_changeAvatar` 入口。
- 第 7 點（Android 15 分享當機）：root cause＝未取得 MediaProjection consent 即
  startForeground(mediaProjection) → ForegroundServiceTypeNotAllowedException。
  改 flutter_webrtc 官方 `Helper.requestCapturePermission(fullScreenOnly: true)`
  同意後才啟動服務（也避免 getDisplayMedia 二彈對話框）；Service startForeground 包 try/catch。
- 第 8 點（點入無法已讀）：root cause①`_lastReadEventId` 在 await 前寫入 → 失敗永不重試；
  ②目標只到「最後一條訊息」而非 `Room.lastEvent`。改：成功才寫 guard（失敗下次 sync 重試；
  自動路徑不洗 SnackBar）＋目標改 `Room.lastEvent`；initState 立即取 `isUnread`
  讓「設為已讀」按鈕在未讀房間立刻出現。
- 其他：`version: 1.0.1+2002`（裝置 versionCode 2001 → 修 INSTALL_FAILED_VERSION_DOWNGRADE；
  非 dependency 變更）。
- 驗證：flutter analyze → 0 error（6 個既有 info）；flutter test → **00:39 +128 ~1: All tests passed!**；
  license_check → EXIT=0；flutter build apk --release → **✓ app-release.apk (102.4MB)**。
- 未決：①reaction/歷史/已讀需實機複測（本機 adb 未授權）；②螢幕分享 Android 15 原生行為
  需實機 logcat 確認；③字級遷移結果需人類目視確認；④若 server 對久未活動房間回
  `prev_batch` null，SDK 源碼註明會停止向後分頁（Logs.i 'No more events...'）——此為 SDK 行為，
  若實機仍讀不到請回報房間與 logcat。

### 2026-11-03（第三次）— 人類指示：①已讀症狀釐清＋②釘選置頂＋③分享畫面 fit（先完成三項；④主題包待規格決定）
- 修改檔案：`app/lib/ui/rooms_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/lib/ui/chat_screen.dart`、`app/pubspec.yaml`（僅 version bump→1.0.2+2003）、
  `known_problems.md`、`PROGRESS.md`。無新增依賴。
- ②釘選置頂：root cause＝列表排序只跑在 `changed==true` 分支，
  釘選／取消釘選只更新 `_pinned` 後 `setState((){})`，`_rooms` 順序從不重算 →
  留在原地。改：抽出 `_sortRooms()` 統一入口；`_load` whenever 重build一律排序；
  pin handler 完成後立即 `setState(_sortRooms)`。
- ③分享畫面 fit：root cause＝`_VideoTile` 全部用 `objectFit: Cover`（橫向螢幕流
  被裁切）＋大畫面條件 `_screenSharing && screenShares.isNotEmpty` 使**觀看端**
  （本地 share flag false）掉進 GridView 小格。改：`_VideoTile(contain:)` 參數，
  螢幕分享 tile 用 Contain（完整可視、比例自動貼合）；大畫面條件改
  `screenShares.isNotEmpty`（任一分享串流即大畫面，與本地 flag 無關）。
- ①「顯示有新訊息但讀不到先前訊息」（人類提供的重現資訊）：未讀徽章來自
  server 計數與本地 loader 無關。補上兩項修正：
  (a) 本地 timeline 訊息過少（<20 筆）時 ListView 無捲動高度、`_onScroll`
      永不觸發 → 進房後主動 `_requestHistory()` 一次（session 內一次，防提示洗版）。
  (b) SDK `_requestEvents` 源碼：`room.prev_batch == null` 時不打 server
      直接退出（'No more events to request from server...'）——久未活動房間
      （超出 recent sync 涵蓋窗口）prev_batch 可為 null → 歷史永遠看不到。退路：官方
      `room.getTimeline(eventContextId: lastEvent)`（/context API，
      chunk 自帶 prevBatch）boot 重建 timeline 後 requestHistory 正常。
- 驗證：flutter analyze → 0 error（6 個既有 info）；flutter test → **00:27 +128 ~1: All tests passed!**；
  flutter build apk --release → **✓ app-release.apk (102.5MB)**（versionCode 2003）。
- 未決：①②③需實機複測；④創作者主題包(zip)屬新功能規格——待人類決定包格式／套用
  範圍／線上 vs 檔案匯入後，先產規格草案文件再動工。

### 2026-11-03（第四次）— known_problems.md 未勾 9 項全批（人類指示「修正所有問題」；零新依賴）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/rooms_screen.dart`、
  `app/lib/ui/settings_screen.dart`、`app/lib/main.dart`、`app/lib/pinned_rooms.dart`、
  `app/lib/app_settings.dart`、`app/pubspec.yaml`（僅 version bump→1.0.2+2004）、
  `known_problems.md`、`PROGRESS.md`。無新增依賴。
- **主清單 3 項**：
  - reaction 取消（第三輪重分析）：SDK `Timeline.addAggregatedEvent`
    （timeline.dart L507）建構時回填聚合**不過濾 `redacted`** → DB 殘留的
    已收回 reaction 讓 chips 永遠顯示自己的反應；對已收回事件 redact 又
    得 server M_NOT_FOUND → 洗版「反應失敗」。改：`_reactionsOf` 以官方
    `Event.redacted`（event.dart L58）過濾＋redact 之 M_NOT_FOUND／404
    視為取消已生效（不再視為失敗）。
  - 無權限房間：官方 `Room.canSendDefaultMessages`（room.dart L2402；
    powerLevels＋membership＋加密）判斷；無權限時輸入列**不渲染**、改
    「此聊天室僅供讀取」只讀列（文案草案）。
  - 取消釘選：根因＝`PinnedRoomsStore._writeRemote` 失敗被靜默吞掉，
    下一輪 `sync()` 聯集合併把 roomId「復活」。改 pinned_rooms.db
    **v2**：新增 `unpinned` tombstone 表（onUpgrade 相容）；
    查詢合併時 tombstone 優先——釘選／取消都以 tombstone 優先合併，
    遠端殘值不再復活本地已取消的釘選。手動已讀：長按選單加「標記為
    已讀」＝官方 `setReadMarker(room.lastEvent)`＋`markUnread(false)`
    （room.dart L630：`unread == markedUnread` 時 no-op 不丟錯）。
- **Issues 6 項**：
  - 滑到底自動跳頂（重分析）：三處來源——`_scrollToBottom` 在
    maxScrollExtent 短暫為 0 時 `jumpTo(0)`（＝最上層）；`_onScroll` 於
    extent==0 時 pixels 恆 0 反覆觸發 `_requestHistory`；`_load` 內容
    縮水時 offset 被 clamp。改：三處 guard＋縮水時保留「距底部距離」
    補償（增長維持原行為）＋`_requestHistory` 補償跳改為使用者仍在原
    位附近（±60px）才套用，不搶回捲動位置。
  - 頭像移除：長按相機徽章 → 確認 → 官方 `Client.setAvatar(null)`
    （client.dart L1673-1680，Synapse 相容以空字串送出）。有頭像時
    才提供長按入口。
  - 隱藏／刪除對話：app_settings.db **v2** 新增 `hidden_rooms` 表
    （本機過濾，不動伺服器）；長按選單「隱藏對話」；列表底部收合
    「已隱藏對話（n）」區可取消隱藏（草案 UI）。刪除＝確認後官方
    `Room.leave()`＋`Room.forget()`（room.dart L1493/1525）。
  - 投票自己可按：移除 `!isOwn` 條件（官方 msc3381 建立者投票無限制）；
    「結束投票」按鈕保留。
  - 私人聊天室名稱：`_roomTitle` 改官方 `Room.getLocalizedDisplayname()`
    （room.dart L228：name→canonicalAlias→directChatMatrixID／heroes
    成員名）；`'Empty chat'`／空回傳時退回旧 room.id（官方本地化字串
    不代表任何房間）。
  - 重開要求重新登入：根因＝冷啟動 `init` 逾時（8s）被外層 catch 成
    「無 session」導向登入頁（第二次啟動快取熱才成功＝「需要再重開」）。
    改：逾時重試一次（12s→30s）、發生錯誤也重試一次；僅 `init()` 正常
    完成且 `isLogged()==false` 才判定無 session 走登入。
- 測試修正插曲：`getLocalizedDisplayname` 在測試 fake room 回
  'Empty chat' → rooms 列表／MainShell 3 測試失敗；以「'Empty chat'
  時退回 room.id」規則修復後全綠（+128 ~1，見下）。
- 驗證：`flutter analyze` → **0 error（6 個既有 info）**；
  `flutter test` → **00:33 +128 ~1: All tests passed!**；
  `python3 ci/license_check.py` → **EXIT=0**；
  `flutter build apk --release` → **✓ app-release.apk (102.5MB)**（versionCode 2004）。
- 未決：9 項全需實機確認；reaction 若仍失敗需 logcat（此修正基於
  SDK 源碼可證的殘留路徑，無相關 dependency 變更）；隱藏／只讀列
  文案待人類定稿。

### 2026-11-03（第五次）— 實測回饋批次（滑到底跳頂第四輪 reverse 重構＋頭像 UX／快取＋聯絡人名稱＋未讀互斥；零新依賴）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/settings_screen.dart`、
  `app/lib/ui/contacts_screen.dart`、`app/lib/ui/rooms_screen.dart`、
  `app/test/ui_redesign_test.dart`、`app/test/contacts_screen_widget_test.dart`、
  `app/pubspec.yaml`（僅 version bump→1.0.2+2005）、`known_problems.md`、`PROGRESS.md`。
- ①「進房自動跳頂／滑到底被拉回頂部重抓舊訊息」（人類重現）：第四輪根因＝
  舊→新列表「底＝高 offset」定位法整體仰賴 lazy ListView 的估算 extent／
  逐 frame 補跳／offset clamp/補償，內容（進房自動補歷史、sync）一動即失準。
  改**Flutter 官方聊天室標準做法 `ListView(reverse: true)`**：
  - offset 0 ＝ 最新訊息 → 進房零跳轉（`_scrollToBottom` 簡化為 jumpTo(0)）；
  - 歷史插在高 offset 端（視覺上方）→ 視覺位置天然不動，`_requestHistory`
    的補償跳、`_load` 的縮水保位補償**全數移除**；
  - `_onScroll`：回看舊訊息＝遠離 offset 0；歷史觸發條件改
    `maxScrollExtent - pixels <= 100`（max==0 短列表不觸發）；
  - 日期分隔線以 `rows.reversed` 顯示，相對位置正確（分隔線在該天訊息前）。
- ②頭像：
  - UX（人類回饋）：長按改**點按**徽章 → bottom sheet 三選項「變更頭像
    （相簿）／拍照／移除頭像」；移除只在有頭像時顯示（草案 UI）。
  - 「移除沒有即時更新」根因＝SDK `_client.getUserProfile` 快取最長 1 天
    （client.dart L1152-1163）→ `fetchOwnProfile` 拿回舊頭像。改：變更／
    移除成功後立即用官方 `CachedProfileInformation.fromProfile(…, outdated:
    true)`＋`client.database.storeUserProfile` 標記過期 → 立即重抓 server。
  - 移除仍走官方 `Client.setAvatar(null)`（Synapse 相容空字串）。
- ③聯絡人名稱（人類回饋「好友名稱在聯絡人仍然無法顯示名稱」）：contacts_screen
  舊邏輯 `name→id`；套用與 rooms_screen 相同的官方 `getLocalizedDisplayname()`
  ＋`'Empty chat'` 退回 id。測試 fake room 缺成員 state → SDK 官方 fallback
  內 fire-and-forget `requestUser`（無 DB→LateError）→ 測試注入真實
  m.room.member state（`StrippedStateEvent`；契約不變）。
- ④未讀互斥（新 Issues）：長按選單「標記為已讀／未讀」依 `room.isUnread`
  二選一顯示（未讀→已讀；已讀→未讀）。- 驗證：`flutter analyze` → **0 error（6 個既有 info）**；
  `flutter test` → **00:34 +128 ~1: All tests passed!**；
  `python3 ci/license_check.py` → **EXIT=0**；
  `flutter build apk --release` → **✓ app-release.apk (102.5MB)**（versionCode 2005）。
- 未決：①②③④需實機確認；reaction 取消本輪未改（前輪第三階修正仍在待驗）；
  ①若 reverse 重構後仍跳頂，需 logcat／操作錄影。

### 2026-11-03（第六次）— 新問題 2 項＋ Suggestions 8 項（投票結束／頭像同步／草稿／通話紀錄在聊天室／放音切換／註冊提醒／主題色即時／icon/進階分區；零新依賴）
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/ui/settings_screen.dart`、
  `app/lib/main.dart`、`app/lib/ui/appearance_screen.dart`、
  `app/lib/ui/call_screen.dart`、`app/lib/ui/login_screen.dart`、
  `app/lib/app_settings.dart`、`app/android/.../res/mipmap-*/ic_launcher.png`（5 檔）+
  tests（`login_screen_widget_test.dart` 註冊 3 測、`ui_redesign_test.dart` 設定捲動）+
  `app/pubspec.yaml`（僅 bump→1.0.2+2006）＋ `known_problems.md` / `PROGRESS.md`。
- ①投票結束（人類回報）：end 事件被 editable 納入→自成一行露 SDK body
  `Unknown message format...`；isPoll 含 startedPollIds→已結束投票退化為純文字。
  改：editable 排除 end（Element X 行為：隱藏 end 事件）；start 恆以
  `_ChatPollTile` 渲染（`pollEndedCompat` 顯示「已結束」＋票數）。
- ②頭像同步第二根因：`_loadProfile` avatar url==null 直接 return→舊頭像停留；
  改清空＋新增 session 旗標 `_ownAvatarRemoved`（Synapse profile 快取仍回舊值
  期間 UI 恆不畫回舊頭像；更換成功即解除）。
- ③草稿（Suggestion #7＝#12 同一功能）：app_settings.db **v3** 新增 `drafts`
  表（room_id PK）；進房還原／離開 dispose 保存／送出成功清除（均 fire-and-
  forget；無 DB 環境忽略）。
- ④通話紀錄在聊天室（Suggestion #8）：editable 增官方 `EventTypes.CallInvite`
  （event_types.dart L28）；`_callInviteLabel` 以 content 官方 `video` 欄位回
  「語音／視訊通話」。hangup/reject 不列（避免洗版）。
- ⑤放音裝置（Suggestion #6）：通話控制列增切換鈕→flutter_webrtc 官方
  `Helper.setSpeakerphoneOn`（1.6.3 media_stream_track_impl.dart L83，官方
  取代已棄用 `enableSpeakerphone`）；`_answer()` 後自動套偏好。
- ⑥註冊提醒＋返回（Suggestion #3）：`_onOpenRegistration` 開瀏覽器前彈「保管
  帳號密碼＋recovery key」確認 dialog；`WidgetsBindingObserver.didChangeApp
  LifecycleState(resumed)`（官方）→ 顯示「註冊完成後請在此頁登入」＋聚焦。
  測試契約同步：3 個註冊測試點「我記住了，開始註冊」。
- ⑦主題色即時（Suggestion #4）：main.dart 新增官方 `ringSeedColor`
  ValueNotifier（同 ringTextScale 模式）；外觀頁選色即時重建 MaterialApp，
  移除舊文案「重啟 App 後生效」。
- ⑧進階分區（Suggestion #2）：設定頁新增「進階」：裝置驗證移入＋唯讀「診斷
  資訊」dialog（SDK client 官方欄位：userID/homeserver/deviceID/isLogged）。
  測試：設定清單捲動改迴圈（分區使 lazy ListView 變長）。
- ⑨icon（Suggestion #11）：design/drawing_icon.svg 經本機 inkscape 生成 5
  密度 ic_launcher.png（48/72/96/144/192），manifest 原指向不變，零依賴。
- 驗證：analyze → **0 error（6 既有 info）**；test → **+128 ~1 All tests passed!**；
  license_check → **EXIT=0**；apk → **✓ 102.5MB（versionCode 2006）**。
- 未決（待人類）：①②⑥⑧③④⑤⑨ 實機確認；reaction 取消；新 unchecked
  「部份訊息抓取失敗（not verified by its owner）但目標沒收到」＝加密範疇待
  批准＋logcat；通知依賴／多語言／CLI 待決；#1 自動上傳金鑰待批准。

### 2026-11-05（第七次）— room 內好友名稱＋投票票數最右＋金鑰自動化（人類批准範圍）；零新依賴
- 修改檔案：`app/lib/ui/chat_screen.dart`、`app/lib/auth.dart`、
  `app/lib/ui/login_screen.dart`、`app/pubspec.yaml`（僅 bump→1.0.2+2007）、
  `known_problems.md`、`PROGRESS.md`。
- ①room 內好友名稱（人類回饋「沒有修改到」）：chat_screen 訊息列直接渲染
  `m.sender`（@ID）。改 `_senderName()`：官方 `Room.getState(RoomMember)` →
  `StrippedStateEvent.asUser(room).calcDisplayname()`（SDK user.dart L97：
  displayname 優先、缺→localpart）；無 state 回退原 ID；**故意**不走
  `unsafeGetUserFromMemoryOrFallback`（fire-and-forget requestUser 觸 DB，
  測試環境 LateError——同 _senderAvatarUri 既有決策）。三處套用：訊號名
  /頭像 label/回覆預覽。
- ②投票票數最右（人類回饋）：_ChatPollTile 已投票／已結束選項列改
  Row＋Spacer——選項文字靠左、票數固定行最右端。
- ③Suggestion #1（人類批准 2026-11-05，範圍＝「只有更動進行順序和自動化」）：
  - 事實（SDK 官方源碼）：`Client.login()`→`init()` 已自動上傳 olm 裝置金鑰
    （olm_manager.dart L57-73 `uploadKeys(uploadDeviceKeys: true)`）；裝置
    「verified by its owner」還需 cross-signing／SSSS——官方入口
    `Client.initCryptoIdentity()`（crypto_setup_extension.dart）。
  - auth.dart 新增 `ensureFirstLoginCryptoIdentity()`：官方
    `getCryptoIdentityState()` 判態 → 未初始化**且**無任何 cross-signing/
    金鑰備份 account 資料（防誤 wipe 既有 identity）→ 官方 initCryptoIdentity()
    → 回傳新 recovery key；已初始化／部份建立 → 不動（人工恢復流程接管）；
    失敗回 null 不阻擋登入。**零自製加密邏輯**，僅官方 API 的順序與自動化。
  - login_screen：登入成功（非測試 stub 路徑）後呼叫上函式；新 recovery key
    **立即畫面顯示一次**（人類決定）：AlertDialog＋SelectableText 全選複製＋
    「複製」（官方 Clipboard.setData）＋「我已保管完成」；文案草案待人類定稿。
  - 測試注入 stub 路徑（widget.login != null）跳過此自動化（契約不變）。
- 驗證：analyze → **0 error（6 既有 info）**；test → **+128 ~1 All tests passed!**；
  license_check → **EXIT=0**；apk → **✓ 102.6MB（versionCode 2007）**。
- 未決：本三項待實機確認；reaction 取消／E2EE 抓取失敗（not verified by its
  owner）仍待人類資訊；通知依賴／多語言／CLI 待決。

### 2026-11-05（第八次）— 頭像移除持久化＋票數真最右＋已讀即時＋登入 recovery key 立即解密＋icon 滿版＋本地通知 v0；零新依賴
- 修改檔案：`app/lib/ui/settings_screen.dart`、`app/lib/ui/chat_screen.dart`、
  `app/lib/ui/login_screen.dart`、`app/lib/ui/main_shell.dart`、
  `app/android/app/src/main/kotlin/com/example/ring/MainActivity.kt`、
  `app/android/app/src/main/res/mipmap-*/ic_launcher.png`（5 密度重新生成）、
  `app/pubspec.yaml`（僅 bump→1.0.2+2008）、`known_problems.md`、`PROGRESS.md`。
- ①頭像移除「仍失敗」（人類回饋「如果清掉 cache 重新抓取？」）根因＝移除旗標僅
  session 級，重啟後失效；且 server（Synapse profile 快取）在 `setAvatar(null)`
  （官方 client.dart L1673-1683 以空字串送出）後可能回舊 `avatar_url`。改：
  旗標**持久化** AppSettings kv `own_avatar_removed`（initState 先載入）；
  期間 UI 恆不顯示頭像，直到 `_loadProfile` 由 server 明確回 null 才自動清旗標；
  成功更換頭像即解除。
- ②票數「應在最右邊，不是加個 tab 鍵」根因＝Spacer 在 shrink-to-child 的
  Column 內收斂成 0。改 `_ChatPollTile` 每選項列包
  `SizedBox(width: double.infinity)` 吃滿氣泡可用寬 → 選項靠左、票數貼右緣
  （卡片同步展為滿寬，同 Element X 樣式）。
- ③已讀「都沒有看到」根因＝receipt 走 sync **ephemeral** 通道
  （官方 `m.receipt` → `_handleEphemerals`（client.dart L2864-2885）→
  `Room.receiptState`），**不改變 `room.lastEvent`** → chat_screen `_syncSub`
  只比對 lastEvent → 已讀永不重畫。改：`_syncSub` 內以官方
  `Room.receiptState.global.otherUsers` 建 `_receiptSummary()`（誰→讀到哪），
  摘要變化即 `_scheduleReload()`（既有 1000ms 節流）。
- ④登入後詢問 recovery key 以解密（人類回報新項）：login_screen 在
  `ensureFirstLoginCryptoIdentity` 未走新帳號建立後，檢查官方
  `getCryptoIdentityState()`＝**initialized 且未 connected** → 彈對話框詢問
  recovery key／密語 → **官方 `Client.restoreCryptoIdentity(value)`**
  （crypto_setup_extension.dart：解鎖既有 SSSS＋自動自簽；SDK 後續 sync
  自動解密，**不需重開 App**）；失敗顯示「recovery key 或密語不正確（$e）」
  可重試；「略過」不阻擋登入。零自製加密邏輯（人類批准範圍＝進行順序與自動化）。
- ⑤icon 滿版（人類指示「改成滿版 icon」）：以
  `inkscape --export-area-drawing`（裁至繪圖邊界去透明留白）重新生成
  mipmap-{m,h,xh,xxh,xxxh}dpi（48/72/96/144/192px）；已驗證 5 檔正方形
  且檔案增大＝繪圖佈滿畫布。
- ⑥本地通知 v0（人類決定「走 local」；**零 pub 依賴**）：
  - Kotlin MainActivity.kt：MethodChannel `ring/local_notifications` `show`
    方法 → 原生 `NotificationManager`（頻道 `ring_messages`
    IMPORTANCE_DEFAULT；smallIcon `R.mipmap.ic_launcher`；setAutoCancel；
    以 room key hashCode 為 notification id）；Android 13+ 未授
    POST_NOTIFICATIONS runtime 權限 → 回 false。
  - Dart main_shell.dart：`client.onSync` 監聽 `_maybeNotify()`——僅
    **App 非前景**時對 `notificationCount > 0` 的房間發通知
    （title＝官方 `Room.getLocalizedDisplayname()`，'Empty chat'→room.id；
    body＝`room.lastEvent?.body`）；以 `_notifiedCounts`（roomId→count）去重；
    權限被拒即取消監聽不再嘗試（不洗版）；dispose 取消。
  - **固有限制披露：無 FCM → App 進程被殺（滑掉／重開機後未開）時收不到
    任何推播**；前台顯示不發通知。FCM／flutter_local_notifications 未經
    人類批准不引入。
- 驗證：analyze → **0 error（6 既有 info）**；test → **00:36 +128 ~1:
  All tests passed!**；license_check → **EXIT=0**；apk →
  **✓ app-release.apk (102.7MB)（versionCode 2008）**。
- 未決：①②③④⑤⑥全部待人類 APK 2008 實機確認；E2EE「not verified by its
  owner」待 logcat；多語言待語言截圖；CLI 後續；主題包 ④ 待 3 規格答案；
  reaction 取消待人類再回報。

### 2026-11-05（第九次）— icon 頁面匯出修正＋空房間補抓＋reaction 取消抑制＋頭像旗標唯一權威；零新依賴
- 人類回饋（APK 2008 實機）：①頭像需重開才消失（僅設定頁顯示）②icon 改壞
  ③某些 room 對話全部消失（一對一／加密／Element X 仍在／重開不恢復）
  ④reaction 仍無法取消。人類回覆重現資訊後批准四項動工。
- 修改檔案：`app/lib/ui/settings_screen.dart`、`app/lib/ui/chat_screen.dart`、
  `app/android/app/src/main/res/mipmap-*/ic_launcher.png`（5 密度重生成）、
  `app/pubspec.yaml`（僅 bump→1.0.2+2009）、`known_problems.md`、`PROGRESS.md`。
- ②icon（確定根因）：SVG 為 512×512 頁面＋底部 Ring（圓心 y=500，上半弧在
  畫布內）；批次八誤用 `--export-area-drawing` 裁到繪圖邊界＝把**頁面下方
  被切掉的半圓**也裁進圖（整顆圓＋下方露白）。改 `--export-area-page` 完整
  頁面匯出＝桃底滿版、Ring 弧貼底邊（原設計）；5 密度重生成＋目視驗證。
- ③對話全部消失：`_load()` 補抓歷史條件多一個 `messages.isNotEmpty` →
  **0 筆房間永不補抓**；且 `prev_batch==null` 時 SDK `getTimeline()` 不打
  server 回 0 筆；捲動觸發補抓因空列表無捲動高度又不成立 → 卡死。修正：
  條件改 `messages.length < 20`（0 筆也觸發）→ `_requestHistory` 既有官方
  /context 退路以 `room.lastEvent` bootstrap；`messages.first` 空列表取值
  加防護。純 timeline 顯示層，不碰解密／金鑰。
- ④reaction 取消（第四輪根因，SDK 官方源碼）：收回事件只標記兩種目標——
  `room.lastEvent`（client.dart L3184-3188）或**仍在目前 timeline chunk**
  的事件（timeline.dart L688-708 `_findEvent` 找不到即跳過、聚合樹不清除）
  ；自己的 reaction 幾乎總是早於本 chunk → 官方收回已生效但聚合殘留未標記
  物件 → `Event.redacted` 永不成立、第三輪的過濾救不到。修正（UI 資料層；
  SDK 無清除聚合的官方介面）：session 抑制清單 `_cancelledReactions`
  （官方收回成功／M_NOT_FOUND 即加入 `_reactionsOf` 吞掉自己那筆，重送同
  emoji 解除）。**已知限制：跨 session DB 殘留（重開後）本輪未處理**。
- ①頭像（僅設定頁顯示）：旗標改**唯一權威**——`_loadProfile` 不再「server
  回 null 自動清旗標」（Synapse cache 往回跳＝鬼影破口），只在成功設定新
  頭像時解除；kv 寫入改 await＋失敗如實提示（原 unawaited 空吞＝落盤失敗
  無從得知）。
- 驗證：analyze → **6 issues（全既有 info），0 error**；test →
  **00:38 +128 ~1: All tests passed!**；license_check → **EXIT=0**；apk →
  **✓ app-release.apk (102.7MB)（versionCode 2009）**。
- 未決／下一步提案（known_problems.md 新發現、未列入本批）：L45「room 上方
  名稱仍為 ID」根因＝chat_screen L1402 AppBar 用 `room.name`（DM 常空→ID）
  ，應改官方 `getLocalizedDisplayname()`（待人類批准）；L62「URL 偵測點選
  」待人類補範圍；reaction 跨 session 殘留待人類重開實測後再決定 kv。
  E2EE「not verified by its owner」仍待 logcat；多語言／CLI／主題包 ④
  維持等待。

### 2026-11-05（第十次）— 投票「：N 票」＋room 上方名稱＋群組通話放音裝置按鈕＋URL 點選；零新依賴
- 人類指示（known_problems.md 筆記＋「先處理票數、ID、放音裝置、URL」）。
- 修改檔案：`app/lib/ui/chat_screen.dart`（投票格式／AppBar 名稱／URL 偵測）、
  `app/lib/ui/group_call_screen.dart`（放音裝置按鈕）、
  `app/pubspec.yaml`（僅 bump→1.0.2+2010）、`known_problems.md`、`PROGRESS.md`。
- ①投票票數（人類新指示「恢復原先設計位置，但改成「：(num) 票」」）：撤回
  批次八滿寬列（SizedBox(double.infinity)＋Spacer），恢復緊湊 Row；票數跟在
  選項文字後，統一格式「：N 票」（labelSmall 字級）。
- ②room 上方名稱仍為 ID（根因＝AppBar `room.name ?: room.id`，DM 的
  `Room.name` 常為空）：改官方 `Room.getLocalizedDisplayname()`
  （room.dart L228：name→alias→direct chat 成員名）；'Empty chat'／例外出
  回 room.id 保底。
- ③放音裝置「沒有專門控制的按鈕（根因＝按鈕只在 1:1 call_screen，群組通話
  group_call_screen 控制列漏掉）：補同款——`_speakerOn`＋官方
  `Helper.setSpeakerphoneOn`（media_stream_track_impl.dart L83）；加入通話
  後套用偏好；切換失敗提示＋UI 回退；按鈕放「切換鏡頭」與「分享螢幕」間。
- ④URL 點選（新項，人類未定範圍→先做最小）：訊息 body `_linkifiedBody`
  偵測 http/https（RegExp；行尾標點剝離）→ 可點樣式（主題色＋底線）→
  既有依賴 `url_launcher` `launchUrl(externalApplication)` 開外部瀏覽器；
  失敗靜默；零新依賴。
- 驗證：analyze → **6 issues（全既有 info），0 error**；test →
  **00:36 +128 ~1: All tests passed!**；license_check → **EXIT=0**；apk →
  **✓ app-release.apk (102.7MB)（versionCode 2010）**。
- 未決：四項待實機；頭像移除已由人類標「暫時放棄」不再動；reaction 跨
  session 殘留待人類重開實測；多語言／CLI／主題包 ④／E2EE logcat 維持等待。

### 2026-11-05（第十一次）— 放音裝置改 Discord 式輸出選單＋Adaptive Icon（滿版根因）；零新依賴
- 人類指示（known_problems.md 筆記：「請依照 Discord 設計修改」＋參考圖
  dc/1793614407662.jpg；「Android icon 圖形用方形以外的圖形就會沒辦法滿版」）。
- 修改檔案：`app/lib/ui/call_screen.dart`、`app/lib/ui/group_call_screen.dart`、
  `app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`（新）、
  `app/android/app/src/main/res/drawable/ic_launcher_background.xml`（新）、
  `app/android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`（新×5
  密度）、`app/pubspec.yaml`（僅 bump→1.0.2+2011）、`known_problems.md`、
  `PROGRESS.md`。
- ①放音裝置 Discord 式選單（1:1＋群組通話同款）：按鈕改開底部 sheet——
  「選擇音訊輸出」＋分組「這個電話」＝電話（聽筒）／喇叭、radio 顯示當前
  （骨架樣式；文案照 DC 範本格式待定稿）；選擇後走官方
  `Helper.setSpeakerphoneOn`（`_setSpeaker`，失敗提示＋UI 回退；加入通話
  後仍套用偏好）。披露：現階段僅兩項（官方 Helper 無裝置清單來源）。
  已清掉批次十的 `_toggleSpeaker`（被 sheet 流程取代）。
- ②Adaptive Icon（滿版根因＝Android 8+ launcher 遮罩）：新增
  `mipmap-anydpi-v26/ic_launcher.xml`（背景＝桃色 #FFBD9F drawable 全滿版；
  前景＝Ring 去背縮入官方安全區 66/108＝61%，自 design/drawing_icon.svg
  抽出兩 circle 以 transform 縮放生成）＋5 密度 ic_launcher_foreground.png
  （108/162/216/324/432px；四角透明已驗證）；舊方形 PNG 保留作 API 25-
  fallback；manifest 免改。**披露：Ring 擺位為骨架計算（弧底部在安全區邊緣
  會被截），最終視覺待人類實機遮罩後定稿**。
- 已讀顯示：人類標「沒有看到，暫時放棄」→ 停止處理（批次八修復仍留在碼內）。
- 驗證：analyze → **6 issues（全既有 info），0 error／0 warning**；test →
  **00:31 +128 ~1: All tests passed!**；license_check → **EXIT=0**；apk →
  **✓ app-release.apk (102.7MB)（versionCode 2011）**。
- 未決：①②待實機（icon 前景擺位／選單文案）；多語言／CLI／主題包 ④ 維持
  等待；E2EE logcat 維持等待。

### 2026-11-07（第十二次）— 主題包 v0＋全域桌布、通知設定分區、room 資訊頁、下載進度＋Size、緊急訊息橫幅（Phase 4.1-4.3）；零新依賴（pubspec 僅 bump 2012）
- 人類指示（2026-11-07 batch「all」＝五項同批；開工前回報已批准）。
- 修改檔案：`app/lib/app_settings.dart`（v3→v4）、`app/lib/ui/appearance_screen.dart`、
  `app/lib/ui/notification_settings_screen.dart`（新）、`app/lib/ui/room_info_screen.dart`
  （新）、`app/lib/ui/main_shell.dart`、`app/lib/ui/settings_screen.dart`、
  `app/lib/ui/chat_screen.dart`、`app/lib/ui/rooms_screen.dart`、
  `app/pubspec.yaml`（僅 bump→1.0.2+2012）、`THEME_FORMAT.md`（新，草稿須人工審）、
  `known_problems.md`、`PROGRESS.md`、`DEPENDENCIES.md`（**補列 unifiedpush**：
  上批人類批准後已在 pubspec、僅漏記錄本檔，非新依賴；SPDX 依 pub-cache LICENSE
  覆核 Apache-2.0）。**未動 main.dart**（原開工回報列入，實作後確認種子色／桌布
  皆走既有接線，無需改）。**未動 pubspec 依賴**（lock 與 HEAD diff=0）。
- ①主題包 v0（分項選取）：app_settings.db v4＝`themes`（name/seed/wallpaper/
  created_at）＋`announcement_rooms`（⑤旗標）兩表（onCreate＋onUpgrade<4 共用
  `_createV4Tables`）；appearance 頁「我的主題」（RadioListTile 套用／建立＝
  FilePicker 圖＋命名（種子沿用當下主題色）／刪除），套用＝kv `selected_theme_id`
  ＋種子色（ringSeedColor 即時生效）＋全域桌布；「全域聊天室背景」Colors／
  Your photos／重置＝kv `chat_wallpaper`；chat_screen 背景＝per-room 優先→
  全域 fallback（含重置／設「預設」兩路徑同步回退）。**未做**：zip 主題包（需
  `archive` 依賴待批准）、圖標（Android 限制）、字型（授權待查證）、輪播／商店。
- ②通知設定：`notification_settings_screen`（顯示通知總開關＋顯示訊息內容），
  kv `notifications_enabled`／`notification_preview`；main_shell `_maybeNotify`
  總開關先擋、preview off 時通知正文打『新訊息』；設定頁一般區入口。
  Mentions 等分區待 SDK 官方條件（LINE 專屬區塊不投射）。
- ③room 資訊頁：`room_info_screen` 骨架＝顯示名／ID／topic／成員數、靜音（官方
  `Room.pushRuleState`/`setPushRuleState`）、成員管理（既有畫面）、邀請（官方
  `Room.invite`）、退出（官方 leave＋forget，確認文案同 rooms_screen）、
  公告房間 SwitchListTile（本機旗標）；chat_screen 選單新增「聊天室資訊」入口。
- ④下載進度＋Size：`_formatBytes`；檔案列 Size 行（官方 `event.infoMap['size']`）；
  開附件＝官方 `Event.downloadAndDecryptAttachment(onDownloadProgress:)`（event.dart
  L821/L957）進度對話框（下載中…／X / Y／進度列＋取消；取消＝僅關 UI，背景下載
  續行寫暫存＝v0 披露；無 size 時進度條不定值）。
- ⑤緊急訊息橫幅（Phase 4.1-4.3 草案）：聊天室內＝最新官方釘選（`Room.pinnedEventIds`
  room.dart L185→`Room.getEventById` L2225→資訊列（未讀列與訊息列間）；點擊
  Scrollable.ensureVisible 跳轉（分頁外不假跳，提示捲動）＋尾端官方取消釘選
  `setPinnedEvents` L676）；首頁＝公告房間∩最新官方釘選→橫幅座（搜尋列下，點擊開
  聊天室）。4.4 自動取消釘選／4.5 官方 bot＝**未做**（藍圖待人工決定）；觸發條件
  （公告房間∩最新釘選）為草案，Human 可否決改法。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 10.5s)`**（注：比上輪
  摘要基準 6 info 少——本輪未動測試／基準檔，詳留待人類重跑複核）；test →
  **`00:40 +143 ~1: All tests passed!`**（與上輪摘要 +128 差 +15：`git status app/test/`
  零變更、pubspec.lock 與 HEAD 一致，差異原因待核對）；license_check → 首跑 **EXIT=1**
  （unifiedpush DEP 檔漏列→補列後）**EXIT=0**；apk →
  **`✓ Built build/app/outputs/flutter-apk/app-release.apk (130.8MB)`**＋aapt2 實測
  **`versionCode='2012' versionName='1.0.2'`**。**披露：APK 變 130.8MB（上輪 102.7MB）**
  ——本輪以預設 `flutter build apk --release`（3 ABI universal：arm64-v8a／
  armeabi-v7a／x86_64，aapt2 native-code 實錄）建出；上輪 102.7MB 對應之建置參數
  （可能為 target-platform 收縮）無法從本 round 工作區重現，**是否改回收縮版待人類定**
- 未決：zip 主題包（archive 依賴）、字型打包（授權查證）、Phase 4.4／4.5、 Mentions
  分區、橫幅／主題視覺定稿；已讀顯示（L58）／頭像移除（L36）維持人類標記「暫時放棄」。

### 2026-11-07（第十二批修補，同日）— 通知啟動修復：補 POST_NOTIFICATIONS runtime 請求路徑；零新依賴
- 人類回報（十二批 2012 實機）：「通知功能沒辦法啟動」。
- 根因（三處合擊，唯讀分析確認）：①`push_permission_screen._defaultRequest()`＝
  `return false` 骨架 stub——「推播通知權限」頁按鈕從未發出系統請求（AndroidManifest
  L19 已聲明 POST_NOTIFICATIONS，只差 runtime）；②MainActivity `show` 於 Android 13+
  未授權回 false（L41-47 既有）；③main_shell `_maybeNotify` 收 false 後
  `_notifSync?.cancel()` **永久停輪詢**（授權後仍需重開 App）。
- 修改檔案：`app/android/app/src/main/kotlin/com/example/ring/MainActivity.kt`
  （channel 新增 `check_permission`／`request_permission`：框架 Activity.requestPermissions
  ＋onRequestPermissionsResult 回填（super 先行）；「不再詢問」由系統直接回拒＋
  Dart 提示指引）、`app/lib/ui/notification_settings_screen.dart`
  （`checkNotificationPermission`／`requestNotificationPermission` helper＋
  `ringNotificationPermission` 執行緒（loadNotificationPrefs 進殼即查現狀）；
  開總開關＝先請求權限，拒絕→退回關＋提示系統設定路徑；新增系統權限現狀列＋
  「請求權限」入口）、`app/lib/ui/main_shell.dart`（`_notifyPermDenied` 旗標取代
  永久 cancel；監聽權限執行緒＝授予即解除＋輪詢復活；dispose 雙向移除）、
  `app/lib/ui/push_permission_screen.dart`（`_defaultRequest` 改接同一 channel；
  說明文更新；注入參數保留＝既有測試契約不破）、`app/pubspec.yaml`
  （僅 bump→1.0.2+2013）、`known_problems.md`、`PROGRESS.md`。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 15.1s)`**；test →
  **`00:59 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**；apk →
  **`✓ Built build/app/outputs/flutter-apk/app-release.apk (130.8MB)`**（Gradle
  Kotlin 編譯過）＋aapt2 **`versionCode='2013' versionName='1.0.2'`**。
- 待實機：①開總開關彈系統授權框→同意→App 切背景收訊→通知出現；②拒絕後提示
  ＋到系統設定授權→回 App 不重開即恢復輪詢；③「顯示訊息內容」off 通知只顯示
  『新訊息』；④「推播通知權限」頁按鈕同樣可授權。

### 2026-11-07（第十三次）— ①外部音訊輸出分組 ③reaction 跨 session 殘留官方掃除＋頭像 race 修＋外部分享 Send-to picker；零新依賴
- 人類批准內容（「1, 3；②新版 apk 待測試；處理已讀功能、頭像移除；外部分享
  功能參考 EX 截圖」）。
- **①外部音訊輸出裝置分組**：`app/lib/ui/call_screen.dart`＋
  `app/lib/ui/group_call_screen.dart`（兩份同款 sheet）新增「外部裝置」分組：
  官方 `navigator.mediaDevices.enumerateDevices()`（flutter_webrtc
  mediadevices_impl.dart L110 包 getSources；原生 MethodCallHandlerImpl.java
  L1849 回 `AudioSwitchManager.availableAudioDevices()` 含藍牙／有線輸出）
  過濾 kind=audiooutput＋剔除內建 speaker/earpiece → radio 列；選取走官方
  `Helper.selectAudioOutput(kind)`（helper.dart L128 → 原生 L880
  AudioDeviceKind.fromTypeName）；聽筒／喇叭維持 `Helper.setSpeakerphoneOn`。
  `_externalAudioDevice` 狀態（選內建即清）；**披露**：deviceId＝
  AudioDeviceKind 種類名（AudioDeviceKind.java L8-12），非特定耳機 unique id
  ＝套件 1.6.3 上限（兩支藍牙耳機同名同選）。
- **③reaction 跨 session 殘留**：`app/lib/ui/chat_screen.dart` 新增
  `_scheduleReactionResidueRefresh`＋去重 set——`_reactionsOf` 遭遇自己反應
  但非本 session 送出 → 背景官方
  `Timeline.fetchAggregatedEvents(targetId, RelationshipTypes.reaction)`
  （timeline.dart L548；/relations 權威清單；`addAggregatedEvent` L507 的
  `_removeEventFromSet` 以 server 回的新物件替換舊殘留；已收回者依規格被
  redact＋`m.relates_to` key 剝除 → `Event.redacted` 過濾自然生效）。
  **放棄** kv 持久化抑制清單方案。成本披露：每則有你反應過的訊息每 session
  至多一次背景查詢（SDK 對同 relation 成功後跳過重抓、失敗可重試）。
- **頭像移除 race 修**（真根因，唯讀發現）：`app/lib/ui/settings_screen.dart`
  initState 原本旗標 kv（fire-and-forget）與 `_loadProfile()` 同時起跑 →
  kv 晚到時舊頭像已畫、旗標就位不再清。修＝新 `_initAvatarState()`：先
  await 旗標就位（含 setState）才抓 profile（順序保證）。
- **外部分享 Send-to picker**：新 `app/lib/ui/share_to_room_screen.dart`
  （EX 截圖結構：搜尋列＋房間列表 avatar／名稱／alias＋多選 checkbox＋
  右上送出；官方 `getLocalizedDisplayname`（room.dart L228）／
  `canonicalAlias`（L313，非空 String）／`avatar`（L294）／
  `Room.sendTextEvent`（L688）逐一送、部分失敗回報不中斷）；
  `app/lib/ui/main_shell.dart` `_listenShareReceiver` 改 push 全頁 picker、
  刪除舊 `_showShareToRoomDialog` stub。**披露 v0**：接收端 app_links 只帶
  連結／文字 uri——檔案型分享需 native intent 整線＝後續待人類決定；
  UI＝骨架草案（EX 僅參考結構，不仿品牌樣式），待人類定稿。
- **已讀重開複驗（無碼改）**：唯讀重查 receipts 全鏈（receipts.dart L243
  `update()` 分 ownPrivate/ownPublic；chat_screen `_receiptSummary` 比對→
  reload；room.dart L1751-52 `setReadMarker` 每 read 恆送 public+private）＝
  無缺陷可修；最可疑＝對方端 private receipt（⚠️待查證），等 2013/2014 實測
  ＋logcat。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2014）、`known_problems.md`
  （L9③／L36頭像／L58外部裝置／L61已讀／Suggestions 外部分享新條目）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.5s)`**；
  test → **`00:39 +143 ~1: All tests passed!`**；license_check →
  **LICENSE_EXIT=0**（26 項零變動）；apk →
  **`✓ Built build/app/outputs/flutter-apk/app-release.apk (130.9MB)`**
  ＋aapt2 **`versionCode='2014' versionName='1.0.2'`**。
- 待實機：①通話中輸出選單出現「外部裝置」分組（連藍牙／有線後測）＋切回
  聽筒即回內建；②reaction：上一 session 反應重開 App 後殘留消失（或確認為
  仍有效反應則照常顯示）；③設定→移除頭像→重開 App＝不再回舊頭像；④從
  瀏覽器分享連結到 Homing→Send-to 選房（可多選）→送出成功。

### 2026-11-07（第十四次）— 通知重開不重發舊訊息＋搜尋不區分大小寫＋通知已讀/回覆動作；零新依賴
- 人類批准內容：「軟體重開後一直跳出靜音前收到的通知；搜尋聊天室名稱改為英文不限大小寫；讓點選通知後能進入對應聊天室，並在通知加入已讀和回覆按鈕，不須進軟體才能回覆」。
- **通知重開不重發舊訊息**：`app/lib/ui/main_shell.dart` `_notifiedCounts`（per room 已通知 count）寫入即持久化到 `app_settings.db` kv（`notif_count_<roomId>`，`AppSettings.set`/`remove`）；initState 新增 `_restoreNotifiedCounts()` 讀回 kv，避免重開 App 後記憶體為空而把「靜音前已收、未彈過」的舊訊息重新彈出（即「軟體重開後一直跳出靜音前收到的通知」的根因）。ok == false（未授權）時回滾 kv。
- **通知「已讀／回覆」動作＋點開進房間**：`app/android/app/src/main/kotlin/com/example/ring/MainActivity.kt` 原生通知新增 `setContentIntent(openPending)`（點開進對應房間，帶 `ring_notif_action=open`＋`ring_room_id`）＋「已讀」（`ring_notif_action=read`）與「回覆」（`ring_notif_action=reply`，`RemoteInput` 輸入框）兩個 `Notification.Action`；新增 `cancel` method、PendingIntent extra 讀取（`onCreate`/`onNewIntent`、`pendingIntentFlags` 相容 Android 12+ `FLAG_IMMUTABLE`）、`sendNotificationActionToDart` 把動作轉發 Dart。Dart 端 `_notifyChannel.setMethodCallHandler` 接收 `notification_action` → `_onNotifAction`：`read` 走官方 `room.setReadMarker(last.eventId)`（每 read 恆送 public+private receipt；client.dart `receiptsPublicByDefault=true`、room.dart L1751-52）；`reply` 走官方 `room.sendTextEvent(replyText)`（加密房 SDK 自動加密，App 端不介入）；`open` 直接 `push` 對應 `ChatScreen`；任何動作後皆 `cancel` 該房間通知＋清 kv。
- **搜尋聊天室名稱不區分大小寫**：`app/lib/ui/rooms_screen.dart` `build` 的 `filtered` 比較，`_roomTitle(r)` 與 `r.id` 皆 `.toLowerCase()` 後再 `contains(_search.toLowerCase())`。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2015）、`known_problems.md`（L57通知項／L61已讀項加批次十四批註＋新增搜尋不區分大小寫條目）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 6.1s)`**；test → **`00:34 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；apk → **`✓ Built build/app/outputs/flutter-apk/app-release.apk (130.9MB)`** ＋aapt2 **`versionCode='2015' versionName='1.0.2'`**。
- 待實機：①重開 App 後不再彈出「靜音前已收」的舊通知（僅新訊息彈）；②通知欄「已讀」按鈕後該房間未讀數歸零／收到 public+private receipt；③通知欄「回覆」輸入後訊息送達對應房間；④點開通知直接進入對應聊天室；⑤首頁搜尋輸入英文大小寫皆命中房間名稱。

### 2026-11-07（第十五次）— 好友控制功能；零新依賴
- 人類指示內容：「增加好友控制功能」（參考 LINE_ref/new_ref/friends/ 四張標註截圖：好友長按選單／刪除好友確認／封鎖確認；截圖僅作**結構參考**，不複製 LINE 品牌樣式，UI＝骨架草案）。
- **`app/lib/ui/contacts_screen.dart`**（好友控制全部實作於此，官方 SDK API、零新依賴）：
  - 長按好友（direct chat）tile → `_showFriendActions` bottom sheet：聊天／語音通話／收藏（收藏⇄取消收藏）／隱藏／刪除好友（紅）／封鎖（紅）或解除封鎖；群組 tile 維持原行為。
  - 收藏＝本機 kv `favorite_contacts`（`jsonEncode` 收藏 roomId 清單於 app_settings.db）；好友區顯示依 `_sortedFriends()` 收藏置頂（其餘維持最新訊息時間排序）、收藏者尾端星形圖示；不新增段落 header（保住測試契約「空清單文案第 1 個 ListTile=direct chat」）。
  - 隱藏＝沿用本機 `AppSettings.hidden_rooms` 表（`rooms_screen` 同源）；聯絡人頁 `_load` 自此也過濾該清單，隱藏後即從列表移除。
  - 刪除好友＝確認對話框「要解除好友並刪除『name』嗎？」→ 官方 `Room.leave()`＋`Room.forget()`（同 rooms_screen._deleteRoom 模式）。
  - 封鎖／解除封鎖＝官方 `Client.ignoreUser()`／`unignoreUser()`（matrix 14.2.0 client.dart L3954/L3991，寫入官方 `m.ignored_user_list` account data），getter `Client.ignoredUsers`；封鎖確認對話框「封鎖『name』？您將不會再收到此帳號的訊息。您可以在『封鎖名單』中解除封鎖。」；已封鎖好友尾端禁止符圖示。**v0 無獨立「封鎖名單」管理頁**（解除封鎖＝長按選單），管理頁待後續批次。
  - 語音通話＝官方 `CallManager.startCall(room, video: false)` → push `CallScreen`（同 chat_screen._startCall 模式，含既有通話／來電回入判定；`callManager==null` 時提示「通話功能不可用」）。
  - 本批新增 imports：`dart:async`/`dart:convert`/`../app_settings.dart`/`call_screen.dart`。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2016）、`known_problems.md`（新增「好友控制功能」條目）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 9.0s)`**；test → **`00:29 +143 ~1: All tests passed!`**（contacts_screen_widget_test 契約未破）；license_check → **LICENSE_EXIT=0**（26 項零變動）；apk → **`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.0MB)`** ＋aapt2 **`versionCode='2016' versionName='1.0.2'`**。
- 待實機：①長按好友出現「聊天／語音通話／收藏／隱藏／刪除好友／封鎖」動作選單；②收藏後該好友置頂＋星形圖示，重開 App 仍在置頂；③隱藏後好友從聯絡人消失（首頁亦不顯示）；④刪除好友經確認後列表消失；⑤封鎖後尾端禁止符圖示，且再次長按時顯示「解除封鎖」；⑥解除封鎖後恢復；⑦語音通話可撥出；已有進行中的通話／來電時回到該通話畫面；manager 不可用時提示「通話功能不可用」不閃退。

### 2026-11-07（第十六次）— 緊急示警 PWS RSS v0（官方 NCDR 聚合 feed）；零新依賴
- 人類批准：第十六批走 RSS（「先 RSS」＝不用中央氣象署 API、不涉授權碼）＋三項範圍決定：**僅高風險類別／僅首頁橫幅（不彈通知）／15 分鐘前景輪詢**。
- **官方端點查證（2026-11-07 live）**：聚合 feed `https://alerts.ncdr.nat.gov.tw/RssAtomFeeds.ashx`（plural、不帶參數）HTTP 200 application/xml、無需登入與金鑰；feed 自帶 `<rights>Public Domain</rights>`；entry 結構 id/title/updated/author（發布機關）/link（.cap 檔）/summary/category/`cap:status`/`cap:msgType`/`cap:effective`/`cap:expires`（後兩者為 zh 本地化格式「2026/11/8 下午 11:00:00」）。**同日對照：人類原提之 cbs.tw 第三方 mirror `updated` 停在 11-02（5 天）→ 棄 mirror 用官方端點**。
- **官方法規／授權查證（2026-11-07）**：開發專區 CAPATOMfeedRules.pdf（每分鐘更新、7 天回溯、test 勿用於對外產品、須 id 去重＋expires 判斷）+ 常見問題（ATOM「所有示警/生效中的示警」不登入可用；KML/推送/API 需會員）+ 資料集 20457 授權＝政府資料開放授權條款-第1版（OGDL-TW-1.0，data.gov.tw/license：不限目的免授權金；**第 3 條(二) 顯名義務未盡=自始未授權**；不含專利/商標；不免責、可停止提供）。
- **`app/lib/emergency_feed.dart`（新檔）**：dart:io HttpClient＋手寫迷你 Atom 剝析（零新依賴）；僅取 `cap:status=Actual`＋`cap:msgType≠Cancel`＋`cap:expires>now`；`kHighRiskCategories` 白名單（草案：地震速報／地震報告／海嘯／颱風／淹水／土石流／疏散避難；待人類增修，常數一處＋`categories` 參數注入）；zh 時間自訂解析；4MB 逾量防呆；失敗回空清單不出錯不重試轟炸。
- **`app/lib/ui/main_shell.dart`**：`_startEmergencyPolling` 進殼即抓一次＋Timer.periodic 15 分鐘（人類決定）；entry id 指紋無變化不 setState；dispose 取消 timer；FLUTTER_TEST 環境不啟動（widget 測試避免 pending Timer/網路）。
- **`app/lib/ui/rooms_screen.dart`**：首頁緊急橫幅座（批次十二⑤機制）擴充 PWS 條目（類別＋發布機關＋本地時間＋摘要；onTap=null v0 無詳情頁）；橫幅下方顯名＋免責小字（「資料來源：國家災害防救科技中心 民生示警公開資料平台（政府資料開放授權條款）／示警可能延遲或不完整；緊急時請以中央氣象署及地方政府原發布管道為準」）。構造參數 `emergencyAlerts` 預設空清單（測試不受影響）。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2017）、`known_problems.md`（新增「緊急訊息用 PWS 通知」條目＋六項限制披露）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.4s)`**（二次確認 `ran in 14.3s` 無 issues）；test → **`00:34 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；apk → **`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.0MB)`**（Gradle 153.6s）＋aapt2 **`versionCode='2017' versionName='1.0.2'`**。解析器離線驗證：對 2026-11-07 實抓官方 feed XML，3 entry 全部解析成功（水庫放流／降雨／強風，含 zh 時間與 cap 檔 link），白名單過濾結果符合預期。
- 待實機：①App 開啟時若有高風險類別示警（如地震速報）→ 首頁頂部出現緊急橫幅＋來源/時間/摘要＋顯名/免責小字；②無黑名單類別示警時不顯示；③示警過期（expires）後不再顯示；④飛航/斷網時不出錯、回復網路後下次輪詢恢復；⑤15 分鐘內 App 背景凍結不產生耗電異常。

### 2026-11-07（第十七次）— 頭像移除即時刷新①＋通話音訊路由②-A＋遠端流重綁②-B＋已讀兜底③；零新依賴
- 人類實測 APK 2014/2015 回饋（2026-11-07）＋分判答案：頭像移除「顯示成功＋重開正常＋當下就應該消失」；外接裝置「偵測不到＋未發揮作用」；已讀「沒有任何顯示文字或符號」；②-B 對端＝Homing（versionName=1.0.2，**versionCode 待補**）；螢幕分享聲音＝**跳過**（flutter_webrtc 1.6.3 Android `getDisplayMedia` audioTracks 恆空，GetUserMediaImpl.java L584-614；不再回訪）。
- ①根因（已定）：`settings_screen.dart` L401 `FutureBuilder(future: _profileAvatar == null ? null : Future.value(...))`——Flutter FutureBuilder 於 future 變 null 時僅把 snapshot 切成 ConnectionState.none、**data 保留**（AsyncSnapshot.inState 官方行為）→ `snap.hasData` 恆真 → 舊頭像停留；重啟後 snapshot 起始為空才正常。**修**：拆 FutureBuilder，`_profileAvatar` 直接渲染；相機徽章抽共用 `_avatarCameraBadge()`。
- ②-A 根因（已定）：偵測——原生 audiooutput 全數來自 `AudioSwitchManager.instance.availableAudioDevices()`（MethodCallHandlerImpl.java L1849），`AudioSwitch.start()`（AudioSwitchManager.java L163-169）的非同步掃描回調才就緒，sheet 開啟當下一次同步呼叫常落空；選擇——原生 `selectAudioOutput` 在 `audioSessionManagementEnabled=false` 時直接 no-op（AudioSwitchManager.java L217 一帶，Dart 層無從查知）。**修**：`_externalAudioOutputs` 空清單重試至多 5 次×600ms＋抽出 `_enumerateAudioOutputsOnce`；`_applyExternalAudio` 套用後單次枚舉二次驗證（選 kind 不在清單→提示「找不到所選放音裝置，可能已斷線」＋回退）；call_screen／group_call_screen 兩份 sheet 同步。
- ②-B 修與續查：SDK `setMicrophoneMuted`／`setLocalVideoMuted`（call_session.dart L826-829／L749-754）經 `updateMuteStatus()`（L1235-1256）已統一翻轉 track enabled＋送 `m.call.sdp_stream_metadata`——移除我們批次 II⑥ 的手動 track.enabled 雙寫（mic／camera 兩處）。Homing 兩端原本遠端流只綁一次且不響應變更 → 訂閱官方 `session.onCallEventChanged`（L109），kFeedsChanged（遠端 metadata 事件 fire，onSDPStreamMetadataReceived）→ `_attachStreams()` 重查重綁（identical guard 不重初始化）；dispose 取消；group_call_screen 已有自己的 `_addSub`/`_removeSub` 串流增減訂閱，免改。**仍待**：人類一節 logcat（`adb logcat -d | grep -iE "voip|mute"`；SDK 會印 `Stream purpose update: ... audio_muted/video_muted`）分辨 A 端 metadata 的 video_muted 值（true→A 端旗標/track 異常；false→B 端渲染鏈）。
- ③根因＋修：發送（`setReadMarker` room.dart L1743-1756＝m.fully_read＋public receipt（`client.receiptsPublicByDefault` 預設 true，Homing 未覆蓋）＋private）與收受（sync ephemeral `_handleEphemerals` client.dart L2859-2883→`LatestReceiptState`；SDK sync filter 預設不排除 ephemeral）皆官方正常。缺口＝官方 `event.receipts`（event.dart L315+）要求他人 receipt eventId 與本訊息 eventId **完全相等**，但對端 markAsRead target＝其房間 lastEvent，夾帶任何後到事件（對端自己的回覆等）即永不相等→真實流程幾乎永不顯示。**修**：`_isReadByOthers` 兩段判定＝快路 eventId 相等＋兜底「任一他人 global receipt ts ≥ 本訊息 originServerTs」（同為 server 時鐘；receipt 晚於本訊息送出⟺讀到本訊息或更後）；receiptSummary 重畫節流沿用。**仍需對端 versionCode**：若對端 < 2015 根本不送 receipt，本修救不了。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2018）、`known_problems.md`（頭像／外接／已讀三條根因重註記＋人類補答＋兩處 logcat 指令）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.4s)`**；test → **`00:34 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；apk／aapt2 待 build 完補貼。
- 待實機（APK 2018）：①移除頭像當下立即清空（不需重開）；②通話中開「選擇音訊輸出」sheet 能列出藍牙／有線裝置且選擇生效（裝置斷線時有提示）；③靜音／關閉攝影機後對端畫面不再黑掉；④已讀：對端讀取後本端最新自訊出現「已讀」小字。

### 2026-11-07（第十八次）— 藍牙放音權限 BLUETOOTH_CONNECT（②-A 根因修）＋封鎖名單獨立頁；零新依賴
- 人類實測 APK 2018 回饋（2026-11-07）：頭像＝**成功**；攝影機＝**失敗**（同分鐘 22:57 兩端截圖：手機 A 兩格皆有影像、手機 B 自己有影像但遠端＝灰人形 placeholder（group_call_screen gridView renderer 未綁或 `_hasVideo`=false 二擇一）→ **單向** B 端接收／渲染；對端 versionCode 仍未提供）；「封鎖名單在哪裡」→ v0 無獨立頁（第十五批決定）→ 人類答「是，介面根據 LINE 重新設計」批准本批。
- ②-A 根因（已定，本機查證）：`AndroidManifest.xml` 只有 `BLUETOOTH`＋`maxSdkVersion="30"`，**缺 `BLUETOOTH_CONNECT`**（Android 12+/API 31 起 runtime 權限；人類提供 dumpsys：targetSdk=36）→ AudioSwitch 無權限建立 BluetoothHeadset profile → `availableAudioDevices()` 永不含藍牙 → 重試救不了（截圖中內建兩項在列＝掃描已完成、非時序問題；機制中段 ⚠️待實機驗證——即時驗證路徑＝手動允許「附近裝置」權限後開 sheet）。修（人類批准「是」）：①manifest 新增 `BLUETOOTH_CONNECT`；②MainActivity.kt 新增 `ring/permissions` channel（check/request，框架 Activity.requestPermissions、requestCode 4712、onRequestPermissionsResult 重構為 when 雙分支，零新依賴）；③新檔 `lib/bluetooth_permission.dart`（非 Android／channel 異常不擋通話流程）；④兩份 sheet 開啟先 `await requestBluetoothPermission()` 再枚舉（已授權不彈框；拒絕→僅內建）；⑤sheet 空清單顯示提示「目前沒有偵測到外部放音裝置」（原樣貌靜默）。**披露**：AudioSwitch 若在授權前已建立（先前通話開過 sheet），藍牙要到下次實例建立（通常下通話）才出現（套件無重新掃描 API）；永久拒絕時每次通話僅請求一次不轟炸。
- 封鎖名單頁：新檔 `blocked_users_screen.dart`＋settings_screen「一般」入口——結構參考 LINE_ref/new_ref/settings/blocked_account 截圖語意（計數＋說明＋清單列頭像／名稱＋解除）；清單＝官方 `Client.ignoredUsers`（client.dart L3945）；解除＝官方 `Client.unignoreUser()`（第十五批確認框同型）；名稱／頭像＝官方 `getProfileFromUserId`（client.dart L1197，內含 1 天快取）＋`Uri.getThumbnailUri`（uri_extension.dart L63）＋`authenticatedMediaSupported()` → Bearer header（批次 I 官方認證媒體路徑）；查不到 → mxid＋首字頭像。骨架樣式／文案草案待人類定稿。LINE 專屬不投射：Friends／Official accounts 分頁、Select all 多選、「刪除後仍封鎖」LINE 特有語意（Matrix：清單即封鎖事實）。
- ②-B 攝影機：本輪 logcat 未含 App 行（裡面僅系統藍牙 HAL／音量群組雜訊）——抓法須 `adb logcat -c` 清空後複現失敗通話、結束立刻 `adb logcat -d | grep -iE "flutter|voip|mute|audioswitch|bluetooth"`；判別問題（①B 聽得到 A 的聲音？②失敗當下對方攝影機確定開著？③幾分鐘內自行恢復過嗎？）仍未答——本批不定案，未動 camera 程式碼。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2019）、`known_problems.md`（頭像成功／②-A 根因／②-B 判別問題註記）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.5s)`**；test → **`00:37 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 139.4s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.0MB)`；merged release manifest → `versionCode="2019"`、`versionName="1.0.2"`、`android.permission.BLUETOOTH_CONNECT` 在列。
- 待實機（APK 2019）：①通話「選擇音訊輸出」sheet 列出藍牙／有線裝置且選擇生效（若先前曾開過 sheet，可能需重進通話一次）；②設定→「封鎖名單」列出已封鎖使用者、解除後好友長按選單與此頁一致；③②-B 攝影機——待上節 logcat＋三個判別問題的答案再定修法。
### 2026-11-08（第十九次）— ②-A 決定性診斷列（臨時除錯）；②-B 觀察正常；零新依賴
- 排除法收斂：人類補測（2026-11-07→08）「**有**強制停止 Homing 再重進通話」且 sheet 仍空 → 「陳舊實例」理論**出局**；fork `AudioDeviceScanner.kt` 整檔核對——SCO(7)／A2DP(8)／BLE_HEADSET(26)／BLE_SPEAKER(27) 皆正確映射、註冊即回完整清單，映射無漏洞 → 唯一未知數＝Homing 進程內的系統裝置清單。`/tmp/ring_bt.log`（00:07）＝0 bytes 屬預期（fork `loggingEnabled=false`＋PID 過濾錯過新進程）。
- 人類其他回饋：②-B 2026-11-08 00:01 群組通話（2 人）**兩格 tile 都有即時影像**＋「手機端看起來正常，最多中間卡住一下」→ 記為已修復（觀察值；「中間偶爾卡一下」小註記持續觀察）；對端手機 dumpsys **versionCode=2019**（targetSdk=36）→ 已讀 ③ 版本疑慮解除，排②-A 收尾後。
- 第十九批修（人類批准「是」）：①`MainActivity.kt` `ring/permissions` 新增 `audio_diagnostics`（**唯讀**：BLUETOOTH_CONNECT 狀態＋`AudioManager.getDevices(GET_DEVICES_OUTPUTS)` 原始輸出清單＋Android 12+ `getCommunicationDevice`／`getAvailableCommunicationDevices`／音訊模式；零新 OS 權限、零依賴）；②`bluetooth_permission.dart` 新 `bluetoothAudioDiagnosticsText()`（非 Android／channel 異常 → null 不顯示）；③`call_screen.dart`／`group_call_screen.dart` sheet 底部臨時診斷除錯列（草案；**根因定案後的下批移除**）；④`pubspec.yaml` bump→1.0.2+2020；⑤`known_problems.md` 註記（判讀樹：原始清單有藍牙→第二十批自建枚舉＋選擇；無藍牙→框架層藏依型別對症；not-granted→查 Gradle merge）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 8.3s)`**；test → **`00:43 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 184.2s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.0MB)`；merged release manifest → `versionCode="2020"`、`versionName="1.0.2"`、`android.permission.BLUETOOTH_CONNECT` 在列。
- 待實機（APK 2020）：進通話 → 開「選擇音訊輸出」→ 截診斷列一張即可（不用 logcat）。
### 2026-11-08（第二十次）— ②-A 根因定案＋自建溝通裝置枚舉／選擇；診斷列除役；零新依賴
- 決定性證據（第十九批診斷列，2026-11-08 00:26 截圖）：`perm=granted`（BLUETOOTH_CONNECT 已進進程）＋`comm 候選: Pixel 9a (builtin_earpiece) · Pixel 9a (builtin_speaker) · user-ThinkPad-P1-Gen-3 (bluetooth_sco)`——**系統溝通裝置清單看得見耳機**、fork AudioSwitch 列舉常缺 → ②-A 根因確定＝fork `AudioDeviceScanner` callback 狀態與系統脫節（非權限問題；糾纏三批的假說排除）；`comm=builtin_earpiece` 與 sheet 選中狀態自洽。
- 第十九批自首 bug：`audio_diagnostics` 漏 `diag["outputDevices"]` 賦值（診斷列顯示「原始輸出清單: 無資料」）→ 本批補回；不影響當時結論（主鏈＝perm＋comm 候選）。
- 第二十批修（人類批准「是」）：①`MainActivity.kt` `ring/permissions` 新增 `list_audio_outputs`（官方 `getAvailableCommunicationDevices()`＋當前溝通裝置 `isCurrent`；<S 回 supported=false）與 `set_communication_device`（官方 `setCommunicationDevice`＋套用後「回讀溝通裝置型別」二次驗證；目標斷線 → false）；②`bluetooth_permission.dart` 新 `AudioOutputOption`／`enumerateCommunicationDevices()`／`setCommunicationDevice(id)`（null＝不支援／異常）；③`call_screen.dart`／`group_call_screen.dart` 外部分組改吃自建枚舉（kind＝官方型別名；內建 earpiece/speaker/safe 過濾；連線耳機顯示真名）＋`_setSpeaker` Android 12+ 一律先走 setCommunicationDevice（builtin_earpiece／builtin_speaker，單一路由權威；false/null → 1.6.3 Helper 舊路徑＋批次十七驗證保留）；④第十九批臨時診斷除錯列**已移除**（audio_diagnostics 通道保留一輪 field 工具，下批除）；⑤`pubspec.yaml` bump→1.0.2+2021；⑥known_problems 定案註記（含披露：型別級選擇、<S 未惠及、HFP 0.5–1s 切換停頓、fork 回拉風險下一槓桿＝audioMode／activate 時 ⚠️待實機）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 8.1s)`**；test → **`00:46 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 158.2s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.0MB)`；merged release manifest → `versionCode="2021"`、`versionName="1.0.2"`、`android.permission.BLUETOOTH_CONNECT` 在列。
- 待實機（APK 2021）：①sheet「外部裝置」出現 user-ThinkPad-P1-Gen-3（藍牙耳機）；②點選後聲音真的到耳機（HFP）；③回內建 電話／喇叭 能切回；④耳機斷開重開 sheet 顯示空＋提示；⑤若「選完又被帶回聽筒」回拉 → 回報即開下一槓桿。
- **✅ 實機結果（2026-11-08 人類回報）＝「成功」**：①②確認通（sheet 列出筆電耳機＋路由生效）。②-A 收口；fork 回拉未出現。第二十一批（排程中）：照第二十批承諾移除 audio_diagnostics 診斷通道＋Dart helper（零功能影響、屬清理）；並準備「已讀」主題 pre-work（對端已證實 2019，版本疑慮解除）。
### 2026-11-10（第二十七次）— Rust 引擎初始化防禦＋診斷記錄（附件送出「flutter_rust_bridge has not been initialized」）；零新依賴
- 人類實測 APK 2027 回饋（2026-11-10）：picker 分享 native 整線已通，但送出加密房附件失敗＝`Bad state: flutter_rust_bridge has not been initialized`（截圖即 chat_screen 附件批次總結「已送出 0 個附件，1 個失敗（最後原因…）」）；人類拍板「防禦性修復＋診斷」＋「插上裝置我直接抓 logcat」。
- 靜態證據鏈（本機查證 matrix 14.2.0 官方原始碼）：本專案媒體／分享全鏈（背景 isolate 內 SDK `encryptFile`＝純 Dart `Random.secure`＋AES-CTR＋SHA-256；圖片解碼／縮圖＝純 Dart image 套件）皆不碰 rust；SDK `nativeImplementations` 以預設 `dummy` 運行（client.dart L219；native_implementations.dart dummy 版全 inline）＝所有 vodozemac 呼叫（megolm 事件加密 `encryptGroupMessagePayload` → outboundGroupSession.encrypt，encryption.dart L326-380）都在**主 isolate**；主 isolate rust 狀態唯一初始化點＝main() 開頭 `vod.init()`，舊版失敗僅 print（靜默）→ 該次 session 的任何加密呼叫即炸出「尚未初始化」而無跡可尋。
- 實機 logcat（2026-11-10 本機直接抓，過濾引擎標記）：本次 2027 啟動**引擎初始化成功**（啟動序列無 `vodozemac init failed`，session 正常還原連上 homeserver；另有 Client.init sync 逾時＝當時裝置網路不佳，屬 SDK 官方逾時路徑）；crash／main／all buffer 輪轉後無任何 vodozemac 殘跡 → 11-07 當晚失敗的瞬時原因**無法回取**，根因（如 dlopen／時序／記憶體）未定案。2028 的診斷記錄＝下次再現時自動留下證據。
- 修（人類批准；**不觸任何加密演算法／金鑰內容**）：新檔 `app/lib/engine_init.dart`＝`initRustEngine`（失敗自動重試一次、每次失敗皆 print 留 logcat；**僅終局仍失敗**才把最後原因落 AppSettings kv `rust_engine_error`；成功即清旗標，清旗標失敗不誤判成引擎失敗）；`main.dart` `_initVodozemac` 改走 helper；`main_shell.dart` 掛載時讀旗標→一次性提示「加密引擎未就緒：…請重啟 Homing；若重現請回報」（無旗標不打擾；橫幅為草案待人類定稿）；`settings_screen.dart` 診斷資訊加「Rust 引擎（二十七批）」唯讀段（成功（無失敗記錄）／失敗：原因）；測試 `app/test/engine_init_test.dart` 4 案（假件注入，不觸 sqflite：首次成功/no 功副作用、敗後成功、兩敗落旗、清旗擲例不誤報）。語意披露：診斷顯示「成功」＝**本 session** 初始化成功（歷史 session 的失敗旗標會在下次成功時清掉）。
- 其餘檔案：`app/pubspec.yaml`（僅 bump→1.0.2+2028）。
- 驗證（實際輸出照貼）：analyze → `No issues found! (ran in 6.9s)`；test → `00:44 +153 ~1: All tests passed!`（批二十六基準 +149 → +153＝新增 engine_init 4 案，無刪除）；license_check → `LICENSE_EXIT=0`（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 245.4s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.2MB)`（build 輸出含 Flutter 內建 Kotlin 遷移警語＋vodozemac_bindings_dart 三架構原生建置 INFO，皆為工具鏈／既有套件行為，本批零新依賴）；aapt2 badging → `versionCode='2028' versionName='1.0.2'`。
- 待實機（APK 2028）：①若引擎初始化再失敗：進殼一次性提示＋設定→診斷資訊「Rust 引擎」列出最後失敗原因（回貼該截圖＝根因證據，供下一批對症）；②初始化成功的 session：分享／附件送出應恢復可送（2027 實機本啟動未重現「尚未初始化」）；③若 2027 本次啟動分享已可送出，視為該病證為「特定 session 初始化失敗」而非永久性。⚠️ 防禦修復僅保證失敗不再靜默＋自動重試一次；真正瞬時根因仍待人類讓 2028 再現一次來定案。
### 2026-11-10（第二十九次改向）— LiveKit 評估（人類拍板「先做 LiveKit 評估」＋「媒體伺服器傾向第三方公益伺服器；帳戶現掛 Matrix.org」）；mesh 修暫緩；零程式碼變更
- **決策**：批 29 原 mesh 修（A/B/F/E/D 草案）暫緩保留；群組通話改評估 MatrixRTC/LiveKit。逐項查證（全文＝known_problems.md「LiveKit 評估報告」節）：
- **公益節點成立**：matrix.org well-known（實抓自官方端點）現公告 livekit foci＝`livekit-jwt.call.matrix.org`；Element 官方 blog（2025-04）明言 matrix.org 帳號由 Matrix.org 基金會供專用節點（LiveKit 贊助）持續可用 → **免自架**；媒體流經第三方＝人類知悉選定的隱私決策（長期承諾 ⚠️待查證）。
- **SDK 整合面**：14.2.0 `LiveKitBackend` 官方包辦 MatrixRTC 成員事件＋E2EE 金鑰輪替（**e2eeEnabled 預設 true**，優於 mesh＝媒體真 E2EE）；媒體連線明文要求 App 端用 `livekit_client` 套件。
- **依賴相容（2.13.2 pubspec 親查）**：Apache-2.0、**pinned flutter_webrtc 1.6.3＝與我方同版零衝突**、dart ≥3.10 過關；直依＋傳遞依賴 → pubspec 變更＝必須停下批准＋license_check 增補。
- **發現機制**：新通道＝MSC4519 transports 端點（Element Call ≥0.24 只讀它）；SDK 無此端點支援，實作批建議補齊＋well-known 兜底（我方 livekit_config.dart 現走 well-known，短期可用）。
- **紅線**：keyProvider／E2EE 接線屬加密必停區；動工前待人類批准。FluffyChat MVP（e1ca8ae，68 檔+1354 行）＝規模參照；Homing 骨架已備，差距＝JWT→Room connect→tile 渲染→掛斷鏈。

### 2026-11-12（第三十五批）— Web/desktop 平台＋寬屏側欄＋聊天四功能（#4 動圖貼圖/#5 無聲/#6 緊急求助流程/#13 Markdown/#14 原始訊息）；org 換定＋批次 33 Kotlin 缺口修復（新依賴 2 項人類批准；versionCode 2034→2035）
- **範圍**：人類指定需求清單 #1/#4/#5/#6/#13/#14；中途插入（人類拍板三項）：org＝`io.github.itsxiaobai`（macOS/Linux 帶 `.homing` 後綴＝各平台慣例）、修批次 33 跨語言斷點、manifest label「Homing」。
- **#1 Web/desktop（新依賴 sqflite_common_ffi_web，人類批准）**：`flutter create --platforms web,linux,windows,macos` 建平台目錄；main.dart 開頭 `kIsWeb` → `databaseFactory = databaseFactoryFfiWeb`（官方用法「set once before opening any database」）；`dart run sqflite_common_ffi_web:setup` 生成 `web/sqflite_sw.js`（267836B）＋`web/sqlite3.wasm`（748686B）；web `getDatabasesPath()` 回 `/`、`xFullPathName` 正規化＝`/app_settings.db` 相容。MainShell 以 `MediaQuery.sizeOf(context).width >= 600` 分流（DESIGN.md §1 斷點）：≥600＝Row[NavigationRail（3 destination、labelType all，**草案樣式待人類設計定稿**）＋Expanded(body)]；<600 維持既有膠囊列。雙欄聊天屬 Phase 4/7 定稿範圍未動。
- **Web 白屏根因＋修（瀏覽器實證 2026-11-12）**：flutter_vodozemac 0.9.1 官方套件未宣告 web 平台（無 web 目錄、未隨附 runtime `pkg/vodozemac_bindings_dart.js`）→ `vod.init()` 於 loader 404 後卡住不返回 → main() 到不了 runApp＝白屏。修＝`_initVodozemac` 於 kIsWeb 直接跳過（依 1.5 既有原則「引擎未就緒時 App 仍可運作（僅無加密）」；非 web 平台行為不變）。**披露：Web 目前無加密**；加密房在 web 的實際行為未驗證。修後瀏覽器實證：登入畫面正常渲染、`sqflite_sw.js` 已載入、console error 歸零（僅餘 matrix SDK 對空庫 db_repair 的已捕捉警告，非致命）。`flutter build web` 成功（141.8s→修後 118.7s；wasm dry-run 僅 flutter_rust_bridge JS-interop lint 警告＝僅影響 wasm 編譯，JS 版正常）。
- **#4 動圖貼圖（不含聲音）**：經拍板走 GIF/APNG 貼圖路線（video_player 不支援透明渲染）。`chat_screen._stickerMime` nullable 白名單（png/gif/jpg/jpeg/bmp/webp）；影片／音訊／未知型別回 null 拒收（不進貼圖庫）。
- **#5 無聲傳送**：送出訊息 content 帶 `dev.homing.silent: true`（送出後／編輯後復位）；僅 Homing 端靜音——`main_shell._maybeNotify` 見該旗標跳過通知。聊天輸入列 `Icons.notifications_off` 開關。
- **#6 緊急求助流程（LINE 式；人類拍板細節）**：`emergency_feed.dart` 開公開 `parseEmergencyFeedXml`＋`kEmergencyFlowCategories = ['地震速報','地震報告','颱風']`＋`isEmergencyFlowAlert`；feed 主端點 `https://cbs.tw/files/rssatomfeed.xml`（無前綴形狀）＋fallback 官方 `RssAtomFeeds.ashx`（cap: 前綴），`_tagAny`/`_sender` 雙形狀相容。`main_shell._pollEmergency` 偵測到流內類別且 id 未在 `_emergencyFlowShownIds` → push 新檔 `emergency_flow_screen.dart` 三步驟（「需要幫忙嗎？是/否」→「幫你聯絡誰？緊急聯絡人／所有人／119」→送出）；一次輪詢最多一個。新檔 `emergency_contacts_screen.dart`（app_settings kv `emergencyContacts`，dart:convert）；settings_screen「一般」區入口；`share_to_room_screen` 加 `preselectedRoomIds`/`title` 支援流程直送。**119＝自動發訊息不撥號**；送出前使用者先看訊息長相、發到哪由使用者決定。
- **#13 Markdown（新依賴 markdown，人類批准）**：kv `markdown_enabled` 預設**關**；開啟時送出帶 `format: org.matrix.custom.html`＋`formatted_body`（SDK `sendEvent`＋`inReplyTo` 官方路徑）；HTML 不二次清毒（SDK 官方 sanitize）。新檔 `markdown_message.dart`：渲染分支 `_formattedBodyWidget`＋自寫白名單 HTML parser（b/strong/i/em/u/s/del/strike/code/pre/blockquote/ul/ol/li/a/p/br；href scheme 白名單 http/https/matrix/mailto；未知標籤剝殼；`mx-reply` 剝除）＝與 #14 共用。輸入列 `Icons.code` 開關。
- **#14 查看原始訊息**：訊息長按選單新增「查看原始訊息」→ content JSON dialog（唯讀）。
- **org 換定（人類拍板；重大影響披露）**：android namespace/applicationId＝`io.github.itsxiaobai`＋kotlin 套件目錄搬移 `android/app/src/main/kotlin/io/github/itsxiaobai/`（manifest 用相對類名跟 namespace 走＝搬移乾淨）；iOS `PRODUCT_BUNDLE_IDENTIFIER = io.github.itsxiaobai`（RunnerTests 帶 `.RunnerTests`）；macOS `io.github.itsxiaobai.homing`；linux `APPLICATION_ID = io.github.itsxiaobai.homing`；windows `Runner.rc` CompanyName/Copyright。`com.example.ring`/`io.github.homing` 殘留＝0。**影響＝App 身分變更**：Android 舊 APK 無法原地升級（解除安裝重裝、本機資料不遷移需重登）；iOS/macOS 須重新簽署。
- **批次 33 Kotlin 缺口修復（查證發現）**：批次 33 的 ring→homing 改名**漏了 Kotlin 端**——Dart 端 5 個 MethodChannel 早已 `homing/...`，Kotlin（HEAD）仍 `ring/...`＝**原本就全斷**；call_service extras：Dart 傳 `'status'`/`'room_id'`、Kotlin 讀 `ring_call_status`/`ring_call_room_id`＝讀不到（預設值兜底）。修＝Kotlin 5 channel 改 `homing/...`、`EXTRA_STATUS="status"`/`EXTRA_ROOM_ID="room_id"`；Kotlin 內部自洽的 `ring_*` intent extras 不動（零風險）。**flutter create 副作用處置披露**：其曾以 git remote 推導 org 擅自改名 android/ios（套件目錄搬移＋channel 字串改名）→ 先逐 byte 還原驗證乾淨 → 經人類確認後有意識重新套用（即本節 org＋channel 修復）。
- **測試**：新檔 `test/batch35_features_test.dart` 24 案；main.dart/main_shell 改動後全套重跑（見驗證）。測試期修正：長按選單 Column 溢出 32px → 包 `SingleChildScrollView`＋`isScrollControlled: true`（真實 UI 修正）；既有 `ui_redesign_test` 2 案明示 compact 尺寸（widget 測試預設視窗 800×600 已落入新 ≥600dp 分支，受測對象本為膠囊列）＋新增 ≥600/<600 分流測試 1 案。
- **依賴**：markdown（BSD-3-Clause，Copyright 2012 the Dart project authors）＋sqflite_common_ffi_web（BSD-2-Clause，Tekartik；連帶 transitive dev_build/pool/process_run；`sqflite_common_ffi` 由 transitive 升格 direct）——皆人類批准，DEPENDENCIES.md 已記。**lock 連帶刷新（人類拍板 2026-11-12「保留 0.9.1」）**：pub 解析時 flutter_vodozemac/vodozemac 0.9.0→0.9.1（**官方 security fix**：vodozemac 0.11.2——GHSA-pqp6-f7wc-6498 malformed Ed25519 key panic＋GHSA-v27v-f96q-qhjq Olm root key 未清零）＋19 組 transitive 次版號（sqflite 2.4.5→2.4.6／sqflite_common 2.5.14→2.5.17／file_picker 家族／mobile_scanner 7.4.3→7.5.0／archive／synchronized／jni 等，皆 constraint 內；本批全部 build/test 均在 0.9.1 上）。
- **驗證**：`flutter analyze` No issues（9.1s）；`flutter test` `00:35 +200 ~1: All tests passed!`（批 34 基準 175＋本批 25：batch35_features 24＋MainShell 寬屏分流 1）；`python3 ci/license_check.py` exit 0（直接依賴 28 項皆已記錄）；`flutter build web` ✓（118.7s）；`flutter build apk` ✓（183.7s，135.2MB）；aapt2 badging `package: name='io.github.itsxiaobai' versionCode='2035' versionName='1.0.2'`＋`application-label:'Homing'`（前一支出過的 APK＝2033，嚴格遞增；2034 跳號——批 34 APK 未出（人類喊停），2034 版驗證 build 亦成功 135.2MB／374.4s＝Kotlin 套件搬移＋channel 修復編譯通過）。Web 白屏修復之瀏覽器實證另經本地伺服器日誌印證：修復前三次載入皆 `pkg/vodozemac_bindings_dart.js` 404＋無 sqflite 請求；修復後 `sqflite_sw.js 200`＋`sqlite3.wasm 200`、零 404。
- **⚠️待實機／待驗證**：Web 無加密（vodozemac web runtime 不存在於官方套件）；Web 加密房行為、登入實測（未用真實帳密）；Web 正式部署需 COOP/COEP headers（目前 SharedArrayBuffer 僅警告）；桌面 build 工具鏈未驗證（linux 需 cmake/ninja；windows/macos 本機不可）；org 變更的升級影響（上節）；#5/#6/#13/#14 實機行為；APK 2035 全鏈回歸（含 Kotlin channel 修復後的通知／分享／權限／螢幕分享／來電）。

### 2026-11-13（第三十六批）— 解密案收案：重裝後私人房歷史訊息恆為未解密佔位（零新依賴；versionCode 2053→2054）
- **病證**：重裝 App 後，私人加密房（實證個案 room `!3gzbN7WyrQYfSorGg2UbG_KCrJ2MUnn1lM5ET9D-K6Q`）歷史訊息全部顯示未解密佔位，重開不恢復。
- **根因（SDK 源碼＋實機 logcat 釘死）**：重裝後舊加密事件在本機 DB 帶 `can_request_session: true` 失敗旗標（實機 8/8 全帶）；SDK 各解密路徑對帶旗標事件**永不重試**——/context 重建路徑只解帶旗標者（room.dart L1775-1776）、timeline 載入閘門下 sync 窗口事件零解（timeline.dart L288）、`decryptRoomEventSync` 失敗必印的 e 級 log（實為拼字錯誤 `Could not decrpyt event`）在實機為零 → 解密**從未被嘗試**。而 7 個 megolm session 其實早已自備份還原成功（實機 7/7 IN-DB、`loadInboundGroupSession` valid=true）——缺的只是「有人去叫用」。vodozemac 0.9.0/0.9.1 api.dart 完全相同＝版本差異非因素；SSSS 快取／公鑰閘／sender_key 缺欄等理論全數排除。附帶懸案定案：sync ~60s 死因＝**裝置網路中斷**（`ClientException: Software caused connection abort`→DNS `Failed host lookup`），非 app 邏輯。
- **修法（全部 SDK 官方 API、零自製加密、零新依賴）**：①`missing_key_repair.dart` 新增 `ensureRoomEncryptionState(room)`——`m.room.encryption` state 缺失時以官方 `getRoomStateWithKey` 補回＋持久化（個案 state 一直在＝防禦性）；②新增 `decryptUndecryptedEvents(room, events)`——訊息渲染前以官方 `Encryption.decryptRoomEvent` 對每個 `m.room.encrypted` 事件補解密，**帶旗標事件一併重試**（關鍵），失敗自動觸發官方 `maybeAutoRequest` 取鑰；`chat_screen.dart` `_defaultLoadMessages` 接入兩者；③金鑰備份還原 `fetchKeys` 強化（`backup_restore_screen.dart`）——全量端點實測漏 session（全量 5 房/46，逐房端點對個案另回 7）→ 對「全量缺／空」房間以官方逐房端點補抓聯集；④取鑰 missing_key_re 與還原判決頁為前案成果保留。
- **診斷碼清理（人類批准）**：`_diagBackupInventory`、fix4 計數 log、`[Diag] fetchKeys` log、`Logs().level = Level.verbose`、sync-error 監聽、`vodozemac as pk` import 全數移除；pubspec 的 `vodozemac: ^0.9.1` direct 宣告隨之撤回 → 回 transitive（lock 解析不變）。**螢幕自動旋轉非 agent 所為；已將 `accelerometer_rotation` 設 0（直向鎖定）**。
- **驗證（實際輸出照貼）**：`flutter analyze` `No issues found! (ran in 6.7s)`；`flutter test` `00:45 +210 ~1: All tests passed!`；build ✓（135.3MB）＋install Success；實機 2053 log `[Diag] fix4: encrypted=8 ok=8 fail=0`＋截圖證實 307_67 全文（文字／投票卡／圖片）可讀、已翻至最早（11/06「已沒有更早的訊息」）；清理版 2054 裝機複驗：307_67 文字＋圖片全解密、可見區零佔位。
- **披露**：Test in RING 回歸未截到實機圖（返回鍵座標漂移）——該房事件走 SDK 原生解密、helper 對明文事件零介入，風險評估極低但仍標未實機複看；全部變更維持未 commit。

### 2026-11-12（第三十四批）— 來電通知改側邊橫幅（需求 #2）＋登入頁伺服器選項收合（需求 #7；零新依賴）
- **需求 #2（人類解讀已確認「是」）**：來電改**側邊橫幅**（root overlay `OverlayEntry`，置右上、點擊穿透不擋底下畫面），橫幅可**接聽／拒接／點擊展開全螢幕通話畫面**；通知設定頁新增「通話→來電顯示」開關——**關＝不彈橫幅，僅系統通知欄提示**（走既有 `homing/local_notifications` `show` 通知）。群組來電邀請同橫幅（加入／忽略）。偏好存 `AppSettings` kv `incoming_call_banner`（預設開）＋ notifier `ringIncomingCallBanner`。
- **實作檔案**：`main_shell.dart`（重寫 `_onIncomingChange`／`_onIncomingGroupChange` 分流橫幅或通知；新增 `_showIncomingBanner`／`_removeIncomingBanner`／`_postIncomingCallNotification`／`_cancelIncomingCallNotification`／`_acceptIncoming`／`_declineIncoming`／`_expandIncoming`／`_joinIncomingGroup`／`_ignoreIncomingGroup`；dispose 收橫幅；檔尾 `_incomingCallDisplayName`（官方 `getLocalizedDisplayname`）＋`_IncomingBannerHost`（回呼由 MainShell 注入）＋`_IncomingBannerCard`（Semantics liveRegion、寬度上限＝畫面 0.72 倍不寫死））；`notification_settings_screen.dart`（notifier＋載入＋`_setIncomingCallBanner`＋SwitchListTile）；`login_screen.dart`（#7：`_showServerOptions` 預設 false——預設只顯示 matrix.org（預設）＋TextButton「如果有自己的伺服器，請按這裡！」（人類指定文案），點開才展開三選項 radio＋homeserver TextField；註冊登入共用）。
- **附帶 bug 移除（披露）**：舊 `_onIncomingChange` 的 `activeCall == session` guard 恆真（`_onNewCall` 先設 `activeCall` 才設 `incomingCall.value`）＝**1:1 來電從未自動彈出**；橫幅實作順帶修復。
- **v0 披露（待人類實機驗證）**：①橫幅僅 App 前景（背景 FCM 推播不在本批，既有限制）；②偏好關閉時的通知與訊息通知共用同一通知 id（roomKey.hashCode）＝後到覆蓋先到；通知「開啟」＝進聊天室再由通話鈕回通話（無橫幅點入）；③單一橫幅不疊第二則；④mesh 群組「忽略」無拒接協定操作（對方逾時自收）；⑤樣式全部草案待人類設計定稿。
- **驗證**：`flutter analyze` No issues（初輪 2 issues＝舊 `_incomingOpen` 欄位 unused，已移除）；`flutter test` `00:29 +175 ~1: All tests passed!`（批 33 的 172＋新增 3：登入收合 2＋橫幅 1；另修 `widget_test.dart` 1 例預設收合斷言）；`python3 ci/license_check.py` exit 0（25 項不變）；pubspec version `1.0.2+2033`→`1.0.2+2034`（僅 bump，零依賴變更）。
- **⚠️待實機驗證（APK 2034）**：①1:1 來電橫幅出現＋接聽／拒接／點擊展開；②群組邀請橫幅加入／忽略；③設定頁關閉後不彈橫幅、通知欄有提示；④通知點擊行為（進聊天室）；⑤登入頁收合→展開自訂 homeserver 全流程；⑥root overlay 在各畫面（聊天室內／通話中）之上顯示正常。

### 2026-11-12（第三十三批）— 全域改名 RING→Homing＋applicationId（人類拍板「改名為 Homing」＋「A，從 git 抓」＝io.github.itsxiaobai；零新依賴）
- **改名動機**：人類詢問「Homing 名稱會不會有問題」→ 查證＝Amazon（Ring LLC）持有 USPTO Reg.4724984/5289328（類 9/38/42，商品含 mobile 通訊 app），且執法活躍（2020 HomingCHAT 異議／2026 WIPO 域名仲裁勝）→ 人類拍板可能上架故改名。**非法律意見**；正式排除仍需商標代理人（⚠️待專業諮詢）。Homing 初查：無撞名通訊 app；USPTO 首查無 HOMING 通訊軟體註冊（現有命中＝尋標器／追蹤標籤等描述性片段）⚠️正式 clearance 待專業。
- **範圍**：pubspec `name: ring→homing`（description 更新）；42 檔 `import 'package:ring/...'`→`package:homing/...`；`build.gradle.kts` namespace＋applicationId `com.example.ring`→`io.github.itsxiaobai`（Play 上架後永不可改，人類選 A＝io.github.<GitHub帳號>）；Kotlin 三檔 package＋目錄搬移 `com/example/ring`→`io/github/itsxiaobai`；iOS `PRODUCT_BUNDLE_IDENTIFIER` 全改；`AndroidManifest` label "ring"→"Homing"；**MethodChannel 全組改名**（`ring/`→`homing/`：permissions/call_service/local_notifications/screen_capture/share；通知 channel id `ring_call`→`homing_call`、`ring_screen_capture`→`homing_screen_capture`，Dart＋Kotlin 兩側同步，舊 `ring/` 0 殘留）；UI 文案 8 處（裝置顯示名 'Homing (Flutter)'／自架伺服器選項／重啟提示／通知設定路徑／push 裝置名／App title）；根層 docs 品牌名（README/PRIVACY/SECURITY/DESIGN/THREAT_MODEL/ARCHITECTURE/DEPENDENCIES/UI_*/THEME_FORMAT `RING→Homing`）；測試一處跟進（connect_screen_widget_test）。
- **不改動**：`ring_notif_action` 等內部 intent extra（內部代號不對外）。**補記（2026-11-13，人類指示「所有說明檔案的軟體名稱和其他文件也一併更新」）**：`agent*.md` 藍圖（v1.1／v1.2／v1_3）、`agent.md`、`AGENTS.md` 標題及 PROGRESS／known_problems 中指 app 本身的 RING 敘述已改 Homing；技術字串（`Test in RING` 房名、`ring/` channel、`RING_TEST_*` 環境變數）與批次 33 商標查證事實、人類原話引用保留原樣。**補記（2026-11-13）**：批次 33 原列「副本目錄（ring 開頭）」已由人類刪除，該條目及相關資訊自此移除。
- **versionCode 2032→2033**。驗證：`flutter analyze` No issues；`flutter test`（初輪 1 測試文案未跟改名，已修）全量見批次報告；license_check／build apk＋aapt2 見後。
- **⚠️待實機（APK 2033）**：全新應用身分（同舊 APK **不同 applicationId＝無法原地升級**，A/B 兩機需先解除安裝舊版再裝 2033，聊天記錄 local DB 會清除——請人類知悉）；通知／分享／權限／螢幕分享各通道改名後全鏈仍通。


- **範圍**：回饋①返回/最小化媒體續用＋②20 秒倒數未出現＋③前後鏡頭記憶＋④通話通知即時狀態／點入回通話／結束消失＋⑥通話表情符號；⑤（1:1 遷 LiveKit）人類追問「mesh 似乎不穩定」→ 拍板方向成立、**排批 33**（未動工）。
- **①根因（本機源碼＋平台規則定案）**：`CallForegroundService` 原型別僅 `dataSync`——Android 平台規則＝App 進背景後攝影機／麥克風擷取須掛有 `camera`／`microphone` 型別之前景服務，否則被系統停擷取 → 對端「全卡住」／無聲（人類證實「返回後/最小化後開始卡」）。修＝manifest 加 `FOREGROUND_SERVICE_CAMERA`＋`FOREGROUND_SERVICE_MICROPHONE`＋service multi-type `dataSync|camera|microphone`，`startForeground` 帶三型別位元遮罩（API 30+）；**返回鍵＝自動縮子母畫面**（人類拍板「改成自動 PiP」；PiP 期間 App 算前台媒體不受限；PiP 不可用才 pop，session 仍持有）。
- **②倒數修**：原觸發條件含 SDK 成員狀態第二重確認（gc.participants），famedly 成員 state 清除走延遲事件殘留數十秒 → 整個擋死倒數。移除、改以 lk 遠端清單為單一事實來源（`_sawARemoteParticipant` 旗標守住「發起人獨自等待不誤掛」）；規則抽純函式 `othersLeftShouldCountdown` 供測試。
- **③**：前後鏡頭選擇存本機 kv `lk_camera_front`（app_settings；僅本機不送伺服器），下次通話自動沿用（預設前鏡頭）。
- **④**：通知（前景服務）生命週期**移入 manager**（返回後 session 仍在＝通知也要在；原在畫面層 pop 後斷管）＋`CallForegroundService.kt` 重寫：狀態即時更新（`active`＝通話進行中／`share`＝正在分享螢幕，`ring/call_service` 新 `update` method）、contentIntent 深鏈 MainActivity（`ring_notif_action=open_call`，批次十四通路）→ main_shell `_onNotifAction` 新 `open_call` case 直接 push LiveKitCallScreen（session 重用不重連、不重新加入）；leave→`stop` 通知消失（既有）。
- **⑥**：通話表情符號（參考 Element X 行為；Element X Flutter repo 已下架＝僅產品行為參照）：控制列表情鈕→sheet 十顆草案 emoji→官方 `publishData`（LOSSY，topic `ring.reaction`）→`DataReceivedEvent` 接收→媒體區膠囊飄浮「名 emoji」**5 秒消失**＋自己端即時顯示。**披露**：表情走 lk 資料通道**未經 E2EE 幀加密**（內容僅 emoji 非敏感；要加密屬必停區待另案）。
- **驗證**：`flutter analyze` No issues；`flutter test` 172＋1 skip 全過（新增 8：倒數規則 4＋表情 payload encode/decode 4，`test/livekit_reaction_test.dart`）；`python3 ci/license_check.py` exit 0；`flutter build apk --release` 134.7MB，aapt2 確認 `versionCode='2032'`（2031→2032 嚴格遞增）。
- **⚠️待實機驗證（APK 2032）**：①返回/最小化後對端不再卡住＋收音收影續行（核心）；②返回即自動縮 PiP；③點通知回通話畫面；④分享螢幕時通知文字變「正在分享螢幕」、結束後通知消失；⑤掛斷對端→20 秒倒數出現並自動退出；⑥表情符號雙端飄浮；⑦鏡頭記憶跨通話保留。

### 2026-11-10（第三十一批）— LiveKit 全功能移植（人類批准「全部，原本的音訊裝置、螢幕分享等功能也要」＋「其他人已離開」倒數 20 秒；零新依賴）

- **範圍**：mesh 群組通話十三項功能＋批 29 草案 B/D/E/F 全部映射到 LiveKit 路徑（映射皆官方 API，親查 lived 碼非瞎猜；映射表見 `livekit_call_manager.dart` 頂部註解）。mesh／1:1 路徑本批未動。
- **`livekit_call_manager.dart` 大幅擴充**：①說話高亮＝`ActiveSpeakersChangedEvent`；②連線品質＝`ParticipantConnectionQualityUpdatedEvent`（poor/lost→「重新加入」按鈕＝官方 leave＋join 重跑）；③wake lock＝`wakelock_plus`（連線啟用／離場停用，已批准依賴）；④「其他人已離開」倒數 20 秒自動退出（條件＝曾見過遠端參與者＋此刻 lk 遠端全空＋SDK 成員狀態查無他人；期間有人加入即取消；離場後 snackbar「其他人已離開，已自動結束通話」）；⑤螢幕分享＝官方 `Hardware.requestCapturePermission`（SDK 標 experimental，照官方建議用法＋ignore 註解）＋既有 `ring/screen_capture` 前景服務（Android 14+ 必需，batch II-b）＋`setScreenShareEnabled`；⑥鏡頭切換＝`LocalVideoTrack.setCameraPosition`；⑦內建放音（電話／喇叭）＝livekit 官方 `AudioManager.setSpeakerOutputPreferred` fallback、主路 `ring/permissions` 溝通裝置通道（batch 20 定案）；⑧通話紀錄＝`CallLog.add`（一次連線一筆）；⑨殘留 membership 檢查＝官方 `isExpired` 觀察＋log（join 路徑 SDK 官方取消 delayed leave，清理包辦）；⑩音訊／視訊／分享軌查詢門面（`videoTrackOf` 等）供 UI 渲染。
- **`call_manager.dart`**：加 `getOrCreateLiveKit`/`clearLiveKit`/`activeLiveKit`（mesh「按返回通話繼續」批次 II-j 語意移植：session 由 CallManager 持有，畫面 dispose 不離開；重入同房間重用；明確掛斷／自動退出才清空＋pop＋snackbar）。
- **`livekit_call_screen.dart` 全文重寫**：joining/connected/error/left 四態、倒數／訊號不佳／狀態三橫幅、螢幕分享大畫面＋縮圖列（mesh II-e 同款）、動態磚格（1/2/3 欄＋說話高亮綠框＋視訊關閉頭像）、七鈕控制列（麥克風／攝影機／切鏡頭／音訊輸出／螢幕分享／子母畫面／掛斷）、參與者列表 sheet、Discord 式放音選單（這個電話：電話／喇叭＋外部裝置分組＋無裝置提示）、PiP（手動＋App 背景自動進入）＋通話前景服務 lifecycle。UI 文案零技術名詞；全部草案待人類設計。
- **驗證**：`flutter analyze` No issues（初輪 23 issues 已修：call_manager import 缺漏／dart:convert／lk 前綴／`videoTrackOf` 新增／null-aware elements／unused import）；`flutter test` 164＋1 skip 全過零退化；`python3 ci/license_check.py` exit 0；`flutter build apk --release` 134.6MB，aapt2 確認 `versionCode='2031'`（2030→2031 嚴格遞增）。
- **⚠️待實機驗證（APK 2031）**：內建放音雙路衝突（`setCommunicationDevice` vs livekit AudioManager 路由 ⚠️batch 20 同款風險）；螢幕分享權限框＋前景服務鏈；倒數橫幅與自動退出實際觸發；PiP 進出行為；返回再入 session 重用。

### 2026-11-10（第三十批）— LiveKit v0 實作（人類批准動工；依賴零新增）
- **實作**：新檔 `livekit_call_manager.dart`（JWT `/sfu/get` → lk Room E2EE 連線 → 磚格 → 掛斷；`RingLiveKitKeyProvider`＝官方 `EncryptionKeyProvider` 純儲存↔轉發）；`ring_delegate.dart` keyProvider 可注入；`call_manager.dart` VoIP getter＋注入＋LiveKit backend 的 mesh UI 圍欄；`livekit_call_screen.dart` 重寫（骨架樣式）；fold menu 標籤改「多人通話（測試）」。groupCallId 定 `'lk:<room.id>'`（與 mesh 同通道互搶 session 的關鍵隔離；加入端從房內既有 livekit membership 抽 call_id 保兩端一致，有 11 個新單元測試）。詳情＝known_problems.md「第三十批」節。
- **驗證**：`flutter analyze` 0 issue；`flutter test` 164 全過（原＋新）；`python3 ci/license_check.py` exit 0；`flutter build apk --release` 134.5MB，aapt2 確認 `versionCode='2030'`（2029→2030 嚴格遞增）。
- **⚠️待實機（APK 2030）**：matrix.org JWT 回應形狀／lk identity 格式（`<userId>:<deviceId>` 先例）／B 端循 famedly state 加入／Element X 不可見（famedly flavor 恆定）。

### 2026-11-10（第二十九次前置研究）— 外部原始碼對照（人類指示「參考 Element X 和 FluffyChat 原始碼設計，不要瞎猜」）
- **Element X Flutter 已下架**：element-hq org 已無 element-x-flutter repo（GitHub 404，2026-11-10 查）；Element X 現僅 Android/iOS native 版（matrix-rust-sdk＋Element Call webview），與我方 Flutter＋官方 dart SDK stack 不同——只剩產品行為可參照，**無程式碼可參照**。
- **FluffyChat 已棄 mesh voip**：2026-08 `refactor: remove legacy calls`（commit c83cd72，-1300 行，全面改走 LiveKit MVP PR #3417 已 merge）。意義＝與我方同 SDK 路徑的 FluffyChat 也長期受 mesh 問題困擾（#1313/#2329）最後整段拋棄——**mesh 深層修復在官方 SDK 資料通道層，App 端只能 mitigation**，與二十八批判讀一致。
- **FluffyChat legacy 源碼對照**（自 GitHub raw 親抓 parent commit e905e87 五檔，存 `/tmp/opencode/fc_legacy/`）：`voip_plugin.dart`＝實作官方 `WebRTCDelegate`，`handleCallEnded` 內 `overlayEntry.remove()`（1:1 UI 結束即拆）；**`handleGroupCallEnded` FluffyChat 本身 TODO 空殼**。SDK 事實（14.2.0 本機查證）：`handleGroupCallEnded` 唯一呼叫點＝本端 `leave()`（group_call_session.dart L166）；遠端成員離開只走 mesh_backend `_removeCall`→`callsChanged`＋`CallRemovedEvent`（內部 `hangup(shouldEmit:false)`，註解「no need to emit individual handleCallEnded on group calls」）＝**SDK 永不為群組 session 發 ended 事件**——正是「B 掛斷後 A UI 不退」根因（我方 delegate 兩入口都已實作，群組入口因 SDK 無事件而永不觸發）。
- **Wake lock 對照**：Android 官方建議 `FLAG_KEEP_SCREEN_ON`（無需 permission/plugin，Activity 退出自動失效）＝零依賴可行（Kotlin MainActivity＋MethodChannel）；FluffyChat legacy 走 `flutter_foreground_task`（點亮一次非保持）＋`wakelock_plus`＝新依賴路徑（須批准）。
- **草案已落 known_problems.md「第二十九批前置研究／草案」節**（A：kEnded→UI 閉合；B：群組 lifecycle watchdog；F：殘留 session 清除；E：inbound-rtp 掉流偵測＋重新加入；D：wake lock 二選一；spurious kEnded 記歷透明化）——**待人類拍板後才動工**；預計動檔：`call_manager.dart`／`call_screen.dart`（＋若 D-1 獲選：`MainActivity.kt`）。versionCode 預計 2029→2030。

### 2026-11-10（第二十八次）— 通話易錯①glare 吞來電修＋②殘留 session 掃除＋③推播到達喚醒（oneShotSync）＋臨時通話診斷列；零新依賴
- 人類筆記清單（/home/user/Downloads/0843ebb7-e8b1-436c-9f4e-1131f1131906.txt）第 16 條「通話容易出錯（無法發起通話、兩邊同時發起，無法互接）」拍板為本批（候選 A 圖片間歇送失敗／B 推播／C 通話／D 背景取消中選 C）；唯讀根因調查後人類拍板修復範圍「**連③一起進本批**」，背景冷喚醒／№14 推播檢修排**第二十九批**（需對端 logcat）。⑤麥克風／相機 runtime 權限硬化＝人類範圍決定未納入。
- 靜態證據鏈（本機查證 matrix 14.2.0 官方原始碼）：①glare——SDK 官方 glare 健全（call_session.dart L208-240 initWithInvite：同房既有 incoming invite 時以 callId 字典序比較，新 callId 較大 → 自掛新的保留舊的；較小 → 自動接受新的），但我們 `CallManager._onNewCall`（舊 L111-113）在 `activeCall` 未清空時**直接丟棄新來電** → 半接聽 glare 情境勝出方向的來電 UI 永不浮現＝「兩邊同時發起無法互接」。②卡死——startCall 撞 `activeCall != null && !callHasEnded` 即擲「已有通話進行中」（L200-203）；批次 II-c 已註記 SDK `onCallEnded` 偶不觸發 → 前通話異常收尾後殘留 → 新通話永遠被擋＝「無法發起」。③來電偵測只靠 sync（call_manager.dart 檔頭註明「背景推送不在本批」）且 `m.call.invite` 是房間事件；`push_runtime.dart` `onMessage` 原為**空實作** → 推播到達不觸發 sync（№14 成因之一）。④TURN——voip.dart `getIceServers`（L937-957）取 TURN 失敗回**空陣列**、無 STUN 兜底＝跨 NAT 連不上風險（SDK 官方行為；依規 App 端不手寫伺服器位址，本批只做診斷驗證）。
- 修（SDK 官方 API 接合、零新依賴、**不碰加密／金鑰**）：
  - `app/lib/voip/call_manager.dart`：①`_onNewCall` 忙碌時改**暫存** `pendingIncoming`（不再丟棄）；`_surfacePendingIncoming`＝microtask（同批 onCallEnded 先清場再判斷），`activeCall` 清空後浮現為 `incomingCall`；pending 已終態即棄（SDK 官方 lifetime 逾時／對方取消）；`_onCallEnded` 補 surface 鉤＋pendingIncoming 分支清理。②`_watchStaleCalls`＝官方 `client.onSync.stream` 每輪檢查：`activeCall` 已終態 → `clearCall`（解 II-c 殘留卡死）、pending 已終態 → 棄（解 glare 逾時殘留）；`onLoginStateChanged`（登入武裝／登出解除＋清狀態）；dispose 取消訂閱；startCall 錯誤訊息帶 `callStateLabel` 狀態標籤。診斷輔助＝`diagnosticLastCallEnd`（最近終態時間＋state）與 `diagnosticIceServerCount()`（官方 `voip.getIceServers()` 數量；−1 取得失敗／−2 未初始化）。
  - `app/lib/push/push_runtime.dart`：`onMessage` 空實作改官方 `client.oneShotSync(timeout:10s)`（`syncPending` 時不疊加——官方語意即等待進行中 sync）。**披露：僅 App 行程仍活時有效**；行程凍結／被殺的背景冷喚醒＝第二十九批。
  - `app/lib/ui/call_screen.dart`：臨時診斷列（批次十九模式）「二十八診斷： ICE=N（0/負值=沒有中繼伺服器）· 上通 HH:MM:SS 終態」——供 ④ TURN 與 glare 失敗回報判讀；**樣式草案、下批除役**（待人類定稿）。
  - `app/pubspec.yaml`：僅 bump→1.0.2+2029。
- 測試**披露（無新增單元測試）**：CallSession／VoIP 鏈綁 RingWebRTCDelegate 與 WebRTC 工廠，無廉價 fake 注入點（批次 II-c 以來同限）；本批行為驗證＝實機（診斷列＋兩端通話）。
- 驗證（實際輸出照貼）：analyze → `No issues found! (ran in 7.7s)`（初版 2 error＝`CachedStreamController` 需 `.stream` 才能 `.listen`（onSync／onLoginStateChanged），照 main_shell 既用法修正後歸零）；test → `00:49 +153 ~1: All tests passed!`（批二十七基準 +153，本批**無增減**＝披露如上）；license_check → `LICENSE_EXIT=0`（26 項零變動）；build → `Running Gradle task 'assembleRelease'...                          196.9s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.2MB)`＋`BUILD_EXIT=0`（輸出含既有 Flutter 內建 Kotlin 遷移警語＋vodozemac_bindings_dart 三架構建置 INFO，皆工具鏈／既有套件行為）；aapt2 badging → `package: name='com.example.ring' versionCode='2029' versionName='1.0.2'`（2028 已於第二十七批出過，嚴格遞增）。
- 待實機（APK 2029；glare／互接需兩端實證，對端請配合）：①正常撥接兩端通（既有回歸）；②**兩端同時撥** → 一端自動掛掉自己的去電並浮現勝出方向的來電（glare 修）；③前通話異常收尾（如對端瞬斷）後**立即**發起新通話，不再卡「已有通話進行中（…）」；④通話畫面診斷列：ICE 數（matrix.org TURN 正常應 ≥1；0／負值 → 回貼截圖供 TURN 診斷）；⑤行程仍活的背景下收到訊息 → 通知／來電會響（凍結情形無效＝第二十九批）。
- 需人類拍板：診斷列樣式定稿與除役時點（承諾下批移除）；兩端實證的時間安排；第二十九批＝№14 推播檢修＋背景鈴冷喚醒（需對端版本與 logcat）。
- **上機實測（2026-11-10 21:0x，人類在對端 B 協同；群組通話兩端實跑）**：加入成功（kCreateAnswer→kConnecting、頂列 2 人、TURN relay 候選成功＝matrix.org ICE 有貨、本機相機渲染正常），但**成員中途變動後 mesh 僵局**：21:07:23 我端收到**無人掛斷**（人類確認）的 kEnded＋kHangup → 引擎結束而 UI 仍掛「群組通話（2 人）」＋控制列（畫面與引擎脫鉤）；SDK 反覆 `[VOIP] Waiting for @itsxiaobai:EIXY3DdfRY to send call invite`（官方 mesh_backend.dart L985）＋成員重談判事件全被「Ignoring call event … because we do not have the call」丟棄；我方 21:11:13 手動掛斷退出乾淨（app 不崩）；退出後官方 `_onActiveSpeakerLoop`（mesh_backend.dart L343）於已 null 的 peerConnection 上 getStats 炸 `Unhandled Exception`（官方 SDK 缺陷）。雙方體感（人類描述）：只看得到自己、對方畫面短暫幾秒後消失、鏡頭兩端都開、無人掛斷。判讀＝**群組通話（MeshBackend）成員 churn 重談判僵局，非本批 1:1 鏈**；證據與三項對策方向列入 known_problems.md 新條目（下批修）；全量 logcat `/tmp/opencode/ring_2029_full.logcat`＋截圖 `/tmp/opencode/ring_2029_gc*.png` 留存。本批 28 的 1:1 診斷列／glare 兩端實證仍未做（需 1:1 DM 兩端再約）。
- **上機實測二三四輪（2026-11-10 21:27-21:57，雙機 force-stop 冷啟＋雙機 ADB assistant 驅動＋人類協同；同版 2029；logcat 存 /tmp/opencode/ring_A_round3.logcat、ring_B_round3.logcat）**：二輪（A 發起→B 加入）連線成功雙 tile 正常，**4-5 分鐘後 B（加入端）遠端掉成灰色頭像 placeholder、A 端正常、雙端 logcat 零異常**＝媒體層單向掉流信號層無感；21:34 B 掛斷＝A 端 kEnding→kEnded→kHangup 事件鏈完整收到**但 UI 不退出（二次重現）**——「remote kEnded 路徑 UI 不閉合」定為常態缺陷（自己按掛斷路徑則正常）；掛斷後 B 端出現殘留「群組通話（0 人）」tile＋頂列電話 icon 被 session 殘留吃掉（需 force-stop 復原）；A 端 adb tap 座標失效（人類手動按成功）。三輪（B 發起→A 加入）＝kConnected 21:49:08/09，**截至 21:57 八分鐘雙 tile 正常、零 kEnded／零掉流**，人類體感「前面卡有點久，後面恢復」；member churn（Not updating _participants）反覆但未掀翻僵局＝僵局觸發條件與 churn 頻率無必然相關（耦合更多條件）。**人類新增需求：通話中避免關屏（wake lock）**。已知問題條目已補全（下批修；含通話期間 drop 根因屬 SDK 資料通道層）。

### 2026-11-09（第二十六次）— ①外部檔案分享完整路線（ACTION_SEND／SEND_MULTIPLE 整線）②公開聊天室分類根因修（join_rules 預載＋單一 state 端點兜底）；零新依賴
- 人類拍板（2026-11-08 實機回饋「外部檔案分享功能仍然沒完成，參考 share_EX」＋「公開聊天室仍無法分開」＋四問算是「是／\*/\*／暫存登入後自動開 picker／session 內快取」）。藍圖 §五覆核：加密邏輯零修改（分享檔案的加密全走 SDK 官方 `sendFileEvent` 內部路由）。
- **根因①**：批十三 v0 只接 app_links（VIEW intent；連結／文字 uri）；AndroidManifest 既有 ACTION_SEND filter 但檔案型 intent 落入 MainActivity 後無人消費＝吞掉；且缺 SEND_MULTIPLE（多檔）。
- ①修（native 零新權限）：`MainActivity.kt` 新增 `ring/share` MethodChannel——onCreate（savedInstanceState==null）冷啟動分享解析後暫存（未登入即停在 native＝人類拍板「登入後自動開 picker」）、onNewIntent 熱啟動即時推 Dart（channel 未就緒亦落暫存，get_initial 可取回）；EXTRA_TEXT＋EXTRA_STREAM（單 Uri／多 Uri；API33 typed getParcelable 分支）；檔案＝ContentResolver 複製到 `cacheDir/ring_share/` 回 {path,name,mimeType,sizeBytes}（intent 自帶讀取授權；檔名 sanitize）。`AndroidManifest.xml` filter 補 SEND_MULTIPLE、mime 統一 `*/*`。Dart：新檔 `share_receiver.dart`（SharedItem/SharePayload＋channel＋廣播流＋readInitialShare 讀取即清）；`main.dart` `_initShareReceiver`＝startShareReceiver(pushShare)＋app_links 分支改推 `SharePayload.textOnly`（舊 String 控制器移除）；`main_shell.dart` `_listenShareReceiver`（MainShell 首掛 readInitialShare→開 picker→再訂流）→ `_openShare(payload)`。
- 分享送出＝聊天頁附件**同一官方鏈**：`share_to_room_screen.dart` 改吃 payload；圖片 `prepareImageInBackground`（背景 isolate 下採樣＋縮圖）→ 加密房 `encryptFileInBackground` → `buildUploadFile` → `sendWithRateLimitRetry`（chat_screen 頂層函式）`Room.sendFileEvent`（自帶 txid；加密由 SDK 官方內部路由）→ 失敗 `OfflineQueue.enqueueAttachment`（path 優先；FileTooBigMatrixException 不入列，批四規則）；文字 `sendTextEvent`。UI 維持 share_EX 結構（搜尋＋多選 checkbox＋右上送出）＝草案，待人類定稿。
- **根因②**（SDK 來源證據）：matrix 14.2.0 `importantStateEvents` 預載清單（client.dart L275-284）**不含 m.room.join_rules** → App 重啟後 partial 房間記憶體 states 缺 join_rules → `Room.joinRules`（room.dart L2644）恆 null → `_isPublicRoom` false → 已加入公開房全落「群組」（實機 47 房全誤截圖）。名稱／頭像／isSpace 正常＝同清單含 RoomName／RoomAvatar／RoomCreate。
- ②修：`client_factory.dart` 持久化 Client 加官方構造參數 `importantStateEvents: {EventTypes.RoomJoinRules}`（之後 sync 取得的 join_rules 由 SDK 永久進 preload box、重啟即載）；`contacts_screen.dart` 分類前以 `_effectiveJoinRules` 取規則：記憶體有值直接回 → session 快取（人類拍板）→ 官方單一 state 端點 `Client.getRoomStateWithKey(roomId,'m.room.join_rules','')`（api.dart L5045）補查 → 成功同時以官方 `StrippedStateEvent` 補進記憶體 states → 查失敗 null（保守歸群組，原行為）＋`resolveJoinRules` 注入點（測試防觸網）。**成本披露**：本地仍缺 join_rules 的房間（歷史 sync 的既有 47 房首次）每 session 各一次單一 state 小 GET；新 sync 之後由重要 state 持久化路線吸收。
- 測試：新檔 `test/share_receiver_test.dart`（parse 完整／缺欄位預設／null-空／textOnly／pushShare 空 payload 不推流，5 案）＋`test/contacts_screen_widget_test.dart` 追加「partial 房 resolveJoinRules 兜底 → 公開聊天室；warm 房（記憶體有值）不觸發降查」1 案（`_FakePartialRoom` 覆寫 joinRules→null）。**+143→+149（＋6）**。**過程披露**：原第 6 案（testWidgets 以 `handlePlatformMessage` 模擬平台 share 呼叫）在 Dart 測試環境造成事件迴圈不停排幀、10 分鐘逾時（`10:15 +149 ~1 -1: Some tests failed`）——channel 橋接屬 Kotlin／實機層，移除該模擬案改列實機驗證；受測核心（SharePayload.parse 端）全保留；產品 handler 相應同步 parse 化（`Future.value` 回包，語意等價）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 6.8s)`**；test → **`00:27 +149 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 120.6s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.2MB)`（BUILD_EXIT=0）；merged as release manifest → `versionCode="2027"`、`versionName="1.0.2"`、`android.intent.action.SEND`＋`SEND_MULTIPLE`＋`ring/share` 在列（2026 已於第二十五批出過，嚴格遞增）。MainActivity.kt Kotlin 不被 analyze／test 涵蓋，僅由 release build 編譯（BUILD_EXIT=0），行為待實機。
- 待實機（APK 2027）：①他 App 分享單檔／多檔／照片／一般檔 → Homing 出現於分享清單 → Send to picker → 送出成功，加密房可解密；②分享時未登入 → 完成登入後自動開 picker；③冷啟動被分享喚起也進 picker（不重複彈）；④App 重啟後「公開聊天室」回到第三塊（47 房首次各一次小 GET 後正確；Space 持續歸群組）。
- 未完成／後續可選：cacheDir/ring_share/ 分享暫存檔送出後不清（v0）；picker 送出僅房間級進度，無逐檔進度 UI（草案待人類定稿）；FileTooBig 附件計為該房失敗不重試。

### 2026-11-08（第二十五次）— 四項整合（設定入首頁頭像＋Spaces 歸聯絡人群組＋聯絡人「＋」三選項＋skeleton 裝置驗證刪除）；零新依賴
- 人類 2026-11-08 四項整合指示＋三問拍板：①「是」＝底列設定 tab 移除（4→3）；②群組欄「＋」＝建立聊天室、加入既有＝公開聊天室（公開房一律第三塊、私群組第二塊）；③「是」＝死檔一併刪除。藍圖 §五覆核：本批加密邏輯**零修改**（官方驗證／診斷只搬位置）。
- ①設定入首頁頭像：`settings_screen.dart` 重構＝`SettingsScreen` 薄 wrapper＋`SettingsBody`（StatefulWidget 本體、去 Scaffold）；`rooms_screen.dart` 左上頭像 tap → isScrollControlled bottom sheet（高 0.85）內嵌 SettingsBody＋「設定」標題＋關閉時刷新頭像；登出入口隨面板（原設定頁登出鏈路。外觀／二階段驗證等全部分區照舊）。頭像官方鏈＝`fetchOwnProfile`→`Uri.getThumbnailUri(width:96)`＋`authenticatedMediaSupported`→Bearer header；**無頭像才顯示名稱第一個字**（人類指示，`_initialForFallback`）；移除頭像後伺服器快取殘影＝共用 kv 旗標（`app_settings.dart` `ownAvatarRemovedFlag`，settings／rooms 同源讀取抑制）。`main_shell.dart` 底列 4→3（聊天室／聯絡人／通話；IndexedStack 移除 Settings 子層）。
- ②Spaces：`rooms_screen.dart` 移除 Spaces 收合區塊＋對話列表過濾 `isSpace`；Space 歸聯絡人「群組」（`contacts_screen.dart` `_isPublicRoom` **排除 `Room.isSpace`**——public join rule 的 Space 不落第三塊）；群組中 Space tile 點擊 →「Space 底下的聊天室」清單（官方 `getSpaceHierarchy`，`room_actions.dart` `showSpaceRoomsSheet`）。第二／三區塊＝第二十三批既有分類語意明文固定：已加入公開房（官方 `Room.joinRules == public`）＝第三塊、私人群組＝第二塊。
- ③聯絡人「＋」三選項：新檔 `room_actions.dart`＝`showAddChatSheet`（建立聊天室／加入公開聊天室／加入好友）＋`runAddChatSheet` 統一派發＋`showCreateRoomFlow`（官方 `createRoom`）＋`showJoinPublicRoomFlow`／`openPublicRoom`（官方 `queryPublicRooms`／`joinRoom`，自 rooms_screen 搬入）＋Space 清單 helper；首頁「＋」同源共用（rooms_screen `_showAddSheet` 改走共用 sheet）。contacts FAB tooltip「新增」。加入後 `_load` 重算分類。
- ④驗證裝置／診斷入設定「進階」區＋skeleton 移除：官方 SAS 裝置驗證（`DeviceKeys.startVerification` → `showDeviceVerificationDialog`）＋完整 crypto 診斷（帳號／homeserver／deviceID／加密狀態＋上傳裝置金鑰／自我簽章）自 rooms_screen ⋮ 搬入 settings 進階（`_selfSignWithRecoveryKey` 原樣搬入）；新裝置信號 listener 留在 rooms_screen；`device_verification_dialog.dart` 新增全域 `deviceVerificationDialogShowing` 旗標互斥（settings 入口與 rooms 來電 listener 防疊窗）。**settings_screen 原「裝置驗證」skeleton 項（無作用按鈕，官方沒有這個東西）移除**。死檔刪除（人類拍板③）：`device_verification_screen.dart`／`new_device_setup_screen.dart`／`new_device_verification_flow_screen.dart`＋測試 `new_device_verification_flow_screen_widget_test.dart`（四檔皆零引用者，grep 覆核）。
- 測試：`ui_redesign_test.dart` 改寫（底列 3 tab＋頭像面板：SettingsBody 分區斷言、捲動至資料匯出／登出、登出確認對話框呼叫注入的 `MainShell.onLogout`；Spaces 首頁消失、聯絡人群組內點開 Space 清單）；`contacts_screen_widget_test.dart` 新增「Space 一律歸群組」＋FAB 三選項案（`_FakeSpaceRoom` 覆寫 `isSpace`）；`device_verification_widget_test.dart`／`ui_smoke_test.dart` 移除死檔案例。**+147→+143（−5 死檔案、＋新案）——測試數減少為人類指示刪檔所致，非鎖弱化；官方功能鏈斷言全保留**。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.7s)`**；test → **`00:24 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（直接依賴清單零變動）；build → `Running Gradle task 'assembleRelease'... 160.6s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.2MB)`；merged release manifest → `versionCode="2026"`、`versionName="1.0.2"`（2025 已於第二十四批出過，嚴格遞增）。
- 待實機（APK 2026）：①底列三 tab、設定由首頁左上頭像開啟（面板內含設定本體＋登出）；②頭像變換兩向：設定換頭像→首頁即刻；移除頭像→首頁消失不殘影；無頭像顯示**名稱首字**；③首頁無 Spaces；Space 在聯絡人「群組」內（點開見 Space 底下聊天室清單）；④群組中公開聊天室列第三塊、私群組第二塊；⑤聯絡人「＋」三選項（建立聊天室／加入公開聊天室／加入好友）；⑥設定進階：官方 SAS 驗證裝置（兩機配對）＋診斷（含上傳裝置金鑰／自我簽章）；⑦加密情景回歸：既有 DM 金鑰對話於重構後解密仍正常（本批零接觸加密邏輯，照規擬驗）。

### 2026-11-08（第二十四次）— Matrix 應有功能補齊（typing／訊息編輯／topic／房名頭像管理／頂列成員數）；零新依賴
- 人類拍板範圍「全做」＋「是」：Tier 1 四項全做＋Q1 成員數 (N)＝加。藍圖 §五覆核（加密／金鑰本批零接觸；本批全部走 SDK 既有官方通路，零新依賴）。
- **typing 指示**：發送＝`Room.setTyping`（room.dart L2637；輸入 onChanged 觸發，7 秒節流、timeout 10000、送出成功／清空輸入即停止 setTyping(false)）；顯示＝官方 `Room.ephemerals['m.typing']` 直讀（`Room.typingUsers` getter 對無 state 使用者會 fire-and-forget `requestUser`→觸碰 DB，測試環境炸 LateError，故遵循本檔「純記憶體讀取、無副作用」慣例改直讀公開 map）。顯示位置＝輸入列上方（Element X 同語意；名稱鏈＝既有 getState(RoomMember)→asUser.calcDisplayname()）。刷新通路＝onSync 摘要指紋＋本地 4 秒 ticker（SDK `Room.setEphemeral` 內建 30s 超時清空**不會**再觸發 onSync，room.dart L442-451）。
- **訊息編輯**：顯示＝官方聚合（`Event.hasAggregatedEvents(timeline, RelationshipTypes.edit)`＋`Event.getDisplayEvent`，event.dart L1180-1222 僅採原作編輯）；`m.replace` 編輯事件自身由轉換迴圈過濾不渲染（`Event.relationshipType`）；純文字列顯示「(已編輯)」記號。送出＝SDK 官方 `Room.sendTextEvent(editEventId:)`（room.dart L688 參數；429 退避重試同一般送出）；長按選單新增「編輯」（條件＝本人＋m.text＋未收回），進入編輯狀態與回覆互斥（編輯預覽列同構圖）。**編輯不入離線佇列**（OfflineQueue.enqueue 會把文字變新訊息，語意不對）→ 離線編輯失敗僅 SnackBar 並保留編輯狀態。
- **聊天室說明（topic）**：官方 `Room.setDescription`（room.dart L528——**無 `setTopic` 此名**）；`RoomInfoScreen` 顯示既有說明列＋管理項「新增／編輯說明」（`Room.canChangeStateEvent(EventTypes.RoomTopic)` 權限判別）。
- **房名／頭像管理**：官方 `Room.setName`（L520）、`Room.setAvatar(MatrixFile?)`（L2317：內建 uploadContent→m.room.avatar；null＝移除）；`RoomInfoScreen` 管理項「更改名稱／更換頭像（相簿選取＋移除）」，一對一不顯示、權限同上。
- **頂列成員數 (N)**（Q1 人類拍板「是」）：非一對一頂列房名旁顯示 ` (N)`，官方來源 `RoomSummary.mJoinedMemberCount`（`Room.summary` 非 null 欄位）；缺值／例外不顯示。
- 測試：`rooms_chat_screens_widget_test.dart` 新增 3 案（typing 顯示／無人輸入不顯示／isEdited 記號）；**+144→+147**（只增不減）。typing 測試內容：SDK setEphemeral 的 30s 清除 Timer 需 `tester.pump(31s)` 跑完避免 pending timer。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.9s)`**；test → **`00:23 +147 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 124.8s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.2MB)`；merged release manifest → `versionCode="2025"`、`versionName="1.0.2"`。
- 已知限度（對人類披露）：①編輯解析僅套用到文字 body／顯示記號；附件類訊息若被他人編輯 msgtype，本 App 依原訊息類型渲染新 body（本 App 送出的編輯僅限制在 m.text，跨類型編輯極少見）；②typing 為告知性資訊、失敗靜默不阻擋送訊；③一對一無房名/頭像管理項；④成員數為房間摘要值（同步延遲時可能短暫缺值不顯示）。
- 待實機（APK 2025）：①輸入時對方裝置顯示「正在輸入…」、反向驗證；②長按自己文字訊息→編輯→送出→兩端顯示新文字＋(已編輯)；③對方用 Element X 編輯，Homing 端顯示新內容；④群房資訊改topic/房名/頭像；⑤頂列群名旁 (N)。Q1 解答已落實（＝頂列成員數）。Tier 2/3 未做項（threads／spaces／presence／金鑰備份／語音訊息）維持未拍板。

### 2026-11-08（第二十三次）— 聯絡人分類照 LINE 模型修正＋「加入公開聊天室」回歸＋選項；零新依賴
- 人類 2026-11-08 指示「查詢 LINE 設計，重新處理」：①公開聊天室（瀏覽/加入）應在**新增選項**（＋ sheet）；②目前歸「群組」的公開房應列在**公開聊天室**；③私人多人＝**群組**；④一對一＝**好友**。
- 分類技術（SDK 官方查證）：`Room.joinRules` getter（room.dart L2644 讀 `m.room.join_rules` state 的 `join_rule`）＋`JoinRules` enum（src/utils/room_enums.dart：public/knock/invite/private/restricted/knock_restricted；matrix.dart L54 匯出）。判別：一對一（isDirectChat）→好友；非 direct 且 joinRules==public →公開聊天室；**其餘（含 null／例外）→群組（保守私密）**。
- `contacts_screen.dart`：`_load` 三分類（`_friends/_groups/_publicJoined`）；公開聊天室 tab＝**已加入**公開房（點擊開啟；長按無功能＝同群組）；空文案「還沒有加入公開聊天室（用首頁『＋』加入公開聊天室）」；`_hideFriend`/`_deleteFriend` 同步過濾三分類。移除批次二十一的 tab 內 `getPublicRooms` 遠端拉取路徑（`_loadPublicRooms`/`_buildPublicRoomTile` 等）。
- `rooms_screen.dart`：「＋」sheet 回復三項（建立聊天室／**加入公開聊天室**／加入好友；批次二十一移除項+回歸）；重建 `_joinPublicRoom()` 瀏覽器 bottom sheet（官方 `queryPublicRooms(limit:100)` 一次性＋已加入 badge（官方 getRoomById）＋調整輸入即時本地過濾＋送出官方 `generic_search_term` 伺服器端重查；StatefulBuilder 可變狀態置於 builder 外避免重建掉焦點，queryCtrl 釋放於面板關閉）；點房：未加入 → 官方 `joinRoom`（成功後 `_load()`＋收面板＋開 ChatScreen 走既有 openRoom 鏈）；失敗 → SnackBar。
- 測試同步：`ui_redesign_test.dart`（sheet 三項回復）；`contacts_screen_widget_test.dart` 新增分類測試（join rule public →公開 tab、無 state →群組）、遺留 +143→**+144**（只增不減）。
- 隨批（同一套驗證鏈）：analyze → **`No issues found! (ran in 7.7s)`**；test → **`00:40 +144 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 139.2s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.1MB)`；merged release manifest → `versionCode="2024"`、`versionName="1.0.2"`（2023 已於第二十二批出過，嚴格跳至 2024）。
- 待實機（APK 2024）：①聯絡人三分類計數與點開；②首頁「＋」→加入公開聊天室瀏覽器（搜尋 / 已加入badge / 加入後自動開房）；③公開房 join 後出現在聯絡人公開 tab。Q1 頂列成員數 (N) 仍待人類回答「加／不加」。

### 2026-11-08（第二十二次）— LINE 結構參考 UI 重設計第二段＋Element X 頭像面板；零新依賴
- 人類 2026-11-08 拍板「全部（聊天內頁→通話→設定→首頁/聯絡）＋左上頭像參考 Element X」；本輪補讀 `LINE_ref/new_ref/` 全部標註稿（chat 5 張／member／calls_history＝Element `Call started` chip 構圖／calls 2 張／settings 主頁／friends 4 張／album）。
- **執行前人類答覆**：②公告摘要列「是」（解讀＝同意預設**本批不做**，屬新功能，見待決定）→ 若解讀有誤請再說；③聯絡長按選單**保留**「收藏」入口（稿上劃掉不採）；④相簿專頁「是」（解讀＝同意預設**不列**）；⑤audio_diagnostics 清除＝「預設」（不併入本批，下批清理）；①成員數 (N)＝人類問「什麼意思」→ 已解釋「307(40)」＝群名括號成員數，**待人類回覆加／不加**，本期頂列僅「頭像＋房名」。
- 範圍內已有而未重做（查證後跳過）：底部輸入列與附件面板（×/相機/相簿＋Files/Contact/Location，批次 III-a）、訊息長按選單（回覆/刪除/複製/檢舉/分享，批次 E）、檔案卡 Size 行（批次十二④，同稿 162223）、封鎖確認對話框結構（批次 III-b，同稿 173655）、首頁 tile 時間/未讀徽章/靜音（批次 D＋III-c）、設定頁分區（批次 III-b 依 210223）。
- 本批實作：①`chat_screen.dart` 頂列＝房頭像（一對一＝對方 m.room.member avatar_url／群組＝Room.avatar，`_roomAvatarUri()` 官方資料）＋房名（`getLocalizedDisplayname` 原鏈路抽成 roomTitle）；②泡泡連續合併：同一發送者連續訊息頭像＋名字只在組首、時間只在組尾（僅樣式，`showSender`／`showTime` 紅旗參數）；③通話事件（既有 m.call.invite 語意）由文字泡泡改**描邊 chip**（`_callInviteChip`；LINE_ref chat calls_history／Element 構圖）；④`main_shell.dart` `_CallsTab` 重排（LINE_ref calls 稿）：大標題「通話紀錄」（headline 風）、tile＝頭像＋名字（**未接＝主題 error 紅字**，不取 LINE 色）＋名字下方向箭號（↙來電／↗去電、群組＝群圖示）＋時間＋時長＋「未接」、**1:1 每列右端電話鈕＝重撥**（官方 `CallManager.startCall`，同 ChatScreen 鏈路；不可用／房間已刪 → SnackBar）、點 tile 本體＝開聊天室、群組列無重撥鈕（群組通話入口仍在聊天頁）；⑤`rooms_screen.dart` 頂列左上頭像**點擊 → 帳號面板**（Element X 款，唯讀 bottom sheet：頭像＋官方 userID／homeserver＋「前往設定」→ 既有 SettingsScreen；登出仍在設定頁）；⑥`settings_screen.dart` 分區標題＝token 次要色。
- LINE 禁區**未**投射（本批清單）：反應表情列（稿上紅字 DO NOT COPY REACTIONS!）、好友推薦、Premium/Coins/主題商店/Labs/Announcements/Help center（稿上皆劃掉）、音樂狀態 pill、上線綠點、Discover/Wallet tab、相簿頁廣告。AD banner 槽＝既有緊急示警橫幅（人類紅框注記映射），未動。
- 測試：**零改動**（新樣式未動任何既有文案斷言；行為鎖 +143 維持）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.7s)`**；test -> **`00:36 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 141.8s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.1MB)`；merged release manifest → `versionCode="2023"`、`versionName="1.0.2"`。
- 待實機（APK 2023）：①聊天頂列頭像＋房名（頭像縮圖載入；無頭像回退首字）；②泡泡連續合併的分組視覺（同人多則時不重複名字）；③通話事件 chip；④通話 tab tile 方向箭號／未接紅字/重撥鈕；⑤頭像點擊帳號面板＋前往設定。
- 待人類決定（帶入下批）：**Q1 成員數 (N) 加／不加**（頂列房名旁）；②公告摘要列（解讀為「本批不做」）與相簿專頁若要進入排程請再拍板；下批擬作：audio_diagnostics 清除（零功能清理）＋已讀③排程。

### 2026-11-08（第二十一次）— UI 重設計首段（首頁／聯絡人／底列）＋更換 icon；零新依賴
- 人類 2026-11-08 提供 design/ mockup（`drawing_defaulthome_UI_v0_2`／`drawing_defaultcontact_UI_v0_1`，SVG＋PNG）＋附圖 icon（`drawing_icon_revert.png`）；拍板：深色用純黑、首頁公開聊天室不實作留給聯絡人頁、選中 chip 調白（#B2B2B2→#C4C4C4 草案）、淺色維持種子色系統（預設或使用者調整）、公開聊天室走路線 A（官方 getPublicRooms）、icon 僅 Android。
- 新檔 `app/lib/ui/design_tokens.dart`（唯一樣式來源；SVG 直出值＋草案標記）：kTextPrimary #282828／kTextSecondary #808080／kDivider #737373／kAccent #FFB381／kSearchFill #E0C1AE／kPillSurface #ECECEC／kChipSurface #C4C4C4／kFabFill #EBD4C8／kDarkSurface #000000。mockup 頁底 #E6C8B8 **未**設為全域 surface（人類拍板淺色跟隨種子系統；如後續想全球化需再拍板）。
- 結構：①`main_shell.dart` 底列＝白膠囊＋選中灰 chip 框 icon、標籤「聊天」→「聊天室」；②`rooms_screen.dart` 頂列＝頭像（登入者首字，#FFB381）＋大標題、搜尋列 token 樣式＋右端「＋」（sheet 移入此列）與 QR；空文案照稿「好像是時候跟朋友聊天了？」；③`contacts_screen.dart` 重構＝三膠囊 tab「好友 (N)／群組 (N)／公開聊天室 (N)」＋搜尋列＋FAB「＋」（添加好友）；公開聊天室＝官方 `Client.getPublicRooms(limit: 100)` 一次性（tab 首開才拉；SDK 型別用非棄用 `PublishedRoomsChunk`），點選未加入→官方 `joinRoom` 後開啟；空文案照稿「加個好友吧！」；④`main.dart` `ringTheme`：dark＝surface/scaffold 純黑 #000000（其他容器維持種子派生灰，草案）；light＝完全維持種子色系統。
- 行為跟著變（披露）：首頁「＋」sheet 移除「加入公開聊天室」（功能移聯絡人頁 tab；`_joinPublicRoom` 對話框路徑移除）；聯絡人 appbar 兩顆 icon（加入好友／設定）依 mockup 移除（加入好友→FAB、設定→底列 tab）；聯絡人「自身頭部」區塊依 mockup 移除。
- icon 更換：`drawing_icon_revert.png`（白底＋桃色半環；量測白 89.0%＋#FFBD9E 10.7%）→ ImageMagick 本機生成 5 密度 legacy（48/72/96/144/192，源稿構圖直譯）＋adaptive 前景（108/162/216/324/432；圖形縮入 66dp 安全區、底緣貼安全區下緣，目視驗證）＋背景層改白 #FFFFFF；iOS 未動（拍板僅 Android）。
- 測試同步（行為鎖不減）：`contacts_screen_widget_test.dart`（tab 計數／稿文案）、`ui_redesign_test.dart`（聊天室標籤／sheet 兩項／聯絡人空文案）、`rooms_chat_screens_widget_test.dart`（新空文案）、`ui_smoke_test.dart`（群組 tab）。
- SDK 延伸記錄：`getPublicRooms`／`joinRoom` 皆 `Client extends MatrixApi` 官方內建（matrix_api_lite/generated/api.dart L3195；本機源碼查證）。
- 驗證（實際輸出照貼）：analyze → **`No issues found! (ran in 7.1s)`**；test → **`00:38 +143 ~1: All tests passed!`**；license_check → **LICENSE_EXIT=0**（26 項零變動）；build → `Running Gradle task 'assembleRelease'... 202.5s`＋`✓ Built build/app/outputs/flutter-apk/app-release.apk (131.1MB)`；merged release manifest → `versionCode="2022"`、`versionName="1.0.2"`。
- 待實機（APK 2022）：①首頁／聯絡人／底列與 mockup 對照（底色種子派生 vs 稿 #E6C8B8 色調差異是否可接受）；②公開聊天室 tab 實拉自家 homeserver 目錄（聯邦可用性 ⚠️待查證）；③深色純黑（容器灰調草案）；④launcher icon 遮罩滿版。

## 發現的事實（查證日 2026-10-31，附來源）

| 事實 | 來源 |
|---|---|
| `matrix` 套件最新版為 **14.2.0**（藍圖 §十五記錄之 12.0.0 已過時） | pub.dev API `packages/matrix` |
| 上游 `pubspec.yaml` 明示 `SPDX-License-Identifier: AGPL-3.0-or-later` | raw.githubusercontent.com/famedly/matrix-dart-sdk main 分支 |
| **matrix.org 已關閉標準 API 註冊**（POST `/register` 與 `?kind=guest` 均回 `M_FORBIDDEN`："Only m.login.application_service registrations are allowed"；GET 回 405；登入僅支援 password／SSO） | matrix.org 客戶端 API 實測 |
| **matrix.org 改用 delegated auth（MAS／OIDC）**：`auth_metadata` 的 issuer 為 `https://account.matrix.org/`；客戶端 `/register` 關閉但**網頁註冊可用**（`https://account.matrix.org/register` 實測 HTTP 200；`/account/` 303 導向登入）。也因此「人類可在 Element 網頁完成註冊」與「API 無法註冊」並不矛盾 | matrix.org `/_matrix/client/v1/auth_metadata`、`account.matrix.org` 端點實測（2026-10-31）；SDK 整合測試 test 4 以 `auth_metadata` 推導出該註冊頁並通過 |
| MAS 提供 legacy `m.login.password` 相容層（舊客戶端仍可帳密登入） | Matrix.org 官方部落格 2023-09「Better authentication…」；matrix.org `/login` flows 實測含 `m.login.password`（2026-10-31） |
| `dynamic_color` 2.1.0 builder 型別指向 `material_ui` 之 ColorScheme，與 `flutter/material` ColorScheme 不相容（故鎖 1.8.1） | 本機 pub cache：dynamic_color-2.1.0/lib/src/dynamic_color_builder.dart＋flutter analyze 實錯輸出 |

## 待人工決定／阻塞中

| # | 事項 | 影響 |
|---|---|---|
| A | ~~matrix.org 註冊已關閉 → 測試帳號~~ **已決議（D，2026-10-31）**：不代建帳號。後續釐清：matrix.org 採 MAS，使用者**可於網頁註冊**（`account.matrix.org/register`），人類已持有 Element 註冊之帳號。**Agent 不索取憑證**；帳密登入由人在本機以 `RING_TEST_USER`／`RING_TEST_PASS` 驗證（測試 2 仍 skip） | 1.3 登入實測（人工） |
| B | matrix.org 關閉客戶端註冊（改走 MAS 網頁註冊）影響藍圖 §一「初期用 matrix.org」的註冊路徑假設 | 藍圖更新（Agent 不得自行改藍圖；可提議文字） |
| C | AGPL 與 App Store 相容性 | Phase 5 前置阻礙，**待專業諮詢** |
| D | ~~pubspec SPDX 標示之人工複核~~ 依賴記錄已補齊（2026-10-31）；**未完成項**：`LICENSE` 版權行與未來版本升級時之人工複核 | 依藍圖 §一規定屬人工確認 |
| E | osv-scanner v2.7.0 binary 由 CI 直接 curl（不驗 checksum） | 若需供應鏈加固，可加 SHA256 校驗或改用官方法 packaging（待人工決定） |
| F | 多帳號／單一 DB 名稱：`client_factory.dart` 固定 `ring.db`／name `ring`；多帳號支援待後續階段（1.13 多裝置前不阻擋） | 1.13 |

## Phase 0 項目清單

| 任務 | 狀態 |
|---|---|
| 0.1 專案命名與商標檢索（TIPO） | 未開工（**待專業諮詢**） |
| 0.2 依賴 SPDX 授權記錄於 DEPENDENCIES.md | ✅ 2026-10-31（並於 1.1 時更新） |
| 0.3 建立 GitHub/GitLab 倉庫 | 未開工 |
| 0.4 設定 LICENSE（AGPL-3.0-or-later） | ✅ 2026-10-31（官方全文 gnu.org/licenses/agpl-3.0.txt；版權行待人類填寫主體） |
| 0.5 撰寫 README.md | ✅ 2026-10-31（草稿；不聲明「與 LINE 無關」，改列「與 LINE 不同之處」） |
| 0.6 建立 DESIGN.md | 🔶 2026-10-31 由 Agent 於授權下撰寫**初版草稿**（名為「須人工審閱定稿」）；定稿後 100% 人工維護 |
| 0.7 撰寫 THREAT_MODEL.md | ✅ 2026-10-31（草稿，依藍圖 §二之二骨架；homeserver 選擇標註待人工決定） |
| 0.8 撰寫 PRIVACY.md | 有草稿（開頭標明須人工審閱） |
| 0.9 撰寫 SECURITY.md | ✅ 2026-10-31（草稿；聯絡管道待人工填寫，不承諾 SLA） |
| 0.10 客戶端支援自訂 homeserver URL | ✅ 2026-10-31（骨架 UI＋解析驗證＋整合測試；正式 DB 儲存方案標註待人工決定） |
| 0.11 CI 授權檢查與依賴弱點掃描 | ✅ 2026-10-31（檔案層：`.github/workflows/license_check.yml`＋`app/ci/license_check.py`；**實際 CI 執行待 0.3 建倉庫後第一次 push 驗證**） |
| 0.12 架構文件 | ✅ draft 2026-10-31（Agent）— `ARCHITECTURE.md` 首版；須人工定稿 |
| 0.13 決定響應式斷點策略 | ✅ 2026-10-31 人類拍板方案 A（Material 3 三斷點）＋已記入 DESIGN.md（草稿待人定稿） |
| 0.14 記錄 Matrix 規格基準版本與 SDK 版本 | ✅ 2026-10-31（DEPENDENCIES.md「規格基準版本」節） |

## 預計目標（backlog；2026-11-01 人類指示記錄，逐項待授權才開工）

- **新增人類目標 (2026-11-03)**：
  - 11. **創作者主題包（開放設計）**：整個軟體的背景、顏色、字型、其他裝飾都能套用主題設計（可能類似貼圖設計做 zip 檔）。※ human 2026-11-03 指示按原始回報「只有新增自訂主題色並非開放設計」重新界定範圍；**暫不動工，先列於此**。開工前需人類決定：①主題包 zip 內容格式（建議比照貼圖包：`theme.json`＋圖片/字型資產，產規格草案文件供審）；②套用範圍（全 App／僅聊天頁）；③匯入方式（建議先支援本地匯入 zip，不做線上商店）。
- **新增人類目標 (2026-11-01)**：
  - 1. **UI/UX 全面重構**：放棄 Material 3 框架，由人類重新設計 UI / UX 視覺與互動邏輯，程式碼實作須確保結構解耦，以便隨時調整版本。
  - 2. 加入投票功能（需評估 Matrix 事件實作方式）。
  - 3. 圖片功能強化：點擊圖片可完整預覽、加入下載、分享圖片功能。
  - 4. 聊天室獨立設定：使用者可選擇是否開啟「自動重點」功能（⚠️ 涉及 E2EE 隱私，需確認本地執行）。
  - 5. 讀取狀態管理：實作「點入後已讀」功能，且允許使用者在看完後手動將訊息標記回「未讀」。
  - 6. 歷史訊息遺失問題：處理「過去訊息消失」現象，解決即使在解密後仍無法抓取舊訊息的問題。
  - 7. 外部分享整合：支援從外部 App 分享檔案至 Homing，並提供選擇分享目標房間（Rooms）的介面。
  - 8. 貼圖關鍵字聯想：貼圖可連結特定關鍵字，當使用者在輸入框打出相關字詞時，自動彈出建議貼圖（Similar to LINE sticker suggestions）。
  - 9. 無聲訊息功能：允許使用者發送不觸發對手裝置通知（靜音）的訊息。
  - 10. Markdown 支援：支援訊息內容以 Markdown 格式顯示（如粗體、斜體、程式碼塊），且使用者可自行選擇開關功能或透過特定按鍵控制切換。
  - 11. 創作者主題包：支援匯入 zip 格式主題包（含背景/顏色/字型/裝飾），可一鍵套用全 App 或局部頁面。⚠️ 屬設計類功能，需人類決定格式規格、套用範圍及匯入方式（建議先實作本地匯入）。
- **批次 A（零新依賴，採用 SDK 官方 API）**：2.7 訊息搜尋功能化（結果點擊→跳進該房間）；Spaces 不視為群組（`Room.isSpace` 分離）；聊天列表／聯絡人／好友顯示頭像（`Room.avatar`）；聊天室通知靜音切換（`Room.setPushRuleState`）；建立／加入／查詢聊天室（`createRoom`／`joinRoom`／`queryPublicRooms`）。
- **批次 B**：聊天室釘選置頂（長按選單；儲存位置待人類決定：本機 sqflite 或 Matrix account data）。
- **批次 C**：聊天室自訂背景；自訂黑白主題與背景色（色板由使用者自選，種子色仍 #FFBD9F）；字型安裝（ttf 匯入）；貼圖系統（⚠️ 屬藍圖 Phase 3，範圍提前須人類明示確認；僅使用者自帶貼圖包，不複製任何 LINE 素材）。
- **P2.15（提案）通話**：人類 2026-11-01 指示「先完成通話功能」。SDK 官方 VoIP 模組（`VoIP` + `WebRTCDelegate`）可用；依賴 `flutter_webrtc`／`webrtc_interface` 已於同日經人類批准並列入 DEPENDENCIES.md。**實作已完成待實機驗證**（見 2026-11-01「P2.15 通話功能」節）。藍圖正文仍無 2.15，**藍圖增補文字由人類定**。
- **人類目標原始清單（2026-11-13 人類提供；逐項標記當前狀態——✅ 已完成／🔶 部分完成／⬜ 未開工；細節以上方批次紀錄與 backlog 編號為準，此處只做對應與狀態標記）**：
  - ✅ 註冊預設 matrix.org，底下多出選項「如果有自己的伺服器，請按這裡！」（2026-10-31 1.3：`connect_screen.dart` 預設 matrix.org＋自訂選項；批次 34 #7 收合）。
  - ✅ 改名（Homing）（批次 33，2026-11-12）。
  - ✅ 選單＝左上按鈕按下 drawer 抽出（電腦版 & Web）、頭像在 drawer 最上方（批次 35 寬屏側欄；待實機）。
  - ✅ 來電通知在旁邊出現，可選擇是否隱藏（批次 34 #2 側邊橫幅＋通知設定「來電顯示」開關）。
  - ✅ 動圖 stickers、不放聲音（批次 35 #4）。
  - ✅ 無聲傳送（批次 35 #5）。
  - ✅ Markdown 支援（批次 35 #13）。
  - 🔶 緊急事件（地震、颱風、綁架）參考 LINE 設計（line-tw-official.weblog.to/archives/17283396.html；批次 35 #6 v0＝RSS 高風險類別橫幅已上；「需要幫忙嗎？（是／否）」「需要幫你聯絡誰？（緊急聯絡人／所有人／119）」求助對話流程＋「緊急訊息不等於聊天室公告」分流未實作）。
  - 🔶 參考 Element X 介面設計和 LINE 按鈕位置配置，重新設計軟體介面（批次 21 首頁／聯絡人／底列；其餘頁面待人類設計定稿）。
  - 🔶 除登入註冊、recovery key 以外，其他相關認證行為應自動化，不應要求使用者手動完成（2026-11-05 已做：登入後官方 `ensureFirstLoginCryptoIdentity()` 自動上傳裝置金鑰＋初始化 SSSS／cross-signing；**裝置互信 SAS 驗證仍為手動**，自動化方案待評估）。
  - ⬜ 建議貼圖不保留（不持久存使用者輸入；貼圖關鍵字聯想＝backlog #8，未開工）。
  - ⬜ 介面或 IP 重新設計（羊和鴿子為主題）——設計類，待人類提供設計稿。
  - ⬜ 顯示事件（聊天頁顯示系統事件如成員加入／改名等；現行 editable 過濾已排除，待人類界定顯示範圍）。
  - ⬜ 所有圖標設為變數，主題包格式為變數對應圖標檔案（併入 backlog #11 創作者主題包；zip 格式待人類定案）。
  - ⬜ 確保無障礙功能仍友善（Fix needed）——無障礙盤點未開工。


## 備註
- `app/` 之 `lib/main.dart`、`test/widget_test.dart` 已於 0.10／1.3 改寫（不再只是 flutter create 預設）。
- flutter create 預設依賴（`cupertino_icons`、`flutter_lints`）之 SPDX 已於 2026-10-31 核對並記入 DEPENDENCIES.md。
- 事實更動時本檔應同步；Agent 每次任務完成依 AGENTS.md 回報格式交付，本檔僅為彙整。
