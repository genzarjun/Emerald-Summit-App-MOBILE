import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'discipline_vibe.dart';

/// Base state for the looping effects below: a ticker that counts seconds
/// into [clock] and pauses while the widget is hidden (an inactive tab in the
/// shell's IndexedStack) or when the system asks for reduced motion. Tickers
/// are also muted by [TickerMode] once another route covers the page.
abstract class _EffectState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin<T> {
  final ValueNotifier<double> clock = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_tick);
  double _resumeAt = 0;

  void _tick(Duration elapsed) =>
      clock.value = _resumeAt + elapsed.inMicroseconds / 1e6;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run =
        Visibility.of(context) && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _resumeAt = clock.value;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    clock.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Ambient background motif
// ---------------------------------------------------------------------------

/// A discipline's animated background (see [VibeMotif]). [compact] draws a
/// lighter version sized for a card.
class AmbientMotif extends StatefulWidget {
  const AmbientMotif({super.key, required this.vibe, this.compact = false});

  final DisciplineVibe vibe;
  final bool compact;

  @override
  State<AmbientMotif> createState() => _AmbientMotifState();
}

class _AmbientMotifState extends _EffectState<AmbientMotif> {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MotifPainter(widget.vibe, widget.compact, clock),
        size: Size.infinite,
      ),
    );
  }
}

/// Seeded particle field shared by the motifs: positions, sizes and phases
/// stay fixed per motif so the scene doesn't jump between rebuilds.
class _Particle {
  _Particle(math.Random r)
    : x = r.nextDouble(),
      y = r.nextDouble(),
      size = r.nextDouble(),
      speed = .5 + r.nextDouble(),
      phase = r.nextDouble() * math.pi * 2,
      flag = r.nextBool();
  final double x, y, size, speed, phase;
  final bool flag;
}

final Map<String, List<_Particle>> _fields = {};

List<_Particle> _field(String key, int count, int seed) =>
    _fields.putIfAbsent(key, () {
      final r = math.Random(seed);
      return [for (var i = 0; i < count; i++) _Particle(r)];
    });

class _MotifPainter extends CustomPainter {
  _MotifPainter(this.vibe, this.compact, this.clock) : super(repaint: clock);

