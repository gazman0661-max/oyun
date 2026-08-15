import 'package:flutter/material.dart';

import '../models/tube.dart';
import '../theme/app_colors.dart';
import 'rock_painter.dart';

/// Bir "enerji tupunu" (sort oyunundaki tube) roket yakit kapsulu gibi
/// gorunecek sekilde tamamen Canvas/Path ile cizen widget.
/// Herhangi bir svg/png dosyasi ya da network istegi kullanilmaz.
/// TubeWidget'in govde/slot oranlarini (hem _TubePainter hem de disaridaki
/// pour animasyonu hesaplarinin AYNI degerleri kullanmasi icin) disari acar.
class TubeBodyGeometry {
  final double bodyTop;
  final double bodyBottom;
  final double left;
  final double right;
  final double bodyWidth;
  final double slotHeight;
  final double padding;
  const TubeBodyGeometry({
    required this.bodyTop,
    required this.bodyBottom,
    required this.left,
    required this.right,
    required this.bodyWidth,
    required this.slotHeight,
    required this.padding,
  });
}

TubeBodyGeometry tubeBodyGeometry(Size size, int capacity) {
  final w = size.width, h = size.height;
  final bodyTop = h * 0.085;
  final bodyBottom = h * 0.955;
  final bodyWidth = w * 0.72;
  final left = (w - bodyWidth) / 2;
  final right = left + bodyWidth;
  final slotHeight = (bodyBottom - bodyTop) / capacity;
  final padding = bodyWidth * 0.05;
  return TubeBodyGeometry(
    bodyTop: bodyTop,
    bodyBottom: bodyBottom,
    left: left,
    right: right,
    bodyWidth: bodyWidth,
    slotHeight: slotHeight,
    padding: padding,
  );
}

class TubeWidget extends StatelessWidget {
  final Tube tube;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double height;

  /// Pour animasyonu sirasinda, "havada ucan" klonlari olan en usttteki
  /// N tasi (kaynak tupte) gizlemek icin kullanilir — boylece ayni top
  /// hem tupte hem havada ikilenmis gorunmez (bkz. HTML'deki seg.opacity=0).
  final int hiddenFromTop;

  const TubeWidget({
    super.key,
    required this.tube,
    required this.selected,
    required this.onTap,
    this.width = 56,
    this.height = 190,
    this.hiddenFromTop = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _TubePainter(
              tube: tube,
              selected: selected,
              hiddenFromTop: hiddenFromTop,
            ),
          ),
        ),
      ),
    );
  }
}

class _TubePainter extends CustomPainter {
  final Tube tube;
  final bool selected;
  final int hiddenFromTop;

