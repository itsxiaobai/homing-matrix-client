// 第一百零二批：相簿卡片訊息（App 層約定，無新依賴）。
//
// Matrix 沒有「相簿卡片」標準訊息型別。為相容其他客戶端，這裡用官方
// `m.room.message` + `msgtype: m.notice`，並帶自訂欄位 `dev.homing.album`
// （Matrix 規格容忍未知欄位；Element 等會當成一般通知訊息顯示）。
// ⚠️ 卡片只帶「分組 id／名稱／照片 id」，**不帶本機檔案路徑**（相簿照片只存本機）。
import 'package:matrix/matrix.dart';

/// 自訂欄位名（ sending / parsing 共用，勿随意改名）。
const String kAlbumCardFlag = 'dev.homing.album';

class AlbumCardData {
  const AlbumCardData({
    required this.id,
    required this.name,
    required this.photoIds,
  });

  final String id;
  final String name;
  final List<String> photoIds;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'photoIds': photoIds,
      };
}

/// 是否為相簿卡片事件（讀不到＝false）。
bool isAlbumCardEvent(Event? event) {
  if (event == null) return false;
  return event.content[kAlbumCardFlag] is Map;
}

/// 解析卡片資料；格式不正確回 null。
AlbumCardData? parseAlbumCardEvent(Event? event) {
  if (event == null) return null;
  final raw = event.content[kAlbumCardFlag];
  if (raw is! Map) return null;
  final id = raw['id'];
  final name = raw['name'];
  final ids = raw['photoIds'];
  if (id is! String || name is! String || name.isEmpty) return null;
  final photoIds = <String>[];
  if (ids is List) {
    for (final item in ids) {
      if (item is String) photoIds.add(item);
    }
  }
  return AlbumCardData(id: id, name: name, photoIds: photoIds);
}

/// 組出卡片訊息內容（[body] 讓呼叫端決定語言）。
Map<String, dynamic> buildAlbumCardContent({
  required String body,
  required String id,
  required String name,
  required List<String> photoIds,
}) {
  return <String, dynamic>{
    'msgtype': 'm.notice',
    'body': body,
    kAlbumCardFlag: AlbumCardData(
      id: id,
      name: name,
      photoIds: photoIds,
    ).toJson(),
  };
}