  final DisciplineVibe vibe;
  final bool compact;
  final ValueNotifier<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = clock.value;
    switch (vibe.motif) {
      case VibeMotif.circuit:
        _circuit(canvas, size, t);
      case VibeMotif.ticker:
        _ticker(canvas, size, t);
      case VibeMotif.cells:
        _cells(canvas, size, t);
      case VibeMotif.stars:
        _stars(canvas, size, t);
      case VibeMotif.ripples:
        _ripples(canvas, size, t);
      case VibeMotif.paint:
        _paint(canvas, size, t);
    }
  }

  String get _key => '${vibe.motif.name}-$compact';

  void _circuit(Canvas canvas, Size size, double t) {
    final g = compact ? 16.0 : 26.0;
    final dots = <Offset>[
      for (var x = g / 2; x < size.width; x += g)
        for (var y = g / 2; y < size.height; y += g) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = vibe.accent.withValues(alpha: .13)
        ..strokeWidth = compact ? 1.2 : 1.6
        ..strokeCap = StrokeCap.round,
    );

    // Data pulses racing along grid lanes, each with a fading tail.
    final lanesX = (size.width / g).floor();
    final lanesY = (size.height / g).floor();
    for (final p in _field(_key, compact ? 4 : 11, 7)) {
      final horizontal = p.flag;
      final length = horizontal ? size.width : size.height;
      final tail = compact ? 34.0 : 70.0;
      final travel = ((t * .16 * p.speed + p.phase) % 1.3) - .15;
      final head = travel * (length + tail);
      final lane = horizontal
          ? (p.y * lanesY).floor() * g + g / 2
          : (p.x * lanesX).floor() * g + g / 2;
      final a = horizontal
          ? Offset(head - tail, lane)
          : Offset(lane, head - tail);
      final b = horizontal ? Offset(head, lane) : Offset(lane, head);
      final color = p.size > .5 ? vibe.accent : vibe.accent2;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0), color.withValues(alpha: .9)],
          ).createShader(Rect.fromPoints(a, b)),
      );
      canvas.drawCircle(
        b,
        compact ? 3 : 5,
        Paint()
          ..color = color.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(b, 1.6, Paint()..color = Colors.white);
    }
  }

  void _ticker(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    final grid = Paint()
      ..color = vibe.accent.withValues(alpha: .06)
      ..strokeWidth = 1;
    final step = compact ? 22.0 : 44.0;
    for (var y = step; y < h; y += step) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    // A chart line that scrolls left and trends up and to the right.
    final line = Path();
    final fill = Path()..moveTo(0, h);
    final scroll = t * (compact ? 14 : 26);
    final amp = compact ? .6 : 1.0;
    double yAt(double x) {
      final u = (x + scroll) / 14;
      final wiggle =
          math.sin(u * .5) * 16 +
          math.sin(u * 1.3 + 1) * 8 +
          math.sin(u * .21) * 26;
      return h * .78 - (x / w) * h * .32 + wiggle * amp;
    }

    for (var x = 0.0; x <= w + 6; x += 6) {
      final y = yAt(x);
      if (x == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      fill.lineTo(x, y);
    }
    fill
      ..lineTo(w + 6, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            vibe.accent.withValues(alpha: .16),
            vibe.accent.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.4 : 2
        ..color = vibe.accent.withValues(alpha: .55),
    );
    final headX = w * .82;
    final pulse = .5 + .5 * math.sin(t * 3);
    canvas.drawCircle(
      Offset(headX, yAt(headX)),
      (compact ? 5 : 8) + pulse * 4,
      Paint()
        ..color = vibe.accent2.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      Offset(headX, yAt(headX)),
      compact ? 2 : 3,
      Paint()..color = vibe.accent2,
    );

    // Embers rising off the chart.
    for (final p in _field(_key, compact ? 6 : 18, 11)) {
      final rise = (t * .12 * p.speed + p.phase) % 1;
      final y = h * (1.05 - rise * 1.1);
      final x = p.x * w + math.sin(t + p.phase) * 8;
      canvas.drawCircle(
        Offset(x, y),
        .8 + p.size * (compact ? 1.2 : 2),
        Paint()
          ..color = (p.flag ? vibe.accent : vibe.accent2).withValues(
            alpha: (1 - rise) * .7,
          ),
      );
    }
  }

  void _cells(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    for (final p in _field(_key, compact ? 7 : 15, 23)) {
      final r = (compact ? 6 : 12) + p.size * (compact ? 14 : 30);
      final rise = (t * .03 * p.speed + p.phase / (math.pi * 2)) % 1;
      final y = h + r - rise * (h + r * 2);
      final x = p.x * w + math.sin(t * .6 + p.phase) * (compact ? 6 : 14);
      final breathe = 1 + .06 * math.sin(t * 1.4 + p.phase);
      final c = Offset(x, y);
      final color = p.flag ? vibe.accent : vibe.accent2;
      canvas.drawCircle(
        c,
        r * breathe,
        Paint()..color = color.withValues(alpha: .06),
      );
      canvas.drawCircle(
        c,
        r * breathe,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: .32),
      );
      final wobble = Offset(
        math.cos(t * .9 + p.phase) * r * .22,
        math.sin(t * 1.1 + p.phase) * r * .22,
      );
      canvas.drawCircle(
        c + wobble,
        r * .3,
        Paint()..color = color.withValues(alpha: .4),
      );
    }
  }

  void _stars(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    for (final p in _field(_key, compact ? 36 : 120, 31)) {
      final twinkle =
          .25 + .75 * (.5 + .5 * math.sin(t * (1 + p.speed) + p.phase));
      final color = p.size > .85
          ? (p.flag ? vibe.accent : vibe.accent2)
          : Colors.white;
      canvas.drawCircle(
        Offset(p.x * w, p.y * h),
        .4 + p.size * (compact ? 1 : 1.4),
        Paint()..color = color.withValues(alpha: twinkle * .85),
      );
    }

    // Two tilted orbits, each carrying a planet.
    final center = compact
        ? Offset(w * .72, h * .28)
        : Offset(w * .78, h * .16);
    void orbit(double rx, double ry, double speed, Color planet, double alpha) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-.35);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2,
        height: ry * 2,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = vibe.accent.withValues(alpha: alpha),
      );
      final a = t * speed;
      final pos = Offset(math.cos(a) * rx, math.sin(a) * ry);
      canvas.drawCircle(
        pos,
        compact ? 5 : 8,
        Paint()
          ..color = planet.withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(pos, compact ? 2.4 : 3.6, Paint()..color = planet);
      canvas.restore();
    }

    final base = compact ? w * .45 : w * .42;
    orbit(base, base * .32, .45, vibe.accent, .2);
    orbit(base * 1.5, base * .5, -.25, vibe.accent2, .1);

    // A shooting star every few seconds.
    if (!compact) {
      final cycle = (t % 6.5) / 6.5;
      if (cycle < .14) {
        final k = cycle / .14;
        final start = Offset(w * .15, h * .08);
        final head = start + Offset(w * .55, h * .22) * k;
        final tail = head - Offset(w * .55, h * .22) * .25;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: (1 - k) * .9),
              ],
            ).createShader(Rect.fromPoints(tail, head)),
        );
      }
    }
  }

  void _ripples(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    // Faint columns, like a courthouse front.
    final column = Paint()
      ..color = vibe.accent.withValues(alpha: .05)
      ..strokeWidth = 1;
    final cols = compact ? 4 : 6;
    for (var i = 1; i < cols; i++) {
      final x = w * i / cols;
      canvas.drawLine(Offset(x - 5, 0), Offset(x - 5, h), column);
      canvas.drawLine(Offset(x + 5, 0), Offset(x + 5, h), column);
    }

    // Rings spreading from a gavel strike, three at a time.
    final origin = compact ? Offset(w * .78, h * .2) : Offset(w * .5, h * .12);
    final maxR = math.sqrt(w * w + h * h) * (compact ? .8 : .9);
    const period = 3.6;
    for (var k = 0; k < 3; k++) {
      final p = ((t / period) + k / 3) % 1;
      final fade = (1 - p) * (1 - p);
      canvas.drawCircle(
        origin,
        p * maxR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = (k.isEven ? vibe.accent : vibe.accent2).withValues(
            alpha: fade * .35,
          ),
      );
    }
    canvas.drawCircle(
      origin,
      compact ? 3 : 4,
      Paint()..color = vibe.accent.withValues(alpha: .7),
    );
  }

  void _paint(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    final radius = math.min(w, h) * (compact ? .55 : .45);
    var i = 0;
    for (final p in _field(_key, 5, 47)) {
      final c = Offset(
        w * (.5 + .4 * math.sin(t * .23 * p.speed + p.phase)),
        h * (.5 + .42 * math.sin(t * .17 * (2 - p.speed) + p.phase * 1.7)),
      );
      // Drift each blob slowly from one palette color to the next.
      final colors = vibe.flowColors;
      final f = (t * .08 + i * .9) % colors.length;
      final color = Color.lerp(
        colors[f.floor() % colors.length],
        colors[(f.floor() + 1) % colors.length],
        f - f.floor(),
      )!;
      final r = radius * (.75 + .25 * math.sin(t * .5 + p.phase));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: .2), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      i++;
    }
  }

  @override
  bool shouldRepaint(_MotifPainter old) =>
      old.vibe != vibe || old.compact != compact || old.clock != clock;
}

