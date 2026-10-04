import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';
import '../widgets/volunteer_contact.dart';

/// The volunteer hub: every other volunteer and admin, each tagged student
/// volunteer / parent volunteer / EAF ambassador / admin, with a tap-through
/// card showing their mobile number so the team can coordinate on summit day.
/// Opened by volunteers and admins; `fetch_volunteer_hub` enforces that
/// server-side.
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

  /// Group filter; null shows everyone.
  VolunteerGroup? _filter;

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
        _error =
            "Couldn't load the volunteer hub. Check your connection and "
            'try again.';
        _loading = false;
      });
    }
  }

  List<VolunteerRef> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final v in _volunteers)
        if ((_filter == null || volunteerGroupOf(v) == _filter) &&
            (q.isEmpty || v.name.toLowerCase().contains(q)))
          v,
    ];
  }

  int _count(VolunteerGroup g) =>
      _volunteers.where((v) => volunteerGroupOf(v) == g).length;

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
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              )
            : RefreshIndicator(onRefresh: _load, child: _buildList(theme)),
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
          'Tap anyone to see their number. Numbers are shared here so '
          'volunteers and admins can reach each other on summit day.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search by name',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _filterChip('All (${_volunteers.length})', null),
            for (final g in VolunteerGroup.values)
              if (_count(g) > 0) _filterChip('${g.plural} (${_count(g)})', g),
          ],
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Text(
              _volunteers.isEmpty
                  ? 'No other volunteers or admins have signed up yet.'
                  : 'No one matches.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          // One headed section per group (Admins, Student Volunteers, …) so
          // who's who is clear at a glance, on top of each card's tag.
          for (final g in VolunteerGroup.values)
            if (visible.any((v) => volunteerGroupOf(v) == g)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  '${g.plural} · '
                  '${visible.where((v) => volunteerGroupOf(v) == g).length}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final v in visible)
                if (volunteerGroupOf(v) == g)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VolunteerCard(
                      volunteer: v,
                      onTap: () => showVolunteerContactSheet(context, v),
                    ),
                  ),
            ],
      ],
    );
  }

  Widget _filterChip(String label, VolunteerGroup? value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
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
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
