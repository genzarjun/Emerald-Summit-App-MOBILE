import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';
import 'front_desk_scanner_screen.dart';

/// Front-desk (summit-wide) check-in. A volunteer with the front-desk capability
/// scans attendees' QR passes ([FrontDeskScannerScreen]), or searches every
/// attendee and marks them as arrived — the list is the fallback for anyone
/// without their pass, and for fixing mistakes. Live stats up top. Stats and
/// list re-sync whenever ANY desk checks someone in or out (realtime, with a
/// slow poll as a backstop), so several volunteers can work the door at once.
/// Independent of session assignments; the capability is enforced server-side
/// by every RPC here.
class FrontDeskScreen extends StatefulWidget {
  const FrontDeskScreen({super.key});

  @override
  State<FrontDeskScreen> createState() => _FrontDeskScreenState();
}

class _FrontDeskScreenState extends State<FrontDeskScreen> {
  bool _loading = true;
  String? _error;
  List<Attendee> _attendees = const [];
  String _query = '';
  Timer? _debounce;

  /// Null until loaded, and while the stats can't be read.
  CheckinStats? _stats;
  StreamSubscription<void>? _changes;
  Timer? _syncDebounce;
  Timer? _poll;

  /// Bumped per directory request so a slow, stale response (an older query,
  /// or a background sync racing a search) never overwrites a newer one.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
    _changes = attendanceRepository.checkinChanges().listen(
      (_) => _scheduleSync(),
    );
    // Backstop for a dropped realtime connection.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _sync());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _syncDebounce?.cancel();
    _poll?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  /// [silent] refreshes in place (no spinner, keeps the list on failure) —
  /// used when another desk's change arrives.
  Future<void> _load({bool silent = false}) async {
    final seq = ++_loadSeq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await attendanceRepository.fetchAttendeeDirectory(_query);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _attendees = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq || silent) return;
      setState(() {
        _error = "Couldn't load attendees. You may not have front-desk access.";
        _loading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await attendanceRepository.fetchCheckinStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // Keep the last numbers; the next change or poll retries.
    }
  }

  /// A burst of check-ins (several desks at once) becomes one refresh.
  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 400), _sync);
  }

  void _sync() {
    if (!mounted) return;
    _loadStats();
    if (!_loading) _load(silent: true);
  }

  void _onQueryChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _toggle(Attendee a, bool value) async {
    final i = _attendees.indexWhere((x) => x.id == a.id);
    if (i < 0) return;
    setState(() => _attendees[i] = _attendees[i].copyWith(present: value));
    try {
      await attendanceRepository.markSummitCheckin(a.id, value);
      _loadStats();
    } catch (e) {
      if (!mounted) return;
      // A background sync may have replaced the list meanwhile; re-find by id.
      final j = _attendees.indexWhere((x) => x.id == a.id);
      if (j >= 0) {
        setState(() => _attendees[j] = _attendees[j].copyWith(present: !value));
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save check-in.')));
    }
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FrontDeskScannerScreen()),
    );
    // Pick up everyone the scanner checked in.
    if (mounted) _sync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = _attendees.where((a) => a.present).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Front desk check-in')),
      body: SafeArea(
        child: Column(
          children: [
            if (_stats != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _StatsRow(stats: _stats!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR passes'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name or email',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$present checked in of ${_attendees.length} shown',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : _attendees.isEmpty
                  ? Center(
                      child: Text(
                        'No matching attendees.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _attendees.length,
                      itemBuilder: (context, i) {
                        final a = _attendees[i];
                        return SwitchListTile(
                          value: a.present,
                          onChanged: (v) => _toggle(a, v),
                          title: Text(a.name.isEmpty ? a.email : a.name),
                          subtitle: Text(
                            a.present ? 'Checked in' : 'Not arrived',
                          ),
                          secondary: CircleAvatar(
                            backgroundColor: a.present
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              a.present
                                  ? Icons.how_to_reg
                                  : Icons.person_outline,
                              color: a.present
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const Divider(height: 1),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everyone / Participants / Volunteers: checked in of total, live.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final CheckinStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(label: 'Checked in', count: stats.everyone),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(label: 'Participants', count: stats.participants),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(label: 'Volunteers', count: stats.volunteers),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.count});

  final String label;
  final CheckinCount count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    return Semantics(
      label: '$label: ${count.checkedIn} of ${count.total}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: s.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: s.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${count.checkedIn}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: s.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${count.total}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: s.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: count.total == 0 ? 0 : count.checkedIn / count.total,
                minHeight: 4,
                backgroundColor: s.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
