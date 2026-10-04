import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../models/user_profile.dart';

/// Opens a sheet with one roster person's profile, for the session's
/// organizers: contact info (tap to email / call), their onboarding answers
/// (school, grade, expertise, bio…), and how they're registered for [session]
/// (attendance, project/team, answers to the session's questions).
///
/// The data rides along on [RosterEntry] from `fetch_session_roster`, which
/// only returns it to people allowed to see this session's roster.
Future<void> showRosterPersonSheet(
  BuildContext context, {
  required Session session,
  required RosterEntry entry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RosterPersonSheet(session: session, entry: entry),
  );
}

/// Labels for `profiles.details` keys, taken from every role's onboarding
/// fields (minus the "(optional)" suffix). Unknown keys — answers to questions
/// since removed from sign-up — fall back to a humanized key.
String _detailLabel(String key) {
  for (final role in SummitRole.values) {
    for (final f in role.onboardingFields) {
      if (f.key == key) return f.label.replaceAll(' (optional)', '');
    }
  }
  final words = key.replaceAll('_', ' ');
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}

class _RosterPersonSheet extends StatelessWidget {
  const _RosterPersonSheet({required this.session, required this.entry});

  final Session session;
  final RosterEntry entry;

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
    final e = entry;
    final name = e.name.isEmpty ? e.email : e.name;
    final phone = e.details['phone']?.trim() ?? '';
    final otherDetails = [
      for (final d in e.details.entries)
        if (d.key != 'phone' && d.value.trim().isNotEmpty) d,
    ];
    final questions = {
      for (final q in session.participantQuestions) q.id: q.prompt,
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (e.role != null)
                              SummitRoleX.fromId(e.role).label,
                            '${e.participationType.chipLabel} in this session',
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _SectionHeader('Contact'),
            if (e.email.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(e.email),
                subtitle: const Text('Email'),
                onTap: () =>
                    _launch(context, Uri(scheme: 'mailto', path: e.email)),
              ),
            // role is null only when the backend predates
            // roster_profile_details.sql, i.e. we have no details at all.
            if (e.role == null)
              const _InfoRow(
                label: 'Mobile number',
                value: "Profile details aren't available yet.",
              )
            else
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: Text(phone.isEmpty ? 'Not provided' : phone),
                subtitle: const Text('Mobile number'),
                enabled: phone.isNotEmpty,
                onTap: phone.isEmpty
                    ? null
                    : () => _launch(
                        context,
                        Uri(
                          scheme: 'tel',
                          path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                        ),
                      ),
              ),
            if (otherDetails.isNotEmpty) ...[
              const _SectionHeader('Profile'),
              for (final d in otherDetails)
                _InfoRow(label: _detailLabel(d.key), value: d.value),
            ],
            const _SectionHeader('This session'),
            _InfoRow(
              label: 'Attendance',
              value: e.attended ? 'Present' : 'Not marked',
            ),
            if (e.projectName?.isNotEmpty == true)
              _InfoRow(
                label: e.isTeam == true ? 'Team project' : 'Solo project',
                value: [
                  e.projectName!,
                  if (e.teamCode != null) 'code ${e.teamCode}',
                  if (e.isTeamOwner) 'team owner',
                ].join(' · '),
              ),
            for (final a in e.answers.entries)
              _InfoRow(label: questions[a.key] ?? 'Answer', value: a.value),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
