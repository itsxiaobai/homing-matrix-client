// 批次十二②（人類指示「all」＋new_ref/settings/notification 結構參考）：
// 通知設定分區骨架。Homing 通知 v0 既有行為：App 非前景才通知（MethodChannel
// ring/local_notifications，零 FCM）。本頁 v0 提供：
//   ① 總開關「顯示通知」（關＝不再發任何本地通知）
//   ② 「顯示訊息內容」（關＝通知只顯示「新訊息」，不顯示 body）
// 參考頁內的 Mute／Albums／OpenChat／LINE Pay 區塊＝LINE 專屬，不透過
// （同截圖標註規則）；Mentions（SDK 端 notificationCount 未分提及）後續
// 需 SDK 官方條件再擴充。骨架草案，待人類設計定稿。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../app_settings.dart';
import 'effects_prefs.dart'; // 第八十六批：音效／視覺效果
import '../push/fcm_prefs.dart' as fcm_prefs;
import '../push/firebase_config.dart'; // 第八十六批：FCM 設定值
import '../push/fcm_runtime.dart'; // 第五十二批：FCM 閘道狀態警告
import '../push/push_channel.dart';
import '../push/push_runtime.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化

/// 批次十二②修（人類實測「通知功能沒辦法啟動」根因＝全 App 無 runtime 權限
/// 請求路徑）：本地通知 channel（零新依賴，同 main_shell 既有 const）。
const MethodChannel _notifyChannel = MethodChannel('homing/local_notifications');

/// 通知偏好執行緒（同 ringSeedColor 模式；main.dart 啟動載入、本頁即時改）。
final ValueNotifier<bool> ringNotificationsEnabled = ValueNotifier<bool>(true);
final ValueNotifier<bool> ringNotificationPreview = ValueNotifier<bool>(true);

/// 第三十四批（人類需求 #2「來電通知在旁邊出現，可選擇是否隱藏」）：
/// 來電橫幅偏好（true＝來電在畫面旁邊以橫幅顯示；false＝不顯示橫幅，
/// 僅系統通知欄提示）。main_shell 依此分流（草案行為，待人類設計定稿）。
final ValueNotifier<bool> ringIncomingCallBanner = ValueNotifier<bool>(true);

/// 系統通知權限狀態（null＝未知；false＝未授予；true＝已授予）。
/// main_shell 監聽：true 時清除「權限被拒」旗標＝重新武裝通知輪詢。
final ValueNotifier<bool?> ringNotificationPermission = ValueNotifier<bool?>(null);

/// 查系統 POST_NOTIFICATIONS（Android 13+；<13 無此 runtime 權限＝true）。
Future<bool> checkNotificationPermission() async {
  try {
    return await _notifyChannel.invokeMethod<bool>('check_permission') ?? false;
  } catch (_) {
    // 非 Android／channel 未初始化（測試環境）→ 回 false 由 UI 提示。
    return false;
  }
}

/// 請求系統授權對話框（Android 13+）；「不再詢問」＝系統直接回拒（不彈框），
/// UI 以提示代替。回 true＝已授予。
Future<bool> requestNotificationPermission() async {
  try {
    return await _notifyChannel.invokeMethod<bool>('request_permission') ?? false;
  } catch (_) {
    return false;
  }
}

/// 啟動／首次進殼時還原偏好（AppSettings 失敗＝預設開）＋查權限現狀。
Future<void> loadNotificationPrefs() async {
  ringNotificationsEnabled.value =
      await AppSettings.get('notifications_enabled').then((v) => v != '0')
          .catchError((_) => true);
  ringNotificationPreview.value =
      await AppSettings.get('notification_preview').then((v) => v != '0')
          .catchError((_) => true);
  // 第三十四批：來電橫幅偏好（預設開；無 DB 環境＝預設值）。
  ringIncomingCallBanner.value =
      await AppSettings.get('incoming_call_banner').then((v) => v != '0')
          .catchError((_) => true);
  // 批次十二②修：進殼即同步系統權限現狀（背景授予／收回都能反映）。
  ringNotificationPermission.value = await checkNotificationPermission();
}

