// 第八十六批（人類指示）：筆記／記事本畫面（只本機、不送伺服器）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../notes_store.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final notes = await loadNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _edit(Note? existing) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? S.t('新增筆記') : S.t('編輯筆記')),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: S.t('標題')),
              ),
              TextField(
                controller: bodyCtrl,
                maxLines: 6,
                decoration: InputDecoration(labelText: S.t('內容')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('儲存')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final note = Note(
      id: existing?.id ?? '${DateTime.now().microsecondsSinceEpoch}',
      title: titleCtrl.text.trim(),
      body: bodyCtrl.text,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final next = <Note>[note, ..._notes.where((n) => n.id != note.id)];
    await saveNotes(next);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('筆記'))),
      floatingActionButton: FloatingActionButton(
        tooltip: S.t('新增筆記'),
        onPressed: () => unawaited(_edit(null)),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(child: Text(S.t('還沒有筆記')))
              : ListView.builder(
                  itemCount: _notes.length,
                  itemBuilder: (context, i) {
                    final n = _notes[i];
                    return ListTile(
                      title: Text(n.title.isEmpty ? S.t('(無標題)') : n.title),
                      subtitle: Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => unawaited(_edit(n)),
                      trailing: IconButton(
                        tooltip: S.t('刪除'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await saveNotes(
                            _notes.where((x) => x.id != n.id).toList(),
                          );
                          unawaited(_load());
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
