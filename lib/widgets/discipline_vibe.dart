import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../theme.dart';
import 'duotone_icon.dart';

/// The animated background each discipline draws behind its content
/// (see [AmbientMotif] in discipline_effects.dart).
enum VibeMotif {
  /// TechVerse: a dot grid with data pulses racing along circuit lanes.
  circuit,

  /// VentureVerse: a chart line climbing to the right, with rising embers.
  ticker,

  /// BioSphere: cells drifting upward, each with a wobbling nucleus.
  cells,

  /// NovaSphere: a twinkling starfield, two orbits and the odd shooting star.
  stars,

  /// CivicVerse: rings spreading out like a gavel strike, between columns.
  ripples,

  /// ImagineX: soft paint blobs drifting and shifting hue.
  paint,
}

/// How the liquid frame around a discipline page moves (see [FlowingBorder]).
class FlowStyle {
  const FlowStyle({
    required this.amplitude,
    required this.depth,
    required this.waves,
    required this.speed,
    required this.spin,
    this.sparks = 0,
    this.heartbeat = false,
  });

  /// Wave height in logical pixels.
  final double amplitude;

  /// How far the calm water line sits in from the screen edge.
  final double depth;

  /// Wave crests around the whole perimeter.
  final double waves;

  /// How fast the crests travel around the edge.
  final double speed;

  /// How fast the colors rotate around the screen (turns per second).
  final double spin;

  /// Bright dots carried along the water line.
  final int sparks;

  /// Swells in a lub-dub rhythm instead of a steady flow.
  final bool heartbeat;
}

/// One step of a discipline's entrance haptic pattern.
enum HapticTap { selection, light, medium, heavy }

/// A discipline's personality: palette, background motif, border flow and
/// the haptic pattern that plays when someone opens it. Looked up by
/// discipline id (falling back to the name), so it needs no database column;
/// a discipline the app doesn't know yet gets the emerald house style.
class DisciplineVibe {
  const DisciplineVibe({
    required this.background,
    required this.surface,
    required this.accent,
    required this.accent2,
    required this.motif,
    required this.flow,
    required this.flowColors,
    required this._entrance,
    this.mark,
  });

  /// Page canvas. Always dark: each discipline is its own little world.
  final Color background;

  /// Cards and raised panels on [background].
  final Color surface;

  /// Main highlight: buttons, meters, selected chips.
  final Color accent;

  /// Second highlight for gradients and small details.
  final Color accent2;

  final VibeMotif motif;
  final FlowStyle flow;

  /// Colors carried around the screen edge by the border flow.
  final List<Color> flowColors;

  /// Pause in milliseconds before each tap of the entrance pattern.
  final List<(int, HapticTap)> _entrance;

  /// The discipline's own two-tone mark. When null, the icon key stored on
  /// the discipline row is drawn instead.
  final DuotoneIconData? mark;

  Color get text => const Color(0xFFF2F5F7);
  Color get textDim => const Color(0xFFB9C2CC);

  /// Plays this discipline's entrance haptic (a short tap pattern).
  Future<void> playEntrance() async {
    for (final (pause, tap) in _entrance) {
      if (pause > 0) await Future<void>.delayed(Duration(milliseconds: pause));
      switch (tap) {
        case HapticTap.selection:
          HapticFeedback.selectionClick();
        case HapticTap.light:
          HapticFeedback.lightImpact();
        case HapticTap.medium:
          HapticFeedback.mediumImpact();
        case HapticTap.heavy:
          HapticFeedback.heavyImpact();
      }
    }
  }

  static final Map<DisciplineVibe, ThemeData> _themes = {};

