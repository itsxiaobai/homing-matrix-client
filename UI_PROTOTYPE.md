# UI_PROTOTYPE.md — UI 架構草案（草案，待人類設計；非最終版）

> 依據 `AGENTS.md` UI規則，本檔僅提供「UI 架構草案」：畫面結構、元件階層、導覽流程、線框與狀態/資料流。  
> **最終介面由人類設計。** 配色、字型、圖示、間距、動效、配色皆不可在此定稿。  
> 元件不得寫死寬度；響應式策略依 `DESIGN.md` §1（Material 3 三斷點）。  
> 2026-11-01（UI 重構，依人類 `LINE_ref/` 標註）：新增 `MainShell` 底部 3 tab
> （聊天／聯絡人／設定，人類決定）；聊天／對話列表／聯絡人／設定改為 LINE 式版位
> （僅版位；叉掉區域一律不實作，見 §2.4 備註）。本檔所有新增描述仍為**草案，待人類定稿**。

---

## 1. 全域導覽

```text
[ConnectScreen] — 選擇 homeserver
  └─ [LoginScreen] — 帳密登入 / 網頁註冊連結
      └─ [MainShell] — 底部 NavigationBar 3 tab（IndexedStack；聊天／聯絡人／設定）
          ├─ tab1 [RoomsScreen] — 對話列表
          │     └─ [ChatScreen] — 單一對話
          │         ├─ 傳送 bar (always-visible)
          │         └ (optional) 回复/引用（Phase 1.6+，未開工）
          ├─ tab2 [ContactsScreen] — 聯絡人（好友／群組）
          └─ tab3 [SettingsScreen] — 設定（串接既有任務畫面）
[AddFriendScreen] — Matrix ID / QR / 邀請連結
[BlockUserScreen] — 封鎖名單
[ReportUserScreen] — 檢舉
[DeviceListingScreen] — 裝置管理 (Phase 1.5/1.14)
[DeviceVerificationScreen] — 新裝置驗證 (Phase 1.5)
[KeyBackupRecoveryScreen] — recovery key (Phase 1.5)
[NewDeviceSetupScreen] — 新裝置流程 (Phase 1.5)
```

### 斷點行為（DESIGN.md §1）
- compact (<600): 單欄，底部分頁列（ChatList / Contacts / Settings）。
- medium (600–839): 左列表 + 右聊天室並存（RoomsScreen + ChatScreen side-by-side）。
- expanded (≥840): 增加更多資訊欄位（群組詳情、房間資訊面板）。

---

## 2. 畫面元件階層（草案）

### 2.1 ConnectScreen（Skeleton Implemented）
```
Scaffold
  ├─ Center → Column (start alignment, no fixed width)
  │   ├─ DropdownButtonFormField<HomeserverPreset>
  │   ├─ TextField (homeserver address)
  │   ├─ TextButton (檢查連線)
  │   └─ Text (status)
  └─ footer note
```

### 2.2 LoginScreen（Skeleton Implemented）
```
Scaffold
  ├─ AppBar (title)
  └─ Center → Column
      ├─ Text (server)
      ├─ TextField (account)
      ├─ TextField (password, obscured)
      ├─ Row (login button, register button)
      └─ Text (status)
```
### 2.3 RoomsScreen（2026-11-01 重構，草案）
```
Scaffold
  ├─ AppBar（title「聊天」草案；actions: 恢復加密＝條件顯示、更多選單 popup：驗證裝置／診斷／登出）
  └─ Column
      ├─ 搜尋列 Row：TextField（加入搜尋過濾 title/id）＋ QR 鈕（與 -> AddFriendScreen）
      └─ ListView（ListTile：頭像圓＝首字、名稱／ID、預覽最近事件
           trailing＝時間（time_format）＋靜音圖示（SDK pushRuleState 非通知）
           ＋未讀徽章（SDK notificationCount，>99 顯示 99+））
  * 未讀標記只顯示既有數字；不做成癮性紅點/紅點增加機制（AGENTS.md）。
```

