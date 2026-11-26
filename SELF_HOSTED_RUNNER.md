# 自架 GitHub Actions Runner（Homing APK 出包）

> 目的：避開 GitHub-hosted runner 在 Gradle compile 中被回收（runner shutdown signal）。
> 適用環境：Ubuntu 24.04 LTS / 8 vCPU / 16 GB RAM / 40 GB 磁碟。
> ⚠️ 我無法登入你的 VPS；以下由你在 VPS 上執行。Token 請從 GitHub 頁面取得，不要貼給我。

## 出包 SOP（強制順序：**先 CI，後 VPS 編譯**）

> 人類 2026-11-24 指示：**先跑完 CI 沒問題，才在 VPS 上編譯 APK。**
> 原因：避免在明明 analyze／test／license 會失敗的程式碼上浪費 VPS 資源與時間。

1. **推 commit 到 `homing-alpha`，先跑 CI**
   - 等 `analyze-test-license` 與 `vulnerability-scan` 兩個 job 都 **success**
   - CI 沒過 → 先修錯誤、重推、重跑，**不要**開始 VPS 編譯
2. **CI 全綠後，同步「通過 CI 的那個 commit」到 VPS**
   ```sh
   cd <本機 side-project>
   git rev-parse --short HEAD        # 記下 commit，etc. 確認與 CI 一致
   tar czf - app | ssh ghadmin@<VPS> 'sudo -n -u gh-runner mkdir -p ~/homing && sudo -n -u gh-runner tar xzf - -C ~/homing'
   ```
3. **在 VPS 上編譯（日常／實機測試：只建 arm64-v8a）**
   ```sh
   ssh ghadmin@<VPS> 'sudo -n -u gh-runner env \
     FLUTTER_SUPPRESS_ANALYTICS=true \
     ANDROID_HOME=/home/gh-runner/android-sdk \
     ANDROID_SDK_ROOT=/home/gh-runner/android-sdk \
     JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
     PATH=/home/gh-runner/flutter/bin:/home/gh-runner/.cargo/bin:$PATH \
     bash -c "cd ~/homing/app && flutter pub get && \
       flutter build apk --release --split-per-abi --target-platform android-arm64"'
   ```
   > 人類 2026-11-25 指示：**平時只建 v8a**，只跑一個 `gen_snapshot`、
   > 時間約 1/3；正式公開前才編譯下面四包。
4. **抓回 APK** 到本機（`/tmp` 中轉避開 `/home/gh-runner` 700 權限）
   ```sh
   ssh ghadmin@<VPS> 'sudo -n cp ~/homing/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /tmp/app.apk && sudo -n chmod 644 /tmp/app.apk'
   scp ghadmin@<VPS>:/tmp/app.apk ./homing-app-<版本>-arm64.apk
   ```
5. **版本號**：每次新的 APK 都要在 `app/pubspec.yaml` 往上 bump（CI 那次也要算）。

### 正式公開前：四包一起出

> 人類 2026-11-25 指示：正式發布時要建立 **三種 ABI 分包 ＋ 通用整合版**。
> 目前 GitHub Actions 的 `build-apk` job（手動 dispatch）就是走通用版；
> 若在 VPS 手動出正式包，執行：
```sh
ssh ghadmin@<VPS> 'sudo -n -u gh-runner env FLUTTER_SUPPRESS_ANALYTICS=true \
  ANDROID_HOME=/home/gh-runner/android-sdk \
  ANDROID_SDK_ROOT=/home/gh-runner/android-sdk \
  JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
  PATH=/home/gh-runner/flutter/bin:/home/gh-runner/.cargo/bin:$PATH \
  bash -c "cd ~/homing/app && flutter build apk --release --split-per-abi && \
    flutter build apk --release"'
```
- `--split-per-abi`：arm64-v8a／armeabi-v7a／x86_64 各一包
- 第二道（無 split）：通用整合版（三 ABI 全包，約 242MB）
- 四包都放進 GitHub Release／F-Droid 交付，日常測試不要浪費時間出這四包

> 補充：GitHub Actions 的 `build-apk` 已設為 self-hosted，但此 VPS 到
> `broker.actions.githubusercontent.com` 的連線間歇性不通 → 不適合當穩定 CI 來源。
> 因此流程改為「CI 只做檢查，APK 由 VPS 手動 build」。

