import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_navigation.dart';
import '../app_state.dart';
import '../data/sample_data.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/home_about_sections.dart';
import '../widgets/summit_logo.dart';
import 'announcement_detail_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'session_detail_screen.dart';

/// "Home" tab — the launchpad. Instead of dropping the participant straight
/// into an (often empty) schedule, this greets them, sets the tone with a
/// daily quote, surfaces what's next, and lays out big,
/// action tiles that route into the rest of the app. It stays
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
          await appState.loadGallery();
        },
        child: ListView(
          // Room at the end for the floating tab bar.
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          children: const [
            _Header(),
            SizedBox(height: 16),
            _PhotoSlideshow(),
            _QuoteCard(),
            SizedBox(height: 20),
            _UpNext(),
            SizedBox(height: 24),
            _LatestNews(),
            SizedBox(height: 28),
            SupportEafSection(),
            SizedBox(height: 28),
            SponsorsSection(),
            SizedBox(height: 28),
            _LinksCard(),
            SizedBox(height: 28),
            AboutAppSection(),
            SizedBox(height: 32),
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
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? EmeraldTheme.nightHero
            : EmeraldTheme.emerald,
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
                    Text(
                      '$_greeting,',
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
              const _BellButton(),
              const SizedBox(width: 10),
              const _AvatarButton(),
            ],
          ),
          const SizedBox(height: 18),
          const _SummitCountdown(),
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 15,
                color: Colors.white.withValues(alpha: .9),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: appState,
                  builder: (context, _) {
                    final date = appState.summitStatus.date;
                    return Text(
                      '${date == null ? SampleData.eventDate : formatDay(date)}'
                      '  ·  ${SampleData.eventVenue}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 13,
                      ),
                    );
                  },
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

/// A live countdown in the Home header to the start of the summit's first
/// session. Shows nothing until the summit date is set
/// (`summit_settings.summit_date`) and disappears once the summit starts.
class _SummitCountdown extends StatefulWidget {
  const _SummitCountdown();

  @override
  State<_SummitCountdown> createState() => _SummitCountdownState();
}

class _SummitCountdownState extends State<_SummitCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Skip the rebuild while Home is a hidden tab.
      if (mounted && Visibility.of(context)) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// When summit day's first session starts. Uses the earliest start time
  /// in the catalog from 6 AM on (ignoring a time typed without the 12-hour
  /// offset), or 8 AM when there are none.
  DateTime? _start() {
    final date = appState.summitStatus.date;
    if (date == null) return null;
    final starts = appState.allSessions
        .map((s) => s.startMinutes)
        .where((m) => m >= 6 * 60);
    final first = starts.isEmpty ? 8 * 60 : starts.reduce(min);
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: first));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final start = _start();
        final now = DateTime.now();
        if (start == null || !now.isBefore(start)) {
          return const SizedBox.shrink();
        }
        final left = start.difference(now);
        final days = left.inDays;
        final hours = left.inHours % 24;
        final minutes = left.inMinutes % 60;
        final seconds = left.inSeconds % 60;
        String two(int n) => n.toString().padLeft(2, '0');
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Semantics(
            label:
                '$days days, $hours hours, $minutes minutes until the '
                'summit',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CountdownUnit(
                  value: '$days',
                  label: days == 1 ? 'day' : 'days',
                ),
                _CountdownUnit(value: two(hours), label: 'hr'),
                _CountdownUnit(value: two(minutes), label: 'min'),
                _CountdownUnit(value: two(seconds), label: 'sec'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.05,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .75),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The bell: opens Notifications, with a red count of unread notes.
class _BellButton extends StatelessWidget {
  const _BellButton();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final unread = appState.unreadNotificationCount;
        return Tooltip(
          message: unread > 0
              ? 'Notifications: $unread unread'
              : 'Notifications',
          child: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            largeSize: 20,
            offset: const Offset(2, -2),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => openNotificationsScreen(context),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: .5)),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.notifications_outlined,
                  color: Colors.white,
                  semanticLabel: 'Notifications',
                ),
              ),
            ),
          ),
        );
      },
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
    // Admins: a red count while experts have been waiting since they last
    // opened Profile.
    final waiting = appState.hasUnseenExpertRequests
        ? appState.pendingExpertCount
        : 0;
    return Tooltip(
      message: waiting > 0
          ? 'Profile: $waiting waiting for expert approval'
          : 'Profile',
      child: Badge(
        isLabelVisible: waiting > 0,
        label: Text('$waiting'),
        largeSize: 20,
        offset: const Offset(2, -2),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo slideshow — a rotating band of event photos that auto-advances, to make
// the dashboard feel alive. Photos come from the backend (every image in the
// `gallery_photos` Storage bucket; sample URLs in demo mode) via
// appState.galleryPhotos. Uses a PageView so each photo slides in from the right
// (and the user can swipe by hand); loops seamlessly. Renders nothing when there
// are no photos, so the layout is unaffected.
// ---------------------------------------------------------------------------
class _PhotoSlideshow extends StatefulWidget {
  const _PhotoSlideshow();

  @override
  State<_PhotoSlideshow> createState() => _PhotoSlideshowState();
}

class _PhotoSlideshowState extends State<_PhotoSlideshow> {
  static const Duration _interval = Duration(seconds: 5);
  // A far-from-zero start page so the PageView can loop "infinitely" in both
  // directions; the real photo shown is always page % photoCount.
  static const int _startPage = 100000;

  final PageController _controller = PageController(initialPage: _startPage);
  Timer? _timer;
  int _page = _startPage;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    if (!mounted || appState.galleryPhotos.length < 2) return;
    if (!_controller.hasClients) return;
    // With reduced motion on, cut to the next photo instead of sliding.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(_page + 1);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final photos = appState.galleryPhotos;
        if (photos.isEmpty) return const SizedBox.shrink();

        final active = _page % photos.length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 2 / 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    onPageChanged: (p) => setState(() => _page = p),
                    // itemCount null → scrolls endlessly; index maps onto the
                    // photo list by modulo, so the loop is seamless.
                    itemBuilder: (context, i) =>
                        _slide(photos[i % photos.length]),
                  ),
                  // Bottom scrim so the dots stay legible over bright photos.
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black38, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: _SlideDots(count: photos.length, active: active),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _slide(GalleryPhoto photo) => _SlideImage(photo.imageUrl);
}

/// A slideshow image that auto-retries on load failure. A transient network
/// error (common on flaky venue Wi-Fi) otherwise leaves a permanent broken-image
/// tile, since Flutter caches the failure; this evicts that cached failure and
/// re-attempts a few times, backing off, before finally showing the placeholder.
class _SlideImage extends StatefulWidget {
  const _SlideImage(this.url);
  final String url;

  @override
  State<_SlideImage> createState() => _SlideImageState();
}

class _SlideImageState extends State<_SlideImage> {
  static const int _maxAttempts = 4;
  static const Duration _retryDelay = Duration(seconds: 2);

  int _attempt = 0;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  // Called from errorBuilder (during build), so it must not setState
  // synchronously — the timer defers it to a later frame.
  void _scheduleRetry() {
    if (_retry != null || _attempt >= _maxAttempts) return;
    _retry = Timer(_retryDelay, () {
      _retry = null;
      if (!mounted) return;
      // Drop the cached failure so the image genuinely re-fetches.
      CachedNetworkImage.evictFromCache(widget.url);
      setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Disk-cached so each photo downloads once per device, not on every
    // launch (re-downloads blew through Supabase's cached-egress quota).
    // memCacheWidth decodes at display size so the in-memory cache doesn't
    // thrash and force re-reads while the slideshow loops.
    return CachedNetworkImage(
      imageUrl: widget.url,
      // A new key per attempt forces a fresh load after eviction.
      key: ValueKey(_attempt),
      fit: BoxFit.cover,
      memCacheWidth: 1200,
      fadeInDuration: Duration.zero,
      placeholder: (context, _) => const _SlidePlaceholder(),
      errorWidget: (context, _, _) {
        _scheduleRetry();
        return const _SlidePlaceholder(icon: Icons.broken_image_outlined);
      },
    );
  }
}

/// Neutral fill shown while a slide image loads or if it fails.
class _SlidePlaceholder extends StatelessWidget {
  const _SlidePlaceholder({this.icon});
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      alignment: Alignment.center,
      child: icon == null
          ? const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(
              icon,
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .5),
            ),
    );
  }
}

