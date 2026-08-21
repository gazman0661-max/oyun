import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'shared_fx.dart';

/// uzay-gemileri.html: yildiz alani + kayan yildizlar + 2 dekor gezegen +
/// soldan saga surekli ucan 3 farkli gemi silueti (kruvazor/avci/kesif),
/// motor alevi titremesi ve yanip sonen navigasyon isiklariyla.
class SpaceshipsBackground extends StatefulWidget {
  final Widget? child;
  const SpaceshipsBackground({super.key, this.child});

  @override
  State<SpaceshipsBackground> createState() => _SpaceshipsBackgroundState();
}

class _SpaceshipsBackgroundState extends State<SpaceshipsBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Random _rnd = Random();
  late final List<BgStar> _stars;
  late final List<_Ship> _ships;
  final List<BgShootingStar> _shooting = [];
  double _nextShootAt = 2;
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _stars = buildStars(_rnd, 200);
    _ships = List.generate(3, (i) => _Ship.random(_rnd, i));
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      final dt = (t - _lastT).clamp(0.0, 0.05).toDouble();
      _lastT = t;
      for (var i = _shooting.length - 1; i >= 0; i--) {
        _shooting[i].update(dt);
        if (_shooting[i].isDead) _shooting.removeAt(i);
      }
      if (t >= _nextShootAt && _shooting.length < 2) {
        _shooting.add(BgShootingStar.spawn(_rnd));
        _nextShootAt = t + 3 + _rnd.nextDouble() * 4;
      }
      _time.value = t;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _time,
            builder: (context, _) => CustomPaint(
              painter: _ShipsPainter(
                stars: _stars,
                ships: _ships,
                shooting: List.unmodifiable(_shooting),
                t: _time.value,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

enum _ShipType { cruiser, fighter, scout }

class _Ship {
  final _ShipType type;
  final double scale, topRel, duration, delay, tilt, drift;
  _Ship({
    required this.type,
    required this.scale,
    required this.topRel,
    required this.duration,
    required this.delay,
    required this.tilt,
    required this.drift,
  });

  factory _Ship.random(Random r, int i) {
    final type = _ShipType.values[i % _ShipType.values.length];
    return _Ship(
      type: type,
      scale: r.nextDouble() * 0.5 + 0.7,
      topRel: r.nextDouble() * 0.7 + 0.08,
      duration: r.nextDouble() * 12 + 16,
      delay: r.nextDouble() * -24,
      tilt: (r.nextDouble() * 8 - 4) * pi / 180,
      drift: r.nextDouble() * 100 - 50,
    );
  }
}

class _ShipsPainter extends CustomPainter {
  final List<BgStar> stars;
  final List<_Ship> ships;
  final List<BgShootingStar> shooting;
  final double t;

  _ShipsPainter({required this.stars, required this.ships, required this.shooting, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.5),
          radius: 1.1,
          colors: [Color(0xFF0C1236), Color(0xFF05060F), Color(0xFF000000)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    paintStars(canvas, size, stars, t);
    paintShootingStars(canvas, size, shooting);

    paintSimpleDecorPlanet(canvas, Offset(size.width * 0.85, size.height * 0.10),
        size.width * 0.24, const Color(0xFF7A4A9D), const Color(0xFF2A1440));
    paintSimpleDecorPlanet(canvas, Offset(size.width * 0.10, size.height * 0.66),
        size.width * 0.12, const Color(0xFF5DA8D1), const Color(0xFF123049));

    for (final ship in ships) {
      _paintShip(canvas, size, ship);
    }
  }

  void _paintShip(Canvas canvas, Size size, _Ship s) {
    final raw = t - s.delay;
    if (raw < 0) return;
    final frac = (raw % s.duration) / s.duration;

    final travel = size.width + 420;
    final x = -260 * s.scale + frac * travel;
    final y = size.height * s.topRel + frac * s.drift;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(s.tilt);
    canvas.scale(s.scale);

    switch (s.type) {
      case _ShipType.cruiser:
        _paintCruiser(canvas);
        break;
      case _ShipType.fighter:
        _paintFighter(canvas);
        break;
      case _ShipType.scout:
        _paintScout(canvas);
        break;
    }
    canvas.restore();
  }

  void _navLight(Canvas canvas, Offset p, double r, Color c, double phase) {
    final blink = 0.4 + 0.6 * ((sin(t * 2.6 + phase) + 1) / 2 > 0.75 ? 1.0 : 0.45);
    canvas.drawCircle(p, r, Paint()..color = c.withValues(alpha: blink.clamp(0.0, 1.0).toDouble()));
  }

  void _engineGlow(Canvas canvas, Offset p, double rx, double ry, Color inner, Color outer, double phase) {
    final flick = 0.85 + 0.3 * sin(t * 26 + phase);
    final paint = Paint()
      ..shader = RadialGradient(colors: [inner, outer, outer.withValues(alpha: 0)], stops: const [0.0, 0.55, 1.0])
          .createShader(Rect.fromCenter(center: p, width: rx * 2.4 * flick, height: ry * 2.4 * flick));
    canvas.drawOval(
      Rect.fromCenter(center: p, width: rx * 2.4 * flick, height: ry * 2.4 * flick),
      paint,
    );
  }

  void _paintCruiser(Canvas canvas) {
    _engineGlow(canvas, const Offset(-24, -14), 30, 9, Colors.white, const Color(0xFF3F8DFF), 0);
    _engineGlow(canvas, const Offset(-26, 0), 36, 11, Colors.white, const Color(0xFF3F8DFF), 1.1);
    _engineGlow(canvas, const Offset(-24, 14), 30, 9, Colors.white, const Color(0xFF3F8DFF), 2.2);

    final hull = Path()
      ..moveTo(40, -22)
      ..cubicTo(70, -30, 130, -32, 190, -24)
      ..cubicTo(230, -19, 258, -12, 268, -3)
      ..lineTo(268, 3)
      ..cubicTo(258, 12, 230, 19, 190, 24)
      ..cubicTo(130, 32, 70, 30, 40, 22)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDFE4EC), Color(0xFF767E90), Color(0xFF1E2129)],
        ).createShader(const Rect.fromLTWH(40, -32, 228, 64)),
    );
    canvas.drawPath(hull, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.3..color = const Color(0xFF14161C));

    final nose = Path()
      ..moveTo(4, -26)
      ..lineTo(44, -22)
      ..lineTo(44, 22)
      ..lineTo(4, 26)
      ..close();
    canvas.drawPath(nose,
        Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFDFE4EC), Color(0xFF1E2129)]).createShader(const Rect.fromLTWH(4, -26, 40, 52)));

    final cockpit = Path()
      ..moveTo(220, -10)
      ..cubicTo(240, -13, 256, -9, 262, -2)
      ..lineTo(262, 2)
      ..cubicTo(256, 9, 240, 13, 220, 10)
      ..close();
    canvas.drawPath(cockpit, Paint()..color = const Color(0xFF6FD0FF));
    canvas.drawPath(cockpit, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0xFF062033));

    _navLight(canvas, const Offset(150, -28), 1.8, const Color(0xFFFF3B3B), 0);
    _navLight(canvas, const Offset(150, 28), 1.8, const Color(0xFF39FF6A), 1.2);
    _navLight(canvas, const Offset(264, 0), 1.6, Colors.white, 0.6);
  }

  void _paintFighter(Canvas canvas) {
    _engineGlow(canvas, const Offset(-30, -46), 12, 5, Colors.white, const Color(0xFFFF7A2F), 0);
    _engineGlow(canvas, const Offset(-30, 46), 12, 5, Colors.white, const Color(0xFFFF7A2F), 1.5);
    _engineGlow(canvas, const Offset(-14, 0), 22, 7, Colors.white, const Color(0xFFFF7A2F), 0.8);

    final wingPaint = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF7D8494), Color(0xFF15161C)])
          .createShader(const Rect.fromLTWH(-30, -50, 64, 100));
    canvas.drawPath(
      Path()..moveTo(20, -4)..lineTo(-30, -46)..lineTo(-14, -50)..lineTo(34, -8)..close(),
      wingPaint,
    );
    canvas.drawPath(
      Path()..moveTo(20, 4)..lineTo(-30, 46)..lineTo(-14, 50)..lineTo(34, 8)..close(),
      wingPaint,
    );

    final hull = Path()
      ..moveTo(8, 0)
      ..cubicTo(16, -10, 46, -13, 78, -8)
      ..cubicTo(100, -5, 118, -2, 128, 0)
      ..cubicTo(118, 2, 100, 5, 78, 8)
      ..cubicTo(46, 13, 16, 10, 8, 0)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEEF1F6), Color(0xFF565D6F), Color(0xFF1C1E26)],
        ).createShader(const Rect.fromLTWH(8, -13, 120, 26)),
    );
    canvas.drawPath(hull, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.1..color = const Color(0xFF101218));

    final cockpit = Path()
      ..moveTo(60, -7)
      ..cubicTo(74, -9, 86, -6, 92, -1)
      ..lineTo(92, 1)
      ..cubicTo(86, 6, 74, 9, 60, 7)
      ..close();
    canvas.drawPath(cockpit, Paint()..color = const Color(0xFF6FD0FF));

    _navLight(canvas, const Offset(35, -11), 1.4, const Color(0xFFFF3B3B), 0);
    _navLight(canvas, const Offset(35, 11), 1.4, const Color(0xFF39FF6A), 1);
  }

  void _paintScout(Canvas canvas) {
    _engineGlow(canvas, const Offset(-4, 20), 20, 7, Colors.white, const Color(0xFF3F8DFF), 0);
    _engineGlow(canvas, const Offset(4, 20), 14, 5, Colors.white, const Color(0xFF3F8DFF), 1.4);

    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 144, height: 40),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.15, -0.4),
          colors: [Color(0xFFEEF1F6), Color(0xFF565C6D), Color(0xFF24272F)],
          stops: [0.0, 0.6, 1.0],
        ).createShader(const Rect.fromLTWH(-72, -20, 144, 40)),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 144, height: 40),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.3..color = const Color(0xFF1A1C22),
    );

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -4), width: 56, height: 32),
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFF8E0), Color(0xFFFFDB7A), Color(0xFF7A5300)], stops: [0.0, 0.55, 1.0])
            .createShader(const Rect.fromLTWH(-28, -20, 56, 32)),
    );

    _navLight(canvas, const Offset(-58, 2), 1.8, const Color(0xFFFF3B3B), 0);
    _navLight(canvas, const Offset(58, 2), 1.8, const Color(0xFF39FF6A), 1.4);
  }

  @override
  bool shouldRepaint(covariant _ShipsPainter oldDelegate) => true;
}
