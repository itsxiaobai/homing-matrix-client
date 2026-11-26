// 主題包（zip）驗證——單元測試（藍圖 §九第 13 項）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/theme_pack_importer.dart';

Uint8List _be32(int v) => Uint8List.fromList([
      (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF,
    ]);

Uint8List _png(int w, int h) {
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = BytesBuilder()
    ..add(_be32(w))
    ..add(_be32(h))
    ..add([8, 6, 0, 0, 0]);
  out
    ..add(_be32(13))
    ..add('IHDR'.codeUnits)
    ..add(ihdr.takeBytes())
    ..add([0, 0, 0, 0])
    ..add(_be32(0))
    ..add('IEND'.codeUnits)
    ..add([0, 0, 0, 0]);
  return out.toBytes();
}

Uint8List _zip(List<MapEntry<String, Uint8List>> files) {
  final archive = Archive();
  for (final f in files) {
    archive.addFile(ArchiveFile.bytes(f.key, f.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

Map<String, dynamic> _theme({
  String spec = '1.0',
  Map<String, dynamic>? colors,
  Map<String, dynamic>? assets,
}) =>
    <String, dynamic>{
      'spec_version': spec,
      'id': 'tw.example.dusk',
      'name': '暮色',
      'author': '創作者',
      'license': 'CC-BY-4.0',
      'attribution': 'https://example.tw/dusk',
      'colors': ?colors,
      'assets': ?assets,
    };

void main() {
  group('parseThemePack（合法）', () {
    test('①合法主題包 → 解析出欄位', () {
      final zip = _zip([
        MapEntry('theme.json', Uint8List.fromList(utf8.encode(jsonEncode(_theme(
              colors: <String, dynamic>{'seed': '#FFBD9F'},
              assets: <String, dynamic>{
                'wallpaper_light': 'wallpaper/light.png',
              },
            ))))),
        MapEntry('wallpaper/light.png', _png(1200, 1200)),
      ]);
      final pack = parseThemePack(zip);
      expect(pack.id, 'tw.example.dusk');
      expect(pack.name, '暮色');
      expect(pack.colors['seed'], '#FFBD9F');
      expect(pack.assets['wallpaper_light'], 'wallpaper/light.png');
    });
  });

  group('parseThemePack（拒收）', () {
    void expectRejected(Uint8List zip, Matcher message) {
      expect(
        () => parseThemePack(zip),
        throwsA(
          isA<ThemePackException>().having((e) => e.message, 'message', message),
        ),
      );
    }

    test('①缺 theme.json', () {
      expectRejected(_zip([MapEntry('wallpaper/light.png', _png(1200, 1200))]),
          contains('theme.json'));
    });

    test('②spec_version 不符', () {
      expectRejected(
        _zip([MapEntry('theme.json',
            Uint8List.fromList(utf8.encode(jsonEncode(_theme(spec: '2.0')))))]),
        contains('spec_version'),
      );
    });

    test('③路徑穿越（..）', () {
      expectRejected(
        _zip([
          MapEntry('theme.json',
              Uint8List.fromList(utf8.encode(jsonEncode(_theme())))),
          MapEntry('wallpaper/../evil.png', _png(1200, 1200)),
        ]),
        contains('不安全'),
      );
    });

    test('④白名單外的檔案', () {
      expectRejected(
        _zip([
          MapEntry('theme.json',
              Uint8List.fromList(utf8.encode(jsonEncode(_theme())))),
          MapEntry('other/evil.exe', Uint8List.fromList([1, 2, 3])),
        ]),
        contains('不允許'),
      );
    });

    test('⑤色彩格式錯誤', () {
      expectRejected(
        _zip([MapEntry('theme.json', Uint8List.fromList(utf8.encode(jsonEncode(
              _theme(colors: <String, dynamic>{'seed': 'FFBD9F'})))))]),
        contains('#RRGGBB'),
      );
    });

    test('⑥桌布尺寸超限', () {
      expectRejected(
        _zip([
          MapEntry('theme.json', Uint8List.fromList(utf8.encode(jsonEncode(_theme(
                assets: <String, dynamic>{
                  'wallpaper_light': 'wallpaper/light.png',
                },
              ))))),
          MapEntry('wallpaper/light.png', _png(5000, 5000)),
        ]),
        contains('長邊'),
      );
    });

    test('⑦資產檔不存在', () {
      expectRejected(
        _zip([MapEntry('theme.json', Uint8List.fromList(utf8.encode(jsonEncode(_theme(
              assets: <String, dynamic>{
                'wallpaper_light': 'wallpaper/light.png',
              },
            )))))]),
        contains('不存在'),
      );
    });

    test('⑧非 zip', () {
      expectRejected(Uint8List.fromList([1, 2, 3]), contains('有效的 zip'));
    });
  });
}
