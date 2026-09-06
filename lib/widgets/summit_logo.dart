import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The Emerald Summit badge — an isometric "summit" prism with a sparkle,
/// rebuilt in Flutter from the brand SVG (viewBox 0 0 96 96) so it stays crisp
/// at any size and needs no image asset.
///
/// Used on the splash screen; safe to drop anywhere a branded mark is wanted.
class SummitLogo extends StatelessWidget {
  const SummitLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SummitLogoPainter()),
    );
  }
}

class _SummitLogoPainter extends CustomPainter {
  // The design is authored in a 96x96 box, matching the source SVG viewBox.
  static const double _viewBox = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _viewBox;
    canvas.save();
    canvas.scale(s, s);

    // The three visible faces of the prism plus its top "table", each a flat
    // polygon with a linear gradient defined in the face's own bounding box
    // (SVG objectBoundingBox semantics).
    _face(
      canvas,
      const [Offset(34, 22), Offset(62, 22), Offset(66, 36), Offset(30, 36)],
      const Alignment(0, -1),
      const Alignment(0, 1),
      const [Color(0xFFD1FAE5), Color(0xFF6EE7B7)],
    );
    _face(
      canvas,
      const [Offset(30, 36), Offset(12, 74), Offset(38, 74)],
      const Alignment(-1, -1),
      const Alignment(-0.2, 1), // x2=0.4 → -0.2 in [-1,1] space
      const [Color(0xFF34D399), Color(0xFF0C7A55)],
    );
    _face(
      canvas,
      const [Offset(30, 36), Offset(66, 36), Offset(58, 74), Offset(38, 74)],
      const Alignment(0, -1),
      const Alignment(0, 1),
      const [Color(0xFF6EE7B7), Color(0xFF10B981)],
    );
    _face(
      canvas,
      const [Offset(66, 36), Offset(84, 74), Offset(58, 74)],
      const Alignment(0.2, -1), // x1=0.6 → 0.2
      const Alignment(-1, 1),
      const [Color(0xFF0C7A55), Color(0xFF064E36)],
    );

    // The sparkle (four-point star) at the upper right.
    final sparkle = Path()
      ..moveTo(73, 14)
      ..relativeLineTo(2.6, 6.4)
      ..lineTo(82, 23)
      ..relativeLineTo(-6.4, 2.6)
      ..lineTo(73, 32)
      ..relativeLineTo(-2.6, -6.4)
      ..lineTo(64, 23)
      ..relativeLineTo(6.4, -2.6)
      ..close();
    canvas.drawPath(
      sparkle,
      Paint()..color = const Color(0xFFA7F3D0).withValues(alpha: 0.95),
    );

    canvas.restore();
  }

  /// Fills [points] with a linear gradient running from [begin] to [end]
  /// (alignments within the polygon's bounding box) across [colors].
  void _face(
    Canvas canvas,
    List<Offset> points,
    Alignment begin,
    Alignment end,
    List<Color> colors,
  ) {
    final path = Path()..addPolygon(points, true);
    final b = path.getBounds();
    final from = begin.withinRect(b);
    final to = end.withinRect(b);
    final paint = Paint()
      ..shader = ui.Gradient.linear(from, to, colors);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
