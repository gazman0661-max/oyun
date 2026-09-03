import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';
import 'orbit_game_screen.dart';

/// "Görevler" ekranı: haftalık, aylık, takımyıldız ve kuyruklu yıldız
/// görevlerini TAM EKRAN olarak gösterir. Eskiden ana ekranda katlanır
/// (accordion) bir kart olarak açılıp kapanıyordu; artık ana ekrandaki
/// görevler kartına dokununca doğrudan bu ayrı ekrana yönlendiriliyor —
/// ana ekran sadeleşir, görev detayları kendi sayfasında yaşar.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final PlayerProgress _progress = PlayerProgress.instance;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgressChanged);
    // Kuyruklu Yıldız geri sayımını canlı tutmak için periyodik yenileme.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _progress.removeListener(_onProgressChanged);
    super.dispose();
  }

  Future<void> _openComet() async {
    SoundService.instance.buttonTap();
    if (!PlayerProgress.cometEventActive()) return;
    if (_progress.cometCompletedThisEvent) {
      CustomToast.show(context, t('comet_alreadyDone'),
          icon: '☄️', accentColor: AppColors.success);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrbitGameScreen(isComet: true)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _claimWeeklyReward() async {
    final reward = _progress.weeklyQuest.reward;
    final granted = await _progress.claimWeeklyReward();
    if (!granted || !mounted) return;
    SoundService.instance.reward();
    CustomToast.show(
      context,
      t('resupply_rewardMeteor', {'n': '$reward'}),
      icon: '☄️',
      accentColor: AppColors.success,
    );
  }

  Future<void> _claimMonthlyReward() async {
    final reward = _progress.monthlyQuest.reward;
    final granted = await _progress.claimMonthlyReward();
    if (!granted || !mounted) return;
    SoundService.instance.reward();
    CustomToast.show(
      context,
      t('resupply_rewardMeteor', {'n': '$reward'}),
      icon: '🌕',
      accentColor: AppColors.success,
    );
  }

  Future<void> _claimConstellationReward() async {
    final def = _progress.activeConstellation;
    final granted = await _progress.claimConstellationReward();
    if (!granted || !mounted) return;
    SoundService.instance.reward();
    CustomToast.show(
      context,
      t('constellation_rewardBadge', {'name': t(def.nameKey)}),
      icon: def.badgeIcon,
      accentColor: AppColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimary, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text('🎯', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    t('home_tasksTitle'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _buildWeeklyQuestCard(),
                  const SizedBox(height: 10),
                  _buildMonthlyQuestCard(),
                  const SizedBox(height: 10),
                  _buildConstellationCard(),
                  const SizedBox(height: 10),
                  _buildCometEventCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Haftalık Görev" kartı: bu hafta N bölüm bitirince meteor ödülü
  /// açılır. Görsel dili _buildResupplyCard ile tutarlı (gradyan kart +
  /// ilerleme metni), ama reklam yok — tamamen ücretsiz, oynama bazlı
  /// bir ödül.
  Widget _buildWeeklyQuestCard() {
    final quest = _progress.weeklyQuest;
    final target = quest.target;
    final done = min(_progress.weeklyQuestProgress, target);
    final ready = _progress.weeklyGoalReady;
    final claimed = _progress.weeklyRewardClaimed && !ready;
    final progress = target == 0 ? 0.0 : done / target;
    final subtitleKey = switch (quest.type) {
      WeeklyQuestType.stagesCleared => 'home_weeklySubtitle',
      WeeklyQuestType.cleanStages => 'home_weeklySubtitle_clean',
      WeeklyQuestType.perfectStars => 'home_weeklySubtitle_perfect',
      WeeklyQuestType.playDays => 'home_weeklySubtitle_playDays',
      WeeklyQuestType.spendMeteors => 'home_weeklySubtitle_spend',
    };
    final progressKey = switch (quest.type) {
      WeeklyQuestType.playDays => 'home_weeklyProgress_days',
      WeeklyQuestType.spendMeteors => 'home_weeklyProgress_meteors',
      _ => 'home_weeklyProgress',
    };

    return GestureDetector(
      onTap: ready ? _claimWeeklyReward : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0EA5E9), Color(0xFF22C55E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Opacity(
          opacity: claimed ? 0.6 : 1.0,
          child: Row(
            children: [
              const Text('🗓️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('home_weeklyTitle'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      t(subtitleKey, {
                        'n': '$target',
                        'r': '${quest.reward}',
                      }),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.black.withValues(alpha: 0.25),
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      claimed
                          ? t('home_weeklyClaimed')
                          : t(progressKey,
                              {'done': '$done', 'total': '$target'}),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (ready) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(t('home_weeklyClaim'),
                      style: const TextStyle(
                          color: Color(0xFF0EA5E9),
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Aylık Görev" kartı: _buildWeeklyQuestCard ile BİREBİR AYNI görsel
  /// dil ve mantık, sadece periyot bir takvim ayı ve hedefler/ödüller
  /// daha büyük (bkz. EconomyConfig.monthlyQuestByMonth).
  Widget _buildMonthlyQuestCard() {
    final quest = _progress.monthlyQuest;
    final target = quest.target;
    final done = min(_progress.monthlyQuestProgress, target);
    final ready = _progress.monthlyGoalReady;
    final claimed = _progress.monthlyRewardClaimed && !ready;
    final progress = target == 0 ? 0.0 : done / target;
    final subtitleKey = switch (quest.type) {
      MonthlyQuestType.stagesCleared => 'home_monthlySubtitle',
      MonthlyQuestType.cleanStages => 'home_monthlySubtitle_clean',
      MonthlyQuestType.perfectStars => 'home_monthlySubtitle_perfect',
      MonthlyQuestType.playDays => 'home_monthlySubtitle_playDays',
      MonthlyQuestType.spendMeteors => 'home_monthlySubtitle_spend',
    };
    final progressKey = switch (quest.type) {
      MonthlyQuestType.playDays => 'home_weeklyProgress_days',
      MonthlyQuestType.spendMeteors => 'home_weeklyProgress_meteors',
      _ => 'home_weeklyProgress',
    };

    return GestureDetector(
      onTap: ready ? _claimMonthlyReward : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Opacity(
          opacity: claimed ? 0.6 : 1.0,
          child: Row(
            children: [
              const Text('🌕', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('home_monthlyTitle'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      t(subtitleKey, {
                        'n': '$target',
                        'r': '${quest.reward}',
                      }),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.black.withValues(alpha: 0.25),
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      claimed
                          ? t('home_monthlyClaimed')
                          : t(progressKey,
                              {'done': '$done', 'total': '$target'}),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (ready) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(t('home_weeklyClaim'),
                      style: const TextStyle(
                          color: Color(0xFFA855F7),
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Takımyıldız" kartı: SADECE Orbit modunda kazanılan yıldızlarla
  /// dolan, haftalık sıfırlanan ayrı bir katman. Nokta/yıldız dizisi
  /// ilerlemeyi görsel olarak gösterir (sayı yerine "gökyüzü doluyor"
  /// hissi) — weeklyQuest ile aynı hafta içinde ama bağımsız ilerler.
  Widget _buildConstellationCard() {
    final def = _progress.activeConstellation;
    final done = _progress.constellationProgress;
    final ready = _progress.constellationGoalReady;
    final claimed = _progress.weeklyConstellationClaimed && !ready;

    return GestureDetector(
      onTap: ready ? _claimConstellationReward : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6D28D9), Color(0xFF312E81)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Opacity(
          opacity: claimed ? 0.6 : 1.0,
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('constellation_title'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      t(def.nameKey),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List.generate(def.pointCount, (i) {
                        final filled = i < done;
                        return Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 14,
                          color: filled ? Colors.white : Colors.white38,
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      claimed
                          ? t('constellation_claimed')
                          : t('constellation_progress',
                              {'done': '$done', 'total': '${def.pointCount}'}),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                    // Ödülün meteor DEĞİL, kalıcı bir rozet olduğunu
                    // açıkça göster — bu katmanın diğer görevlerden
                    // (haftalık/aylık/Kuyruklu Yıldız) neden farklı bir
                    // "dönme sebebi" olduğu burada okunur olmalı.
                    if (!claimed) ...[
                      const SizedBox(height: 4),
                      Text(
                        t('constellation_badgeReward',
                            {'icon': def.badgeIcon}),
                        style: const TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.w600,
                            fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              if (ready) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(t('home_weeklyClaim'),
                      style: const TextStyle(
                          color: Color(0xFF6D28D9),
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Kuyruklu Yıldız" kartı: periyodik, zaman sınırlı özel bir Orbit
  /// tahtası. Pencere kapalıyken bir sonraki açılışa kalan süreyi,
  /// açıkken ise "oyna"/"bitirildi" durumunu gösterir. _ticker (30sn'de
  /// bir setState) sayesinde geri sayım otomatik güncellenir.
  Widget _buildCometEventCard() {
    final active = PlayerProgress.cometEventActive();
    final done = _progress.cometCompletedThisEvent;
    final remaining = PlayerProgress.cometTimeRemaining();
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final timeLabel = hours > 0
        ? t('comet_timeHm', {'h': '$hours', 'm': '$minutes'})
        : t('comet_timeM', {'m': '$minutes'});

    return GestureDetector(
      onTap: (active && !done) ? _openComet : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFF9D174D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Opacity(
          opacity: active ? 1.0 : 0.6,
          child: Row(
            children: [
              const Text('☄️', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('comet_title'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      t('comet_subtitle', {
                        'r': '${EconomyConfig.cometMeteorReward}',
                      }),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      !active
                          ? t('comet_nextIn', {'time': timeLabel})
                          : done
                              ? t('comet_done')
                              : t('comet_closesIn', {'time': timeLabel}),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (active && !done) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(t('comet_play'),
                      style: const TextStyle(
                          color: Color(0xFFEA580C),
                          fontWeight: FontWeight.w800,
                          fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
