import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'shared_fx.dart';

/// meteor-yagmuru.html: yildiz alani + sol-ustte Mars, sag-altta Venus
/// (ikisi de dokulu/atmosferli, kismen kadraj disinda) + capraz dusen,
/// alevli-kivilcimli meteor yagmuru. Tamamen Canvas ile vektorel.
class MeteorShowerBackground extends StatefulWidget {
  final Widget? child;
  const MeteorShowerBackground({super.key, this.child});

  @override
  State<MeteorShowerBackground> createState() => _MeteorShowerBackgroundState();
}

class _MeteorShowerBackgroundState extends State<MeteorShowerBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Random _rnd = Random();
  late final List<BgStar> _stars;
  late final List<_Meteor> _meteors;

  @override
  void initState() {
    super.initState();
    _stars = buildStars(_rnd, 140);
    _meteors = List.generate(9, (_) => _Meteor.random(_rnd));
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1e6;
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
              painter: _MeteorPainter(stars: _stars, meteors: _meteors, t: _time.value),
              size: Size.infinite,
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _Meteor {
  final double startXRel, startYRel, len, thickness, duration, delay;
  _Meteor({
    required this.startXRel,
    required this.startYRel,
    required this.len,
    required this.thickness,
    required this.duration,
    required this.delay,
  });

  factory _Meteor.random(Random r) => _Meteor(
        startXRel: r.nextDouble() * 1.4 - 0.2,
        startYRel: -(r.nextDouble() * 0.25 + 0.04),
        len: r.nextDouble() * 70 + 55,
        thickness: r.nextDouble() * 1.4 + 1.1,
        duration: r.nextDouble() * 2 + 1.6,
        delay: r.nextDouble() * 14,
      );
}

class _MeteorPainter extends CustomPainter {
  final List<BgStar> stars;
  final List<_Meteor> meteors;
  final double t;
  static const double _angleDeg = 34;

  _MeteorPainter({required this.stars, required this.meteors, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    paintSpaceBase(canvas, rect);
    paintStars(canvas, size, stars, t);

    paintSimpleDecorPlanet(
      canvas,
      Offset(size.width * 0.18, size.height * 0.72),
      size.width * 0.06,
      const Color(0xFF8FB8D8),
      const Color(0xFF1C3A52),
    );

    _paintMars(canvas, size, Offset(size.width * 0.06, size.height * 0.08), size.width * 0.34);
    _paintVenus(canvas, size, Offset(size.width * 0.95, size.height * 0.88), size.width * 0.32);

    for (final m in meteors) {
      _paintMeteor(canvas, size, m);
    }
  }

  void _paintMeteor(Canvas canvas, Size size, _Meteor m) {
    final localRaw = t - m.delay;
    if (localRaw < 0) return;
    final frac = (localRaw % m.duration) / m.duration;

    double opacity;
    if (frac < 0.04) {
      opacity = frac / 0.04;
    } else if (frac < 0.70) {
      opacity = 1;
    } else if (frac < 0.92) {
      opacity = 1 - (frac - 0.70) / 0.22;
    } else {
      opacity = 0;
    }
    if (opacity <= 0.01) return;

    final posT = 1 - pow(1 - frac, 3).toDouble();
    const rad = _angleDeg * pi / 180;
    final dist = size.height + 300;
    final dx = sin(rad) * dist * posT;
    final dy = cos(rad) * dist * posT;

    final start = Offset(m.startXRel * size.width, m.startYRel * size.height);
    final pos = start + Offset(dx, dy);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rad);

    final tailPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = m.thickness * 2.6
      ..shader = LinearGradient(colors: [
        Colors.white.withValues(alpha: 0),
        const Color(0xFFBFE3FF).withValues(alpha: 0.5 * opacity),
        Colors.white.withValues(alpha: 0.95 * opacity),
      ], stops: const [
        0.0,
        0.6,
        1.0
      ]).createShader(Rect.fromLTWH(-m.len, -4, m.len, 8));
    canvas.drawLine(Offset(-m.len, 0), Offset.zero, tailPaint);

    final flicker = 0.85 + 0.15 * sin(t * 22 + m.len);
    final headGlow = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: opacity),
        const Color(0xFFFF9A2F).withValues(alpha: 0.5 * opacity),
        const Color(0xFFFF9A2F).withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: m.thickness * 3.2 * flicker));
    canvas.drawCircle(Offset.zero, m.thickness * 3.2 * flicker, headGlow);
    canvas.drawCircle(Offset.zero, m.thickness * 1.2, Paint()..color = Colors.white.withValues(alpha: opacity));

    for (var i = 0; i < 3; i++) {
      final sf = ((t * 1.7 + i * 0.33 + m.len * 0.01) % 1.0);
      final sx = -m.len * (0.2 + sf * 0.6);
      final sOpacity = (1 - sf) * opacity * 0.8;
      if (sOpacity <= 0.02) continue;
      canvas.drawCircle(
        Offset(sx, sin(sf * 6 + i) * 2.5),
        m.thickness * 0.6 * (1 - sf * 0.6),
        Paint()..color = (i.isEven ? const Color(0xFFFFCF5F) : const Color(0xFFFF9A2F)).withValues(alpha: sOpacity),
      );
    }

    canvas.restore();
  }

  void _paintMars(Canvas canvas, Size size, Offset center, double radius) {
    final atmo = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFFF8A5C).withValues(alpha: 0.25),
        const Color(0xFFFF8A5C).withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: center, radius: radius * 1.15));
    canvas.drawCircle(center, radius * 1.15, atmo);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    final base = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.25, -0.3),
        colors: [Color(0xFFE8A06A), Color(0xFFC9704A), Color(0xFF8A3D2A), Color(0xFF3D1810)],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, base);

    final craterPaint = Paint()..color = const Color(0x8C5A2214);
    const craterOffsets = [
      Offset(-0.15, -0.15),
      Offset(0.15, -0.2),
      Offset(0.05, 0.1),
      Offset(-0.2, 0.15),
      Offset(0.25, 0.05),
    ];
    for (var i = 0; i < craterOffsets.length; i++) {
      final o = craterOffsets[i];
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(o.dx * radius * 2, o.dy * radius * 2),
          width: radius * (0.14 + (i % 2) * 0.05) * 2,
          height: radius * (0.1 + (i % 2) * 0.03) * 2,
        ),
        craterPaint,
      );
    }

    final capOpacity = (0.85 + 0.15 * sin(t * (2 * pi / 5))).clamp(0.0, 1.0).toDouble();
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-radius * 0.15, -radius * 0.76),
        width: radius * 0.42,
        height: radius * 0.22,
      ),
      Paint()..color = const Color(0xFFFBE9E2).withValues(alpha: capOpacity),
    );

    final shadow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.35),
        colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.78)],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shadow);
    canvas.restore();
  }

  void _paintVenus(Canvas canvas, Size size, Offset center, double radius) {
    final atmo = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFFFE9A8).withValues(alpha: 0.35),
        const Color(0xFFFFE9A8).withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: center, radius: radius * 1.15));
    canvas.drawCircle(center, radius * 1.15, atmo);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    final base = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.35),
        colors: [Color(0xFFFFF3D6), Color(0xFFF0D59A), Color(0xFFC9A463), Color(0xFF6E4F2A)],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, base);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(t * 0.03);
    canvas.translate(-center.dx, -center.dy);
    final cloudPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final bands = [
      (-0.35, const Color(0xFFFFF6DF), 0.2, 0.05),
      (0.1, const Color(0xFFD9B46A), 0.25, 0.06),
      (0.35, const Color(0xFFFFF6DF), 0.17, 0.04),
      (-0.08, const Color(0xFFD9B46A), 0.18, 0.045),
    ];
    for (final band in bands) {
      final y = center.dy + band.$1 * radius;
      final path = Path()
        ..moveTo(center.dx - radius * 0.9, y)
        ..quadraticBezierTo(center.dx, y - radius * 0.14, center.dx + radius * 0.9, y);
      cloudPaint
        ..color = band.$2.withValues(alpha: band.$3)
        ..strokeWidth = radius * band.$4;
      canvas.drawPath(path, cloudPaint);
    }
    canvas.restore();

    final shadow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.45, 0.4),
        colors: [Colors.black.withValues(alpha: 0), const Color(0xFF2A1A00).withValues(alpha: 0.75)],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shadow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MeteorPainter oldDelegate) => true;
}