class NotificationSettingsScreen extends StatefulWidget {
  /// 第七十八批：傳入 client 讓 FCM 開關能即時註冊／移除 pusher。
  const NotificationSettingsScreen({super.key, this.client});

  final Client? client;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;

  /// 推播總開關（kv `push_enabled`；預設開）。
  bool _pushEnabled = true;

  /// 第七十八批：FCM opt-in 開關（使用者主動啟用才會碰 Google）。
  bool _fcmEnabled = false;

  Future<void> _setFcm(bool value) async {
    final client = widget.client;
    if (client == null) {
      // 無 client（測試）→ 僅保存偏好，下次登入生效。
      await fcm_prefs.setFcmEnabled(value);
      if (mounted) setState(() => _fcmEnabled = value);
      return;
    }
    final ok = await RingPushRuntime.setFcmEnabled(value, client);
    await fcm_prefs.loadFcmEnabledPref();
    if (mounted) {
      setState(() => _fcmEnabled = fcm_prefs.ringFcmEnabled.value);
      if (!value) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('已停用 FCM；推播改走其他通道'))),
        );
      } else if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.t('FCM 無法啟用（憑證或閘道未設定）；請检查 Firebase 設定'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _setPushEnabled(bool v) async {
    await AppSettings.set('push_enabled', v ? '1' : '0');
    if (mounted) setState(() => _pushEnabled = v);
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      loadNotificationPrefs().whenComplete(
        () => mounted ? setState(() => _loading = false) : null,
      ),
    );
    // 推播總開關（第四十一批）。
    unawaited(
      AppSettings.get('push_enabled')
          .then((v) {
            if (mounted) setState(() => _pushEnabled = v != '0');
          })
          .catchError((_) {}),
    );
    // 第七十八批：FCM opt-in（預設關；讀取失敗維持關）。
    unawaited(
      fcm_prefs.loadFcmEnabledPref().whenComplete(
        () => mounted ? setState(() => _fcmEnabled = fcm_prefs.ringFcmEnabled.value) : null,
      ),
    );
  }

  /// 批次十二②修：權限列「再次請求」——成功後讓總開關可用（main_shell 同步
  /// 解除「權限被拒」旗標）。
  Future<void> _requestAgain() async {
    final granted = await requestNotificationPermission();
    ringNotificationPermission.value = granted;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? '已授予系統通知權限' // 文案草案
                : '仍未授予：請到 Android「設定 → 應用程式 → Homing → 通知」手動開啟', // 草案文案
          ),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  /// 批次十二②修：開啟總開關＝**先請求系統權限**（Android 13+ 無權限時發不
  /// 出通知）；拒絕→退回關閉＋提示（含「不再詢問」時需到系統設定的指引）。
  Future<void> _setEnabled(bool value) async {
    if (value) {
      final granted = await requestNotificationPermission();
      ringNotificationPermission.value = granted;
      if (!granted) {
        ringNotificationsEnabled.value = false;
        await AppSettings.set('notifications_enabled', '0');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '系統通知權限未授予：請到 Android「設定 → 應用程式 → Homing → 通知」'
                '開啟後再試', // 文案草案
              ),
            ),
          );
        }
        if (mounted) setState(() {});
        return;
      }
    }
    ringNotificationsEnabled.value = value;
    await AppSettings.set('notifications_enabled', value ? '1' : '0');
    if (mounted) setState(() {});
  }

  Future<void> _setPreview(bool value) async {
    ringNotificationPreview.value = value;
    await AppSettings.set('notification_preview', value ? '1' : '0');
    if (mounted) setState(() {});
  }

  /// 第三十四批：來電橫幅偏好（開＝側邊橫幅；關＝僅系統通知欄提示）。
  Future<void> _setIncomingCallBanner(bool value) async {
    ringIncomingCallBanner.value = value;
    await AppSettings.set('incoming_call_banner', value ? '1' : '0');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('通知設定')), // 文案草案
      ),
      body: ListView(
        children: [
          // 批次十二②修：系統權限現狀（Android 13+ 無權限＝前面所有通知都不發）。
          ValueListenableBuilder<bool?>(
            valueListenable: ringNotificationPermission,
            builder: (cctx, granted, _) {
              final text = granted == null
                  ? '查詢中…'
                  : granted
                      ? '已授予'
                      : '未授予（通知不會彈出）'; // 文案草案
              return ListTile(
                leading: Icon(
                  granted == true ? AllIcons.notificationsActive : AllIcons.notificationsOff,
                ),
                title: Text('${S.t('系統通知權限：')}$text'), // 文案草案
                subtitle: Text(S.t('Android 13+ 需在系統彈框（或系統設定）授權')), // 草案文案
                trailing: granted == true
                    ? null
                    : TextButton(
                        // 拒絕後再按＝再次請求（已「不再詢問」時系統不彈框，
                        // 依訊息引導到系統設定）。
                        onPressed: () => unawaited(_requestAgain()),
                        child: Text(S.t('請求權限')), // 文案草案
                      ),
              );
            },
          ),
          const Divider(),
          // DC 結構（new_ref/settings/notification 紅框）：總開關＋說明文。
          SwitchListTile(
            title: Text(S.t('顯示通知')), // 文案草案
            subtitle: Text(S.t('關閉＝收到訊息時不發任何通知（App 內提醒不受影響）')), // 草案文案
            value: ringNotificationsEnabled.value,
            onChanged: (v) => unawaited(_setEnabled(v)),
          ),
          const Divider(),
          // Messages 區塊（人類紅框）：訊息通知正文顯示開關。
          ListTile(
            title: Text(
              S.t('訊息'),
              style: TextStyle(fontWeight: FontWeight.bold),
            ), // 文案草案
          ),
          SwitchListTile(
            title: Text(S.t('顯示訊息內容')), // 文案草案
            subtitle: Text(
              S.t('開＝通知顯示訊息文字；關＝只顯示「新訊息」（護隱私）'),
            ), // 草案文案
            value: ringNotificationPreview.value,
            onChanged: ringNotificationsEnabled.value
                ? (v) => unawaited(_setPreview(v))
                : null,
          ),
          const Divider(),
          // 第四十一批（LINE 版位＋三層通道）：推播區。
          ListTile(
            title: Text(S.t('推播'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          // 推播總開關（kv `push_enabled`，預設開）。
          SwitchListTile(
            title: Text(S.t('啟用推播')),
            subtitle: Text(
              S.t('關閉＝App 不再向 homeserver 註冊推播通道（僅前景收訊息）'),
            ),
            value: _pushEnabled,
            onChanged: (v) => unawaited(_setPushEnabled(v)),
          ),
          // 第七十八批（人類指示）：FCM 預設不開啟，使用者自行啟用。
          SwitchListTile(
            title: Text(S.t('使用 FCM 推播')),
            subtitle: Text(FcmRuntime.isAvailable ||
                FirebaseDefines.fromEnvironment().isComplete
                ? S.t('已偵測到 FCM 設定；開啟後向 Google 註冊推播通道')
                : S.t('此建置沒有 FCM 設定（google-services.json／dart-define），無法選用')),
            value: _fcmEnabled,
            // 第八十六批：只有 FCM 可用時才可選（預設關閉）。
            onChanged: (_pushEnabled &&
                (FcmRuntime.isAvailable ||
                    FirebaseDefines.fromEnvironment().isComplete))
                ? (v) => unawaited(_setFcm(v))
                : null,
          ),
          // 通道狀態（UnifiedPush → FCM → App 直接收）。
          PushChannelStatusTile(status: RingPushRuntime.channelStatus),
          // 第五十二批：舊版 Google FCM 端點已停用（實測 HTTP 404）→ 明確
          // 顯示警告，避免誤以為「FCM 已通」。
          //
          // ⚠️ **修正（2026-11-16 合併複核）**：原本**無條件**顯示 → 使用者
          // 的生效通道若是 **UnifiedPush**（不經 Google），根本不經 FCM 閘道，
          // 卻看到「FCM 閘道無法投遞」＝誤導。
          // → 只在**實際生效通道就是 FCM** 時顯示（即 App 真的把推播送進那個
          //   已停用的端點時）。診斷頁仍會列出 FCM 閘道 URL（那是診斷資訊，
          //   無條件顯示合理）。
          if (FcmRuntime.gatewayWarning != null &&
              RingPushRuntime.channelStatus.kind == PushChannelKind.fcm)
            ListTile(
              leading: Icon(AllIcons.warningAmberRounded),
              title: Text(S.t('FCM 閘道無法投遞')), // 文案草案
              subtitle: Text(FcmRuntime.gatewayWarning!),
              isThreeLine: true,
            ),
          ListTile(
            leading: Icon(AllIcons.infoOutline),
            title: Text(S.t('推播不含訊息內文')),
            subtitle: Text(
              S.t(
                '推播只帶 event_id，內容由 App 同步後自行解密顯示；'
                'FCM 需你自己的 Firebase 專案（設定方式見 README）',
              ),
            ),
          ),
          const Divider(),
          // 第八十六批：音效／視覺效果／震動（本機偏好）。
          ListTile(
            title: Text(
              S.t('音效與效果'),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ringSoundEnabled,
            builder: (context, v, _) => SwitchListTile(
              title: Text(S.t('通知音效')),
              value: v,
              onChanged: (nv) => unawaited(
                setEffect('effect_sound', nv, ringSoundEnabled),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ringVibration,
            builder: (context, v, _) => SwitchListTile(
              title: Text(S.t('震動')),
              value: v,
              onChanged: (nv) => unawaited(
                setEffect('effect_vibration', nv, ringVibration),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ringVisualEffects,
            builder: (context, v, _) => SwitchListTile(
              title: Text(S.t('視覺效果')),
              subtitle: Text(S.t('關閉＝減少動畫（系統「移除動畫」優先）')),
              value: v,
              onChanged: (nv) => unawaited(
                setEffect('effect_visual', nv, ringVisualEffects),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ringHighContrast,
            builder: (context, v, _) => SwitchListTile(
              title: Text(S.t('高對比模式')),
              subtitle: Text(S.t('提升文字與邊界對比（照顧低視能）')),
              value: v,
              onChanged: (nv) => unawaited(
                setEffect('high_contrast', nv, ringHighContrast),
              ),
            ),
          ),
          const Divider(),
          // 第三十四批（人類需求 #2）：通話區——來電顯示偏好（草案）。
          ListTile(
            title: Text(S.t('通話'), style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: Text(S.t('來電顯示')), // 文案草案
            subtitle: Text(
              S.t(
                '開＝來電在畫面旁邊以橫幅顯示（可接聽／拒接）；'
                '關＝不顯示橫幅，僅系統通知欄提示',
              ),
            ), // 草案文案
            value: ringIncomingCallBanner.value,
            onChanged: (v) => unawaited(_setIncomingCallBanner(v)),
          ),
          const Divider(),
          // 第四十二批：推播通道狀態（UnifiedPush → FCM → App 直接送）。
          PushChannelStatusTile(status: RingPushRuntime.channelStatus),
          const Divider(),
          // 披露：限制（Mentions／群組邀請分類——SDK notificationCount 未含
          // 提及類型判定；推播內容為 event_id_only，內文由 App 解密後顯示）。
          ListTile(
            leading: Icon(AllIcons.infoOutline),
            title: Text(S.t('推播不帶訊息內文')), // 草案文案
            subtitle: Text(
              '推播只帶 event_id，內容由 App 同步後自行解密顯示；'
              'Mentions／群組邀請分類待擴充',
            ), // 草案文案
          ),
        ],
      ),
    );
  }
}
