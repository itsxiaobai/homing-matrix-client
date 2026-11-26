// 第三十批 — LiveKit v0 純函式單元測試：/sfu/get 回應解析、參與者 identity
// 對映、famedly 成員 state 的 livekit call_id 抽取（groupCallId 兩端一致）。
// 全部零網路、零加密邏輯（解析與字串組裝而已）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/voip/livekit_call_manager.dart';

void main() {
  group('parseSfuGetResponse', () {
    test('200 正常回應 {url, jwt} 可解析', () {
      final got = parseSfuGetResponse(
        <String, Object?>{
          'url': 'wss://livekit.example.com',
          'jwt': 'eyJxxx.yyy.zzz',
          'extra': 'ignored',
        },
      );
      expect(got.url, 'wss://livekit.example.com');
      expect(got.jwt, 'eyJxxx.yyy.zzz');
    });

    test('缺 url 欄位丟 FormatException', () {
      expect(
        () => parseSfuGetResponse(<String, Object?>{'jwt': 'x'}),
        throwsFormatException,
      );
    });

    test('url 空字串丟 FormatException', () {
      expect(
        () => parseSfuGetResponse(
          <String, Object?>{'url': '', 'jwt': 'x'},
        ),
        throwsFormatException,
      );
    });

    test('jwt 非字串丟 FormatException', () {
      expect(
        () => parseSfuGetResponse(
          <String, Object?>{'url': 'wss://a.b', 'jwt': 42},
        ),
        throwsFormatException,
      );
    });
  });

  group('lkParticipantIdentity', () {
    test('有 deviceId → <userId>:<deviceId>', () {
      expect(
        lkParticipantIdentity('@a:matrix.org', 'ABCD1234'),
        '@a:matrix.org:ABCD1234',
      );
    });

    test('deviceId null → 僅 userId', () {
      expect(lkParticipantIdentity('@a:matrix.org', null), '@a:matrix.org');
    });

    test('deviceId 空字串 → 僅 userId', () {
      expect(lkParticipantIdentity('@a:matrix.org', ''), '@a:matrix.org');
    });
  });

  group('deriveLiveKitGroupCallIdFromContent', () {
    test('抽取 livekit membership 的 call_id', () {
      final got = deriveLiveKitGroupCallIdFromContent(<String, Object?>{
        'memberships': [
          <String, Object?>{
            'call_id': 'lk:!room:matrix.org',
            'foci_active': [
              <String, Object?>{'type': 'livekit'},
            ],
          },
        ],
      });
      expect(got, 'lk:!room:matrix.org');
    });

    test('mesh membership（非 livekit）回 null', () {
      final got = deriveLiveKitGroupCallIdFromContent(<String, Object?>{
        'memberships': [
          <String, Object?>{
            'call_id': '…',
            'foci_active': [
              <String, Object?>{'type': 'mesh'},
            ],
          },
        ],
      });
      expect(got, isNull);
    });

    test('空內容回 null', () {
      expect(deriveLiveKitGroupCallIdFromContent({}), isNull);
    });

    test('memberships 非清單回 null', () {
      expect(
        deriveLiveKitGroupCallIdFromContent(<String, Object?>{
          'memberships': 'oops',
        }),
        isNull,
      );
    });
  });
}
