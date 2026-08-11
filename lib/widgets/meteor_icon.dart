import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Meteor (para birimi) ikonu — gercek bir goktasi/kuyrukluyildiz
/// fotografindan (assets/currency/meteor.png, seffaf arka planla islenmis)
/// uretilir. Onceki surum tamamen CustomPainter ile vektorel ciziliyordu;
/// widget API'si (MeteorIcon(size: ...)) ayni kaldigi icin tum cagiran
/// yerler (MeteorBadge, orbit_game_screen.dart) degismeden calisir.
class MeteorIcon extends StatelessWidget {
  final double size;
  const MeteorIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/currency/meteor.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Ana ekran üst bar için: sağ üstte "🔶 sayı" formatındaki para birimi
/// rozetlerinin meteor sürümü.
class MeteorBadge extends StatelessWidget {
  final int amount;
  final VoidCallback? onTap;
  const MeteorBadge({super.key, required this.amount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.tubeGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.tubeGlassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MeteorIcon(size: 16),
            const SizedBox(width: 5),
            Text(
              '$amount',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
