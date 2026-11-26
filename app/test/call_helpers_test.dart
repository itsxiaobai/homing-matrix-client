// P2.15 提案（人類指示 2026-11-01）— 通話純函式層測試。
//
// 範圍限制（說明，非「測試通過」宣稱）：
// * CallManager / CallScreen / MainShell 的 widget 級通話測試在本環境**不可行**：
//   flutter_webrtc 需要 Android/iOS 原生平台層（getUserMedia、RTCPeerConnection），
//   widget test 環境沒有 WebRTC platform 通道；強行初始化只會走 catch 分支。
// * 因此本檔僅涵蓋**純函式**：CallState → 顯示文案映射、通話計時格式。
//   通話行為（撥打／接聽／掛斷）待人類實機驗證。
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/voip/call_manager.dart';

void main() {
  group('callStateLabel（CallState → 草案文案映射）', () {
    test('每個 CallState 都有文案且不為空', () {
      for (final s in CallState.values) {
        final label = callStateLabel(s);
        expect(label, isNotEmpty, reason: '$s 應有非空文案');
      }
    });

    test('關鍵狀態映射正確', () {
      expect(callStateLabel(CallState.kRinging), contains('響鈴'));
      expect(callStateLabel(CallState.kConnected), contains('通話中'));
      expect(callStateLabel(CallState.kEnded), contains('已結束'));
    });
  });

  group('formatCallDuration', () {
    test('59 秒 → 00:59', () {
      expect(formatCallDuration(const Duration(seconds: 59)), '00:59');
    });

    test('65 秒 → 01:05', () {
      expect(formatCallDuration(const Duration(seconds: 65)), '01:05');
    });

    test('一小時內無時欄位：3599 秒 → 59:59', () {
      expect(formatCallDuration(const Duration(seconds: 3599)), '59:59');
    });

    test('一小時以上顯示 h:mm:ss：3675 秒 → 1:01:15', () {
      expect(formatCallDuration(const Duration(seconds: 3675)), '1:01:15');
    });
  });
}
