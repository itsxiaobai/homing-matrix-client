// 第三十五批（人類需求 #13 Markdown ＋ #14 讀到原始訊息）。
//
// **#13 送出端**：Markdown→HTML（Dart 官方 `markdown` 套件，人類批准
// 「官方依賴允許」），以 Matrix 官方規格欄位送出：
// `format: org.matrix.custom.html` ＋ `formatted_body`（spec appendix；
// Element 等客戶端互相渲染）。輸出 HTML **不再二次清毒**（與 Element 同
// 策略：消毒在**渲染端**；Homing 渲染端見下）。
//
// **#14 收訊端**：依人類「依 Element X 標準」——Element X 對 formatted_body
// 做**有限白名單渲染**（不加載任意 HTML）。本檔同策略：小體積白名單解析器，
// 僅渲染 b/strong、i/em、u、s/del/strike、code、pre、blockquote、ul/ol/li、
// a（href 僅 http/https/matrix/mailto）、p/br；**未知標籤一律剝殼留文字**
// （sanitize；防注入）。收到的訊息**沒有** formatted_body ＝照舊純文字
// 路徑（不改變既有行為）。
//
// 樣式皆草案，待人類設計定稿（連結色由呼叫端主題注入，本檔不寫死）。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// #13 送出端：Markdown→HTML。解析失敗／空輸出回 null（呼叫端退回
/// 純文字 body，不帶格式欄位）。採 Dart 官方套件預設 CommonMark 集
/// （粗體／斜體／行內碼／程式碼塊／引用／清單／連結；人類原始需求所列）。
String? markdownToMessageHtml(String text) {
  try {
    // 第七十二批（人類實機回報「Markdown 功能不管開不開一樣開啟？」）：
    // `markdownToHtml` 未指定 extensionSet 時走 **CommonMark**（markdown
    // 7.3.1 `document.dart` L65：extensionSet==null → ExtensionSet.commonMark），
    // **不含 GFM 的 `~~刪除線~~`**→ 開著 Markdown 打 `~~文字~~` 送出的
    // formatted_body 仍是字面波浪號，看起來跟沒開一樣（實機 `~~123~~`）。
    // 改為 CommonMark ＋ Strikethrough ＋ Autolink；**不啟用 GFM 表格**
    // （收訊端白名單沒有 table，會把表格壓成一串文字）。
    final html = md.markdownToHtml(
      text,
      extensionSet: md.ExtensionSet(
        const [md.FencedCodeBlockSyntax()],
        [
          md.InlineHtmlSyntax(),
          md.StrikethroughSyntax(),
          md.AutolinkExtensionSyntax(),
        ],
      ),
    ).trim();
    return html.isEmpty ? null : html;
  } catch (_) {
    return null;
  }
}

// ── #14 收訊端：有限 HTML 白名單解析 ─────────────────────────────────

/// 允許渲染的標籤白名單（與 Element X 有限渲染集對齊的子集）。
const Set<String> _allowedTags = {
  'p', 'br', 'b', 'strong', 'i', 'em', 'u', 's', 'del', 'strike',
  'code', 'pre', 'blockquote', 'ul', 'ol', 'li', 'a',
};

/// 標籤 token 掃描正則。
final RegExp _tagPattern = RegExp(r'<[^>]*>');

/// 標籤名抓取。
final RegExp _tagNamePattern = RegExp(r'</?\s*([a-zA-Z0-9]+)');

/// href 屬性抓取（寬鬆；scheme 白名單見 _safeHref）。
final RegExp _hrefPattern = RegExp(r'''href\s*=\s*["']?([^"'>\s]+)''');

/// scheme 白名單（Element 同款原則：只留安全 scheme）。
bool _safeHref(String href) {
  final scheme = Uri.tryParse(href)?.scheme.toLowerCase() ?? '';
  return scheme == 'http' || scheme == 'https' || scheme == 'matrix'
      || scheme == 'mailto';
}

/// 解碼常見 HTML entity（最小集；其餘原樣保留＝草案）。
String _decodeEntities(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}

