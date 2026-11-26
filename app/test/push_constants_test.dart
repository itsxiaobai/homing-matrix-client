// 推播常數一致性——第四十一批的單元測試。
//
// 重點：Matrix pusher 的 `app_id` 必須與 Android `applicationId` 一致
// （批次 33 改名後曾殘留 `com.example.ring`，導致推播導向錯誤的 App 設定）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/push/push_constants.dart';

void main() {
  test('①pusher app_id 為反向域名且與 applicationId 一致', () {
    expect(kPushAppId, 'io.github.itsxiaobai');
    expect(kPushAppId, contains('.'));
    expect(kPushAppId.startsWith('io.github.'), isTrue);
    expect(kPushAppId, isNot('com.example.ring')); // 舊值已失效
  });

  test('②FCM pusher endpoint 為 FCM 官方端點', () {
    expect(kFcmPusherUrl, startsWith('https://fcm.googleapis.com/'));
  });
}
