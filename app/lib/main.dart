// 任務：Phase 0 / 0.10 — 應用入口：進入「選擇 homeserver」骨架畫面
// Phase 1 / 1.3：連線成功後導向登入畫面（網頁註冊連結由伺服器提供）。
// 2026-10-31（人類批准）：啟動時嘗試還原既有 session（方案 C 持久化），
//   成功則直接進主殼（MainShell：聊天／聯絡人／設定），避免每次重新登入。
// 2026-11-01（UI 重構，人類 LINE_ref 標註）：登入成功／還原 session 改導向
//   MainShell（底部 3 tab）。
// 主題（批次 H 修訂 2026-11-02，人類決定）：預設一律 Homing 種子色 #FFBD9F
//（Android 12+ 桌布動態取色**預設關閉**＝修「顏色被 Android 設定吃掉」；
// 外觀頁開啟「跟隨 Android 桌布配色」才採 dynamic_color 該來的系統色）。
// 自訂字型（批次 H）：外觀頁匯入 ttf/otf → FontLoader（官方 services API）
// 全 App fontFamily 即時生效；啟動時從 font_path 還原。
// 版面骨架仍為「草案，待人類設計」；元件不寫死寬度。
// 1.5（人類批准 2026-10-31）：啟動時先載入官方 vodozemac 加密引擎
// （`vod.init()` 僅呼叫 SDK 官方初始化；不寫任何加密／金鑰邏輯）。
// 引擎未就緒時 App 仍可運作（僅無加密，與現狀一致）。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'package:matrix/matrix.dart';
// 第三十五批 #1（人類批准依賴＋2026-11-12 拍板 Web/desktop 支援）：Web 端
// 本機資料層——sqflite 官方同源生態的 IndexedDB 後端（見 pubspec 註解）。
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'
    show databaseFactoryFfiWeb;

import 'auth.dart';
import 'client_factory.dart';
import 'engine_init.dart';
import 'ui/design_tokens.dart';
import 'ui/login_screen.dart';
import 'ui/main_shell.dart';
import 'app_settings.dart';

// 第 2 點：接收外部分享（文字/檔案）→ 選擇聊天室。
// 第二十六批：接收載體改 SharePayload（檔案型走 MainActivity `ring/share`
// channel，見 share_receiver.dart；app_links 仍收 VIEW 連結 → 文字 only）。
import 'package:app_links/app_links.dart';
import 'share_receiver.dart';

/// 人類指定之品牌種子色（2026-10-31；不採用 LINE 綠）
const _ringSeedColor = Color(0xFFFFBD9F);

Future<void> _initShareReceiver() async {
  // 第二十六批：檔案型分享原生通道——熱啟動（onNewIntent）事件進廣播流；
  // 冷啟動分享停在 native 暫存（MainShell 首掛 readInitialShare 讀取即清，
  // 人類拍板「未登入先暫存，登入後自動開 picker」）。
  startShareReceiver(pushShare);
  try {
    final appLinks = AppLinks();
    // 冷啟動：取得啟動時的初始 uri（若有）。
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      pushShare(SharePayload.textOnly(initialUri.toString()));
    }
    // 熱啟動：監聽後續傳入 uri。
    appLinks.uriLinkStream.listen((uri) {
      pushShare(SharePayload.textOnly(uri.toString()));
    }, onError: (err) {
      // 忽略平台端錯誤。
    });
  } on Exception {
    // app_links 在不支援的平台上可能拋例外；靜默忽略。
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 第三十五批 #1：Web 資料層——官方用法「set the factory once, before
  // opening any database」（sqflite_common_ffi_web README；IndexedDB 後端）。
  // 非本機平台（web）不支援 dart:io SQLite，故僅 kIsWeb 分支設定。
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  final vodReady = await _initVodozemac();
  final restored = await _tryRestoreSession();
  final seedHex = await AppSettings.get('theme_seed_color');
  // Suggestion #4：啟動即把已存種子色灌入 notifier（外觀頁之後可即時改）。
  ringSeedColor.value = seedHex;
  // 批次 H：字型／動態色開關背景還原（不阻擋啟動；AppSettings 失敗＝預設值）。
  unawaited(_loadAppearanceSettings());
  // 第 2 點：初始化外部分享接收器（uni_links 監聽 Android intent）。
  unawaited(_initShareReceiver());
  runApp(RingApp(vodozemacReady: vodReady, restoredClient: restored, seedColorHex: seedHex));

/// 第 2 點：監聽 Android  external app 分享進來的 uri / text。


}

