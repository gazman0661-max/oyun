import 'dart:math';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

// =============================================================================
// 1) MATCH BURST — bir gezegen teslim edildiginde/eslesince patlayan,
//    disari dogru yayilan kucuk parcaciklar. Tek bir AnimationController ile
//    surulur, sabit ve dusuk sayida parcacik (10) kullanir; agir particle
//    paketleri yerine tek CustomPainter cizimi oldugu icin dusuk segment
//    Android'de de ucuzdur.
// =============================================================================

class MatchBurstItem {
  final int id;
  final Offset center;
  final Color color;
  final AnimationController anim;

  MatchBurstItem({
    required this.id,
    required this.center,
    required this.color,
    required this.anim,
  });
}

class MatchBurstWidget extends AnimatedWidget {
  final MatchBurstItem item;
  static const int particleCount = 10;
  static const double maxRadius = 46.0;

  MatchBurstWidget({super.key, required this.item}) : super(listenable: item.anim);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BurstPainter(
          progress: item.anim.value,
          center: item.center,
          color: item.color,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress; // 0..1
  final Offset center;
  final Color color;
  _BurstPainter({required this.progress, required this.center, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(progress);
    final fade = (1.0 - progress).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < MatchBurstWidget.particleCount; i++) {
      final angle = (2 * pi / MatchBurstWidget.particleCount) * i;
      final dist = MatchBurstWidget.maxRadius * eased;
      final pos = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final radius = 3.2 * fade + 0.6;
      paint.color = (i.isEven ? color : Colors.white).withValues(alpha: fade * 0.9);
      canvas.drawCircle(pos, radius, paint);
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: fade * 0.6);
    canvas.drawCircle(center, 10 + eased * 18, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.center != center;
}

// =============================================================================
// 2) JAM FLASH — halka rihtim doluluğu yuzunden reddedince (bkz. orbit_board
//    _flash) artik sadece o halka degil, TUM ekran cok kisa/hafif kirmizi
//    yanip soner. Ses tarafi zaten SoundService.instance.invalid() ile ayni
//    anda calindigi icin burada tekrar ses tetiklemiyoruz.
// =============================================================================

class JamFlashOverlay extends AnimatedWidget {
  final Animation<double> intensity; // 0..1..0

  const JamFlashOverlay({super.key, required this.intensity}) : super(listenable: intensity);

  @override
  Widget build(BuildContext context) {
    final v = intensity.value;
    if (v <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(color: AppColors.danger.withValues(alpha: v * 0.28)),
    );
  }
}

// =============================================================================
// 3) COMBO FLAMES — combo arttikca ekranin SOL ve SAG kenarlarindan yukari
//    dogru KADEMELI olarak yukselen bir "alev" siluetti. Artik esik bazli
//    tek seferlik bir patlama degil: [level] (0..1) dogrudan mevcut combo
//    degerine oranli - combo arttikca alev buyur, combo sifirlaninca
//    (miss/jam) yumusakca soner. [flicker], alevin sürekli hafifce titremesi
//    icin var olan (zaten calisan) pulse animasyonunu yeniden kullanir - ek
//    bir AnimationController/Ticker acmaya gerek yok, maliyetsiz.
// =============================================================================

class ComboFlamesOverlay extends AnimatedWidget {
  final Animation<double> level; // 0..1, combo'ya oranli hedef yukseklik
  final Animation<double> flicker; // 0..1, surekli tekrar eden titreme fazi

  ComboFlamesOverlay({super.key, required this.level, required this.flicker})
      : super(listenable: Listenable.merge([level, flicker]));

  @override
  Widget build(BuildContext context) {
    final v = level.value;
    if (v <= 0.001) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _FlamesPainter(level: v, flicker: flicker.value),
        size: Size.infinite,
      ),
    );
  }
}

class _FlamesPainter extends CustomPainter {
  final double level; // 0..1 - mevcut combo'ya gore hedef yukseklik
  final double flicker; // 0..1 - surekli titreme fazi
  _FlamesPainter({required this.level, required this.flicker});

  @override
  void paint(Canvas canvas, Size size) {
    // Yukseklik dogrudan combo seviyesine baglı; titreme (flicker) sadece
    // gorsel canlilik icin kucuk bir dalgalanma katar, yuksekligi belirlemez.
    final flameHeight = size.height * 0.34 * level;
    const fade = 1.0;

    for (final fromLeft in [true, false]) {
      _drawFlameColumn(canvas, size, fromLeft, flameHeight, fade, flicker);
    }
  }

