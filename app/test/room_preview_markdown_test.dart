// 聊天列表預覽的 Markdown 渲染（第四十二批；人類要求「聊天室外預覽也應支援
// Markdown」）。
//
// 驗證：列表列的摘要以 RichText 呈現，且 `**粗體**` 的 formatted_body 會以
// **粗體樣式**渲染（而非顯示 `**` 記號或純文字）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:homing/client_factory.dart';
import 'package:homing/ui/rooms_screen.dart';

void main() {
  testWidgets('預覽以 RichText 渲染 formatted_body（粗體）', (tester) async {
    final client = createClient();
    final room = Room(id: '!room:matrix.org', client: client);
    room.lastEvent = Event.fromJson(<String, dynamic>{
      'event_id': '\$e1',
      'sender': '@alice:matrix.org',
      'origin_server_ts': 1000,
      'type': 'm.room.message',
      'content': <String, dynamic>{
        'msgtype': 'm.text',
        'body': '粗體預覽',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<b>粗體預覽</b>',
        'dev.homing.markdown': true, // 2026-11-20：渲染要求旗標
      },
    }, room);

    await tester.pumpWidget(
      MaterialApp(
        home: RoomsScreen(
          client: client,
          loadRooms: (_) async => [room],
          openRoom: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 找到預覽的 RichText（列表列的 subtitle）。
    final rich = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(rich, isNotEmpty);
    final hasBold = rich.any((r) {
      final span = r.text;
      if (span is! TextSpan) return false;
      return span.children != null &&
          span.children!.any((c) =>
              c is TextSpan &&
              (c.style?.fontWeight?.value ?? 0) >= FontWeight.bold.value);
    });
    expect(hasBold, isTrue, reason: '預覽應以粗體渲染 formatted_body');
  });
}
