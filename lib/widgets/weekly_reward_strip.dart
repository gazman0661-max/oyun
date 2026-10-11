import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'meteor_icon.dart';

/// Haftalık ödül şeridi (Empires & Puzzles tarzı, Pazartesi-Pazar sabit
/// takvim haftası): her gün SADECE o gün alınabilir bir ödül, kaçırılan
/// günün ödülü o hafta için kalıcı olarak kaybedilir. Pazar kutusu,
/// Pzt-Cmt'nin hepsi alınmışsa ekstra bir "kusursuz hafta" bonusu da verir.
///
/// Ana ekranda SÜREKLİ görünmez — artık sadece [showPopup] ile, uygulama
/// açılışında bir kereliğine popup olarak gösterilir; bugünün ödülü
/// alınınca (veya popup kapatılınca) o oturumda tekrar çıkmaz, bir
/// sonraki gün tekrar açılır.
///
/// Tüm durum PlayerProgress'te tutulur (bkz. weeklyRewardClaimedDays /
/// claimWeeklyLoginReward) — bu widget sadece o state'in üstüne ince bir
/// arayüz katmanıdır, kendi başına mantık taşımaz.
class WeeklyRewardStrip extends StatefulWidget {
  /// true ise, bugünün ödülü başarıyla alındığında bu widget'ı saran
  /// dialog'u (bkz. [showPopup]) otomatik olarak kapatır.
  final bool isPopup;

  const WeeklyRewardStrip({super.key, this.isPopup = false});

  /// Uygulama açılışında haftalık ödül takvimini popup olarak gösterir.
  /// Bugünün ödülü zaten alınmışsa hiçbir şey yapmaz (çağıran taraf zaten
  /// bunu kontrol etmeli, ama burada da ikinci bir güvenlik olarak
  /// tekrarlanır).
  static Future<void> showPopup(BuildContext context) async {
    if (PlayerProgress.instance.weeklyRewardIsTodayClaimed()) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t('weeklyReward_title'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const WeeklyRewardStrip(isPopup: true),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<WeeklyRewardStrip> createState() => _WeeklyRewardStripState();
}

class _WeeklyRewardStripState extends State<WeeklyRewardStrip> {
  static const _dayLetterKeys = [
    'weeklyReward_mon',
    'weeklyReward_tue',
    'weeklyReward_wed',
    'weeklyReward_thu',
    'weeklyReward_fri',
    'weeklyReward_sat',
    'weeklyReward_sun',
  ];

  Future<void> _claim(int dayIndex) async {
    final todayIndex = PlayerProgress.instance.weeklyRewardTodayIndex();
    if (dayIndex != todayIndex) return; // sadece bugünün kutusu tıklanabilir
    SoundService.instance.buttonTap();
    final result = await PlayerProgress.instance.claimWeeklyLoginReward();
    if (result == null || !mounted) return;
    SoundService.instance.reward();
    await showDialog<void>(
      context: context,
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
              Text(result.isSundayBonus ? '🎁' : '☄️',
                  style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                t('weeklyReward_claimedTitle'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MeteorIcon(size: 20),
                  const SizedBox(width: 6),
                  Text(
                    '+${result.totalMeteor}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              if (result.isSundayBonus) ...[
                const SizedBox(height: 6),
                Text(
                  t('weeklyReward_perfectWeekBonus',
                      {'n': '${result.bonusMeteor}'}),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
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
                  child: Text(
                    t('resupply_close'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
    // Popup modundaysa (uygulama açılışı), bugünün ödülü alındıktan ve
    // kutlama diyaloğu kapatıldıktan sonra bu widget'ı saran dış popup'ı
    // da otomatik kapat — kullanıcı iki kere kapatmak zorunda kalmasın.
    if (widget.isPopup && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = PlayerProgress.instance;
    final todayIndex = progress.weeklyRewardTodayIndex();
    final sundayBonusAlive = progress.weeklyRewardSundayBonusEligible();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tubeGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tubeGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎁', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(
                t('weeklyReward_title'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(7, (i) {
              final isLast = i == 6;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 4),
                  child: _DayBox(
                    label: t(_dayLetterKeys[i]),
                    meteorAmount: EconomyConfig.weeklyRewardMeteor[i],
                    state: progress.weeklyRewardDayState(i),
                    isSunday: isLast,
                    sundayBonusAlive: isLast ? sundayBonusAlive : false,
                    onTap: i == todayIndex ? () => _claim(i) : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DayBox extends StatelessWidget {
  final String label;
  final int meteorAmount;
  final WeeklyRewardDayState state;
  final bool isSunday;
  final bool sundayBonusAlive;
  final VoidCallback? onTap;

  const _DayBox({
    required this.label,
    required this.meteorAmount,
    required this.state,
    required this.isSunday,
    required this.sundayBonusAlive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool claimable = state == WeeklyRewardDayState.claimableToday;
    final bool claimed = state == WeeklyRewardDayState.claimed;
    final bool missed = state == WeeklyRewardDayState.missed;

    final Color boxColor = claimable
        ? AppColors.accent.withOpacity(0.22)
        : claimed
            ? AppColors.success.withOpacity(0.14)
            : AppColors.surface;
    final Color borderColor = claimable
        ? AppColors.accent
        : claimed
            ? AppColors.success.withOpacity(0.5)
            : AppColors.tubeGlassBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: claimable ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: missed
                    ? AppColors.textSecondary.withOpacity(0.5)
                    : AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            if (claimed)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 16)
            else if (missed)
              Icon(Icons.close_rounded,
                  color: AppColors.textSecondary.withOpacity(0.4), size: 16)
            else ...[
              MeteorIcon(size: isSunday ? 18 : 14),
              const SizedBox(height: 2),
              Text(
                '$meteorAmount',
                style: TextStyle(
                  color: claimable
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (isSunday && sundayBonusAlive && !claimed) ...[
              const SizedBox(height: 2),
              const Text('🎁', style: TextStyle(fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}
