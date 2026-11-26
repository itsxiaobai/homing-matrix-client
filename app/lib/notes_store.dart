// 第八十六批（人類指示）：筆記／記事本——**只存本機**（kv），不送伺服器。
// 每則：id／title／body／updatedAt。純邏輯可單測。
import 'dart:convert';

import 'app_settings.dart';

const String kNotesKey = 'local_notes';

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final int updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'body': body,
        'updatedAt': updatedAt,
      };

  static Note? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    final title = v['title'];
    final body = v['body'];
    final ts = v['updatedAt'];
    if (id is! String || title is! String || body is! String || ts is! int) {
      return null;
    }
    return Note(id: id, title: title, body: body, updatedAt: ts);
  }
}

List<Note> parseNotes(String? raw) {
  if (raw == null || raw.isEmpty) return <Note>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Note>[];
    return decoded
        .map(Note.fromJson)
        .whereType<Note>()
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  } on Object {
    return <Note>[];
  }
}

String encodeNotes(List<Note> notes) =>
    jsonEncode(<Object?>[for (final n in notes) n.toJson()]);

Future<List<Note>> loadNotes() async {
  try {
    return parseNotes(await AppSettings.get(kNotesKey));
  } on Object {
    return <Note>[];
  }
}

Future<void> saveNotes(List<Note> notes) async {
  await AppSettings.set(kNotesKey, encodeNotes(notes));
}
