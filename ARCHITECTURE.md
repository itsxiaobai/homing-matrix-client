# ARCHITECTURE.md — 架構文件（草稿，須人工審閱，非最終版）

> **草稿，須人工最終定稿、修訂。本檔由 Agent 依 0.12 項目自 lib 檔案結構 drafting，未經設計審核。**
> **2026-11-14 同步**：依現行實作更新 §1.3／§2／§4 的事實描述（僅事實同步，未定案任何設計）。

---

## 1. 資料模型

### 1.1 基本單位
- **使用者（User）**：Matrix ID（`@localpart:homeserver`）。
- ** homeserver 位址**：以 `Uri`（scheme/host/port，無 path）表示，符合 Matrix 規格。
- **對話（Room）**：Matrix 房間 `id`（`!roomid:domain`）。
- **訊息（Message）**：以事件類型分流渲染——`m.text`（含 Markdown `formatted_body`）、`m.sticker`（貼圖）、`m.image`／`m.video`／`m.audio`／`m.file`（附件）、`m.poll.start`（投票）、`m.call.invite`（通話事件），以及 `m.room.encrypted` 的解密後結果。

### 1.2 客戶端狀態
- `Client`（`matrix` SDK v14.2.0）：代表一個使用者 session。
- `Room`（SDK 內建）：房間物件，內含 `states`、`ephemerals`、`roomAccountData`。
- `Timeline`（SDK 內建）：房間訊息 timeline，`events` 列表（新在前）。

### 1.3 資料模型缺口
- **聯絡人（Contacts/Friends）**：`contacts_screen.dart` 以「好友／群組／公開聊天室」三分類呈現（判準：官方 `Room.isDirectChat` ＋ `Room.joinRules`；`joinRules` 缺值或例外時保守歸入群組）。聯絡人本身不另建模型，資料來源為 `client.rooms`。
- **貼圖（Stickers）**：已實作——`m.sticker` 收發與渲染、匯入端的 zip 解析與上傳（`sticker_pack_importer.dart` 驗證／`sticker_pack_installer.dart` 安裝）、貼圖關鍵字聯想（`sticker_suggestions.dart`，純邏輯）；貼圖清單存於本機 `app_settings.db` 的 `stickers` 表（含 `sort_order`／`mxc_url`／`body`／`pack_id`）。
- **未讀數、account data**：由 SDK 處理（`notificationCount` 等）；App 層另以 `app_settings.db` kv 保存「已推播過的訊息計數」（`notif_count_<roomId>`）以避免重覆推播。
- **未讀徽章／靜音**：靜音走官方 `Room.setPushRuleState`；本機自訂（收藏、隱藏、釘選、佈景、主題、緊急聯絡人）另存本機 DB（見 §2.3）。

---

## 2. 本地資料庫 Schema

### 2.1 儲存方案（方案 C，2026-10-31 人類批准）
- **SQLite 後端**：`MatrixSdkDatabase.init('ring', database: sqflite db, secureStorage: ...)`。
- **SDK 資料庫檔**：`${getDatabasesPath()}/ring.db`（單一 `ring`，多帳號留待後續；單一帳號為目前限制）。
- **App 層自訂資料庫檔**（皆 sqflite，與 SDK 庫分開）：
  | 檔名 | 用途 |
  |---|---|
  | `app_settings.db` | 一般設定 kv、房間背景、貼圖清單、隱藏房間、草稿、主題、公告房間 |
  | `pinned_rooms.db` | 釘選房間（含 `unpinned` tombstone） |
  | `call_log.db` | 通話紀錄 |
  | `offline_queue.db` | 離線訊息佇列 |
- **安全儲存**：access token + SSSS cache 走 `FlutterSecureStorage`（Keychain/Keystore）。

### 2.2 SDK 內建 Box（MatrixSdkDatabase 提供）
SDK 內部 `BoxCollection` 包含 25+ box，App 層直接依賴，不自行定義新表：
```
client, account data, rooms, room state, room members, to-device queue,
read receipts, events, timelines, olm sessions, inbound/outbound group sessions,
cross-signing keys, SSSS cache, presences, ...（完整清單見 matrix SDK 原碼）
```
- ** encryption keys** 由 SDK（vodozemac）管理；App 層**不寫任何加密/金鑰程式**（依 AGENTS.md 約束）。

