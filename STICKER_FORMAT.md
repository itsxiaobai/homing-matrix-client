# STICKER_FORMAT.md — Homing 貼圖包格式規格 v1

> **狀態：v1.0 草案（內容依藍圖 `agent_v1_3.md` §十一；凍結與定稿由人類決定 —— 藍圖 Phase 3.1）。**
> **授權**：本規格建議以 **CC0 或 MIT** 釋出，讓他人可自由實作（藍圖 §七、§十一）。
> 規格本身與「Homing 客戶端」是兩件事：若另附使用 matrix SDK 的匯入工具，該工具須為 AGPL。

**版本**：1.0（尚未凍結）
**相容性**：Matrix v1.19 的 image packs（MSC2545）
**規格基準日**：2026-10-27（藍圖 §十五）

---

## 1. 目的

定義一種標準化的貼圖包格式，使創作者可以在自己的平台上發布貼圖，使用者透過 Homing 或其他支援 image packs 的客戶端匯入使用。

## 2. 目錄結構

```text
catpack.zip
├── manifest.json          （必要）
├── stickers/
│   ├── 001.png
│   ├── 002.png
│   └── ...
├── thumbnail.png          （選用，包裝縮圖；唯一允許在 stickers/ 之外的圖片）
└── LICENSE.txt            （選用；唯一允許的 .txt 檔）
```

**說明**：
- 貼圖圖片必須放在 `stickers/` 子目錄；僅 `thumbnail.png`／`thumbnail.webp` 例外
- 不得使用絕對路徑或 `..`（防止 zip slip），不得含符號連結
- 僅允許 PNG 或 WebP **靜態**圖片（含 APNG、動畫 WebP 一律拒收）
- 不支援 GIF、SVG（v1 版本）
- 規格 v1.18 已新增 `m.sticker` 的 `is_animated` 欄位（MSC4230），日後若支援動態貼圖可使用，v1 不納入

## 3. manifest.json 規格

```json
{
  "spec_version": "1.0",
  "id": "tw.example.catpack",
  "name": "貓咪日常",
  "author": "範例創作者",
  "description": "20 張手繪貓咪貼圖",
  "license": "CC-BY-4.0",
  "usage": ["sticker"],
  "attribution": "https://example.tw/catpack",
  "stickers": [
    {
      "shortcode": "cat_happy",
      "name": "開心的貓",
      "keywords": ["開心", "happy", "貓"],
      "file": "stickers/001.png",
      "body": "😺 開心"
    },
    { "shortcode": "cat_sad", "file": "stickers/002.png", "body": "😿 難過" }
  ],
  "thumbnail": "thumbnail.png"
}
```

**欄位定義**：

| 欄位 | 必要/選用 | 說明 |
|---|---|---|
| `spec_version` | **必要** | 格式版本，固定為 `"1.0"` |
| `id` | **必要** | 貼圖包全域唯一識別碼，建議用反向網域名稱或 UUID；將作為 state_key，長度須 ≤ 255 bytes |
| `name` | **必要** | 貼圖包顯示名稱 |
| `author` | **必要** | 創作者名稱 |
| `description` | 選用 | 貼圖包描述（僅供 Homing 本機顯示，不寫入 Matrix 事件） |
| `license` | **必要** | SPDX 識別碼（如 CC-BY-4.0、MIT、AGPL-3.0）或 `"proprietary"` |
| `usage` | 選用 | 陣列，值為 `"sticker"`、`"emoticon"`；空缺＝兩者皆可（與 Matrix 規格一致）。**沒有** `"both"` |
| `attribution` | **必要** | 創作者網址或出處 |
| `stickers` | **必要** | 貼圖列表，陣列格式 |
| `thumbnail` | 選用 | 縮圖檔案路徑 |

**每個 sticker 物件**：

| 欄位 | 必要/選用 | 說明 |
|---|---|---|
| `shortcode` | **必要** | 包內唯一，格式 `^[a-z0-9_-]{1,32}$`（Homing 自訂限制）；對應 Matrix `images` 物件的 key |
| `file` | **必要** | 貼圖檔案相對路徑 |
| `body` | 選用 | 發送時的文字內容（alt text）；空缺時 Matrix 規格預設為 shortcode |
| `name` | 選用 | **貼圖名稱**（顯示用；缺漏＝shortcode）——第四十二批新增 |
| `keywords` | 選用 | **搜尋關鍵字**（字串陣列）——第四十二批新增；Homing 的貼圖建議功能**優先**比對此清單（檔名 token 為備援） |

