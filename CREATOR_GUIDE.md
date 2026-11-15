# CREATOR_GUIDE.md — 創作者指南：Homing 貼圖包與主題包

> **狀態**：草案（對應 `STICKER_FORMAT.md` v1 與 `THEME_FORMAT.md` v1，兩者**待人類凍結**）。
> 用途：讓創作者在**自己的平台**發布貼圖包／主題包，Homing 只做「匯入與顯示」——
> **Homing 不託管、不索引、不審核、不販售**任何內容（藍圖 §十一 §6）。

## 一、快速上手（貼圖包）

1. 準備資料夾：

```text
catpack.zip
├── manifest.json
├── stickers/
│   ├── 001.png
│   └── 002.png
├── thumbnail.png      （選用）
└── LICENSE.txt        （選用）
```

2. `manifest.json`（完整欄位見 `STICKER_FORMAT.md` §2–3）：

```json
{
  "spec_version": "1.0",
  "id": "tw.example.catpack",
  "name": "貓咪日常",
  "author": "範例創作者",
  "license": "CC-BY-4.0",
  "attribution": "https://example.tw/catpack",
  "usage": ["sticker"],
  "stickers": [
    {
      "shortcode": "cat_happy",
      "name": "開心的貓",
      "keywords": ["開心", "happy", "貓"],
      "file": "stickers/001.png",
      "body": "😺 開心"
    }
  ]
}
```

3. **打包成 zip**（根目錄直接放 `manifest.json`，不要多包一層資料夾）。
4. **本機驗證**（不用裝 App）：

```bash
cd app
dart run tool/verify_sticker_pack.dart /path/to/catpack.zip
```

輸出範例：

```text
✓ /path/to/catpack.zip
  貼圖包：貓咪日常（tw.example.catpack）
  創作者：範例創作者｜授權：CC-BY-4.0
  張數：1
    - cat_happy  512×512  image/png  😺 開心
```

5. **匯入 Homing**：設定 → 外觀設定 → 貼圖 →「匯入貼圖包（zip）」。
   Homing 會在匯入前做安全驗證（路徑穿越／解壓炸彈／白名單／動圖／尺寸），
   通過後把圖片上傳到**使用者自己的 homeserver**（檔案不上傳到 Homing 的伺服器）。
6. **跨裝置共用**：同一個貼圖包可在「同步貼圖庫（跨裝置）」寫進你的**貼圖庫私密房間**
   （其他裝置即可取得同一份貼圖庫）。

## 二、關鍵字（讓貼圖能被建議）

Homing 在你輸入文字時，會在上方顯示建議貼圖。比對順序：

1. **創作者指定的 `keywords`**（建議務必填，能含中文與英文）→ 例：`["開心","happy"]`
2. `name`（貼圖名稱）與 `shortcode` 的字元

沒有 `keywords` 時仍可用檔名／shortcode 比對（例如 `cat_happy` 會被 `cat` 命中）。

## 三、限制（貼圖包）

| 項目 | 建議 | 硬上限（超過拒收） |
|---|---|---|
| 圖片格式 | PNG／WebP（**靜態**） | 其他格式、APNG、動畫 WebP 拒收 |
| 圖片長邊 | 512–1024 px | > 2048 px |
| 單檔大小 | ≤ 512 KB | > 2 MB |
| 每包張數 | ≤ 120 | > 200 |
| 解壓後總大小 | — | > 50 MB |
| zip 內檔案數 | — | > 210 |
| 單檔壓縮比 | — | > 100:1 |

## 四、主題包（v1 草案）

結構、欄位與限制見 `THEME_FORMAT.md`；驗證方式同樣是
`dart run tool/verify_sticker_pack.dart`（主題包用同一支工具的驗證邏輯，
或由 Homing 內「匯入主題包（zip）」在匯入前驗證）。

主題包含：桌布（淺／深）、配色（`#RRGGBB`）、字型（`fonts/*.ttf|otf`）與圖示索引（v1 不套用）。

## 五、權利與免責

- 貼圖內容的著作權與商用授權**由創作者負責**；`license` 欄位只是**聲明**，Homing **不驗證、不執行**。
- `attribution` 會被寫入 Matrix 事件（`pack.attribution`）→ 建議填可公開的出處連結。
- Homing 不會出現在貼圖商店、推薦或搜尋結果中（藍圖：貼圖商店 ❌ 不做）；
  發現途徑＝你自己的平台、房間分享、或使用者自行匯入。
