import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/repositories.dart';
import '../backend/service_locator.dart';
import '../models/user_profile.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/welcome_screen.dart' show roleColor;

/// Change role for a signed-in person, in a sheet, like the website's popup:
/// the four roles with the current one marked; picking one checks what the
/// switch changes and asks to confirm, then the new role's sign-up questions
/// open (where the change is saved).
Future<void> showChangeRoleSheet(BuildContext context) async {
  final picked = await showModalBottomSheet<SummitRole>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _ChangeRoleSheet(),
  );
  if (picked == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) =>
        OnboardingScreen(initialRole: picked, startOnDetails: true),
  ));
}

class _ChangeRoleSheet extends StatefulWidget {
  const _ChangeRoleSheet();

  @override
  State<_ChangeRoleSheet> createState() => _ChangeRoleSheetState();
}

class _ChangeRoleSheetState extends State<_ChangeRoleSheet> {
  static const _roles = [
    SummitRole.participant,
    SummitRole.parentSpectator,
    SummitRole.expert,
    SummitRole.volunteer,
  ];

  SummitRole? _picked;
  List<RoleChangeItem>? _changes;
  bool _busy = false;
  String? _error;

  Future<void> _pick(SummitRole role) async {
    setState(() {
      _picked = role;
      _changes = null;
      _error = null;
      _busy = true;
    });
    // Volunteer and admin need the email on the allowlist, checked before
    // anything is saved.
    if (role.isGated) {
      bool? eligible;
      try {
        eligible = await allowlistRepository.isEligible(role);
      } catch (_) {
        eligible = null; // Could not read the list: not a refusal.
      }
      if (!mounted) return;
      if (eligible != true) {
        setState(() {
          _busy = false;
          _error = eligible == null
              ? SummitRoleX.allowlistCheckFailedMessage
              : role.notAllowedMessage;
        });
        return;
      }
    }
    List<RoleChangeItem> changes;
    try {
      changes = await appState.previewRoleChange(role);
    } catch (_) {
      // Go ahead with no list when the preview can't load.
      changes = const [];
    }
    if (!mounted) return;
    setState(() {
      _changes = changes;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = appState.profile?.role;
    final picked = _picked;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change your role', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              "You're a ${appState.userRole}. Pick the role you want instead. "
              "You'll see what changes before anything is switched.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (picked == null)
              for (final role in _roles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RoleOption(
                    role: role,
                    isCurrent: role == current,
                    onTap: role == current ? null : () => _pick(role),
                  ),
                )
            else
              _preview(theme, picked),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme, SummitRole role) {
    final scheme = theme.colorScheme;
    final changes = _changes;
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _picked = null;
              _error = null;
            }),
            child: const Text('Pick another role'),
          ),
        ],
      );
    }
    if (_busy || changes == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Checking what changes…'),
          ],
        ),
      );
    }
    final body =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onTertiaryContainer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Switching to ${role.label}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onTertiaryContainer)),
              if (role == SummitRole.expert) ...[
                const SizedBox(height: 8),
                Text(
                  'Expert accounts need an admin to approve them. Until then, '
                  "you'll only see a screen saying your account is awaiting "
                  'approval.',
                  style: body,
                ),
              ],
              if (changes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(roleChangeLeadIn(role), style: body),
                for (final c in changes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: body),
                        Expanded(
                            child: Text(describeRoleChange(c), style: body)),
                      ],
                    ),
                  ),
                if (changes.any((c) => c.from == 'managing')) ...[
                  const SizedBox(height: 8),
                  Text(
                    "The admins will be told you're no longer managing these "
                    'sessions, so they can find someone else.',
                    style: body,
                  ),
                ],
              ],
              if (role != SummitRole.expert && changes.isEmpty) ...[
                const SizedBox(height: 8),
                Text('None of your sessions change.', style: body),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(role),
                child: const Text('Confirm'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => setState(() => _picked = null),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.role, required this.isCurrent, this.onTap});

  final SummitRole role;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isCurrent ? scheme.primary : scheme.outlineVariant),
          color: isCurrent ? scheme.primary.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: roleColor(role),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(role.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label, style: theme.textTheme.titleSmall),
                  Text(role.blurb,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 16, color: scheme.primary),
              const SizedBox(width: 2),
              Text('Current',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