/// Page-dot indicator; the active dot is wider and opaque.
class _SlideDots extends StatelessWidget {
  const _SlideDots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == active ? .95 : .5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Daily quote — a quiet typographic break between sections.
// ---------------------------------------------------------------------------
class _QuoteCard extends StatelessWidget {
  const _QuoteCard();

  static const List<({String quote, String author})> _quotes = [
    (
      quote: 'The science of today is the technology of tomorrow.',
      author: 'Edward Teller',
    ),
    (
      quote: 'Creativity is intelligence having fun.',
      author: 'Albert Einstein',
    ),
    (
      quote: 'Somewhere, something incredible is waiting to be known.',
      author: 'Carl Sagan',
    ),
    (
      quote: 'The best way to predict the future is to invent it.',
      author: 'Alan Kay',
    ),
    (
      quote: 'Design is not just what it looks like. Design is how it works.',
      author: 'Steve Jobs',
    ),
    (
      quote: 'Pure mathematics is, in its way, the poetry of logical ideas.',
      author: 'Albert Einstein',
    ),
    (
      quote: 'What we know is a drop, what we don\'t know is an ocean.',
      author: 'Isaac Newton',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays;
    final q = _quotes[dayOfYear % _quotes.length];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.primary, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.quote,
              style: TextStyle(
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              q.author,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Up next — the participant's next session, or a plan-your-day nudge.
// ---------------------------------------------------------------------------
class _UpNext extends StatefulWidget {
  const _UpNext();

  @override
  State<_UpNext> createState() => _UpNextState();
}

class _UpNextState extends State<_UpNext> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // On summit day the card moves on as sessions end.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.scheduleEntries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _PlanNudge(),
          );
        }
        final next = appState.upNext(DateTime.now());
        if (next == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _NextSessionCard(session: next),
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
        const _SectionTitle(title: 'Up next'),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => openSession(context, session, from: context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Text(
                          session.timeLabel.split(' – ').first,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
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
                        Text(
                          session.title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${session.disciplineName} · ${session.roomLabel}',
                          style: theme.textTheme.bodySmall,
                        ),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: .5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.event_available,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your day is a blank slate',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                SizedBox(height: 2),
                Text(
                  'Browse sessions and build your schedule.',
                  style: TextStyle(fontSize: 13),
                ),
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
          const _SectionTitle(title: 'Latest announcements'),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openAnnouncement(context, a),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (a.pinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            a.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(a.timeAgo, style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.body,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
    (
      icon: Icons.language,
      label: 'Summit website',
      url: 'https://emeraldsummit.ehsacademics.org',
    ),
    (
      icon: Icons.camera_alt,
      label: 'Instagram',
      url: 'https://www.instagram.com/emeraldsummit27?stkn=MzRlODBiNWFlZA==',
    ),
    (
      icon: Icons.mail_outline,
      label: 'Contact',
      url: 'mailto:president@ehsacademics.org',
    ),
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
          const _SectionTitle(title: 'Links'),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _links.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      _links[i].icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
// Shared small section header.
// ---------------------------------------------------------------------------
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
