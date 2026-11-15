// 貼圖包驗證工具（開發者／創作者用）。
//
// 用法：`dart run tool/verify_sticker_pack.dart <pack.zip> [pack2.zip …]`
// 逐檔執行與 App 端**相同**的驗證（`sticker_pack_importer.dart` 的純邏輯），
// 輸出是否可匯入與失敗原因；不連線、不上傳、不寫檔。
import 'dart:io';

import 'package:homing/sticker_pack_importer.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('用法：dart run tool/verify_sticker_pack.dart <pack.zip> …');
    exitCode = 2;
    return;
  }
  var failed = 0;
  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('✗ $path：檔案不存在');
      failed++;
      continue;
    }
    try {
      final pack = parseStickerPack(await file.readAsBytes());
      stdout.writeln('✓ $path');
      stdout.writeln('  貼圖包：${pack.name}（${pack.id}）');
      stdout.writeln('  創作者：${pack.author}｜授權：${pack.license}');
      stdout.writeln('  張數：${pack.stickers.length}');
      for (final s in pack.stickers) {
        stdout.writeln('    - ${s.shortcode}  ${s.width}×${s.height}  ${s.mimeType}  ${s.body}');
      }
      if (pack.warnings.isNotEmpty) {
        stdout.writeln('  警告：${pack.warnings.join("；")}');
      }
    } on StickerPackException catch (e) {
      stdout.writeln('✗ $path：${e.message}');
      failed++;
    } catch (e) {
      stdout.writeln('✗ $path：未預期的錯誤（$e）');
      failed++;
    }
  }
  exitCode = failed == 0 ? 0 : 1;
}
