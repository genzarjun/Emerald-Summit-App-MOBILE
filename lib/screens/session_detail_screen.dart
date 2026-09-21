import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';
import '../theme.dart';
import 'session_editor_screen.dart';
import 'session_roster_screen.dart';
import 'session_volunteers_screen.dart';

/// The session page — a vibrant, tabbed view of a single session.
///
/// A horizontal (scrollable) tab bar surfaces tabs based on the viewer's
/// permission:
///   * **Session** (everyone) — the rich "marketing page": hero photo, gallery,
///     description, editor-authored content blocks, and the add/remove-to-my-day
///     action.
///   * **Participants** (admins + volunteers assigned to the session) — roster +
///     attendance.
///   * **Volunteers** (admins) — assign/unassign volunteers.
/// Anyone who can edit the session's discipline also gets an Edit action that
/// opens the editor for the main page.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.session});
  final Session session;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  // Bumped after returning from the editor to force the About tab to reload its
  // photos (they live in Storage, separate from the catalog row).
  int _refreshToken = 0;

  Future<void> _openEditor(Session current) async {
    final discipline = appState.disciplines.firstWhere(
      (d) => d.id == current.disciplineId,
      orElse: () => Discipline(
        id: current.disciplineId,
        name: current.disciplineName,
        tagline: '',
        icon: Icons.category,
        sessions: const [],
      ),
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SessionEditorScreen(discipline: discipline, session: current),
      ),
    );
    if (mounted) setState(() => _refreshToken++);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        // Show the latest version from the live catalog so seats/enrolled and
        // page edits stay accurate; fall back to the one we were handed.
        final current = appState.allSessions.firstWhere(
          (s) => s.id == widget.session.id,
          orElse: () => widget.session,
        );

        final canEdit = appState.canManageDiscipline(current.disciplineId);
        final canSeeParticipants =
            appState.isAdmin || appState.isManaging(current.id);
        final canSeeVolunteers = appState.isAdmin;

        // Build the tab set in a fixed order, tracking labels for the TabBar.
        final tabs = <Tab>[const Tab(text: 'Session')];
        final views = <Widget>[
          _SessionAboutTab(
            key: ValueKey('about-${current.id}-$_refreshToken'),
            session: current,
            canEdit: canEdit,
            onEdit: () => _openEditor(current),
          ),
        ];
        if (canSeeParticipants) {
          tabs.add(const Tab(text: 'Participants'));
          views.add(SessionRosterView(session: current));
        }
        if (canSeeVolunteers) {
          tabs.add(const Tab(text: 'Volunteers'));
          views.add(SessionVolunteersView(session: current));
        }

        final actions = <Widget>[
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit session page',
              onPressed: () => _openEditor(current),
            ),
        ];

        // A single-tab (plain participant) view needs no tab bar.
        if (tabs.length == 1) {
          return Scaffold(
            appBar: AppBar(
              title: Text(current.disciplineName),
              actions: actions,
            ),
            body: views.first,
          );
        }

        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(current.disciplineName),
              actions: actions,
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Theme.of(context).colorScheme.onPrimary,
                unselectedLabelColor: Theme.of(context).colorScheme.onPrimary
                    .withValues(alpha: 0.7),
                indicatorColor: Theme.of(context).colorScheme.onPrimary,
                tabs: tabs,
              ),
            ),
            body: TabBarView(children: views),
          ),
        );
      },
    );
  }
}

/// The main "Session" tab — the rich page. Loads the session's gallery photos
/// (Storage) once, and renders the hero, info, description, content blocks,
/// gallery, sponsor, and the day-plan action.
class _SessionAboutTab extends StatefulWidget {
  const _SessionAboutTab({
    super.key,
    required this.session,
    required this.canEdit,
    required this.onEdit,
  });

  final Session session;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  State<_SessionAboutTab> createState() => _SessionAboutTabState();
}

class _SessionAboutTabState extends State<_SessionAboutTab> {
  List<GalleryPhoto> _photos = const [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final photos = await sessionMediaRepository.fetchPhotos(widget.session.id);
    if (!mounted) return;
    setState(() => _photos = photos);
  }