/// 批次 H：種子色主題**純函式**（供單元測試直呼；RingApp 的 _fromSeed 走它）。
/// 第二十一批（人類 2026-11-08 拍板「深色用純黑」）：深色主題頁面底色改純黑
/// （design_tokens.kDarkSurface）；淺色維持種子色系統（「淺色用預設或使用者
/// 調整顏色」）→ 淺色路徑完全不改。其他 M3 容器（卡片／sheet）維持種子派生
/// 深灰，頁面底／AppBar／Scaffold 走 surface＝純黑（草案，待實機定稿）。
ThemeData ringTheme(
  Brightness brightness, {
  required Color seedColor,
  String? fontFamily,
}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
    fontFamily: fontFamily, // 批次 H：自訂字型（null＝平台預設）
  );
  if (brightness == Brightness.dark) {
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(surface: kDarkSurface),
      scaffoldBackgroundColor: kDarkSurface,
    );
  }
  return base;
}

/// 批次 H：外觀執行緒（零依賴 ValueNotifier；外觀頁匯入後即時生效）。
/// fontFamily null＝未載入（平台預設字型）；useDynamicColor false＝Homing 種子色。
final ValueNotifier<String?> ringFontFamily = ValueNotifier<String?>(null);
final ValueNotifier<bool> ringUseDynamicColor = ValueNotifier<bool>(false);

/// 批次 I①：文字大小（TextScaler.linear）與深淺模式（ThemeMode）。
/// 預設 1.0／跟隨系統；外觀頁可調（可及時生效）。
final ValueNotifier<double> ringTextScale = ValueNotifier<double>(0.9);
final ValueNotifier<ThemeMode> ringThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Suggestion #4「主題色應要能即時改變」（人類回饋 2026-11-03）：
/// 自訂種子色走同一 ValueNotifier 通道（hex 或 null＝預設）；外觀頁變更
/// → MaterialApp 同 frame 重建（同 ringTextScale 模式，零新依賴）。
final ValueNotifier<String?> ringSeedColor = ValueNotifier<String?>(null);

/// FontLoader 內註冊的 runtime family 名（草案常量；匯入即以同一家族載入）。
const String kRingFontFamily = 'ringCustom';

/// 外觀設定 kv key（與 appearance_screen 共用字面值；勿隨意改）。
const String kSettingFontPath = 'font_path';
const String kSettingUseDynamicColor = 'use_dynamic_color';

/// 啟動／匯入時把 ttf/otf 註冊進引擎（官方 FontLoader；失敗靜默＝維持可運作）。
Future<bool> applyRingFontFromPath(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    final Uint8List bytes = await file.readAsBytes();
    return await applyRingFontFromBytes(bytes);
  } catch (_) {
    return false;
  }
}