/// #14：formatted_body（HTML）→ InlineSpan 清單（純函式；測試可離線跑）。
///
/// * [baseStyle]：基準樣式（呼叫端由主題提供）。
/// * [linkStyle]：連結樣式（呼叫端以主題色提供；null＝僅底線）。
/// * [onLinkTap]：連結點擊回呼（v0 選用；未提供＝連結不可點，草案披露）。
/// * 未知／不允許標籤剝殼留文字；`mx-reply` 整段剝除（回覆引言由本 App
///   既有 m.relates_to 路徑呈現，避免雙重引言）。
List<InlineSpan> formattedMessageSpans(
  String html, {
  TextStyle? baseStyle,
  TextStyle? linkStyle,
  void Function(String url)? onLinkTap,
}) {
  // mx-reply 整段剝除（Element 規格的回覆 fallback 區塊）。
  final cleaned = html.replaceAll(
    RegExp(r'<mx-reply>.*?</mx-reply>', dotAll: true),
    '',
  );

  final base = baseStyle ?? const TextStyle();
  final spans = <InlineSpan>[];
  final bold = <bool>[]; // 影響域 stack（開＝push，關＝pop；防呆不炸）
  final italic = <bool>[];
  final underline = <bool>[];
  final strike = <bool>[];
  final code = <bool>[];
  final link = <String?>[]; // 當前 a href（null＝不在連結內／href 不安全）
  var quoteDepth = 0;
  final listStack = <int>[]; // 每層：0=ul；1..n=ol 已輸出項計數
  var inPre = false;
  var cursor = 0;

  void pop<T>(List<T> stack) {
    if (stack.isNotEmpty) {
      stack.removeLast();
    }
  }

  TextStyle styleOf() {
    TextDecoration? decoration;
    final hasUnderline = underline.any((v) => v);
    final hasStrike = strike.any((v) => v);
    if (hasUnderline && hasStrike) {
      decoration = TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]);
    } else if (hasUnderline) {
      decoration = TextDecoration.underline;
    } else if (hasStrike) {
      decoration = TextDecoration.lineThrough;
    }
    return base.copyWith(
      fontWeight: bold.any((v) => v) ? FontWeight.bold : null,
      fontStyle: italic.any((v) => v) || quoteDepth > 0
          ? FontStyle.italic
          : null,
      decoration: decoration,
      // 第七十二批（人類「markdown 文字顏色顯示還有問題」）：裝飾線顏色
      // **必須**跟文字色。深色主題的 textTheme 由 Material Typography 帶入
      // `decorationColor`＝白（flutter typography.dart material2021 white
      // 分支 `apply(decorationColor: light)`），呼叫端只 `copyWith(color:)`
      // 時刪除線／底線仍是白 → 亮綠泡泡上出現白色刪除線（對比不足）。
      // base.color 為 null 時維持 null（引擎自動跟隨文字色）。
      decorationColor: decoration == null ? null : base.color,
      fontFamily: code.any((v) => v) ? 'monospace' : null,
    );
  }

  void emit(String text) {
    if (text.isEmpty) {
      return;
    }
    if (link.isNotEmpty && link.last != null) {
      final href = link.last!;
      spans.add(
        TextSpan(
          text: text,
          style: (linkStyle ?? styleOf()).copyWith(
            decoration: linkStyle?.decoration ?? TextDecoration.underline,
          ),
          recognizer:
              onLinkTap == null ? null : (TapGestureRecognizer()..onTap = () => onLinkTap(href)),
        ),
      );
      return;
    }
    spans.add(TextSpan(text: text, style: styleOf()));
  }

  void closeLine() {
    spans.add(const TextSpan(text: '\n'));
  }

  for (final match in _tagPattern.allMatches(cleaned)) {
    if (match.start > cursor) {
      final chunk = cleaned.substring(cursor, match.start);
      emit(inPre ? chunk : _decodeEntities(chunk));
    }
    cursor = match.end;
    final raw = match.group(0)!;
    final isClose = raw.startsWith('</');
    final name =
        _tagNamePattern.firstMatch(raw)?.group(1)?.toLowerCase() ?? '';
    if (!_allowedTags.contains(name)) {
      continue; // 未知標籤剝殼（sanitize）
    }
    switch (name) {
      case 'p':
      case 'blockquote':
        if (isClose) {
          if (name == 'blockquote' && quoteDepth > 0) {
            quoteDepth -= 1;
          }
          closeLine();
        } else if (name == 'blockquote') {
          quoteDepth += 1;
        }
      case 'br':
        closeLine();
      case 'b' || 'strong':
        if (isClose) {
          pop(bold);
        } else {
          bold.add(true);
        }
      case 'i' || 'em':
        if (isClose) {
          pop(italic);
        } else {
          italic.add(true);
        }
      case 'u':
        if (isClose) {
          pop(underline);
        } else {
          underline.add(true);
        }
      case 's' || 'del' || 'strike':
        if (isClose) {
          pop(strike);
        } else {
          strike.add(true);
        }
      case 'code':
        if (isClose) {
          pop(code);
        } else {
          code.add(true);
        }
      case 'pre':
        if (isClose) {
          inPre = false;
          closeLine();
        } else {
          inPre = true;
        }
      case 'ul':
        if (isClose) {
          if (listStack.isNotEmpty) {
            listStack.removeLast();
          }
        } else {
          listStack.add(0);
        }
      case 'ol':
        if (isClose) {
          if (listStack.isNotEmpty) {
            listStack.removeLast();
          }
        } else {
          listStack.add(1);
        }
      case 'li':
        if (!isClose && listStack.isNotEmpty) {
          final parent = listStack.last;
          final String prefix;
          if (parent == 0) {
            prefix = '• ';
          } else {
            prefix = '$parent. ';
            listStack[listStack.length - 1] = parent + 1;
          }
          spans.add(TextSpan(text: prefix, style: styleOf()));
        }
      case 'a':
        if (isClose) {
          pop(link);
        } else {
          final href = _hrefPattern.firstMatch(raw)?.group(1);
          link.add(href != null && _safeHref(href) ? href : null);
        }
    }
  }
  if (cursor < cleaned.length) {
    final rest = cleaned.substring(cursor);
    emit(inPre ? rest : _decodeEntities(rest));
  }
  return spans;
}

/// #14：formatted 訊息渲染入口。解析後以 Text.rich 呈現（樣式草案）。
/// 解析失敗／無輸出回 null（呼叫端退回純文字路徑）。
Widget? formattedMessageWidget(
  String html, {
  TextStyle? baseStyle,
  TextStyle? linkStyle,
  void Function(String url)? onLinkTap,
}) {
  final spans = formattedMessageSpans(
    html,
    baseStyle: baseStyle,
    linkStyle: linkStyle,
    onLinkTap: onLinkTap,
  );
  if (spans.isEmpty) {
    return null;
  }
  return Text.rich(TextSpan(children: spans, style: baseStyle));
}
