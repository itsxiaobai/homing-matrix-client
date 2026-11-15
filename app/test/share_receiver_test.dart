// 第二十六批（人類拍板 2026-11-08）：外部分享接收載體測試。
// 覆蓋：SharePayload.parse（文字／檔案／缺欄位／null）、textOnly 工廠、
// pushShare 廣播流（空 payload 不推）。
// 注意：native `ring/share` channel handler（平台 share 呼叫 → parse → 流）
// 屬 Kotlin／實機層；本測試環境以 handlePlatformMessage 模擬平台訊息會造成
// 事件迴圈不停止（10 分鐘逾時——observed 2026-11-09），此橋接由實機驗證，
// 不放進 Dart 測試（payload 自身邏輯即 parse 端，已在此覆蓋）。
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/share_receiver.dart';

void main() {
  test('SharePayload.parse：文字＋檔案清單完整解析', () {
    final payload = SharePayload.parse(<Object?, Object?>{
      'text': '看看這個',
      'files': [
        <String, Object?>{
          'path': '/cache/ring_share/a.png',
          'name': 'a.png',
          'mimeType': 'image/png',
          'sizeBytes': 3,
        },
        <String, Object?>{
          'path': '/cache/ring_share/b.mp4',
          'name': 'b.mp4',
          'mimeType': 'video/mp4',
          'sizeBytes': 4,
        },
      ],
    });
    expect(payload.text, '看看這個');
    expect(payload.files, hasLength(2));
    expect(payload.files[0].path, '/cache/ring_share/a.png');
    expect(payload.files[0].name, 'a.png');
    expect(payload.files[0].mimeType, 'image/png');
    expect(payload.files[0].sizeBytes, 3);
    expect(payload.files[1].sizeBytes, 4);
    expect(payload.isEmpty, isFalse);
  });

  test('SharePayload.parse：null／空 map／壞列＝空 payload', () {
    expect(SharePayload.parse(null).isEmpty, isTrue);
    expect(SharePayload.parse(<Object?, Object?>{}).isEmpty, isTrue);
    // 有文字無檔案：files 空、isEmpty false。
    final textOnly = SharePayload.parse(<Object?, Object?>{'text': 'x'});
    expect(textOnly.files, isEmpty);
    expect(textOnly.isEmpty, isFalse);
    // 檔案缺 path → 該檔跳過（不猜路徑）。
    final skipped = SharePayload.parse(<Object?, Object?>{
      'files': [<String, Object?>{'name': 'x'}],
    });
    expect(skipped.files, isEmpty);
    expect(skipped.isEmpty, isTrue);
  });

  test('SharePayload.parse：檔案缺欄位走預設值', () {
    final payload = SharePayload.parse(<Object?, Object?>{
      'files': [<String, Object?>{'path': '/cache/ring_share/x'}],
    });
    expect(payload.files, hasLength(1));
    expect(payload.files.single.name, 'ring_share');
    expect(payload.files.single.mimeType, 'application/octet-stream');
    expect(payload.files.single.sizeBytes, 0);
  });

  test('SharePayload.textOnly：純文字（app_links VIEW uri 路線）', () {
    final payload = SharePayload.textOnly('https://matrix.to/#/!r:example.org');
    expect(payload.text, 'https://matrix.to/#/!r:example.org');
    expect(payload.files, isEmpty);
    expect(payload.isEmpty, isFalse);
  });

  test('pushShare：空 payload 不推流；非空 payload 推一次', () async {
    final received = <SharePayload>[];
    final sub = shareReceiverStream.listen(received.add);
    pushShare(const SharePayload(text: null, files: <SharedItem>[]));
    pushShare(
      const SharePayload(
        text: null,
        files: <SharedItem>[
          SharedItem(
            path: '/cache/ring_share/a',
            name: 'a',
            mimeType: 'application/octet-stream',
            sizeBytes: 1,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    expect(received.single.files.single.path, '/cache/ring_share/a');
    await sub.cancel();
  });
}
