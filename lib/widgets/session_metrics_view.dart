import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/metrics.dart';
import '../models/models.dart';
import 'metrics_widgets.dart';

/// Who a session's Metrics tab counts. Experts have their own tab and no
/// school or grade, so they're left out.
enum _Who { all, participating, spectating }

/// The Metrics tab on a session page, for the people who can see its roster
/// (admins, its assigned volunteers, and editors of its discipline): which
/// schools and grades the people registered for it come from. Counted from
/// the same `fetch_session_roster` the Participants tab reads.
class SessionMetricsView extends StatefulWidget {
  const SessionMetricsView({super.key, required this.session});

  final Session session;

  @override
  State<SessionMetricsView> createState() => _SessionMetricsViewState();
}

class _SessionMetricsViewState extends State<SessionMetricsView> {
  List<RosterEntry>? _roster;
  String? _error;
  _Who _who = _Who.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final roster = await attendanceRepository.fetchSessionRoster(
        widget.session.id,
      );
      if (mounted) setState(() => _roster = roster);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't load this session's metrics. Pull "
              'down to try again.',
        );
      }
    }
  }

  bool _counts(RosterEntry e) => switch (_who) {
    _Who.all => e.participationType != ParticipationType.expert,
    _Who.participating => e.participationType == ParticipationType.participant,
    _Who.spectating => e.participationType == ParticipationType.spectator,
  };

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          MetricsFilter<_Who>(
            options: const [
              (_Who.all, 'Everyone'),
              (_Who.participating, 'Participating'),
              (_Who.spectating, 'Spectating'),
            ],
            selected: _who,
            onSelected: (w) => setState(() => _who = w),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            EmptyMetric(_error!)
          else if (_roster == null)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._charts(_roster!.where(_counts).toList()),
        ],
      ),
    );
  }

  List<Widget> _charts(List<RosterEntry> people) {
    String school(RosterEntry e) => schoolLabel(e.details['school']);
    String grade(RosterEntry e) => gradeLabel(e.details['grade']);
    final schools = {
      for (final e in people)
        if (school(e) != noSchoolLabel) school(e),
    };
    final grades = {for (final e in people) grade(e)}.toList()
      ..sort(compareGrades);
    const empty = 'Nobody here has registered yet.';

    return [
      StatTiles(
        stats: [
          ('Registered', '${people.length}'),
          ('Schools', '${schools.length}'),
          ('Marked present', '${people.where((e) => e.attended).length}'),
        ],
      ),
      MetricsSection(
        title: 'By school',
        child: BarList(
          rows: countBy([
            for (final e in people) (school(e), e.userId),
          ], last: noSchoolLabel),
          total: people.length,
          emptyText: empty,
        ),
      ),
      MetricsSection(
        title: 'By grade',
        child: BarList(
          rows: countBy([
            for (final e in people) (grade(e), e.userId),
          ], compare: compareGrades),
          total: people.length,
          emptyText: empty,
        ),
      ),
      MetricsSection(
        title: 'Grades by school',
        child: HeatTable(
          table: CrossTab.of(
            [for (final e in people) (school(e), grade(e), e.userId)],
            columns: grades,
            lastRow: noSchoolLabel,
          ),
          cornerLabel: 'School',
          describe: (school, grade, n) =>
              '$n ${n == 1 ? 'person' : 'people'} from $school'
              '${int.tryParse(grade) != null ? ' in grade $grade' : ' ($grade)'}',
          emptyText: empty,
        ),
      ),
    ];
  }
}
