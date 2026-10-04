import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme.dart';

/// What the registration form hands back: the participant's project answer plus
/// their answers to the session's own questions (question id → answer).
class RegistrationFormResult {
  const RegistrationFormResult({required this.project, required this.answers});

  final ProjectChoice project;
  final Map<String, String> answers;
}

/// The participant registration form for one session. Always asks the app's
/// built-in project question — solo (with a project name) or team (create one
/// and get a code, or join a teammate's by code, confirming its project name) —
/// followed by any questions the session's editors added. Pops a
/// [RegistrationFormResult], or null if the user backs out.
///
/// With [editing] true it revises an existing registration: [initialProject]
/// and [initialAnswers] prefill the form, and a team member can stay on their
/// team (renaming its project) instead of creating/joining one.
class SessionRegistrationScreen extends StatefulWidget {
  const SessionRegistrationScreen({
    super.key,
    required this.session,
    this.editing = false,
    this.initialProject,
    this.initialAnswers = const {},
  });

  final Session session;
  final bool editing;
  final MyProject? initialProject;
  final Map<String, String> initialAnswers;

  @override
  State<SessionRegistrationScreen> createState() =>
      _SessionRegistrationScreenState();
}

class _SessionRegistrationScreenState extends State<SessionRegistrationScreen> {
  /// Solo (false) or team (true); null until the user picks.
  bool? _isTeam;

  /// Within team mode: create, join, or (editing an existing team) stay.
  ProjectAction? _teamAction;

  late final TextEditingController _soloName;
  late final TextEditingController _newTeamName;
  late final TextEditingController _stayName;
  final TextEditingController _code = TextEditingController();

  /// The team the user confirmed ("Is your project name …?" → Yes).
  ({String code, String projectName})? _confirmedTeam;
  bool _lookingUp = false;
  String? _codeError;

  late final Map<String, TextEditingController> _answers = {
    for (final q in widget.session.participantQuestions)
      q.id: TextEditingController(text: widget.initialAnswers[q.id] ?? ''),
  };
  String? _error;

  bool get _onTeamNow => widget.initialProject?.isTeam ?? false;

  /// The session's editors turned teams off.
  bool get _soloOnly => !widget.session.teamsAllowed;

  /// Solo-only sessions skip the solo/team question — unless the user is
  /// already on a team from before teams were turned off, who may keep it.
  bool get _askSoloOrTeam => !_soloOnly || _onTeamNow;

  /// True when saving would take an owner (with teammates) off their team, so
  /// they'll be asked to choose a new owner.
  bool get _willHandOff {
    final p = widget.initialProject;
    if (p == null || !p.mustHandOff || _isTeam == null) return false;
    if (_isTeam == false) return true;
    return switch (_teamAction) {
      ProjectAction.createTeam => true,
      ProjectAction.joinTeam =>
        _confirmedTeam != null && _confirmedTeam!.code != p.teamCode,
      _ => false,
    };
  }

  String get _prefix => teamCodePrefix(
    widget.session.disciplineId,
    widget.session.disciplineName,
  );

  @override
  void initState() {
    super.initState();
    final p = widget.initialProject;
    _isTeam = p?.isTeam ?? (_soloOnly ? false : null);
    if (_onTeamNow) _teamAction = ProjectAction.stayOnTeam;
    _soloName = TextEditingController(
      text: p != null && !p.isTeam ? p.projectName : '',
    );
    _newTeamName = TextEditingController();
    _stayName = TextEditingController(text: _onTeamNow ? p!.projectName : '');
  }

