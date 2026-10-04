import 'package:flutter/material.dart';

/// Brand palette and theme for Emerald Summit, taken from the product
/// spec (section 03 — Brand & typography).
class EmeraldTheme {
  // Spec colors.
  static const Color emerald = Color(0xFF0C7A55); // Primary actions
  static const Color deepEmerald = Color(0xFF0A5F43); // Pressed / accents
  static const Color ink = Color(0xFF16211C); // Text
  static const Color mist = Color(0xFFEEF5F1); // Surfaces

  // Dark-mode counterparts: a true-black canvas with green boxes on it —
  // cards, fills and the Home header are distinctly emerald-tinted so they
  // stand out against the black. Emerald (softened to mint) carries actions
  // and selection; the logo's navy is a small second accent (supporting
  // roles, Archie's chat bubbles).
  static const Color mint = Color(0xFF5FCB9C); // Primary actions (dark)
  static const Color night = Color(0xFF000000); // Scaffold (dark)
  static const Color nightSurface = Color(0xFF10261E); // Cards (dark)
  static const Color nightMist = Color(0xFF153126); // Fills, pills (dark)
  static const Color nightBorder = Color(0xFF24493A);
  static const Color nightText = Color(0xFFE6F0EC);
  static const Color nightTextDim = Color(0xFF9DB3AB);
  static const Color nightAppBar = night;
  static const Color nightEmeraldContainer = Color(0xFF17513F);
  static const Color nightBlue = Color(0xFFA3BEF2); // Navy accent, lifted
  static const Color nightBlueContainer = Color(0xFF213A63);
  static const Color nightHero = Color(0xFF0F4D3A); // Home header (dark)

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
    // The neutral variant keeps every role we don't override below (error
    // containers, inverse surface, …) low-chroma instead of tinted green.
    final base = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    // Widgets read these roles instead of the raw constants above, so each
    // one maps to its light-mode twin: primary ↔ emerald, secondary ↔
    // deepEmerald, onSurface ↔ ink, surfaceContainer ↔ mist. Selection
    // (secondaryContainer: the nav-bar pill, "registered" banners) stays
    // emerald; blue carries the supporting roles (secondary, tertiary).
    final scheme = base.copyWith(
      primary: mint,
      onPrimary: night,
      primaryContainer: nightEmeraldContainer,
      onPrimaryContainer: const Color(0xFFBDEFD7),
      secondary: nightBlue,
      onSecondary: night,
      secondaryContainer: nightEmeraldContainer,
      onSecondaryContainer: const Color(0xFFBDEFD7),
      tertiary: nightBlue,
      onTertiary: night,
      tertiaryContainer: nightBlueContainer,
      onTertiaryContainer: const Color(0xFFD6E3FF),
      surface: nightSurface,
      onSurface: nightText,
      onSurfaceVariant: nightTextDim,
      surfaceContainerLowest: night,
      surfaceContainerLow: nightSurface,
      surfaceContainer: nightMist,
      surfaceContainerHigh: const Color(0xFF1B3B2F),
      surfaceContainerHighest: nightBorder,
      outline: const Color(0xFF627D73),
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
