import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/metrics.dart';
import '../models/models.dart';
import '../models/user_profile.dart';
import '../widgets/metrics_widgets.dart';

/// Who the admin Metrics screen counts.
enum _Who { participants, parents, everyone }

/// Profile → Metrics (admins): who has signed up for the summit, by school
/// and grade, and which disciplines each school's students registered for.
/// Counts come from `fetch_summit_metrics` (summit_metrics.sql); every number
/// is distinct people, never names.
class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  SummitMetrics? _data;
  String? _error;
  _Who _who = _Who.participants;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await metricsRepository.fetchSummitMetrics();
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't load metrics. Pull down to try "
              'again.',
        );
      }
    }
  }

  bool _counts(MetricsPerson p) => switch (_who) {
    _Who.participants => p.role == SummitRole.participant,
    _Who.parents => p.role == SummitRole.parentSpectator,
    _Who.everyone => true,
  };

  String get _whoNoun => switch (_who) {
    _Who.participants => 'participants',
    _Who.parents => 'parents and spectators',
    _Who.everyone => 'people',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Metrics')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MetricsFilter<_Who>(
                options: const [
                  (_Who.participants, 'Participants'),
                  (_Who.parents, 'Parents & spectators'),
                  (_Who.everyone, 'Everyone'),
                ],
                selected: _who,
                onSelected: (w) => setState(() => _who = w),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                EmptyMetric(_error!)
              else if (_data == null)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ..._charts(context, _data!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _charts(BuildContext context, SummitMetrics data) {
    final people = data.people.where(_counts).toList();
    final byId = {for (final p in people) p.id: p};
    // Experts leading a session aren't showing interest in it.
    final regs = data.registrations
        .where(
          (r) =>
              byId.containsKey(r.userId) && r.type != ParticipationType.expert,
        )
        .toList();
    final inSessions = {for (final r in regs) r.userId};
    final schools = {
      for (final p in people)
        if (p.school != noSchoolLabel) p.school,
    };

    final disciplineOrder = [for (final d in appState.disciplines) d.name];
    final bySchoolDiscipline = CrossTab.of(
      [
        for (final r in regs)
          (byId[r.userId]!.school, r.disciplineName, r.userId),
      ],
      columns: disciplineOrder,
      lastRow: noSchoolLabel,
    );
    final grades = {for (final p in people) p.grade}.toList()
      ..sort(compareGrades);
    final bySchoolGrade = CrossTab.of(
      [for (final p in people) (p.school, p.grade, p.id)],
      columns: grades,
      lastRow: noSchoolLabel,
    );
    final showGrades = _who != _Who.parents;

    return [
      StatTiles(
        stats: [
          ('Signed up', '${people.length}'),
          ('Schools', '${schools.length}'),
          ('In a session', '${inSessions.length}'),
          ('Session sign-ups', '${regs.length}'),
        ],
      ),
      MetricsSection(
        title: 'Sign-ups by school',
        note: 'Accounts that finished sign-up, by the school they picked.',
        child: BarList(
          rows: countBy([
            for (final p in people) (p.school, p.id),
          ], last: noSchoolLabel),
          total: people.length,
          emptyText: 'No $_whoNoun have signed up yet.',
        ),
      ),
      MetricsSection(
        title: 'Disciplines by school',
        note:
            'People from each school registered for at least one session '
            'in a discipline. Someone in two Tech sessions counts once '
            'under Tech, so a row total can be less than its cells added up.',
        child: HeatTable(
          table: bySchoolDiscipline,
          cornerLabel: 'School',
          describe: (school, discipline, n) =>
              '$n ${n == 1 ? 'person' : 'people'} from $school in '
              '$discipline',
          emptyText: 'No $_whoNoun have registered for a session yet.',
        ),
      ),
      MetricsSection(
        title: 'Interest by discipline',
        note: 'People registered for at least one session in each.',
        child: BarList(
          rows: countBy([for (final r in regs) (r.disciplineName, r.userId)]),
          total: inSessions.length,
          emptyText: 'No $_whoNoun have registered for a session yet.',
        ),
      ),
      if (showGrades) ...[
        MetricsSection(
          title: 'Grades by school',
          note: 'Everyone who signed up, by school and grade.',
          child: HeatTable(
            table: bySchoolGrade,
            cornerLabel: 'School',
            describe: (school, grade, n) =>
                '$n ${n == 1 ? 'person' : 'people'} from $school'
                '${int.tryParse(grade) != null ? ' in grade $grade' : ' ($grade)'}',
            emptyText: 'No $_whoNoun have signed up yet.',
          ),
        ),
        MetricsSection(
          title: 'Sign-ups by grade',
          child: BarList(
            rows: countBy([
              for (final p in people) (p.grade, p.id),
            ], compare: compareGrades),
            total: people.length,
            emptyText: 'No $_whoNoun have signed up yet.',
          ),
        ),
      ],
    ];
  }
}
