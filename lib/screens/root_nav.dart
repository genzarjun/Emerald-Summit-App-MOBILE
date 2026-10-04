import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../app_state.dart';
import 'dashboard_screen.dart';
import 'schedule_screen.dart';
import 'discover_screen.dart';
import 'announcements_screen.dart';
import 'archie_screen.dart';

/// Bottom-tab shell hosting the five main sections of the app (Home ·
/// Schedule · Discover · News · Archie). Resources is no longer a tab — it's
/// pushed from the Home tiles. Profile lives
/// behind the avatar in the [DashboardScreen] header (Uber-style), so it isn't
/// a bottom-bar destination.
class RootNav extends StatelessWidget {
  const RootNav({super.key});

  static const _screens = [
    DashboardScreen(),
    ScheduleScreen(),
    DiscoverScreen(),
    AnnouncementsScreen(),
    ArchieScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Driven by the global [rootTab] so code outside the widget tree (the in-app
    // banner) can switch tabs.
    return ValueListenableBuilder<int>(
      valueListenable: rootTab,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(index: index, children: _screens),
        // Inner builder so the News unread badge repaints on feed/read changes.
        bottomNavigationBar: ListenableBuilder(
          listenable: appState,
          builder: (context, _) => Theme(
            // Archie's tab has its own backdrop; match the bar to it.
            data: index == kArchieTabIndex
                ? ArchieScreen.navBarTheme(Theme.of(context))
                : Theme.of(context),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => rootTab.value = i,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note),
                  label: 'Schedule',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Discover',
                ),
                NavigationDestination(
                  icon: _newsIcon(
                    const Icon(Icons.campaign_outlined),
                    appState.unreadAnnouncementCount,
                  ),
                  selectedIcon: _newsIcon(
                    const Icon(Icons.campaign),
                    appState.unreadAnnouncementCount,
                  ),
                  label: 'News',
                ),
                const NavigationDestination(
                  icon: ArchieNavIcon(selected: false),
                  selectedIcon: ArchieNavIcon(selected: true),
                  label: 'Archie',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The News icon, with an Instagram-style red count badge when there are
  /// unread announcements. Plain icon when the count is zero.
  static Widget _newsIcon(Icon icon, int unread) {
    if (unread <= 0) return icon;
    return Badge.count(count: unread, child: icon);
  }
}
