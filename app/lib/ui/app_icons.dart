// 圖示變數化（第五十七批・人類指示「圖片也『類似』方式處理（作為變數，
// 使用者可在主題包更換圖示）」）。
//
// 設計（與 i18n 字串表平行）：
// * **不直接使用 Icons.xxx**，而是走 `AppIcons.chat`／`AppIcons.call` 等具名槽位；
// * 預設值為 Material IconData → **零新依賴**；
// * 主題包可在 `theme.json` 的 `icons` 欄位指定：
//   - Material 名稱：`"chat": "chat_bubble_outline"`
//   - 自訂字型：`"chat": {"font": "icons.ttf", "codepoint": "e001"}`
//     （字型需由主題包提供，並以 Flutter 官方 `FontLoader` 載入；授權⚠️待查證）
// * 覆寫只影響**使用 AppIcons 槽位**的地方（其他地方維持 Material 圖示）→
//   屬漸進式遷移，不一次改完全部 128 種圖示。
library;

import 'package:flutter/material.dart';

import 'app_icons_generated.dart'
    show kAllIconSlotNames, kAllMaterialIconByName;

/// 圖示槽位名稱（主題包 `icons` 的 key 必須是這些名稱之一）。
class AppIconName {
  const AppIconName._();

  static const String chat = 'chat';
  static const String chatFilled = 'chat_filled';
  static const String contacts = 'contacts';
  static const String contactsFilled = 'contacts_filled';
  static const String call = 'call';
  static const String callFilled = 'call_filled';
  static const String settings = 'settings';
  static const String search = 'search';
  static const String back = 'back';
  static const String menu = 'menu';
  static const String send = 'send';
  static const String sticker = 'sticker';
  static const String attach = 'attach';
  static const String camera = 'camera';
  static const String more = 'more';
  static const String block = 'block';
  static const String report = 'report';
  static const String delete = 'delete';
  static const String edit = 'edit';
  static const String logout = 'logout';

  /// 所有合法槽位（供驗證用）。
  static const Set<String> all = {
    chat, chatFilled, contacts, contactsFilled, call, callFilled, settings,
    search, back, menu, send, sticker, attach, camera, more, block, report,
    delete, edit, logout,
  };
}

/// 圖示覆寫（由主題包套用；**目前行程有效**）。
final Map<String, IconData> _overrides = <String, IconData>{};

/// 通用解析（供自動產生的 `AllIcons` getter 與主題包驗證使用）：
/// ① 主題包覆寫 → ② 全數 Material 圖示表 → ③ 後備圖示。
IconData appIcon(String name) =>
    _overrides[name] ?? kAllMaterialIconByName[name] ?? Icons.help_outline;

/// 註冊圖示覆寫（只接受合法槽位）。
void setAppIconOverride(String name, IconData icon) {
  // 接受兩類：①20 個具名別名（chat/call/...）②130 個 Material 圖示名稱
  // （全數替換後的主槽位）。缺一都會讓既有測試／舊主題包失效。
  if (!kAllIconSlotNames.contains(name) && !AppIconName.all.contains(name)) {
    return;
  }
  _overrides[name] = icon;
}

/// 清除全部覆寫（切換回預設主題時呼叫）。
void clearAppIconOverrides() => _overrides.clear();

/// 目前是否有覆寫（診斷用）。
bool get hasAppIconOverrides => _overrides.isNotEmpty;

