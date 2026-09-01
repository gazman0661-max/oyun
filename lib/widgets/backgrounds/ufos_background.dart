import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'shared_fx.dart';

/// ufolar.html: yildiz alani + kayan yildizlar + 2 dekor gezegen + soldan
/// saga ucan, hafifce inip-kalkan (bob), isik huzmeli ve kenar isiklari
/// yanip sonen UFO'lar. Buyuk tip (A) kubbe icinde el sallayan/goz kirpan
/// bir uzayli icerir; kucuk tip (B) sade/uzak bir disktir.
class UfosBackground extends StatefulWidget {
  final Widget? child;
  const UfosBackground({super.key, this.child});

  @override
  State<UfosBackground> createState() => _UfosBackgroundState();
}

class _UfosBackgroundState extends State<UfosBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Random _rnd = Random();
  late final List<BgStar> _stars;
  late final List<_Ufo> _ufos;
  final List<BgShootingStar> _shooting = [];
  double _nextShootAt = 2;
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _stars = buildStars(_rnd, 180);
    _ufos = List.generate(3, (i) => _Ufo.random(_rnd, i));
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
              painter: _UfosPainter(
                stars: _stars,
                ufos: _ufos,
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

enum _UfoType { big, small }

class _Ufo {
  final _UfoType type;
  final double scale, topRel, duration, delay, tilt, drift, bobPhase;
  _Ufo({
    required this.type,
    required this.scale,
    required this.topRel,
    required this.duration,
    required this.delay,
    required this.tilt,
    required this.drift,
    required this.bobPhase,
  });

  factory _Ufo.random(Random r, int i) {
    final type = i.isEven ? _UfoType.big : _UfoType.small;
    return _Ufo(
      type: type,
      scale: r.nextDouble() * 0.4 + 0.65,
      topRel: r.nextDouble() * 0.65 + 0.08,
      duration: r.nextDouble() * 14 + 18,
      delay: r.nextDouble() * -26,
      tilt: (r.nextDouble() * 6 - 3) * pi / 180,
      drift: r.nextDouble() * 90 - 45,
      bobPhase: r.nextDouble() * 2 * pi,
    );
  }
}

class _UfosPainter extends CustomPainter {
  final List<BgStar> stars;
  final List<_Ufo> ufos;
  final List<BgShootingStar> shooting;
  final double t;

  _UfosPainter({required this.stars, required this.ufos, required this.shooting, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    paintSpaceBase(canvas, Offset.zero & size, violet: false);
    paintStars(canvas, size, stars, t);
    paintShootingStars(canvas, size, shooting);

    paintSimpleDecorPlanet(canvas, Offset(size.width * 0.82, size.height * 0.08),
        size.width * 0.22, const Color(0xFF7A4A9D), const Color(0xFF2A1440));
    paintSimpleDecorPlanet(canvas, Offset(size.width * 0.08, size.height * 0.60),
        size.width * 0.11, const Color(0xFF5DA8D1), const Color(0xFF123049));

    for (final u in ufos) {
      _paintUfo(canvas, size, u);
    }
  }

  void _paintUfo(Canvas canvas, Size size, _Ufo u) {
    final raw = t - u.delay;
    if (raw < 0) return;
    final frac = (raw % u.duration) / u.duration;

    final travel = size.width + 320;
    final x = -260 * u.scale + frac * travel;
    final bob = sin(t * (2 * pi / 2.6) + u.bobPhase) * 8;
    final y = size.height * u.topRel + frac * u.drift + bob;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(u.tilt);
    canvas.scale(u.scale);

    if (u.type == _UfoType.big) {
      _paintUfoA(canvas);
    } else {
      _paintUfoB(canvas);
    }
    canvas.restore();
  }

  void _rimLights(Canvas canvas, List<Offset> positions, List<Color> colors, double r) {
    for (var i = 0; i < positions.length; i++) {
      final blink = 0.45 + 0.55 * ((sin(t * 4.5 + i * 0.9) + 1) / 2);
      canvas.drawCircle(positions[i], r, Paint()..color = colors[i % colors.length].withValues(alpha: blink.clamp(0.0, 1.0).toDouble()));
    }
  }

  void _beam(Canvas canvas, double halfTopW, double halfBotW, double topY, double botY, double opacityBase) {
    final pulse = (0.25 + 0.25 * ((sin(t * (2 * pi / 2.2)) + 1) / 2)).clamp(0.0, 1.0).toDouble();
    final path = Path()
      ..moveTo(-halfTopW, topY)
      ..lineTo(halfTopW, topY)
      ..lineTo(halfBotW, botY)
      ..lineTo(-halfBotW, botY)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          colors: [
            const Color(0xFFEAFFB0).withValues(alpha: pulse * opacityBase),
            const Color(0xFFC8FFB0).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTRB(-halfBotW, topY, halfBotW, botY)),
    );
  }

  void _paintUfoA(Canvas canvas) {
    _beam(canvas, 30, 82, 30, 150, 1.0);

    canvas.drawOval(const Rect.fromLTWH(-80, 35, 160, 18), Paint()..color = const Color(0x40000000));

    canvas.drawOval(
      const Rect.fromLTWH(-96, -6, 192, 48),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3F4F6), Color(0xFF8F939B), Color(0xFF5A5D64)],
        ).createShader(const Rect.fromLTWH(-96, -6, 192, 48)),
    );
    canvas.drawOval(const Rect.fromLTWH(-96, -6, 192, 48),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF3A3D44));

    canvas.drawOval(
      const Rect.fromLTWH(-64, -9, 128, 30),
      Paint()..shader = const LinearGradient(colors: [Color(0xFFD5D8DD), Color(0xFF7A7D85)]).createShader(const Rect.fromLTWH(-64, -9, 128, 30)),
    );

    _rimLights(
      canvas,
      const [
        Offset(-78, 18),
        Offset(-52, 27),
        Offset(-18, 32),
        Offset(18, 32),
        Offset(52, 27),
        Offset(78, 18),
      ],
      const [Color(0xFFFFD23F), Color(0xFFFF4D4D), Color(0xFF3FA9FF)],
      5,
    );

    final dome = Path()
      ..moveTo(-38, -6)
      ..cubicTo(-38, -34, 38, -34, 38, -6)
      ..cubicTo(38, 4, -38, 4, -38, -6)
      ..close();
    canvas.drawPath(dome, Paint()..color = const Color(0xFF8FD9F2).withValues(alpha: 0.55));
    canvas.drawPath(dome, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF2A5A6B));
    canvas.drawOval(const Rect.fromLTWH(-26, -26, 20, 12), Paint()..color = Colors.white.withValues(alpha: 0.5));

    _paintAlien(canvas);
  }

  void _paintAlien(Canvas canvas) {
    final wave = sin(t * (2 * pi / 1.6));
    final waveAngle = (wave > 0 ? wave * 18 : wave * 6) * pi / 180;

    final antennaPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF3D7A3D);
    canvas.drawLine(const Offset(-8, -30), const Offset(-12, -40), antennaPaint);
    canvas.drawLine(const Offset(8, -30), const Offset(12, -40), antennaPaint);
    canvas.drawCircle(const Offset(-12, -41), 2.2, Paint()..color = const Color(0xFF7EE06A));
    canvas.drawCircle(const Offset(12, -41), 2.2, Paint()..color = const Color(0xFF7EE06A));

    final head = Path()
      ..moveTo(-18, -28)
      ..cubicTo(-18, -12, -12, -2, 0, -2)
      ..cubicTo(12, -2, 18, -12, 18, -28)
      ..cubicTo(18, -36, 10, -32, 0, -32)
      ..cubicTo(-10, -32, -18, -36, -18, -28)
      ..close();
    canvas.drawPath(head, Paint()..color = const Color(0xFF8FE06A));
    canvas.drawPath(head, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0xFF3D7A3D));

    final blink = ((sin(t * (2 * pi / 3.5)) + 1) / 2) > 0.97 ? 0.15 : 1.0;
    for (final ex in [-8.0, 8.0]) {
      canvas.save();
      canvas.translate(ex, -20);
      canvas.scale(1, blink);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 9, height: 12), Paint()..color = const Color(0xFF1A1A1A));
      canvas.restore();
    }
    canvas.drawOval(const Rect.fromLTWH(-10.6, -24.1, 2.6, 3.2), Paint()..color = Colors.white.withValues(alpha: 0.85));
    canvas.drawOval(const Rect.fromLTWH(5.4, -24.1, 2.6, 3.2), Paint()..color = Colors.white.withValues(alpha: 0.85));

    final body = Path()
      ..moveTo(-13, -2)
      ..cubicTo(-13, 8, -8, 14, 0, 14)
      ..cubicTo(8, 14, 13, 8, 13, -2)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFFF9D3D));
    canvas.drawPath(body, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.3..color = const Color(0xFF7A4400));
    canvas.drawCircle(const Offset(0, 6), 2.6, Paint()..color = const Color(0xFF3FA9FF));

    canvas.save();
    canvas.translate(14, -1);
    canvas.rotate(waveAngle);
    canvas.drawOval(Rect.fromCenter(center: const Offset(3, -3), width: 8, height: 11),
        Paint()..color = const Color(0xFF8FE06A));
    canvas.restore();
  }

  void _paintUfoB(Canvas canvas) {
    _beam(canvas, 18, 48, 18, 88, 0.55);

    canvas.drawOval(const Rect.fromLTWH(-48, 21, 96, 6), Paint()..color = const Color(0x38000000));

    canvas.drawOval(
      const Rect.fromLTWH(-58, -3, 116, 28),
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3F4F6), Color(0xFF5A5D64)]).createShader(const Rect.fromLTWH(-58, -3, 116, 28)),
    );
    canvas.drawOval(const Rect.fromLTWH(-58, -3, 116, 28),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = const Color(0xFF3A3D44));

    _rimLights(
      canvas,
      const [Offset(-46, 10), Offset(-16, 17), Offset(16, 17), Offset(46, 10)],
      const [Color(0xFFFFD23F), Color(0xFFFF4D4D), Color(0xFF3FA9FF), Color(0xFFFFD23F)],
      3,
    );

    final dome = Path()
      ..moveTo(-22, -4)
      ..cubicTo(-22, -20, 22, -20, 22, -4)
      ..cubicTo(22, 2, -22, 2, -22, -4)
      ..close();
    canvas.drawPath(dome, Paint()..color = const Color(0xFF8FD9F2).withValues(alpha: 0.55));
    canvas.drawPath(dome, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = const Color(0xFF2A5A6B));
    canvas.drawOval(const Rect.fromLTWH(-14, -14, 12, 7), Paint()..color = Colors.white.withValues(alpha: 0.5));
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, -8), width: 14, height: 18),
        Paint()..color = const Color(0xFF6FCE55).withValues(alpha: 0.65));
  }

  @override
  bool shouldRepaint(covariant _UfosPainter oldDelegate) => true;
}
