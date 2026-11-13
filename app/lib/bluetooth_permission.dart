// 第十八批（人類批准 2026-11-07「是」）：BLUETOOTH_CONNECT runtime 權限
// （Android 12+/API 31 起必需）——通話「選擇音訊輸出」sheet 列舉藍牙放音
// 裝置的前提（AudioSwitch 無此權限時 availableAudioDevices() 永不含藍牙）。
// 走 `ring/permissions` channel（MainActivity.kt 新增；框架
// Activity.requestPermissions，零新依賴，同批次十二②通知權限模式）。
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

const MethodChannel _permChannel = MethodChannel('homing/permissions');

/// 是否已取得 BLUETOOTH_CONNECT（非 Android → true：無此權限概念；
/// channel 異常（如測試環境）→ true，不擋通話流程，僅列內建裝置）。
Future<bool> bluetoothPermissionGranted() async {
  if (!Platform.isAndroid) {
    return true;
  }
  try {
    return await _permChannel.invokeMethod<bool>('check_bluetooth') ?? true;
  } catch (_) {
    return true;
  }
}

/// 請求 BLUETOOTH_CONNECT；回傳授予與否（非 Android → true；
/// 已授權 → true 不彈框；拒絕／channel 異常 → false）。
/// 呼叫端（兩份通話 sheet）在請求後才枚舉，拒絕時顯示「沒有偵測到外部
/// 放音裝置」提示文案（草案）。
Future<bool> requestBluetoothPermission() async {
  if (!Platform.isAndroid) {
    return true;
  }
  try {
    return await _permChannel.invokeMethod<bool>('request_bluetooth') ?? false;
  } catch (_) {
    return false;
  }
}

// ─── 第二十批：②-A 根因修（繞過 AudioSwitch fork 清單維護）──────────────
// 進程內診斷（APK 2020，2026-11-08 00:26 截圖）定案：BLUETOOTH_CONNECT 已授
// （perm=granted）且系統 `getAvailableCommunicationDevices()` 列出筆電耳機
// （user-ThinkPad-P1-Gen-3, bluetooth_sco）——框架沒藏藍牙；缺的是 fork
// AudioSwitch 自己那份清單（AudioDeviceScanner 的 callback 狀態與系統脫節）。
// Android 12+ 起改用官方 AudioManager 溝通裝置 API 自建枚舉＋選擇；
// Android 11 以下維持 1.6.3 舊路徑（batch 13/17）。

/// 自建枚舉的單項（isCurrent＝目前溝通裝置，供 sheet radio 預選）。
class AudioOutputOption {
  const AudioOutputOption({
    required this.id,
    required this.name,
    required this.isCurrent,
  });

  /// 溝通裝置型別名（bluetooth_sco／ble_headset／wired_headset…；
  /// 即 sheet 外部分組的 kind 識別）。
  final String id;

  /// 裝置名（`productName`；無名 → 空字串，由呼叫端 fallback）。
  final String name;

  /// 是否為當前溝通裝置。
  final bool isCurrent;
}

/// 自建枚舉：Android 12+ 官方溝通裝置清單。
/// 非支援（非 Android／< Android 12）／channel 異常 → null
/// （呼叫端回退 1.6.3 舊路徑；不清單空兩者有別）。
Future<List<AudioOutputOption>?> enumerateCommunicationDevices() async {
  if (!Platform.isAndroid) {
    return null;
  }
  try {
    final raw =
        await _permChannel.invokeMethod<Map<Object?, Object?>>(
      'list_audio_outputs',
    );
    if (raw == null || raw['supported'] != true) {
      return null;
    }
    final list = raw['devices'];
    if (list is! List) {
      return null;
    }
    final out = <AudioOutputOption>[];
    for (final m in list.whereType<Map>()) {
      final id = m['typeName'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      out.add(
        AudioOutputOption(
          id: id,
          name: m['name'] as String? ?? '',
          isCurrent: m['isCurrent'] == true,
        ),
      );
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// 自建選擇：官方 `AudioManager.setCommunicationDevice`（Android 12+），
/// 原生端「套用後回讀溝通裝置型別」二次驗證。
/// true＝已套用並驗證；false＝不支援（<S）／裝置斷線（系統清單無此型別）／
/// 驗證失敗；null＝channel 異常（也視為不支援）。
Future<bool?> setCommunicationDevice(String id) async {
  if (!Platform.isAndroid) {
    return null;
  }
  try {
    return await _permChannel.invokeMethod<bool>(
      'set_communication_device',
      <String, String>{'typeName': id},
    );
  } catch (_) {
    return null;
  }
}

// ─── 第十九批：②-A 決定性診斷（臨時除錯元件；已除役——sheet 除錯列於
// 第二十批移除；本通道（audio_diagnostics）保留一輪作為 field 診斷工具，
// 路由確認後下批整段移除）───────
// 上面兩個函式只管「權限」，AudioSwitch 列舉失敗時無從分辨「是權限沒進
// process，還是框架層把藍牙藏掉」。`bluetoothAudioDiagnosticsText()` 繞開
// AudioSwitch，直接讀 App 進程內的系統視角（Kotlin `audio_diagnostics`，
// 唯讀 framework API）：BLUETOOTH_CONNECT 狀態、AudioManager 原始輸出清單、
// Android 12+ 另附當前溝通裝置／候選／音訊模式。
//
/// 診斷文字（直接顯示於 sheet 底部除錯列草案）；非 Android、channel 異常
/// 或回傳異常 → null（sheet 不顯示該列）。
Future<String?> bluetoothAudioDiagnosticsText() async {
  if (!Platform.isAndroid) {
    return null;
  }
  String device(String name, String typeName) =>
      name.isEmpty ? typeName : '$name ($typeName)';
  try {
    final raw =
        await _permChannel.invokeMethod<Map<Object?, Object?>>(
      'audio_diagnostics',
    );
    if (raw == null) {
      return null;
    }
    final sb = StringBuffer('音訊診斷（臨時除錯）\n'); // 文案草案
    sb.write(
      'perm=${raw['permissionGranted'] == true ? 'granted' : 'not-granted'} '
      'mode=${raw['audioMode'] ?? '?'}\n',
    );
    final comm = raw['communicationDevice'];
    if (comm is Map) {
      sb.write(
        'comm=${device(comm['name'] as String? ?? '', comm['typeName'] as String? ?? '?')}\n',
      );
    }
    final candidates = raw['communicationDevices'];
    if (candidates is List && candidates.isNotEmpty) {
      sb.write(
        'comm 候選: '
        '${candidates.whereType<Map>().map((m) => device(m['name'] as String? ?? '', m['typeName'] as String? ?? '?')).join(' · ')}\n',
      );
    }
    final outputs = raw['outputDevices'];
    if (outputs is List) {
      sb.write('原始輸出清單:\n');
      if (outputs.isEmpty) {
        sb.write('- (空清單)\n');
      }
      for (final m in outputs.whereType<Map>()) {
        sb.write(
          '- ${device(m['name'] as String? ?? '', m['typeName'] as String? ?? '?')}\n',
        );
      }
    } else {
      sb.write('原始輸出清單: 無資料\n');
    }
    return sb.toString();
  } catch (_) {
    return null;
  }
}
