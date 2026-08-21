import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/ad_service.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'meteor_icon.dart';

class WinDialog extends StatefulWidget {
  final int stage;
  final int stars;
  final int moveCount;
  final String timeLabel;
  final int score;
  final int gainedXp;
  final bool leveledUp;
  final int? newLevel;
  final VoidCallback onNextStage;
  final VoidCallback onClose;
  // 2x XP: reklam izlenip odul onaylandiginda cagrilir (ebeveyn ekran
  // burada PlayerProgress.addXp(gainedXp) cagirip XP'yi ikiye katlar).
  // AdService.showRewardedAdFlow'un placement analitigi icin Tup ve Orbit
  // modlari farkli bir placementId gecirir (bkz. game_screen.dart /
  // orbit_game_screen.dart).
  final VoidCallback onXpDoubled;
  final String doubleXpPlacementId;

  const WinDialog({
    super.key,
    required this.stage,
    required this.stars,
    required this.moveCount,
    required this.timeLabel,
    required this.score,
    required this.gainedXp,
    required this.leveledUp,
    required this.newLevel,
    required this.onNextStage,
    required this.onClose,
    required this.onXpDoubled,
    required this.doubleXpPlacementId,
  });

  @override
  State<WinDialog> createState() => _WinDialogState();
}

class _WinDialogState extends State<WinDialog> {
  bool _doubling = false;
  bool _doubled = false;

  Future<void> _handleDoubleXp() async {
    setState(() => _doubling = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🎬',
      title: t('win_doubleXpTitle'),
      placementId: widget.doubleXpPlacementId,
    );
    if (!mounted) return;
    if (granted == true) {
      widget.onXpDoubled();
      SoundService.instance.reward();
      setState(() {
        _doubling = false;
        _doubled = true;
      });
    } else {
      setState(() => _doubling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            const Icon(Icons.rocket_launch_rounded,
                color: AppColors.accentSoft, size: 42),
            const SizedBox(height: 10),
            Text(
              t('win_missionCompleted', {'n': '${widget.stage}'}),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final lit = i < widget.stars;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    lit ? Icons.star_rounded : Icons.star_border_rounded,
                    color: lit ? AppColors.warning : AppColors.textSecondary,
                    size: 30,
                  ),
                );
              }),
            ),
            if (widget.leveledUp) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t('win_levelUp', {'n': '${widget.newLevel}'}),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statColumn(t('win_moves'), '${widget.moveCount}'),
                _statColumn(t('win_time'), widget.timeLabel),
                _statColumn(t('win_score'), '${widget.score}'),
                _statColumn('XP', '+${widget.gainedXp}'),
              ],
            ),
            const SizedBox(height: 16),
            // 2x XP: opsiyonel, tek seferlik. Odul alinca buton yerine
            // "alindi" durumuna geciyor (daily_result_dialog.dart'taki
            // ayni pattern).
            if (!_doubled)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _doubling ? null : _handleDoubleXp,
                  icon: const Icon(Icons.movie_filter_rounded,
                      size: 18, color: Colors.black87),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          t('win_doubleXp', {
                            'n': '${widget.gainedXp}',
                            'm': '${EconomyConfig.winDoubleXpMeteorBonus}',
                          }),
                          style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const MeteorIcon(size: 16),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '✅ ${t('win_doubleXpClaimed', {
                              'm': '${EconomyConfig.winDoubleXpMeteorBonus}',
                            })}',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const MeteorIcon(size: 14),
                  ],
                ),
              ),
            const SizedBox(height: 8),
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
                onPressed: widget.onNextStage,
                child: Text(t('win_nextMission'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onClose,
              child: Text(
                t('win_backToMissions'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}
