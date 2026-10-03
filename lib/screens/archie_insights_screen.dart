import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../backend/service_locator.dart';

/// Admin-only: what people are asking Archie and how it answers, newest first.
///
/// Deliberately anonymous — the backend (`archie_recent_exchanges`) returns
/// only question/answer text and a timestamp, never who asked. Use it to spot
/// gaps in the app's content (questions Archie can't answer well) and to
/// sanity-check answer quality.
class ArchieInsightsScreen extends StatefulWidget {
  const ArchieInsightsScreen({super.key});

  @override
  State<ArchieInsightsScreen> createState() => _ArchieInsightsScreenState();
}

class _ArchieInsightsScreenState extends State<ArchieInsightsScreen> {
  late Future<List<ArchieExchange>> _future = archieRepository
      .recentExchanges();

  Future<void> _refresh() async {
    final next = archieRepository.recentExchanges();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archie insights')),
      body: FutureBuilder<List<ArchieExchange>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.error_outline,
              text:
                  "Couldn't load Archie conversations. Make sure "
                  'archie_history_setup.sql has been run.',
              onRetry: _refresh,
            );
          }
          final exchanges = snap.data!;
          if (exchanges.isEmpty) {
            return _Message(
              icon: Icons.forum_outlined,
              text: 'No one has asked Archie anything yet.',
              onRetry: _refresh,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: exchanges.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => i == 0
                  ? Text(
                      'The ${exchanges.length} most recent questions across '
                      'all users. Anonymous — no names or accounts are shown.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : _ExchangeCard(exchange: exchanges[i - 1]),
            ),
          );
        },
      ),
    );
  }
}

class _ExchangeCard extends StatefulWidget {
  const _ExchangeCard({required this.exchange});
  final ArchieExchange exchange;

  @override
  State<_ExchangeCard> createState() => _ExchangeCardState();
}

class _ExchangeCardState extends State<_ExchangeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.exchange;
    final local = MaterialLocalizations.of(context);
    final when =
        '${local.formatShortMonthDay(e.askedAt)}, '
        '${local.formatTimeOfDay(TimeOfDay.fromDateTime(e.askedAt))}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.question,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                e.answer,
                maxLines: _expanded ? null : 4,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                [
                  when,
                  if (e.sourceCount > 0)
                    '${e.sourceCount} web source${e.sourceCount == 1 ? '' : 's'}',
                  if (!_expanded) 'Tap to expand',
                ].join('  ·  '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}
