import 'package:flutter/material.dart';

/// Brand palette and theme for Emerald Summit, taken from the product
/// spec (section 03 — Brand & typography).
class EmeraldTheme {
  // Spec colors.
  static const Color emerald = Color(0xFF0C7A55); // Primary actions
  static const Color deepEmerald = Color(0xFF0A5F43); // Pressed / accents
  static const Color ink = Color(0xFF16211C); // Text
  static const Color mist = Color(0xFFEEF5F1); // Surfaces

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
    return _build(scheme, mist);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
    );
    return _build(scheme, scheme.surface);
  }

  static ThemeData _build(ColorScheme scheme, Color scaffold) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.brightness == Brightness.light
            ? Colors.white
            : scheme.surfaceContainerHighest,
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
