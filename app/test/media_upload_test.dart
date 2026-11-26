// 2.8（bugfix）— 背景 isolate 上傳輔助的純邏輯測試（不打網路、不碰金鑰流程）。
// EXIF 摘除案例使用官方 image 套件（與實作同版本）造出帶 EXIF 的 JPEG。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as iimg;
import 'package:matrix/matrix.dart';

import 'package:homing/media_upload.dart';

/// 造一張 64x48、帶 EXIF（Artist metadata，與 GPS 走同一 ExifData 容器、
/// 同一 _writeAPP1 回寫機制）的 JPEG——驗證輸入側，使測試自證。
Uint8List _generateExifJpeg() {
  final image = iimg.Image(width: 64, height: 48);
  image.exif.imageIfd['Artist'] = 'ring-test-exif';
  return iimg.encodeJpg(image);
}

bool _isJpegBytesPublic(Uint8List data) =>
    data.lengthInBytes >= 2 && data[0] == 0xFF && data[1] == 0xD8;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isImageFileName / isVideoFileName', () {
    test('副檔名分類', () {
      expect(isImageFileName('photo.jpg'), isTrue);
      expect(isImageFileName('clip.MP4'), isFalse);
      expect(isVideoFileName('clip.mp4'), isTrue);
      expect(isVideoFileName('photo.jpg'), isFalse);
      expect(isVideoFileName('video.MKV'), isTrue);
    });
  });

  group('prepareImageInBackground', () {
    test('小圖（1x1 PNG）預處理成功，不產生 thumbnail', () async {
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGP4z8AARwzEcQCukw/x0F8jngAAAABJRU5ErkJggg==';
      final bytes = Uint8List.fromList(base64Decode(pngBase64));
      final image = await prepareImageInBackground(bytes: bytes, name: 'tiny.png');
      expect(image, isNotNull);
      expect(image!.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      expect(image.thumbnailBytes, isNull);
    });

    // EXIF 摘除（人類批准 2026-11-06 方案 C）：JPEG 一律重編丟 EXIF。
    test('帶 EXIF 的 JPEG 預處理後輸出無 EXIF 且為 JPEG', () async {
      final testJpeg = _generateExifJpeg();
      // 輸入側自證：造出的 JPEG 確實帶 EXIF（Artist；GPS 走同一 ExifData
      // 容器與同一 _writeAPP1 回寫機制，摘除粒度＝整個 exif 容器）。
      final decodedSrc = iimg.decodeImage(testJpeg);
      expect(decodedSrc!.exif.imageIfd['Artist'], isNotNull);

      final result =
          await prepareImageInBackground(bytes: testJpeg, name: 'photo.jpg');
      expect(result, isNotNull);
      expect(result!.upload, isNotNull); // ≤1920px 小圖也要被重編（淨化不縮放）。
      final clean = result.upload!;
      expect(_isJpegBytesPublic(clean.bytes), isTrue);
      final decoded = iimg.decodeImage(clean.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.exif.imageIfd.keys, isEmpty); // EXIF 全摘除。
      expect(clean.width, result.width);
      expect(clean.mimeType, 'image/jpeg');
    });
  });

  group('PreEncryptedUpload', () {
    test('UploadImageFile 使用預先注入的 EncryptedFile', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final encrypted = EncryptedFile(
        data: Uint8List(32),
        k: 'k',
        iv: 'iv',
        sha256: 'sha',
      );
      final file = UploadImageFile(
        bytes: bytes,
        name: 'x.jpg',
        preEncrypted: encrypted,
      );
      final result = await file.encrypt();
      expect(result, same(encrypted));
    });

    test('UploadPlainFile 未提供 preEncrypted 時 fallback 官方 encrypt', () {
      final file = UploadPlainFile(
        bytes: Uint8List(4),
        name: 'x.bin',
      );
      expect(file.preEncrypted, isNull);
    });
  });
}
