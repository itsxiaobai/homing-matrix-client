// 第六十八批 a（人類 2026-11-17 授權「照 LINE_ref 複製」；2026-11-19 裁決為
// **暫定標準、隨時回復**，非正式定稿）——LINE 式**自繪**圖示與版面常數。
//
// 為什麼不用 Material Icons：人類明確指示「不要侷限在 Material，否則會反而
// 像 Google Chat」。Material 預設 icon 筆畫／圓角與 LINE 不同 → 本檔以
// CustomPainter 畫線條圖示（round cap/join、固定 stroke），只複製**幾何與
// 筆畫**，不匯入任何 LINE 圖片／logo／角色素材（著作權）。
//
// 這些是**繪製**函式，不是品牌識別；色值由呼叫端傳入（-design_tokens 或
// 主題），本檔不綁死配色。
library;

import 'package:flutter/material.dart';
import 'compound_icon.dart'; // 第七十批 c：Compound 圖示覆蓋 68 自繪
import 'design_tokens.dart'; // 第九十一批：kLineGreen（回復 v2 主色）

/// 線條粗細（相對 size）；LINE 圖示筆畫偏細、端點圓。
const double kLineIconStrokeRatio = 0.085;

/// LINE 式自繪圖示種類（68a 先做首頁／導覽所需）。
enum LineIcon {
  /// 房子（首頁）。
  home,

  /// 對話氣泡＋三點（聊天室）。
  chat,

  /// 人形（聯絡人）。
  person,

  /// 話筒（通話）。
  phone,

  /// 放大鏡（搜尋）。
  search,

  /// 加號（新增）。
  plus,

  /// 向下箭頭（頂列膠囊）。
  chevronDown,

  /// 人形＋加號（加入好友）。
  personAdd,

  /// 通知鈴。
  bell,

  /// QR 掃描框（搜尋列右端）。
  scan,

  /// 三點垂直（更多）。
  moreVertical,

  /// 鉛筆（編輯）。
  pencil,

  /// 迴紋針／資料夾（附件；後續批次用）。
  attach,

  /// chevron 左（返回）。
  chevronLeft,

  /// 時鐘（通話紀錄）。
  clock,

  /// 日曆。
  calendar,

  /// 三條線（選單）。
  menu,

  /// 相機。
  camera,

  /// 圖片（山＋太陽）。
  image,

  /// 笑臉（表情）。
  emoji,

  /// 麥克風。
  mic,

  /// 檔案（PDF 卡片用）。
  file,

  /// 紙飛機（送出）。
  send,

  /// 分享（三點連線）。
  share,
}

/// LINE 式線條圖示（尺寸由 [size] 決定，無寫死版面寬度）。
class LineIconWidget extends StatelessWidget {
  const LineIconWidget(
    this.icon, {
    required this.size,
    required this.color,
    super.key,
  });

  final LineIcon icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _LineIconPainter(icon: icon, color: color),
        ),
      ),
    );
  }
}

/// LINE 泡泡尾巴（**暫定標準**）：在圓角氣泡外側畫一個小三角，與氣泡同色。/// [own]＝自己（尾巴在右下），他人＝左上。尾巴不影響佈局（只是 painter 疊圖）。
class LineBubbleTail extends CustomPainter {  const LineBubbleTail({required this.color, required this.own});

  final Color color;
  final bool own;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (own) {
      // 右下：底邊靠右的一段 + 向外的小尖角。
      path
        ..moveTo(size.width * 0.62, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height * 0.30)
        ..close();
    } else {
      // 左上。
      path
        ..moveTo(0, size.height * 0.70)
        ..lineTo(0, 0)
        ..lineTo(size.width * 0.38, 0)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant LineBubbleTail old) =>
      old.color != color || old.own != own;
}

class _LineIconPainter extends CustomPainter {
  _LineIconPainter({required this.icon, required this.color});

