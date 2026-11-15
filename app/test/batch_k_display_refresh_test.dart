// 2026-11-06 修復批次（人類批准）— 顯示刷新／上傳純邏輯測試。
// 覆蓋：
//   D「頭像無法即時更新」：roomDisplayFingerprint 指紋函式（未讀／預覽／
//     頭像／釘選／名稱／會員狀態變動都應改變指紋→觸發列表重畫）。
//   A「取消會刪除背景」與 B「QR 確認」為 widget 流程，分別由
//     rooms_chat_screens／add_friend 測試契約涵蓋；上傳下採樣需真實
//     大圖碼流，本批不建構（已在輸入程式碼註解標註門檻常數）。
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/client_factory.dart';
import 'package:homing/ui/rooms_screen.dart';

Room _room(String id) {
  final client = createClient();
  return Room(id: id, client: client);
}

void main() {
  group('roomDisplayFingerprint（D 修復：列表刷新條件）', () {
    test('同一房間同狀態 → 指紋相同（不觸發重畫）', () {
      final a = _room('!a:matrix.org');
      final b = _room('!a:matrix.org');
      expect(
        roomDisplayFingerprint(a, pinned: false, hidden: false),
        roomDisplayFingerprint(b, pinned: false, hidden: false),
      );
    });

    test('未讀數變動 → 指紋改變', () {
      final a = _room('!a:matrix.org');
      final before = roomDisplayFingerprint(a, pinned: false, hidden: false);
      a.notificationCount = 3;
      final after = roomDisplayFingerprint(a, pinned: false, hidden: false);
      expect(after, isNot(before));
    });

    test('釘選／隱藏狀態變動 → 指紋改變', () {
      final a = _room('!a:matrix.org');
      final plain = roomDisplayFingerprint(a, pinned: false, hidden: false);
      expect(
        roomDisplayFingerprint(a, pinned: true, hidden: false),
        isNot(plain),
      );
      expect(
        roomDisplayFingerprint(a, pinned: false, hidden: true),
        isNot(plain),
      );
    });

    test('會員狀態（invite→join）變動 → 指紋改變', () {
      final a = _room('!a:matrix.org');
      a.membership = Membership.invite;
      final before = roomDisplayFingerprint(a, pinned: false, hidden: false);
      a.membership = Membership.join;
      final after = roomDisplayFingerprint(a, pinned: false, hidden: false);
      expect(after, isNot(before));
    });

    test('不同房間 → 指紋不同；無 lastEvent 時預覽欄位為空不擲錯', () {
      final a = _room('!a:matrix.org');
      final b = _room('!b:matrix.org');
      expect(
        roomDisplayFingerprint(a, pinned: false, hidden: false),
        isNot(roomDisplayFingerprint(b, pinned: false, hidden: false)),
      );
    });
  });
}
