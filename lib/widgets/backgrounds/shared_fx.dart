import 'dart:math';

import 'package:flutter/material.dart';

// meteor-yagmuru.html / uzay-gemileri.html / ufolar.html prototiplerindeki
// ortak ".star" / ".shooting-star" / ".planet" ogelerinin, 4 arkaplan
// animasyonu arasinda paylasilan Dart/CustomPainter karsiligi.

class BgStar {
  final double dx, dy, size, phase, speed;
  BgStar({
    required this.dx,
    required this.dy,
    required this.size,
    required this.phase,
    required this.speed,
  });

  factory BgStar.random(Random r) => BgStar(
        dx: r.nextDouble(),
        dy: r.nextDouble(),
        size: r.nextDouble() * 1.6 + 0.4,
        phase: r.nextDouble() * 2 * pi,
        speed: 0.5 + r.nextDouble() * 1.5,
      );
}

List<BgStar> buildStars(Random r, int count) =>
    List.generate(count, (_) => BgStar.random(r));

void paintStars(Canvas canvas, Size size, List<BgStar> stars, double t) {
  final paint = Paint()..style = PaintingStyle.fill;
  for (final s in stars) {
    final twinkle = 0.5 + 0.5 * sin(t * s.speed + s.phase);
    paint.color = Colors.white.withValues(alpha: (0.15 + twinkle * 0.85).clamp(0.0, 1.0).toDouble());
    final r = s.size * (0.8 + twinkle * 0.4);
    canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), r, paint);
  }
}

/// HTML'deki .shooting-star ile ayni fikir: capraz asagi dogru kisa,
/// parlak bir iz birakip sonen nokta; belirli araliklarla yeniden dogar.
class BgShootingStar {
  double x, y; // normalize (0..1)
  final double vx, vy; // normalize / saniye
  double life; // 1 -> 0
  final List<Offset> trail = [];

  BgShootingStar({required this.x, required this.y, required this.vx, required this.vy})
      : life = 1;

  bool get isDead => life <= 0;

  factory BgShootingStar.spawn(Random r) {
    final startX = r.nextDouble() * 0.7 + 0.2;
    final startY = r.nextDouble() * 0.35;
    final speed = 0.5 + r.nextDouble() * 0.35;
    const angle = 0.45; // asagi-saga egik (radyan)
    return BgShootingStar(
      x: startX,
      y: startY,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
    );
  }

  void update(double dt) {
    trail.add(Offset(x, y));
    if (trail.length > 10) trail.removeAt(0);
    x += vx * dt;
    y += vy * dt;
    life -= dt * 0.9;
  }
}

void paintShootingStars(Canvas canvas, Size size, List<BgShootingStar> list) {
  for (final s in list) {
    if (s.trail.length < 2) continue;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < s.trail.length - 1; i++) {
      final p1 = Offset(s.trail[i].dx * size.width, s.trail[i].dy * size.height);
      final p2 = Offset(s.trail[i + 1].dx * size.width, s.trail[i + 1].dy * size.height);
      final frac = i / s.trail.length;
      paint
        ..color = Colors.white.withValues(alpha: (frac * s.life).clamp(0.0, 1.0).toDouble())
        ..strokeWidth = 1.6 * frac;
      canvas.drawLine(p1, p2, paint);
    }
    final head = Offset(s.x * size.width, s.y * size.height);
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: s.life.clamp(0.0, 1.0).toDouble()),
        Colors.white.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: head, radius: 5));
    canvas.drawCircle(head, 5, glow);
  }
}

/// Uzak/basit dekor gezegen (ufolar.html / uzay-gemileri.html'deki .planet
/// div'i: radial-gradient(circle at 35% 30%, c1, c2 75%) + hafif isilti).
void paintSimpleDecorPlanet(Canvas canvas, Offset center, double radius, Color c1, Color c2) {
  final glow = Paint()
    ..color = Colors.white.withValues(alpha: 0.05)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
  canvas.drawCircle(center, radius * 1.2, glow);
  final grad = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      colors: [c1, c2],
      stops: const [0.0, 0.9],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  canvas.drawCircle(center, radius, grad);
}

Color shadeColor(Color c, int amt) {
  int ch(int v) => (v + amt).clamp(0, 255).toInt();
  return Color.fromARGB(
    255,
    ch((c.r * 255.0).round().clamp(0, 255)),
    ch((c.g * 255.0).round().clamp(0, 255)),
    ch((c.b * 255.0).round().clamp(0, 255)),
  );
}

/// Arkaplan sahnelerinin ortak koyu-lacivert/derin-uzay zemin gradyani
/// (her HTML dosyasinin body { background: radial-gradient(...) } kismi).
void paintSpaceBase(Canvas canvas, Rect rect, {bool violet = true}) {
  final base = Paint()
    ..shader = const RadialGradient(
      center: Alignment(0, -0.4),
      radius: 1.1,
      colors: [Color(0xFF0C1236), Color(0xFF05060F), Color(0xFF000000)],
      stops: [0.0, 0.55, 1.0],
    ).createShader(rect);
  canvas.drawRect(rect, base);
  if (violet) {
    final blob1 = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF5A2878).withValues(alpha: 0.25),
        const Color(0xFF5A2878).withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(
          center: Offset(rect.width * 0.15, rect.height * 0.2), radius: rect.width * 0.5));
    canvas.drawCircle(Offset(rect.width * 0.15, rect.height * 0.2), rect.width * 0.5, blob1);
    final blob2 = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF1E4678).withValues(alpha: 0.22),
        const Color(0xFF1E4678).withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(
          center: Offset(rect.width * 0.85, rect.height * 0.7), radius: rect.width * 0.5));
    canvas.drawCircle(Offset(rect.width * 0.85, rect.height * 0.7), rect.width * 0.5, blob2);
  }
}