  final LineIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * kLineIconStrokeRatio
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path();
    final w = size.width;
    final h = size.height;

    void line(double x1, double y1, double x2, double y2) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    switch (icon) {
      case LineIcon.home:
        p
          ..moveTo(w * 0.14, h * 0.46)
          ..lineTo(w * 0.5, h * 0.16)
          ..lineTo(w * 0.86, h * 0.46)
          ..lineTo(w * 0.86, h * 0.84)
          ..lineTo(w * 0.14, h * 0.84)
          ..close();
        canvas.drawPath(p, paint);
        break;

      case LineIcon.chat:
        // 圓角對話氣泡（右下尾巴）＋三點。
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.10, h * 0.16, w * 0.80, h * 0.62),
          Radius.circular(w * 0.20),
        );
        canvas.drawRRect(rect, paint);
        p
          ..moveTo(w * 0.30, h * 0.76)
          ..lineTo(w * 0.24, h * 0.88)
          ..lineTo(w * 0.43, h * 0.77);
        canvas.drawPath(p, paint);
        for (final dx in [0.38, 0.50, 0.62]) {
          canvas.drawCircle(
            Offset(w * dx, h * 0.47),
            size.shortestSide * 0.035,
            paint..style = PaintingStyle.fill,
          );
        }
        paint.style = PaintingStyle.stroke;
        break;

      case LineIcon.person:
        canvas.drawCircle(
          Offset(w * 0.5, h * 0.34),
          w * 0.17,
          paint,
        );
        p
          ..moveTo(w * 0.16, h * 0.88)
          ..quadraticBezierTo(w * 0.16, h * 0.60, w * 0.5, h * 0.60)
          ..quadraticBezierTo(w * 0.84, h * 0.60, w * 0.84, h * 0.88);
        canvas.drawPath(p, paint);
        break;

      case LineIcon.phone:
        // 話筒：LINE 式單筆輪廓（非 Material 實心）。
        p
          ..moveTo(w * 0.21, h * 0.16)
          ..quadraticBezierTo(w * 0.30, h * 0.14, w * 0.37, h * 0.30)
          ..lineTo(w * 0.30, h * 0.40)
          ..quadraticBezierTo(w * 0.50, h * 0.60, w * 0.61, h * 0.69)
          ..lineTo(w * 0.71, h * 0.62)
          ..quadraticBezierTo(w * 0.87, h * 0.69, w * 0.84, h * 0.79)
          ..quadraticBezierTo(w * 0.81, h * 0.90, w * 0.64, h * 0.86)
          ..quadraticBezierTo(w * 0.33, h * 0.75, w * 0.18, h * 0.36)
          ..quadraticBezierTo(w * 0.15, h * 0.22, w * 0.21, h * 0.16)
          ..close();
        canvas.drawPath(p, paint);
        break;

      case LineIcon.search:
        canvas.drawCircle(Offset(w * 0.44, h * 0.42), w * 0.25, paint);
        line(w * 0.62, h * 0.60, w * 0.86, h * 0.84);
        break;

      case LineIcon.plus:
        line(w * 0.2, h * 0.5, w * 0.8, h * 0.5);
        line(w * 0.5, h * 0.2, w * 0.5, h * 0.8);
        break;

      case LineIcon.chevronDown:
        p
          ..moveTo(w * 0.26, h * 0.40)
          ..lineTo(w * 0.5, h * 0.64)
          ..lineTo(w * 0.74, h * 0.40);
        canvas.drawPath(p, paint);
        break;

      case LineIcon.personAdd:
        canvas.drawCircle(Offset(w * 0.37, h * 0.34), w * 0.15, paint);
        p
          ..moveTo(w * 0.10, h * 0.84)
          ..quadraticBezierTo(w * 0.10, h * 0.58, w * 0.37, h * 0.58)
          ..quadraticBezierTo(w * 0.55, h * 0.58, w * 0.62, h * 0.70);
        canvas.drawPath(p, paint);
        line(w * 0.80, h * 0.57, w * 0.80, h * 0.89);
        line(w * 0.64, h * 0.73, w * 0.96, h * 0.73);
        break;

      case LineIcon.bell:
        p
          ..moveTo(w * 0.24, h * 0.70)
          ..lineTo(w * 0.76, h * 0.70)
          ..quadraticBezierTo(w * 0.68, h * 0.62, w * 0.68, h * 0.42)
          ..quadraticBezierTo(w * 0.68, h * 0.24, w * 0.5, h * 0.20)
          ..quadraticBezierTo(w * 0.32, h * 0.24, w * 0.32, h * 0.42)
          ..quadraticBezierTo(w * 0.32, h * 0.62, w * 0.24, h * 0.70)
          ..close();
        canvas.drawPath(p, paint);
        p
          ..moveTo(w * 0.43, h * 0.79)
          ..quadraticBezierTo(w * 0.5, h * 0.90, w * 0.57, h * 0.79);
        canvas.drawPath(p, paint);
        break;

      case LineIcon.scan:
        const c = 0.22;
        // 四個角（不以 Material crop 圖示代替）。
        for (final (x, sx) in [
          (c, 1.0),
          (1 - c, -1.0),
        ]) {
          p
            ..moveTo(w * (x + sx * c), h * c)
            ..lineTo(w * x, h * c)
            ..lineTo(w * x, h * (c + c));
          p
            ..moveTo(w * (x + sx * c), h * (1 - c))
            ..lineTo(w * x, h * (1 - c))
            ..lineTo(w * x, h * (1 - c - c));
        }
        canvas.drawPath(p, paint);
        line(w * 0.20, h * 0.5, w * 0.80, h * 0.5);
        break;

      case LineIcon.moreVertical:
        for (final dy in [0.26, 0.5, 0.74]) {
          canvas.drawCircle(
            Offset(w * 0.5, h * dy),
            size.shortestSide * 0.045,
            paint..style = PaintingStyle.fill,
          );
        }
        paint.style = PaintingStyle.stroke;
        break;

      case LineIcon.pencil:
        p
          ..moveTo(w * 0.18, h * 0.82)
          ..lineTo(w * 0.25, h * 0.62)
          ..lineTo(w * 0.72, h * 0.15)
          ..quadraticBezierTo(w * 0.85, h * 0.28, w * 0.78, h * 0.35)
          ..lineTo(w * 0.31, h * 0.82)
          ..close();
        canvas.drawPath(p, paint);
        line(w * 0.18, h * 0.82, w * 0.31, h * 0.82);
        break;

      case LineIcon.attach:
        p
          ..moveTo(w * 0.22, h * 0.82)
          ..lineTo(w * 0.78, h * 0.18);
        canvas.drawPath(p, paint);
        canvas.drawCircle(Offset(w * 0.72, h * 0.24), w * 0.06, paint);
        break;

      case LineIcon.chevronLeft:
        p
          ..moveTo(w * 0.62, h * 0.26)
          ..lineTo(w * 0.36, h * 0.5)
          ..lineTo(w * 0.62, h * 0.74);
        canvas.drawPath(p, paint);
        break;

      case LineIcon.clock:
        canvas.drawCircle(
          Offset(w * 0.5, h * 0.5),
          w * 0.32,
          paint,
        );
        line(w * 0.5, h * 0.5, w * 0.5, h * 0.29);
        line(w * 0.5, h * 0.5, w * 0.68, h * 0.58);
        break;

      case LineIcon.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.16, h * 0.22, w * 0.68, h * 0.64),
            Radius.circular(w * 0.10),
          ),
          paint,
        );
        line(w * 0.16, h * 0.40, w * 0.84, h * 0.40);
        line(w * 0.34, h * 0.16, w * 0.34, h * 0.30);
        line(w * 0.66, h * 0.16, w * 0.66, h * 0.30);
        break;

      case LineIcon.menu:
        for (final dy in [0.30, 0.50, 0.70]) {
          line(w * 0.18, h * dy, w * 0.82, h * dy);
        }
        break;

      case LineIcon.camera:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.10, h * 0.28, w * 0.80, h * 0.56),
            Radius.circular(w * 0.12),
          ),
          paint,
        );
        p
          ..moveTo(w * 0.36, h * 0.28)
          ..lineTo(w * 0.42, h * 0.19)
          ..lineTo(w * 0.58, h * 0.19)
          ..lineTo(w * 0.64, h * 0.28);
        canvas.drawPath(p, paint);
        canvas.drawCircle(Offset(w * 0.5, h * 0.56), w * 0.15, paint);
        break;

      case LineIcon.image:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.10, h * 0.20, w * 0.80, h * 0.60),
            Radius.circular(w * 0.10),
          ),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.32, h * 0.38), w * 0.08, paint);
        p
          ..moveTo(w * 0.14, h * 0.72)
          ..lineTo(w * 0.42, h * 0.48)
          ..lineTo(w * 0.62, h * 0.66)
          ..lineTo(w * 0.76, h * 0.54)
          ..lineTo(w * 0.88, h * 0.70);
        canvas.drawPath(p, paint);
        break;

      case LineIcon.emoji:
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.34, paint);
        for (final dx in [0.38, 0.62]) {
          canvas.drawCircle(
            Offset(w * dx, h * 0.42),
            size.shortestSide * 0.035,
            paint..style = PaintingStyle.fill,
          );
        }
        paint.style = PaintingStyle.stroke;
        p
          ..moveTo(w * 0.36, h * 0.60)
          ..quadraticBezierTo(w * 0.5, h * 0.76, w * 0.64, h * 0.60);
        canvas.drawPath(p, paint);
        break;

      case LineIcon.mic:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.38, h * 0.16, w * 0.24, h * 0.44),
            Radius.circular(w * 0.12),
          ),
          paint,
        );
        p
          ..moveTo(w * 0.24, h * 0.50)
          ..quadraticBezierTo(w * 0.24, h * 0.74, w * 0.5, h * 0.74)
          ..quadraticBezierTo(w * 0.76, h * 0.74, w * 0.76, h * 0.50);
        canvas.drawPath(p, paint);
        line(w * 0.5, h * 0.74, w * 0.5, h * 0.88);
        break;

      case LineIcon.file:
        p
          ..moveTo(w * 0.26, h * 0.14)
          ..lineTo(w * 0.66, h * 0.14)
          ..quadraticBezierTo(w * 0.74, h * 0.14, w * 0.74, h * 0.24)
          ..lineTo(w * 0.74, h * 0.86)
          ..quadraticBezierTo(w * 0.74, h * 0.92, w * 0.66, h * 0.92)
          ..lineTo(w * 0.26, h * 0.92)
          ..quadraticBezierTo(w * 0.18, h * 0.92, w * 0.18, h * 0.82)
          ..lineTo(w * 0.18, h * 0.24)
          ..quadraticBezierTo(w * 0.18, h * 0.14, w * 0.26, h * 0.14)
          ..close();
        canvas.drawPath(p, paint);
        line(w * 0.30, h * 0.42, w * 0.62, h * 0.42);
        line(w * 0.30, h * 0.56, w * 0.62, h * 0.56);
        break;

      case LineIcon.send:
        p
          ..moveTo(w * 0.14, h * 0.5)
          ..lineTo(w * 0.86, h * 0.18)
          ..lineTo(w * 0.62, h * 0.86)
          ..lineTo(w * 0.40, h * 0.62)
          ..close();
        canvas.drawPath(p, paint);
        line(w * 0.40, h * 0.62, w * 0.86, h * 0.18);
        break;

      case LineIcon.share:
        for (final c in [
          Offset(w * 0.72, h * 0.26),
          Offset(w * 0.26, h * 0.5),
          Offset(w * 0.72, h * 0.74),
        ]) {
          canvas.drawCircle(c, size.shortestSide * 0.09, paint);
        }
        line(w * 0.64, h * 0.30, w * 0.34, h * 0.46);
        line(w * 0.64, h * 0.70, w * 0.34, h * 0.54);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LineIconPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}

