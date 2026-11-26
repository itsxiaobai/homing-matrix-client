// 任務：Phase 1 / 1.3 — 登入畫面骨架（草案，待人類設計）
// 依 AGENTS.md UI 規則：無樣式／最小樣式、不寫死寬度、文案與版面待定稿。
// 註冊：matrix.org 已關閉客戶端註冊，改以系統瀏覽器開啟伺服器網頁註冊頁。
// 1.4 前置：登入成功後回呼**持久化 Client**，導向訊息列表（1.4 skeleton）。
// 第三十四批（人類需求 #7，2026-11-12）：預設只顯示 matrix.org；底下提供
// 「如果有自己的伺服器，請按這裡！」連結，點開才展開自訂 homeserver 欄位
// 與選項（註冊／登入共用同一伺服器選擇；展開後仍可回到既有三選項流程）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth.dart';
// 新項（2026-11-05）：官方 CryptoSetupExtension（getCryptoIdentityState／
// restoreCryptoIdentity）未由 matrix.dart 匯出 → 直引官方路徑。
import 'package:matrix/encryption/utils/crypto_setup_extension.dart';
import '../client_factory.dart';
import '../crypto_recovery.dart';
import '../homeserver_url.dart';
import '../oidc_login.dart'
    show
        OidcLoginSessionHolder,
        oidcCallbackParams,
        oidcCallbackStream,
        prepareOidcLogin,
        completeOidcLogin; // 第一百零三批：MAS／OIDC 登入（零新依賴）
import 'connect_screen.dart' show HomeserverPreset;
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化
import 'line_style.dart'; // 68e/68f LINE 版面

/// 開啟外部 URL 的抽象（供測試注入）。
typedef UrlOpener = Future<bool> Function(Uri url);