  void _drawFlameColumn(
      Canvas canvas, Size size, bool fromLeft, double height, double fade, double t) {
    final baseX = fromLeft ? 0.0 : size.width;
    final dir = fromLeft ? 1.0 : -1.0;
    final baseY = size.height;

    final colors = [
      const Color(0xFFFFE082),
      AppColors.warning,
      const Color(0xFFFB8C00),
      const Color(0xFFE64A19),
    ];

    for (int layer = 0; layer < colors.length; layer++) {
      final layerHeight = height * (1.0 - layer * 0.16);
      final width = 34.0 + layer * 10.0;
      final wobble = sin(t * pi * 6 + layer) * 6;

      final path = Path()..moveTo(baseX, baseY);
      path.lineTo(baseX + dir * (width * 0.15), baseY - layerHeight * 0.35);
      path.quadraticBezierTo(
        baseX + dir * (width * 0.55 + wobble),
        baseY - layerHeight * 0.7,
        baseX + dir * (width * 0.25),
        baseY - layerHeight,
      );
      path.quadraticBezierTo(
        baseX + dir * (width * 0.05),
        baseY - layerHeight * 0.85,
        baseX,
        baseY - layerHeight * 0.55,
      );
      path.close();

      final paint = Paint()
        ..color = colors[layer].withValues(alpha: fade * (0.85 - layer * 0.12));
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlamesPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.flicker != flicker;
}

// =============================================================================
// 4) LEVEL COMPLETE CELEBRATION — bolum tamamlaninca:
//    - hafif, kisa sureli "yagmur gibi" konfeti (once 22 parcaydi, artik 12,
//      daha ince/az sallanan/daha kisa sureli)
//    - yildiz sayisina gore SOL/SAG kenarda patlayan havai fisekler
//      (1 yildiz -> 1, 2 yildiz -> 2, 3 yildiz -> 5)
//    - kullanicinin gonderdigi iki UFO gorseli (assets/fx/alien_ufo_1.png,
//      alien_ufo_2.png) kucultulup ekranda ucusturuluyor (her birinden 2 adet)
// =============================================================================

class LevelCompleteCelebration extends StatefulWidget {
  final int stars; // 1..3
  /// Kutlama animasyonu tamamen bitince cagrilir. Bu, bolum sonu ozel
  /// popup'ini (2x XP / Sonraki Bolum butonlari) DOGRU SIRAYLA - yani
  /// konfeti + ucan uzaylilar tamamen bittikten SONRA - acmak icin kullanilir.
  final VoidCallback? onComplete;
  const LevelCompleteCelebration({super.key, required this.stars, this.onComplete});

  @override
  State<LevelCompleteCelebration> createState() => _LevelCompleteCelebrationState();
}

class _LevelCompleteCelebrationState extends State<LevelCompleteCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;
  late final List<_FireworkSpark> _fireworks;
  late final List<_FlyingAlien> _aliens;

  // DUZELTME (istek): "cok sade oldu, eski haline getir" - konfeti eski
  // (daha bol/daha uzun sureli) haline donduruldu.
  static const int _pieceCount = 22;
  static const Duration _totalDuration = Duration(milliseconds: 2600);
  static const List<Color> _palette = [
    AppColors.warning,
    AppColors.accent,
    AppColors.success,
    Colors.pinkAccent,
    Colors.cyanAccent,
  ];
  static const List<Color> _fireworkPalette = [
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.lightBlueAccent,
    AppColors.warning,
    Colors.greenAccent,
  ];

  static const Map<int, int> _fireworkCountByStar = {1: 1, 2: 2, 3: 5};

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    _pieces = List.generate(_pieceCount, (i) {
      return _ConfettiPiece(
        xFraction: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.35,
        color: _palette[rnd.nextInt(_palette.length)],
        wobble: 0.4 + rnd.nextDouble() * 0.8,
        spin: (rnd.nextBool() ? 1 : -1) * (2 + rnd.nextDouble() * 3),
        size: 5 + rnd.nextDouble() * 4,
      );
    });

    final fireworkCount = _fireworkCountByStar[widget.stars.clamp(1, 3)] ?? 1;
    _fireworks = List.generate(fireworkCount, (i) {
      final left = i.isEven;
      return _FireworkSpark(
        fromLeft: left,
        xFraction: 0.08 + rnd.nextDouble() * 0.14,
        yFraction: 0.15 + rnd.nextDouble() * 0.45,
        delay: (i ~/ 2) * 0.18 + rnd.nextDouble() * 0.08,
        color: _fireworkPalette[rnd.nextInt(_fireworkPalette.length)],
      );
    });

    // DUZELTME (istek): "uzaylilar cok hizli, hizini azalt" - her uzaylinin
    // ekrani gecme suresi artik toplam sürenin buyuk bir kismini (~%75-85)
    // kaplayacak sekilde uzatildi, boylece belirgin sekilde daha yavas ve
    // "sukunetle sÜzülen" bir gecis hissi veriyor.
    _aliens = [
      _FlyingAlien(asset: _alienAsset1, laneFraction: 0.16, delay: 0.02, crossFraction: 0.82, leftToRight: true),
      _FlyingAlien(asset: _alienAsset2, laneFraction: 0.34, delay: 0.16, crossFraction: 0.78, leftToRight: false),
      _FlyingAlien(asset: _alienAsset1, laneFraction: 0.58, delay: 0.10, crossFraction: 0.80, leftToRight: false),
      _FlyingAlien(asset: _alienAsset2, laneFraction: 0.76, delay: 0.20, crossFraction: 0.75, leftToRight: true),
    ];

    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration,
    )..forward().whenComplete(() {
        widget.onComplete?.call();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConfettiPainter(pieces: _pieces, t: t),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _FireworksPainter(sparks: _fireworks, t: t),
                ),
              ),
              for (final alien in _aliens) _buildAlien(context, alien, t),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlien(BuildContext context, _FlyingAlien alien, double t) {
    final localT = ((t - alien.delay) / alien.crossFraction).clamp(0.0, 1.0);
    if (localT <= 0 || localT >= 1) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final startX = alien.leftToRight ? -70.0 : w + 70.0;
      final endX = alien.leftToRight ? w + 70.0 : -70.0;
      final x = startX + (endX - startX) * Curves.easeInOut.transform(localT);
      final y = h * alien.laneFraction + sin(localT * pi * 2) * 10;
      final opacity = localT < 0.12
          ? localT / 0.12
          : (localT > 0.85 ? (1.0 - localT) / 0.15 : 1.0);
      return Positioned(
        left: x - 26,
        top: y - 18,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.flip(
            flipX: !alien.leftToRight,
            child: Image.asset(alien.asset, width: 52, height: 36, fit: BoxFit.contain),
          ),
        ),
      );
    });
  }
}