/// 第七十批 c：Compound icon **覆蓋**在既有 Material Icon 之上。
/// 底層 Icon 以 opacity 0 保留，讓既有 widget 測試的 `find.byIcon(...)` 仍可定位；
/// 使用者只看到 Compound 官方 SVG icon（第七十批 c 覆蓋 68 自繪）。
Widget lineIconOverMaterial({
  required IconData materialIcon,
  required LineIcon lineIcon,
  required Color color,
  double size = 24,
}) {
  // 68 的 LineIcon → Compound 名稱對照（仅本 App 用到的）。
  final compoundName = switch (lineIcon) {
    LineIcon.search => CompoundIcons.search,
    LineIcon.plus => CompoundIcons.plus,
    LineIcon.camera => CompoundIcons.takePhoto,
    LineIcon.image => CompoundIcons.image,
    LineIcon.emoji => CompoundIcons.reaction,
    LineIcon.mic => CompoundIcons.micOn,
    LineIcon.send => CompoundIcons.send,
    LineIcon.menu => CompoundIcons.menu,
    LineIcon.moreVertical => CompoundIcons.menu,
    LineIcon.chevronDown => CompoundIcons.chevronDown,
    LineIcon.chevronLeft => CompoundIcons.chevronLeft,
    LineIcon.bell => CompoundIcons.notificationsOff, // 唯一使用處＝無聲傳送開關
    LineIcon.attach => CompoundIcons.files, // 先前落入 default 顯示成聊天气泡
    LineIcon.clock => CompoundIcons.time,
    _ => CompoundIcons.chat, // 其他 68 icon 未用在此 helper。
  };
  return Stack(
    alignment: Alignment.center,
    children: [
      Opacity(opacity: 0, child: Icon(materialIcon, size: size)),
      CompoundIcon(compoundName, size: size, color: color),
    ],
  );
}

