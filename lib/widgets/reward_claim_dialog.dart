import 'dart:math';

import 'package:flutter/material.dart';

import '../game/daily_missions.dart' show PassReward;
import '../services/haptic_service.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';

/// Odul teslim ekraninda gosterilen tek bir kalem (ikon + miktar + ad).
class RewardItem {
  final String icon;
  final int amount;
  final String label;
  const RewardItem(this.icon, this.amount, this.label);
}

/// [PassReward] -> odul teslim ekrani kalemleri.
List<RewardItem> rewardItemsFor(PassReward r) => [
      if (r.meteors > 0) RewardItem('☄️', r.meteors, t('reward_meteor')),
      if (r.xp > 0) RewardItem('✨', r.xp, 'XP'),
      if (r.bomb > 0) RewardItem('💥', r.bomb, t('power_bomb')),
      if (r.swap > 0) RewardItem('🔄', r.swap, t('power_swap')),
      if (r.shake > 0) RewardItem('🌀', r.shake, t('power_shake')),
    ];

/// Tum odul teslimleri (gorev, seviye odulu, haftalik/aylik gorev) icin ortak,
/// animasyonlu "odul kazandin" ekrani: isinlar + kivilcimlar, ortada zipalayan
/// ikon, sirayla beliren odul kalemleri (sayilar yukari sayar).
Future<void> showRewardClaim(
  BuildContext context, {
  required String title,
  String heroIcon = '🎁',
  required List<RewardItem> items,
}) async {
  SoundService.instance.reward();
  HapticService.instance.medium();
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'reward',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) =>
        _RewardClaimView(title: title, heroIcon: heroIcon, items: items),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _RewardClaimView extends StatefulWidget {
  final String title;
  final String heroIcon;
  final List<RewardItem> items;
  const _RewardClaimView({
    required this.title,
    required this.heroIcon,
    required this.items,
  });

  @override
  State<_RewardClaimView> createState() => _RewardClaimViewState();
}

class _RewardClaimViewState extends State<_RewardClaimView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double p, double from, double to) =>
      ((p - from) / (to - from)).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final p = _c.value;
              final hero = Curves.elasticOut.transform(_seg(p, 0, 0.35));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 320,
                    height: 230,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(320, 230),
                          painter: _BurstPainter(p),
                        ),
                        Transform.scale(
                          scale: 0.25 + 0.75 * hero,
                          child: Text(widget.heroIcon,
                              style: const TextStyle(fontSize: 88)),
                        ),
                      ],
                    ),
                  ),
                  Opacity(
                    opacity: _seg(p, 0.15, 0.4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          shadows: [
                            Shadow(color: Color(0xFFFFB300), blurRadius: 16),
                            Shadow(
                                color: Colors.black,
                                blurRadius: 3,
                                offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < widget.items.length; i++)
                    _buildItem(widget.items[i], _seg(p, 0.3 + i * 0.1, 0.55 + i * 0.1)),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: _seg(p, 0.7, 0.95),
                    child: ElevatedButton(
                      onPressed: p >= 0.7 ? () => Navigator.of(context).pop() : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 42, vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        t('reward_ok'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildItem(RewardItem item, double local) {
    final shown = (item.amount * Curves.easeOut.transform(local)).round();
    return Opacity(
      opacity: local,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - local)),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF0F2A5F)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFBBF24), width: 1.5),
          ),
          child: Row(
            children: [
              Text(item.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '+$shown',
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Donen isinlar + disa saçilan kivilcimlar.
class _BurstPainter extends CustomPainter {
  final double p;
  _BurstPainter(this.p);

  static const _colors = [
    Color(0xFFFFD54F),
    Color(0xFFFFB300),
    Color(0xFF7DD3FC),
    Color(0xFFF9A8D4),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Isinlar
    final rayAlpha = (0.35 * (1 - p * 0.55)).clamp(0.0, 1.0);
    final rayPaint = Paint()
      ..color = const Color(0xFFFFE082).withValues(alpha: rayAlpha);
    final rot = p * 1.4;
    for (var k = 0; k < 12; k++) {
      final a = rot + k * pi / 6;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a - 0.1) * 150, c.dy + sin(a - 0.1) * 150)
        ..lineTo(c.dx + cos(a + 0.1) * 150, c.dy + sin(a + 0.1) * 150)
        ..close();
      canvas.drawPath(path, rayPaint);
    }
    // Kivilcimlar
    final e = Curves.easeOutCubic.transform((p / 0.8).clamp(0.0, 1.0));
    final fade = (1 - ((p - 0.5) / 0.5)).clamp(0.0, 1.0);
    for (var i = 0; i < 26; i++) {
      final a = i * 2 * pi / 26 + (i % 3) * 0.12;
      final dist = (70 + (i * 37) % 85) * e;
      final pos = Offset(c.dx + cos(a) * dist, c.dy + sin(a) * dist);
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: fade);
      canvas.drawCircle(pos, 2.5 + (i % 4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.p != p;
}
