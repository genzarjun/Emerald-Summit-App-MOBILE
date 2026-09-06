import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/summit_logo.dart';

/// Deep-emerald backdrop the burst radiates from. Matches the native launch
/// background (iOS storyboard / Android launch_background) so a cold start
/// flows straight into the animation with no flash.
const Color _bgTop = Color(0xFF063C2A);
const Color _bgBottom = Color(0xFF02100B);

/// Animated launch splash: an emerald sunburst where a warp field of sparks
/// streams outward while the "sun" (a glowing orb carrying the [SummitLogo])
/// scales *in* to a peak, holds a beat, then recedes back *out* as the whole
/// screen fades to reveal [next]. Duolingo-style haptics pulse through it.
///
/// Shown once at app start; on completion it replaces itself with [next] via a
/// cross-fade, so the animation is never seen again this session.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// The real first screen (auth gate or root nav) revealed once the splash
  /// finishes.
  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Ray> _rays;

  /// Haptic beats keyed to points in the timeline (0..1). Each fires once.
  static const List<_Beat> _beats = [
    _Beat(0.02, _Haptic.medium), // the burst arrives
    _Beat(0.12, _Haptic.light),
    _Beat(0.20, _Haptic.light),
    _Beat(0.29, _Haptic.light),
    _Beat(0.38, _Haptic.light),
    _Beat(0.46, _Haptic.heavy), // sun at peak
    _Beat(0.74, _Haptic.light), // recede begins
    _Beat(0.86, _Haptic.light),
  ];
  final Set<int> _firedBeats = {};

  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(27); // fixed seed → the same handsome burst each run
    _rays = List.generate(230, (_) => _Ray.random(rng));

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )
      ..addListener(_fireBeats)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _handOff();
      });

    // Kick off after the first frame so the very first haptic lands with the
    // burst rather than during route construction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  void _fireBeats() {
    final t = _controller.value;
    for (var i = 0; i < _beats.length; i++) {
      if (!_firedBeats.contains(i) && t >= _beats[i].at) {
        _firedBeats.add(i);
        _beats[i].haptic.fire();
      }
    }
  }

  void _handOff() {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBottom,
      body: GestureDetector(
        // Tap anywhere to skip straight to the app.
        onTap: () {
          _controller.stop();
          _handOff();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return CustomPaint(
              painter: _SunburstPainter(t: t, rays: _rays),
              size: Size.infinite,
              child: _content(t),
            );
          },
        ),
      ),
    );
  }

  /// Logo + wordmark. The logo sits at the exact screen centre so the painted
  /// sun-glow blooms directly behind it; the wordmark rides just below.
  Widget _content(double t) {
    // Logo scale/opacity: in (0→0.42) with overshoot, hold, out (0.68→1).
    final double scale;
    final double opacity;
    if (t < 0.42) {
      final p = Curves.easeOutBack.transform(t / 0.42);
      scale = 0.2 + 0.8 * p;
      opacity = Curves.easeOut.transform((t / 0.42).clamp(0, 1));
    } else if (t < 0.68) {
      scale = 1.0;
      opacity = 1.0;
    } else {
      final p = Curves.easeInCubic.transform((t - 0.68) / 0.32);
      scale = 1.0 - 0.35 * p; // recede back toward a point
      opacity = 1.0 - p;
    }

    final outFade =
        1 - Curves.easeInCubic.transform(((t - 0.68) / 0.32).clamp(0.0, 1.0));
    final wordOpacity = ((t - 0.30) / 0.15).clamp(0.0, 1.0) * outFade;

    return Stack(
      children: [
        Align(
          alignment: Alignment.center,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: const SummitLogo(size: 116),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.17),
          child: Opacity(
            opacity: wordOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EMERALD SUMMIT',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '’27',
                  style: TextStyle(
                    color: const Color(0xFF6EE7B7),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One streak in the warp field. Its angle, length and brightness are fixed;
/// [phase] staggers where it is along its outward run so the field streams
/// continuously rather than firing in a single synchronized sweep.
class _Ray {
  _Ray({
    required this.angle,
    required this.phase,
    required this.lengthFrac,
    required this.width,
    required this.brightness,
  });

  final double angle; // radians
  final double phase; // 0..1 offset into the outward run
  final double lengthFrac; // streak length as a fraction of maxR
  final double width;
  final double brightness; // 0..1

  factory _Ray.random(math.Random rng) {
    return _Ray(
      angle: rng.nextDouble() * math.pi * 2,
      phase: rng.nextDouble(),
      lengthFrac: 0.10 + rng.nextDouble() * 0.28,
      width: 0.7 + rng.nextDouble() * 1.9,
      brightness: 0.45 + rng.nextDouble() * 0.55,
    );
  }
}

class _SunburstPainter extends CustomPainter {
  _SunburstPainter({required this.t, required this.rays});

  final double t; // 0..1 timeline
  final List<_Ray> rays;

  /// How many times a ray traverses centre→edge across the whole splash.
  static const double _loops = 1.35;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Reach the far corners so the burst always fills the screen.
    final maxR =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;

    _paintBackground(canvas, size, center, maxR);
    _paintRays(canvas, center, maxR);
    _paintGlow(canvas, center, maxR);
  }

  /// Envelope: rays and glow swell in (0→0.42), hold, then recede out (0.68→1).
  double get _envelope {
    final in_ = Curves.easeOut.transform((t / 0.42).clamp(0.0, 1.0));
    final out =
        1 - Curves.easeInCubic.transform(((t - 0.68) / 0.32).clamp(0.0, 1.0));
    return in_ * out;
  }

  void _paintBackground(Canvas canvas, Size size, Offset center, double maxR) {
    // Vertical brand gradient, lifted by a gentle radial emerald bloom at the
    // core (kept subtle so the sparks stay legible over it).
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [_bgTop, _bgBottom],
        ),
    );

    final bloom = _envelope;
    if (bloom <= 0) return;
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..shader = ui.Gradient.radial(center, maxR, [
          const Color(0xFF0C7A55).withValues(alpha: 0.30 * bloom),
          const Color(0xFF0C7A55).withValues(alpha: 0.0),
        ], const [0.0, 0.6]),
    );
  }

  void _paintRays(Canvas canvas, Offset center, double maxR) {
    final env = _envelope;
    if (env <= 0) return;

    final base = t * _loops;
    final coreR = maxR * 0.05; // streaks emerge from just behind the logo
    final rayColor = Color.lerp(
        const Color(0xFFEAFFF6), const Color(0xFF6EE7B7), 0.35)!;

    for (final ray in rays) {
      final dir = Offset(math.cos(ray.angle), math.sin(ray.angle));
      final p = (ray.phase + base) % 1.0; // 0 at core, 1 at edge

      final headR = ui.lerpDouble(coreR, maxR, p)!;
      final tailR = math.max(coreR, headR - ray.lengthFrac * maxR);

      // Fade in as the streak leaves the core, fade out as it nears the edge.
      final centerFade = (p / 0.10).clamp(0.0, 1.0);
      final edgeFade = (1 - (p - 0.72) / 0.28).clamp(0.0, 1.0);
      final a = ray.brightness * env * centerFade * edgeFade;
      if (a <= 0.01) continue;

      final head = center + dir * headR;
      final tail = center + dir * tailR;
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = ray.width
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, [
            rayColor.withValues(alpha: 0.0),
            rayColor.withValues(alpha: a.clamp(0.0, 1.0)),
          ]),
      );
    }
  }

  void _paintGlow(Canvas canvas, Offset center, double maxR) {
    // Bright core behind the logo — the "sun" itself.
    final intensity = _envelope;
    if (intensity <= 0) return;

    final r = maxR * (0.10 + 0.06 * intensity);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          const Color(0xFFEAFFF6).withValues(alpha: 0.75 * intensity),
          const Color(0xFF6EE7B7).withValues(alpha: 0.30 * intensity),
          const Color(0xFF6EE7B7).withValues(alpha: 0.0),
        ], const [0.0, 0.4, 1.0])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// A haptic beat scheduled at a point in the timeline.
class _Beat {
  const _Beat(this.at, this.haptic);
  final double at;
  final _Haptic haptic;
}

enum _Haptic {
  light,
  medium,
  heavy;

  void fire() {
    switch (this) {
      case _Haptic.light:
        HapticFeedback.lightImpact();
      case _Haptic.medium:
        HapticFeedback.mediumImpact();
      case _Haptic.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}
