# THEME_FORMAT.md — Homing 主題包格式（v1 草案 · 待人類審閱）

> **狀態**：v1 草案（人類 2026-11-15 指示「你出草案我審」）；**規格凍結與最終介面由人類定稿**。
> 本檔不含法律意見；字型與圖示的授權問題標為 ⚠️待查證。
> 對應藍圖 Phase（主題包 zip 規格＝§九第 13 項；貼圖包格式＝`STICKER_FORMAT.md`）。

---

## 0. 設計原則（與貼圖包一致）

1. **一包一主題**：zip 內一個 `theme.json` ＋ 資產檔。
2. **本機優先、跨裝置可選**：主題匯入後存本機；是否同步到「貼圖庫房間」待 3.11 決定後一併處理。
3. **不追隨 LINE**：主題結構自創；LINE 的主題商店、主題動態字、Premium 主題皆**不做**。
4. **安全驗證與貼圖包同級**：中央目錄掃描、路徑安全、白名單、檔頭預檢、大小上限。

---

## 1. zip 結構

```text
theme-pack.zip
├── theme.json            （必要）
├── wallpaper/
│   ├── light.jpg         （可選；淺色模式桌布）
│   └── dark.jpg          （可選；深色模式桌布）
├── fonts/
│   ├── regular.ttf       （可選；⚠️字型授權待查證）
│   └── bold.ttf          （可選）
├── icons/                （選用；v1 可放自訂圖示字型 .ttf）
│   └── myicons.ttf
└── LICENSE.txt           （可選；權利宣告）
```

**規則**
- 圖片僅 `wallpaper/` 與 `icons/` 內；字型僅 `fonts/` 內；根目錄僅 `theme.json`、`LICENSE.txt`。
- 桌布：`.jpg`／`.png`／`.webp`；**不含 GIF／APNG**（避免動畫桌布耗電與解析風險）。
- 字型：`.ttf`／`.otf`。
- 圖示：v1 支援**兩條路線**（見 §2 `icons`）：①Material 圖示名稱（零新依賴）②自訂圖示字型 `.ttf`（需隨包提供；⚠️授權待查證）。`.svg` 不再列為 v1 可用格式。

## 2. `theme.json`

```json
{
  "spec_version": "1.0",
  "id": "tw.example.dusk",
  "name": "暮色",
  "author": "主題創作者",
  "license": "CC-BY-4.0",
  "attribution": "https://example.tw/dusk",
  "description": "暖色暮色主題（桌布＋配色）",
  "colors": {
    "seed": "#FFBD9F",
    "light_surface": "#FFFFFF",
    "dark_surface": "#000000",
    "chat_bubble_light": "#FFE9DE",
    "chat_bubble_dark": "#3A3A3A"
  },
  "assets": {
    "wallpaper_light": "wallpaper/light.jpg",
    "wallpaper_dark": "wallpaper/dark.jpg",
    "font_regular": "fonts/regular.ttf",
    "font_bold": "fonts/bold.ttf"
  },
  "icons": {
    "chat": "chat_bubble_outline",
    "call": "phone",
    "sticker": { "font": "myicons.ttf", "codepoint": "e001" }
  }
}
```

| 欄位 | 必要/選用 | 說明 |
|---|---|---|
| `spec_version` | **必要** | 固定 `"1.0"` |
| `id` | **必要** | 全域唯一（反向網域名或 UUID），長度 ≤255 bytes |
| `name` | **必要** | 顯示名稱 |
| `author` | **必要** | 創作者名稱 |
| `license` | **必要** | SPDX 識別碼或 `"proprietary"`（Homing 不驗證、不執行） |
| `attribution` | **必要** | 出處連結 |
| `description` | 選用 | 說明 |
| `colors` | 選用 | 配色（見下表） |
| `assets` | 選用 | 資產路徑（相對於 zip 根） |
| `icons` | 選用 | **第五十七批：可實際替換圖示**（詳下） |

**`icons` 欄位（第五十七批・圖示變數化）**

- key 必須是合法槽位名（**第五十八批「全部替換」後＝130 個 Material 圖示名稱全數可覆換**，
  例如 `chat_bubble_outline`／`arrow_back`／`add`／`send`…；完整清單見
  `app/lib/ui/app_icons_generated.dart` 的 `kAllIconSlotNames`）；
  其他 key → **驗證失敗**（避免「寫了卻沒作用」）。