  Future<void> _toggleSession(Session s) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await appState.toggle(s);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    switch (result.outcome) {
      case AddOutcome.added:
        messenger.showSnackBar(
          SnackBar(content: Text('Added "${s.title}" to your day')),
        );
      case AddOutcome.removed:
        messenger.showSnackBar(
          SnackBar(content: Text('Removed "${s.title}" from your day')),
        );
      case AddOutcome.full:
        _showBlockedDialog(
          'Session full',
          'This session has reached its capacity of ${s.capacity}. '
              'You can still join the waitlist on the day.',
        );
      case AddOutcome.conflict:
        _showBlockedDialog(
          'Time conflict',
          'This overlaps with "${result.conflictingTitle}", which is '
              'already on your schedule. Remove that one first to add this.',
        );
    }
  }

  void _showBlockedDialog(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.session;
    final registered = appState.isRegistered(current.id);
    // A volunteer assigned (by an admin) to manage this session can't add/remove
    // it themselves — it's already on their schedule.
    final managing = appState.isManaging(current.id);
    // The big top photo: the explicit hero, or the first gallery photo when no
    // hero was set, so a session with any photo always has a banner.
    final heroUrl = current.heroImageUrl ??
        (_photos.isNotEmpty ? _photos.first.imageUrl : null);
    // The hero is one of the folder's files; keep it out of the strip.
    final gallery = [
      for (final p in _photos)
        if (p.imageUrl != heroUrl) p,
    ];
    // More sessions in this discipline that fit an open slot on their schedule.
    final suggested = appState.suggestedSessions(current);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (heroUrl != null) _HeroImage(url: heroUrl),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.track.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(current.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.schedule, text: current.timeLabel),
              _InfoRow(icon: Icons.place, text: current.room),
              _InfoRow(
                icon: Icons.person,
                text: 'Expert: ${current.expertName}',
              ),
              _InfoRow(
                icon: Icons.groups,
                text: current.isFull
                    ? 'Full (${current.enrolled}/${current.capacity})'
                    : '${current.seatsLeft} of ${current.capacity} seats left',
              ),
              const SizedBox(height: 20),
              Text('About this session', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(current.description, style: theme.textTheme.bodyLarge),
              // Editor-authored content sections.
              for (final block in current.pageBlocks)
                if (block.title.trim().isNotEmpty ||
                    block.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  if (block.title.trim().isNotEmpty)
                    Text(block.title, style: theme.textTheme.titleMedium),
                  if (block.title.trim().isNotEmpty) const SizedBox(height: 8),
                  if (block.body.trim().isNotEmpty)
                    Text(block.body, style: theme.textTheme.bodyLarge),
                ],
              if (gallery.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Gallery', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        if (gallery.isNotEmpty) _Gallery(photos: gallery),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (current.sponsor != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: EmeraldTheme.mist,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.handshake,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          current.sponsor!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              if (managing)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_ind,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "You're managing this session. It was added to your "
                          'schedule by an admin.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => _toggleSession(current),
                  style: registered
                      ? FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.errorContainer,
                          foregroundColor: theme.colorScheme.onErrorContainer,
                        )
                      : null,
                  icon: Icon(registered ? Icons.remove_circle : Icons.add),
                  label: Text(
                    registered ? 'Remove from my day' : 'Add to my day',
                  ),
                ),
              if (widget.canEdit) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit session page'),
                ),
              ],
              if (suggested.isNotEmpty) ...[
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Sessions similar to this',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'More in ${current.disciplineName} that fit an open slot on '
                  'your schedule.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 272,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    clipBehavior: Clip.none,
                    itemCount: suggested.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final s = suggested[i];
                      return _SuggestedSessionCard(
                        session: s,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SessionDetailScreen(session: s),
                          ),
                        ),
                        onAdd: () => _toggleSession(s),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A fixed-width card for a suggested session in the horizontal rail: a hero
/// photo on top, then title, time/seats, and a one-tap Add. Shown only for
/// sessions that fit an open slot (see [AppState.suggestedSessions]).
class _SuggestedSessionCard extends StatefulWidget {
  const _SuggestedSessionCard({
    required this.session,
    required this.onOpen,
    required this.onAdd,
  });

  final Session session;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  State<_SuggestedSessionCard> createState() => _SuggestedSessionCardState();
}

class _SuggestedSessionCardState extends State<_SuggestedSessionCard> {
  // The card's banner: the session's explicit hero, or its first gallery photo.
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.session.heroImageUrl;
    if (_imageUrl == null) _resolveFromGallery();
  }

  Future<void> _resolveFromGallery() async {
    final photos =
        await sessionMediaRepository.fetchPhotos(widget.session.id);
    if (!mounted || photos.isEmpty) return;
    setState(() => _imageUrl = photos.first.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    return SizedBox(
      width: 230,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: widget.onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _imageUrl == null
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.photo_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Image.network(
                        _imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${s.timeLabel} · ${s.seatsLeft} '
                      'seat${s.seatsLeft == 1 ? '' : 's'} left',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: widget.onAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width hero banner for the session page.
class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

/// A horizontal gallery strip of the session's photos.
class _Gallery extends StatelessWidget {
  const _Gallery({required this.photos});
  final List<GalleryPhoto> photos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            photos[i].imageUrl,
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 220,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
