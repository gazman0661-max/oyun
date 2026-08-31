import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../services/player_progress.dart';
import '../theme/app_colors.dart';
import 'custom_toast.dart';
import 'rock_painter.dart';

const int kTotalPlanets = 10;

class _PlanetOrbPainter extends CustomPainter {
  final int index;
  const _PlanetOrbPainter(this.index);

  @override
  void paint(Canvas canvas, Size size) {
    paintRock(canvas, Offset.zero & size, index);
  }

  @override
  bool shouldRepaint(covariant _PlanetOrbPainter oldDelegate) =>
      oldDelegate.index != index;
}

/// Bir gezegen dairesel kucuk gorseli (kesfedilmisse gercek foto —
/// diger ekranlardaki [paintRock] ile ayni contain-fit cizim, kesfedilmemis
/// olan icin kilitli silindir).
class _PlanetOrb extends StatelessWidget {
  final int index;
  final bool discovered;
  final double size;
  const _PlanetOrb({
    required this.index,
    required this.discovered,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.tubeGlass,
        border: Border.all(
          color: discovered ? AppColors.accentSoft : AppColors.surfaceBorder,
          width: 2,
        ),
        boxShadow: discovered
            ? [
                BoxShadow(
                  color: AppColors.accentSoft.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: !discovered
          ? Icon(Icons.lock_rounded,
              color: AppColors.textSecondary, size: size * 0.4)
          : CustomPaint(painter: _PlanetOrbPainter(index)),
    );
  }
}

/// Bolum kazanildiktan sonra, o bolumde ilk kez ortaya cikan gezegen(ler)
/// icin gosterilen kisa "kesif" diyalogu. Kazanma ekranindan (WinDialog)
/// once cagrilir.
Future<void> showPlanetDiscoveryDialog(
  BuildContext context,
  List<int> newlyDiscovered,
) async {
  if (newlyDiscovered.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('discovery_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                for (final idx in newlyDiscovered)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PlanetOrb(index: idx, discovered: true, size: 72),
                      const SizedBox(height: 8),
                      Text(
                        t('planet_${idx}_name'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              newlyDiscovered.length == 1
                  ? t('planet_${newlyDiscovered.first}_fact')
                  : t('discovery_addedToSystem'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t('discovery_continue'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Ana ekrandan acilan, oyuncunun su ana kadar kesfettigi tum gezegenleri
/// (ve kilitli kalanlari) gosteren kodeks/koleksiyon paneli.
class PlanetCodexSheet extends StatelessWidget {
  const PlanetCodexSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const PlanetCodexSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discovered = PlayerProgress.instance.discoveredPlanets;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              t('codex_sheetTitle'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('codex_cardSubtitle', {'n': '${discovered.length}'}),
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: kTotalPlanets,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 14,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, i) {
                final isOn = discovered.contains(i);
                return GestureDetector(
                  onTap: () {
                    if (!isOn) {
                      CustomToast.show(context, t('codex_lockedHint'),
                          icon: '🔒', accentColor: AppColors.warning);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PlanetOrb(index: i, discovered: isOn),
                      const SizedBox(height: 6),
                      Text(
                        isOn ? t('planet_${i}_name') : t('codex_locked'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOn
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('codex_close'),
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