## 其他機器怎麼接上 VPS（分步驟）

> 情境：換電腦、或另一台開發機要接手出包。每個人／每台機器用**自己的金鑰**，
> 不要共用私鑰，也不要在聊天室貼密碼。

### A. 取得 SSH 存取權

1. **在新機器產生金鑰**（Linux/macOS/WSL）：
   ```sh
   ssh-keygen -t ed25519 -C "你的識別@機器"
   # 產生 ~/.ssh/id_ed25519（私鑰，不外傳）與 ~/.ssh/id_ed25519.pub（公鑰）
   ```
   Windows（PowerShell，無 WSL）：用 `ssh-keygen` 或 PuTTYgen 產生，私鑰存好。
2. **把公鑰交給 VPS 管理者**，由他在 VPS 上加入：
   ```sh
   # 在 VPS（ghadmin 或有 sudo 的帳號）
   echo 'ssh-ed25519 AAAA... 你的識別@機器' >> /home/ghadmin/.ssh/authorized_keys
   ```
   ⚠️ 只要公鑰；管理者不需要（也不該）拿到你的私鑰。
3. **在新機器驗證**：
   ```sh
   ssh ghadmin@<VPS IP> 'echo OK; sudo -n whoami'
   ```
   出現 `OK` 與 `root` 就可接手（ghadmin 有 NOPASSWD sudo，用來切換到 gh-runner）。

### B. 把原始碼傳到 VPS

```sh
cd <本機的 side-project>
git rev-parse --short HEAD     # 確認是「CI 全綠」的那個 commit
tar czf - app | ssh ghadmin@<VPS IP> \
  'sudo -n -u gh-runner mkdir -p ~/homing && sudo -n -u gh-runner tar xzf - -C ~/homing'
```

### C. 在 VPS 編譯

```sh
ssh ghadmin@<VPS IP> 'sudo -n -u gh-runner env \
  FLUTTER_SUPPRESS_ANALYTICS=true \
  ANDROID_HOME=/home/gh-runner/android-sdk \
  ANDROID_SDK_ROOT=/home/gh-runner/android-sdk \
  JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
  PATH=/home/gh-runner/flutter/bin:/home/gh-runner/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash -c "cd ~/homing/app && flutter pub get && flutter build apk --release"'
```

### D. 抓回 APK

`/home/gh-runner` 是 700，ghadmin 進不去 → 先複製到 `/tmp` 中轉：

```sh
ssh ghadmin@<VPS IP> 'sudo -n cp /home/gh-runner/homing/app/build/app/outputs/flutter-apk/app-release.apk /tmp/app.apk && sudo -n chmod 644 /tmp/app.apk'
scp ghadmin@<VPS IP>:/tmp/app.apk ./homing-app-<版本>.apk
```

### E. 常見問題與撤權

| 狀況 | 處理 |
|---|---|
| `Permission denied (publickey)` | 公鑰還沒加進 `authorized_keys`，或私鑰檔權限太寬（`chmod 600 ~/.ssh/id_ed25519`） |
| scp 說 `No such file` | 檔案在 `/home/gh-runner`（700），照 D 先中轉 `/tmp` |
| `rustup not found` | 用上面 C 的完整 `PATH`（含 `~/.cargo/bin`），或重裝 Rust |
| OOM killer | workflow 已加 `GRADLE_OPTS` 限制 heap；手動 build 時 16GB 已足夠 |
| 某台機器不再使用 | 管理者從 `/home/ghadmin/.ssh/authorized_keys` **刪掉那行公鑰**，該機立刻失效 |

> 記得：新機器接入後仍遵守「先 CI 全綠、再 VPS 編譯」的 SOP（見本檔最上方）。

## 0. 安全前置（建議先做）

```sh
# 用金鑰登入、關閉密碼與 root 登入（依你現有 SSH 設定調整）
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 防火牆只開 SSH / HTTP / HTTPS
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable
```

## 1. 建立 runner 專用帳號

```sh
sudo useradd -m -s /bin/bash gh-runner
sudo usermod -aG sudo gh-runner   # 僅安裝階段需要；裝完可考虑移除
sudo -iu gh-runner
cd ~
```

