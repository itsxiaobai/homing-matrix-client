// 貼圖包（zip）匯入安全驗證——藍圖 Phase 3.3 的單元測試。
// 覆蓋：格式白名單、路徑穿越、絕對路徑、manifest 欄位、shortcode 規則、
// 圖片檔頭預檢（尺寸／像素／動圖）、解壓炸彈（檔案數／大小／壓縮比）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/sticker_pack_importer.dart';

Uint8List _be32(int v) => Uint8List.fromList([
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);

/// RIFF/WebP chunk 長度為小端。
Uint8List _le32(int v) => Uint8List.fromList([
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ]);

/// 最小 PNG（僅檔頭 + IHDR + IEND；不做像素編碼）。
Uint8List _png(int width, int height, {bool animated = false}) {
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  // IHDR：13 bytes data（width/height/bitdepth/colortype/…）
  final ihdr = BytesBuilder()
    ..add(_be32(width))
    ..add(_be32(height))
    ..add([8, 6, 0, 0, 0]);
  out
    ..add(_be32(13))
    ..add('IHDR'.codeUnits)
    ..add(ihdr.takeBytes())
    ..add([0, 0, 0, 0]); // crc（不檢查）
  if (animated) {
    out
      ..add(_be32(8))
      ..add('acTL'.codeUnits)
      ..add(List<int>.filled(8, 0))
      ..add([0, 0, 0, 0]);
  }
  out
    ..add(_be32(0))
    ..add('IEND'.codeUnits)
    ..add([0, 0, 0, 0]);
  return out.toBytes();
}

/// 最小 WebP（VP8L，靜態）。
Uint8List _webp(int width, int height) {
  final out = BytesBuilder();
  out
    ..add('RIFF'.codeUnits)
    ..add(_le32(30))
    ..add('WEBP'.codeUnits)
    ..add('VP8L'.codeUnits)
    ..add(_le32(10));
  final bits = ((width - 1) & 0x3FFF) | (((height - 1) & 0x3FFF) << 14);
  out
    ..add([0x2f])
    ..add([
      bits & 0xFF,
      (bits >> 8) & 0xFF,
      (bits >> 16) & 0xFF,
      (bits >> 24) & 0xFF,
    ])
    ..add(List<int>.filled(5, 0));
  return out.toBytes();
}

/// 動畫 WebP（VP8X ＋ ANIM chunk；RIFF 長度為小端）。
Uint8List _webpAnimated(int width, int height) {
  final out = BytesBuilder();
  out
    ..add('RIFF'.codeUnits)
    ..add(_le32(40))
    ..add('WEBP'.codeUnits)
    ..add('VP8X'.codeUnits)
    ..add(_le32(10))
    ..add([0x02, 0, 0, 0]) // flags（animation）＋reserved
    ..add([(width - 1) & 0xFF, ((width - 1) >> 8) & 0xFF, 0])
    ..add([(height - 1) & 0xFF, ((height - 1) >> 8) & 0xFF, 0])
    ..add('ANIM'.codeUnits)
    ..add(_le32(6))
    ..add(List<int>.filled(6, 0));
  return out.toBytes();
}

Map<String, dynamic> _manifest({
  String specVersion = '1.0',
  String id = 'tw.example.catpack',
  String name = '貓咪日常',
  String author = '範例創作者',
  String license = 'CC-BY-4.0',
  String attribution = 'https://example.tw/catpack',
  List<Map<String, String>>? stickers,
  Map<String, dynamic>? extra,
}) =>
    <String, dynamic>{
      'spec_version': specVersion,
      'id': id,
      'name': name,
      'author': author,
      'license': license,
      'attribution': attribution,
      'usage': ['sticker'],
      'stickers': stickers ??
          [
            {'shortcode': 'cat_happy', 'file': 'stickers/001.png', 'body': '😺 開心'},
          ],
      ...?extra,
    };

Uint8List _zip(List<MapEntry<String, Uint8List>> files) {
  final archive = Archive();
  for (final f in files) {
    archive.addFile(ArchiveFile.bytes(f.key, f.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('parseStickerPack（合法）', () {
    test('①合法貼圖包 → 解析出欄位與尺寸', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(
              stickers: [
                {'shortcode': 'cat_happy', 'file': 'stickers/001.png', 'body': '😺 開心'},
                {'shortcode': 'cat_sad', 'file': 'stickers/002.webp', 'body': '😿 難過'},
              ],
            ))))),
        MapEntry('stickers/001.png', _png(512, 512)),
        MapEntry('stickers/002.webp', _webp(600, 400)),
        MapEntry('LICENSE.txt', Uint8List.fromList(utf8.encode('CC-BY-4.0'))),
      ]);
      final pack = parseStickerPack(zip);
      expect(pack.id, 'tw.example.catpack');
      expect(pack.name, '貓咪日常');
      expect(pack.author, '範例創作者');
      expect(pack.license, 'CC-BY-4.0');
      expect(pack.usage, ['sticker']);
      expect(pack.stickers.length, 2);
      expect(pack.stickers.first.shortcode, 'cat_happy');
      expect(pack.stickers.first.body, '😺 開心');
      expect(pack.stickers.first.mimeType, 'image/png');
      expect(pack.stickers.first.width, 512);
      expect(pack.stickers.last.mimeType, 'image/webp');
      expect(pack.stickers.last.height, 400);
    });

    test('②body 缺漏 → 以 shortcode 為預設', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(
              stickers: [
                {'shortcode': 'cat_sad', 'file': 'stickers/001.png'},
              ],
            ))))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      final pack = parseStickerPack(zip);
      expect(pack.stickers.single.body, 'cat_sad');
    });
  });

  group('parseStickerPack（拒收）', () {
    void expectRejected(Uint8List zip, Matcher message) {
      expect(
        () => parseStickerPack(zip),
        throwsA(
          isA<StickerPackException>().having((e) => e.message, 'message', message),
        ),
      );
    }

    test('①缺 manifest.json', () {
      expectRejected(
        _zip([MapEntry('stickers/001.png', _png(512, 512))]),
        contains('manifest'),
      );
    });

    test('②spec_version 不符', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(specVersion: '2.0'))))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      expectRejected(zip, contains('spec_version'));
    });

    test('③shortcode 重複', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(
              stickers: [
                {'shortcode': 'cat', 'file': 'stickers/001.png'},
                {'shortcode': 'cat', 'file': 'stickers/002.png'},
              ],
            ))))),
        MapEntry('stickers/001.png', _png(512, 512)),
        MapEntry('stickers/002.png', _png(512, 512)),
      ]);
      expectRejected(zip, contains('重複'));
    });

    test('④shortcode 格式非法', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(
              stickers: [
                {'shortcode': 'Cat Happy!', 'file': 'stickers/001.png'},
              ],
            ))))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      expectRejected(zip, contains('shortcode'));
    });

    test('⑤檔案不在 stickers/ 目錄', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(
              stickers: [
                {'shortcode': 'cat', 'file': '001.png'},
              ],
            ))))),
        MapEntry('001.png', _png(512, 512)),
      ]);
      expectRejected(zip, contains('不允許'));
    });

    test('⑥白名單外的檔案類型', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(512, 512)),
        MapEntry('stickers/evil.exe', Uint8List.fromList(utf8.encode('MZ'))),
      ]);
      expectRejected(zip, contains('不允許'));
    });

    test('⑦路徑穿越（..）', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/../../evil.png', _png(512, 512)),
      ]);
      expectRejected(zip, contains('..'));
    });

    test('⑧絕對路徑', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('/etc/evil.png', _png(512, 512)),
      ]);
      expectRejected(zip, contains('絕對路徑'));
    });

    test('⑨非 PNG／WebP 的圖片', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', Uint8List.fromList(utf8.encode('not an image'))),
      ]);
      expectRejected(zip, contains('PNG'));
    });

    test('⑩尺寸超過長邊上限', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(4096, 4096)),
      ]);
      expectRejected(zip, contains('長邊'));
    });

    test('⑪像素上限與長邊上限一致（2048×2048 邊界應通過）', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(2048, 2048)),
      ]);
      final pack = parseStickerPack(zip);
      expect(pack.stickers.single.width, 2048);
    });

    test('⑫動圖 PNG（APNG）拒收', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(512, 512, animated: true)),
      ]);
      expectRejected(zip, contains('動態'));
    });

    test('⑬動畫 WebP 拒收', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest(
              stickers: [
                {'shortcode': 'cat_anim', 'file': 'stickers/001.webp'},
              ],
            ))))),
        MapEntry('stickers/001.webp', _webpAnimated(512, 512)),
      ]);
      expectRejected(zip, contains('動態'));
    });

    test('⑭檔案數超過上限（以 limits 覆寫驗證）', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      expect(
        () => parseStickerPack(zip, limits: const StickerPackLimits(maxFileCount: 1)),
        throwsA(isA<StickerPackException>()),
      );
    });

    test('⑮壓縮比過高（以 limits 覆寫驗證）', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      expect(
        () => parseStickerPack(zip, limits: const StickerPackLimits(maxCompressionRatio: 1)),
        throwsA(isA<StickerPackException>()),
      );
    });

    test('⑯單檔過大（以 limits 覆寫驗證）', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      expect(
        () => parseStickerPack(zip, limits: const StickerPackLimits(maxSingleFileSize: 10)),
        throwsA(isA<StickerPackException>()),
      );
    });

    test('⑰空檔／非 zip', () {
      expect(
        () => parseStickerPack(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StickerPackException>()),
      );
    });
  });

  group('buildPackContent（STICKER_FORMAT.md §7 對映）', () {
    test('①images／pack 欄位對應', () {
      final zip = _zip([
        MapEntry('manifest.json', Uint8List.fromList(utf8.encode(jsonEncode(_manifest())))),
        MapEntry('stickers/001.png', _png(512, 512)),
      ]);
      final pack = parseStickerPack(zip);
      final content = buildPackContent(
        pack,
        {'cat_happy': 'mxc://example.org/abc'},
        {
          'cat_happy': {'w': 512, 'h': 512, 'mimetype': 'image/png', 'size': 100},
        },
      );
      final images = content['images'] as Map<String, dynamic>;
      final image = images['cat_happy'] as Map<String, dynamic>;
      expect(image['url'], 'mxc://example.org/abc');
      expect(image['body'], '😺 開心');
      final meta = content['pack'] as Map<String, dynamic>;
      expect(meta['display_name'], '貓咪日常');
      expect(meta['attribution'], '範例創作者 — https://example.tw/catpack');
      expect(meta['usage'], ['sticker']);
    });
  });
}
