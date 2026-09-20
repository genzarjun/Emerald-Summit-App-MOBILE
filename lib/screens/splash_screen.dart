import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Deep-emerald backdrop the scene sits on. Matches the native launch
/// background (iOS storyboard / Android launch_background) so a cold start
/// flows straight into the animation with no flash.
const Color _bgBottom = Color(0xFF02100B);

// --- Brand palette (from the Emerald Summit site hero) ---
const Color _skyCore = Color(0xFF0C4A35); // emerald behind the sun
const Color _skyEdge = Color(0xFF031410); // vignette edge
const Color _skyBottom = Color(0xFF010C09);
const Color _sunCore = Color(0xFFEAFFF6); // white-hot centre
const Color _sunBody = Color(0xFF34E1C4); // bright cyan-emerald
const Color _sunHalo = Color(0xFF2EC8AA);
const Color _mtnBack = Color(0xFF469678);
const Color _mtnFront = Color(0xFF96DCC8);
const Color _frost = Color(0xFFC8F5E6);

/// Animated launch splash — "Arc Traverse". A glowing emerald sun rises from
/// behind the left peaks of a mountain-range summit, arcs across a starry
/// emerald sky, and sets behind the right peaks. As it crosses its apex the
/// wordmark "Emerald Summit '27" wipes on left→right and holds on one line
/// until the animation completes. A Duolingo-style haptic crescendo — soft
/// taps accelerating into the crest, then a gentle settle — rides the arc.
///
/// Shown once at app start; on completion it cross-fades to [next], so the
/// animation is never seen again this session.
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
  late final _Scene _scene;

  /// Haptic beats keyed to points in the timeline (0..1). Times accelerate
  /// toward the sun's crest (~0.50) for a build-up, then settle as it sets.
  /// Each fires once.
  static const List<_Beat> _beats = [
    _Beat(0.08, _Haptic.select),
    _Beat(0.22, _Haptic.select),
    _Beat(0.32, _Haptic.select),
    _Beat(0.40, _Haptic.light),
    _Beat(0.45, _Haptic.light),
    _Beat(0.48, _Haptic.medium),
    _Beat(0.50, _Haptic.heavy), // sun at its apex — the crest
    _Beat(0.68, _Haptic.light), // recede / settle
    _Beat(0.84, _Haptic.select),
  ];
  final Set<int> _firedBeats = {};

  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _scene = _Scene.generate(math.Random(23));

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )
      ..addListener(_fireBeats)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _handOff();
      });

    // Kick off after the first frame so the very first haptic lands with the
    // animation rather than during route construction.
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
            return CustomPaint(
              painter: _SplashPainter(t: _controller.value, scene: _scene),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene data — generated once with a fixed seed so every launch is identical.
// All coordinates are normalized (0..1) and scaled to the canvas at paint time.
// ---------------------------------------------------------------------------

class _Scene {
  _Scene({
    required this.stars,
    required this.rays,
    required this.back,
    required this.front,
  });

  final List<_Star> stars;
  final List<_Ray> rays;
  final List<Offset> back; // back mountain ridge (normalized)
  final List<Offset> front; // front mountain ridge (normalized)

  factory _Scene.generate(math.Random r) {
    final stars = List.generate(
      90,
      (_) => _Star(
        x: r.nextDouble(),
        y: r.nextDouble() * 0.82,
        radius: 0.4 + r.nextDouble() * 1.4,
        alpha: 0.15 + r.nextDouble() * 0.6,
        phase: r.nextDouble() * math.pi * 2,
        speed: 0.5 + r.nextDouble() * 1.5,
      ),
    );

    const nRays = 44;
    final rays = List.generate(nRays, (i) {
      return _Ray(
        angle: i / nRays * math.pi * 2 + r.nextDouble() * 0.06,
        length: 0.55 + r.nextDouble() * 0.9,
        width: 0.6 + r.nextDouble() * 1.3,
        alpha: 0.25 + r.nextDouble() * 0.55,
      );
    });

    List<Offset> ridge(int n, double amp, double base) {
      return List.generate(n + 1, (i) {
        final jag = math.pow(r.nextDouble(), 1.7).toDouble();
        return Offset(i / n, base - amp * jag);
      });
    }

    return _Scene(
      stars: stars,
      rays: rays,
      back: ridge(9, 0.13, 0.86),
      front: ridge(13, 0.20, 0.92),
    );
  }
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.alpha,
    required this.phase,
    required this.speed,
  });
  final double x, y, radius, alpha, phase, speed;
}

