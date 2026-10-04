import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Ilk birkac bolumde masanin uzerine binen, oyuncuya iki seyi otomatik
/// olarak GOSTEREN bir el/parmak animasyonu:
///   Faz 1 - Firlatma: el, atis noktasindaki objeyi "tutar", yukari dogru
///           surukler, birakir; obje kendi kendine kayip durur.
///   Faz 2 - Birlesme: ayni seviyeden iki obje yan yana gelince
///           birlesip bir ustteki objeye donustugunu gosterir.
/// Bu widget TAMAMEN KOZMETIKTIR: kendi hayalet objelerini cizer, gercek
/// _balls fizigine hic dokunmaz. IgnorePointer ile sarilarak kullanilir,
/// boylece gercek surukle/at hareketini asla engellemez.
class HandTutorialOverlay extends StatefulWidget {
  final double boardWidth;
  final double boardHeight;
  final double padX;
  final double padY;
  final double tableTopY;
  final ui.Image? itemImage; // bekleyen (pending) objenin gorseli
  final ui.Image? mergedImage; // bir ust seviyenin gorseli (varsa)
  final double itemDiameter;

  const HandTutorialOverlay({
    super.key,
    required this.boardWidth,
    required this.boardHeight,
    required this.padX,
    required this.padY,
    required this.tableTopY,
    required this.itemImage,
    required this.mergedImage,
    required this.itemDiameter,
  });

  @override
  State<HandTutorialOverlay> createState() => _HandTutorialOverlayState();
}

class _HandTutorialOverlayState extends State<HandTutorialOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  // Toplam dongu suresi iki faza bolunur (0..0.5 firlatma, 0.5..1 birlesme).
  static const _cycle = Duration(milliseconds: 4400);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _cycle)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.boardWidth,
        height: widget.boardHeight,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: Size(widget.boardWidth, widget.boardHeight),
            painter: _HandTutorialPainter(
              t: _c.value,
              padX: widget.padX,
              padY: widget.padY,
              tableTopY: widget.tableTopY,
              itemImage: widget.itemImage,
              mergedImage: widget.mergedImage,
              itemDiameter: widget.itemDiameter,
            ),
          ),
        ),
      ),
    );
  }
}

double _easeInOut(double x) => x < 0.5 ? 2 * x * x : 1 - ((-2 * x + 2) * (-2 * x + 2)) / 2;

class _HandTutorialPainter extends CustomPainter {
  final double t; // 0..1, tam bir dongu
  final double padX;
  final double padY;
  final double tableTopY;
  final ui.Image? itemImage;
  final ui.Image? mergedImage;
  final double itemDiameter;

  _HandTutorialPainter({
    required this.t,
    required this.padX,
    required this.padY,
    required this.tableTopY,
    required this.itemImage,
    required this.mergedImage,
    required this.itemDiameter,
  });

