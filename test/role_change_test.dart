import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/auth/onboarding_screen.dart';

RoleChangeItem _item(String from, String to, {RoleChangeTeam? team}) =>
    RoleChangeItem(
      sessionId: 's1',
      title: 'Robotics Lab',
      from: from,
      to: to,
      team: team,
    );

void main() {
  group('role change wording', () {
    test('participating and expert sessions move to spectating', () {
      expect(describeRoleChange(_item('participant', 'spectator')),
          '"Robotics Lab": you\'ll go from participating to spectating.');
      expect(describeRoleChange(_item('expert', 'spectator')),
          '"Robotics Lab": you\'ll go from serving as an expert to spectating.');
    });

    test('managing: spectate, dropped when full, or still registered', () {
      expect(describeRoleChange(_item('managing', 'spectator')),
          '"Robotics Lab": you\'ll stop managing it and spectate instead.');
      expect(describeRoleChange(_item('managing', 'dropped')),
          contains("It's full, so it will be removed from your day."));
      expect(describeRoleChange(_item('managing', 'unchanged')),
          contains('You stay registered for it.'));
    });

    test('says what happens to the team', () {
      expect(
        describeRoleChange(_item('participant', 'spectator',
            team: const RoleChangeTeam(
                action: 'handed_off', projectName: 'Kite', toName: 'Ana'))),
        endsWith('Your team "Kite" goes to Ana.'),
      );
      expect(
        describeRoleChange(_item('participant', 'spectator',
            team: const RoleChangeTeam(
                action: 'deleted', projectName: 'Kite', code: 'TV1234'))),
        endsWith('so it will be deleted and its code TV1234 will stop '
            'working.'),
      );
      expect(
        describeRoleChange(_item('participant', 'spectator',
            team: const RoleChangeTeam(action: 'left', projectName: 'Kite'))),
        endsWith('You\'ll leave the team "Kite".'),
      );
    });

    test('reads the preview the database returns', () {
      final item = RoleChangeItem.fromMap({
        'session_id': 'x',
        'title': 'Shark Tank',
        'from': 'participant',
        'to': 'spectator',
        'team': {'action': 'deleted', 'project_name': 'P', 'code': 'VV1'},
      });
      expect(item.team?.action, 'deleted');
      expect(item.team?.code, 'VV1');
    });
  });

  group('admin badge', () {
    tearDown(() {
      appState.profile = null;
      appState.expertRequests = const [];
    });

    ExpertRequest req(DateTime at) => ExpertRequest(
        userId: '$at', fullName: 'A', email: 'a@x.org', requestedAt: at);

    test('shows until opened, and again for a newer sign-up', () {
      final seen = DateTime.utc(2026, 10, 19, 12);
      appState.profile = UserProfile(
        id: 'admin',
        email: 'admin@x.org',
        role: SummitRole.admin,
        onboarded: true,
        expertQueueSeenAt: seen,
      );
      appState.expertRequests = [req(seen.subtract(const Duration(hours: 1)))];
      expect(appState.hasUnseenExpertRequests, isFalse);
      expect(appState.pendingExpertCount, 1);

      appState.expertRequests = [
        ...appState.expertRequests,
        req(seen.add(const Duration(minutes: 5))),
      ];
      expect(appState.hasUnseenExpertRequests, isTrue);
      expect(appState.pendingExpertCount, 2);
    });

    test('never shows for non-admins', () {
      appState.profile = UserProfile(
          id: 'p', email: 'p@x.org', role: SummitRole.participant);
      appState.expertRequests = [req(DateTime.now())];
      expect(appState.hasUnseenExpertRequests, isFalse);
    });
  });
}
