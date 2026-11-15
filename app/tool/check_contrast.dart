// 對比度量測工具（第四十九批）——量測 Homing 實際使用的顏色組合。
//
// 用法：`dart run tool/check_contrast.dart`
//
// 輸出：每組「前景 on 背景」的 WCAG 2.1 對比比與等級（AA／AAA／FAIL）。
// 退出碼：0＝全部達 AA（一般文字 4.5:1）；1＝有未達 AA 的組合（CI 可用）。
//
// ⚠️ 量測的是**設計 token 的固定組合**（淺色系）。深色模式由 Material 3
// 種子色派生（`main.dart` 的 `ringTheme`），其對比需另行量測——本工具
// 只覆蓋明列於下表的組合。
//
// 對比數值只是**量測**，不等於「已通過無障礙審查」；最終可讀性仍需人類
// 在真實螢幕／字級下判讀（見 `ACCESSIBILITY.md`）。
import 'dart:io';

import 'package:homing/contrast.dart';

/// 待量測的顏色組合（前景, 背景, 名稱）。
typedef Pair = ({String name, Rgb8 fg, Rgb8 bg});

const _pairs = <Pair>[
  (
    name: '主文字 on 頁面底',
    fg: Rgb8.fromHex(0xFF282828),
    bg: Rgb8.fromHex(0xFFFFFFFF),
  ),
  (
    name: '次要文字 on 頁面底',
    fg: Rgb8.fromHex(0xFF808080),
    bg: Rgb8.fromHex(0xFFFFFFFF),
  ),
  (
    name: '主文字 on 搜尋列底',
    fg: Rgb8.fromHex(0xFF282828),
    bg: Rgb8.fromHex(0xFFE0C1AE),
  ),
  (
    name: '次要文字 on 搜尋列底',
    fg: Rgb8.fromHex(0xFF808080),
    bg: Rgb8.fromHex(0xFFE0C1AE),
  ),
  (
    name: '主文字 on 選中 chip 底',
    fg: Rgb8.fromHex(0xFF282828),
    bg: Rgb8.fromHex(0xFFC4C4C4),
  ),
  (
    name: '主文字 on 底列膠囊底',
    fg: Rgb8.fromHex(0xFF282828),
    bg: Rgb8.fromHex(0xFFECECEC),
  ),
  (
    name: '白字 on 緊急紅',
    fg: Rgb8.fromHex(0xFFFFFFFF),
    bg: Rgb8.fromHex(0xFFE8384F),
  ),
  (
    name: '主文字 on 緊急紅',
    fg: Rgb8.fromHex(0xFF282828),
    bg: Rgb8.fromHex(0xFFE8384F),
  ),
  (
    name: '主文字 on 深色頁面底',
    fg: Rgb8.fromHex(0xFFFFFFFF),
    bg: Rgb8.fromHex(0xFF000000),
  ),
  (
    name: '主文字 on 強調色（頭像圓）',
    fg: Rgb8.fromHex(0xFF282828),
    bg: Rgb8.fromHex(0xFFFFB381),
  ),
];

Future<void> main(List<String> args) async {
  stdout.writeln('Homing 對比度量測（WCAG 2.1）');
  stdout.writeln('門檻：AA 一般文字 ≥ 4.5:1｜AAA ≥ 7:1');
  stdout.writeln('');
  var failed = 0;
  for (final p in _pairs) {
    final ratio = contrastRatio(p.fg, p.bg);
    final check = ContrastCheck(
      name: p.name,
      foreground: p.fg,
      background: p.bg,
      ratio: ratio,
    );
    stdout.writeln(check.toString());
    if (!check.passesAa) failed++;
  }
  stdout.writeln('');
  stdout.writeln(
    failed == 0
        ? '✓ 全部 ${_pairs.length} 組達 AA'
        : '✗ $failed / ${_pairs.length} 組未達 AA（需調整配色或改用大字級）',
  );
  exitCode = failed == 0 ? 0 : 1;
}
