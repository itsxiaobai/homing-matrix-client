// 第八十八批（人類指示）：相簿——**只存本機 App 專屬目錄**，不送伺服器、
// 不要求「讀取所有照片」權限（用 file_picker 選檔 → 複製到 App 沙箱）。
// 保護隱私、舊裝置可跑。每張：id／本機路徑／標題／addedAt。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';

const String kAlbumKey = 'local_album';

/// 第一百零二批：相簿**分組**（名稱＋照片 id）。另開 kv，完全不影響
/// `kAlbumKey` 既有扁平照片清單。只存本機；卡片訊息只帶 id／名稱，不帶本機路徑。
const String kAlbumGroupsKey = 'local_album_groups';

class AlbumGroup {
  const AlbumGroup({
    required this.id,
    required this.name,
    required this.photoIds,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<String> photoIds;
  final int createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'photoIds': photoIds,
        'createdAt': createdAt,
      };

  static AlbumGroup? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    final name = v['name'];
    final ids = v['photoIds'];
    final ts = v['createdAt'];
    if (id is! String || name is! String || ts is! int) return null;
    final photoIds = <String>[];
    if (ids is List) {
      for (final item in ids) {
        if (item is String) photoIds.add(item);
      }
    }
    return AlbumGroup(
      id: id,
      name: name,
      photoIds: photoIds,
      createdAt: ts,
    );
  }
}

List<AlbumGroup> parseAlbumGroups(String? raw) {
  if (raw == null || raw.isEmpty) return <AlbumGroup>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <AlbumGroup>[];
    return decoded
        .map(AlbumGroup.fromJson)
        .whereType<AlbumGroup>()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  } on Object {
    return <AlbumGroup>[];
  }
}

String encodeAlbumGroups(List<AlbumGroup> groups) =>
    jsonEncode(<Object?>[for (final g in groups) g.toJson()]);

Future<List<AlbumGroup>> loadAlbumGroups() async {
  try {
    return parseAlbumGroups(await AppSettings.get(kAlbumGroupsKey));
  } on Object {
    return <AlbumGroup>[];
  }
}

Future<void> saveAlbumGroups(List<AlbumGroup> groups) async {
  await AppSettings.set(kAlbumGroupsKey, encodeAlbumGroups(groups));
}

/// 建立相簿分組（回傳新分組）。照片本身已由 importPhoto／importPhotoBytes
/// 存進本機相簿，這裡只記「哪些 id 屬於這本相簿」。
Future<AlbumGroup> createAlbumGroup(String name, List<String> photoIds) async {
  final group = AlbumGroup(
    id: '${DateTime.now().microsecondsSinceEpoch}',
    name: name,
    photoIds: List<String>.of(photoIds),
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
  final all = await loadAlbumGroups();
  await saveAlbumGroups(<AlbumGroup>[group, ...all]);
  return group;
}

/// 從位元組匯入聊天圖片（長按圖片 → 加入相簿用；不帶本機路徑到伺服器）。
Future<AlbumPhoto> importPhotoBytes(
  Uint8List bytes, {
  String? title,
  String extension = '.jpg',
}) async {
  final dir = await _albumDir();
  final id = '${DateTime.now().microsecondsSinceEpoch}';
  final ext = extension.startsWith('.') ? extension : '.$extension';
  final dest = File('${dir.path}/$id$ext');
  await dest.writeAsBytes(bytes);
  return AlbumPhoto(
    id: id,
    path: dest.path,
    title: title ?? dest.uri.pathSegments.last,
    addedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

class AlbumPhoto {
  const AlbumPhoto({
    required this.id,
    required this.path,
    required this.title,
    required this.addedAt,
  });

  final String id;
  final String path;
  final String title;
  final int addedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'path': path,
        'title': title,
        'addedAt': addedAt,
      };

  static AlbumPhoto? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    final path = v['path'];
    final title = v['title'];
    final ts = v['addedAt'];
    if (id is! String || path is! String || title is! String || ts is! int) {
      return null;
    }
    return AlbumPhoto(id: id, path: path, title: title, addedAt: ts);
  }
}

List<AlbumPhoto> parseAlbum(String? raw) {
  if (raw == null || raw.isEmpty) return <AlbumPhoto>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <AlbumPhoto>[];
    return decoded
        .map(AlbumPhoto.fromJson)
        .whereType<AlbumPhoto>()
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  } on Object {
    return <AlbumPhoto>[];
  }
}

String encodeAlbum(List<AlbumPhoto> photos) =>
    jsonEncode(<Object?>[for (final p in photos) p.toJson()]);

Future<Directory> _albumDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/album');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

Future<List<AlbumPhoto>> loadAlbum() async {
  try {
    final photos = parseAlbum(await AppSettings.get(kAlbumKey));
    // 過濾掉檔已不存在者（不自動刪 kv，避免檔案短暫不可見即消失）。
    return photos.where((p) => File(p.path).existsSync()).toList();
  } on Object {
    return <AlbumPhoto>[];
  }
}

Future<void> saveAlbum(List<AlbumPhoto> photos) async {
  await AppSettings.set(kAlbumKey, encodeAlbum(photos));
}

/// 從外部路徑複製一張進相簿（回傳新 AlbumPhoto）。
Future<AlbumPhoto> importPhoto(String sourcePath, {String? title}) async {
  final dir = await _albumDir();
  final id = '${DateTime.now().microsecondsSinceEpoch}';
  final ext = sourcePath.contains('.')
      ? sourcePath.substring(sourcePath.lastIndexOf('.'))
      : '.jpg';
  final dest = File('${dir.path}/$id$ext');
  await File(sourcePath).copy(dest.path);
  return AlbumPhoto(
    id: id,
    path: dest.path,
    title: title ?? dest.uri.pathSegments.last,
    addedAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 刪除（同時刪檔＋kv）。
Future<void> deletePhoto(AlbumPhoto photo) async {
  try {
    final f = File(photo.path);
    if (f.existsSync()) await f.delete();
  } on Object {
    // 檔案已不存在 → 忽略。
  }
  final all = await loadAlbum();
  await saveAlbum(all.where((p) => p.id != photo.id).toList());
}

/// 清理不再被 kv References 的孤檔（可選，設定頁手動呼叫）。
Future<int> cleanOrphanPhotos() async {
  final dir = await _albumDir();
  final referenced = (await loadAlbum()).map((p) => p.path).toSet();
  var removed = 0;
  for (final f in dir.listSync()) {
    if (f is File && !referenced.contains(f.path)) {
      try {
        await f.delete();
        removed++;
      } on Object {
        // 忽略。
      }
    }
  }
  return removed;
}
