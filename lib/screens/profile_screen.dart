import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../theme_setting.dart';
import '../widgets/checkin_pass_card.dart';
import 'archie_insights_screen.dart';
import 'auth/onboarding_screen.dart';
import 'edit_profile_screen.dart';
import 'front_desk_screen.dart';
import 'my_assignments_screen.dart';
import 'rooms_manager_screen.dart';
import 'volunteer_hub_screen.dart';

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
          _PassSection(),
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
                          color: theme.colorScheme.surfaceContainer,
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
                if (appState.profile != null)
                  IconButton(
                    tooltip: 'Edit profile',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openEditProfile(context),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Every signed-in user's front-desk QR pass. Hidden in sample mode, where
/// nobody is signed in and there's no id to encode.
class _PassSection extends StatelessWidget {
  const _PassSection();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final id = appState.profile?.id;
        if (id == null || id.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CheckinPassCard(key: ValueKey(id), userId: id),
        );
      },
    );
  }
}

void _openEditProfile(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()),
    );

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
                const _AppearanceTile(),
                if (appState.profile != null)
                  ListTile(
                    leading: Icon(Icons.edit_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Edit profile'),
                    subtitle: const Text('Your name and sign-up details'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openEditProfile(context),
                  ),
                if (appState.isVolunteer)
                  ListTile(
                    leading: Icon(Icons.event_available_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text("Sessions I'm managing"),
                    subtitle:
                        const Text('Take attendance for sessions you run'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const MyAssignmentsScreen()),
                    ),
                  ),
                if (appState.isVolunteer || appState.isAdmin)
                  ListTile(
                    leading: Icon(Icons.groups_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Volunteer hub'),
                    subtitle: const Text('Volunteers, admins, and how to reach them'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const VolunteerHubScreen()),
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
                if (appState.isAdmin)
                  ListTile(
                    leading: Icon(Icons.insights_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Archie insights'),
                    subtitle:
                        const Text('What people ask Archie (anonymous)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const ArchieInsightsScreen()),
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
    // Capture before any await so we don't use context across an async gap.
    final navigator = Navigator.of(context);
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
      // Pop the pushed Profile (and any screens above it) so the auth gate's
      // now-signed-out state shows the sign-in screen — otherwise this stale
      // Profile route lingers on top showing demo defaults ("Alex Rivera").
      navigator.popUntil((route) => route.isFirst);
    }
  }
}

/// Light / Dark / System picker. Saved on this device ([themeSetting]).
class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeSetting,
      builder: (context, mode, _) => ListTile(
        title: const Text('Appearance'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Equal-width segments get narrow on small phones with large
              // text. When a segment can't hold icon + "System" on one line,
              // drop the icons so all three labels stay the same size.
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final showIcons = constraints.maxWidth / 3 >= 44 + 46 * scale;
              return SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  // Trim padding so labels fit; _SegmentLabel keeps them on one
                  // line (shrinking as a last resort) instead of wrapping.
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: showIcons
                          ? const Icon(Icons.light_mode_outlined)
                          : null,
                      label: const _SegmentLabel('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: showIcons
                          ? const Icon(Icons.dark_mode_outlined)
                          : null,
                      label: const _SegmentLabel('Dark'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: showIcons
                          ? const Icon(Icons.brightness_auto_outlined)
                          : null,
                      label: const _SegmentLabel('System'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => themeSetting.set(s.first),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Single-line segment label that scales down rather than wrapping.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
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
