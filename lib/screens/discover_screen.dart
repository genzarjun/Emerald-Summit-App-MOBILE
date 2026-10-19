import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../widgets/discipline_effects.dart';
import '../widgets/discipline_vibe.dart';
import 'discipline_editor_screen.dart';
import 'discipline_screen.dart';
import 'session_detail_screen.dart';

/// "Discover" tab: a browsable catalog of all disciplines
/// (spec section 04, Build your own schedule). A search box up top finds
/// sessions across every discipline, and each discipline is a listing in its own
/// colors with its animated motif. Tapping one opens its page through a
/// portal transition. Reads the live catalog from [appState]
/// (backend-backed; sample data when no backend is configured).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Load once if the catalog isn't populated yet (e.g. sample mode, or a
    // direct open before the auth gate primed it).
    if (appState.disciplines.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => appState.loadCatalog());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      floatingActionButton: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => appState.isAdmin
            ? FloatingActionButton.extended(
                heroTag: 'fab-new-discipline',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DisciplineEditorScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New discipline'),
              )
            : const SizedBox.shrink(),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final disciplines = appState.disciplines;

          if (appState.catalogLoading && disciplines.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (appState.catalogError != null && disciplines.isEmpty) {
            return _ErrorState(onRetry: appState.loadCatalog);
          }

          final searching = _query.trim().isNotEmpty;
          return RefreshIndicator(
            onRefresh: appState.loadCatalog,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search sessions, rooms, tracks',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (searching)
                  _SearchResults(query: _query.trim())
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      '${disciplines.length} disciplines',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final d in disciplines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DisciplineListing(discipline: d),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One discipline as a full-width listing in its own colors: name, topics,
/// a few of its real session titles, and when it starts.
class _DisciplineListing extends StatefulWidget {
  const _DisciplineListing({required this.discipline});
  final Discipline discipline;

  @override
  State<_DisciplineListing> createState() => _DisciplineListingState();
}

class _DisciplineListingState extends State<_DisciplineListing> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.discipline;
    final vibe = DisciplineVibe.of(d);
    final sessions = [...d.sessions]
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final open = sessions.where((s) => !s.isFull).length;
    final mine = sessions.where((s) => appState.isRegistered(s.id)).length;

    final titles = <String>[];
    for (final s in sessions) {
      if (!titles.contains(s.title)) titles.add(s.title);
    }
    final preview = switch (titles.length) {
      0 => 'No sessions yet.',
      1 => titles.first,
      2 => '${titles[0]} and ${titles[1]}',
      _ => '${titles[0]}, ${titles[1]} and ${titles.length - 2} more',
    };
    final facts = [
      if (sessions.isNotEmpty) 'From ${sessions.first.timeLabel.split(' – ').first}',
      if (sessions.isNotEmpty) '$open of ${sessions.length} open',
    ].join('  ·  ');

    return Semantics(
      button: true,
      label: d.name,
      child: GestureDetector(
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          setState(() => _down = true);
        },
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () => openDiscipline(context, d, from: context),
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: vibe.accent.withValues(alpha: .28)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: vibe.background)),
                  Positioned.fill(
                    child: AmbientMotif(vibe: vibe, compact: true),
                  ),
                  // Keep the text side calm so it always reads.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            vibe.background.withValues(alpha: .9),
                            vibe.background.withValues(alpha: .62),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Hero(
                              tag: disciplineHeroTag(d.id),
                              child: DisciplineBadge(
                                vibe: vibe,
                                discipline: d,
                                size: 40,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                d.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: vibe.text,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.3,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: vibe.textDim),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: vibe.text, height: 1.35),
                        ),
                        if (d.tagline.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            d.tagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: vibe.textDim),
                          ),
                        ],
                        if (facts.isNotEmpty || mine > 0) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  facts,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: vibe.textDim),
                                ),
                              ),
                              if (mine > 0) ...[
                                Icon(Icons.check, size: 15, color: vibe.accent),
                                const SizedBox(width: 3),
                                Text(
                                  '$mine on your day',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: vibe.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sessions from every discipline whose title, track, room, expert or
/// discipline name contains [query].
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = query.toLowerCase();
    final results = [
      for (final d in appState.disciplines)
        for (final s in d.sessions)
          if ([s.title, s.track, s.room, d.name]
              .any((f) => f.toLowerCase().contains(q)))
            (d, s),
    ]..sort((a, b) => a.$2.startMinutes.compareTo(b.$2.startMinutes));

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'No sessions match "$query".',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '${results.length} result${results.length == 1 ? '' : 's'}',
            style: theme.textTheme.labelLarge,
          ),
        ),
        for (final (d, s) in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ResultTile(discipline: d, session: s),
          ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.discipline, required this.session});
  final Discipline discipline;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SessionDetailScreen(session: s)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              DisciplineBadge(
                vibe: DisciplineVibe.of(discipline),
                discipline: discipline,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${discipline.name} · ${s.timeLabel} · ${s.room}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (appState.isRegistered(s.id))
                Icon(Icons.check_circle,
                    size: 18, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text("Couldn't load the catalog", style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
