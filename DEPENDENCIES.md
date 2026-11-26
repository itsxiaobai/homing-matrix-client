# DEPENDENCIES.md — 依賴清單與授權

> **草稿，須人工審閱，非法律意見。**

## 依賴清單（SPDX 授權）

| 套件 | 版本（2026-11-19 同步） | SPDX License | 備註 |
|---|---|---|---|
| `flutter_svg` | ^2.2.0（第七十批 c） | **BSD-3-Clause** | 直接依賴（Compound Icons SVG 渲染）。**經人類批准 2026-11-19**（option 1）。配套素材 `element-hq/compound-design-tokens` 為 **AGPL-3.0**（與 Homing 相容），置 `app/assets/icons/compound/`（50 個 SVG） |
| `record` | ^6.1.2（第七十批 d） | **BSD-3-Clause** | 直接依賴（語音訊息錄音；Android RECORD_AUDIO 已在 manifest）。**經人類批准 2026-11-19** |
| `just_audio` | ^0.9.41（第七十批 d） | **BSD-3-Clause** | 直接依賴（語音訊息播放）。**經人類批准 2026-11-19** |
| `permission_handler` | ^11.4.0（第七十批 d） | **BSD-3-Clause** | 直接依賴（錄音權限請求）。**經人類批准 2026-11-19** |
| `intl` | 由 Flutter 3.47.9 鎖定（pubspec `any`） | **BSD-3-Clause** | 直接依賴（**第五十七批 i18n 全量遷移，經人類批准 2026-11-17「全部，是」**）：`flutter_localizations`（Flutter SDK 內建，非 pub 套件）所需之 internationalization 套件；官方建議以 `intl: any` 避免與 Flutter 鎖定版本衝突。LICENSE 為 BSD-3-Clause（Copyright 2012, the Dart project authors；Flutter SDK 隨附 `packages/intl/LICENSE`）。CI `license_check.py` 要求所有直接依賴皆記錄於本檔 |
| `matrix`（matrix-dart-sdk） | 16.0.4（pubspec `^16.0.4`；第五十七批升級） | **AGPL-3.0-or-later** | 直接依賴。上游 `pubspec.yaml` 明示 `SPDX-License-Identifier: AGPL-3.0-or-later`，LICENSE 檔為 GNU Affero General Public License（本機 pub cache 內已解析套件為準）。藍圖 v1.3 記錄之 v12.0.0 已過時，併入本檔更新 |
| `sqflite_common_ffi` | 2.4.5（dev_dependency，僅整合測試用） | **BSD-2-Clause** | 直接依賴（測試專用）。原因：matrix 14.2.0 起的 `Client` 建構子必須提供 sqflite `Database`，測試採 in-memory sqlite 不落檔。LICENSE 為 BSD 2-Clause（Tekartik）。**此依賴經人類授權加入（2026-10-31）** |
| `dynamic_color` | 1.8.1（pubspec **精確固定**，非 `^`） | **Apache-2.0** | 直接依賴（Android 12+ 系統取色；fallback 為人類指定種子色，見 DESIGN.md §3）。**經人類授權加入（2026-10-31）**。⚠️ 2.1.0 的 `DynamicColorBuilder` 簽名指向套件 `material_ui` 之私有 ColorScheme，與 `flutter/material` 的 ColorScheme **型別不相容**（實測），故鎖定 1.8.1；升級前需人工重新評估 |
| `url_launcher` | 6.3.3（pubspec `^6.3.3`） | **BSD-3-Clause** | 直接依賴（1.3：以系統瀏覽器開啟 homeserver 網頁註冊頁）。**經人類授權加入（2026-10-31）**。LICENSE 為 BSD-3-Clause（The Flutter Authors；本機 pub cache url_launcher-6.3.3/LICENSE） |
| `sqflite` | 2.4.5（pubspec `^2.4.5`） | **BSD-2-Clause** | 直接依賴（1.4 前置：`MatrixSdkDatabase` 行動端 SQLite 後端；儲存方案 C）。**經人類授權加入（2026-10-31）**。LICENSE 為 BSD-2-Clause（Tekartik；本機 pub cache sqflite-2.4.5/LICENSE） |
| `sqflite_common_ffi_web` | 1.2.0+1（pubspec `^1.2.0`） | **BSD-2-Clause** | 直接依賴（**第三十五批 #1 Web/desktop，經人類批准 2026-11-12「官方依賴允許」**）：Web 端本機資料庫（IndexedDB 後端；sqflite 同源生態，tekartik 維護）。LICENSE 為 BSD 2-Clause（Copyright (c) 2022, Alexandre Roux Tekartik；本機 pub cache sqflite_common_ffi_web-1.2.0+1/LICENSE 覆核 2026-11-12） |
| `markdown` | 7.3.1（pubspec `^7.3.0`；原為 transitive 依賴，本批升 direct） | **BSD-3-Clause** | 直接依賴（**第三十五批 #13 Markdown 送出，經人類批准 2026-11-12「官方依賴允許」**）：Markdown→HTML（Matrix 官方 `formatted_body` 格式送出）。LICENSE 為 BSD-3-Clause（Copyright 2012, the Dart project authors；本機 pub cache markdown-7.3.1/LICENSE 覆核 2026-11-12） |
| `flutter_secure_storage` | 11.2.0（pubspec `^11.2.0`） | **BSD-3-Clause** | 直接依賴（1.4 前置：access token／SSSS cache 存系統安全儲存，SDK `secureStorage` 參數；儲存方案 C）。**經人類授權加入（2026-10-31）**。LICENSE 為 BSD-3-Clause（本機 pub cache flutter_secure_storage-11.2.0/LICENSE） |
| `mobile_scanner` | 7.4.3（pubspec `^7.4.3`） | **BSD-3-Clause** | 直接依賴（1.8：QR 掃描 skeleton；攝影機權限由套件處理）。**經人類授權加入（2026-10-31）**。LICENSE 為 BSD-3-Clause（GitHub raw juliansteenbakker/mobile_scanner/master/LICENSE） |
| `qr_flutter` | 4.1.0（pubspec `^4.1.0`） | **MIT** | 直接依賴（批次 III-c：好友邀請 QR 顯示；**經人類授權加入（2026-11-03）**） |
| `open_file` | 5.3.2（pubspec `^5.3.2`） | **MIT** | 直接依賴（第 1 點：檔案開啟，呼叫系統開啟支援格式的軟體；**經人類授權加入（2026-11-03）**） |
| `flutter_map` | 8.3.2（pubspec `^8.3.2`） | **BSD-3-Clause** | 直接依賴（批次 III-c：位置分享；OpenStreetMap tile＋flutter_map；**經人類授權加入（2026-11-03）**） |
| `latlong2` | 0.10.1（pubspec `^0.10.1`） | **BSD-3-Clause** | 直接依賴（位置分享 transitive 但 lint 要求直接引 declared；OpenStreetMap） |
| `app_links` | 7.2.2（pubspec `^7.2.2`） | **MIT** | 直接依賴（第 2 點：接收外部分享，監聽 Android intent；**經人類授權加入（2026-11-03）**） |
| `file_picker` | 13.3.0（pubspec `^13.3.0`） | **MIT** | 直接依賴（2.8：照片/影片多選附件，使用 Android 系統檔案選取器；MIME 自動分類，無影片開關）。**經人類授權加入（2026-10-31）**。LICENSE 為 MIT（pub.dev packages/file_picker/license 查證日 2026-10-31）。附屬 transitive：`android_file_picker`、`file_picker_darwin`、`file_picker_linux`、`file_picker_web`、`windows_file_picker`、`file_picker_platform_interface`（MIT）；`cross_file`（BSD-3-Clause，Flutter Authors）——本機 pub cache LICENSE 覆核 2026-10-31 |
| `flutter_vodozemac` | 0.9.1（pubspec `^0.9.0`） | **AGPL-3.0** | 直接依賴（1.5：matrix 14.2.0 加密引擎的 Rust 原生綁定；Android 端以 cargokit 於建置時由 Rust 原始碼編譯出 `libvodozemac_bindings_dart.so`，首次建置需 cargokit 自動下載 rustup 工具鏈）。**經人類授權加入（2026-10-31，同批修復「無法加密／載入加密訊息」根因）**。LICENSE 為 AGPL-3.0（Famedly；pub.dev packages/flutter_vodozemac/license 查證日 2026-10-31）。附屬 transitive：`vodozemac` 0.9.1（AGPL-3.0；**2026-11-12 lock 刷新 0.9.0→0.9.1，官方 security fix：GHSA-pqp6-f7wc-6498／GHSA-v27v-f96q-qhjq，人類拍板保留**；本機 pub cache LICENSE 覆核 2026-10-31）、`flutter_rust_bridge` 2.13.0（MIT，本機 pub cache LICENSE 覆核 2026-10-31） |
| `image` | 4.13.1（pubspec `^4.13.0`；lock 解析 4.13.1；原為 matrix 的傳遞依賴，現改為直接引用） | **MIT** | 直接依賴（**2026-11-06 人工批准方案 C**：上傳前於 isolate 內 decode → 清 EXIF → copyResize → encodeJpg(quality 78)；**2026-11-14 升級 4.12.0 → 4.13.0**，人類批准依賴變更）。matrix 已傳遞依賴 `image ^4.0.15`，此處僅**直接化引用**，非新增套件。LICENSE 為 MIT（brendan-duncan/image；本機 pub-cache LICENSE 已核對，見 `app/pubspec.yaml` 註解）。附屬 transitive：`archive` 4.6.0（MIT，`image` 帶入；**已在依賴樹內**） |
| `firebase_core` | 5.1.0（pubspec `^5.1.0`） | **BSD-3-Clause** | 直接依賴（**2026-11-15 人類批准**：FCM 推播——Firebase 初始化）。僅 Android 有效；無 `google-services.json` 時 App 端靜默停用 FCM。LICENSE 為 BSD-3-Clause（Copyright 2017 The Chromium Authors；本機 pub-cache firebase_core-5.1.0/LICENSE 覆核 2026-11-15） |
| `firebase_messaging` | 17.0.1（pubspec `^17.0.1`） | **BSD-3-Clause** | 直接依賴（**2026-11-15 人類批准**：FCM 推播——token 取得／訊息監聽／背景冷喚醒）。Android 側另需 App 模組直接引用 Firebase Android SDK（`com.google.firebase:firebase-messaging`，BoM 35.1.0；見 `android/app/build.gradle.kts`）。LICENSE 為 BSD-3-Clause（Copyright 2017 The Chromium Authors；本機 pub-cache firebase_messaging-17.0.1/LICENSE 覆核 2026-11-15）。附屬 Android 傳遞依賴：`firebase-messaging`（Apache-2.0，Google）——⚠️ **新增第三方傳遞依賴（Google Firebase SDK）**，授權為 Apache-2.0 |
| `archive` | 4.6.0（pubspec `^4.6.0`；lock 解析 4.6.0） | **MIT** | 直接依賴（**2026-11-14 人類批准**：zip 貼圖包匯入，藍圖 Phase 3.2／3.3——zip 讀取與安全驗證）。**原本已在依賴樹內**（`image` 的傳遞依賴）→ 升為直接依賴，**不新增任何套件到 App**。LICENSE 為 MIT（Copyright (c) 2013-2021 Brendan Duncan；本機 pub-cache archive-4.6.0/LICENSE 覆核 2026-11-14）。附屬 transitive：`archive_io` 等 |
| `path_provider` | 2.1.6（pubspec `^2.1.6`；lock 解析 2.1.6） | **BSD-3-Clause** | 直接依賴（**2026-11-14 人類批准**：本機貼圖庫資料夾，存放 zip 貼圖包解壓副本，供預覽與關鍵字建議）。**原本已在依賴樹內**（傳遞依賴）→ 升為直接依賴，**不新增任何套件到 App**。LICENSE 為 BSD-3-Clause（The Flutter Authors；本機 pub-cache path_provider-2.1.6/LICENSE 覆核 2026-11-14）。附屬 transitive：`path_provider_android`／`path_provider_foundation`／`path_provider_linux`／`path_provider_windows`（同授權） |
| `image_picker` | 1.2.4（pubspec `^1.2.1`） | **BSD-3-Clause** | 直接依賴（UI 重構：輸入列「相機」鈕拍照附件，`ImageSource.camera` 走系統相機 intent）。**經人類授權加入（2026-11-01）**。LICENSE 為 BSD-3-Clause（Copyright 2013 The Flutter Authors；本機 pub cache image_picker-1.2.4/LICENSE 覆核 2026-11-01）。附屬 transitive（全部 BSD-3-Clause，The Flutter Authors；本機 pub cache LICENSE 逐一覆核 2026-11-01）：`image_picker_android` 0.8.13+25、`image_picker_ios` 0.8.13+14、`image_picker_for_web` 3.1.1、`image_picker_linux` 0.2.2、`image_picker_macos` 0.2.2+1、`image_picker_platform_interface` 2.11.2、`image_picker_windows` 0.2.2 |
| `flutter_webrtc` | 1.6.3（pubspec `^1.6.3`） | **MIT** | 直接依賴（P2.15 通話，提案；人類批准依賴 2026-11-01）：matrix 14.2.0 官方 VoIP 模組需 App 端自備 WebRTCDelegate 實作 → 本套件提供 Android/iOS WebRTC 能力。LICENSE 為 MIT（Copyright 2018 湖北捷智云技术有限公司；flutter-webrtc/flutter-webrtc GitHub LICENSE 查證日 2026-11-01）。附屬 transitive：`dart_webrtc` 1.8.2（MIT，Copyright 2020 Flutter WebRTC；本機 pub cache LICENSE 覆核 2026-11-01） |\n
| `livekit_client` | 2.13.2（pubspec `^2.8.1`，pub 解析至 2.13.2） | **Apache-2.0** | 直接依賴（P2.15c LiveKit-backed 群組通話／MatrixRTC，人類批准 2026-11-01）：matrix 14.2.0 LiveKitBackend 僅負責信令＋金鑰分發，實際媒體連線由 App 透過本套件完成。LICENSE 為 Apache-2.0（livekit/client-sdk-flutter，pub-cache LICENSE 覆核 2026-11-01）。附屬 transitive 依賴眾多（protobuf、grpc 等），授權詳見 pub-cache |
| `share_plus` | 13.3.1（pubspec `^13.3.1`） | **BSD-3-Clause** | 直接依賴（backlog 批次 D：圖片全屏預覽的「分享／下載」走系統分享 sheet，`XFile.fromData` 記憶體分享、不落本地檔；**經人類批准 2026-11-01**）。LICENSE 為 BSD-3-Clause（Copyright 2017 The Flutter project authors；本機 pub cache share_plus-13.3.1/LICENSE 覆核 2026-11-01）。本批新增 transitive：`share_plus_platform_interface` 7.2.0（BSD-3-Clause，Chromium Authors；本機 LICENSE 覆核 2026-11-01）、`file` 7.0.1（BSD-3-Clause，Dart project authors；本機 LICENSE 覆核 2026-11-01）；`cross_file` 0.3.5+5（BSD-3-Clause）先前已隨 file_picker 記錄 |
| `pip` | 0.0.4（pubspec `^0.0.4`） | **BSD-3-Clause** | 直接依賴（P2.15c PiP，人類批准 2026-11-01）：Android Picture-in-Picture 支援。LICENSE 為 BSD-3-Clause（本機 pub cache 覆核 2026-11-01） |
| `wakelock_plus` | 1.8.2（pubspec `^1.8.2`） | **BSD-3-Clause** | 直接依賴（P2.15c 螢幕分享期間保持螢幕常亮，避免系統回收 App；人類批准 2026-11-01）。LICENSE 為 BSD-3-Clause（本機 pub cache 覆核 2026-11-01） |
| `webrtc_interface` | 1.5.1（pubspec `^1.5.1`） | **MIT** | 直接依賴（P2.15：SDK `WebRTCDelegate` 之 `RTCPeerConnection`／`MediaDevices` 型別來源須直接引用；原為 matrix 14.2.0 transitive `^1.2.0`，本批轉直接依賴以免重複版本漂移）。**經人類授權加入（2026-11-01，同批通話依賴）**。LICENSE 為 MIT（Copyright 2021 Flutter WebRTC；本機 pub cache webrtc_interface-1.5.1/LICENSE 覆核 2026-11-01） |
| `cupertino_icons` | 來自 flutter create 預設（pubspec `^1.0.8`，lock 1.0.9） | MIT | flutter create 預設依賴。LICENSE 為 The MIT License（本機 pub cache cupertino_icons-1.0.9/LICENSE，查證日 2026-10-31） |
| `unifiedpush` | 6.1.0（pubspec `^6.1.0`） | **Apache-2.0** | 直接依賴（任務 3 批次 A，**經人類批准 2026-11-07**，pubspec 註解既有記錄；DEP 檔補列 2026-11-07 十二批驗證時發現漏記）：UnifiedPush 通道偵測／註冊（偵測使用者自選 distributor，如 ntfy）。LICENSE 為 Apache License 2.0（本機 pub cache unifiedpush-6.1.0/LICENSE 覆核 2026-11-07）。附屬 transitive：`unifiedpush_android` 3.3.1、`unifiedpush_platform_interface` 3.1.0（兩者 LICENSE 均 Apache-2.0，本機 pub cache 覆核 2026-11-07） |
| `flutter_lints` | 來自 flutter create 預設（pubspec `^6.0.0`，lock 6.0.0，dev） | BSD-3-Clause | flutter create 預設依賴（lint 規則集）。LICENSE 為 BSD-3-Clause（The Flutter Authors；本機 pub cache flutter_lints-6.0.0/LICENSE，查證日 2026-10-31） |

