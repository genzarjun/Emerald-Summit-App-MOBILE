import 'package:flutter/widgets.dart';

/// Two-tone icons from the Phosphor icon family (phosphoricons.com, MIT
/// license), drawn from the duotone font bundled at
/// assets/fonts/Phosphor-Duotone.ttf. Each icon is two glyphs: a solid
/// outline and a soft fill behind it. The font is used directly because the
/// phosphor_flutter package doesn't build on this Flutter version.
class DuotoneIconData {
  const DuotoneIconData(this.outlineGlyph, this.fillGlyph);

  final IconData outlineGlyph;
  final IconData fillGlyph;
}

const _family = 'PhosphorDuotone';

/// The duotone icons the app uses. Add a new one by copying its two
/// codepoints from Phosphor's duotone set.
abstract final class Duotone {
  static const circuitry = DuotoneIconData(
    IconData(0xe9c3, fontFamily: _family),
    IconData(0xe9c2, fontFamily: _family),
  );
  static const chartLineUp = DuotoneIconData(
    IconData(0xe157, fontFamily: _family),
    IconData(0xe156, fontFamily: _family),
  );
  static const dna = DuotoneIconData(
    IconData(0xe925, fontFamily: _family),
    IconData(0xe924, fontFamily: _family),
  );
  static const planet = DuotoneIconData(
    IconData(0xe653, fontFamily: _family),
    IconData(0xe652, fontFamily: _family),
  );
  static const scales = DuotoneIconData(
    IconData(0xe751, fontFamily: _family),
    IconData(0xe750, fontFamily: _family),
  );
  static const paintBrushBroad = DuotoneIconData(
    IconData(0xe591, fontFamily: _family),
    IconData(0xe590, fontFamily: _family),
  );
  static const calendarCheck = DuotoneIconData(
    IconData(0xe713, fontFamily: _family),
    IconData(0xe712, fontFamily: _family),
  );
  static const compass = DuotoneIconData(
    IconData(0xe1c9, fontFamily: _family),
    IconData(0xe1c8, fontFamily: _family),
  );
  static const megaphoneSimple = DuotoneIconData(
    IconData(0xe643, fontFamily: _family),
    IconData(0xe642, fontFamily: _family),
  );
  static const mapTrifold = DuotoneIconData(
    IconData(0xe31b, fontFamily: _family),
    IconData(0xe31a, fontFamily: _family),
  );
  static const books = DuotoneIconData(
    IconData(0xe759, fontFamily: _family),
    IconData(0xe758, fontFamily: _family),
  );
  static const handshake = DuotoneIconData(
    IconData(0xe583, fontFamily: _family),
    IconData(0xe582, fontFamily: _family),
  );
  static const identificationCard = DuotoneIconData(
    IconData(0xe2c9, fontFamily: _family),
    IconData(0xe2c8, fontFamily: _family),
  );
}

/// Draws a [DuotoneIconData]: the fill glyph in [fillColor] (or [color]) at
/// [fillOpacity], with the outline in [color] on top.
class DuotoneIcon extends StatelessWidget {
  const DuotoneIcon(
    this.icon, {
    super.key,
    this.size = 24,
    required this.color,
    this.fillColor,
    this.fillOpacity = .25,
    this.semanticLabel,
  });

  final DuotoneIconData icon;
  final double size;
  final Color color;
  final Color? fillColor;
  final double fillOpacity;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            icon.fillGlyph,
            size: size,
            color: (fillColor ?? color).withValues(alpha: fillOpacity),
          ),
          Icon(icon.outlineGlyph, size: size, color: color),
        ],
      ),
    );
  }
}
