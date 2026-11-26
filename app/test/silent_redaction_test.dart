// 第七十批（無痕收回）：純邏輯測試（不碰 sqflite／SDK Event）。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/silent_redaction.dart';

void main() {
  group('無痕收回（第七十批）', () {
    test('reason 旗標辨識', () {
      expect(isSilentRedactionContent(null), isFalse);
      expect(isSilentRedactionContent(const <String, Object?>{}), isFalse);
      expect(
        isSilentRedactionContent(const <String, Object?>{'reason': '一般收回'}),
        isFalse,
      );
      expect(
        isSilentRedactionContent(<String, Object?>{
          'reason': silentRedactionReason(),
        }),
        isTrue,
      );
      expect(
        isSilentRedactionContent(<String, Object?>{
          'reason': '前綴 $kSilentRedactionMarker 後綴',
        }),
        isTrue,
      );
    });

    test('id 集合解析／序列化（含壞資料）', () {
      expect(parseSilentRedactionIds(null), isEmpty);
      expect(parseSilentRedactionIds('not json'), isEmpty);
      expect(parseSilentRedactionIds('[1, "a", "b", "a"]'), {'a', 'b'});
      final encoded = encodeSilentRedactionIds({'b', 'a'});
      expect(parseSilentRedactionIds(encoded), {'a', 'b'});
    });
  });
}
