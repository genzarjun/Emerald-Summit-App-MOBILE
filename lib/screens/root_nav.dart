import 'package:flutter/material.dart';

import '../app_navigation.dart';
import 'schedule_screen.dart';
import 'discover_screen.dart';
import 'announcements_screen.dart';
import 'resources_screen.dart';
import 'profile_screen.dart';

/// Bottom-tab shell hosting the five main sections of the app.
class RootNav extends StatelessWidget {
  const RootNav({super.key});

  static const _screens = [
    ScheduleScreen(),
    DiscoverScreen(),
    AnnouncementsScreen(),
    ResourcesScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Driven by the global [rootTab] so code outside the widget tree (the in-app
    // banner) can switch tabs.
    return ValueListenableBuilder<int>(
      valueListenable: rootTab,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(index: index, children: _screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => rootTab.value = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'My Day',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'News',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Resources',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        ),
      ),
    );
  }
}