- value 兩種格式：
  1. **Material 圖示名稱**（字串）：例如 `"chat": "chat_bubble_outline"`。
     可用名稱限 `AppIcons.kMaterialIconByName` 對照表（本專案實際用到者）；
     **查無 → 驗證失敗**（不猜、不靜默忽略）。零新依賴。
  2. **自訂圖示字型**：`{"font": "myicons.ttf", "codepoint": "e001"}`。
     `font` 必須是包內 `fonts/` 下的 `.ttf`（驗證會檢查檔案存在）；
     `codepoint` 為十六進位碼位。字型需由 App 以官方 `FontLoader` 載入。
     ⚠️ 字型授權由創作者負責，Homing 不審核。
- 套用主題時：先清掉前一個主題的覆寫 → 即使新主題沒有 `icons` 也**還原預設圖示**
  （避免換主題後殘留舊圖示）。
- 目前**全部 130 個圖示**皆走 `AppIcons`/`AllIcons` 槽位（第五十八批全數替換）→
  主題包可完整替換 App 內所有圖示。

**`colors` 欄位**

| 鍵 | 格式 | 對應 App 用途（`UI_SPEC.md` token） |
|---|---|---|
| `seed` | `#RRGGBB` | 主題種子色（Material `ColorScheme.fromSeed`） |
| `light_surface` | `#RRGGBB` | 淺色背景 |
| `dark_surface` | `#RRGGBB` | 深色背景 |
| `chat_bubble_light` | `#RRGGBB` | 淺色自己泡泡 |
| `chat_bubble_dark` | `#RRGGBB` | 深色自己泡泡 |

> 全部為**選用**：缺值則沿用 App 預設（不覆蓋使用者的既有偏好）。

## 3. 硬性限制

| 項目 | 建議值 | 硬上限（超過則拒收） |
|---|---|---|
| 單檔大小（桌布） | ≤ 4 MB | > 8 MB |
| 單檔大小（字型） | ≤ 2 MB | > 10 MB |
| zip 內檔案數 | ≤ 40 | > 100 |
| 解壓後總大小 | ≤ 40 MB | > 80 MB |
| 單檔壓縮比 | ≤ 50:1 | > 100:1 |
| 桌布長邊 | 1080–2560 px | > 4096 px |
| 桌布像素總數 | ≤ 4,194,304 | > 8,388,608 |
| 色彩格式 | `#RRGGBB` | 其他（`#AARRGGBB`／命名色）→ 拒收 |

## 4. 匯入流程

1. **中央目錄掃描**（不解壓）：檔案數、單檔大小、總大小、壓縮比。
2. **路徑與白名單**：絕對路徑／`..`／符號連結 → 中止；副檔名白名單；根目錄只允許 `theme.json`／`LICENSE.txt`。
3. **`theme.json` 驗證**：`spec_version`、必填欄位、`colors` 為 `#RRGGBB`、資產路徑存在且在允許目錄內。
4. **桌布檔頭預檢**：讀 PNG IHDR／WebP header 取尺寸 → 驗長邊與像素；**不做 GIF／APNG**。
5. **落地**：桌布與字型複製到 App 私有目錄（`path_provider` documents／themes／<id>／）。
6. **登錄**：寫入 `themes`（名稱／種子色／桌布）＋ 另存 `theme.json` 全文（供日後同步）。
7. **套用**（使用者手動）：種子色即時生效；桌布下次進入聊天室生效（既有行為）。

## 5. 與貼圖包的差異

| | 貼圖包 | 主題包 |
|---|---|---|
| 中繼檔 | `manifest.json` | `theme.json` |
| 資產 | 貼圖圖片（`stickers/`） | 桌布／字型／圖示 |
| 事件 | `m.room.image_pack`（已實作） | **未定**（等 3.11 貼圖庫房間決策後一併處理） |
| 關鍵字 | `keywords`（搜尋建議） | 無 |

## 6. 停機與待查證

- **字型打包**：字型檔的商用授權範圍 ⚠️待查證（v1 匯入支援，但發布時需標示「字型授權由創作者負責」）。
- **圖示套用**：Android 動態 icon 受系統限制 → v1 只索引不套用。
- **主題同步**：待 3.11 決定（可寫入同一「貼圖庫房間」或另立主機制）。
- **商店流傳／簽章**：不做（藍圖 §二：貼圖商店 ❌ 不做）。
- 本檔為**草案**；凍結前 Agent 只實作「匯入＋套用」路徑，不改介面定稿。