  @override
  void dispose() {
    for (final c in [_soloName, _newTeamName, _stayName, _code]) {
      c.dispose();
    }
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Looks up the typed code and asks the user to confirm the team's project.
  Future<void> _findTeam() async {
    final code = normalizeTeamCode(_code.text);
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter the code your teammate shared.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _lookingUp = true;
      _codeError = null;
    });
    TeamLookup lookup;
    try {
      lookup = await appState.findTeam(widget.session, code);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _codeError = "Couldn't check that code. Try again.";
      });
      return;
    }
    if (!mounted) return;
    setState(() => _lookingUp = false);
    if (lookup.problem != null) {
      setState(() => _codeError = lookup.problem);
      return;
    }
    final name = lookup.projectName ?? '';
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your team'),
        content: Text.rich(
          TextSpan(
            children: [
              // A reworded project question can't be phrased as "Is your
              // project name …?", so it shows the question and the answer.
              if (widget.session.customProjectPrompt == null)
                const TextSpan(text: 'Is your project name ')
              else
                TextSpan(
                  text: 'Is this your team?\n\n'
                      '${widget.session.projectPrompt}\n',
                ),
              TextSpan(
                text: '"$name"',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (widget.session.customProjectPrompt == null)
                const TextSpan(text: '?'),
              if (lookup.memberCount > 0)
                TextSpan(
                  text:
                      '\n\nTeam $code already has ${lookup.memberCount} '
                      'member${lookup.memberCount == 1 ? '' : 's'}.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Yes, that's us"),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (yes == true) {
      setState(() => _confirmedTeam = (code: code, projectName: name));
    } else {
      setState(
        () => _codeError =
            'Double-check the code with your teammate and try again.',
      );
    }
  }

  void _submit() {
    setState(() => _error = null);
    ProjectChoice project;
    if (_isTeam == null) {
      setState(
        () => _error =
            'Choose whether you\'re participating solo or '
            'as a team.',
      );
      return;
    }
    if (_isTeam == false) {
      final name = _soloName.text.trim();
      if (name.isEmpty) {
        setState(() => _error = _projectMissing);
        return;
      }
      project = ProjectChoice.solo(name);
    } else {
      switch (_teamAction) {
        case null:
          setState(() => _error = 'Create a team or join one with a code.');
          return;
        case ProjectAction.createTeam:
          final name = _newTeamName.text.trim();
          if (name.isEmpty) {
            setState(() => _error = _projectMissing);
            return;
          }
          project = ProjectChoice.createTeam(name);
        case ProjectAction.joinTeam:
          final team = _confirmedTeam;
          if (team == null) {
            setState(
              () => _error =
                  'Enter your team code and tap "Find team" to confirm it.',
            );
            return;
          }
          project = ProjectChoice.joinTeam(team.code);
        case ProjectAction.stayOnTeam:
          final name = _stayName.text.trim();
          project = ProjectChoice.stayOnTeam(name.isEmpty ? null : name);
        case ProjectAction.solo:
          return; // not offered within team mode
      }
    }

    final answers = <String, String>{};
    for (final q in widget.session.participantQuestions) {
      final text = _answers[q.id]!.text.trim();
      if (text.isEmpty) {
        setState(() => _error = 'Please answer every question.');
        return;
      }
      answers[q.id] = text;
    }
    Navigator.of(context)
        .pop(RegistrationFormResult(project: project, answers: answers));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = widget.session.participantQuestions;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing ? 'Edit my registration' : 'Register'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(widget.session.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              '${widget.session.disciplineName} · ${widget.session.timeLabel}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (!_askSoloOrTeam) ...[
              const _Note(
                text:
                    'This session is solo only — every participant works on '
                    'their own project.',
              ),
              const SizedBox(height: 20),
            ] else ...[
              Text(
                DefaultQuestions.soloOrTeam,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.person_outline),
                      label: Text('Solo'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.groups_outlined),
                      label: Text('Team'),
                    ),
                  ],
                  selected: {?_isTeam},
                  onSelectionChanged: (sel) => setState(() {
                    _isTeam = sel.isEmpty ? _isTeam : sel.first;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              _Note(
                text: _soloOnly
                    ? 'This session is now solo only. You can stay on your '
                          "team or go solo, but teams can't be created or joined."
                    : DefaultQuestions.unsureNote,
              ),
              const SizedBox(height: 20),
            ],
            if (_isTeam == false) _soloSection(theme),
            if (_isTeam == true) _teamSection(theme),
            if (_willHandOff) ...[
              const SizedBox(height: 14),
              _Note(
                text:
                    'You own "${widget.initialProject!.projectName}". '
                    "After you save, you'll pick the teammate who takes it "
                    'over.',
              ),
            ],
            if (questions.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('A few more questions', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'The session organizers ask participants to share this.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (final q in questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: _answers[q.id],
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: q.prompt,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 28),
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _lookingUp ? null : _submit,
              icon: const Icon(Icons.check),
              label: Text(widget.editing ? 'Save changes' : 'Confirm & add'),
            ),
          ],
        ),
      ),
    );
  }

  /// The error when the built-in project question is left blank.
  String get _projectMissing => widget.session.customProjectPrompt == null
      ? 'Please enter your project name.'
      : 'Please answer "${widget.session.projectPrompt}"';

  /// The built-in project question (in the session's wording) above its answer
  /// field. Shown as text, not a field label, so long rewordings wrap.
  Widget _projectField(
    ThemeData theme,
    TextEditingController controller, {
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.session.projectPrompt, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Your answer',
            helperText: helperText,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _soloSection(ThemeData theme) => _projectField(theme, _soloName);

  Widget _teamSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ProjectAction>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              if (_onTeamNow)
                const ButtonSegment(
                  value: ProjectAction.stayOnTeam,
                  label: Text('My team'),
                ),
              if (!_soloOnly) ...const [
                ButtonSegment(
                  value: ProjectAction.createTeam,
                  icon: Icon(Icons.add),
                  label: Text('Create'),
                ),
                ButtonSegment(
                  value: ProjectAction.joinTeam,
                  icon: Icon(Icons.login),
                  label: Text('Join'),
                ),
              ],
            ],
            selected: {?_teamAction},
            onSelectionChanged: (sel) => setState(() {
              _teamAction = sel.isEmpty ? _teamAction : sel.first;
              _error = null;
            }),
          ),
        ),
        const SizedBox(height: 16),
        switch (_teamAction) {
          ProjectAction.stayOnTeam => _staySection(theme),
          ProjectAction.createTeam => _createSection(theme),
          ProjectAction.joinTeam => _joinSection(theme),
          _ => Text(
            'Starting a team? Create it and share the code. Have a code '
            'from a teammate? Join their team.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        },
      ],
    );
  }

  Widget _staySection(ThemeData theme) {
    final p = widget.initialProject!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _projectField(
          theme,
          _stayName,
          helperText: 'Changing this changes it for your whole team.',
        ),
        if (p.teamCode != null) ...[
          const SizedBox(height: 12),
          Text('Team code: ${p.teamCode}', style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  Widget _createSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _projectField(theme, _newTeamName),
        const SizedBox(height: 10),
        Text(
          "You'll get a team code (like ${_prefix}1234) to share with your "
          'teammates. They enter it when they register for this session. '
          'Teams here can have up to ${widget.session.maxTeamSize} members, '
          "and you'll be the team's owner.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _joinSection(ThemeData theme) {
    final team = _confirmedTeam;
    if (team != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.verified_outlined,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.projectName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Joining team ${team.code}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _confirmedTeam = null),
              child: const Text('Change'),
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _findTeam(),
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            decoration: InputDecoration(
              labelText: DefaultQuestions.teamCode,
              hintText: 'e.g. ${_prefix}1234',
              errorText: _codeError,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FilledButton.tonal(
            // The theme's full-width minimum size can't lay out inside a Row.
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _lookingUp ? null : _findTeam,
            child: _lookingUp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Find team'),
          ),
        ),
      ],
    );
  }
}

/// A soft info note (the "not sure yet? register solo" reassurance).
class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EmeraldTheme.mist,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: EmeraldTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