  /// A dark theme in this discipline's colors for its page and sheets.
  ThemeData get theme => _themes.putIfAbsent(this, () {
    final base = EmeraldTheme.dark();
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: background,
      primaryContainer: Color.lerp(surface, accent, .35),
      onPrimaryContainer: text,
      secondary: accent2,
      onSecondary: background,
      secondaryContainer: Color.lerp(surface, accent, .28),
      onSecondaryContainer: text,
      tertiary: accent2,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textDim,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: Color.lerp(surface, accent, .08),
      surfaceContainerHigh: Color.lerp(surface, accent, .12),
      surfaceContainerHighest: Color.lerp(surface, accent, .16),
      outlineVariant: accent.withValues(alpha: .28),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: background,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent,
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide.none
              : BorderSide(color: accent.withValues(alpha: .3)),
        ),
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? background : text,
          ),
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    );
  });

  /// The personality for [d].
  static DisciplineVibe of(Discipline d) => forKey(d.id, name: d.name);

  /// Looks a personality up by discipline id, then by lower-cased name.
  static DisciplineVibe forKey(String id, {String name = ''}) =>
      _byKey[id.toLowerCase()] ??
      _byKey[name.toLowerCase().replaceAll(' ', '')] ??
      emerald;

  // Palettes come from the summit's discipline color sheet (four swatches
  // each). Accents are the lighter swatches so they read on dark; the page
  // backgrounds are deep shades of each palette's darkest swatch.
  static const techVerse = DisciplineVibe(
    mark: Duotone.circuitry,
    background: Color(0xFF050B18),
    surface: Color(0xFF0E1A31),
    accent: Color(0xFF80DED9),
    accent2: Color(0xFF6D9DC5),
    motif: VibeMotif.circuit,
    flow: FlowStyle(
      amplitude: 9,
      depth: 5,
      waves: 7,
      speed: 1.6,
      spin: .22,
      sparks: 6,
    ),
    flowColors: [
      Color(0xFF119DA4),
      Color(0xFF254F93),
      Color(0xFF6D9DC5),
      Color(0xFF80DED9),
    ],
    // Quick keystrokes.
    entrance: [
      (0, HapticTap.light),
      (55, HapticTap.light),
      (55, HapticTap.selection),
    ],
  );

  static const ventureVerse = DisciplineVibe(
    mark: Duotone.chartLineUp,
    background: Color(0xFF12080D),
    surface: Color(0xFF26141C),
    accent: Color(0xFFFFA552),
    accent2: Color(0xFFFCDE9C),
    motif: VibeMotif.ticker,
    flow: FlowStyle(
      amplitude: 5,
      depth: 4,
      waves: 12,
      speed: 2.4,
      spin: .35,
      sparks: 8,
    ),
    flowColors: [
      Color(0xFFFFA552),
      Color(0xFFFCDE9C),
      Color(0xFFBA5624),
      Color(0xFF381D2A),
    ],
    // Handshake, then the deal lands.
    entrance: [(0, HapticTap.medium), (90, HapticTap.heavy)],
  );

  static const bioSphere = DisciplineVibe(
    mark: Duotone.dna,
    background: Color(0xFF0C0E05),
    surface: Color(0xFF1A1E0C),
    accent: Color(0xFFB6C454),
    accent2: Color(0xFFE6D3A3),
    motif: VibeMotif.cells,
    flow: FlowStyle(
      amplitude: 7,
      depth: 6,
      waves: 5,
      speed: .9,
      spin: .08,
      heartbeat: true,
    ),
    flowColors: [
      Color(0xFFB6C454),
      Color(0xFFD8D174),
      Color(0xFFE6D3A3),
      Color(0xFFF6FEDB),
    ],
    // A heartbeat.
    entrance: [(0, HapticTap.light), (130, HapticTap.medium)],
  );

  static const novaSphere = DisciplineVibe(
    mark: Duotone.planet,
    background: Color(0xFF020C07),
    surface: Color(0xFF0A1D13),
    accent: Color(0xFF8FD5A6),
    accent2: Color(0xFFE5C2C0),
    motif: VibeMotif.stars,
    flow: FlowStyle(
      amplitude: 14,
      depth: 7,
      waves: 3,
      speed: .5,
      spin: .07,
      sparks: 3,
    ),
    flowColors: [
      Color(0xFF8FD5A6),
      Color(0xFF329F5B),
      Color(0xFF0C8346),
      Color(0xFFE5C2C0),
    ],
    // Liftoff, fading as it climbs.
    entrance: [
      (0, HapticTap.heavy),
      (80, HapticTap.medium),
      (90, HapticTap.light),
    ],
  );

  static const civicVerse = DisciplineVibe(
    mark: Duotone.scales,
    background: Color(0xFF0D0412),
    surface: Color(0xFF1E0B25),
    accent: Color(0xFFDCCCA3),
    accent2: Color(0xFF824C71),
    motif: VibeMotif.ripples,
    flow: FlowStyle(amplitude: 3, depth: 4, waves: 4, speed: .6, spin: .05),
    flowColors: [
      Color(0xFFDCCCA3),
      Color(0xFF824C71),
      Color(0xFF4A2545),
      Color(0xFF2B0539),
    ],
    // Two gavel strikes.
    entrance: [(0, HapticTap.heavy), (190, HapticTap.heavy)],
  );

  static const imagineX = DisciplineVibe(
    mark: Duotone.paintBrushBroad,
    background: Color(0xFF0F0A16),
    surface: Color(0xFF1E1729),
    accent: Color(0xFFA6B1E1),
    accent2: Color(0xFFDCD6F7),
    motif: VibeMotif.paint,
    flow: FlowStyle(
      amplitude: 11,
      depth: 6,
      waves: 6,
      speed: 1.2,
      spin: .45,
      sparks: 4,
    ),
    flowColors: [
      Color(0xFFDCD6F7),
      Color(0xFFA6B1E1),
      Color(0xFFB4869F),
      Color(0xFF805D93),
    ],
    // Playful skips.
    entrance: [
      (0, HapticTap.selection),
      (50, HapticTap.light),
      (50, HapticTap.selection),
      (60, HapticTap.medium),
    ],
  );

  /// House style for disciplines added later.
  static const emerald = DisciplineVibe(
    background: Color(0xFF02120C),
    surface: Color(0xFF0B241B),
    accent: EmeraldTheme.mint,
    accent2: EmeraldTheme.nightBlue,
    motif: VibeMotif.ripples,
    flow: FlowStyle(
      amplitude: 6,
      depth: 5,
      waves: 5,
      speed: .9,
      spin: .12,
      sparks: 2,
    ),
    flowColors: [EmeraldTheme.mint, EmeraldTheme.nightBlue, Color(0xFF14B8A6)],
    entrance: [(0, HapticTap.medium)],
  );

  static const Map<String, DisciplineVibe> _byKey = {
    'techverse': techVerse,
    'ventureverse': ventureVerse,
    'biosphere': bioSphere,
    'novasphere': novaSphere,
    'civicverse': civicVerse,
    'imaginex': imagineX,
  };
}
