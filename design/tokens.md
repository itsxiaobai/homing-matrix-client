# 全局設計 Token（人類填寫；填「—」＝沿用現狀草案）

> Agent 會把本檔翻譯成 `app/lib/ui/design_tokens.dart`（唯一樣式來源；
> 換視覺只改這個檔＋tokens.md）。每項填好一個就生效一個，不必一次填完。

## 色彩

| Token | 淺色值 | 深色值 | 用途說明 |
|---|---|---|---|
| primary | | | 主色（目前草案 #FFBD9F 種子色） |
| onPrimary | | | 主色上的文字 |
| surface | | | 頁面底色 |
| surfaceVariant | | | 泡泡／卡片底 |
| bubbleOwn | | | 自己訊息泡泡 |
| bubbleOther | | | 對方訊息泡泡 |
| textPrimary | | | 主要文字 |
| textSecondary | | | 次要文字（時間戳、寄件者） |
| error | | | 錯誤提示 |
| badgeUnread | | | 未讀徽章 |
| （自由增列） | | | |

## 字型

| Token | 值 | 用途 |
|---|---|---|
| fontFamily | | （自帶 ttf 檔名 → 放 `design/fonts/`） |
| bodySize | | 一般訊息 |
| captionSize | | 時間戳／寄件者列 |
| titleSize | | 頁面標題 |
| （自由增列） | | |

## 圓角

| Token | 值 | 用途 |
|---|---|---|
| bubbleRadius | | 訊息泡泡（例：16） |
| cardRadius | | 卡片／bottom sheet（例：12） |
| buttonRadius | | 按鈕（例：圓形／8／24） |
| avatarRadius | | 頭像圓 |

## 間距（相對單位或 dp 皆可，Agent 會做相對約束、不寫死寬度）

| Token | 值 | 用途 |
|---|---|---|
| pagePaddingH | | 頁面左右 |
| bubbleGap | | 泡泡間垂直 |
| chipGap | | 表情反應 chips 間 |
| toolbarHeight | | 底部輸入列高 |

## 圖示

| 位置 | 圖示（內建 Material 圖示名或你指定的 SVG 檔） |
|---|---|
| 送出 | Icons.send □ |
| 附加 | |
| 相機 | |
| 下載 | |
| 分享 | |
| 回覆 | |
| （自由增列） | |

## 動效（選填；不填＝無動效直接套用）

| Token | 值 | 用途 |
|---|---|---|
| zoomCurve | | 雙擊放大曲線（例：easeOut 200ms） |
| swipeReplyAnim | | 滑動回覆回彈 |
| sheetAnim | | bottom sheet |

## 其他全局

| 項目 | 值 |
|---|---|
| 深色模式 | 支援深＋淺 □／僅淺色 □ |
| 種子色 | （Material ColorScheme seed） |
