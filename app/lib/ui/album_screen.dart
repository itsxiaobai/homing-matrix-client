// 第八十八批：相簿畫面（本機相簿，只存 App 沙箱）。
// 第一百零二批：加入「相簿分組」與「建立相簿」；點聊天室卡片可帶 initialGroupName 進入。
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../album_store.dart';
import '../l10n/app_strings.dart';

class AlbumScreen extends StatefulWidget {
  /// [initialGroupName] ＝從聊天室相簿卡片點進來時，只看這本相簿。
  const AlbumScreen({super.key, this.initialGroupName});

  final String? initialGroupName;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<AlbumPhoto> _photos = const [];
  List<AlbumGroup> _groups = const [];
  String? _selectedGroup;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.initialGroupName;
    unawaited(_load());
  }

  Future<void> _load() async {
    final results = await Future.wait(<Future<Object>>[
      loadAlbum(),
      loadAlbumGroups(),
    ]);
    if (!mounted) return;
    setState(() {
      _photos = results[0] as List<AlbumPhoto>;
      _groups = results[1] as List<AlbumGroup>;
      _loading = false;
    });
  }

  List<AlbumPhoto> get _visiblePhotos {
    final groupName = _selectedGroup;
    if (groupName == null) return _photos;
    final group = _groups.where((g) => g.name == groupName).firstOrNull;
    if (group == null) return _photos;
    final ids = group.photoIds.toSet();
    return _photos.where((p) => ids.contains(p.id)).toList();
  }

  Future<void> _add() async {
    // file_picker 13：pickFiles() 預設可多選（allowMultiple 已移除）。
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    var added = 0;
    for (final f in picked) {
      if (f.path == null) continue;
      await importPhoto(f.path!);
      added++;
    }
    if (added > 0) unawaited(_load());
  }

  /// 建立相簿分組：選照片 → 輸入名稱 → 存本機 kv。
  Future<void> _createAlbum() async {
    // file_picker 13：pickFiles() 預設可多選（allowMultiple 已移除）。
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || !mounted) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('建立相簿')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(hintText: S.t('相簿名稱')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: Text(S.t('建立')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final ids = <String>[];
    for (final f in picked) {
      if (f.path == null) continue;
      final photo = await importPhoto(f.path!);
      ids.add(photo.id);
    }
    if (ids.isEmpty) return;
    final group = await createAlbumGroup(name, ids);
    if (!mounted) return;
    setState(() {
      _selectedGroup = group.name;
    });
    unawaited(_load());
  }

  Future<void> _open(AlbumPhoto p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(p.title)),
          body: Center(child: Image.file(File(p.path), fit: BoxFit.contain)),
        ),
      ),
    );
  }

  Future<void> _delete(AlbumPhoto p) async {
    await deletePhoto(p);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePhotos;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('相簿')),
        actions: [
          IconButton(
            tooltip: S.t('建立相簿'),
            onPressed: () => unawaited(_createAlbum()),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: S.t('加入照片'),
        onPressed: () => unawaited(_add()),
        child: const Icon(Icons.add_photo_alternate),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 分組切換（最小樣式；最終版面待人類設計定稿）。
                if (_groups.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(S.t('全部')),
                            selected: _selectedGroup == null,
                            onSelected: (_) =>
                                setState(() => _selectedGroup = null),
                          ),
                        ),
                        for (final g in _groups)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(g.name),
                              selected: _selectedGroup == g.name,
                              onSelected: (_) =>
                                  setState(() => _selectedGroup = g.name),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(child: Text(S.t('相簿是空的')))
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final p = visible[i];
                            return GestureDetector(
                              onTap: () => unawaited(_open(p)),
                              onLongPress: () => unawaited(_delete(p)),
                              child: GridTile(
                                footer: Container(
                                  color: Colors.black54,
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    p.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                child: Image.file(
                                  File(p.path),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
