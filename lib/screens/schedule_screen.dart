import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/sample_data.dart';
import '../models/models.dart';
import '../widgets/day_summary.dart';
import 'discover_screen.dart';
import 'session_detail_screen.dart';

/// "My Day" tab — the user's full personal schedule: sessions they're attending
/// (registered) AND sessions they're managing (assigned by an admin), each
/// labeled with their role (spec section 04 — Build your own schedule).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh both halves of the schedule (registrations + assignments) when the
    // tab first opens, so an admin's just-made assignment shows up here too.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    await appState.loadSchedule();
    await appState.loadMyAssignments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Day'),
        bottom: const _EventBanner(),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final entries = appState.scheduleEntries;
          if (entries.isEmpty) return const _EmptyPlan();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: _timeline(context, entries),
            ),
          );
        },
      ),
    );
  }
}

/// The summary line, then each session in time order with the free time
/// between them. On summit day the current and next sessions are tagged, and
/// finished ones move into a collapsed "Past" group at the bottom.
List<Widget> _timeline(BuildContext context, List<ScheduleEntry> entries) {
  final now = DateTime.now();
  final date = appState.summitStatus.date;
  final today = date != null && DateUtils.isSameDay(date, now);
  final nowMinutes = now.hour * 60 + now.minute;
  bool ended(ScheduleEntry e) => today && e.session.endMinutes <= nowMinutes;

  final upcoming = entries.where((e) => !ended(e)).toList();
  final past = entries.where(ended).toList();
  final nextIndex = today
      ? upcoming.indexWhere((e) => e.session.startMinutes > nowMinutes)
      : -1;

  final out = <Widget>[const DaySummary(), const SizedBox(height: 12)];
  if (upcoming.isEmpty && past.isNotEmpty) {
    out.add(const Padding(
      padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Text("That's the end of your day. Your sessions are under Past."),
    ));
  }
  for (var i = 0; i < upcoming.length; i++) {
    final s = upcoming[i].session;
    if (i > 0) {
      final gap = s.startMinutes - upcoming[i - 1].session.endMinutes;
      out.add(gap >= 15 ? _FreeTime(minutes: gap) : const SizedBox(height: 12));
    }
    final live = today && s.startMinutes <= nowMinutes;
    out.add(_ScheduleCard(
      entry: upcoming[i],
      tag: live ? 'Now' : i == nextIndex ? 'Next' : null,
    ));
  }
  if (past.isNotEmpty) {
    out.add(const SizedBox(height: 16));
    out.add(_PastGroup(entries: past));
  }
  return out;
}

/// Sessions that have already ended today, collapsed under "Past".
class _PastGroup extends StatelessWidget {
  const _PastGroup({required this.entries});
  final List<ScheduleEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // No divider lines above and below the expanded group.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Past  ·  ${entries.length}',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(opacity: .6, child: _ScheduleCard(entry: e)),
            ),
        ],
      ),
    );
  }
}

/// A quiet divider between two sessions saying how long the break is.
class _FreeTime extends StatelessWidget {
  const _FreeTime({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 4, 10),
      child: Row(
        children: [
          Icon(Icons.coffee_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '${formatMinutes(minutes)} free',
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }
}

class _EventBanner extends StatelessWidget implements PreferredSizeWidget {
  const _EventBanner();

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${SampleData.eventDate}  ·  ${SampleData.eventVenue}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .85),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Your day is a blank slate',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Browse the six disciplines and add sessions to build your '
              'personal schedule. We\'ll flag time clashes and full tracks.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiscoverScreen()),
              ),
              icon: const Icon(Icons.explore),
              label: const Text('Browse sessions'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.entry, this.tag});
  final ScheduleEntry entry;

  /// "Now" or "Next" on summit day; null otherwise.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = entry.session;
    return Card(
      margin: EdgeInsets.zero,
      shape: tag == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(session: session),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.timeLabel.split(' – ').first,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      )),
                  Text(session.timeLabel.split(' – ').last,
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(width: 16),
              Container(
                width: 3,
                height: 44,
                color: theme.colorScheme.primary.withValues(alpha: .3),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tag != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          tag!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(session.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${session.disciplineName} · ${session.room}',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    _RoleChip(entry: entry),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill showing the user's role in a scheduled session: Managing,
/// Participating, Spectating, or Expert — each with its own color.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.entry});
  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Managing keeps the strong primary fill; the participation types get
    // distinct, softer treatments.
    final (Color bg, Color fg) = entry.managing
        ? (scheme.primary, scheme.onPrimary)
        : switch (entry.participationType ?? ParticipationType.participant) {
            ParticipationType.participant => (
                scheme.primaryContainer,
                scheme.onPrimaryContainer
              ),
            ParticipationType.spectator => (
                scheme.surfaceContainerHighest,
                scheme.onSurfaceVariant
              ),
            ParticipationType.expert => (
                scheme.tertiaryContainer,
                scheme.onTertiaryContainer
              ),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        entry.roleLabel,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
