// 第七十三批（人類指示「GIF 開關」）：貼圖動畫偏好（前庭障礙 A2-3）。
// 預設「自動播放」＝一般使用者體驗不變；開啟後貼圖只顯示**靜態首幀**。
// 不新增依賴（dart:ui 解碼首幀）、不碰加密邏輯。
import 'package:flutter/foundation.dart';

import 'app_settings.dart';

const String _kKey = 'static_sticker_frame';

/// true＝貼圖只顯示靜態首幀（不播放 GIF／APNG 動畫）。
final ValueNotifier<bool> ringStaticStickers = ValueNotifier<bool>(false);

Future<void> loadStickerMotionPref() async {
  try {
    ringStaticStickers.value = (await AppSettings.get(_kKey)) == '1';
  } on Object {
    ringStaticStickers.value = false;
  }
}

Future<void> setStaticStickers(bool enabled) async {
  ringStaticStickers.value = enabled;
  await AppSettings.set(_kKey, enabled ? '1' : '0');
}