// ── 第八十五批合併相容層 ─────────────────────────────────────────────
// 舊功能呼叫 lineIconWithTestFallback / lineTitlePill；此處補回，
// 內部轉成 Compound icon（第七十批 c 為視覺準則）。

/// 相容：舊 helper → Compound icon＋透明 Material fallback（測試定位用）。
Widget lineIconWithTestFallback(
  IconData fallback,
  LineIcon icon, {
  required double size,
  required Color color,
}) {
  final compoundName = switch (icon) {
    LineIcon.chat => CompoundIcons.chat,
    LineIcon.chevronLeft => CompoundIcons.arrowLeft, // 返回鈕先前落入 default 顯示成聊天气泡
    LineIcon.chevronDown => CompoundIcons.chevronDown,
    LineIcon.pencil => CompoundIcons.edit,
    LineIcon.personAdd => CompoundIcons.userAdd,
    LineIcon.phone => CompoundIcons.chat, // 無 phone → chat
    LineIcon.plus => CompoundIcons.plus,
    LineIcon.scan => CompoundIcons.qrCode,
    LineIcon.search => CompoundIcons.search,
    _ => CompoundIcons.chat,
  };
  return Stack(
    alignment: Alignment.center,
    children: [
      Opacity(opacity: 0, child: Icon(fallback, size: size)),
      CompoundIcon(compoundName, size: size, color: color),
    ],
  );
}

/// 相容：舊標題膠囊 helper → 主色膠囊（第九十一批回復 v2：種子桃色 kLineGreen）。
Widget lineTitlePill(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: kLineGreen,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFFFFFFFF),
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    ),
  );
}
