import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/theme.dart';

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Every foreground/background pairing the screens actually draw, checked in
/// both themes, so a palette tweak can't quietly make text unreadable in one
/// of them (the dark theme once filled boxes with the border color and drew
/// tab labels in black on a black app bar).
void main() {
  for (final (name, theme) in [
    ('light', EmeraldTheme.light()),
    ('dark', EmeraldTheme.dark()),
  ]) {
    group('$name theme', () {
      final s = theme.colorScheme;
      final backgrounds = {
        'scaffold': theme.scaffoldBackgroundColor,
        'surface': s.surface,
        'surfaceContainerLowest': s.surfaceContainerLowest,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
      };

      // Body text: 4.5:1.
      for (final (fgName, fg) in [
        ('onSurface', s.onSurface),
        ('onSurfaceVariant', s.onSurfaceVariant),
        ('primary', s.primary),
        ('secondary', s.secondary),
        ('tertiary', s.tertiary),
        ('error', s.error),
      ]) {
        for (final MapEntry(key: bgName, value: bg) in backgrounds.entries) {
          test('$fgName on $bgName', () {
            expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
          });
        }
      }

      // Filled roles and their "on" colors.
      for (final (pair, fg, bg) in [
        ('onPrimary/primary', s.onPrimary, s.primary),
        ('onPrimaryContainer/primaryContainer', s.onPrimaryContainer,
            s.primaryContainer),
        ('onSecondary/secondary', s.onSecondary, s.secondary),
        ('onSecondaryContainer/secondaryContainer', s.onSecondaryContainer,
            s.secondaryContainer),
        ('onTertiary/tertiary', s.onTertiary, s.tertiary),
        ('onTertiaryContainer/tertiaryContainer', s.onTertiaryContainer,
            s.tertiaryContainer),
        ('onError/error', s.onError, s.error),
        ('onErrorContainer/errorContainer', s.onErrorContainer,
            s.errorContainer),
        ('onInverseSurface/inverseSurface', s.onInverseSurface,
            s.inverseSurface),
        ('inversePrimary/inverseSurface', s.inversePrimary, s.inverseSurface),
        ('app bar', theme.appBarTheme.foregroundColor!,
            theme.appBarTheme.backgroundColor!),
      ]) {
        test(pair, () {
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }

      // Control boundaries (text fields, outlined buttons): 3:1.
      for (final MapEntry(key: bgName, value: bg) in backgrounds.entries) {
        test('outline on $bgName', () {
          expect(_contrast(s.outline, bg), greaterThanOrEqualTo(3));
        });
      }
    });
  }
}
