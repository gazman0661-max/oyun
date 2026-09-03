import 'dart:math';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../services/sound_service.dart';

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
// 3) COMBO FLAMES — ekranin SOL ve SAG kenarlarinda duran birer MESALE
//    (torch: sap + metal kafes). Mesale govdesi HER ZAMAN gorunur (combo 0
//    iken sonmus/kor halde durur); [level] (0..1) SADECE alevin boyunu VE
//    "harlanma" yogunlugunu (ic beyaz-sari cekirdegin buyumesi, ekstra
//    "dil" sayisi, yukselen kivilcimlarin artmasi) belirler — combo
//    sifirlaninca (miss/jam) alev yumusakca soner ama mesale yerinde kalir.
//    [flicker], alevin sürekli titremesi/dalgalanmasi icin var olan (zaten
//    calisan) pulse animasyonunu yeniden kullanir - ek bir
//    AnimationController/Ticker acmaya gerek yok, maliyetsiz.
// =============================================================================

class ComboFlamesOverlay extends AnimatedWidget {
  final Animation<double> level; // 0..1, combo'ya oranli hedef yukseklik/harlanma
  final Animation<double> flicker; // 0..1, surekli tekrar eden titreme fazi

  ComboFlamesOverlay({super.key, required this.level, required this.flicker})
      : super(listenable: Listenable.merge([level, flicker]));

  @override
  Widget build(BuildContext context) {
    // DUZELTME: mesale govdesi artik combo 0 iken de gorunur (sonmus halde),
    // bu yuzden level==0 durumunda da widget'i gizlemiyoruz.
    return IgnorePointer(
      child: CustomPaint(
        painter: _TorchFlamesPainter(level: level.value, flicker: flicker.value),
        size: Size.infinite,
      ),
    );
  }
}

class _TorchFlamesPainter extends CustomPainter {
  final double level; // 0..1 - mevcut combo'ya gore alev boyu/harlanma
  final double flicker; // 0..1 - surekli titreme fazi
  _TorchFlamesPainter({required this.level, required this.flicker});

  // Mesale govdesinin sabit olcculeri (combo'dan bagimsiz).
  static const double _torchInset = 22; // kenardan ic mesafe
  static const double _handleHeight = 96;
  static const double _handleWidth = 12;
  static const double _cupWidth = 40;
  static const double _cupHeight = 20;

  @override
  void paint(Canvas canvas, Size size) {
    for (final fromLeft in [true, false]) {
      _drawTorch(canvas, size, fromLeft);
    }
  }

  void _drawTorch(Canvas canvas, Size size, bool fromLeft) {
    final baseX = fromLeft ? _torchInset : size.width - _torchInset;
    final handleBottomY = size.height + 24; // ekranin altina gomulu, sabit dursun
    final cupTopY = size.height - _handleHeight;

    _drawHandle(canvas, baseX, handleBottomY, cupTopY);
    _drawCup(canvas, baseX, cupTopY);

    final flameOriginY = cupTopY - _cupHeight * 0.55;
    final maxHeight = size.height * 0.30;
    final height = maxHeight * level;

    if (height > 0.5) {
      _drawGlow(canvas, Offset(baseX, flameOriginY), height, level);
      _drawFlameTongues(canvas, baseX, flameOriginY, height, fromLeft, flicker, level);
      _drawEmbers(canvas, baseX, flameOriginY, height, flicker, level);
    } else {
      // Sonmus mesale: kafeste hafif bir kor kalintisi.
      final emberPaint = Paint()..color = const Color(0xFF6B4A3A).withValues(alpha: 0.55);
      canvas.drawCircle(Offset(baseX, flameOriginY), 3.5, emberPaint);
    }
  }

