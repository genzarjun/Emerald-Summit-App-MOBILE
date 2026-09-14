import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme.dart';
import 'discipline_editor_screen.dart';
import 'discipline_screen.dart';

/// "Discover" tab — a browsable catalog of all disciplines
/// (spec section 04 — Build your own schedule). Reads the live catalog from
/// [appState] (backend-backed; sample data when no backend is configured).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    // Load once if the catalog isn't populated yet (e.g. sample mode, or a
    // direct open before the auth gate primed it).
    if (appState.disciplines.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => appState.loadCatalog());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      floatingActionButton: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => appState.isAdmin
            ? FloatingActionButton.extended(
                heroTag: 'fab-new-discipline',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DisciplineEditorScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New discipline'),
              )
            : const SizedBox.shrink(),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final disciplines = appState.disciplines;

          if (appState.catalogLoading && disciplines.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (appState.catalogError != null && disciplines.isEmpty) {
            return _ErrorState(onRetry: appState.loadCatalog);
          }

          return RefreshIndicator(
            onRefresh: appState.loadCatalog,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${disciplines.length} disciplines',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Tap a discipline to explore its sessions and add them to '
                  'your day.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Slightly taller cards give the two-line names + tagline room
                  // to breathe on iOS, where the system font is wider.
                  childAspectRatio: 0.80,
                  children: [
                    for (final d in disciplines) _DisciplineCard(discipline: d),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text("Couldn't load the catalog", style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard({required this.discipline});
  final Discipline discipline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DisciplineScreen(discipline: discipline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                backgroundColor: EmeraldTheme.mist,
                child: Icon(discipline.icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Text(
                discipline.name,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                discipline.tagline,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '${discipline.sessions.length} '
                'session${discipline.sessions.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