> **為什麼加 `name` / `keywords`？**（人類 2026-11-15 的多裝置同步構想）
> 未來的同步格式是「**多份圖檔 ＋ 一份 json**」，json 內填入**貼圖名稱、搜尋關鍵字、
> 檔名**。本規格的 `name`／`keywords`／`file` 三欄即對應該 json 的三個欄位：
> `name`＝名稱、`keywords`＝搜尋關鍵字、`file`＝檔名。

**`license` 欄位用途說明**：
Homing 不以此欄位做任何顯示或限制決策，僅供創作者聲明與匯入端標示之用；值為 `"proprietary"` 時代表創作者保留全部權利（例如付費貼圖），Homing 不驗證、不執行此宣告。

## 4. 硬性限制

| 項目 | 建議值（超過則警告） | 硬上限（超過則拒收） |
|---|---|---|
| 圖片格式 | PNG 或 WebP（靜態） | 其他格式、APNG、動畫 WebP 拒收 |
| 長邊 | 512–1024 px | > 2048 px |
| 總像素 | ≤ 1,048,576（1024×1024） | > 4,194,304（2048×2048） |
| 單檔大小 | ≤ 512 KB | > 2 MB |
| 每包張數 | ≤ 120 | > 200 |
| 解壓後總大小 | — | > 50 MB |
| zip 內檔案數 | — | > 210 |
| 單檔壓縮比 | — | > 100:1（初始值，待實測調整） |
| 縮圖大小 | ≤ 128 KB、長邊 ≤ 512 px | > 512 KB |
| 路徑安全性 | — | 絕對路徑、`..`、符號連結 → 立即中止並報錯 |
| 檔案類型白名單 | — | 僅 `.png`、`.webp`、`manifest.json`、`LICENSE.txt`；其他拒收 |
| 副檔名與內容 | — | 檔頭（magic bytes）須與副檔名一致，否則拒收 |

> 張數 × 單檔上限（200 × 2 MB）超過 50 MB，實際上限由「解壓後總大小」決定。

**安全驗證要求**：
- **串流檢查**：逐一讀取 zip entry，累計大小與檔案數超限即中止，不先整包解壓
- **解碼前讀檔頭預檢**：PNG 的 IHDR（byte 16–23）、WebP 的 header 需在配置任何像素緩衝區前讀出宣告的尺寸，並拒絕超限者
- **格式白名單**：見上表

## 5. 匯入流程

1. **選檔與串流檢查**：逐 entry 檢查路徑、檔案數、累計大小、壓縮比
2. **驗證 manifest**：存在、有效 JSON、欄位符合 §3、`shortcode` 包內唯一
3. **圖片檔頭預檢**：解碼前確認格式、尺寸、像素數；通過後才解碼
4. **上傳**：將圖片逐一上傳至使用者的 homeserver，取得 `mxc://` URI
5. **建立 pack 事件**：依 §7 寫入 `m.room.image_pack` 房間狀態事件
6. **啟用**：將該房間的 pack 記錄於 `m.image_pack.rooms` account data
7. **清理**：刪除臨時檔案

## 6. Homing 責任限制

- **Homing 不託管貼圖圖片**——圖片上傳至使用者的 homeserver
- **Homing 不審核貼圖內容**——使用者自行承擔來源風險
- **Homing 不處理金流**——付費貼圖由創作者在其平台自理，Homing 不介入
- **Homing 不建貼圖目錄**——貼圖靠創作者自行散布與房間分享

**免責聲明**：創作者發布的貼圖內容如有侵權或違法問題，由創作者自行承擔責任，Homing 不承擔任何連帶責任。（此為一般性聲明，**不構成法律意見**，是否足夠待專業諮詢。）

**附帶揭露**：貼圖圖片以明文形式儲存於 homeserver，即使房間啟用 E2EE，貼圖圖片仍可被 homeserver 管理者讀取；另外任何持有 mxc 連結且通過該伺服器認證者可下載。

## 7. Matrix 事件對映（以 v1.19 穩定規格為準）

穩定規格定義兩個項目：`m.room.image_pack`（**房間狀態事件**，state_key 為貼圖包識別碼）與 `m.image_pack.rooms`（**account data**，記錄使用者全域啟用哪些房間的 pack）。事件內容：`images`（shortcode → `{url, body?, info?}`）與 `pack`（`display_name?`、`avatar_url?`、`usage?`、`attribution?`）。