class _Ray {
  const _Ray({
    required this.angle,
    required this.length,
    required this.width,
    required this.alpha,
  });
  final double angle, length, width, alpha;
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _SplashPainter extends CustomPainter {
  _SplashPainter({required this.t, required this.scene});

  final double t; // 0..1 timeline
  final _Scene scene;

  // Sun path constants.
  static const double _horizon = 0.80; // where it sits at rise/set
  static const double _rise = 0.52; // fraction of H it climbs above horizon

  // Wordmark timing.
  static const double _wipeStart = 0.28;
  static const double _wipeEnd = 0.52;
  static const double _wordY = 0.60;

  double get _dayness => math.sin(t.clamp(0.0, 1.0) * math.pi); // 0→1→0

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final day = _dayness;

    _paintSky(canvas, size, day);
    _paintStars(canvas, size, day);

    // Sun position (arc, left → right). Drawn BEFORE the mountains so it rises
    // and sets behind the peaks.
    final sx = w * ui.lerpDouble(0.20, 0.80, t.clamp(0.0, 1.0))!;
    final climb = math.sin(t.clamp(0.0, 1.0) * math.pi);
    final sy = h * (_horizon - climb * _rise * 0.62);
    final radius = w * 0.10;
    _paintSun(canvas, Offset(sx, sy), radius, math.max(day, 0.08));

    _paintMountains(canvas, size, day);
    _paintWordmark(canvas, size);
    _paintHandoffDip(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size, double day) {
    final w = size.width, h = size.height;
    final center = Offset(w * 0.5, h * 0.34);
    final c0 = Color.lerp(_skyEdge, _skyCore, 0.4 + 0.6 * day)!;
    final c1 = Color.lerp(_skyEdge, _skyCore, 0.15 + 0.2 * day)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          h * 0.95,
          [c0, c1, _skyBottom],
          const [0.0, 0.55, 1.0],
        ),
    );
  }

  void _paintStars(Canvas canvas, Size size, double day) {
    final w = size.width, h = size.height;
    final dim = 1 - 0.45 * day;
    final paint = Paint();
    for (final s in scene.stars) {
      final tw = 0.55 + 0.45 * math.sin(t * math.pi * 2 * s.speed + s.phase);
      final a = (s.alpha * dim * tw).clamp(0.0, 1.0);
      if (a <= 0.01) continue;
      paint.color = const Color(0xFFDCFFF4).withValues(alpha: a);
      canvas.drawCircle(Offset(s.x * w, s.y * h), s.radius, paint);
    }
  }

  void _paintSun(Canvas canvas, Offset c, double r, double day) {
    // Soft outer glow.
    final glowR = r * 3.2;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = ui.Gradient.radial(c, glowR, [
          _sunCore.withValues(alpha: 0.55 * day),
          _sunBody.withValues(alpha: 0.30 * day),
          _sunHalo.withValues(alpha: 0.0),
        ], const [0.0, 0.28, 1.0]),
    );

    // Fine needle rays (additive).
    final spin = t * 0.4;
    for (final ray in scene.rays) {
      final tw = 0.75 + 0.25 * math.sin(t * math.pi * 6 * ray.width + ray.angle * 7);
      final a = ray.alpha * day * tw;
      if (a <= 0.01) continue;
      final ang = ray.angle + spin;
      final dir = Offset(math.cos(ang), math.sin(ang));
      final p0 = c + dir * (r * 1.05);
      final p1 = c + dir * (r * (1.05 + ray.length));
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..strokeWidth = ray.width
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(p0, p1, [
            _sunCore.withValues(alpha: (a * 0.8).clamp(0.0, 1.0)),
            _sunBody.withValues(alpha: 0.0),
          ]),
      );
    }

    // Bright disc.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(c.dx, c.dy - r * 0.15),
          r,
          [
            _sunCore.withValues(alpha: day),
            _sunBody.withValues(alpha: 0.95 * day),
            _sunHalo.withValues(alpha: 0.15 * day),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );
  }

  void _paintMountains(Canvas canvas, Size size, double day) {
    final w = size.width, h = size.height;

    _paintRange(canvas, size, scene.back, _mtnBack, 0.55 + 0.25 * day, false);

    // Ground glow strip behind the front range.
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.82, w, h * 0.18),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.82),
          Offset(0, h),
          [
            _frost.withValues(alpha: 0.0),
            _frost.withValues(alpha: 0.12 + 0.12 * day),
          ],
        ),
    );

    _paintRange(canvas, size, scene.front, _mtnFront, 0.5 + 0.2 * day, true);
  }

  void _paintRange(
    Canvas canvas,
    Size size,
    List<Offset> ridge,
    Color color,
    double alpha,
    bool rim,
  ) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(0, h);
    for (final p in ridge) {
      path.lineTo(p.dx * w, p.dy * h);
    }
    path
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.6),
          Offset(0, h),
          [
            color.withValues(alpha: alpha * 0.85),
            color.withValues(alpha: alpha * 0.35),
          ],
        ),
    );

    if (rim) {
      final edge = Path()..moveTo(0, ridge.first.dy * h);
      for (final p in ridge) {
        edge.lineTo(p.dx * w, p.dy * h);
      }
      canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _frost.withValues(alpha: alpha * 0.55),
      );
    }
  }

  void _paintWordmark(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final wipe = _easeOutCubic(
        ((t - _wipeStart) / (_wipeEnd - _wipeStart)).clamp(0.0, 1.0));
    final alpha = _easeOutCubic(((t - _wipeStart) / 0.08).clamp(0.0, 1.0));
    if (alpha <= 0.01) return;

    var fs = w * 0.072;
    final maxW = w * 0.88;

    // Measure at the trial size, then shrink to fit on one line.
    double emeraldW(double size) => _measure('Emerald ', size);
    double summitW(double size) => _measure('Summit', size);
    double tailW(double size) => _measure(' ’27', size);
    double totalW(double size) => emeraldW(size) + summitW(size) + tailW(size);

    if (totalW(fs) > maxW) fs *= maxW / totalW(fs);

    final wE = emeraldW(fs);
    final wS = summitW(fs);
    final total = wE + wS + tailW(fs);
    final baseX = (w - total) / 2;
    final y = h * _wordY;

    // "Summit" gradient shader, positioned in canvas space.
    final summitShader = ui.Gradient.linear(
      Offset(baseX + wE, y),
      Offset(baseX + wE + wS, y),
      const [Color(0xFFD1FAE5), Color(0xFF10B981)],
    );

    final span = TextSpan(
      style: TextStyle(
        fontSize: fs,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        height: 1.0,
      ),
      children: [
        const TextSpan(
          text: 'Emerald ',
          style: TextStyle(color: _sunCore),
        ),
        TextSpan(
          text: 'Summit',
          style: TextStyle(foreground: Paint()..shader = summitShader),
        ),
        const TextSpan(
          text: ' ’27',
          style: TextStyle(color: Color(0xFF6EE7B7)),
        ),
      ],
    );

    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();

    // Layer opacity for the fade-in ramp.
    final bounds = Rect.fromLTWH(baseX - 8, y - fs, total + 16, fs * 2);
    canvas.saveLayer(
      bounds,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );

    // Left→right wipe reveal.
    final revealW = total * wipe;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(baseX - 4, y - fs, revealW + 8, fs * 2));
    tp.paint(canvas, Offset(baseX, y - tp.height / 2));
    canvas.restore();

    // Leading shine at the wipe edge.
    if (wipe > 0.02 && wipe < 0.99) {
      final ex = baseX + revealW;
      canvas.drawRect(
        Rect.fromLTWH(ex - fs * 0.7, y - fs * 0.85, fs, fs * 1.7),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(ex - fs * 0.7, y),
            Offset(ex + fs * 0.3, y),
            [
              _sunCore.withValues(alpha: 0.0),
              _sunCore.withValues(alpha: 0.5),
            ],
          ),
      );
    }

    canvas.restore();
  }

  double _measure(String text, double fs) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  /// Final handoff: dip the whole scene into the brand ground so the fade to
  /// the next screen is seamless.
  void _paintHandoffDip(Canvas canvas, Size size) {
    final out = _smoothstep(((t - 0.93) / 0.07).clamp(0.0, 1.0));
    if (out <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _skyBottom.withValues(alpha: out),
    );
  }

  static double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
  static double _smoothstep(double x) => x * x * (3 - 2 * x);

  @override
  bool shouldRepaint(covariant _SplashPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// A haptic beat scheduled at a point in the timeline.
class _Beat {
  const _Beat(this.at, this.haptic);
  final double at;
  final _Haptic haptic;
}

enum _Haptic {
  select,
  light,
  medium,
  heavy;

  void fire() {
    switch (this) {
      case _Haptic.select:
        HapticFeedback.selectionClick();
      case _Haptic.light:
        HapticFeedback.lightImpact();
      case _Haptic.medium:
        HapticFeedback.mediumImpact();
      case _Haptic.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}
