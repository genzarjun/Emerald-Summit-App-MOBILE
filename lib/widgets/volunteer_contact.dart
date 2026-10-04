import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../models/user_profile.dart';

// Shared by the volunteer hub and a session's Volunteers tab: a person's card
// (initials, name, role tag) and the tap-through sheet with their mobile
// number and Call / Text buttons.

/// What each person is on the summit team — the tag on their card and the
/// filter chips. [volunteer] covers a volunteer with no subtype on the sheet.
enum VolunteerGroup {
  admin('Admin', 'Admins'),
  studentVolunteer('Student Volunteer', 'Student Volunteers'),
  parentVolunteer('Parent Volunteer', 'Parent Volunteers'),
  eafAmbassador('EAF Ambassador', 'EAF Ambassadors'),
  volunteer('Volunteer', 'Other volunteers');

  const VolunteerGroup(this.label, this.plural);

  final String label;
  final String plural;
}

VolunteerGroup volunteerGroupOf(VolunteerRef v) {
  if (v.isAdmin) return VolunteerGroup.admin;
  return switch (VolunteerSubtypeX.fromId(v.subtype)) {
    VolunteerSubtype.studentVolunteer => VolunteerGroup.studentVolunteer,
    VolunteerSubtype.parentVolunteer => VolunteerGroup.parentVolunteer,
    VolunteerSubtype.eafAmbassador => VolunteerGroup.eafAmbassador,
    null => VolunteerGroup.volunteer,
  };
}

String volunteerDisplayName(VolunteerRef v) =>
    v.name.isEmpty ? volunteerGroupOf(v).label : v.name;

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = parts.map((w) => w[0]).take(2).join().toUpperCase();
  return letters.isEmpty ? '?' : letters;
}

/// Tag colors per group, from the theme so they follow light/dark.
({Color bg, Color fg}) _tagColors(ColorScheme cs, VolunteerGroup g) =>
    switch (g) {
      VolunteerGroup.admin => (bg: cs.secondary, fg: cs.onSecondary),
      VolunteerGroup.studentVolunteer => (
        bg: cs.primaryContainer,
        fg: cs.onPrimaryContainer,
      ),
      VolunteerGroup.parentVolunteer => (
        bg: cs.tertiaryContainer,
        fg: cs.onTertiaryContainer,
      ),
      _ => (bg: cs.surfaceContainerHighest, fg: cs.onSurface),
    };

class _GroupTag extends StatelessWidget {
  const _GroupTag(this.group);

  final VolunteerGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _tagColors(theme.colorScheme, group);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        group.label,
        style: theme.textTheme.labelMedium?.copyWith(color: colors.fg),
      ),
    );
  }
}

/// A tappable person card. [isYou] adds a "(you)" after the name; [trailing]
/// replaces the default chevron (e.g. an admin's remove button).
class VolunteerCard extends StatelessWidget {
  const VolunteerCard({
    super.key,
    required this.volunteer,
    required this.onTap,
    this.isYou = false,
    this.trailing,
  });

  final VolunteerRef volunteer;
  final VoidCallback onTap;
  final bool isYou;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = volunteerGroupOf(volunteer);
    final colors = _tagColors(theme.colorScheme, group);
    final name = volunteerDisplayName(volunteer);
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
                child: Text(
                  _initials(name),
                  style: theme.textTheme.titleSmall?.copyWith(color: colors.fg),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isYou ? '$name (you)' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    _GroupTag(group),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [v]'s contact sheet: name, role, and their mobile number with copy,
/// Call and Text.
Future<void> showVolunteerContactSheet(BuildContext context, VolunteerRef v) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _VolunteerContactSheet(volunteer: v),
  );
}

class _VolunteerContactSheet extends StatelessWidget {
  const _VolunteerContactSheet({required this.volunteer});

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
    final group = volunteerGroupOf(volunteer);
    final colors = _tagColors(theme.colorScheme, group);
    final name = volunteerDisplayName(volunteer);
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
                  child: Text(
                    _initials(name),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colors.fg,
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
                        group.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Mobile number',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            if (phone.isEmpty)
              Text('Not provided', style: theme.textTheme.titleMedium)
            else
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      phone,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy number',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: phone));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Number copied')),
                      );
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
