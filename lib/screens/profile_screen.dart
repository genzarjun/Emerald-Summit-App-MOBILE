import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../theme.dart';
import 'auth/onboarding_screen.dart';
import 'front_desk_screen.dart';
import 'my_assignments_screen.dart';
import 'rooms_manager_screen.dart';

/// "Profile" tab — the user's contact card, role, notification settings,
/// and volunteer hours / certificate (spec section 04 — Profiles &
/// contact cards, Volunteer hours & certificates).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Each card wraps its own body in a ListenableBuilder, so a role/settings
    // change repaints it. (A single outer ListenableBuilder with const children
    // wouldn't — Flutter skips rebuilding identical const widgets, which is why
    // the role badge didn't update after "Change role".)
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _ContactCard(),
          SizedBox(height: 16),
          _VisibilityCard(),
          SizedBox(height: 16),
          _VolunteerCard(),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    appState.userName
                        .split(' ')
                        .map((w) => w[0])
                        .take(2)
                        .join(),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appState.userName,
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: EmeraldTheme.mist,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(appState.userRole,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.colorScheme.primary)),
                      ),
                      if (appState.volunteerSubtypeLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(appState.volunteerSubtypeLabel!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                      if (appState.volunteerScopeLabel != null) ...[
                        const SizedBox(height: 6),
                        Text('Manages ${appState.volunteerScopeLabel}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text('Settings', style: theme.textTheme.titleMedium),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Push notifications'),
                  subtitle:
                      const Text('Next-session reminders & announcements'),
                  value: appState.notificationsEnabled,
                  onChanged: appState.setNotifications,
                ),
                if (appState.isVolunteer)
                  ListTile(
                    leading: Icon(Icons.event_available_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('My sessions'),
                    subtitle:
                        const Text('Sessions you help run & their attendance'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const MyAssignmentsScreen()),
                    ),
                  ),
                if (appState.canCheckInFrontDesk)
                  ListTile(
                    leading: Icon(Icons.how_to_reg_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Front desk check-in'),
                    subtitle: const Text('Mark attendees arrived at the summit'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const FrontDeskScreen()),
                    ),
                  ),
                if (appState.isAdmin)
                  ListTile(
                    leading: Icon(Icons.meeting_room_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Manage rooms'),
                    subtitle: const Text('The rooms sessions can be held in'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const RoomsManagerScreen()),
                    ),
                  ),
                if (backendInfo.isLive)
                  ListTile(
                    leading: Icon(Icons.badge_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Change role'),
                    subtitle: Text('Currently ${appState.userRole}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const OnboardingScreen()),
                    ),
                  ),
                if (backendInfo.isLive)
                  ListTile(
                    leading:
                        Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text('Sign out',
                        style: TextStyle(color: theme.colorScheme.error)),
                    onTap: () => _confirmSignOut(context),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            "You'll need to enter a fresh email code to sign back in. Your "
            'data stays safe in your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await appState.signOut();
    }
  }
}

class _VolunteerCard extends StatelessWidget {
  const _VolunteerCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Volunteer hours', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${appState.volunteerHours}',
                        style: theme.textTheme.displaySmall
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const SizedBox(width: 6),
                    Text('hours logged', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content:
                              Text('Generating your signed certificate…'),
                        ),
                      );
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download certificate'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
