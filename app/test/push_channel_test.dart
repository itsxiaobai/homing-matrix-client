// 推播三層通道規則（第四十二批）——單元測試。
// 規則（人類指示）：UnifiedPush → FCM → App 直接送。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/push/push_channel.dart';

void main() {
  test('①UnifiedPush 可用 → 第一層（不經 Google）', () {
    final s = describePushChannel(
      unifiedPushReady: true,
      fcmAvailable: true,
    );
    expect(s.kind, PushChannelKind.unifiedPush);
    expect(s.canWakeApp, isTrue);
    expect(s.label, contains('UnifiedPush'));
  });

  test('②僅 FCM 可用 → 第二層', () {
    final s = describePushChannel(
      unifiedPushReady: false,
      fcmAvailable: true,
    );
    expect(s.kind, PushChannelKind.fcm);
    expect(s.canWakeApp, isTrue);
  });

  test('③兩者皆不可用 → 第三層 App 直接收（無法喚醒 App）', () {
    final s = describePushChannel(
      unifiedPushReady: false,
      fcmAvailable: false,
    );
    expect(s.kind, PushChannelKind.inApp);
    expect(s.canWakeApp, isFalse);
    expect(s.detail, contains('不會收到通知'));
  });
}