// ---------------------------------------------------------------------------
// Flowing border
// ---------------------------------------------------------------------------

/// A band of liquid light that flows around the edge of the screen in a
/// discipline's colors. [intro] (0 to 1) pours it in from the top center.
/// Draw it above the content inside an [IgnorePointer].
class FlowingBorder extends StatefulWidget {
  const FlowingBorder({
    super.key,
    required this.vibe,
    this.intro,
    this.cornerRadius = 44,
  });

  final DisciplineVibe vibe;
  final Animation<double>? intro;
  final double cornerRadius;

  @override
  State<FlowingBorder> createState() => _FlowingBorderState();
}

class _FlowingBorderState extends _EffectState<FlowingBorder> {
  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BorderPainter(
          widget.vibe,
          clock,
          still ? null : widget.intro,
          widget.cornerRadius,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Points around the screen edge with the inward normal at each one.
class _Perimeter {
  _Perimeter(Size size, double radius) {
    final rect = Offset.zero & size;
    final metric =
        (Path()..addRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(radius)),
            ))
            .computeMetrics()
            .first;
    final inner = rect.deflate(2);
    var bestTop = double.infinity;
    for (var i = 0; i < count; i++) {
      final tan = metric.getTangentForOffset(metric.length * i / count)!;
      var n = Offset(-tan.vector.dy, tan.vector.dx);
      if (!inner.contains(tan.position + n * 8)) n = -n;
      points.add(tan.position);
      normals.add(n);
      final d = (tan.position - Offset(size.width / 2, 0)).distanceSquared;
      if (d < bestTop) {
        bestTop = d;
        top = i;
      }
    }
  }

  static const count = 220;
  final List<Offset> points = [];
  final List<Offset> normals = [];

  /// Index of the sample nearest the top center, where the intro pours in.
  int top = 0;

  static final Map<(Size, double), _Perimeter> _cache = {};
  static _Perimeter of(Size size, double radius) {
    if (_cache.length > 8) _cache.clear();
    return _cache.putIfAbsent((size, radius), () => _Perimeter(size, radius));
  }
}

class _BorderPainter extends CustomPainter {
  _BorderPainter(this.vibe, this.clock, this.intro, this.radius)
    : super(repaint: Listenable.merge([clock, ?intro]));

  final DisciplineVibe vibe;
  final ValueNotifier<double> clock;
  final Animation<double>? intro;
  final double radius;

