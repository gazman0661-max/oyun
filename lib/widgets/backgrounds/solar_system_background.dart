import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_colors.dart';
import 'shared_fx.dart';

/// gunes-sistemi.html: merkezde donen Gunes, etrafinda yorungede Merkur,
/// Venus, (Ay'i olan) Dunya ve Mars. Orijinal canvas mantiginin birebir
/// Dart/CustomPainter karsiligi.
class SolarSystemBackground extends StatefulWidget {
  final Widget? child;
  const SolarSystemBackground({super.key, this.child});

  @override
  State<SolarSystemBackground> createState() => _SolarSystemBackgroundState();
}

class _SolarSystemBackgroundState extends State<SolarSystemBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Random _rnd = Random();
  late final List<BgStar> _stars;

  // Yorunge fazlari (baslangicta rastgele, ardindan surekli ilerler).
  late double _sunRot;
  late double _earthOrbit, _earthRot;
  late double _moonOrbit;
  late double _mercuryOrbit, _venusOrbit, _marsOrbit;
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _stars = buildStars(_rnd, 220);
    _sunRot = 0;
    _earthOrbit = _rnd.nextDouble() * 2 * pi;
    _earthRot = 0;
    _moonOrbit = _rnd.nextDouble() * 2 * pi;
    _mercuryOrbit = _rnd.nextDouble() * 2 * pi;
    _venusOrbit = _rnd.nextDouble() * 2 * pi;
    _marsOrbit = _rnd.nextDouble() * 2 * pi;

    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      final dt = (t - _lastT).clamp(0.0, 0.05).toDouble();
      _lastT = t;
      _sunRot += dt * 0.09;
      _earthOrbit += dt * 0.36;
      _earthRot += dt * 2.4;
      _moonOrbit += dt * 2.7;
      _mercuryOrbit += dt * 0.72;
      _venusOrbit += dt * 0.48;
      _marsOrbit += dt * 0.24;
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
              painter: _SolarPainter(
                stars: _stars,
                t: _time.value,
                sunRot: _sunRot,
                earthOrbit: _earthOrbit,
                earthRot: _earthRot,
                moonOrbit: _moonOrbit,
                mercuryOrbit: _mercuryOrbit,
                venusOrbit: _venusOrbit,
                marsOrbit: _marsOrbit,
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

class _SolarPainter extends CustomPainter {
  final List<BgStar> stars;
  final double t;
  final double sunRot, earthOrbit, earthRot, moonOrbit;
  final double mercuryOrbit, venusOrbit, marsOrbit;

  _SolarPainter({
    required this.stars,
    required this.t,
    required this.sunRot,
    required this.earthOrbit,
    required this.earthRot,
    required this.moonOrbit,
    required this.mercuryOrbit,
    required this.venusOrbit,
    required this.marsOrbit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Once duz siyahti — "dunyanin etrafinda fazla siyahlik var" geri
    // bildirimi buradan geliyordu. Uygulamanin genelindeki derin uzay
    // gradyanina (spaceTop/Mid/Bottom) cevirip, gunesin etrafina yumusak
    // bir menekse/turuncu parilti ekleyerek bosluk hissini kirdik.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.spaceTop, AppColors.spaceMid, AppColors.spaceBottom],
        ).createShader(rect),
    );
    final ambientGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accentSoft.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.shortestSide * 0.75,
      ));
    canvas.drawRect(rect, ambientGlow);
    paintStars(canvas, size, stars, t);

    final cx = size.width / 2;
    final cy = size.height / 2;
    // Orijinal tasarim ~700px genislikte dusunulmus; ekrana oranla olcekle.
    final scale = (size.shortestSide / 480).clamp(0.55, 1.3).toDouble();

    _drawOrbit(canvas, cx, cy, 90 * scale);
    _drawOrbit(canvas, cx, cy, 140 * scale);
    _drawOrbit(canvas, cx, cy, 220 * scale);
    _drawOrbit(canvas, cx, cy, 290 * scale);

    _drawSimplePlanet(canvas, cx, cy, 90 * scale, mercuryOrbit, 5 * scale, const Color(0xFFB5A293));
    _drawSimplePlanet(canvas, cx, cy, 140 * scale, venusOrbit, 9 * scale, const Color(0xFFE8C27A));

    _drawSun(canvas, cx, cy, 45 * scale);

    final earthPos = _drawEarth(canvas, cx, cy, 220 * scale, 14 * scale);
    _drawMoon(canvas, earthPos, 38 * scale, 4 * scale);

    _drawSimplePlanet(canvas, cx, cy, 290 * scale, marsOrbit, 10 * scale, const Color(0xFFC1552C));
  }

  void _drawOrbit(Canvas canvas, double cx, double cy, double radius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(Offset(cx, cy), radius, paint);
  }

  Color _lighten(Color c, int amt) => shadeColor(c, amt);

  void _drawGlow(Canvas canvas, Offset p, double radius, Color inner, Color outer, double mult) {
    final paint = Paint()
      ..shader = RadialGradient(colors: [inner, outer, outer.withValues(alpha: 0)], stops: const [0.0, 0.4, 1.0])
          .createShader(Rect.fromCircle(center: p, radius: radius * mult));
    canvas.drawCircle(p, radius * mult, paint);
  }

  void _drawSun(Canvas canvas, double cx, double cy, double radius) {
    _drawGlow(canvas, Offset(cx, cy), radius, const Color(0x8CFFE696), const Color(0x40FFA03C), 3.2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(sunRot);
    final grad = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [Color(0xFFFFF8DC), Color(0xFFFFD35C), Color(0xFFFF9D1F)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, grad);

    final spotPaint = Paint()..color = const Color(0x59C85A14);
    for (var i = 0; i < 5; i++) {
      final a = (i / 5) * 2 * pi;
      final r = radius * 0.55;
      final sx = cos(a) * r;
      final sy = sin(a) * r * 0.6;
      canvas.save();
      canvas.translate(sx, sy);
      canvas.rotate(a);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: radius * 0.16, height: radius * 0.1),
        spotPaint,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  Offset _drawEarth(Canvas canvas, double cx, double cy, double orbitRadius, double radius) {
    final ex = cx + cos(earthOrbit) * orbitRadius;
    final ey = cy + sin(earthOrbit) * orbitRadius * 0.55;

    _drawGlow(canvas, Offset(ex, ey), radius, const Color(0x5964AAFF), const Color(0x1F508CFF), 2.2);

    canvas.save();
    canvas.translate(ex, ey);
    canvas.rotate(0.41);
    canvas.rotate(earthRot);

    final ocean = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [Color(0xFF5EA8FF), Color(0xFF1A4FA0)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, ocean);

    final landPaint = Paint()..color = const Color(0xE550A046);
    const continents = [
      (0.3, 0.5, 0.55, 0.35),
      (2.1, 0.4, 0.5, 0.45),
      (4.0, 0.55, 0.4, 0.3),
      (5.2, 0.35, 0.45, 0.4),
    ];
    for (final c in continents) {
      final px = cos(c.$1) * radius * c.$2;
      final py = sin(c.$1) * radius * c.$2;
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(c.$1);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: radius * c.$3 * 0.8, height: radius * c.$4 * 0.8),
        landPaint,
      );
      canvas.restore();
    }
    canvas.restore();

    return Offset(ex, ey);
  }

  void _drawMoon(Canvas canvas, Offset earthPos, double orbitRadius, double radius) {
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawOval(
      Rect.fromCenter(
        center: earthPos,
        width: orbitRadius * 2,
        height: orbitRadius * 2 * 0.7,
      ),
      orbitPaint,
    );

    final mx = earthPos.dx + cos(moonOrbit) * orbitRadius;
    final my = earthPos.dy + sin(moonOrbit) * orbitRadius * 0.7;

    canvas.save();
    canvas.translate(mx, my);
    canvas.rotate(moonOrbit);
    final moonGrad = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [Color(0xFFE8E6E0), Color(0xFF9A978F)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, moonGrad);

    final craterPaint = Paint()..color = const Color(0x99787670);
    const craters = [(-0.3, -0.2, 0.18), (0.2, 0.3, 0.15), (0.35, -0.15, 0.12)];
    for (final c in craters) {
      canvas.drawCircle(Offset(c.$1 * radius, c.$2 * radius), c.$3 * radius, craterPaint);
    }
    canvas.restore();
  }

  Offset _drawSimplePlanet(
    Canvas canvas,
    double cx,
    double cy,
    double orbitRadius,
    double orbitAngle,
    double radius,
    Color color,
  ) {
    final x = cx + cos(orbitAngle) * orbitRadius;
    final y = cy + sin(orbitAngle) * orbitRadius * 0.55;
    final grad = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [_lighten(color, 40), color],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius));
    canvas.drawCircle(Offset(x, y), radius, grad);
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _SolarPainter oldDelegate) => true;
}