  void _drawHandle(Canvas canvas, double x, double bottomY, double topY) {
    final rect = RRect.fromLTRBR(
      x - _handleWidth / 2,
      topY,
      x + _handleWidth / 2,
      bottomY,
      const Radius.circular(4),
    );
    final woodPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3E2723), Color(0xFF5D4037), Color(0xFF3E2723)],
      ).createShader(Rect.fromLTWH(x - _handleWidth / 2, topY, _handleWidth, bottomY - topY));
    canvas.drawRRect(rect, woodPaint);

    // Sap uzerinde birkac ince metal sargı bandi (detay).
    final bandPaint = Paint()..color = const Color(0xFF212121);
    for (final t in [0.3, 0.6]) {
      final y = topY + (bottomY - topY) * t;
      canvas.drawRect(
        Rect.fromLTWH(x - _handleWidth / 2 - 1, y, _handleWidth + 2, 3),
        bandPaint,
      );
    }
  }

  void _drawCup(Canvas canvas, double x, double cupTopY) {
    final path = Path()
      ..moveTo(x - _handleWidth / 2 - 2, cupTopY + _cupHeight)
      ..lineTo(x - _cupWidth / 2, cupTopY)
      ..lineTo(x + _cupWidth / 2, cupTopY)
      ..lineTo(x + _handleWidth / 2 + 2, cupTopY + _cupHeight)
      ..close();
    final metalPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF616161), Color(0xFF212121)],
      ).createShader(Rect.fromLTWH(x - _cupWidth / 2, cupTopY, _cupWidth, _cupHeight));
    canvas.drawPath(path, metalPaint);

    // Kafes cubuklari (dekoratif detay).
    final barPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 1.6;
    for (final dx in [-0.28, 0.0, 0.28]) {
      canvas.drawLine(
        Offset(x + dx * _cupWidth, cupTopY),
        Offset(x + dx * _handleWidth * 1.2, cupTopY + _cupHeight),
        barPaint,
      );
    }
  }

  /// Alevin arkasinda, harlandikca (level artikca) parlaklasan yumusak bir
  /// isik halesi (bloom). Gercek bir mesalenin cevreyi aydinlatma hissini
  /// vermek icin.
  void _drawGlow(Canvas canvas, Offset origin, double height, double lvl) {
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD54F).withValues(alpha: 0.35 * lvl),
          const Color(0xFFFFD54F).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: origin, radius: height * 0.9))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(origin, height * 0.85, glowPaint);
  }

  /// Birden fazla, birbirinin icinden gecen "dil" (tongue) ile gercek bir
  /// mesale alevi gibi dagimik/yalayan bir siluet olusturur — tek, duz bir
  /// damla yerine. Combo (level) yukseldikce hem dil sayisi artar (4.
  /// dil sadece level>0.55 sonrasi eklenir) hem de ic beyaz-sari cekirdek
  /// buyuyup parlaklasarak "harlanma" hissi verir.
  void _drawFlameTongues(
    Canvas canvas,
    double baseX,
    double baseY,
    double height,
    bool fromLeft,
    double t,
    double lvl,
  ) {
    final dir = fromLeft ? 1.0 : -1.0;
    final tongueDefs = <({double heightScale, double widthScale, double phase, double xShift})>[
      (heightScale: 1.0, widthScale: 1.0, phase: 0.0, xShift: 0.0),
      (heightScale: 0.72, widthScale: 0.65, phase: 1.7, xShift: 0.55),
      (heightScale: 0.55, widthScale: 0.5, phase: 3.4, xShift: -0.5),
      if (lvl > 0.55) (heightScale: 0.42, widthScale: 0.4, phase: 5.1, xShift: 0.9),
    ];

    for (final def in tongueDefs) {
      _drawTongue(
        canvas,
        baseX + dir * def.xShift * 14,
        baseY,
        height * def.heightScale,
        26 * def.widthScale + lvl * 6,
        dir,
        t,
        def.phase,
        outer: true,
      );
    }
    // Ic sicak cekirdek: harlandikca (lvl) buyur ve beyazlasir.
    _drawTongue(
      canvas,
      baseX,
      baseY,
      height * (0.45 + lvl * 0.35),
      14 + lvl * 8,
      dir,
      t,
      0.8,
      outer: false,
    );
  }

  void _drawTongue(
    Canvas canvas,
    double baseX,
    double baseY,
    double h,
    double w,
    double dir,
    double t,
    double phase, {
    required bool outer,
  }) {
    if (h < 1) return;
    final wobble1 = sin(t * pi * 6 + phase) * (w * 0.18);
    final wobble2 = sin(t * pi * 9 + phase * 1.6) * (w * 0.10);
    final tipX = baseX + dir * (w * 0.12 + wobble1);
    final tipY = baseY - h;

    // Asimetrik, kivrik/jagged bir "dil" siluetti: duz bir damla yerine
    // yanlarda gelisiguzel sisen, tepede tek bir noktaya kivrilan gercek
    // alev gorunumu.
    final path = Path()
      ..moveTo(baseX - w * 0.28, baseY)
      ..quadraticBezierTo(
        baseX - w * 0.42 + wobble2,
        baseY - h * 0.45,
        baseX - w * 0.10,
        baseY - h * 0.72,
      )
      ..quadraticBezierTo(
        baseX - w * 0.02,
        baseY - h * 0.9,
        tipX,
        tipY,
      )
      ..quadraticBezierTo(
        baseX + w * 0.14,
        baseY - h * 0.78,
        baseX + w * 0.46 + wobble1,
        baseY - h * 0.5,
      )
      ..quadraticBezierTo(
        baseX + w * 0.30 - wobble2,
        baseY - h * 0.2,
        baseX + w * 0.28,
        baseY,
      )
      ..close();

    final colors = outer
        ? const [Color(0xFFE64A19), Color(0xFFFB8C00), AppColors.warning]
        : const [AppColors.warning, Color(0xFFFFF176), Color(0xFFFFFDE7)];

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: colors,
      ).createShader(Rect.fromLTWH(baseX - w, baseY - h, w * 2, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  /// Alev harlandikca (level artikca) ucundan yukari dogru kacan, sonup
  /// giden kivilcimlar. Sayilari ve hizlari combo seviyesiyle artar.
  void _drawEmbers(Canvas canvas, double baseX, double baseY, double height, double t, double lvl) {
    final count = (lvl * 7).round();
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < count; i++) {
      final seed = i * 0.618;
      final cycle = ((t * 0.55) + seed) % 1.0;
      final riseY = baseY - height * (0.7 + cycle * 1.4);
      final jitterX = sin(t * 4 + seed * 10) * (10 + i * 2);
      final alpha = (1.0 - cycle).clamp(0.0, 1.0);
      final radius = 2.2 * (1.0 - cycle * 0.6);
      paint.color = (i.isEven ? const Color(0xFFFFD54F) : const Color(0xFFFF8A65))
          .withValues(alpha: alpha * 0.85);
      canvas.drawCircle(Offset(baseX + jitterX, riseY), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TorchFlamesPainter oldDelegate) =>
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
        // DUZELTME (istek): "havai fisek patlamalari yapmacik duruyor,
        // gercekci olsun" - asagidaki alanlar patlama basina benzersiz,
        // KARE-KOKLU (deterministik) bir "seed" ve hafif yaricap
        // cesitliligi saglar; boylece her patlama az sonra asagida
        // (_FireworksPainter) hesaplanan duzensiz/organik kivilcim
        // dagilimi, yercekimi egrisi ve parlama/iz efektlerinde
        // BIRBIRINDEN FARKLI ama HER KAREDE AYNI (kararli, titremeyen)
        // sonuc uretir.
        seed: rnd.nextDouble() * 1000,
        burstRadius: 44 + rnd.nextDouble() * 14,
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
          _triggerTimedSounds(t);
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

  /// Her yeniden cizimde (frame), henuz sesi calinmamis ve baslama anina
  /// (delay) ulasilmis parlama/uzayli varsa ilgili sesi bir kez tetikler.
  /// Boylece havai fisek patlamasi/uzayli gecisi gorsel anla es zamanli
  /// ("senkron") ses alir, hepsi ayni anda degil.
  void _triggerTimedSounds(double t) {
    for (final s in _fireworks) {
      if (!s.soundPlayed && t >= s.delay) {
        s.soundPlayed = true;
        SoundService.instance.fireworkPop();
      }
    }
    for (final a in _aliens) {
      if (!a.soundPlayed && t >= a.delay) {
        a.soundPlayed = true;
        SoundService.instance.ufoFlyby();
      }
    }
  }

  Widget _buildAlien(BuildContext context, _FlyingAlien alien, double t) {
    final localT = ((t - alien.delay) / alien.crossFraction).clamp(0.0, 1.0);
    if (localT <= 0 || localT >= 1) return const SizedBox.shrink();
    // DUZELTME (bug): Positioned, LayoutBuilder icine sarilinca Stack'in
    // DOGRUDAN cocugu sayilmiyor ve konumlandirma etkisiz kaliyor (uzayli
    // sol-ust kosede kucuk bir noktada sikisip kaliyordu). LayoutBuilder
    // tamamen kaldirildi; bu widget zaten Positioned.fill ile tam ekran
    // acildigi icin boyut MediaQuery'den okunuyor ve Positioned artik
    // gercekten Stack'in dogrudan cocugu.
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
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
  /// Gecis sesi (ufoFlyby) sadece bir kez calinsin diye kullanilir.
  bool soundPlayed = false;
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
  /// Bu patlamaya ozel, deterministik "seed" — kivilcim dagilimini,
  /// yaricap/hiz varyasyonunu ve beyaz-cekirdek parcaciklarini HER
  /// KAREDE AYNI (titremeyen) ama patlamadan patlamaya FARKLI kilmak
  /// icin kullanilir (bkz. _FireworksPainter._hash).
  final double seed;
  /// Bu patlamanin yaricapi (px) — hafif rastgele, boylece art arda
  /// gelen patlamalar birbirinin ayni boyda hissettirmez.
  final double burstRadius;
  /// Patlama sesi (fireworkPop) sadece bir kez calinsin diye kullanilir.
  bool soundPlayed = false;
  _FireworkSpark({
    required this.fromLeft,
    required this.xFraction,
    required this.yFraction,
    required this.delay,
    required this.color,
    required this.seed,
    required this.burstRadius,
  });
}

/// DUZELTME (istek): "havai fisek patlamalari yapmacik duruyor, gercekci
/// olsun" - eski versiyon tek renkli, mukemmel simetrik bir daire
/// uzerinde esit araliklarla dizilmis noktalardan olusuyordu (hicbir
/// kalkis/fune izi, yercekimi, iz/kuyruk ya da sicak-cekirdek yoktu) -
/// gercek bir havai fisekten cok "yildizlarin daire seklinde acilmasina"
/// benziyordu. Bu surum su gercek havai fisek ozelliklerini ekliyor:
///   1) KALKIS IZI: patlamadan once ekranin altindan yukari dogru kisa,
///      parlak bir fune izi yukselir (gercek havai fisegin roket
///      asamasi).
///   2) DUZENSIZ/ORGANIK DAGILIM: kivilcimlar mukemmel esit acili bir
///      cember uzerinde DEGIL, her isinin acisi ve hizi hafifce (ama
///      HER KAREDE AYNI kalacak sekilde, deterministik bir hash ile)
///      farklilastirilmis - gercek bir barut patlamasinin duzensizligini
///      taklit eder.
///   3) YERCEKIMI: kivilcimlar disari firladikca zamanla asagi dogru
///      egilir (parabolik dusus), duz cizgiler yerine gercek bir yay
///      cizer.
///   4) SICAK CEKIRDEKTEN SOGUYAN RENK: her isinin ic ucu once
///      beyaz-sari ("tam sicak"), zamanla patlamanin kendi rengine
///      "soguyarak" gecer - gercek barut kivilciminin yanma egrisi.
///   5) IZ (KUYRUK): her kivilcimin arkasinda, hareket yonunde solan
///      kisa bir kuyruk cizilir - noktalar yerine gercek "kivilcim
///      cizgileri" hissi verir.
///   6) PATLAMA PARLAMASI (FLASH): patlama anin hemen basinda, kisa
///      sureli yumusak beyaz bir isik halesi (bloom) parlar - gercek
///      barut patlamasinin ani isik sacmasi.
class _FireworksPainter extends CustomPainter {
  final List<_FireworkSpark> sparks;
  final double t;
  static const int raysPerBurst = 18;
  static const double launchDuration = 0.08;
  static const double burstDuration = 0.45;
  _FireworksPainter({required this.sparks, required this.t});

  /// Basit, hizli, deterministik bir "hash" - gercek Random() KULLANMAZ
  /// (her cizimde/frame'de ayni [seed] icin HER ZAMAN ayni sonucu verir,
  /// boylece kivilcimlar kare kare titremez/sicramaz) ama gorsel olarak
  /// yeterince duzensiz (pseudo-random) bir 0..1 degeri uretir.
  static double _hash(double seed) {
    final v = sin(seed * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..style = PaintingStyle.fill;
    for (final s in sparks) {
      final cx = s.xFraction * size.width;
      final cy = s.yFraction * size.height;

      // --- 1) KALKIS IZI: patlamadan hemen once, ekranin altindan
      // patlama noktasina dogru yukselen kisa, parlak bir fune izi. ---
      final launchT =
          ((t - (s.delay - launchDuration)) / launchDuration).clamp(0.0, 1.0);
      if (launchT > 0 && launchT < 1 && t < s.delay) {
        final startY = size.height * 1.05;
        final headY = startY + (cy - startY) * Curves.easeIn.transform(launchT);
        final tailY = startY + (cy - startY) * Curves.easeIn.transform((launchT - 0.22).clamp(0.0, 1.0));
        final trailPaint = Paint()
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              s.color.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.85),
            ],
          ).createShader(Rect.fromPoints(Offset(cx, tailY), Offset(cx, headY)));
        canvas.drawLine(Offset(cx, tailY), Offset(cx, headY), trailPaint);
        canvas.drawCircle(Offset(cx, headY), 2.0, Paint()..color = Colors.white);
      }

      final localT = ((t - s.delay) / burstDuration).clamp(0.0, 1.0);
      if (localT <= 0 || (t - s.delay) > burstDuration) continue;
      final eased = Curves.easeOutCubic.transform(localT);
      final fade = (1.0 - localT).clamp(0.0, 1.0);
      // Yercekimi: patlama buyudukce (burstRadius arttikca) kivilcimlar
      // orantili olarak daha belirgin egilir - gercek bir havai fisegin
      // buyuk/kucuk patlama farkini taklit eder.
      final gravity = s.burstRadius * 0.55;

      // --- 6) PATLAMA PARLAMASI: patlamanin ilk aninda kisa, yumusak
      // bir beyaz isik halesi. ---
      if (localT < 0.22) {
        final flashFade = (1.0 - localT / 0.22).clamp(0.0, 1.0);
        final flashPaint = Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.55 * flashFade),
            Colors.white.withValues(alpha: 0.0),
          ]).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: s.burstRadius * 0.7))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(Offset(cx, cy), s.burstRadius * 0.65, flashPaint);
      }

      for (int i = 0; i < raysPerBurst; i++) {
        // --- 2) DUZENSIZ/ORGANIK DAGILIM: aci ve hiz, her isi icin
        // deterministik hash ile hafifce farklilastirilir. ---
        final angleJitter = (_hash(s.seed + i * 7.31) - 0.5) * 0.5;
        final speedVar = 0.72 + _hash(s.seed + i * 3.17) * 0.56;
        final angle = (2 * pi / raysPerBurst) * i + angleJitter;
        final dist = s.burstRadius * speedVar * eased;

        // --- 3) YERCEKIMI: zamanla asagi dogru egilen parabolik yol. ---
        final drop = gravity * localT * localT;
        final x = cx + cos(angle) * dist;
        final y = cy + sin(angle) * dist * 0.85 + drop;

        // --- 5) IZ (KUYRUK): bir onceki konumdan simdiki konuma kisa,
        // solan bir cizgi - "noktalar" yerine "kivilcim cizgileri". ---
        final prevLocalT = (localT - 0.06).clamp(0.0, 1.0);
        if (prevLocalT > 0) {
          final prevEased = Curves.easeOutCubic.transform(prevLocalT);
          final prevDist = s.burstRadius * speedVar * prevEased;
          final prevDrop = gravity * prevLocalT * prevLocalT;
          final px = cx + cos(angle) * prevDist;
          final py = cy + sin(angle) * prevDist * 0.85 + prevDrop;
          final tailPaint = Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = s.color.withValues(alpha: fade * 0.45);
          canvas.drawLine(Offset(px, py), Offset(x, y), tailPaint);
        }

        // --- 4) SICAK CEKIRDEKTEN SOGUYAN RENK: erken localT'de beyaz-
        // sari "tam sicak" cekirdek, zamanla kendi rengine soguyor. ---
        final coolT = (localT * 1.8).clamp(0.0, 1.0);
        final sparkColor =
            Color.lerp(const Color(0xFFFFF9C4), s.color, coolT) ?? s.color;
        // Her patlamada bazi isinlar (deterministik olarak secilen ~1/4'u)
        // biraz daha buyuk/parlak "ana kivilcim", geri kalani daha kucuk
        // "ince toz" kivilcimlari olarak cizilir - tek boyutlu, mekanik
        // gorunumun onune gecer.
        final isPrimary = _hash(s.seed + i * 1.91) > 0.7;
        final sizeJitter = 0.65 + _hash(s.seed + i * 5.53) * 0.7;
        final radius =
            (isPrimary ? 3.0 : 1.7) * sizeJitter * (fade * 0.85 + 0.15);

        // Hafif "pirilti" (twinkle): kivilcimlar sabit sonmek yerine
        // ince bir titresimle parlaklik degistirir.
        final twinkle = 0.75 + 0.25 * sin(t * 46 + s.seed + i * 2.3);
        fillPaint.color = sparkColor.withValues(alpha: (fade * twinkle).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), radius, fillPaint);
      }

      // Merkezden disari yayilan yumusak halka (patlamanin "govdesi").
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = s.color.withValues(alpha: fade * 0.5);
      canvas.drawCircle(Offset(cx, cy + gravity * localT * localT * 0.4),
          6 + eased * s.burstRadius * 0.6, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) => oldDelegate.t != t;
}