### 2.4 ChatScreen（2026-11-01 重構，草案；LINE 版位，待人類定稿）
```
Scaffold
  ├─ AppBar（title＝房間名；actions: 語音通話＋視訊通話（P2.15 提案，僅 direct chat 且已注入通話管理）＋搜尋＋ 菜單 IconButton
  │    → 底部選單：封鎖／檢舉（direct chat 時）、成員管理）
  └─ Column
      ├─ Expanded(ListView) — 對話流水紀錄（舊→新）
      │   ├─ 日期分隔標籤（time_format.daySeparatorLabel：今天／昨天／MM/DD）
      │   ├─ 他人訊息：左側（頭像＋sender＋time）；自己訊息：右側（time＋bubble）
      │   ├─ 已讀＝每一訊息 SDK Event.receipts（僅顯示既有資料）
      │   └─ 圖片訊息：Event.downloadAndDecryptAttachment（官方 API）
      ├─ 「滑到底部」IconButton（離開底部時顯示）
      ├─ 上傳橫幅（2.8：背景 isolate 預處理／上傳中進度）
      └─ 輸入列 Row：＋（→ 選單：照片／影片（系統多選）／檔案）／相機（image_picker）
          圖片鈕（直接開相簿多選）／輸入框（suffix 表情鈕）
          右側：有文字 → 送出（Room.sendTextEvent）／無文字 → mic（disabled 占位，語音訊息不在藍圖）
  EmojiPanel：表情＝40 個 Unicode emoji 網格草案（不複製任何平台貼圖素材）；貼圖 tab＝骨架殼（Phase 3；無資料源）。
  ⚠ LINE_ref 叉掉區域一律不實作：Services／Recommended stickers／AD banner／Select music／story ＋、圖片／貼圖上的 save-star、LINE STORE。
```

### 2.5 ContactsScreen（2026-11-01 重構，草案）
```
Scaffold
  ├─ AppBar（title「聯絡人」；actions: person_add→AddFriendScreen、settings→SettingsScreen push）
  ├─ 自己列 Row：頭像圓＋ Matrix ID
  └─ ListView
      ├─ 「好友（N）」section header + direct chat 列表（SDK `Room.directChatMatrixID`＝官方 `m.direct` 帳號資料）
      └─ 「群組（N）」section header + 普通房間列表
  * 未實作 LINE_ref 叉掉區域：Services／推薦貼圖／廣告。
```

### 2.5a SettingsScreen（2026-11-01 新增，草案；串接既有任務畫面，不新增行為）
```
Scaffold
  ├─ AppBar（title「設定」草案）
  └─ ListView（ListTile entry → push 各任務畫面）
      ├─ 裝置管理（1.14：client.getDevices／deleteDevice）
      ├─ 多裝置登入（1.13 skeleton）
      ├─ 裝置清單（1.5：deviceSource＝client.getDevices）
      ├─ 裝置驗證（1.5 skeleton；加密流程仍 100% 人工審核）
      ├─ 金鑰備份恢復（1.5 skeleton）
      ├─ 訊息搜尋（2.7）
      ├─ 推播通知權限（1.10／2.5）
      ├─ 資料匯出（2.9）
      ├─ 帳號停用（2.10）
      └─ 登出（確認對話框 → onLogout 注入，預設 SDK Client.logout）
```

### 2.5b MainShell（2026-11-01 新增，草案）
```
Scaffold
  ├─ body: IndexedStack（RoomsScreen／ContactsScreen／SettingsScreen）
  └─ bottomNavigationBar: NavigationBar（聊天／聯絡人／設定）
  * 人類決定（2026-11-01）：3 tab；不含 Wallet（無金流）、Calls（VoIP 未進藍圖，提案 2.15）。
  * medium／expanded 雙欄版面屬 Phase 7（DESIGN.md §1）。
  * P2.15（提案，2026-11-01）：殼內自建／注入 CallManager；來電時以 rootNavigator
    全螢幕 route 彈出 CallScreen（見 2.5c）。通話入口不在 tab 層（僅聊天畫面頂列）。
```

### 2.5c CallScreen（P2.15 提案，2026-11-01 新增，草案，待人類設計定稿）
```
Scaffold（黑底）
  ├─ 頂部欄：對方 ID ＋ 通話狀態文案（callStateLabel 映射，草案）
  ├─ 媒體區：
  │    遠端畫面（RTCVideoView, cover）｜音訊通話時為圖標占位
  │    本機小畫面（右上角小窗, mirror）— 僅視訊通話
  └─ 控制列：
       來電中（kIncoming＋kRinging）：[掛斷(拒接)] [接聽]
       通話中：[靜音] [攝影機開關(視訊時)] [結束通話]
  * 僅一對一（1:1 P2P）；群組通話暫緩。
  * 進入路徑：ChatScreen 頂列「語音通話／視訊通話」鈕（僅 direct chat 且通話可用時）。
  * 離開行為：kEnded 後 700ms 自動退頁；拒接立即退頁。
  * 鈴聲：無內建音檔（占位＝系統提示音＋震動）；資產授權待人類決定。
```

