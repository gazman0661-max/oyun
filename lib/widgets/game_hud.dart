import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../theme/app_colors.dart';

class GameHud extends StatelessWidget {
  final String stageLabel;
  final int moveCount;
  final String timeLabel;
  final VoidCallback onRestart;
  final VoidCallback onBack;
  /// Verilirse, geri butonunun yaninda kucuk bir "?" butonu gosterir —
  /// kullanici ilk-acilis ogreticisini istedigi zaman tekrar izleyebilir.
  final VoidCallback? onHelp;

  /// Bugun kalan ucretsiz "yeniden baslat" hakki — reset butonunun
  /// uzerinde kucuk bir rozet olarak gosterilir (hesap bazli, gunluk).
  final int resetsLeft;

  const GameHud({
    super.key,
    required this.stageLabel,
    required this.moveCount,
    required this.timeLabel,
    required this.onRestart,
    required this.onBack,
    this.onHelp,
    this.resetsLeft = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          _circleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          if (onHelp != null) ...[
            const SizedBox(width: 6),
            _circleButton(icon: Icons.help_outline_rounded, onTap: onHelp),
          ],
          const SizedBox(width: 6),
          Expanded(child: _stat(t('game_mission'), stageLabel)),
          Expanded(child: _stat(t('game_moves'), '$moveCount')),
          Expanded(child: _stat(t('game_time'), timeLabel)),
          _circleButton(
            icon: Icons.refresh_rounded,
            onTap: onRestart,
            badgeCount: resetsLeft,
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    VoidCallback? onTap,
    int? badgeCount,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.tubeGlass,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.tubeGlassBorder),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, size: 20, color: AppColors.textPrimary),
            ),
          ),
        ),
        if (badgeCount != null)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: badgeCount > 0 ? AppColors.success : AppColors.danger,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.spaceTop, width: 1.5),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