## 規格基準版本（任務 0.14；查證紀錄見藍圖 §十五）

| 項目 | 版本 | 發布日 | 來源 |
|---|---|---|---|
| Matrix 規格基準 | **v1.19** | 2026-07-08 | spec.matrix.org/v1.19/changelog/v1.19/（藍圖 §十五 已查證） |
| Matrix 規格前一版 | v1.18 | 2026-03-25 | 同上（v1.18 changelog；藍圖 §十五 已查證） |
| `matrix` SDK | **14.2.0** | — | 本專案 `app/pubspec.lock`（direct main）＋ pub.dev `packages/matrix`（2026-10-31） |

- 規格基準日：2026-10-27（藍圖 v1.3 查證基準日）；每個 Phase 開始前依藍圖 §六「規格快速演進」風險項重查。
- 貼圖功能以 v1.19 穩定規格為準（事件對映見藍圖 §十一）。
- 新增／相容性問題（如 SDK 對 image pack 事件的命名）仍標 ⚠️待查證，不因本節而視為已確認。

## 說明

- Flutter 專案位於 `app/`：套件名 **`homing`**（原 `ring`，2026-11-12 改名）、Android `applicationId`＝**`io.github.itsxiaobai`**（批次 35 換定）、平台目錄 `android/ ios/ web/ linux/ windows/ macos/`（批次 35 新增 Web／桌面骨架）；Flutter 3.47.9 stable / Dart 3.13.7。`flutter_test` 為 Flutter SDK 內建，不列第三方。
- **每次新增依賴**：由人類決定 → 於本檔記錄其 SPDX 授權 → CI 加入授權檢查（✅ 已實作：0.11，見 `app/ci/license_check.py`）。

