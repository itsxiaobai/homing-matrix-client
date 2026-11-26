// 第七十三批（GIF 開關）：以 dart:ui 解碼圖片**第一幀**靜態顯示。
// 不新增依賴；不影響一般使用者（僅ringStaticStickers 開啟時使用）。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class StaticImage extends StatefulWidget {
  const StaticImage({super.key, required this.bytes, this.width, this.height});

  final Uint8List bytes;
  final double? width;
  final double? height;

  @override
  State<StaticImage> createState() => _StaticImageState();
}

class _StaticImageState extends State<StaticImage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(StaticImage old) {
    super.didUpdateWidget(old);
    if (old.bytes != widget.bytes) {
      _image?.dispose();
      _image = null;
      unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } on Object {
      // 解碼失敗 → 保持空白（由父層語意標籤說明）。
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _StaticImagePainter(image),
      ),
    );
  }
}

class _StaticImagePainter extends CustomPainter {
  const _StaticImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final scale = size.width / src.width < size.height / src.height
        ? size.width / src.width
        : size.height / src.height;
    final w = src.width * scale;
    final h = src.height * scale;
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(
        (size.width - w) / 2,
        (size.height - h) / 2,
        w,
        h,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _StaticImagePainter old) => old.image != image;
}