## 2. 安裝編譯依賴

```sh
sudo apt update
sudo apt install -y git curl unzip zip xz-utils build-essential clang cmake ninja-build pkg-config libgl1-mesa-dev libxml2-utils openjdk-17-jdk
```

> Flutter SDK 與 JDK 會由 workflow 的 `subosito/flutter-action` / `actions/setup-java` 自動下載，
> 這裡裝的 JDK 是給 sdkmanager 與疑難排解用。

## 3. 安裝 Android SDK（含 NDK 29）

```sh
mkdir -p ~/android-sdk/cmdline-tools
cd /tmp
# 到 https://developer.android.com/studio#command-line-tools-only 取得「Command line tools only」最新版連結
curl -sSLO <最新版 commandlinetools-linux-XXXX_latest.zip 的下載網址>
unzip -q commandlinetools-linux-*_latest.zip -d ~/android-sdk/cmdline-tools
mv ~/android-sdk/cmdline-tools/cmdline-tools ~/android-sdk/cmdline-tools/latest

export ANDROID_HOME=$HOME/android-sdk
export ANDROID_SDK_ROOT=$HOME/android-sdk
yes | ~/android-sdk/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null
~/android-sdk/cmdline-tools/latest/bin/sdkmanager \
  "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;29.0.13113456"
```

⚠️ workflow 會再跑一次 `sdkmanager --licenses`，並可能另外安裝 NDK 28.2（某個相依套件要求），
大約多吃 3 GB —— 40 GB 磁碟要留意（見第 6 節）。

## 4. 註冊 runner（含 workflow 需要的標籤）

到 repo 頁面取得 token：
https://github.com/itsxiaobai/homing-alpha/settings/actions/runners/new

```sh
cd ~
mkdir actions-runner && cd actions-runner
# 在上方頁面複製對應「Linux x64」的下載與解壓指令（版本號以頁面為準）
curl -sSLO https://github.com/actions/runner/releases/download/<版本>/actions-runner-linux-x64-<版本>.tar.gz
tar xzf ./actions-runner-linux-x64-<版本>.tar.gz

# --labels 必須有 homing-builder（workflow 的 runs-on 會比對）
./config.sh \
  --url https://github.com/itsxiaobai/homing-alpha \
  --token <你的 token> \
  --name homing-vps-01 \
  --labels homing-builder \
  --work _work \
  --unattended
```

預設標籤 `self-hosted`、`linux`、`x64` 會自動加上，所以 workflow 的
`runs-on: [self-hosted, linux, x64, homing-builder]` 會配對到這台。

### 設定環境變數給 job

在 `~/actions-runner/.env` 加入（若檔案不存在就新增）：

```
ANDROID_HOME=/home/gh-runner/android-sdk
ANDROID_SDK_ROOT=/home/gh-runner/android-sdk
```

## 5. 安裝服務並啟動

```sh
cd ~/actions-runner
sudo ./svc.sh install gh-runner
sudo ./svc.sh start
sudo ./svc.sh status
```

回到 GitHub runner 頁面，狀態應顯示 **Idle**（綠點）。

## 6. 磁碟管理（40 GB 要顧）

```sh
# 手動查看
df -h /

# 手動清理舊 job 目錄（保留最近 7 天）
find ~/actions-runner/_work -mindepth 2 -maxdepth 2 -type d -mtime +7 -exec rm -rf {} +

# Gradle 快取過大時
du -sh ~/.gradle/caches 2>/dev/null
rm -rf ~/.gradle/caches/modules-2/metadata-*   # 僅在空間不足時
```

建議加 cron 每週清一次舊 job 目錄；低於 10 GB 可用時要先清再觸發 build。

## 7. 觸發與驗證

runner 上線後，在 homing-alpha 手動觸發 `license-check-and-vulnerability-scan`（workflow_dispatch）。
`build-apk` job 應該顯示跑在 `homing-vps-01`，而不是 GitHub-hosted runner。

## 8. 注意事項

- **不要再的包公開 repo 用同一台 runner**；公開 repo 任何人都能發 PR 觸發程式碼執行。
- runner 版本要定期更新（GitHub 會在页面上提示）。
- 若換機或重裝，`--labels homing-builder` 要重新加，否則 job 會一直 pending。
