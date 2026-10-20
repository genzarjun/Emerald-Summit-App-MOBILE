import 'package:flutter/material.dart';

import '../models/metrics.dart';

/// Building blocks shared by the admin Metrics screen and a session's Metrics
/// tab. Every chart is one hue (the theme's primary), and every bar and cell
/// prints its number, so nothing depends on reading a color.

/// A row of headline numbers.
class StatTiles extends StatelessWidget {
  const StatTiles({super.key, required this.stats});

  final List<(String label, String value)> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // Even tiles: all in one row when they fit, else two per row.
        const gap = 10.0;
        final perRow = c.maxWidth >= stats.length * 120 ? stats.length : 2;
        final width = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, value) in stats)
              Container(
                width: width,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A titled block with an optional one-line note on how it's counted.
class MetricsSection extends StatelessWidget {
  const MetricsSection({
    super.key,
    required this.title,
    this.note,
    required this.child,
  });

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Horizontal bars: one per label, longest = the largest count, with the
/// count and its share of [total] printed beside it.
class BarList extends StatelessWidget {
  const BarList({
    super.key,
    required this.rows,
    required this.total,
    this.emptyText = 'Nobody yet.',
  });

  final List<(String label, int count)> rows;

  /// What the share is out of (usually distinct people).
  final int total;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) return EmptyMetric(emptyText);
    final max = rows.fold(0, (m, r) => r.$2 > m ? r.$2 : m);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        for (final (label, count) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: label == noSchoolLabel || label == noGradeLabel
                              ? muted
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        total == 0 ? '' : '${(count * 100 / total).round()}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, c) => Container(
                    height: 8,
                    width: max == 0
                        ? 0
                        : (c.maxWidth * count / max).clamp(4, c.maxWidth),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A grid of counts (e.g. schools × disciplines), each cell shaded from pale
/// to the theme's primary by its size, with row and column totals. The row
/// labels stay put while the columns scroll sideways. Tap a cell for a
/// sentence spelling it out.
class HeatTable extends StatelessWidget {
  const HeatTable({
    super.key,
    required this.table,
    required this.cornerLabel,
    required this.describe,
    this.emptyText = 'Nobody yet.',
  });

  final CrossTab table;

  /// Header over the row labels, e.g. "School".
  final String cornerLabel;

  /// The tap-to-read sentence for one cell.
  final String Function(String row, String column, int count) describe;
  final String emptyText;

  static const _labelWidth = 120.0;
  static const _minCell = 46.0;
  static const _maxCell = 72.0;
  static const _cellHeight = 44.0;
  static const _headerHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    if (table.isEmpty) return EmptyMetric(emptyText);
    // Stretch the cells to fill the width when the columns (plus Total) fit;
    // past that they hold at the minimum and the grid scrolls sideways.
    // A column is never narrower than its header's longest word, so a name
    // like "Engineering" wraps between words, not inside one.
    final style = Theme.of(context).textTheme.bodySmall;
    final scaler = MediaQuery.textScalerOf(context);
    var widestWord = 0.0;
    for (final header in table.columns) {
      for (final word in header.split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        if (painter.width > widestWord) widestWord = painter.width;
        painter.dispose();
      }
    }
    final minCell = widestWord + 10 > _minCell ? widestWord + 10 : _minCell;
    return LayoutBuilder(
      builder: (context, c) => _grid(
        context,
        ((c.maxWidth - _labelWidth) / (table.columns.length + 1)).clamp(
          minCell,
          minCell > _maxCell ? minCell : _maxCell,
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, double cellWidth) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final max = table.maxCell;
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: scheme.onSurfaceVariant);
    final bold = small?.copyWith(fontWeight: FontWeight.w700);

    Widget header(String text, {bool strong = false}) => SizedBox(
      width: cellWidth,
      height: _headerHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: strong ? bold : muted,
          ),
        ),
      ),
    );

    Widget cell(String row, String col) {
      final n = table.count(row, col);
      final t = max == 0 ? 0.0 : n / max;
      final fill = n == 0
          ? scheme.surfaceContainerLow
          : Color.lerp(scheme.primaryContainer, scheme.primary, t)!;
      final ink = n == 0
          ? scheme.onSurfaceVariant
          : (t > 0.5 ? scheme.onPrimary : scheme.onPrimaryContainer);
      return Tooltip(
        message: describe(row, col, n),
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          width: cellWidth - 2,
          height: _cellHeight - 2,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            n == 0 ? '–' : '$n',
            style: small?.copyWith(
              color: ink,
              fontWeight: n == 0 ? FontWeight.w400 : FontWeight.w700,
            ),
          ),
        ),
      );
    }

    Widget total(String text) => SizedBox(
      width: cellWidth,
      height: _cellHeight,
      child: Center(child: Text(text, style: bold)),
    );

    Widget rowLabel(String text, {bool strong = false}) => SizedBox(
      height: _cellHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: strong
              ? bold
              : (text == noSchoolLabel || text == noGradeLabel ? muted : small),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: _headerHeight,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(cornerLabel, style: muted),
                  ),
                ),
              ),
              for (final r in table.rows) rowLabel(r),
              rowLabel('Total', strong: true),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final c in table.columns)
                      header(c == noGradeLabel ? 'No grade' : c),
                    header('Total', strong: true),
                  ],
                ),
                for (final r in table.rows)
                  Row(
                    children: [
                      for (final c in table.columns) cell(r, c),
                      total('${table.rowTotals[r] ?? 0}'),
                    ],
                  ),
                Row(
                  children: [
                    for (final c in table.columns)
                      total('${table.columnTotals[c] ?? 0}'),
                    total('${table.total}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Muted placeholder for a chart with nothing to show.
class EmptyMetric extends StatelessWidget {
  const EmptyMetric(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One row of choice chips for narrowing who's counted.
class MetricsFilter<T> extends StatelessWidget {
  const MetricsFilter({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}