```text
manifest.id                  → m.room.image_pack 的 state_key
manifest.name                → pack.display_name
"{author} — {attribution}"   → pack.attribution
manifest.usage               → pack.usage（空缺則省略）
manifest.thumbnail           → 上傳後的 mxc:// → pack.avatar_url

stickers[].shortcode         → images 物件的 key
stickers[].file              → 上傳後的 mxc:// → images[shortcode].url
stickers[].body              → images[shortcode].body
圖片實際屬性                  → images[shortcode].info（寬、高、mimetype、size）

manifest.description / license → 不寫入事件（規格無對應欄位）
```

**個人貼圖庫（待人工決定）**：依 Ruma 對 v1.19 的型別定義，穩定規格只有「房間狀態」型的 pack，**未見** MSC 草案中曾有的「個人 account data pack」。因此 Homing 需決定：建立一個僅自己所在的私人「貼圖庫」房間存放所有 pack，或沿用既有房間。此點 ⚠️須對照規格原文再定案。注意：房間狀態事件**不加密**，pack 定義為明文。

發送貼圖時，使用 `m.sticker` 事件：

```text
body     = images[shortcode].body（預設為 shortcode）
url      = mxc://（上傳後取得）
info     = ImageInfo（含 mimetype、寬高、size；is_animated 選用，v1 靜態可省略）
```

## 8. 相容性注意事項

- 本規格以 **Matrix v1.19** 的 image packs 為基準（2026-07-08 發布）
- 其他客戶端是否支援（FluffyChat、Cinny、Nheko 等）—— **2026-11-16 已查證（GitHub 程式碼搜尋，`image_pack` 關鍵字）**：fluffychat／cinny／nheko／matrix-rust-sdk **皆 0 命中**（對照組：`sticker` 在 fluffychat 82 命中 → 搜尋機制正常）→ **這些客戶端／SDK 尚未實作 image packs**。文件不得宣稱「皆支援」；實作細節仍待逐一實測。
- **規格的「個人 account data」是清單，不是內容**（2026-11-16 查證 `spec.matrix.org/v1.19/client-server-api/`）：規格定義 **User image packs** → 事件型別 **`m.image_pack.rooms`（account data）**，內容 `{rooms: {<room_id>: {<state_key>: {}}}}`＝「使用者全域啟用了哪些房間的貼圖包」；**貼圖內容本身仍在房間 state 事件 `m.room.image_pack`**。
  → 對 Homing 3.11 決策的意義：**「專用私密房間 ＋ 房間 state `m.room.image_pack`」的作法與規格一致**（內容在房間、用 `m.image_pack.rooms` 記錄個人啟用清單屬規格可選的輔助）。
  → 規格原文亦提醒：用戶可能不是被引用房間的成員 → 該情況下**無法取得該房貼圖圖片**（Homing 的貼圖庫房間由使用者自己建立，無此問題）。
- **舊名稱**：規格定案前曾使用 `im.ponies.room_emotes`、`im.ponies.emote_rooms`、`im.ponies.user_emotes`。部分 SDK／客戶端可能仍使用舊名，Phase 3.10 須檢查並做相容
  - **已查證（2026-11-14，本機 pub cache `matrix-14.2.0` 原始碼）**：SDK 14.2.0 的 image pack 擴充（`lib/src/utils/image_pack_extension.dart`）**只讀舊草案名** `im.ponies.user_emotes`／`im.ponies.emote_rooms`／`im.ponies.room_emotes`；其內容模型（`ImagePackContent`：`images`（url/body/info/usage）＋ `pack`（display_name/avatar_url/usage/attribution））與本規格 §7 欄位一致。寫入 v1.19 穩定名可用 SDK 官方 `Client.setRoomStateWithKey(roomId, eventType, stateKey, body)`（`matrix_api_lite/generated/api.dart`）與 `Client.setAccountData(type, body)`，**事件型別字串由 App 端指定**。
- **排序限制**：`images` 為 JSON 物件，Matrix 規格不保證順序；`stickers[]` 陣列的順序僅在 Homing 內有效
- **E2EE 限制**：貼圖圖片本身未加密，這是目前使用方式的限制，非 Homing 實作問題

## 9. 參考資源

- [Matrix v1.19 Changelog（image packs 納入）](https://spec.matrix.org/v1.19/changelog/v1.19/)
- [Matrix v1.18 Changelog（MSC4230 is_animated 等）](https://spec.matrix.org/v1.19/changelog/v1.18/)
- [MSC2545 提案](https://github.com/matrix-org/matrix-spec-proposals/pull/2545)
- [Ruma Events — image_pack.rs（v1.19 型別）](https://docs.rs/ruma-events/0.35.0/src/ruma_events/room/image_pack.rs.html)
