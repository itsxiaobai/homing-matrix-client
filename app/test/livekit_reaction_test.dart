// 第三十二批（人類批准 2026-11-10）— LiveKit 批 31 修：倒數規則＋表情符號
// payload 純函式測試。零新依賴。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homing/voip/livekit_call_manager.dart';

void main() {
  group('第三十一批 B｜其他人已離開倒數（第三十二批規則修）', () {
    test('曾見遠端＋連線中＋遠端歸零 → 倒數', () {
      expect(
        LiveKitCallManager.othersLeftShouldCountdown(
          sawRemoteParticipant: true,
          remoteParticipantCount: 0,
          connected: true,
        ),
        isTrue,
      );
    });
    test('未見過任何遠端（發起人獨自等待）→ 永不倒數', () {
      expect(
        LiveKitCallManager.othersLeftShouldCountdown(
          sawRemoteParticipant: false,
          remoteParticipantCount: 0,
          connected: true,
        ),
        isFalse,
      );
    });
    test('遠端仍在 → 不倒數', () {
      expect(
        LiveKitCallManager.othersLeftShouldCountdown(
          sawRemoteParticipant: true,
          remoteParticipantCount: 2,
          connected: true,
        ),
        isFalse,
      );
    });
    test('非連線中（join/err等多種）→ 不倒數', () {
      expect(
        LiveKitCallManager.othersLeftShouldCountdown(
          sawRemoteParticipant: true,
          remoteParticipantCount: 0,
          connected: false,
        ),
        isFalse,
      );
    });
  });

  group('第三十二批⑥｜通話表情符號 payload（純函式）', () {
    test('encode→decode 往返一致', () {
      const payload = '{"kind":"reaction","emoji":"👍","identity":"a:DEV","ts":123}';
      final data = utf8.encode(payload);
      final decoded = liveKitReactionDecode(data);
      expect(decoded, isNotNull);
      expect(decoded!.identity, 'a:DEV');
      expect(decoded.emoji, '👍');
    });
    test('kind 不符 → null（完整丟棄，不瞎猜）', () {
      final data = utf8.encode(
        jsonEncode({'kind': 'other', 'emoji': '👍', 'identity': 'a'}),
      );
      expect(liveKitReactionDecode(data), isNull);
    });
    test('缺欄位／空字串 → null', () {
      expect(liveKitReactionDecode(utf8.encode(jsonEncode({'kind': 'reaction'}))), isNull);
      expect(
        liveKitReactionDecode(utf8.encode(jsonEncode({'kind': 'reaction', 'emoji': '', 'identity': 'a'}))),
        isNull,
      );
      expect(
        liveKitReactionDecode(utf8.encode(jsonEncode({'kind': 'reaction', 'emoji': '👍', 'identity': ''}))),
        isNull,
      );
    });
    test('非 JSON／非 Map → null 不炸', () {
      expect(liveKitReactionDecode(utf8.encode('not json')), isNull);
      expect(liveKitReactionDecode(utf8.encode('[1,2,3]')), isNull);
    });
  });
}
