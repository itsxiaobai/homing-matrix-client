# FCM_SETUP.md — Homing 的 FCM 設定步驟（照著做即可）

> 狀態：**FCM 預設關閉**（2026-11-19 人類指示），要在 App 內「設定 → 通知設定 → 使用 FCM 推播」主動開啟才會用。
> 你已決定 Android 包名先用 `io.github.itsxiaobai`（日後改包名要重做第 3 步）。
> 本檔是操作備註，不是法律意見；Firebase 帳號需你自己的 Google 帳號，Agent 不能代辦。

---

## 你會不會需要 FCM？先確認

- 目前推播通道：**UnifiedPush（已通）→ FCM（預設關）→ App 直接收**。
- 一般使用者手機**沒有裝 UnifiedPush 接收端**時，才需要 FCM。若你只是自己測且手機已裝接收端，可以**先不設定 FCM**，推播已經會動。
- FCM 要能真的收到通知，需要兩件事都完成：**①Firebase 專案憑證 ②可用的推播閘道**。只做①不夠（見下方「殘酷現實」）。

---

## 步驟 1：建立 Firebase 專案（你的 Google 帳號）

1. 打開 <https://console.firebase.google.com/> → 登入你的 Google 帳號。
2. 點 **「新增專案」／「Add project」**。
3. 專案名稱填一個你認得的，例如 `homing-push`（名稱可隨意，之後可改）。
4. Google Analytics：**可以選「不要啟用」**（Homing 不需要，避免多設定）。
5. 建立完成 → 進入專案首頁。

## 步驟 2：加入 Android App

1. 專案首頁點 Android 機器人圖示 **「將 Firebase 加入 Android 應用程式」**。
2. **Android 套件名稱**填（照你選的現況）：

   ```text
   io.github.itsxiaobai
   ```

   ⚠️ 必須與 `app/android/app/build.gradle.kts` 的 `applicationId` 一模一樣；大小寫不同也不行。
3. 暱稱可填 `Homing`（選填）。
4. 點 **「註冊應用程式」／Register app**。

## 步驟 3：取得google-services.json（二選一，建議①）

### ① 用 google-services.json（最簡單，不用 dart-define）

1. 註冊完成後畫面會出現 **Download google-services.json** → 下載。
2. 把檔案放到：`app/android/app/google-services.json`
3. **不要 commit**（加到 `.gitignore`，目前已忽略是否符合要檢查）。
4. 打包時 App 自己會讀到；不用在指令帶任何 FCM_* 參數。

### ② 用 dart-define（不放檔案進磁碟，CI 用這個）

在 Firebase 主控台：**專案設定 ⚙ → 您的應用程式 → Android app → 「Firebase SDK 設定檔／google-services.json」** 或用畫面顯示的 snippets，抄出這四個值：

| 要抄的值 | Firebase 欄位 | 範例（非真實值） |
|---|---|---|
| `FCM_PROJECT_ID` | `project_id` | `homing-push-12345` |
| `FCM_API_KEY` | `api_key` | `AIzaSy...` |
| `FCM_APP_ID` | `mobilesdk_app_id` | `1:123456789012:android:abcdef` |
| `FCM_SENDER_ID` | `project_number` | `123456789012` |

本機 build 指令就變成：

```bash
flutter build apk --release \
  --dart-define=FCM_PROJECT_ID="..." \
  --dart-define=FCM_API_KEY="..." \
  --dart-define=FCM_APP_ID="..." \
  --dart-define=FCM_SENDER_ID="..."
```

CI 則是把這四個值放進 homing-tmp 的 **Settings → Secrets and variables → Actions**，名稱同樣是 `FCM_PROJECT_ID`／`FCM_API_KEY`／`FCM_APP_ID`／`FCM_SENDER_ID`。

## 步驟 4：殘酷現實 —— 你還需要「推播閘道」

就算上面都做對，Homing 目前**仍送不到推播**，原因（2026-11-16 實測，見 `PROGRESS.md` 第五十二批）：

- Google 舊端點 `https://fcm.googleapis.com/fcm/send` → **HTTP 404**（已停用）。
- FCM HTTP v1 存在，但需要 service account 的短效 OAuth2 token；Matrix `http` pusher 只能帶**靜態** `data.auth`，兩者對不起來。

所以必須再給 Homing 一個可用的閘道 URL：

```bash
--dart-define=FCM_GATEWAY_URL=https://<可用的轉送端>/push
```

或 CI secrets 加一筆 `FCM_GATEWAY_URL`。

三種現實選擇：

| 方案 | 做法 | 成本／風險 |
|---|---|---|
| A. 不設定 FCM（建議先这样） | 維持現況：UP 已通、FCM 預設關 | 沒有 Google 帳號／閘道問題 |
| B. 用別人的 Matrix 相容 FCM 閘道 | 填入你信任的第三方 URL | ⚠️ 第三方信譽需你自行評估；可能收費 |
| C. 自架 v1 轉送端 | 你的 service account＋一支小服務轉送 | 需長期維運，與藍圖「不引入需維運系統」衝突，需你例外授權 |

> 程式目前在 **沒有有效閘道**（沿用舊端點）時，會直接略過 FCM、退回 UP／App 直接收，
> 所以你就算填了 Firebase 憑證但沒填 gateway，也不會出錯，只是 FCM 不會被啟用。

## 步驟 5：在 App 內啟用

1. 打開 App → **設定 → 通知設定**（或首頁頂列通知 icon）。
2. 开启 **「使用 FCM 推播」**（預設關閉）。
3. 房间設定 → 通知設定總開關也要開（Android 13+ 還要允許系統通知權限）。
4. 讓朋友從另一台發訊息測試「App 被殺掉仍能收到」。

## 日後改包名怎麼辦

你日後若真的把 applicationId 改成 `io.github.itsxiaobai.homing`：

1. Firebase 主控台 **同一個專案** → 新增第二個 Android app，套件名填新值。
2. 重新下載新的 `google-services.json` 覆蓋舊檔（或更新四個 dart-define 值）。
3. 舊 pusher 要用**舊 app_id** 清掉（程式登出會清；若已換機須在提示下處理）。

---

## 給 Agent 的備註（你不需做）

- 本機不編譯：設定完成後由你那台跑 `flutter pub get`／`build apk`，或 CI check。
- 憑證別貼到公開頻道；若要我幫你把值放進 CI secrets，請用安全方式提供（或你自己填）。
