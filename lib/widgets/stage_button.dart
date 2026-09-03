import 'package:flutter/material.dart';

import '../services/player_progress.dart';
import '../theme/app_colors.dart';

/// Bir bolum numarasini, kilit durumunu ve kazanilan yildizlari gosteren,
/// hem ana ekrandaki Orbit Jam izgarasinda hem de Tup Bolumleri ekraninda
/// ortak kullanilan buton.
class StageButton extends StatelessWidget {
  final int stage;
  final bool locked;
  final bool isCurrent;
  final StageStat? stat;
  final VoidCallback onTap;

  const StageButton({
    super.key,
    required this.stage,
    required this.locked,
    required this.isCurrent,
    required this.stat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tubeGlass,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? AppColors.accentSoft
                  : AppColors.tubeGlassBorder,
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                locked ? '🔒' : '$stage',
                style: TextStyle(
                  color: locked ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              if (!locked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final lit = stat != null && i < stat!.stars;
                    return Icon(
                      lit ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 12,
                      color: lit ? AppColors.warning : AppColors.textSecondary,
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
