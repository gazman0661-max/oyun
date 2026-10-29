import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// Tamamen kod ile (Canvas/Path) cizilmis, harici hicbir gorsele veya
/// aga (network) ihtiyac duymayan animasyonlu uzay arka plani.
///
/// `uzay-arkaplan.html` prototipindeki 3 katmanli yapiyi birebir ayni
/// mantikla, vektorel (Canvas API) olarak uretir:
///   1) Nebula   -> birden fazla yumusak, renkli, transparan leke.
///   2) Yildizlar -> 3 hiz/boyut katmani, her biri kendi ritminde
///      parildar (twinkle), renk cesitliligi (beyaz/mavi/sari/kirmizi).
///   3) Kayan yildizlar -> belirli araliklarla dogan, iz birakan,
///      sonup giden kayan yildizlar.
///
/// Performans/stabilite icin:
///   - Nebula + gokyuzu gradyani AYRI ve STATIK bir katmanda cizilir;
///     sadece boyut degistiginde yeniden hesaplanir (her frame degil).
///   - Yildiz + kayan yildiz katmani tek bir Ticker ile surulur ve
///     `RepaintBoundary` ile diger katmanlardan izole edilir, boylece
///     her frame'de sadece bu kucuk katman yeniden ciziliyor.
///   - Ekran disina cikinca (baska bir sayfa ustte oldugunda) Flutter'in
///     TickerMode mekanizmasi bu animasyonu otomatik olarak durdurur.
///   - Buyuk/parlak (glow'lu) yildiz sayisi bilerek sinirlandirilmistir.
class SpaceBackground extends StatefulWidget {
  final Widget? child;

  const SpaceBackground({super.key, this.child});

  @override
  State<SpaceBackground> createState() => _SpaceBackgroundState();
}