## 授權結論

- 核心依賴授權為 AGPL，故本專案授權模式為 **AGPL-3.0-or-later（已定，非選項）**。
- AGPL 與 App Store 條款相容性：**待專業諮詢**；Agent 不得給出法律結論。

## 第八十六批新增依賴（無障礙服務；本機處理、隱私保護）

| 套件 | 版本 | 用途 | SPDX |
|---|---|---|---|
| `flutter_tts` | ^4.2.0 | 文字轉語音（系統引擎，讀出訊息） | MIT |
| `speech_to_text` | ^7.3.0 | 語音轉文字（系統引擎） | MIT |
| `google_mlkit_text_recognition` | ^0.15.0 | OCR（**本機**模型，不送雲端） | Apache-2.0 |
| `whisper_ggml` | ^2.10.0 | 音檔／通話本機 Whisper STT（模型分開下載、離線；Android API 24+ 舊裝置可跑） | MIT |

> 以上肇於人類 2026-11-20 指示「無障礙服務 OCR/TTS/STT…同時保護隱私 & 舊裝置可跑」：
> 全部本機處理（TTS/STT 用系統引擎、OCR 用 ML Kit 離線模型），不上传任何資料。
> `pubspec.lock` 需由人類在可編譯機器 `flutter pub get` 更新（目前 lock 仍為舊版）。

## 待確認事項

- `app/pubspec.lock` 已鎖定 `matrix 14.2.0`；`pubspec.yaml` 之 `^14.2.0` 未來升級時須重新核對 SPDX。
- `cupertino_icons`、`flutter_lints`、`url_launcher`、`sqflite`、`flutter_secure_storage` 已完成 SPDX 核對與記錄（截至 2026-10-31）；本檔之 CI 防護（0.11）透過 `app/ci/license_check.py` 於 GitHub Actions 執行。
- 儲存方案 C（人類拍板 2026-10-31）：sqflite（行動端 SQLite）＋ flutter_secure_storage（access token／SSSS cache 走 Keychain/Keystore）；E2EE 金鑰由 matrix SDK 14.2.0 內建管理（`MatrixSdkDatabase` 內含 Olm/Megolm session 與 device keys box，密碼學引擎為 SDK 依賴之 vodozemac；App 端不自寫加密程式）。