const String _alienAsset1 = 'assets/fx/alien_ufo_1.png';
const String _alienAsset2 = 'assets/fx/alien_ufo_2.png';

class _FlyingAlien {
  final String asset;
  final double laneFraction; // 0..1, dikey konum
  final double delay; // 0..1, controller icinde ne zaman baslasin
  /// Ekrani gecme suresinin, toplam kutlama suresine orani (0..1). Buyuk
  /// deger = daha YAVAS gecis (daha uzun sürede ekrani kat eder).
  final double crossFraction;
  final bool leftToRight;
  _FlyingAlien({
    required this.asset,
    required this.laneFraction,
    required this.delay,
    required this.crossFraction,
    required this.leftToRight,
  });
}

class _ConfettiPiece {
  final double xFraction;
  final double delay;
  final Color color;
  final double wobble;
  final double spin;
  final double size;
  _ConfettiPiece({
    required this.xFraction,
    required this.delay,
    required this.color,
    required this.wobble,
    required this.spin,
    required this.size,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double t; // 0..1
  _ConfettiPainter({required this.pieces, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in pieces) {
      final localT = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      // DUZELTME (istek): "cok sade oldu, eski haline getir" - daha canli
      // sallanan/donen, daha "konfeti gibi" bir dusus egrisine donuldu.
      final fallY = size.height * 0.55 * Curves.easeIn.transform(localT);
      final sway = sin(localT * pi * 2 * p.wobble) * 14;
      final dx = p.xFraction * size.width + sway;
      final dy = fallY - 20;
      final opacity = (1.0 - (localT > 0.75 ? (localT - 0.75) / 0.25 : 0)).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(localT * p.spin);
      paint.color = p.color.withValues(alpha: opacity);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 1.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}

class _FireworkSpark {
  final bool fromLeft;
  final double xFraction;
  final double yFraction;
  final double delay;
  final Color color;
  _FireworkSpark({
    required this.fromLeft,
    required this.xFraction,
    required this.yFraction,
    required this.delay,
    required this.color,
  });
}

class _FireworksPainter extends CustomPainter {
  final List<_FireworkSpark> sparks;
  final double t;
  static const int raysPerBurst = 12;
  static const double burstDuration = 0.45;
  _FireworksPainter({required this.sparks, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in sparks) {
      final localT = ((t - s.delay) / burstDuration).clamp(0.0, 1.0);
      if (localT <= 0 || (t - s.delay) > burstDuration) continue;
      final eased = Curves.easeOutCubic.transform(localT);
      final fade = (1.0 - localT).clamp(0.0, 1.0);
      final cx = s.xFraction * size.width;
      final cy = s.yFraction * size.height;
      final maxDist = 42.0;

      for (int i = 0; i < raysPerBurst; i++) {
        final angle = (2 * pi / raysPerBurst) * i;
        final dist = maxDist * eased;
        final x = cx + cos(angle) * dist;
        final y = cy + sin(angle) * dist * 0.85;
        paint.color = s.color.withValues(alpha: fade);
        canvas.drawCircle(Offset(x, y), 2.4 * fade + 0.4, paint);
      }
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = s.color.withValues(alpha: fade * 0.7);
      canvas.drawCircle(Offset(cx, cy), 6 + eased * 20, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) => oldDelegate.t != t;
}
