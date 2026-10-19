import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../app_state.dart';
import '../models/models.dart';

/// The line above the My Day list: how many sessions and how much time the
/// user has booked, and how many open sessions
/// still fit around what they have (with a jump to Discover to find one).
/// It sums the list up rather than repeating any of it.
class DaySummary extends StatelessWidget {
  const DaySummary({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final mine = appState.mySessions;
    final booked = mine.fold<int>(
      0,
      (sum, s) => sum + (s.endMinutes - s.startMinutes).clamp(0, 24 * 60),
    );
    final busy = [for (final e in appState.scheduleEntries) e.session];
    final fits = appState.allSessions
        .where(
          (s) =>
              !appState.isRegistered(s.id) &&
              !appState.isManaging(s.id) &&
              !s.isFull &&
              !busy.any((b) => b.overlaps(s)),
        )
        .length;

    final count = busy.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodyLarge,
                    children: [
                      TextSpan(
                        text: '$count ${count == 1 ? 'session' : 'sessions'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (booked > 0)
                        TextSpan(
                          text: '  ·  ${formatMinutes(booked)} booked',
                          style: TextStyle(color: dim),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (fits > 0)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$fits open ${fits == 1 ? 'session still fits' : 'sessions still fit'} around these.',
                    style: theme.textTheme.bodySmall?.copyWith(color: dim),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => rootTab.value = kDiscoverTabIndex,
                  child: const Text('Find one'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