class _SpaceBackgroundState extends State<SpaceBackground>
    with SingleTickerProviderStateMixin {
  static const List<_StarLayerSpec> _layerSpecs = [
    _StarLayerSpec(count: 70, twinkleSpeed: 0.5, sizeMin: 0.4, sizeMax: 1.0),
    _StarLayerSpec(count: 50, twinkleSpeed: 0.9, sizeMin: 0.8, sizeMax: 1.8),
    _StarLayerSpec(count: 30, twinkleSpeed: 1.4, sizeMin: 1.2, sizeMax: 2.6),
  ];

  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Random _rnd = Random();
  final List<_Star> _stars = [];
  final List<_ShootingStar> _shooting = [];

  double _lastT = 0;
  double _nextShootAt = 2.0;

  @override
  void initState() {
    super.initState();
    final seedRnd = Random(7);
    for (var li = 0; li < _layerSpecs.length; li++) {
      final spec = _layerSpecs[li];
      for (var i = 0; i < spec.count; i++) {
        _stars.add(_Star.random(seedRnd, li, spec));
      }
    }
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final double dt =
        (t - _lastT).clamp(0.0, 0.05).toDouble(); // don en fazla 50ms adim
    _lastT = t;

    // Kayan yildizlari guncelle / sonmus olanlari temizle.
    for (var i = _shooting.length - 1; i >= 0; i--) {
      final s = _shooting[i];
      s.update(dt);
      if (s.isDead) _shooting.removeAt(i);
    }
    // Yeni kayan yildiz dogur.
    if (t >= _nextShootAt && _shooting.length < 2) {
      _shooting.add(_ShootingStar.spawn(_rnd));
      _nextShootAt = t + 1.8 + _rnd.nextDouble() * 3.4;
    }

    _time.value = t;
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
        // Statik katman: gokyuzu gradyani + nebula lekeleri.
        const RepaintBoundary(
          child: CustomPaint(
            painter: _NebulaPainter(),
            size: Size.infinite,
          ),
        ),
        // Animasyonlu katman: yildizlar + kayan yildizlar.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _time,
            builder: (context, _) {
              return CustomPaint(
                painter: _StarfieldPainter(
                  stars: _stars,
                  shooting: List.unmodifiable(_shooting),
                  t: _time.value,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _StarLayerSpec {
  final int count;
  final double twinkleSpeed;
  final double sizeMin;
  final double sizeMax;
  const _StarLayerSpec({
    required this.count,
    required this.twinkleSpeed,
    required this.sizeMin,
    required this.sizeMax,
  });
}

class _Star {
  final double dx; // 0..1 orantili konum
  final double dy;
  final double baseSize;
  final double phase; // yanip sonme fazi
  final double twinkleSpeed;
  final double colorSeed;

  _Star({
    required this.dx,
    required this.dy,
    required this.baseSize,
    required this.phase,
    required this.twinkleSpeed,
    required this.colorSeed,
  });

  factory _Star.random(Random rnd, int layerIndex, _StarLayerSpec spec) {
    return _Star(
      dx: rnd.nextDouble(),
      dy: rnd.nextDouble(),
      baseSize: spec.sizeMin + rnd.nextDouble() * (spec.sizeMax - spec.sizeMin),
      phase: rnd.nextDouble() * 2 * pi,
      twinkleSpeed: spec.twinkleSpeed * (0.7 + rnd.nextDouble() * 0.6),
      colorSeed: rnd.nextDouble(),
    );
  }

  Color color(double alpha) {
    // Cogu yildiz beyaz/mavimsi, bazilari sari/kirmizimsi (HTML ile ayni
    // dagilim): %60 beyaz, %20 mavimsi, %12 sarimsi, %8 kirmizimsi.
    if (colorSeed < 0.6) return Colors.white.withValues(alpha: alpha);
    if (colorSeed < 0.8) {
      return Color.fromRGBO(180, 210, 255, alpha);
    }
    if (colorSeed < 0.92) {
      return Color.fromRGBO(255, 230, 180, alpha);
    }
    return Color.fromRGBO(255, 180, 160, alpha);
  }
}

class _ShootingStar {
  double x, y;
  final double vx, vy;
  double life; // 1 -> 0
  final List<Offset> trail = [];

  _ShootingStar({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
  }) : life = 1;

  bool get isDead => life <= 0;

  factory _ShootingStar.spawn(Random rnd) {
    // Konum/aci HTML prototipindeki gibi normalize (0..1) araliklarla
    // tanimlanir; ciziminde gercek boyuta olceklenir.
    final startX = rnd.nextDouble() * 0.7 + 0.15;
    final startY = rnd.nextDouble() * 0.3;
    final angle = pi / 4 + (rnd.nextDouble() - 0.5) * 0.4;
    final speed = 0.55 + rnd.nextDouble() * 0.35; // ekran genisligi/saniye
    return _ShootingStar(
      x: startX,
      y: startY,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
    );
  }

  void update(double dt) {
    trail.add(Offset(x, y));
    if (trail.length > 14) trail.removeAt(0);
    x += vx * dt;
    y += vy * dt;
    life -= dt * 0.75;
  }
}

class _NebulaPainter extends CustomPainter {
  const _NebulaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Gokyuzu gradyani (derin lacivertten mora).
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.spaceTop,
          AppColors.spaceMid,
          AppColors.spaceBottom,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    // uzay-arkaplan.html'deki 4 nebula lekesiyle birebir ayni konum/renk.
    final blobs = <_NebulaBlob>[
      const _NebulaBlob(0.20, 0.30, 0.35, Color(0x59502890)), // mor
      const _NebulaBlob(0.80, 0.60, 0.30, Color(0x4D143C78)), // mavi
      const _NebulaBlob(0.50, 0.80, 0.28, Color(0x38781459)), // pembemsi
      const _NebulaBlob(0.65, 0.15, 0.25, Color(0x400A5A6E)), // camgobegi
    ];
    for (final b in blobs) {
      final center = Offset(size.width * b.cx, size.height * b.cy);
      final radius = size.width * b.r;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [b.color, b.color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter oldDelegate) => false;
}

class _NebulaBlob {
  final double cx, cy, r;
  final Color color;
  const _NebulaBlob(this.cx, this.cy, this.r, this.color);
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_ShootingStar> shooting;
  final double t;

  _StarfieldPainter({
    required this.stars,
    required this.shooting,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      final twinkle = 0.55 + 0.45 * sin(t * star.twinkleSpeed + star.phase);
      final double alpha = (0.3 + twinkle * 0.7).clamp(0.0, 1.0).toDouble();
      final radius = star.baseSize * (0.85 + twinkle * 0.3);
      final center = Offset(star.dx * size.width, star.dy * size.height);

      dotPaint.color = star.color(alpha);
      canvas.drawCircle(center, radius, dotPaint);

      // Sadece buyuk yildizlara yumusak isilti (glow) ekle.
      if (star.baseSize > 1.8) {
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              star.color(alpha * 0.5),
              star.color(0),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: radius * 4),
          );
        canvas.drawCircle(center, radius * 4, glowPaint);
      }
    }

    for (final s in shooting) {
      if (s.trail.length < 2) continue;
      final trailPaint = Paint()..style = PaintingStyle.stroke;
      for (var i = 0; i < s.trail.length - 1; i++) {
        final p1 = Offset(
          s.trail[i].dx * size.width,
          s.trail[i].dy * size.height,
        );
        final p2 = Offset(
          s.trail[i + 1].dx * size.width,
          s.trail[i + 1].dy * size.height,
        );
        final frac = i / s.trail.length;
        final double alpha = (frac * s.life).clamp(0.0, 1.0).toDouble();
        trailPaint
          ..color = Colors.white.withValues(alpha: alpha)
          ..strokeWidth = 2 * frac;
        canvas.drawLine(p1, p2, trailPaint);
      }

      final head = Offset(s.x * size.width, s.y * size.height);
      final double headAlpha = s.life.clamp(0.0, 1.0).toDouble();
      final headGlow = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: headAlpha),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: head, radius: 6));
      canvas.drawCircle(head, 6, headGlow);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => true;
}
