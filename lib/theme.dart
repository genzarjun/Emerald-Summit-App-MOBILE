import 'package:flutter/material.dart';

/// Brand palette and theme for Emerald Summit, taken from the product
/// spec (section 03 — Brand & typography).
class EmeraldTheme {
  // Spec colors.
  static const Color emerald = Color(0xFF0C7A55); // Primary actions
  static const Color deepEmerald = Color(0xFF0A5F43); // Pressed / accents
  static const Color ink = Color(0xFF16211C); // Text
  static const Color mist = Color(0xFFEEF5F1); // Surfaces

  // Dark-mode counterparts: the deep emerald night of the launch splash and
  // Archie, with a mint accent that stays readable on it.
  static const Color mint = Color(0xFF5BE0A4); // Primary actions (dark)
  static const Color night = Color(0xFF0B1612); // Scaffold (dark)
  static const Color nightSurface = Color(0xFF13211B); // Cards (dark)
  static const Color nightMist = Color(0xFF1B2D25); // Fills, pills (dark)
  static const Color nightBorder = Color(0xFF26392F);
  static const Color nightText = Color(0xFFE6F0EA);
  static const Color nightTextDim = Color(0xFF93AA9E);
  static const Color nightAppBar = Color(0xFF0E3326);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.light,
    );
    final scheme = base.copyWith(
      primary: emerald,
      onPrimary: Colors.white,
      secondary: deepEmerald,
      surface: Colors.white,
      onSurface: ink,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: mist,
      surfaceContainer: mist,
    );
    return _build(
      scheme,
      scaffold: mist,
      appBar: scheme.primary,
      onAppBar: scheme.onPrimary,
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
    );
    // Widgets read these roles instead of the raw constants above, so each
    // one maps to its light-mode twin: primary ↔ emerald, secondary ↔
    // deepEmerald, onSurface ↔ ink, surfaceContainer ↔ mist.
    final scheme = base.copyWith(
      primary: mint,
      onPrimary: night,
      primaryContainer: const Color(0xFF0F4A35),
      onPrimaryContainer: const Color(0xFFB9F6D5),
      secondary: const Color(0xFF9BE8C4),
      onSecondary: night,
      surface: nightSurface,
      onSurface: nightText,
      onSurfaceVariant: nightTextDim,
      surfaceContainerLowest: night,
      surfaceContainerLow: nightSurface,
      surfaceContainer: nightMist,
      surfaceContainerHigh: const Color(0xFF213429),
      surfaceContainerHighest: nightBorder,
      outline: const Color(0xFF4A6357),
      outlineVariant: nightBorder,
    );
    return _build(
      scheme,
      scaffold: night,
      appBar: nightAppBar,
      onAppBar: nightText,
    );
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required Color scaffold,
    required Color appBar,
    required Color onAppBar,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: appBar,
        foregroundColor: onAppBar,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
      ),
      chipTheme: const ChipThemeData(
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        // A slightly smaller, tighter label keeps every tab of the five-tab
        // bar on a single line across both platforms (the iOS system font is
        // wider; "Resources" used to wrap before Archie replaced it).
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.1,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: scheme.onSurface,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
