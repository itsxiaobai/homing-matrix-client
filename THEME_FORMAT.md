# THEME_FORMAT.md — Homing 主題包格式（v0 草案）

> 草稿，須人工審閱，非法律意見。
> 批次十二①（人類指示「all」，2026-11-07）。本檔描述 Homing 自訂主題的資料格式與
> 打包格式草案。最終介面與規格由人類定稿；本文僅為程式目前實作的最小說明。

## 現狀（v0 已實作）

Homing 的「主題」v0＝**兩個分項設定值的命名組合**，全部存在本機
`app_settings.db`（sqflite），**不送任何伺服器**：

| 分項 | 儲存位置 | 值格式 |
|---|---|---|
| 主題名稱 | `themes.name` | 文字 |
| 種子色 | `themes.seed` | `RRGGBB` 六碼十六進位（不含 `#`；可空） |
| 全域聊天室桌布 | `themes.wallpaper` | 圖片檔的本機絕對路徑（可空）；套用時寫入 kv `chat_wallpaper` |

資料表：

```sql
CREATE TABLE themes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  seed TEXT,
  wallpaper TEXT,
  created_at INTEGER NOT NULL   -- epoch ms
);
```

套用行為（appearance_screen）：

1. 寫 kv `selected_theme_id`（記錄「目前選中」；未套用任何主題時無此 key）。
2. 主題帶種子色 → 寫 kv `theme_seed_color`＋`ringSeedColor` notifier 即時生效。
3. 主題帶桌布 → 寫 kv `chat_wallpaper`（全域聊天室背景；per-room `room_bg`
   仍優先）。**主題無桌布時不清除現有桌布**（v0 行為披露）。
4. 已開啟中的聊天室畫面不會即時換桌布（重新進入後生效）；種子色即時生效。

## 計畫中的 zip 打包格式（未實作——需 `archive` 依賴，待人類批准）

與既有貼圖包相同思路：zip 內放中繼資料檔＋資源檔（下列結構為**本專案自訂草案**，
未參考任何既有套件格式）：

```
ring-theme.zip
├── theme.json        # meta ＋分項
├── wallpaper.png     # 桌布（可選）
└── （未來：fonts/、icons/ —— 字型授權待查證；圖示受 Android 限制 v0 不做）
```

`theme.json` 草案：

```json
{
  "format": "ring-theme",
  "version": 1,
  "name": "使用者可見主題名",
  "seed": "FFBD9F"
}
```

- `wallpaper.png`（或 .jpg）存在 → 匯入時複製到 App 私有目錄，路徑寫入 `themes.wallpaper`。
- 讀 zip 需要 `archive`（或 `zip` / `flutter_archive`）套件 → **pubspec 變更＝停工等批准**，
  v0 因此先把「分項選取」路徑做完。
- 圖標（app icon）替換：Android 動態 icon 有系統限制（需 activity-alias／Ukraine
  store 審查問題），v0 不做。

## 停機事項（AGENTS.md）

- 新增 `archive` 依賴＝碰 pubspec，需人類明確批准才動工。
- 字型打包＝字型檔授權需查證，v0 不做。
- 本檔為格式草案；正式規格待人類定稿（是否支援第三方商店流傳、簽章、版本相容）。
