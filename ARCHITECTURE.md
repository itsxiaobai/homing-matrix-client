# ARCHITECTURE.md — 架構文件（草稿，須人工審閱，非最終版）

> **草稿，須人工最終定稿、修訂。本檔由 Agent 依 0.12 項目自 lib 檔案結構 drafting，未經設計審核。**

---

## 1. 資料模型

### 1.1 基本單位
- **使用者（User）**：Matrix ID（`@localpart:homeserver`）。
- ** homeserver 位址**：以 `Uri`（scheme/host/port，無 path）表示，符合 Matrix 規格。
- **對話（Room）**：Matrix 房間 `id`（`!roomid:domain`）。
- **訊息（Message）**：`m.room.message` 事件中的 `m.text` 類型（Phase 1.4 文字訊息骨架僅處理 `m.text`）。

### 1.2 客戶端狀態
- `Client`（`matrix` SDK v14.2.0）：代表一個使用者 session。
- `Room`（SDK 內建）：房間物件，內含 `states`、`ephemerals`、`roomAccountData`。
- `Timeline`（SDK 內建）：房間訊息 timeline，`events` 列表（新在前）。

### 1.3 資料模型缺口
- **聯絡人（Contacts/Friends）**：目前未獨立建模， reliance on `client.rooms`（群組＋私聊混在一起）。
- **貼圖（Stickers）**：1.4 骨架中尚未實作；Matrix regex `m.image_pack`／`m.sticker` 為相應事件。
- **未讀數、account data**：由 SDK 處理；App 層不另建模型。

---

## 2. 本地資料庫 Schema

### 2.1 儲存方案（方案 C，2026-10-31 人類批准）
- **SQLite 後端**：`MatrixSdkDatabase.init('ring', database: sqflite db, secureStorage: ...)`。
- **資料庫檔**：`${getDatabasesPath()}/ring.db`（單一 `ring`，多帳號留待 1.13）。
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
- 本階段（Phase 1）App 不自行建立 SQL tables。`client_factory.dart` 只封裝 `createPersistentClient()` 與 `createClient()`。
- 若未來需要（Phase 2 資料匯出、 sticker cache），那就是以 Hive 本地 box 由 Agent 寫入，需另經人類批准 schema。

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
- Off-line sending queue 由 SDK 內部管理（本階段不額外實作）。

---

## 4. 狀態管理決策

### 4.1 目前選擇（骨架）
- **不採用** Riverpod / Bloc / GetIt：Phase 1–5 骨架階段 App 元件各自 `StatefulWidget`，Client 由 constructor 傳遞（`RoomsScreen(client:..)`）。
- `login_screen` 成功後 `onLoggedIn(client)` 回呼；`main.dart` 以 `Navigator.pushReplacement` 傳進 `RoomsScreen`。

### 4.2 限制
- 單一 Client（無多帳號）；F 項多 DB 留待 Phase 1.13。
- Client 從 `login_screen` 傳到 `rooms_screen` 由 navigator 區域堆疊持有，無全域 service locator。

### 4.3 待定
- 完整 Provider/StateManagement 方案：需人類決定後才引入（可能新增依賴，要走 AGENTS.md §緊急事項）。

---

## 附錄：摘要

- ** encryption 與 keys 全權交給 Matrix SDK**（vodozemac；SSSS via secure storage）；App 層不寫加密程式。
- ** sync / DB 全由 SDK 提供**，App 只是 UI layer + 少許 routing 介面。
- 本文件為 `0.12` 架構草案，仍需人類定稿（特別是「狀態管理解耦策略」與「多帳號 DB 路徑」）。
