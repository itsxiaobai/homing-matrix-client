// 第四十九批：對比度量測（WCAG 2.1 相對亮度與對比比）——純函式 + CLI 工具。
//
// 目的：把「文字對背景的對比是否足夠」從**目視**變成**可重現的數值**，
// 讓 UI 的顏色組合能被自動檢查（CI 可跑）。
//
// 標準依據（WCAG 2.1）：
// - 相對亮度 L = 0.2126R + 0.7152G + 0.0722B（R／G／B 為 sRGB 線性化值）。
// - 對比比 CR = (L_light + 0.05) / (L_dark + 0.05)。
// - AA 一般文字：CR ≥ 4.5；AA 大字（≥18pt 或 ≥14pt 粗體）：CR ≥ 3.0；
//   AAA 一般文字：CR ≥ 7.0。
//
// ⚠️ 本檔**不是**法規認證工具，只是可重現的量測；最終的可讀性仍需
// 人類在真實螢幕與真實字級下判讀（見 `ACCESSIBILITY.md`）。
library;

import 'dart:math' as math;

/// sRGB 8-bit 色階。
class Rgb8 {
  const Rgb8(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// 由 `0xFFRRGGBB` 解析（const 可用）。
  const Rgb8.fromHex(int argb)
      : r = (argb >> 16) & 0xFF,
        g = (argb >> 8) & 0xFF,
        b = argb & 0xFF;

  @override
  String toString() =>
      '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

/// sRGB → 線性化（WCAG 2.1 公式）。
double srgbChannelToLinear(int channel) {
  final c = channel / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// 相對亮度 L（0..1）。
double relativeLuminance(Rgb8 color) {
  final r = srgbChannelToLinear(color.r);
  final g = srgbChannelToLinear(color.g);
  final b = srgbChannelToLinear(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// 對比比 CR（1.0 .. 21.0）。
double contrastRatio(Rgb8 a, Rgb8 b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

/// WCAG 等級判定。
enum WcagLevel {
  /// 未達 AA（一般文字 4.5）。
  fail,

  /// 達 AA（一般文字 4.5）。
  aa,

  /// 達 AAA（一般文字 7.0）。
  aaa,
}

/// 依對比比判定等級（以一般文字門檻判定）。
WcagLevel wcagLevel(double ratio) {
  if (ratio >= 7.0) return WcagLevel.aaa;
  if (ratio >= 4.5) return WcagLevel.aa;
  return WcagLevel.fail;
}

/// 一筆量測結果（可讀的報告列）。
class ContrastCheck {
  const ContrastCheck({
    required this.name,
    required this.foreground,
    required this.background,
    required this.ratio,
  });

  final String name;
  final Rgb8 foreground;
  final Rgb8 background;
  final double ratio;

  WcagLevel get level => wcagLevel(ratio);

  /// 是否達 AA（一般文字 4.5:1）。
  bool get passesAa => level != WcagLevel.fail;

  @override
  String toString() {
    final mark = switch (level) {
      WcagLevel.aaa => 'AAA',
      WcagLevel.aa => 'AA ',
      WcagLevel.fail => 'FAIL',
    };
    return '$mark  ${ratio.toStringAsFixed(2)}:1  '
        '$name  (${foreground.toString()} on ${background.toString()})';
  }
}
