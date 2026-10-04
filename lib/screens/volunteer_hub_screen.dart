import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';
import '../models/user_profile.dart';

/// The volunteer hub: every other volunteer, each tagged student / parent /
/// EAF ambassador, with a tap-through card showing their mobile number so
/// volunteers can coordinate on summit day. Opened by volunteers (and admins);
/// `fetch_volunteer_hub` enforces that server-side.
class VolunteerHubScreen extends StatefulWidget {
  const VolunteerHubScreen({super.key});

  @override
  State<VolunteerHubScreen> createState() => _VolunteerHubScreenState();
}

class _VolunteerHubScreenState extends State<VolunteerHubScreen> {
  bool _loading = true;
  String? _error;
  List<VolunteerRef> _volunteers = const [];
  String _query = '';

  /// Subtype filter; null shows everyone.
  VolunteerSubtype? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _volunteers.isEmpty;
      _error = null;
    });
    try {
      final list = await assignmentRepository.fetchVolunteerHub();
      if (!mounted) return;
      setState(() {
        _volunteers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load the volunteer hub. Check your connection and "
            'try again.';
        _loading = false;
      });
    }
  }

  List<VolunteerRef> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final v in _volunteers)
        if ((_filter == null ||
                VolunteerSubtypeX.fromId(v.subtype) == _filter) &&
            (q.isEmpty || v.name.toLowerCase().contains(q)))
          v,
    ];
  }

  int _count(VolunteerSubtype s) =>
      _volunteers.where((v) => VolunteerSubtypeX.fromId(v.subtype) == s).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Volunteer hub')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _Message(
                    text: _error!,
                    action: FilledButton(
                        onPressed: _load, child: const Text('Try again')),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _buildList(theme),
                  ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final visible = _visible;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Tap a volunteer to see their number. Numbers are shared here so '
          'volunteers can reach each other on summit day.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search volunteers',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _filterChip('All (${_volunteers.length})', null),
            for (final s in [
              VolunteerSubtype.studentVolunteer,
              VolunteerSubtype.parentVolunteer,
              VolunteerSubtype.eafAmbassador,
            ])
              _filterChip('${_shortLabel(s)}s (${_count(s)})', s),
          ],
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Text(
              _volunteers.isEmpty
                  ? 'No other volunteers have signed up yet.'
                  : 'No volunteers match.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final v in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _VolunteerCard(
                volunteer: v,
                onTap: () => _showVolunteerSheet(context, v),
              ),
            ),
      ],
    );
  }

  Widget _filterChip(String label, VolunteerSubtype? value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

/// "Student", "Parent", "EAF Ambassador" — the tag shown on each card.
String _shortLabel(VolunteerSubtype s) => switch (s) {
      VolunteerSubtype.studentVolunteer => 'Student',
      VolunteerSubtype.parentVolunteer => 'Parent',
      VolunteerSubtype.eafAmbassador => 'EAF Ambassador',
    };

String _displayName(VolunteerRef v) => v.name.isEmpty ? 'Volunteer' : v.name;

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = parts.map((w) => w[0]).take(2).join().toUpperCase();
  return letters.isEmpty ? '?' : letters;
}

/// Tag colors per subtype, from the theme so they follow light/dark.
({Color bg, Color fg}) _tagColors(ColorScheme cs, VolunteerSubtype? s) =>
    switch (s) {
      VolunteerSubtype.studentVolunteer =>
        (bg: cs.primaryContainer, fg: cs.onPrimaryContainer),
      VolunteerSubtype.parentVolunteer =>
        (bg: cs.tertiaryContainer, fg: cs.onTertiaryContainer),
      _ => (bg: cs.surfaceContainerHighest, fg: cs.onSurface),
    };

class _SubtypeTag extends StatelessWidget {
  const _SubtypeTag(this.subtype);

  final VolunteerSubtype? subtype;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _tagColors(theme.colorScheme, subtype);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        subtype == null ? 'Volunteer' : _shortLabel(subtype!),
        style: theme.textTheme.labelMedium?.copyWith(color: colors.fg),
      ),
    );
  }
}

class _VolunteerCard extends StatelessWidget {
  const _VolunteerCard({required this.volunteer, required this.onTap});

  final VolunteerRef volunteer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtype = VolunteerSubtypeX.fromId(volunteer.subtype);
    final colors = _tagColors(theme.colorScheme, subtype);
    final name = _displayName(volunteer);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.bg,
                child: Text(_initials(name),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: colors.fg)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    _SubtypeTag(subtype),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showVolunteerSheet(BuildContext context, VolunteerRef v) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _VolunteerSheet(volunteer: v),
  );
}

class _VolunteerSheet extends StatelessWidget {
  const _VolunteerSheet({required this.volunteer});

  final VolunteerRef volunteer;

  Future<void> _launch(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open that on this device.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtype = VolunteerSubtypeX.fromId(volunteer.subtype);
    final colors = _tagColors(theme.colorScheme, subtype);
    final name = _displayName(volunteer);
    final phone = volunteer.phone?.trim() ?? '';
    final dial = phone.replaceAll(RegExp(r'[^0-9+]'), '');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colors.bg,
                  child: Text(_initials(name),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: colors.fg)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtype?.label ?? 'Volunteer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Mobile number',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            if (phone.isEmpty)
              Text('Not provided', style: theme.textTheme.titleMedium)
            else
              Row(
                children: [
                  Expanded(
                    child: SelectableText(phone,
                        style: theme.textTheme.headlineSmall),
                  ),
                  IconButton(
                    tooltip: 'Copy number',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: phone));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Number copied')));
                    },
                  ),
                ],
              ),
            if (dial.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call'),
                      onPressed: () =>
                          _launch(context, Uri(scheme: 'tel', path: dial)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Text'),
                      onPressed: () =>
                          _launch(context, Uri(scheme: 'sms', path: dial)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
