# THREAT_MODEL.md — Homing 威脅模型

> **草稿，須人工審閱，非法律意見。**

本文是 `PRIVACY.md` 的前置文件：先定義「防誰、不防誰」，隱私聲明才能準確。此骨架依藍圖（agent_v1_3.md）§二之二。

## 系統概述

- 客戶端：Homing（Flutter）；v1.0 平台為 Android + iOS（Web／桌面僅骨架，尚未正式發布）
- E2EE：Olm / Megolm，預設開啟（**Web 版不支援**，加密引擎無該平台實作）
- 通話：1:1 與群組通話（MatrixRTC／LiveKit SFU）；群組通話的媒體流會經過 homeserver 公告的 LiveKit 節點
- Homeserver：初期使用第三方公共 homeserver（※matrix.org 目前已關閉標準註冊，homeserver 選擇**待人工決定**）；Homing 自訂 homeserver URL 為 P0 功能

## 在防護範圍內

本模型**防護**以下威脅：

- **好奇或惡意的 homeserver 管理者（對訊息內容）**——E2EE 房間內的訊息內容、reaction 內容對伺服器不可讀
- **網路竊聽者**——所有流量走 HTTPS ／ Matrix 傳輸加密
- **未經驗證的第三方裝置**——Homing 政策：未交叉簽署的裝置不得讀取新訊息（比規格 MSC4153 的 SHOULD NOT 建議更嚴格）

## 不在防護範圍內

本模型**不防護**以下威脅／風險，使用後果由使用者承擔：

- **擁有你裝置實體存取權的人**（可讀取本機快取、通知）
- **已驗證但被惡意使用的裝置**（持有金鑰即可解密）
- **Metadata 分析**——誰在何時跟誰說話、線上狀態、已讀回條、裝置清單、IP 連線紀錄等對 homeserver 可見
- **橋接對話（如 LINE 橋接，若啟用）**——伺服器端明文
- **推播基礎設施所見的資訊**——APNs / FCM / push gateway 可能看到推播內容或 metadata
- **你自己截圖或轉傳的內容**
- **貼圖圖片本身的保密性**——以明文存放於 homeserver；任何持有 mxc 連結且通過該伺服器認證者可下載，伺服器管理者可直接讀取
- **金鑰／裝置全遺失**——recovery key 遺失且無任何已登入的已驗證裝置時，歷史訊息**永久無法恢復**，homeserver 也救援不了
- **群組通話的媒體轉送節點**——群組通話（MatrixRTC）的媒體流經 homeserver 公告的 LiveKit SFU 節點；該節點位於 homeserver 之外，媒體流本身的加密狀態 ⚠️待查證
- **Web 平台**——該平台無 E2EE（僅開發骨架，未正式發布）；若公開發布，該平台上的對話內容對 homeserver 與第三方節點可見

## 信任假設

- Homeserver 誠實執行列出的規格行為（未含 supply-chain 攻擊伺服器軟體的情境）
- 使用者妥善保管 recovery key 與已驗證裝置
- Homing 不託管貼圖、不審核內容（詳見藍圖 §十一 §6）

## 已知限制待補

- 範圍外的軟體層供應鏈風險（依賴遭汙染）：由 CI 授權/弱點掃描（Phase 0.11）緩解，本文僅提及
- 詳細的攻擊面列表（端點、權限、秘密儲存）隨 Phase 1 實作補充

<!-- 待人工決定：自建 homeserver 後的信任假設須更新 -->
