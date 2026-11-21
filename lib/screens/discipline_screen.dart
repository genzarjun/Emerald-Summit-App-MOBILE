import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../widgets/discipline_vibe.dart';
import '../widgets/duotone_icon.dart';
import '../widgets/eighth_grade_badge.dart';
import 'session_detail_screen.dart';
import 'session_editor_screen.dart';

/// Opens [discipline]'s page using the platform's standard page transition.
void openDiscipline(
  BuildContext context,
  Discipline discipline, {
  BuildContext? from,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DisciplineScreen(discipline: discipline),
    ),
  );
}

/// Hero tag shared by a discipline's icon badge on Discover and on its page.
String disciplineHeroTag(String id) => 'discipline-badge-$id';

/// Lists the sessions within one discipline, in that discipline's own look:
/// its colors and a clear list of tracks.
/// Its sessions are listed under "Tracks" (a track is a session), grouped by
/// start time, and can be filtered by open seats or time of day. Admins and mentors scoped to this discipline also
/// get controls to create and edit sessions. Disciplines can't be deleted
/// from the app, only from the Supabase dashboard.
class DisciplineScreen extends StatefulWidget {
  const DisciplineScreen({super.key, required this.discipline});
  final Discipline discipline;

  @override
  State<DisciplineScreen> createState() => _DisciplineScreenState();
}

/// The session list filters.
enum _Filter { all, open, morning, afternoon }

class _DisciplineScreenState extends State<DisciplineScreen>
    with SingleTickerProviderStateMixin {
  late final DisciplineVibe _vibe = DisciplineVibe.of(widget.discipline);

  /// Fades the session list in; replayed quickly when the filter changes.
  late final AnimationController _list = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  final _scroll = ScrollController();
  final _titleShown = ValueNotifier(false);

  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleShown.value = _scroll.offset > 120);
    _list.forward();
  }

  @override
  void dispose() {
    _list.dispose();
    _scroll.dispose();
    _titleShown.dispose();
    super.dispose();
  }

  void _setFilter(_Filter f) {
    if (f == _filter) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = f);
    _list.forward(from: 0);
  }

  bool _matches(Session s) {
    return switch (_filter) {
      _Filter.all => true,
      _Filter.open => !s.isFull,
      _Filter.morning => s.startMinutes < 12 * 60,
      _Filter.afternoon => s.startMinutes >= 12 * 60,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _vibe.theme,
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          // Resolve the latest version from the live catalog so session lists
          // and enrolled counts stay fresh after adds/removes/edits; fall back
          // to the one we were handed if it's no longer in the catalog.
          final current = appState.disciplines.firstWhere(
            (d) => d.id == widget.discipline.id,
            orElse: () => widget.discipline,
          );
          final canManage = appState.canManageDiscipline(current.id);
          return _buildPage(context, current, canManage);
        },
      ),
    );
  }

  Widget _buildPage(BuildContext context, Discipline d, bool canManage) {
    final topInset = MediaQuery.paddingOf(context).top;
    final sessions = [...d.sessions]
      ..sort((a, b) {
        final byTime = a.startMinutes.compareTo(b.startMinutes);
        return byTime != 0 ? byTime : a.title.compareTo(b.title);
      });
    final shown = sessions.where(_matches).toList();

    // Group by start time, the way event listings do.
    final groups = <String, List<Session>>{};
    for (final s in shown) {
      groups.putIfAbsent(s.timeLabel.split(' – ').first, () => []).add(s);
    }

    final fade = CurvedAnimation(parent: _list, curve: Curves.easeOutCubic);
    final still = MediaQuery.disableAnimationsOf(context);
    Widget faded(Widget child) =>
        still ? child : FadeTransition(opacity: fade, child: child);

    final slivers = <Widget>[
      for (final MapEntry(key: time, value: group) in groups.entries) ...[
        SliverToBoxAdapter(
          child: faded(_TimeHeader(label: time, vibe: _vibe)),
        ),
        for (final s in group)
          SliverToBoxAdapter(
            child: faded(
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _SessionCard(
                  session: s,
                  discipline: d,
                  vibe: _vibe,
                  canManage: canManage,
                ),
              ),
            ),
          ),
      ],
    ];

    return Scaffold(
      backgroundColor: _vibe.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: ValueListenableBuilder<bool>(
          valueListenable: _titleShown,
          builder: (context, shown, _) => AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Text(d.name),
          ),
        ),
        flexibleSpace: ValueListenableBuilder<bool>(
          valueListenable: _titleShown,
          builder: (context, shown, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: shown
                ? _vibe.background.withValues(alpha: .94)
                : Colors.transparent,
          ),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'fab-new-session',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionEditorScreen(discipline: d),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New session'),
            )
          : null,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  discipline: d,
                  vibe: _vibe,
                  // The status bar height read above the Scaffold, which
                  // rewrites the insets its body sees.
                  top: topInset + kToolbarHeight + 8,
                ),
              ),
              SliverToBoxAdapter(
                child: _FilterBar(filter: _filter, onFilter: _setFilter),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRACKS',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _vibe.textDim,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                      ),
                      if (appState.isEighthGradeParticipant) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Tracks marked "${EighthGradeBadge.label}" are '
                          'the ones you can participate in. You can spectate '
                          'any of them.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _vibe.textDim),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (sessions.isEmpty)
                const SliverToBoxAdapter(
                  child: _EmptyNote('No tracks in this discipline yet.'),
                )
              else if (shown.isEmpty)
                const SliverToBoxAdapter(
                  child: _EmptyNote('No sessions match this filter.'),
                ),
              ...slivers,
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 96 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.discipline,
    required this.vibe,
    required this.top,
  });
  final Discipline discipline;
  final DisciplineVibe vibe;

  /// Space above the badge so it clears the status bar and back button.
  final double top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = discipline;
    final open = d.sessions.fold<int>(
      0,
      (sum, s) => sum + (s.seatsLeft > 0 ? s.seatsLeft : 0),
    );
    final mine = d.sessions.where((s) => appState.isRegistered(s.id)).length;
    final topics = d.tagline
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .join('  ·  ');
    final count = d.sessions.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, top, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: disciplineHeroTag(d.id),
            child: DisciplineBadge(vibe: vibe, discipline: d, size: 52),
          ),
          const SizedBox(height: 16),
          Text(
            d.name,
            style: theme.textTheme.displaySmall?.copyWith(
              color: vibe.text,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
              height: 1.05,
            ),
          ),
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              topics,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: vibe.textDim,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(color: vibe.text),
              children: [
                TextSpan(
                  text: '$count ${count == 1 ? 'session' : 'sessions'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ', $open seats open'),
                if (mine > 0)
                  TextSpan(
                    text: '.  $mine on your day',
                    style: TextStyle(
                      color: vibe.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A discipline's mark on a tinted square in its colors. Duotone marks fill
/// their second tone with the palette's second accent.
class DisciplineBadge extends StatelessWidget {
  const DisciplineBadge({
    super.key,
    required this.vibe,
    required this.discipline,
    this.size = 40,
  });
  final DisciplineVibe vibe;
  final Discipline discipline;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.lerp(vibe.background, vibe.accent, .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: vibe.accent.withValues(alpha: .45)),
      ),
      child: switch (vibe.mark) {
        final DuotoneIconData mark => DuotoneIcon(
          mark,
          size: size * .58,
          color: vibe.accent,
          fillColor: vibe.accent2,
          fillOpacity: .4,
        ),
        null => Icon(discipline.icon, size: size * .52, color: vibe.accent),
      },
    );
  }
}

/// A thin bar showing how full a session is.
class _Meter extends StatelessWidget {
  const _Meter({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      // Full width: the card's column hands down loose constraints, which
      // would otherwise shrink the track to the filled part.
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: .14)),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onFilter});
  final _Filter filter;
  final void Function(_Filter) onFilter;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        children: [
          chip('All', filter == _Filter.all, () => onFilter(_Filter.all)),
          chip(
            'Open seats',
            filter == _Filter.open,
            () => onFilter(_Filter.open),
          ),
          chip(
            'Morning',
            filter == _Filter.morning,
            () => onFilter(_Filter.morning),
          ),
          chip(
            'Afternoon',
            filter == _Filter.afternoon,
            () => onFilter(_Filter.afternoon),
          ),
        ],
      ),
    );
  }
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({required this.label, required this.vibe});
  final String label;
  final DisciplineVibe vibe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: vibe.accent,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              height: 1,
              color: vibe.accent.withValues(alpha: .22),
            ),
          ),
        ],
      ),
    );
  }
}