### 2.3 App 層自訂資料
- App 層自訂資料**全部存於本機 sqflite**（`app_settings.db` 等，見 §2.1），**不使用 Hive**。
- `app_settings.db`（**v5**）結構：`kv`（key/value 設定）、`room_bg`（per-room 背景）、`stickers`（貼圖清單，含 `sort_order` 排序欄位）、`hidden_rooms`（隱藏對話）、`drafts`（草稿）、`themes`（主題命名組合）、`announcement_rooms`（公告房間）。後三張表為後續版本增量加入（遷移以 `onUpgrade` 執行；v5 以 `ALTER TABLE` 加 `sort_order`，既有貼圖順序不變）。
- 所有本機資料**不送任何伺服器**（除官方 API 本身必要的 account data，例如釘選狀態走官方 API）。

---

## 3. 同步策略

### 3.1 SDK Sync
- App 不自寫 sync loop；依 SDK `Client.onSync` 事件驅動刷新 (`rooms_screen` 監聽 `onSync.stream` 並 `_load()`)。
- `Client.rooms` 由 SDK 內部 `_rooms` 提供，已是同步後快照。

### 3.2 房間列表刷新
- `RoomsScreen`：初次 sync 後載房間；sync update 來時 reload `_rooms`（skip heavy re-init）。
- 排序：依 `Room.latestEventReceivedTime` 降序（骨架行為，待 UI 定稿）。

### 3.3 對話訊息刷新
- `ChatScreen`：載 `Room.getTimeline()` → 篩 `m.text` → 舊在前（reversed）；送出後重新 reload。
- 設計上 `Timeline.events` 為新在前，因此需 reverse 以便 ListView 由舊到新。
- **解密案（2026-11-13）**：SDK 對「重裝後重新載入的舊加密事件」沒有重解機制（`can_request_session` 旗標閘；room.dart L1775-1776／timeline.dart L288）。`missing_key_repair.dart` 的 `ensureRoomEncryptionState`／`decryptUndecryptedEvents` 在 `_defaultLoadMessages` 渲染前以 **SDK 官方 API**（`getRoomStateWithKey`／`Encryption.decryptRoomEvent`）補 state 與補解密——仍是官方 API，App 層不新增加密演算法；金鑰備份還原（`backup_restore_screen.dart` `fetchKeys`）對「全量端點漏／空」房間以官方逐房端點補抓聯集（全量端點實測會漏 session）。

### 3.4 離線
- SDK 內部管理部分離線狀態；App 層另有 `offline_queue.dart`（`offline_queue.db`）保存待送訊息佇列（文字與附件，依入列順序 FIFO），於 sync 恢復連線後由 `OfflineQueue.drain` 逐筆送出（送出仍走官方 `Room.sendTextEvent`／`sendFileEvent`）。

---

## 4. 狀態管理決策

### 4.1 目前選擇（現況）
- **不採用** Riverpod / Bloc / GetIt（未新增依賴）；App 層以 `StatefulWidget` 為主，少數共用狀態以 `ValueNotifier`（`AppSettings`）與 `sqflite` 本機資料承載。
- `login_screen` 成功後 `onLoggedIn(client)` 回呼；`main.dart` 以 `Navigator.pushReplacement` 傳進 `RoomsScreen`。
- `Client` 經 constructor 由畫面逐層傳遞（`RoomsScreen(client:..)` → `ChatScreen(client:..)`）；`MainShell` 為底部三 tab 的容器（聊天／聯絡人／設定）。

### 4.2 限制
- 單一 Client（**無多帳號**）；`ring.db` 單一庫名，多帳號需另案設計。
- Client 從 `login_screen` 傳到 `rooms_screen` 由 navigator 區域堆疊持有，無全域 service locator。

### 4.3 待定
- 完整 Provider/StateManagement 方案：需人類決定後才引入（可能新增依賴，要走 AGENTS.md §緊急事項）。

---

## 附錄：摘要

- ** encryption 與 keys 全權交給 Matrix SDK**（vodozemac；SSSS via secure storage）；App 層不寫加密程式。
- ** sync / DB 全由 SDK 提供**，App 只是 UI layer + 少許 routing 介面。
- 本文件為 `0.12` 架構草案，仍需人類定稿（特別是「狀態管理解耦策略」與「多帳號 DB 路徑」）。
