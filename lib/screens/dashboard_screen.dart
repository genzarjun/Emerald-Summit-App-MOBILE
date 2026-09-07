import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_navigation.dart';
import '../app_state.dart';
import '../data/sample_data.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/summit_logo.dart';
import 'discipline_screen.dart';
import 'profile_screen.dart';
import 'session_detail_screen.dart';

/// "Home" tab — the launchpad. Instead of dropping the participant straight
/// into an (often empty) schedule, this greets them, sets the tone with a
/// rotating quote + brand art, surfaces what's next, and lays out big,
/// Uber-style action tiles that route into the rest of the app. It stays
/// interesting even before anything is added to the schedule.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Each dynamic section wraps its own body in a ListenableBuilder (see the
    // same pattern in profile_screen.dart), so a schedule/catalog/announcement
    // change repaints it. A single outer ListenableBuilder with const children
    // wouldn't — Flutter skips rebuilding identical const widgets.
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.loadCatalog();
          await appState.loadAnnouncements();
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: const [
            _Header(),
            SizedBox(height: 16),
            _QuoteCard(),
            SizedBox(height: 20),
            _UpNext(),
            SizedBox(height: 24),
            _QuickActions(),
            SizedBox(height: 24),
            _DisciplineStrip(),
            SizedBox(height: 24),
            _LatestNews(),
            SizedBox(height: 24),
            _LinksCard(),
            SizedBox(height: 28),
            _Footer(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — greeting, tappable avatar → Profile, brand art.
// ---------------------------------------------------------------------------
class _Header extends StatefulWidget {
  const _Header();

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  // Picked once per mount so it's stable across the header's rebuilds (name /
  // schedule changes) instead of flickering to a new greeting each time.
  late final String _greeting = _pickGreeting();

  static String _pickGreeting() {
    final h = DateTime.now().hour;
    final timeGreeting = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    // The standard time-based greeting stays in the mix alongside the playful
    // ones — a random one shows each time Home mounts.
    final pool = <String>[
      timeGreeting,
      "What's up",
      "What's cooking",
      "What's building",
      "What's innovating",
      "What's brewing",
      "What's poppin'",
      'Ready to create',
      "Let's build something",
    ];
    return pool[Random().nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final firstName = appState.userName.split(' ').first;
        return _buildHeader(context, topInset, firstName);
      },
    );
  }

  Widget _buildHeader(BuildContext context, double topInset, String firstName) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 16, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [EmeraldTheme.emerald, EmeraldTheme.deepEmerald],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerText(
                      text: '$_greeting,',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      firstName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const _AvatarButton(),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 15, color: Colors.white.withValues(alpha: .9)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${SampleData.eventDate}  ·  ${SampleData.eventVenue}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .9),
                    fontSize: 13,
                  ),
                ),
              ),
              const SummitLogo(size: 34),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => _buildAvatar(context),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final name = appState.userName.trim();
    final initials = name.isEmpty
        ? '?'
        : name
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join();
    return Tooltip(
      message: 'Profile',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .18),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: .5)),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quote card — a rotating dose of inspiration + a spark of brand art.
// ---------------------------------------------------------------------------
class _QuoteCard extends StatefulWidget {
  const _QuoteCard();

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard>
    with SingleTickerProviderStateMixin {
  // Plays once on first mount for the "wipe down" reveal.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const List<({String quote, String author})> _quotes = [
    (
      quote: 'The science of today is the technology of tomorrow.',
      author: 'Edward Teller'
    ),
    (
      quote: 'Creativity is intelligence having fun.',
      author: 'Albert Einstein'
    ),
    (
      quote: 'Somewhere, something incredible is waiting to be known.',
      author: 'Carl Sagan'
    ),
    (
      quote: 'The best way to predict the future is to invent it.',
      author: 'Alan Kay'
    ),
    (
      quote: 'Design is not just what it looks like. Design is how it works.',
      author: 'Steve Jobs'
    ),
    (
      quote: 'Pure mathematics is, in its way, the poetry of logical ideas.',
      author: 'Albert Einstein'
    ),
    (
      quote: 'What we know is a drop, what we don\'t know is an ocean.',
      author: 'Isaac Newton'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Rotate by day so it feels fresh but is stable within a session.
    final today = DateTime.now();
    final dayOfYear =
        today.difference(DateTime(today.year, 1, 1)).inDays;
    final q = _quotes[dayOfYear % _quotes.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final v = Curves.easeOutCubic.transform(_c.value);
          return Opacity(
            opacity: v,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: v,
                child: child,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              EmeraldTheme.emerald.withValues(alpha: .10),
              EmeraldTheme.emerald.withValues(alpha: .03),
            ],
          ),
          border: Border.all(
            color: EmeraldTheme.emerald.withValues(alpha: .18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote,
                color: EmeraldTheme.emerald.withValues(alpha: .7), size: 28),
            const SizedBox(height: 6),
            Text(
              q.quote,
              style: const TextStyle(
                fontSize: 16.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EmeraldTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '— ${q.author}',
              style: TextStyle(
                fontSize: 13,
                color: EmeraldTheme.ink.withValues(alpha: .6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Up next — the participant's next session, or a plan-your-day nudge.
// ---------------------------------------------------------------------------
class _UpNext extends StatelessWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final sessions = appState.mySessions;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: sessions.isEmpty
              ? const _PlanNudge()
              : _NextSessionCard(session: sessions.first),
        );
      },
    );
  }
}

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Up next', icon: Icons.schedule),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: session),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: EmeraldTheme.emerald.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          session.timeLabel.split(' – ').first,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: EmeraldTheme.emerald,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${session.disciplineName} · ${session.room}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanNudge extends StatelessWidget {
  const _PlanNudge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: EmeraldTheme.emerald.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available,
                color: EmeraldTheme.emerald),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your day is a blank slate',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 2),
                Text('Browse sessions and build your schedule.',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => rootTab.value = kDiscoverTabIndex,
            child: const Text('Browse'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions — the Uber-style tile grid.
// ---------------------------------------------------------------------------
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => _buildActions(context),
    );
  }

  Widget _buildActions(BuildContext context) {
    final unread = appState.unreadAnnouncementCount;
    final actions = <_Action>[
      _Action(
        icon: Icons.event_note,
        label: 'My schedule',
        onTap: () => rootTab.value = kScheduleTabIndex,
      ),
      _Action(
        icon: Icons.explore,
        label: 'Browse sessions',
        onTap: () => rootTab.value = kDiscoverTabIndex,
      ),
      _Action(
        icon: Icons.campaign,
        label: 'What\'s new',
        badge: unread > 0 ? '$unread' : null,
        onTap: () => rootTab.value = kNewsTabIndex,
      ),
      _Action(
        icon: Icons.map,
        label: 'Campus map',
        onTap: () => rootTab.value = kResourcesTabIndex,
      ),
      _Action(
        icon: Icons.folder,
        label: 'Resources',
        onTap: () => rootTab.value = kResourcesTabIndex,
      ),
      _Action(
        icon: Icons.person,
        label: 'My profile',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Jump to', icon: Icons.grid_view),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final tileWidth = (constraints.maxWidth - spacing * 2) / 3;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final a in actions)
                    SizedBox(
                      width: tileWidth,
                      child: _ActionTile(action: a),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final _Action action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: .5),
            ),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: EmeraldTheme.emerald.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(action.icon,
                        color: EmeraldTheme.emerald, size: 24),
                  ),
                  if (action.badge != null)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 20),
                        child: Text(
                          action.badge!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discipline strip — a horizontal browse rail into the catalog.
// ---------------------------------------------------------------------------
class _DisciplineStrip extends StatelessWidget {
  const _DisciplineStrip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => _buildStrip(context),
    );
  }

  Widget _buildStrip(BuildContext context) {
    final disciplines = appState.disciplines;
    if (disciplines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                    title: 'Explore disciplines', icon: Icons.category),
              ),
              TextButton(
                onPressed: () => rootTab.value = kDiscoverTabIndex,
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: disciplines.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _DisciplineChip(discipline: disciplines[i]),
          ),
        ),
      ],
    );
  }
}

