// 2026-11-21：另存資料夾（Android SAF ACTION_OPEN_DOCUMENT_TREE）。
// 首次選資料夾 → 永久 Uri 權限存本機 kv → 之後下載一律寫入該資料夾。
// 不碰加密／金鑰；純本機檔案寫入（Android 原生 API，零新 pub 依賴）。
import 'package:flutter/services.dart';

import 'app_settings.dart';

class SaveLocation {
  SaveLocation._();

  static const MethodChannel _channel = MethodChannel('homing/save_location');
  static const String _kFolderUri = 'save_folder_uri';

  /// 已設定的資料夾 Uri（null／空＝尚未設定）。
  static Future<String?> get folderUri async {
    try {
      final raw = await AppSettings.get(_kFolderUri);
      return (raw == null || raw.isEmpty) ? null : raw;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> get isConfigured async => await folderUri != null;

  /// 開啟系統資料夾選擇器；成功後寫入 kv 並回傳 Uri。
  static Future<String?> pickFolder() async {
    try {
      final uri = await _channel.invokeMethod<String>('pick_folder');
      if (uri != null && uri.isNotEmpty) {
        try {
          await AppSettings.set(_kFolderUri, uri);
        } catch (_) {
          // kv 寫入失敗：本 session 仍可用（Uri 已取得永久權限）。
        }
      }
      return uri;
    } on PlatformException {
      return null;
    }
  }

  /// 清除設定（uri 權限仍在系統，但 App 不再使用）。
  static Future<void> clear() async {
    try {
      await AppSettings.set(_kFolderUri, '');
    } catch (_) {}
  }

  /// 寫入已設定資料夾。回傳 (ok, 檔名)；未設定資料夾時 ok=false。
  static Future<({bool ok, String? name})> saveBytes({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    final uri = await folderUri;
    if (uri == null) return (ok: false, name: null);
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'save_bytes',
        <String, Object?>{'uri': uri, 'name': name, 'mime': mime, 'bytes': bytes},
      );
      return (ok: true, name: result?['name'] as String? ?? name);
    } on PlatformException {
      return (ok: false, name: null);
    }
  }
}
