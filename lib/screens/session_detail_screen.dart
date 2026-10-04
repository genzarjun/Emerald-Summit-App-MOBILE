import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';
import 'session_editor_screen.dart';
import 'session_registration_screen.dart';
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
///   * **Volunteers** (admins, the session's organizers, and its editors) — who's
///     organizing the session, with their numbers; admins also assign/unassign.
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
        // Admins and volunteers who manage this session take attendance; the
        // session's editors also see the people tabs (read-only) so they can
        // follow who's working on which project.
        final canMarkAttendance =
            appState.isAdmin || appState.isManaging(current.id);
        final canSeeRoster = canMarkAttendance || canEdit;
        // Organizers and editors see their co-workers; only admins assign.
        final canSeeVolunteers = canSeeRoster;

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
        if (canSeeRoster) {
          tabs.add(const Tab(text: 'Participants'));
          views.add(
            SessionRosterView(
              session: current,
              types: const {
                ParticipationType.participant,
                ParticipationType.spectator,
              },
              canMarkAttendance: canMarkAttendance,
              emptyMessage:
                  'No participants have registered for this session '
                  'yet.',
            ),
          );
          tabs.add(const Tab(text: 'Experts'));
          views.add(
            SessionRosterView(
              session: current,
              types: const {ParticipationType.expert},
              canMarkAttendance: canMarkAttendance,
              emptyMessage: 'No experts have registered for this session yet.',
            ),
          );
        }
        if (canSeeVolunteers) {
          tabs.add(const Tab(text: 'Volunteers'));
          views.add(SessionVolunteersView(
              session: current, canAssign: appState.isAdmin));
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

  /// The viewer's project for this session (solo, or their team + code), shown
  /// once they've registered as a participant. Null when not loaded/answered.
  MyProject? _project;
  bool _projectLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _loadProject();
  }

  Future<void> _loadProject() async {
    if (appState.participationOf(widget.session.id) !=
        ParticipationType.participant) {
      if (mounted) setState(() => _project = null);
      return;
    }
    MyProject? project;
    try {
      project = await appState.myProject(widget.session);
    } catch (_) {
      project = null;
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _projectLoaded = true;
    });
  }

  Future<void> _loadPhotos() async {
    final photos = await sessionMediaRepository.fetchPhotos(widget.session.id);
    if (!mounted) return;
    setState(() => _photos = photos);
  }

  /// Entry point for the "Add to my day" button and the suggested-session Add.
  /// Routes by role: the Parent/Spectator role auto-spectates; everyone else
  /// picks a mode, and participating collects the session's questions first.
  Future<void> _addToDay(Session s) async {
    if (appState.autoSpectates) {
      await _register(s, ParticipationType.spectator);
      return;
    }
    final modes = appState.myAddModes;
    // A single non-manage option (shouldn't happen for these roles, but be safe)
    // still deserves the chooser so the user knows what they're agreeing to.
    final mode = await _pickAddMode(s, modes);
    if (mode == null || !mounted) return;

    if (mode == AddMode.manage) {
      await _setManage(s, true);
      return;
    }
    final type = mode.participationType!;
    if (type == ParticipationType.participant) {
      // Every participant answers the built-in solo/team question, plus any
      // questions the session's editors added.
      final form = await Navigator.of(context).push(
        MaterialPageRoute<RegistrationFormResult>(
          fullscreenDialog: true,
          builder: (_) => SessionRegistrationScreen(session: s),
        ),
      );
      if (form == null || !mounted) return; // cancelled
      await _register(s, type, answers: form.answers, project: form.project);
    } else {
      await _register(s, type);
    }
  }

  /// Shows the role-appropriate mode chooser. Returns the chosen [AddMode], or
  /// null if dismissed. Past [s]'s participant deadline, Participate is shown
  /// but disabled, so people see why they can only spectate.
  Future<AddMode?> _pickAddMode(Session s, List<AddMode> modes) {
    final theme = Theme.of(context);
    final isVolunteer = appState.isVolunteer;
    final deadline = s.participantDeadline;
    return showModalBottomSheet<AddMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Add to my day', style: theme.textTheme.titleLarge),
            ),
            for (final m in modes)
              if (m == AddMode.participate && s.participationClosed)
                ListTile(
                  enabled: false,
                  leading: Icon(m.icon),
                  title: Text(m.title),
                  subtitle: Text(
                    'Registration to participate closed on '
                    '${formatDeadline(deadline!)}.',
                  ),
                )
              else
                ListTile(
                  leading: Icon(m.icon, color: theme.colorScheme.primary),
                  title: Text(m.title),
                  subtitle: Text(
                    m == AddMode.participate && deadline != null
                        ? '${m.blurb} Closes ${formatDeadline(deadline)}.'
                        : m.blurb,
                  ),
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
            if (isVolunteer)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'To manage this session, an admin will assign you — '
                        "you'll be notified if they do.",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Lets a registered participant revise their project (solo ↔ team, a
  /// different team, a renamed project) and the answers they gave on joining.
  Future<void> _editRegistration(Session s) async {
    final messenger = ScaffoldMessenger.of(context);
    Map<String, String> answers;
    try {
      answers = await appState.myAnswers(s);
    } catch (_) {
      answers = const {};
    }
    if (!mounted) return;
    final form = await Navigator.of(context).push(
      MaterialPageRoute<RegistrationFormResult>(
        fullscreenDialog: true,
        builder: (_) => SessionRegistrationScreen(
          session: s,
          editing: true,
          initialProject: _project,
          initialAnswers: answers,
        ),
      ),
    );
    if (form == null || !mounted) return;
    // Leaving the current team (to go solo, start a new one, or join another)
    // means an owner with teammates hands the team over first.
    final current = _project;
    final leavingTeam = current != null &&
        current.isTeam &&
        switch (form.project.action) {
          ProjectAction.stayOnTeam => false,
          ProjectAction.joinTeam =>
            normalizeTeamCode(form.project.teamCode ?? '') != current.teamCode,
          _ => true,
        };
    String? newOwnerId;
    if (leavingTeam) {
      final handOff = await _handOffIfNeeded(s, action: 'leave');
      if (!handOff.proceed || !mounted) return;
      newOwnerId = handOff.newOwnerId;
    }
    messenger.hideCurrentSnackBar();
    try {
      final project = await appState.updateMyRegistration(
        s,
        answers: form.answers,
        project: form.project,
        newOwnerId: newOwnerId,
      );
      if (!mounted) return;
      setState(() => _project = project);
      if (form.project.action == ProjectAction.createTeam &&
          project.teamCode != null) {
        await _showTeamCode(project.teamCode!, project.projectName);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Your registration was updated')),
        );
      }
    } on TeamCodeException catch (e) {
      _showBlockedDialog('Couldn\'t update your team', e.message);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save your changes. Try again.")),
      );
    }
  }

  /// Re-reads the user's project (teammates may have joined since the page
  /// loaded) and, when they own a team that still has others on it, asks which
  /// teammate takes over. `proceed` is false if they back out.
  Future<({bool proceed, String? newOwnerId})> _handOffIfNeeded(
    Session s, {
    required String action,
  }) async {
    MyProject? fresh;
    try {
      fresh = await appState.myProject(s);
    } catch (_) {
      fresh = _project;
    }
    if (!mounted) return (proceed: false, newOwnerId: null);
    if (fresh == null || !fresh.mustHandOff) {
      return (proceed: true, newOwnerId: null);
    }
    final id = await _pickNewOwner(
      fresh,
      title: 'Choose a new owner',
      blurb: 'You own "${fresh.projectName}". Pick the teammate who takes it '
          'over before you $action.',
    );
    return (proceed: id != null, newOwnerId: id);
  }

  /// A sheet listing [p]'s other members; returns the chosen member's id.
  Future<String?> _pickNewOwner(
    MyProject p, {
    required String title,
    required String blurb,
  }) {
    final theme = Theme.of(context);
    final candidates = [
      for (final m in p.members)
        if (!m.isOwner && m.id.isNotEmpty) m,
    ];
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  blurb,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final m in candidates)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(m.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(ctx).pop(m.id),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Leaves the user's team and keeps them registered as a solo participant.
  Future<void> _leaveTeam(Session s) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _LeaveTeamDialog(
        initialProjectName: _project?.projectName ?? '',
        prompt: s.projectPrompt,
      ),
    );
    if (name == null || !mounted) return;
    final handOff = await _handOffIfNeeded(s, action: 'leave');
    if (!handOff.proceed || !mounted) return;
    Map<String, String> answers;
    try {
      answers = await appState.myAnswers(s);
    } catch (_) {
      answers = const {};
    }
    try {
      final project = await appState.updateMyRegistration(
        s,
        answers: answers,
        project: ProjectChoice.solo(name),
        newOwnerId: handOff.newOwnerId,
      );
      if (!mounted) return;
      setState(() => _project = project);
      messenger.showSnackBar(
        const SnackBar(
          content: Text("You left the team — you're now registered solo."),
        ),
      );
    } on TeamCodeException catch (e) {
      _showBlockedDialog("Couldn't leave the team", e.message);
      _loadProject();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't leave the team. Try again.")),
      );
    }
  }

  /// Lets a team owner take [member] off the team (e.g. someone who got the
  /// code but isn't really a teammate). They stay registered for the session.
  Future<void> _removeMember(Session s, TeamMember member) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: const Text(
          "They'll be taken off your team but stay registered for this "
          "session, and they'll be notified. They won't be able to rejoin "
          'your team with its code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await appState.removeTeamMember(s, member.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Removed ${member.name} from your team')),
      );
    } on TeamCodeException catch (e) {
      _showBlockedDialog("Couldn't remove them", e.message);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't remove them. Try again.")),
      );
    }
    _loadProject();
  }

  /// Lets a team owner hand the team to a teammate while staying on it.
  Future<void> _transferOwnership(Session s) async {
    final messenger = ScaffoldMessenger.of(context);
    MyProject? fresh;
    try {
      fresh = await appState.myProject(s);
    } catch (_) {
      fresh = _project;
    }
    if (fresh == null || !fresh.mustHandOff || !mounted) return;
    final id = await _pickNewOwner(
      fresh,
      title: 'Transfer ownership',
      blurb: "Pick the teammate who'll own \"${fresh.projectName}\". You'll "
          'stay on the team.',
    );
    if (id == null || !mounted) return;
    try {
      await appState.transferTeamOwnership(s, id);
      final name = fresh.members.firstWhere((m) => m.id == id).name;
      messenger.showSnackBar(
        SnackBar(content: Text('$name now owns the team')),
      );
    } on TeamCodeException catch (e) {
      _showBlockedDialog("Couldn't transfer ownership", e.message);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't transfer ownership. Try again.")),
      );
    }
    _loadProject();
  }

  /// Shows a newly created team's code, ready to copy and share.
  Future<void> _showTeamCode(String code, String projectName) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.groups_outlined),
        title: const Text('Your team is ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              projectName,
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _TeamCodeChip(code: code),
            const SizedBox(height: 16),
            const Text(
              'Share this code with your teammates. They enter it when they '
              'register for this session to join your team. You can always '
              'find it again on this page.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Registers [s] under [type], surfacing full/conflict blocks.
  Future<void> _register(
    Session s,
    ParticipationType type, {
    Map<String, String> answers = const {},
    ProjectChoice? project,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await appState.toggle(
      s,
      type: type,
      answers: answers,
      project: project,
    );
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (s.id == widget.session.id) _loadProject();
    switch (result.outcome) {
      case AddOutcome.added:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Added "${s.title}" — ${type.chipLabel.toLowerCase()}',
            ),
          ),
        );
        if (result.teamCode != null) {
          await _showTeamCode(result.teamCode!, project?.projectName ?? '');
        }
      case AddOutcome.removed:
        messenger.showSnackBar(
          SnackBar(content: Text('Removed "${s.title}" from your day')),
        );
      case AddOutcome.invalidProject:
        _showBlockedDialog(
          "Couldn't register",
          result.message ?? 'Check your project details and try again.',
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
      case AddOutcome.participationClosed:
        final deadline = s.participantDeadline;
        final when =
            deadline == null ? '' : ' on ${formatDeadline(deadline)}';
        _showBlockedDialog(
          'Participant registration closed',
          'Registration to participate closed$when. You can still add this '
              'session as a spectator while seats are left.',
        );
    }
  }

  /// Removes [s] from the day (toggles the registration off). A team owner
  /// with teammates picks a new owner first.
  Future<void> _removeFromDay(Session s) async {
    final messenger = ScaffoldMessenger.of(context);
    String? newOwnerId;
    if (appState.participationOf(s.id) == ParticipationType.participant) {
      final handOff = await _handOffIfNeeded(s, action: 'remove this session');
      if (!handOff.proceed || !mounted) return;
      newOwnerId = handOff.newOwnerId;
    }
    final result = await appState.toggle(s, newOwnerId: newOwnerId);
    if (!mounted) return;
    if (result.outcome == AddOutcome.invalidProject) {
      _showBlockedDialog(
        "Couldn't remove this session",
        result.message ?? 'Try again.',
      );
      _loadProject();
      return;
    }
    if (s.id == widget.session.id) setState(() => _project = null);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.outcome == AddOutcome.removed
                ? 'Removed "${s.title}" from your day'
                : 'Updated your day',
          ),
        ),
      );
  }

  /// Admin self-manage toggle for [s].
  Future<void> _setManage(Session s, bool manage) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await appState.setManage(s, manage);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    switch (result.outcome) {
      case AddOutcome.added:
        messenger.showSnackBar(
          SnackBar(content: Text('You\'re now managing "${s.title}"')),
        );
      case AddOutcome.removed:
        messenger.showSnackBar(
          SnackBar(content: Text('Stopped managing "${s.title}"')),
        );
      case AddOutcome.conflict:
        _showBlockedDialog(
          'Time conflict',
          'Managing this overlaps with "${result.conflictingTitle}", which is '
              'already on your schedule.',
        );
      case AddOutcome.full:
      case AddOutcome.invalidProject:
      case AddOutcome.participationClosed:
        break; // not applicable to managing
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
    final heroUrl =
        current.heroImageUrl ??
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
              if (current.track.trim().isNotEmpty) ...[
                Text(
                  current.track.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
              ],
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
              if (current.participantDeadline != null || widget.canEdit) ...[
                const SizedBox(height: 12),
                _ParticipantDeadlineCard(
                  session: current,
                  registered: registered || managing,
                  canEdit: widget.canEdit,
                ),
              ],
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
                    color: theme.colorScheme.surfaceContainer,
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
                _ManagingCard(
                  // An admin who self-managed (or manages any session) can stop;
                  // a volunteer was assigned by an admin and cannot.
                  onStop: appState.isAdmin
                      ? () => _setManage(current, false)
                      : null,
                )
              else if (registered) ...[
                _RegisteredStatus(
                  type:
                      appState.participationOf(current.id) ??
                      ParticipationType.participant,
                ),
                if (appState.participationOf(current.id) ==
                    ParticipationType.participant) ...[
                  if (_projectLoaded) ...[
                    const SizedBox(height: 12),
                    _ProjectCard(
                      project: _project,
                      onLeave: () => _leaveTeam(current),
                      onTransfer: () => _transferOwnership(current),
                      onRemoveMember: (m) => _removeMember(current, m),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _editRegistration(current),
                    icon: const Icon(Icons.edit_note),
                    label: Text(
                      _projectLoaded && _project == null
                          ? 'Add my project details'
                          : 'Edit my registration',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _removeFromDay(current),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                  ),
                  icon: const Icon(Icons.remove_circle),
                  label: const Text('Remove from my day'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: () => _addToDay(current),
                  icon: const Icon(Icons.add),
                  label: const Text('Add to my day'),
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
                        onAdd: () => _addToDay(s),
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
    final photos = await sessionMediaRepository.fetchPhotos(widget.session.id);
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
                    : CachedNetworkImage(
                        imageUrl: _imageUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 1200,
                        errorWidget: (_, _, _) => Container(
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
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 1200,
        errorWidget: (_, _, _) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        placeholder: (_, _) => Container(
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
          child: CachedNetworkImage(
            imageUrl: photos[i].imageUrl,
            width: 220,
            fit: BoxFit.cover,
            memCacheWidth: 660,
            errorWidget: (_, _, _) => Container(
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

/// Spells out the session's participant deadline: when registering to
/// participate closes (or that it has), and that spectating stays open while
/// seats are left. Editors also see it when no deadline is set, with a pointer
/// to where they set one.
class _ParticipantDeadlineCard extends StatelessWidget {
  const _ParticipantDeadlineCard({
    required this.session,
    required this.registered,
    required this.canEdit,
  });

  final Session session;

  /// Whether the viewer already has this session on their day.
  final bool registered;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final deadline = session.participantDeadline;
    final editorNote = canEdit ? ' You can change this in the editor.' : '';
    final seats = session.seatsLeft;
    final afterClose = session.isFull
        ? 'The session is also full, so there are no spots left to spectate.'
        : registered && !canEdit
            ? 'People who registered before then keep their spot.'
            : 'You can still register to spectate — $seats '
                'spot${seats == 1 ? '' : 's'} left.';

    final (IconData icon, String title, String body, Color bg, Color fg) =
        switch (deadline) {
      null => (
          Icons.event_note_outlined,
          'No participant deadline',
          'People can register to participate any time while seats are left. '
              'Set a deadline in the editor to close participant registration '
              'at a specific date and time.',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      final d when session.participationClosed => (
          Icons.event_busy,
          'Participant registration closed',
          'It closed on ${formatDeadline(d)}. $afterClose$editorNote',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      final d => (
          Icons.how_to_reg_outlined,
          'Register to participate by ${formatDeadline(d)}',
          'After that, nobody can register to participate, but people can '
              'still register to spectate while seats are left.$editorNote',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(color: fg),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "you're managing this session" card. When [onStop] is set (an admin), it
/// offers a "Stop managing" action; a volunteer (null) sees the read-only note
/// that an admin put it on their schedule.
class _ManagingCard extends StatelessWidget {
  const _ManagingCard({this.onStop});
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_ind,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  onStop != null
                      ? "You're managing this session."
                      : "You're managing this session. It was added to your "
                            'schedule by an admin.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (onStop != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Stop managing'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small status line shown when the user has this session on their day,
/// telling them how they joined (participating / spectating / expert).
class _RegisteredStatus extends StatelessWidget {
  const _RegisteredStatus({required this.type});
  final ParticipationType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_available,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              type.statusLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The participant's project on the session page: solo, or their team with
/// its shareable code and members. A null [project] means they registered
/// before the team question existed and haven't answered it yet.
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onLeave,
    required this.onTransfer,
    required this.onRemoveMember,
  });
  final MyProject? project;
  final VoidCallback onLeave;
  final VoidCallback onTransfer;

  /// Owner only: take a teammate off the team.
  final ValueChanged<TeamMember> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = project;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                p == null
                    ? Icons.help_outline
                    : p.isTeam
                        ? Icons.groups_outlined
                        : Icons.person_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                p == null
                    ? 'Your project'
                    : p.isTeam
                        ? 'Team project'
                        : 'Solo project',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (p == null)
            Text(
              "Let the organizers know whether you're working solo or on a "
              'team, and what your project is.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Text(p.projectName, style: theme.textTheme.titleMedium),
            if (p.isTeam && p.teamCode != null) ...[
              const SizedBox(height: 12),
              _TeamCodeChip(code: p.teamCode!),
              const SizedBox(height: 8),
              Text(
                'Share this code with teammates so they can join when they '
                'register for this session.',
                style: muted,
              ),
            ],
            if (p.isTeam && p.members.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Members', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final m in p.members)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        m.isOwner ? Icons.star_rounded : Icons.person_outline,
                        size: 18,
                        color: m.isOwner
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.isOwner ? '${m.name} · Owner' : m.name,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      // The owner can take anyone else off the team.
                      if (p.isOwner && !m.isOwner && m.id.isNotEmpty)
                        IconButton(
                          tooltip: 'Remove ${m.name} from the team',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.person_remove_outlined,
                              size: 20),
                          color: theme.colorScheme.error,
                          onPressed: () => onRemoveMember(m),
                        ),
                    ],
                  ),
                ),
              if (p.teamsAllowed) ...[
                const SizedBox(height: 6),
                Text(
                  'The max number of members your team can have is '
                  '${p.maxTeamSize}.',
                  style: muted,
                ),
              ],
            ],
            if (p.isTeam) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onLeave,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Leave team / go solo'),
                  ),
                  if (p.mustHandOff)
                    TextButton.icon(
                      onPressed: onTransfer,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Transfer ownership'),
                    ),
                ],
              ),
            ],
            if (!p.isTeam && p.teamsAllowed) ...[
              const SizedBox(height: 6),
              Text(
                'Teaming up later? Edit your registration to create or join '
                'a team.',
                style: muted,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A team code in large type with a copy button.
class _TeamCodeChip extends StatelessWidget {
  const _TeamCodeChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            code,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy, size: 20),
            color: theme.colorScheme.secondary,
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              await Clipboard.setData(ClipboardData(text: code));
              messenger?.showSnackBar(
                SnackBar(content: Text('Copied team code $code')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Confirms leaving a team and asks for the solo project name the user will be
/// registered under (prefilled with the team's project).
class _LeaveTeamDialog extends StatefulWidget {
  const _LeaveTeamDialog({
    required this.initialProjectName,
    required this.prompt,
  });
  final String initialProjectName;

  /// The session's wording of the built-in project question.
  final String prompt;

  @override
  State<_LeaveTeamDialog> createState() => _LeaveTeamDialogState();
}

class _LeaveTeamDialogState extends State<_LeaveTeamDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialProjectName);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please answer this to go solo.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leave team?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "You'll stay registered for this session as a solo participant. "
            'You can join or create a team again any time from Edit my '
            'registration.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.prompt,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Your answer',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Leave team'),
        ),
      ],
    );
  }
}