  _TubePainter({
    required this.tube,
    required this.selected,
    this.hiddenFromTop = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bodyTop = h * 0.085;
    final bodyBottom = h * 0.955;
    final bodyWidth = w * 0.72;
    final left = (w - bodyWidth) / 2;
    final right = left + bodyWidth;
    // Referans foto 1'deki gibi: govde neredeyse duz kenarli, hafif
    // yuvarlatilmis koseli (tam pill/kapsul degil, orta-derece rounded-rect).
    final cornerRadius = bodyWidth * 0.24;

    final bodyRect = Rect.fromLTRB(left, bodyTop, right, bodyBottom);
    final bodyRRect = RRect.fromRectAndCorners(
      bodyRect,
      topLeft: Radius.circular(cornerRadius * 0.6),
      topRight: Radius.circular(cornerRadius * 0.6),
      bottomLeft: Radius.circular(cornerRadius),
      bottomRight: Radius.circular(cornerRadius),
    );

    // Seciliyken dis parlama (glow)
    if (selected) {
      final glowPaint = Paint()
        ..color = AppColors.tubeSelectedGlow.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14);
      canvas.drawRRect(bodyRRect.inflate(2), glowPaint);
    }

    // --- Metalik ust "kapak" (referans foto 1'deki gibi: govde ile ayni
    // genislikte, kisa, yuvarlatilmis koseli bir bant; yatay silindirik
    // parlama + koyu kenarlar) ---
    final capWidth = bodyWidth * 1.02;
    final capLeft = (w - capWidth) / 2;
    final capHeight = h * 0.05;
    final capRect = Rect.fromLTWH(capLeft, bodyTop - capHeight * 0.82, capWidth, capHeight);
    final capRRect = RRect.fromRectAndRadius(capRect, Radius.circular(capHeight * 0.5));
    final capPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF7B84AC),
          Color(0xFFE2E7F7),
          Color(0xFF9AA2CC),
          Color(0xFF565F8C),
        ],
        stops: [0.0, 0.38, 0.68, 1.0],
      ).createShader(capRect);
    canvas.drawRRect(capRRect, capPaint);
    final capBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xAA20263F);
    canvas.drawRRect(capRRect, capBorderPaint);

    // --- Toplarin (energy) cizilecegi clip alani ---
    canvas.save();
    canvas.clipRRect(bodyRRect);

    // Cam/gövde arka plani (hafif transparan, koyu-lacivert)
    final glassPaint = Paint()..color = const Color(0x662B3466);
    canvas.drawRect(bodyRect, glassPaint);

    final capacity = tube.capacity;
    final slotHeight = (bodyBottom - bodyTop) / capacity;
    final padding = bodyWidth * 0.05;

    // --- Referans fotografdaki gibi ince grafik-kagidi (grid) dokusu ---
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0x1EAFC2FF);
    for (var i = 1; i < 3; i++) {
      final x = left + bodyWidth * i / 3;
      canvas.drawLine(Offset(x, bodyTop), Offset(x, bodyBottom), gridPaint);
    }
    final slotLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0x2AAFC2FF);
    for (var i = 1; i < capacity; i++) {
      final y = bodyTop + slotHeight * i;
      canvas.drawLine(Offset(left, y), Offset(right, y), slotLinePaint);
    }

    // Toplari (gezegenleri) alttan yukari dogru ciz.
    final visibleCount = (tube.balls.length - hiddenFromTop).clamp(0, tube.balls.length);
    for (var i = 0; i < visibleCount; i++) {
      final colorIndex = tube.balls[i];
      final slotTop = bodyBottom - (i + 1) * slotHeight;
      final rect = Rect.fromLTRB(
        left + padding,
        slotTop + padding * 0.6,
        right - padding,
        slotTop + slotHeight - padding * 0.6,
      );
      paintRock(canvas, rect, colorIndex);
    }

    // --- Cam parlama seridi (capraz, sol ustten asagiya dogru) ---
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(bodyRect)
      ..strokeWidth = w * 0.16
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(left + bodyWidth * 0.24, bodyTop + 4),
      Offset(left + bodyWidth * 0.38, bodyBottom - 8),
      shinePaint,
    );

    canvas.restore();

    // --- Cam govde cercevesi ---
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.6 : 1.8
      ..color = selected ? AppColors.tubeSelectedGlow : const Color(0xFFAAB4DD);
    canvas.drawRRect(bodyRRect, borderPaint);

    // --- Sag kenarda olcum cizgileri (tick mark) — referans fotografdaki
    // gibi her slot sinirinda kucuk yatay cizgiler ---
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xCCE4E9FF);
    for (var i = 0; i <= capacity; i++) {
      final y = bodyTop + slotHeight * i;
      canvas.drawLine(
        Offset(right + 2, y),
        Offset(right + w * 0.05, y),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TubePainter oldDelegate) {
    // Tube nesnesi GameController icinde yerinde (in-place) mutasyona
    // ugradigi icin referans karsilastirmasi guvenilir degil; guvenli
    // tarafta kalmak icin her zaman yeniden ciziyoruz (maliyeti dusuk).
    return true;
  }
}