  void _drawImage(Canvas canvas, ui.Image? img, Offset center, double diameter, double opacity, {double scale = 1}) {
    if (img == null || opacity <= 0) return;
    final d = diameter * scale;
    final rect = Rect.fromCenter(center: center, width: d, height: d);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1));
    canvas.drawImageRect(img, src, rect, paint);
  }

  void _drawHand(Canvas canvas, Offset pos, double opacity, {double press = 0}) {
    if (opacity <= 0) return;
    final scale = 1.0 - press * 0.14; // basma aninda hafif kuculme
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(scale);

    // Yumusak koyu daire (ikonun her arka planda okunurlugu icin).
    final bg = Paint()..color = Color.fromRGBO(20, 14, 8, 0.5 * opacity);
    canvas.drawCircle(Offset.zero, 27, bg);

    // Basma halkasi (release/press anlarinda genisleyip solan bir cember).
    if (press > 0) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Color.fromRGBO(255, 255, 255, (1 - press) * 0.9 * opacity);
      canvas.drawCircle(Offset.zero, 20 + press * 22, ringPaint);
    }

    // Gercek bir el/dokunma ikonu (Material Icons) - onceki elle-cizilmis
    // "parmak" sekli garip duruyordu, hazir ve duzgun tasarlanmis ikon
    // kullaniliyor. Farkli bir gorunum istersen Icons.back_hand (acik el)
    // veya Icons.pan_tool ile degistirebilirsin.
    const icon = Icons.touch_app;
    const iconSize = 32.0;
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Color.fromRGBO(255, 255, 255, opacity),
        ),
      )
      ..layout();
    tp.paint(canvas, Offset(-iconSize / 2, -iconSize / 2));

    canvas.restore();
  }

  void _drawGlow(Canvas canvas, Offset center, double radius, double opacity) {
    if (opacity <= 0 || radius <= 0) return;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(255, 236, 173, 0.85 * opacity),
          Color.fromRGBO(255, 236, 173, 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _drawTrail(Canvas canvas, Offset from, Offset to, double progress, double opacity) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Color.fromRGBO(255, 255, 255, 0.5 * opacity);
    final end = Offset.lerp(from, to, progress)!;
    const dashLen = 8.0, gapLen = 6.0;
    final total = (end - from).distance;
    if (total < 1) return;
    final dir = (end - from) / total;
    double covered = 0;
    while (covered < total) {
      final segEnd = (covered + dashLen).clamp(0, total);
      canvas.drawLine(from + dir * covered, from + dir * segEnd.toDouble(), paint);
      covered += dashLen + gapLen;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ---- Faz 1: NISAN AL + FIRLAT (t: 0.00 - 0.50) ----
    // Oyunda surukleme SADECE YATAY (saga-sola nisan alma); birakinca obje
    // KENDI KENDINE yukari firliyor (parmakla surukleyip yukari tasima
    // YOK). Bu yuzden el: 1) sabit y'de saga-sola gidip-gelir (nisan),
    // 2) bir noktada "birakma" darbesi gosterir, 3) hayalet obje o andan
    // itibaren kendi basina hizla yukari firlar, el ise pad'de kalir/soner.
    // 0.00-0.08 el fade-in (pad'in biraz ustunde, sabit y)
    // 0.08-0.58 el sadece X ekseninde saga-sola gidip gelir (nisan alma)
    // 0.58-0.66 birakma (ring burst)
    // 0.66-0.90 hayalet obje KENDI BASINA hizla yukari firlar (el sabit/soner)
    // 0.90-1.00 sonlanip soner
    const p1Start = 0.0, p1End = 0.50;
    // ---- Faz 2: BIRLESME (t: 0.55 - 1.00) ----
    const p2Start = 0.55, p2End = 1.00;

    final targetX = padX + (padY - tableTopY) * 0.0; // ayni x hizasinda, sade bir gosterim
    final demoTargetY = tableTopY + (padY - tableTopY) * 0.34;
    final handY = padY - 34; // el, pad'in biraz ustunde sabit bir yukseklikte kalir
    const wiggleAmp = 52.0; // saga-sola nisan salinim genisligi (px)

    if (t >= p1Start && t < p1End) {
      final lt = (t - p1Start) / (p1End - p1Start); // 0..1 bu faz icinde
      final fadeIn = (lt / 0.08).clamp(0.0, 1.0);
      final fadeOut = lt > 0.90 ? (1 - (lt - 0.90) / 0.10).clamp(0.0, 1.0) : 1.0;
      final opacity = fadeIn * fadeOut;

      // --- yatay nisan salinimi: pad -> sol -> sag -> sabit atis noktasi ---
      final wiggleT = ((lt - 0.08) / 0.50).clamp(0.0, 1.0); // 0.08-0.58 arasi
      double aimX;
      if (wiggleT < 0.34) {
        aimX = Offset.lerp(Offset(padX, 0), Offset(padX - wiggleAmp, 0), _easeInOut(wiggleT / 0.34))!.dx;
      } else if (wiggleT < 0.68) {
        aimX = Offset.lerp(Offset(padX - wiggleAmp, 0), Offset(padX + wiggleAmp * 0.7, 0), _easeInOut((wiggleT - 0.34) / 0.34))!.dx;
      } else {
        aimX = Offset.lerp(Offset(padX + wiggleAmp * 0.7, 0), Offset(padX - 8, 0), _easeInOut((wiggleT - 0.68) / 0.32))!.dx;
      }

      final releaseX = padX - 8; // nisanin sabitlendigi son nokta
      final press = (lt > 0.58 && lt < 0.66) ? (1 - (lt - 0.58) / 0.08) : 0.0;

      // firlatma sonrasi: hayalet obje bagimsiz sekilde yukari kayar
      final flyT = ((lt - 0.66) / 0.24).clamp(0.0, 1.0);
      final flying = flyT > 0;
      final itemPos = flying
          ? Offset.lerp(Offset(releaseX, padY), Offset(releaseX, demoTargetY), _easeInOut(flyT))!
          : Offset(aimX, padY);

      final handOpacity = lt < 0.72 ? opacity : (opacity * (1 - ((lt - 0.72) / 0.10).clamp(0.0, 1.0)));
      final handPos = Offset(lt < 0.66 ? aimX : releaseX, handY);

      // yatay nisan izi (salinim boyunca sabit y'de kisa bir cizgi)
      if (lt < 0.66) {
        _drawTrail(canvas, Offset(padX - wiggleAmp, handY), Offset(padX + wiggleAmp * 0.7, handY), 1.0, opacity * 0.35);
      }

      final itemOpacity = (lt > 0.04 && lt < 0.96) ? opacity : 0.0;
      _drawImage(canvas, itemImage, itemPos, itemDiameter, itemOpacity * 0.95);

      if (handOpacity > 0) _drawHand(canvas, handPos, handOpacity, press: press.clamp(0.0, 1.0));
    }

    if (t >= p2Start && t < p2End) {
      final lt = (t - p2Start) / (p2End - p2Start);
      final fadeIn = (lt / 0.08).clamp(0.0, 1.0);
      final fadeOut = lt > 0.88 ? (1 - (lt - 0.88) / 0.12).clamp(0.0, 1.0) : 1.0;
      final opacity = fadeIn * fadeOut;

      final restX = targetX - 30;
      final restY = demoTargetY + 34;
      final startPos = Offset(targetX + 10, padY - 20);
      final approachT = _easeInOut(((lt - 0.06) / 0.30).clamp(0.0, 1.0));
      final movingPos = Offset.lerp(startPos, Offset(restX + itemDiameter * 0.72, restY), approachT)!;

      final contactT = ((lt - 0.34) / 0.10).clamp(0.0, 1.0); // temas anindaki patlama
      final mergedT = ((lt - 0.46) / 0.30).clamp(0.0, 1.0); // sonuc obje gosterimi

      if (lt < 0.46) {
        // iki ayri obje hala gorunur
        _drawImage(canvas, itemImage, Offset(restX, restY), itemDiameter, opacity);
        _drawImage(canvas, itemImage, movingPos, itemDiameter, opacity);
        if (contactT > 0 && contactT < 1) {
          _drawGlow(canvas, Offset.lerp(Offset(restX, restY), movingPos, 0.5)!, itemDiameter * (0.4 + contactT * 0.5), opacity);
        }
      } else {
        // birlesme sonucu: buyuyerek beliren tek obje
        final popScale = 0.7 + 0.3 * (1 - (1 - mergedT) * (1 - mergedT));
        final resultCenter = Offset.lerp(Offset(restX, restY), movingPos, 0.5)!;
        _drawGlow(canvas, resultCenter, itemDiameter * 0.75 * (1 - mergedT * 0.4), opacity * (1 - mergedT * 0.5));
        _drawImage(
          canvas,
          mergedImage ?? itemImage,
          resultCenter,
          itemDiameter,
          opacity,
          scale: popScale.clamp(0.0, 1.15),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HandTutorialPainter old) => old.t != t;
}