  List<Color> _colors(double t, double alpha) {
    final base = vibe.flowColors;
    return [
      for (final c in [...base, base.first]) c.withValues(alpha: alpha),
    ];
  }

  /// Lub-dub swell for heartbeat flows; 1 for everything else.
  double _pulse(double t) {
    if (!vibe.flow.heartbeat) return 1;
    final p = (t % 1.1) / 1.1;
    double bump(double at, double width) =>
        math.exp(-math.pow((p - at) / width, 2).toDouble());
    return .65 + .9 * (bump(.1, .04) + .6 * bump(.28, .05));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = clock.value;
    final pour = Curves.easeOutCubic.transform(intro?.value ?? 1);
    final flow = vibe.flow;
    final per = _Perimeter.of(size, radius);
    final n = _Perimeter.count;
    final rect = Offset.zero & size;
    final pulse = _pulse(t);
    final rotation = GradientRotation(t * flow.spin * math.pi * 2);

    // How much of the edge the pour has reached, as a share of half the loop.
    double reveal(int i) {
      if (pour >= 1) return 1;
      final steps = (i - per.top).abs();
      final dist = math.min(steps, n - steps) / (n / 2);
      return ((pour * 1.25 - dist) / .12).clamp(0.0, 1.0);
    }

    final reveals = [for (var i = 0; i < n; i++) reveal(i)];

    Path waterLine(int layer) {
      final path = Path();
      final speed = flow.speed * (1 + layer * .35);
      for (var i = 0; i < n; i++) {
        final u = i / n;
        final wave =
            .6 *
                math.sin(
                  math.pi * 2 * flow.waves * u + t * speed + layer * 1.7,
                ) +
            .4 *
                math.sin(
                  math.pi * 2 * (flow.waves * 2 + 1) * u -
                      t * speed * .8 +
                      layer,
                );
        final d =
            (flow.depth * (1 + layer * .7) +
                flow.amplitude * (1 - layer * .25) * pulse * (.5 + .5 * wave)) *
            reveals[i];
        final p = per.points[i] + per.normals[i] * d;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      return path..close();
    }

    Shader sweep(double alpha) => SweepGradient(
      colors: _colors(t, alpha),
      transform: rotation,
    ).createShader(rect);

    // Deepest, faintest layer first; the bright surface line last.
    const alphas = [.30, .17, .10];
    Path? surface;
    for (var layer = 2; layer >= 0; layer--) {
      final line = waterLine(layer);
      if (layer == 0) surface = line;
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(2))
          ..addPath(line, Offset.zero),
        Paint()..shader = sweep(alphas[layer]),
      );
    }
    canvas.drawPath(
      surface!,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = sweep(.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      surface,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = sweep(.9),
    );

    // Bright sparks riding the surface.
    if (flow.sparks > 0 && pour > .6) {
      final metric = surface.computeMetrics().first;
      for (var k = 0; k < flow.sparks; k++) {
        final along =
            ((t * .045 * flow.speed * (1 + k * .13)) + k / flow.sparks) % 1;
        final tan = metric.getTangentForOffset(metric.length * along);
        if (tan == null) continue;
        final color = vibe.flowColors[k % vibe.flowColors.length];
        canvas.drawCircle(
          tan.position,
          6,
          Paint()
            ..color = color.withValues(alpha: .55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawCircle(tan.position, 1.8, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_BorderPainter old) =>
      old.vibe != vibe || old.intro != intro || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Portal route
// ---------------------------------------------------------------------------

/// Opens a discipline page as a circle of its color growing out of the card
/// that was tapped. Falls back to a plain fade under reduced motion. Swipe
/// back from the left edge is handled by the page itself.
class DisciplinePortalRoute<T> extends PageRouteBuilder<T> {
  DisciplinePortalRoute({
    required WidgetBuilder builder,
    required this.origin,
    required this.color,
  }) : super(
         transitionDuration: const Duration(milliseconds: 620),
         reverseTransitionDuration: const Duration(milliseconds: 420),
         pageBuilder: (context, _, _) => builder(context),
       );

  /// Global position the circle grows from.
  final Offset origin;
  final Color color;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final grow = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final contentIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(.35, 1, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: grow,
      builder: (context, _) {
        final size = MediaQuery.sizeOf(context);
        final far = [
          Offset.zero,
          Offset(size.width, 0),
          Offset(0, size.height),
          Offset(size.width, size.height),
        ].map((c) => (c - origin).distance).reduce(math.max);
        return ClipPath(
          clipper: _CircleClipper(origin, far * grow.value),
          child: ColoredBox(
            color: color,
            child: FadeTransition(opacity: contentIn, child: child),
          ),
        );
      },
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.center != center || old.radius != radius;
}