class _DisciplineChip extends StatelessWidget {
  const _DisciplineChip({required this.discipline});
  final Discipline discipline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DisciplineScreen(discipline: discipline),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: EmeraldTheme.mist,
                  child: Icon(discipline.icon,
                      color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  discipline.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${discipline.sessions.length} '
                  'session${discipline.sessions.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Latest news — a peek at the top announcement.
// ---------------------------------------------------------------------------
class _LatestNews extends StatelessWidget {
  const _LatestNews();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => _buildNews(context),
    );
  }

  Widget _buildNews(BuildContext context) {
    final items = appState.visibleAnnouncements;
    if (items.isEmpty) return const SizedBox.shrink();
    final a = items.first;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Latest news', icon: Icons.campaign),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => rootTab.value = kNewsTabIndex,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (a.pinned) ...[
                          const Icon(Icons.push_pin,
                              size: 14, color: EmeraldTheme.emerald),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(a.title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(a.timeAgo, style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(a.body,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Links — quick outbound links, opened in the browser / mail app.
// ---------------------------------------------------------------------------
class _LinksCard extends StatelessWidget {
  const _LinksCard();

  static const _links = [
    (icon: Icons.language, label: 'Summit website', url: 'https://sites.google.com/view/ehs-academic-foundation/programs/emerald-summit'),
    (icon: Icons.camera_alt, label: 'Instagram', url: 'https://www.instagram.com/emeraldsummit26/'),
    (icon: Icons.mail_outline, label: 'Contact', url: 'mailto:president@ehsacademics.org'),
  ];

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t open $url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'Links', icon: Icons.link),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _links.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(_links[i].icon,
                        color: EmeraldTheme.emerald),
                    title: Text(_links[i].label),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _open(context, _links[i].url),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer — brand sign-off.
// ---------------------------------------------------------------------------
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SummitLogo(size: 40),
        const SizedBox(height: 8),
        Text(
          SampleData.eventName,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: EmeraldTheme.ink.withValues(alpha: .7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'STEAM, together. Lead, together. Build, together.',
          style: TextStyle(
            fontSize: 12,
            color: EmeraldTheme.ink.withValues(alpha: .5),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shimmer text — a light "glimpse" band that sweeps across the greeting,
// echoing the wordmark shine on the Emerald Summit website.
// ---------------------------------------------------------------------------
class _ShimmerText extends StatefulWidget {
  const _ShimmerText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const Color _base = Colors.white;
  static const Color _highlight = Color(0xFFB9F6D5); // light emerald glimpse

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_base, _base, _highlight, _base, _base],
          stops: const [0.0, 0.38, 0.5, 0.62, 1.0],
          transform: _SweepTransform(_c.value),
        ).createShader(bounds),
        child: child,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}

/// Slides a gradient horizontally so its bright band travels from off the left
/// edge to off the right edge across one animation cycle (clamped ends leave
/// the text its base color between passes).
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.t);
  final double t; // 0..1

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues((2 * t - 1) * bounds.width * 1.4, 0, 0);
}

// ---------------------------------------------------------------------------
// Shared small section header.
// ---------------------------------------------------------------------------
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: EmeraldTheme.emerald),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: EmeraldTheme.ink,
          ),
        ),
      ],
    );
  }
}