/// 測試縫：直接由 bytes 載入（正式一律走 applyRingFontFromPath）。
Future<bool> applyRingFontFromBytes(Uint8List bytes) async {
  try {
    final loader = FontLoader(kRingFontFamily)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    ringFontFamily.value = kRingFontFamily;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _loadAppearanceSettings() async {
  try {
    final path = await AppSettings.get(kSettingFontPath);
    if (path != null) {
      await applyRingFontFromPath(path);
    }
  } catch (_) {}
  try {
    final v = await AppSettings.get(kSettingUseDynamicColor);
    ringUseDynamicColor.value = v == '1';
  } catch (_) {}
  try {
    final v = await AppSettings.get('text_scale');
    final d = double.tryParse(v ?? '');
    if (d != null) {
      // 第 5 點（人類回報 2026-11-03「標準字型仍然過大」）：裝置上已持久化
      // 舊字級值，改「預設值」對已存值的裝置完全無效。舊字階（0.9/1.0/1.15/
      // 1.3/1.7）→ 新字階各下移一檔，並以 `text_scale_migrated` 戳記**只跑一次**
      //（否則使用者重選後每次啟動都會再位移，愈用愈小）。
      final migrated = await AppSettings.get('text_scale_migrated');
      if (migrated != '1') {
        final shift = <double, double>{
          1.7: 1.3,
          1.3: 1.15,
          1.15: 1.0,
          1.0: 0.9,
          0.9: 0.75,
        };
        final applied = shift[d] ?? d;
        ringTextScale.value = applied;
        await AppSettings.set('text_scale', applied.toString());
        await AppSettings.set('text_scale_migrated', '1');
      } else {
        ringTextScale.value = d;
      }
    }
  } catch (_) {}
  try {
    final v = await AppSettings.get('theme_mode');
    switch (v) {
      case 'light':
        ringThemeMode.value = ThemeMode.light;
      case 'dark':
        ringThemeMode.value = ThemeMode.dark;
      default:
        ringThemeMode.value = ThemeMode.system;
    }
  } catch (_) {}
}

/// 載入官方 vodozemac 原生引擎；失敗不阻擋 App（僅無加密）。
// 第二十七批（人類拍板）：引擎初始化改防禦＋記錄（engine_init.dart）——
// 失敗自動重試一次、原因落 kv 旗標（MainShell 提示＋設定診斷可見）；
// 不再靜默。加密演算法／金鑰本體零接觸（仍是官方 vod.init()）。
Future<bool> _initVodozemac() {
  // 第三十五批 #1（Web 白屏根因，2026-11-12 瀏覽器實證）：flutter_vodozemac
  // 0.9.1 官方套件未宣告 web 平台（無 web 目錄、未隨附 runtime
  // pkg/vodozemac_bindings_dart.js＋wasm）→ `vod.init()` 在 web 於 loader
  // 404 後卡住不返回，main() 永遠到不了 runApp＝白屏。依 1.5 既有原則
  // 「引擎未就緒時 App 仍可運作（僅無加密）」：Web 端跳過引擎初始化
  // （**披露：Web 目前無加密**）。非 web 平台行為不變。
  if (kIsWeb) return Future.value(false);
  return initRustEngine(init: vod.init);
}

/// 嘗試還原既有 session（方案 C：sqflite + secure storage）。
/// 失敗／無 session → 回傳 null，走正常登入流程。
///
/// Issues「軟體重新開啟時要求重新登入（需要再重開）」根因（重分析）：
/// 冷啟動時裝置 IO／首次 DB 讀取慢——`init` 逾時（舊值 8 秒）會被外層
/// catch 成「無 session」→ 導向登入頁；第二次啟動快取已熱 → 成功，
/// 看起來就是「要重開一次才正常」。修正（人類批准 2026-11-06）：
/// 逾時**逐次拉長重試**（12s→30s→60s，共三輪）；只有在確認
/// `isLogged() == false`（secure storage 真的沒有 token）時才走登入。
/// 已知限制：三輪都逾時的最後一道防線仍是登入頁（本專案不引入背景
/// 常駐重試服務）；真機 log 顯示逾時常源自大事件查詢被首頁渲染拖住，
/// 60s 已遠超過去實測的最長恢復時間（⚠️待查證：30s 上限是推測值）。
Future<Client?> _tryRestoreSession() async {
  const timeouts = [
    Duration(seconds: 12),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];
  for (var attempt = 0; attempt < timeouts.length; attempt++) {
    Client? client;
    try {
      client = await createPersistentClient();
      await client
          .init(waitUntilLoadCompletedLoaded: false)
          .timeout(timeouts[attempt]);
      // 確保 cross-signing / 裝置金鑰與帳號資料（SSSS secret refs）已載入，
      // 否則恢復流程的 selfSign 會被跳過、裝置維持未驗證。
      // （逾時不視為失敗：金鑰可於進入主殼後繼續載入。）
      if (client.userDeviceKeysLoading != null) {
        await client.userDeviceKeysLoading!
            .timeout(const Duration(seconds: 5))
            .catchError((_) {});
      }
      if (client.accountDataLoading != null) {
        await client.accountDataLoading!
            .timeout(const Duration(seconds: 5))
            .catchError((_) {});
      }
      if (client.isLogged()) {
        return client;
      }
      // `init` 正常完成且確認無 token → 真的沒有 session，不再重試。
      return null;
    } on TimeoutException {
      unawaited(client?.dispose()); // 逾時 → 清理半初始化 client，重試。
      continue;
    } catch (_) {
      unawaited(client?.dispose());
      // 其他錯誤（DB 鎖／損毀暫態）→ 重試一次；再失敗才走登入。
      if (attempt == timeouts.length - 1) return null;
    }
  }
  return null;
}

class RingApp extends StatelessWidget {
  const RingApp({super.key, required this.vodozemacReady, this.restoredClient, this.seedColorHex});

  /// vodozemac 官方引擎是否成功載入（供診斷／後續畫面使用；目前不影響導向）。
  final bool vodozemacReady;

  /// 啟動時還原的既有 session（若有）。
  final Client? restoredClient;

  /// 使用者自訂種子色（hex 字串，null 則用預設 #FFBD9F）。
  final String? seedColorHex;

  @override
  Widget build(BuildContext context) {
    // 批次 H：外觀執行緒（ringFontFamily／ringUseDynamicColor）任一變動
    // → MaterialApp 立即以新主題重建（人類批准「導入即生效」）。
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => AnimatedBuilder(
        animation: Listenable.merge([
          ringFontFamily,
          ringUseDynamicColor,
          ringTextScale,
          ringThemeMode,
          ringSeedColor, // Suggestion #4：主題色即時改變。
        ]),
        builder: (context, _) => _buildRoot(lightDynamic, darkDynamic),
      ),
    );
  }

  Widget _buildRoot(ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
    // 批次 H（人類決定）：動態取色預設**關閉**（Homing 種子色恆定）；
    // 外觀頁開關開啟且系統有提供時才採桌布衍生色。
    final dynamicAvailable =
        ringUseDynamicColor.value && lightDynamic != null && darkDynamic != null;
    final font = ringFontFamily.value;
    // 批次 I②（人類指示）：登入頁整合「選擇伺服器＋測試連線＋帳密登入」，
    // 送出一站式（先測後登入）→ 流程不再經過 ConnectScreen
    // （ConnectScreen 保留：connect_screen_widget_test 仍涵蓋其骨架功能）。
    final Widget home = restoredClient != null
        ? MainShell(client: restoredClient!)
        : Builder(
            builder: (context) => LoginScreen(
              homeserver: defaultHomeserver,
              onLoggedIn: (client) {
                // 1.4：登入成功 → 主殼（聊天列表 tab）。
                Navigator.of(context, rootNavigator: true).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => MainShell(client: client),
                  ),
                );
              },
            ),
          );
    final Widget root = MaterialApp(
      title: 'Homing', // 文案／字型待 UI 定稿
      theme: dynamicAvailable
          ? _fromScheme(lightDynamic, fontFamily: font)
          : _fromSeed(Brightness.light, fontFamily: font),
      darkTheme: dynamicAvailable
          ? _fromScheme(darkDynamic, fontFamily: font)
          : _fromSeed(Brightness.dark, fontFamily: font),
      themeMode: ringThemeMode.value,
      builder: (context, child) {
        // 批次 I①：文字大小（TextScaler.linear）全 App 套用。
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(ringTextScale.value),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: home,
    );
    return root;
  }

  Color get _seedColor {
    // Suggestion #4：值來源改走 ringSeedColor notifier（啟動時由 seedColorHex
    // 初始化；之後外觀頁變更即時生效，不再需重啟）。
    final hexStr = ringSeedColor.value ?? seedColorHex;
    if (hexStr == null) return _ringSeedColor;
    final hex = hexStr.replaceFirst('#', '');
    final val = int.tryParse(hex, radix: 16);
    if (val == null) return _ringSeedColor;
    return Color(val | 0xFF000000);
  }

  ThemeData _fromSeed(Brightness brightness, {String? fontFamily}) =>
      ringTheme(
        brightness,
        seedColor: _seedColor,
        fontFamily: fontFamily, // 批次 H：自訂字型（null＝平台預設）
      );

  ThemeData _fromScheme(ColorScheme scheme, {String? fontFamily}) =>
      ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: fontFamily);
}
