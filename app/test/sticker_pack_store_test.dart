// 貼圖庫房間（藍圖 3.11）與 pack 事件 content 組裝——單元測試。
// 對映規格：STICKER_FORMAT.md §7。
import 'package:flutter_test/flutter_test.dart';
import 'package:homing/sticker_pack_store.dart';

void main() {
  group('buildPackContentForRoom', () {
    test('①images／pack 欄位對映（STICKER_FORMAT.md §7）', () {
      final content = StickerPackStore.buildPackContentForRoom(
        packMeta: <String, dynamic>{
          'id': 'tw.example.catpack',
          'name': '貓咪日常',
          'author': '範例創作者',
          'attribution': 'https://example.tw/catpack',
          'usage': <String>['sticker'],
        },
        stickers: <Map<String, dynamic>>[
          <String, dynamic>{
            'shortcode': 'cat_happy',
            'body': '😺 開心',
            'url': 'mxc://example.org/abc',
            'info': <String, dynamic>{'w': 512, 'h': 512},
          },
        ],
      );
      final images = content['images'] as Map<String, dynamic>;
      final image = images['cat_happy'] as Map<String, dynamic>;
      expect(image['url'], 'mxc://example.org/abc');
      expect(image['body'], '😺 開心');
      expect((image['info'] as Map)['w'], 512);
      final pack = content['pack'] as Map<String, dynamic>;
      expect(pack['display_name'], '貓咪日常');
      expect(pack['attribution'], '範例創作者 — https://example.tw/catpack');
      expect(pack['usage'], <String>['sticker']);
    });

    test('②缺 shortcode／url 的項目略過；無 attribution 時不產生空欄位', () {
      final content = StickerPackStore.buildPackContentForRoom(
        packMeta: <String, dynamic>{'id': 'x', 'name': 'X'},
        stickers: <Map<String, dynamic>>[
          <String, dynamic>{'shortcode': '', 'url': 'mxc://a'},
          <String, dynamic>{'shortcode': 'ok', 'url': ''},
          <String, dynamic>{'shortcode': 'good', 'url': 'mxc://b'},
        ],
      );
      final images = content['images'] as Map<String, dynamic>;
      expect(images.keys, <String>['good']);
      final pack = content['pack'] as Map<String, dynamic>;
      expect(pack.containsKey('attribution'), isFalse);
      expect(pack.containsKey('usage'), isFalse);
    });
  });

  group('常數', () {
    test('①事件型別為 Matrix v1.19 穩定名', () {
      expect(StickerPackStore.kPackStateType, 'm.room.image_pack');
      expect(StickerPackStore.kPackAccountDataType, 'm.image_pack.rooms');
    });
  });
}
