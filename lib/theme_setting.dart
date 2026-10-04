import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's Appearance choice (Light / Dark / System), chosen in Profile →
/// Settings. It's a per-device preference, so it lives in local storage rather
/// than on the account: a phone in dark mode and an iPad in light mode can
/// each keep their own.
class ThemeSetting extends ValueNotifier<ThemeMode> {
  ThemeSetting() : super(ThemeMode.system);

  static const _key = 'theme_mode';

  /// Reads the saved choice. Called before [runApp] so the first frame is
  /// already in the right mode (no light-to-dark flash).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      value = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      // Storage unavailable — fall back to following the system.
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

/// Global instance, like [appState].
final themeSetting = ThemeSetting();