/// Warm amber for "only a few seats left" and a soft red for full, both
/// readable on every discipline's dark background.
const _lowSeats = Color(0xFFFFB86B);
const _full = Color(0xFFFF8A8A);

class _SessionCard extends StatefulWidget {
  const _SessionCard({
    required this.session,
    required this.discipline,
    required this.vibe,
    required this.canManage,
  });
  final Session session;
  final Discipline discipline;
  final DisciplineVibe vibe;
  final bool canManage;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _down = false;

  void _open() {
    HapticFeedback.lightImpact();
    openSession(context, widget.session, from: context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final vibe = widget.vibe;
    final registered = appState.isRegistered(s.id);
    final filled = s.capacity == 0 ? 1.0 : s.enrolled / s.capacity;
    final low =
        !s.isFull && s.seatsLeft <= (s.capacity * .2).ceil().clamp(3, 1 << 30);

    final (status, statusColor) = s.isFull
        ? ('Full · waitlist only', _full)
        : s.participationClosed
        ? ('${s.seatsLeft} seats left · spectators only', vibe.textDim)
        : low
        ? ('Only ${s.seatsLeft} seats left', _lowSeats)
        : ('${s.seatsLeft} of ${s.capacity} seats left', vibe.textDim);

    return Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: _open,
        child: AnimatedScale(
          scale: _down ? .98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            decoration: BoxDecoration(
              color: vibe.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: registered
                    ? vibe.accent.withValues(alpha: .7)
                    : Colors.white.withValues(alpha: .07),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Text(
                          s.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: vibe.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (registered)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 16, color: vibe.accent),
                            const SizedBox(width: 3),
                            Text(
                              'Added',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: vibe.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.canManage)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Edit session',
                        visualDensity: VisualDensity.compact,
                        color: vibe.textDim,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SessionEditorScreen(
                              discipline: widget.discipline,
                              session: s,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    s.timeLabel,
                    if (s.roomLabel.isNotEmpty) s.roomLabel,
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: vibe.textDim,
                  ),
                ),
                if (appState.isEighthGradeParticipant &&
                    s.allowEighthGraders) ...[
                  const SizedBox(height: 8),
                  EighthGradeBadge(color: vibe.accent),
                ],
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Meter(
                    value: filled,
                    color: s.isFull
                        ? _full
                        : low
                        ? _lowSeats
                        : vibe.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
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

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