/// 第一百零三批：OIDC 準備／完成與 callback 流的抽象（供測試注入）。
typedef OidcPrepare = Future<OidcLoginSessionHolder> Function(Uri homeserver);
typedef OidcComplete = Future<void> Function(
  OidcLoginSessionHolder holder,
  Uri callback,
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.homeserver,
    this.login,
    this.checkServer,
    this.onLoggedIn,
    this.resolveRegistrationPage,
    this.openUrl,
    this.oidcPrepare,
    this.oidcComplete,
    this.oidcCallbacks,
    this.createClientForLogin,
    this.autoOpenRegistration = false,
  });

  /// 批次 I②：自選 homeserver 一併放進登入頁；不提供時＝matrix.org 預設。
  final Uri? homeserver;
  final PasswordLogin? login;

  /// 批次 I②：「測試連線」與登入合併——送出時**先檢查後登入**（自動完成步驟，
  /// 人類指示「使用者只須輸入帳號密碼即自動完成步驟」）。可注入以供測試。
  final Future<String?> Function(Uri homeserverUrl)? checkServer;

  /// 登入成功後的出口：回呼持久的 Client；未提供時僅顯示提示（1.3 骨架行為）。
  final void Function(Client client)? onLoggedIn;

  final RegistrationPageResolver? resolveRegistrationPage;
  final UrlOpener? openUrl;

  /// MAS／OIDC：準備授權、完成登入、以及 callback 來源（都可注入測試）。
  final OidcPrepare? oidcPrepare;
  final OidcComplete? oidcComplete;
  final Stream<Uri>? oidcCallbacks;

  /// 第一百零四批：多帳號新增時，用指定 DB／SDK name 建立 Client。
  final Future<Client> Function()? createClientForLogin;

  /// 第一百零五批：從歡迎頁「建立帳號」進來時，直接帶出註冊提醒。
  final bool autoOpenRegistration;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _homeserverController = TextEditingController(
    text: (widget.homeserver ?? defaultHomeserver).toString(),
  );
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();

  /// 批次 I②：伺服器預設選項（與 ConnectScreen 同枚舉；預設 matrix.org）。
  HomeserverPreset _preset = HomeserverPreset.homing;

  /// 第三十四批（人類需求 #7）：自訂伺服器選項預設收起；點下方連結展開。
  /// 收起時一律以 matrix.org（或外部傳入的預設）為準。
  bool _showServerOptions = false;

  String? _message;
  bool _busy = false;
  bool _registrationBusy = false;

  /// Suggestion #3（人類回饋 2026-11-03）：已開啟網頁註冊、使用者回到 App
  /// （AppLifecycleState.resumed）時顯示「註冊完成請在此登入」並聚焦帳號欄。
  bool _registrationLaunched = false;

  /// 第一百零三批：SSO 授權等待中的 session／callback 訂閱。
  OidcLoginSessionHolder? _oidcHolder;
  StreamSubscription<Uri>? _oidcSub;
  bool _ssoPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _oidcSub = (widget.oidcCallbacks ?? oidcCallbackStream)
        .listen(_onOidcCallback);
    if (widget.autoOpenRegistration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_onOpenRegistration());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Suggestion #3「註冊完成應自動跳回登入頁」：本頁即登入頁——監測從
    // 瀏覽器返回（resumed），自動切回登入狀態並聚焦帳號欄（草案行為）。
    if (state == AppLifecycleState.resumed &&
        _registrationLaunched &&
        !_ssoPending &&
        mounted) {
      _registrationLaunched = false;
      setState(() {
        _registrationBusy = false;
        _message = '註冊完成後請在此頁登入。'; // 文案草案
      });
      _focusUserField();
    }
  }

  void _focusUserField() {
    // FocusScope.requestFocus 官方 API 為同步 void（無 await 需要）。
    FocusScope.of(context).requestFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_oidcSub?.cancel());
    _homeserverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Uri _currentHomeserver() {
    final text = _homeserverController.text.trim();
    if (text.isEmpty) return widget.homeserver ?? defaultHomeserver;
    return Uri.tryParse(text) ?? (widget.homeserver ?? defaultHomeserver);
  }

  /// 批次 I②：預設選項切換（同 ConnectScreen 行為；Homing 自架＝尚未提供）。
  void _selectPreset(HomeserverPreset? preset) {
    if (preset == null) {
      return;
    }
    setState(() {
      _preset = preset;
      _message = null;
      switch (preset) {
        case HomeserverPreset.homing:
          _homeserverController.text = defaultHomeserver.toString();
        case HomeserverPreset.matrixOrg:
          _homeserverController.text = matrixOrgHomeserver.toString();
        case HomeserverPreset.custom:
          _homeserverController.clear();
        case HomeserverPreset.ringSelfHosted:
          _homeserverController.clear();
          _message = 'Homing 自架伺服器尚未架設；目前請使用 matrix.org 或自訂 homeserver。';
      }
    });
  }

  /// 批次 I②：一站式送出＝**先測試連線、再登入**（失敗即停在錯誤訊息，不登入）。
  Future<void> _onLogin() async {
    if (_preset == HomeserverPreset.ringSelfHosted) {
      setState(() {
        _message = 'Homing 自架伺服器尚未架設；目前請使用 matrix.org 或自訂 homeserver。';
      });
      return;
    }
    final uri = parseUserHomeserverUrl(_homeserverController.text) ??
        _currentHomeserver();

    setState(() {
      _busy = true;
      _message = null;
    });
    // 先測（官方 checkServer：不落地）；失敗不進登入。
    String? preError;
    try {
      preError = await (widget.checkServer ?? checkServer)(uri);
    } catch (_) {
      preError = '無法連線：請檢查位址與網路';
    }
    if (!mounted) {
      return;
    }
    if (preError != null) {
      setState(() {
        _busy = false;
        _message = '連線測試失敗：$preError';
      });
      return;
    }

    final homeserver = uri;
    final userInput = _userController.text.trim();
    final password = _passwordController.text;
    if (userInput.isEmpty || password.isEmpty) {
      setState(() {
        _busy = false;
        _message = '請輸入帳號與密碼';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    String? error;
    Client? client;
    try {
      final PasswordLogin doLogin = widget.login ??
          ({
            required Uri homeserver,
            required String user,
            required String password,
          }) =>
              loginWithPassword(
                homeserver: homeserver,
                user: user,
                password: password,
                createClient: widget.createClientForLogin,
              );
      client = await doLogin(
        homeserver: homeserver,
        user: normalizeUserId(userInput, homeserver),
        password: password,
      );
    } on MatrixException catch (e) {
      error = _loginErrorMessage(e);
    } catch (_) {
      error = '無法連線：請檢查網路或稍後再試';
    }

    if (!mounted) {
      return;
    }

    await _afterLogin(client, error);
  }

  /// 登入成功／失敗後的共用出口（密碼與 OIDC 都走這裡）。
  ///  crypto identity 自動化與既有行為完全不變。
  Future<void> _afterLogin(Client? client, String? error) async {
    // Suggestion #1（人類批准 2026-11-05；範圍＝進行順序與自動化）：
    // 登入成功後（注入 stub 的測試路徑除外）執行官方 crypto identity 自動化；
    // 新帳號會生成 recovery key → 以畫面顯示一次（人類決定，可複製保管）。
    if (error == null && client != null && widget.login == null) {
      final recoveryOnce = await ensureFirstLoginCryptoIdentity(client);
      if (recoveryOnce != null && mounted) {
        await _presentRecoveryKeyOnce(context, recoveryOnce);
        if (!mounted) {
          return;
        }
      } else if (mounted) {
        try {
          final state = await client.getCryptoIdentityState();
          if (state.initialized && !state.connected) {
            await _askRecoveryKeyAndRestore(client);
          }
        } catch (_) {
          // state 判斷失敗（無引擎／網路）＝維持既有行為。
        }
      }
    }

    if (!mounted) {
      return;
    }

    if (error == null && widget.onLoggedIn != null) {
      widget.onLoggedIn!(client!);
      if (mounted) setState(() => _busy = false);
      return;
    }

    setState(() {
      _busy = false;
      _message = error ?? '已登入：${client!.userID}（本階段不導航）';
    });
  }

  // ── 第一百零三批：MAS／OIDC 登入 ───────────────────────────────────────

  /// 點「使用單一登入」：向伺服器動態註冊 OIDC client、開瀏覽器授權，
  /// 之後等 deep link callback 完成登入（不碰加密邏輯，全走 SDK 官方 API）。
  Future<void> _onSsoLogin() async {
    if (_busy || _ssoPending) return;
    final homeserver =
        parseUserHomeserverUrl(_homeserverController.text) ?? _currentHomeserver();
    setState(() {
      _busy = true;
      _message = null;
    });
    String? preError;
    try {
      preError = await (widget.checkServer ?? checkServer)(homeserver);
    } catch (_) {
      preError = '無法連線：請檢查位址與網路';
    }
    if (!mounted) return;
    if (preError != null) {
      setState(() {
        _busy = false;
        _message = '連線測試失敗：$preError';
      });
      return;
    }
    try {
      final OidcPrepare doPrepare = widget.oidcPrepare ??
          (homeserver) => prepareOidcLogin(
                homeserver,
                createClient: widget.createClientForLogin,
              );
      final holder = await doPrepare(homeserver);
      if (!mounted) return;
      _oidcHolder = holder;
      _ssoPending = true;
      final opened = await (widget.openUrl ?? _launch)(
        holder.session.authenticationUri,
      );
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _ssoPending = false;
          _busy = false;
          _message = '無法開啟瀏覽器，請手動完成單一登入。';
        });
        return;
      }
      setState(() {
        _busy = false;
        _message = S.t('正在等待單一登入完成…');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ssoPending = false;
        _busy = false;
        _message = '${S.t('單一登入失敗')}：$e';
      });
    }
  }

  /// app_links 收到的 OIDC callback（main.dart 已分流，分享內容不會進來）。
  Future<void> _onOidcCallback(Uri uri) async {
    final holder = _oidcHolder;
    if (holder == null || !_ssoPending || !mounted) return;
    if (oidcCallbackParams(uri) == null) return;
    await _oidcSub?.cancel();
    _oidcSub = null;
    _ssoPending = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    String? error;
    try {
      await (widget.oidcComplete ?? completeOidcLogin)(holder, uri);
    } on MatrixException catch (e) {
      error = _loginErrorMessage(e);
    } catch (e) {
      error = '${S.t('單一登入失敗')}：$e';
    }
    if (!mounted) return;
    _oidcHolder = null;
    await _afterLogin(error == null ? holder.client : null, error);
  }

  Future<void> _onOpenRegistration() async {
    setState(() {
      _registrationBusy = true;
      _message = null;
    });

    // Suggestion #3「註冊開始前提醒使用者保管好帳號密碼與 recovery key」：
    // 開啟網頁註冊前彈出提醒（草案文案；純提醒、不涉任何金鑰處理）。
    if (mounted) {
      final acknowledged = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.t('開始註冊前')), // 文案草案
          content: const Text(
            '完成註冊後，請務必妥善保管：\n\n'
            '・帳號與密碼\n'
            '・註冊過程顯示的 recovery key（復原金鑰）\n\n'
            '遺失 recovery key 將無法在復原加密資料。', // 文案草案
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.t('取消')), // 文案草案
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.t('我記住了，開始註冊')), // 文案草案
            ),
          ],
        ),
      );
      if (acknowledged != true) {
        if (!mounted) {
          return;
        }
        setState(() => _registrationBusy = false);
        return;
      }
    }

    Uri? url;
    String? error;
    final hs = _currentHomeserver();
    try {
      url = await (widget.resolveRegistrationPage ?? resolveRegistrationPage)(
        hs,
      );
    } catch (_) {
      url = null;
    }

    if (url == null) {
      error = '此伺服器未提供網頁註冊資訊；請洽伺服器管理員。';
    } else {
      final opened = await (widget.openUrl ?? _launch)(url);
      if (!opened) {
        error = '無法開啟瀏覽器，請手動前往：$url';
      } else {
        // Suggestion #3：記錄已開啟 → 返回 App 時由 lifecycle 顯示登入提示。
        _registrationLaunched = true;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _registrationBusy = false;
      _message = error;
    });
  }

  Future<bool> _launch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// Suggestion #1（人類決定 2026-11-05）：新帳號首次登入自動設定完成後，
  /// **立即以畫面顯示一次** recovery key——可全選複製、不可再見（草案文案）。
  Future<void> _presentRecoveryKeyOnce(BuildContext dialogContext, String key) {
    return showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('請保管這組 recovery key')), // 文案草案
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('只顯示這一次。遺失將無法在新裝置恢復歷史加密訊息。')), // 文案草案
            const SizedBox(height: 8),
            // SelectableText：可長按全選複製（最小樣式骨架，視覺待人類定稿）。
            SelectableText(key, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // 官方 services API：複製到系統剪貼簿。
              await Clipboard.setData(ClipboardData(text: key));
              if (ctx.mounted) {
                ScaffoldMessenger.of(dialogContext)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text(S.t('已複製到剪貼簿'))), // 文案草案
                  );
              }
            },
            child: Text(S.t('複製')), // 文案草案
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('我已保管完成')), // 文案草案
          ),
        ],
      ),
    );
  }

  /// 新項（人類回報 2026-11-05）：登入後詢問 recovery key／密語 →
  /// **官方** `Client.restoreCryptoIdentity()`（crypto_setup_extension.dart：
  /// 解鎖既有 SSSS 自動自簽本裝置；成功後 SDK 於 sync 時自動解密，不須重開）。
  /// 失敗 → 對話框顯示錯誤並可重試；「略過」== 走既有路徑（不阻擋登入）。
  Future<void> _askRecoveryKeyAndRestore(Client client) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final controller = TextEditingController();
        String? errorText;
        String? statusText;
        var busy = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(S.t('輸入 recovery key 以解密')), // 文案草案
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '輸入註冊／新帳號顯示過的 recovery key 或密語；'
                  '解密會立即生效，不需重新開啟 App。', // 文案草案
                ),
                const SizedBox(height: 8),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      statusText!,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  controller: controller,
                  enabled: !busy,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'recovery key 或密語', // 文案草案
                    errorText: errorText,
                  ),
                  onSubmitted: null,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(S.t('略過')), // 文案草案
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final value = controller.text.trim();
                        if (value.isEmpty) {
                          return;
                        }
                        setDialogState(() {
                          busy = true;
                          errorText = null;
                          statusText = null;
                        });
                        try {
                          // 第三十八批（實機根因）：SDK 自我簽章需要**本裝置的
                          // device key** 已回填；初次登入時 initial sync 逾時
                          // （logcat：`TimeoutException after 0:00:10` → 之後
                          // 才出現 `Updating user device keys in database...`）
                          // 會讓金鑰晚到 → 先等待就緒，避免誤報「key 不正確」。
                          setDialogState(() {
                            statusText = '等待本裝置金鑰同步…（首次連線可能需數十秒）';
                          });
                          final ready = await waitForOwnDeviceKeys(
                            client,
                            timeout: const Duration(seconds: 30),
                          );
                          setDialogState(() => statusText = null);
                          if (!ready) {
                            setDialogState(() {
                              busy = false;
                              errorText = describeRecoveryError(
                                Exception(kOwnDeviceKeysMissingError),
                              );
                            });
                            return;
                          }
                          // 官方 API：selfSign 預設 true（解鎖後自動自簽）。
                          await client.restoreCryptoIdentity(value);
                          // 第九十四批（人類授權 C）：restoreCryptoIdentity 只
                          // 解鎖 SSSS／自我簽章，不會把 megolm session 抓回本機
                          // → 重裝後舊訊息仍無法解密。接著跑官方金鑰備份還原。
                          if (ctx.mounted) {
                            setDialogState(() {
                              statusText = '正在從金鑰備份還原歷史訊息…';
                            });
                          }
                          try {
                            final restored =
                                await restoreKeyBackupSessions(client);
                            if (ctx.mounted) {
                              setDialogState(() {
                                statusText = restored > 0
                                    ? '已從備份還原 $restored 個 session'
                                    : '備份內沒有可還原的 session';
                              });
                              await Future<void>.delayed(
                                const Duration(milliseconds: 800),
                              );
                            }
                          } on Object catch (e) {
                            if (ctx.mounted) {
                              setDialogState(() {
                                errorText =
                                    '身份已解鎖，但備份還原失敗：$e（可稍後在'
                                    '設定 → 金鑰備份診斷與還原重試）';
                              });
                              return; // 不關閉對話框，讓使用者看到並可重試。
                            }
                          }
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                        } catch (e) {
                          setDialogState(() {
                            busy = false;
                            errorText = describeRecoveryError(e); // 草案文案
                          });
                        }
                      },
                child: Text(busy ? '解密中…' : '解密'), // 文案草案
              ),
            ],
          ),
        );
      },
    );
  }

  String _loginErrorMessage(MatrixException e) {
    switch (e.error) {
      case MatrixError.M_FORBIDDEN:
        return '帳號或密碼錯誤';
      case MatrixError.M_USER_DEACTIVATED:
        return '此帳號已停用';
      case MatrixError.M_LIMIT_EXCEEDED:
        return '嘗試次數過多，請稍後再試';
      default:
        return '登入失敗（${e.error}）';
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || _registrationBusy;
    return Scaffold(
      appBar: AppBar(title: lineTitlePill(context, S.t('登入'))), // 文案待 UI 定稿
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第三十四批（人類需求 #7）：預設只顯示 matrix.org；自訂伺服器
              // 選項收合在「如果有自己的伺服器，請按這裡！」連結後（草案）。
              if (!_showServerOptions) ...[
                ListTile(
                  dense: true,
                  leading: Icon(AllIcons.radioButtonChecked),
                  title: Text(HomeserverPreset.homing.label), // Homing 優先
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => _showServerOptions = true),
                  child: Text(S.t('如果有自己的伺服器，請按這裡！')), // 人類指定文案
                ),
              ] else ...[
                // 批次 I②：伺服器預設選項（草案；文案與样式待人類設計定稿）。
                Text(S.t('伺服器'), style: Theme.of(context).textTheme.labelLarge),
                ...[
                  for (final preset in HomeserverPreset.values)
                    ListTile(
                      title: Text(
                        preset == HomeserverPreset.ringSelfHosted
                            ? '${preset.label}（尚未提供）'
                            : preset.label,
                      ),
                      dense: true,
                      leading: Icon(
                        _preset == preset
                            ? AllIcons.radioButtonChecked
                            : AllIcons.radioButtonOff,
                      ),
                      onTap: busy ? null : () => _selectPreset(preset),
                    ),
                ],
                TextField(
                  controller: _homeserverController,
                  enabled: !busy,
                  autocorrect: false,
                  decoration:
                      const InputDecoration(labelText: 'Homeserver 位址'),
                ),
                Text('${S.t('伺服器：')}${_currentHomeserver()}'),
              ],
              TextField(
                controller: _userController,
                enabled: !busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '帳號（@user:伺服器 或 user）',
                ),
              ),
              TextField(
                controller: _passwordController,
                enabled: !busy,
                obscureText: true,
                onSubmitted: (_) => _onLogin(),
                decoration: const InputDecoration(labelText: '密碼'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: busy ? null : _onLogin,
                    child: Text(_busy ? '登入中…' : '登入'),
                  ),
                  TextButton(
                    onPressed: busy ? null : _onOpenRegistration,
                    child: Text(
                      _registrationBusy ? '開啟註冊頁…' : '前往網頁註冊',
                    ),
                  ),
                  // 第一百零三批：MAS／OIDC-only 伺服器用這個登入。
                  TextButton(
                    onPressed: busy ? null : _onSsoLogin,
                    child: Text(S.t('使用單一登入')),
                  ),
                ],
              ),
              if (_message != null) Text(_message!),
              // 註冊說明（文案待 UI 定稿）
              Text(S.t('註冊由伺服器網頁處理，完成後回到此畫面登入。')),
            ],
          ),
        ),
      ),
    );
  }
}