### 2.5d GroupCallScreen（P2.15b，2026-11-01 新增，草案，待人類設計定稿）
```
Scaffold（黑底）
  ├─ 頂部：「群組通話（N 人）」
  ├─ 未加入時：中央「加入通話」按鈕
  └─ 已加入：
       ├─ GridView（2 欄）：本機小窗 + 各參與者遠端畫面
       └─ 控制列：[靜音] [攝影機] [離開]
  * 採 MeshBackend（matrix SDK e2eeEnabled=false）；群組媒體無 E2EE，UI 需明示。
  * 進入路徑：群組聊天室頂列「群組通話」鈕（Icons.groups）或遠端發起時的全螢幕 route。
  * 離開行為：呼叫 GroupCallSession.leave() 後退頁。
  * 僅適合少人數房間；LiveKit E2EE 群組通話暫緩。
```

### 2.6 AddFriendScreen
```
Scaffold
  ├─ AppBar
  ├─ TextField (Matrix ID / invite link)
  └─ Row (invite button, scan QR button)
  └─ result message
```

### 2.7 BlockUserScreen
```
Scaffold
  ├─ AppBar
  ├─ TextField (mxid) + Block button
  └─ ListView (blocked users) + unblock action
```

### 2.8 ReportUserScreen
```
Scaffold
  ├─ AppBar
  ├─ TextField (target mxid)
  ├─ TextField (reason)
  └─ Submit button
  └─ Note (server may return 200 regardless of existence)
```

### 2.9 Device Flows (Phase 1.5)
```
Scaffold
  ├─ AppBar
  ├─ Text (Mode A / Mode B)
  ├─ Button (Start verification)
  └─ Button (Recovery key)
```

### 2.10 DeviceListingScreen
```
Scaffold
  ├─ AppBar
  └─ ListView rows: device name, id, remote logout
```

### 2.11 KeyBackupRecoveryScreen
```
Scaffold
  ├─ AppBar
  ├─ TextField (recovery key)
  └─ Recover button
```

---

## 3. 狀態與資料流（草案，非最終版）

### 3.1 認證流程（ skeleton flow）
1. App 啟動：`main()` 先載入 vodozemac，再 `_tryRestoreSession()`（方案 C）；成功則直接進 `MainShell`，否則走 Connect/Login。
2. `ConnectScreen` 檢查 homeserver → `onHandled(Uri)`。
3. `main.dart` 導向 `LoginScreen`。
4. `LoginScreen.onLoggedIn(Client)` → `MainShell(client)`（底部 3 tab）。
5. `RoomsScreen._load()`（tab1）依 SDK `onSync` → `_rooms`；設定頁登出成功後 `popUntil(first)` 回 ConnectScreen（MainShell 注入 onLogout）。
6. RoomsScreen／ContactsScreen → push `ChatScreen(room)`。
7. `ChatScreen` 訂閱 `client.onSync`（debounce 200ms）→ `_load()`；送出時 `room.sendTextEvent`（加密房由 SDK 自動加密）+ 樂觀更新。訊息載入 `Room.getTimeline()`：m.text／m.image／m.file／m.video／m.audio＋未解密事件占位。
8. 已讀顯示：`Event.receipts`（官方 receipts，僅顯示既有資料）；標記 read marker 走 `Room.setReadMarker`。
9. 表情面板與附件入口見 §2.4；上傳流程見 2.8 bugfix 紀錄。

### 3.2 錯誤處理
- 驗證失敗 → 僅顯示文字訊息 + 記錄 ；不產生紅點/asterisk.
- 網路錯誤 → retry 按鈕（UI 待人類設計）。
- 不在 SDK 以外自行做 crypto.

### 3.3 全域事件
- `Client.onSync`：驅動 `_load()` in RoomsScreen.
- 未 reads: 1.6 透過 `setReadMarker` 呼叫 SDK（async）。

---

## 4. 待人類定稿題（Phase 1.11）

- [ ] 視覺風格（配色／字型／圖示）
- [ ] 操作細節（-terminals UX）
- [ ] Confirm tab 结构（Paged vs Lists）
- [ ] 於 mobile/direct 風格統一
- [ ] E2EE UI indicating status（顯示密鑰狀態by SDK）

> 本檔案為** skeletal draft** for understanding flows; final design must be human-defined.
