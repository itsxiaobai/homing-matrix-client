// 第二十六批（人類拍板 2026-11-08）：外部「檔案型」分享接收整線。
// 背景披露：批十三 v0 只經 app_links（VIEW 類 intent，連結／文字 uri）；
// 而 AndroidManifest 早已宣告 ACTION_SEND——檔案分享 intent 落入 MainActivity
// 後無人消費（人類實測「外部檔案分享功能仍然沒完成」）。
// 本批：MainActivity.kt `ring/share` MethodChannel——onCreate 冷啟動分享暫存
// （Dart 端 MainShell 首掛以 [readInitialShare] 讀取即清；未登入時即在 native
// 暫存，登入後 MainShell 掛起自動開 picker＝人類拍板）、onNewIntent 熱啟動
// 即時推送；檔案由 ContentResolver 複製到 cacheDir 後回傳絕對路徑。
// 零新 pub 依賴、零新 OS 權限（intent 自帶 FLAG_GRANT_READ_URI_PERMISSION）。
// 參考（僅結構語意）：LINE_ref/new_ref/share_EX（EX Send-to picker 中繼欄
// 保持原樣，picker 本體見 share_to_room_screen.dart）。
import 'dart:async';

import 'package:flutter/services.dart';

/// 單一分享檔案（MainActivity 複製到 cacheDir 後的絕對路徑；讀取雜湊與
/// 上傳由 Dart 端 SDK 官方鏈處理，見 share_to_room_screen.dart）。
class SharedItem {
  const SharedItem({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  /// cacheDir 內複製檔的絕對路徑（content:// URI 已轉成本檔可讀）。
  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;

  static SharedItem? fromMap(Object? raw) {
    if (raw is Map) {
      final path = raw['path'];
      if (path is String && path.isNotEmpty) {
        return SharedItem(
          path: path,
          name: (raw['name'] as String?) ?? 'ring_share',
          mimeType: (raw['mimeType'] as String?) ?? 'application/octet-stream',
          sizeBytes: (raw['sizeBytes'] as int?) ?? 0,
        );
      }
    }
    return null;
  }
}

/// 一次分享的內容（文字與檔案可並存）。
class SharePayload {
  const SharePayload({this.text, this.files = const <SharedItem>[]});

  /// EXTRA_TEXT（app_links 的 uri 分享也走此欄位＝文字 only）。
  final String? text;
  final List<SharedItem> files;

  bool get isEmpty => (text == null || text!.isEmpty) && files.isEmpty;

  /// 純文字分享（app_links VIEW uri 等）。
  factory SharePayload.textOnly(String value) =>
      SharePayload(text: value, files: const <SharedItem>[]);

  factory SharePayload.parse(Object? raw) {
    String? text;
    var files = const <SharedItem>[];
    if (raw is Map) {
      final t = raw['text'];
      if (t is String && t.isNotEmpty) {
        text = t;
      }
      final list = raw['files'];
      if (list is List) {
        files = <SharedItem>[
          for (final entry in list) ?SharedItem.fromMap(entry),
        ];
      }
    }
    return SharePayload(text: text, files: files);
  }
}

/// `ring/share` MethodChannel（與 MainActivity.kt 對接）。
const MethodChannel shareReceiveChannel = MethodChannel('homing/share');

/// 熱啟動分享廣播流（MainShell 訂閱；冷啟動分享不走這裡，直接讀 native 暫存）。
final StreamController<SharePayload> _shareStream =
    StreamController<SharePayload>.broadcast();

Stream<SharePayload> get shareReceiverStream => _shareStream.stream;

void pushShare(SharePayload payload) {
  if (!payload.isEmpty) {
    _shareStream.add(payload);
  }
}

/// 冷啟動分享：MainActivity onCreate 暫存的 intent payload。
/// 未登入時 share 也停在這裡（native 暫存）→ 登入後 MainShell 首掛讀取即開
/// picker（人類拍板）。讀取後 native 暫存即清（不重複）。
Future<SharePayload?> readInitialShare() async {
  try {
    final args = await shareReceiveChannel.invokeMethod('get_initial');
    return SharePayload.parse(args);
  } on Object {
    // channel 未註冊／平台不支援：視同無分享。
    return null;
  }
}

/// 熱啟動訂閱：由 main.dart 在啟動時指定（channel handler 一次性設定）。
/// handler 同步 parse＋轉推（不 async：避免 messenger 回包路徑多餘排幀）。
void startShareReceiver(void Function(SharePayload payload) onShare) {
  shareReceiveChannel.setMethodCallHandler((call) {
    if (call.method == 'share') {
      pushShare(SharePayload.parse(call.arguments));
    }
    return Future.value(null);
  });
}
