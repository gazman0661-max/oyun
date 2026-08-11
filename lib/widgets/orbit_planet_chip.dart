import 'package:flutter/material.dart';

import 'rock_painter.dart';

/// Kucuk, dairesel GERCEK gezegen rozeti. Ana tup oyunundaki [paintRock]
/// fonksiyonunu (assets/planets/ altindaki gercek PNG'ler) aynen kullanir;
/// boylece Orbit Jam'deki hedef kuyrugu onizlemesi ve kargo rihtimi da
/// oyuncunun zaten bildigi gercek gezegen gorselleriyle gosterilir.
class PlanetChip extends StatelessWidget {
  final int colorIndex;
  final double size;
  final bool highlighted;

  const PlanetChip({
    super.key,
    required this.colorIndex,
    this.size = 20,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: highlighted
            ? Border.all(color: Colors.white, width: 2)
            : Border.all(color: Colors.white24, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _PlanetChipPainter(colorIndex)),
    );
  }
}

class _PlanetChipPainter extends CustomPainter {
  final int colorIndex;
  const _PlanetChipPainter(this.colorIndex);

  @override
  void paint(Canvas canvas, Size size) {
    paintRock(canvas, Offset.zero & size, colorIndex);
  }

  @override
  bool shouldRepaint(covariant _PlanetChipPainter oldDelegate) =>
      oldDelegate.colorIndex != colorIndex;
}