/// 主題包 `icons` 的 Material 名稱 → IconData 對照表。///
/// 只收錄本專案實際會用到的名稱；其他名稱**不猜**（回 null → 主題包驗證失敗）。
const Map<String, IconData> kMaterialIconByName = <String, IconData>{
  'chat_bubble_outline': Icons.chat_bubble_outline,
  'chat_bubble': Icons.chat_bubble,
  'person_outline': Icons.person_outline,
  'person': Icons.person,
  'people_outline': Icons.people_outline,
  'call_outlined': Icons.call_outlined,
  'call': Icons.call,
  'settings_outlined': Icons.settings_outlined,
  'settings': Icons.settings,
  'search': Icons.search,
  'arrow_back': Icons.arrow_back,
  'menu': Icons.menu,
  'send': Icons.send,
  'insert_emoticon_outlined': Icons.insert_emoticon_outlined,
  'emoji_emotions_outlined': Icons.emoji_emotions_outlined,
  'attach_file': Icons.attach_file,
  'add_photo_alternate_outlined': Icons.add_photo_alternate_outlined,
  'photo_camera_outlined': Icons.photo_camera_outlined,
  'more_vert': Icons.more_vert,
  'block': Icons.block,
  'report_outlined': Icons.report_outlined,
  'delete_outline': Icons.delete_outline,
  'edit_outlined': Icons.edit_outlined,
  'logout': Icons.logout,
};

/// 由主題包的 Material 名稱解析 IconData（查無 → null）。
IconData? materialIconByName(String name) =>
    kAllMaterialIconByName[name] ?? kMaterialIconByName[name];

/// 套用主題包的圖示覆寫（Material 名稱）。
///
/// 先清掉前一個主題的覆寫 → 即使新主題沒有 `icons` 也會**還原預設圖示**。
void applyThemeIconOverrides(Map<String, String> icons) {
  clearAppIconOverrides();
  for (final entry in icons.entries) {
    final icon = materialIconByName(entry.value);
    if (icon != null) {
      setAppIconOverride(entry.key, icon);
    }
  }
}

/// 由自訂字型建立 IconData（字型需已由 `FontLoader` 註冊）。
///
/// ⚠️ Flutter 3.47 的 `IconData` 建構子要求常數參數（`non_const_argument_for_const_parameter`
/// 警告）；此處**必須**接受執行期傳入的字型名與碼位（主題包動態載入）→ 明確忽略。
IconData fontIcon(String fontFamily, int codePoint) =>
    // ignore: non_const_argument_for_const_parameter
    IconData(codePoint, fontFamily: fontFamily);

/// 圖示槽位（**UI 應使用這些 getter 而非直接 `Icons.*`**，才能被主題包替換）。
class AppIcons {
  AppIcons._();

  static IconData _slot(String name, IconData fallback) =>
      _overrides[name] ?? fallback;

  static IconData get chat => _slot(AppIconName.chat, Icons.chat_bubble_outline);
  static IconData get chatFilled => _slot(AppIconName.chatFilled, Icons.chat_bubble);
  static IconData get contacts => _slot(AppIconName.contacts, Icons.person_outline);
  static IconData get contactsFilled => _slot(AppIconName.contactsFilled, Icons.person);
  static IconData get call => _slot(AppIconName.call, Icons.call_outlined);
  static IconData get callFilled => _slot(AppIconName.callFilled, Icons.call);
  static IconData get settings => _slot(AppIconName.settings, Icons.settings_outlined);
  static IconData get search => _slot(AppIconName.search, Icons.search);
  static IconData get back => _slot(AppIconName.back, Icons.arrow_back);
  static IconData get menu => _slot(AppIconName.menu, Icons.menu);
  static IconData get send => _slot(AppIconName.send, Icons.send);
  static IconData get sticker => _slot(AppIconName.sticker, Icons.emoji_emotions_outlined);
  static IconData get attach => _slot(AppIconName.attach, Icons.attach_file);
  static IconData get camera => _slot(AppIconName.camera, Icons.photo_camera_outlined);
  static IconData get more => _slot(AppIconName.more, Icons.more_vert);
  static IconData get block => _slot(AppIconName.block, Icons.block);
  static IconData get report => _slot(AppIconName.report, Icons.report_outlined);
  static IconData get delete => _slot(AppIconName.delete, Icons.delete_outline);
  static IconData get edit => _slot(AppIconName.edit, Icons.edit_outlined);
  static IconData get logout => _slot(AppIconName.logout, Icons.logout);
}
