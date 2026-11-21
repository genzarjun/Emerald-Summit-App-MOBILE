import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One tab in a [FloatingTabBar].
class FloatingTab {
  const FloatingTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// A compact tab bar with a subtle rectangular selected-tab indicator.
///
/// Colors come from the theme's `navigationBarTheme` (background, indicator,
/// icon and label styles), so a tab that restyles the bar, like Ask Archie,
/// still can.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<FloatingTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Space between the bar and the screen's sides.
  static const double sideMargin = 14;

  /// Space between the bar and the bottom edge on phones without a home
  /// indicator. With one, the bar sits just above it.
  static const double bottomMargin = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nav = theme.navigationBarTheme;
    final dark = theme.brightness == Brightness.dark;

    final background = nav.backgroundColor ?? scheme.surfaceContainer;
    final pill = nav.indicatorColor ?? scheme.secondaryContainer;
    final dim = nav.iconTheme?.resolve({})?.color ?? scheme.onSurfaceVariant;
    TextStyle labelStyle(bool selected) {
      final base =
          nav.labelTextStyle?.resolve({if (selected) WidgetState.selected}) ??
          const TextStyle(fontSize: 11.5);
      return base.copyWith(
        color: selected ? (base.color ?? scheme.onSurface) : dim,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      );
    }

    // Sit just above the home indicator rather than a full safe-area height
    // up, so the bar hugs the bottom near the screen edge.
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottom = safeBottom > 0 ? safeBottom - 10 : bottomMargin;

    return Padding(
      padding: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, bottom),
      child: Material(
        color: background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: dark ? 0.55 : 0.8),
          ),
        ),
        shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.25),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _TabButton(
                    tab: tabs[i],
                    selected: i == selectedIndex,
                    pill: pill,
                    iconColor: i == selectedIndex
                        ? labelStyle(true).color!
                        : dim,
                    labelStyle: labelStyle(i == selectedIndex),
                    onTap: () {
                      if (i != selectedIndex) HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.pill,
    required this.iconColor,
    required this.labelStyle,
    required this.onTap,
  });

  final FloatingTab tab;
  final bool selected;
  final Color pill;
  final Color iconColor;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 54),
        decoration: ShapeDecoration(
          color: selected ? pill : pill.withValues(alpha: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Same height for every icon (Archie's avatar runs a little
                // taller) so all the labels line up.
                SizedBox(
                  height: 30,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(color: iconColor, size: 24),
                      child: selected ? tab.selectedIcon : tab.icon,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                // Never wraps; very large text sizes shrink to fit instead.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    softWrap: false,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
