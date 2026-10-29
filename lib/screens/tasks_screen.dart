import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/daily_missions.dart';
import '../game/economy_config.dart';
import '../services/haptic_service.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';
import '../widgets/reward_claim_dialog.dart';
import '../widgets/tutorial_overlay.dart';
import 'planet_merge_screen.dart';

/// \"Galaksi Yolu\" ekranı: üstte sezon sayacı, seviye çubuğu ve iki sekme.
///
/// - GÖREVLER: günlük görev kartları (3 adet, her gün yenilenir) + günlük
///   bonus + özel görevler (haftalık, aylık, takımyıldız, kuyruklu yıldız).
/// - ÖDÜLLER: Yıldız puanıyla açılan seviye ödülleri (meteor, XP,
///   güçlendiriciler). Sezon her ay başı sıfırlanır.
///
/// Tüm ödül tesliminde ortak animasyonlu [showRewardClaim] ekranı gösterilir.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

enum _TileState { progress, claimable, claimed, locked, play }

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  final PlayerProgress _progress = PlayerProgress.instance;
  Timer? _ticker;
  int _tab = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  static const Color _gold = Color(0xFFFBBF24);
  static const Color _green = Color(0xFF22C55E);

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgressChanged);
    // Geri sayımları canlı tutmak için periyodik yenileme.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTutorialTour());
  }

  TutorialHandle? _tutHandle;

  /// Ana ekran turundan gelindiyse iki kisa balonla bu ekrani anlatir.
  Future<void> _maybeTutorialTour() async {
    final tut = TutorialService.instance;
    if (!tut.tasksTourPending || !mounted) return;
    tut.tasksTourPending = false;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    var h = TutorialOverlay.show(
        context, const TutorialStep(textKey: 'tut_h_tasks_in1'));
    _tutHandle = h;
    if (await h.done) {
      await tut.skip();
      return;
    }
    if (!mounted) return;
    h = TutorialOverlay.show(
        context, const TutorialStep(textKey: 'tut_h_tasks_in2'));
    _tutHandle = h;
    if (await h.done) await tut.skip();
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tutHandle?.close();
    _pulse.dispose();
    _progress.removeListener(_onProgressChanged);
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------
  String _fmt(Duration d) {
    final days = d.inDays;
    final h = d.inHours % 24;
    final m = d.inMinutes % 60;
    if (days > 0) return '$days${t('pass_unitD')} $h${t('pass_unitH')}';
    return '$h${t('pass_unitH')} $m${t('pass_unitM')}';
  }

  List<RewardItem> _itemsFor(PassReward r) => [
        if (r.meteors > 0) RewardItem('☄️', r.meteors, t('reward_meteor')),
        if (r.xp > 0) RewardItem('✨', r.xp, 'XP'),
        if (r.bomb > 0) RewardItem('💥', r.bomb, t('power_bomb')),
        if (r.swap > 0) RewardItem('🔄', r.swap, t('power_swap')),
        if (r.shake > 0) RewardItem('🌀', r.shake, t('power_shake')),
      ];

  String _missionParam(DailyMissionDef d) {
    if (d.metric == MissionMetric.bestTier) {
      return t('pm_planet_${d.target}');
    }
    return '${d.target}';
  }

  // ---------------------------------------------------------------------
  // Ödül alma
  // ---------------------------------------------------------------------
  Future<void> _claimMission(DailyMissionDef d) async {
    final pts = await _progress.claimMission(d);
    if (pts <= 0 || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleMission'),
      heroIcon: d.icon,
      items: [RewardItem('⭐', pts, t('pass_pointsLabel'))],
    );
  }

  Future<void> _claimBonus() async {
    final pts = await _progress.claimMissionBonus();
    if (pts <= 0 || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleMission'),
      heroIcon: '🎁',
      items: [RewardItem('⭐', pts, t('pass_pointsLabel'))],
    );
  }

  Future<void> _claimLevel(int level) async {
    final r = await _progress.claimPassLevel(level);
    if (r == null || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleLevel', {'n': '$level'}),
      heroIcon: level == PassConfig.maxLevel ? '🏆' : '🎁',
      items: _itemsFor(r),
    );
  }

  Future<void> _claimAllLevels() async {
    var meteors = 0, xp = 0, bomb = 0, swap = 0, shake = 0;
    final upTo = _progress.passLevel;
    for (var l = 1; l <= upTo; l++) {
      final r = await _progress.claimPassLevel(l);
      if (r == null) continue;
      meteors += r.meteors;
      xp += r.xp;
      bomb += r.bomb;
      swap += r.swap;
      shake += r.shake;
    }
    if (!mounted) return;
    final items = _itemsFor(PassReward(
      meteors: meteors,
      xp: xp,
      bomb: bomb,
      swap: swap,
      shake: shake,
    ));
    if (items.isEmpty) return;
    await showRewardClaim(
      context,
      title: t('reward_titleQuest'),
      heroIcon: '🎁',
      items: items,
    );
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
      MaterialPageRoute(
          builder: (_) => const PlanetMergeScreen(mode: MergeMode.comet)),
    );
    // Ana menu muzigine geri don (merge ekrani kendi muzigini calar).
    SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
    if (mounted) setState(() {});
  }

  Future<void> _claimWeeklyReward() async {
    final reward = _progress.weeklyQuest.reward;
    final granted = await _progress.claimWeeklyReward();
    if (!granted || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleQuest'),
      heroIcon: '🗓️',
      items: [
        RewardItem('☄️', reward, t('reward_meteor')),
        RewardItem('⭐', PassConfig.weeklyQuestPoints, t('pass_pointsLabel')),
      ],
    );
  }

  Future<void> _claimMonthlyReward() async {
    final reward = _progress.monthlyQuest.reward;
    final granted = await _progress.claimMonthlyReward();
    if (!granted || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleQuest'),
      heroIcon: '🌕',
      items: [
        RewardItem('☄️', reward, t('reward_meteor')),
        RewardItem('⭐', PassConfig.monthlyQuestPoints, t('pass_pointsLabel')),
      ],
    );
  }

  Future<void> _claimConstellationReward() async {
    final def = _progress.activeConstellation;
    final granted = await _progress.claimConstellationReward();
    if (!granted || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleQuest'),
      heroIcon: def.badgeIcon,
      items: [RewardItem(def.badgeIcon, 1, t(def.nameKey))],
    );
  }

  void _showHelp() {
    SoundService.instance.buttonTap();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF12306B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _gold, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌟', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text(
                t('pass_helpTitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t('pass_helpBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  t('reward_ok'),
                  style: const TextStyle(
                      color: _gold, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Ana yapı
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1433),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12306B), Color(0xFF0A1433)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabs(),
              _buildPassBar(),
              Expanded(
                child: _tab == 0 ? _buildTasksTab() : _buildRewardsTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundIconButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF22D3EE), Color(0xFF0F766E)],
        ),
        border: Border(bottom: BorderSide(color: _gold, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _roundIconButton(
                  Icons.help_outline_rounded, const Color(0xFF3B82F6), _showHelp),
              Expanded(
                child: Column(
                  children: [
                    const Text('🌟', style: TextStyle(fontSize: 26)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        t('pass_title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          shadows: [
                            Shadow(
                                color: Color(0xFF0B3B52),
                                blurRadius: 2,
                                offset: Offset(0, 3)),
                            Shadow(color: Color(0xFF0B3B52), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _roundIconButton(Icons.close_rounded, const Color(0xFFDC2626),
                  () => Navigator.of(context).pop()),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: _gold),
                const SizedBox(width: 6),
                Text(
                  t('pass_endsIn', {'t': _fmt(_progress.passTimeRemaining)}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final taskDot = _progress.missionClaimableCount > 0;
    final rewardDot = _progress.passClaimableCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(child: _tabButton(t('pass_tabTasks'), 0, taskDot)),
          const SizedBox(width: 8),
          Expanded(child: _tabButton(t('pass_tabRewards'), 1, rewardDot)),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index, bool dot) {
    final sel = _tab == index;
    return GestureDetector(
      onTap: () {
        if (_tab == index) return;
        SoundService.instance.buttonTap();
        HapticService.instance.tick();
        setState(() => _tab = index);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: sel
                  ? const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : null,
              color: sel ? null : const Color(0xFF14284F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel ? const Color(0xFF93C5FD) : const Color(0xFF1E3A6B),
                width: 2,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: sel ? Colors.white : const Color(0xFF6B84B8),
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          if (dot)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _levelBadge(int n, bool active) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: active
              ? const [Color(0xFFFDE68A), Color(0xFFF59E0B)]
              : const [Color(0xFF1E3A6B), Color(0xFF14284F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(
          color: active ? Colors.white : const Color(0xFF3B5A9A),
          width: 2,
        ),
      ),
      child: Text(
        '$n',
        style: TextStyle(
          color: active ? const Color(0xFF3B2A00) : const Color(0xFF8FA6D6),
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _bar(double value, String text, {Color color = const Color(0xFF38BDF8)}) {
    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0).toDouble(),
              minHeight: 22,
              backgroundColor: const Color(0xFF0A1433),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassBar() {
    final lvl = _progress.passLevel;
    final maxed = lvl >= PassConfig.maxLevel;
    final inLvl = _progress.passPointsInLevel;
    final frac = maxed ? 1.0 : inLvl / PassConfig.pointsPerLevel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          _levelBadge(lvl, true),
          const SizedBox(width: 8),
          Expanded(
            child: _bar(
              frac,
              '$inLvl/${PassConfig.pointsPerLevel}',
              color: const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 8),
          _levelBadge(min(lvl + 1, PassConfig.maxLevel), false),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFFA5B4D6),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  Widget _pulseButton(String label, Color color) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Transform.scale(
        scale: 1 + 0.07 * _pulse.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 4 + 10 * _pulse.value,
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // GÖREVLER sekmesi
  // ---------------------------------------------------------------------
  Widget _buildTasksTab() {
    final missions = _progress.todaysMissions;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _sectionTitle(
          t('pass_dailyTitle'),
          trailing: t('pass_refreshIn', {'t': _fmt(_progress.missionResetIn)}),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final d in missions) _missionCard(d)],
          ),
        ),
        const SizedBox(height: 10),
        _buildBonusTile(missions),
        const SizedBox(height: 18),
        _sectionTitle(t('pass_specialTitle')),
        const SizedBox(height: 10),
        _buildWeeklyTile(),
        const SizedBox(height: 10),
        _buildMonthlyTile(),
        const SizedBox(height: 10),
        _buildConstellationTile(),
        const SizedBox(height: 10),
        _buildCometTile(),
      ],
    );
  }

  Widget _missionCard(DailyMissionDef d) {
    final isTier = d.metric == MissionMetric.bestTier;
    final done = _progress.missionDone(d);
    final claimed = _progress.missionIsClaimed(d);
    final value = isTier ? (done ? 1 : 0) : _progress.missionValue(d);
    final total = isTier ? 1 : d.target;
    final title = t(d.titleKey, {'n': _missionParam(d)});

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: (done && !claimed) ? () => _claimMission(d) : null,
          child: Opacity(
            opacity: claimed ? 0.55 : 1.0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0B5CAD), Color(0xFF0A3A75)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (done && !claimed) ? _gold : const Color(0xFF7DB5E8),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: Center(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.28),
                      border: Border.all(color: _gold, width: 2),
                    ),
                    child: Text(d.icon, style: const TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(height: 10),
                  _bar(total == 0 ? 0.0 : value / total, '$value/$total'),
                  const Spacer(),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: Center(
                      child: claimed
                          ? Text(
                              '✓ ${t('pass_claimed')}',
                              style: const TextStyle(
                                color: _green,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            )
                          : done
                              ? _pulseButton(t('pass_claim'), _green)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '+${d.points}',
                                      style: const TextStyle(
                                        color: Color(0xFFFFE082),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Text('⭐',
                                        style: TextStyle(fontSize: 16)),
                                  ],
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBonusTile(List<DailyMissionDef> missions) {
    final claimedCount =
        missions.where((d) => _progress.missionIsClaimed(d)).length;
    final ready = _progress.missionBonusReady;
    final claimed = _progress.missionBonusClaimed;
    return _tile(
      icon: '🎁',
      title: t('pass_bonusTitle'),
      progress: claimedCount / missions.length,
      progressText: '$claimedCount/${missions.length}',
      colors: const [Color(0xFF0F766E), Color(0xFF115E59)],
      rewardText: '+${PassConfig.dailyBonusPoints} ⭐',
      state: ready
          ? _TileState.claimable
          : claimed
              ? _TileState.claimed
              : _TileState.progress,
      onTap: ready ? _claimBonus : null,
    );
  }

  /// Özel görevler için ortak kart: ikon, başlık, ilerleme ve sağda ödül /
  /// alma butonu.
  Widget _tile({
    required String icon,
    required String title,
    String? subtitle,
    double? progress,
    String? progressText,
    Widget? extra,
    required List<Color> colors,
    String? rewardText,
    required _TileState state,
    VoidCallback? onTap,
    String? actionLabel,
  }) {
    final highlight =
        state == _TileState.claimable || state == _TileState.play;
    final opacity = state == _TileState.claimed
        ? 0.55
        : state == _TileState.locked
            ? 0.75
            : 1.0;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlight ? _gold : Colors.white24,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.28),
                  border: Border.all(color: _gold, width: 2),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ],
                    if (extra != null) ...[
                      const SizedBox(height: 6),
                      extra,
                    ],
                    if (progress != null) ...[
                      const SizedBox(height: 8),
                      _bar(progress, progressText ?? ''),
                    ] else if (progressText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        progressText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _tileTrailing(state, rewardText, actionLabel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileTrailing(_TileState state, String? rewardText, String? label) {
    switch (state) {
      case _TileState.claimable:
        return _pulseButton(label ?? t('pass_claim'), _green);
      case _TileState.play:
        return _pulseButton(label ?? t('pass_claim'), const Color(0xFFEA580C));
      case _TileState.claimed:
        return const Text('✓',
            style: TextStyle(
                color: _green, fontWeight: FontWeight.w900, fontSize: 24));
      case _TileState.locked:
        return const Text('🔒', style: TextStyle(fontSize: 22));
      case _TileState.progress:
        if (rewardText == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gold, width: 1.2),
          ),
          child: Text(
            rewardText,
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        );
    }
  }

  Widget _buildWeeklyTile() {
    final quest = _progress.weeklyQuest;
    final target = quest.target;
    final done = min(_progress.weeklyQuestProgress, target);
    final ready = _progress.weeklyGoalReady;
    final claimed = _progress.weeklyRewardClaimed && !ready;
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
    return _tile(
      icon: '🗓️',
      title: t('home_weeklyTitle'),
      subtitle: t(subtitleKey, {'n': '$target', 'r': '${quest.reward}'}),
      progress: target == 0 ? 0.0 : done / target,
      progressText: claimed
          ? t('home_weeklyClaimed')
          : t(progressKey, {'done': '$done', 'total': '$target'}),
      colors: const [Color(0xFF0369A1), Color(0xFF0F766E)],
      rewardText: '+${quest.reward} ☄️',
      state: ready
          ? _TileState.claimable
          : claimed
              ? _TileState.claimed
              : _TileState.progress,
      onTap: ready ? _claimWeeklyReward : null,
      actionLabel: t('home_weeklyClaim'),
    );
  }

  Widget _buildMonthlyTile() {
    final quest = _progress.monthlyQuest;
    final target = quest.target;
    final done = min(_progress.monthlyQuestProgress, target);
    final ready = _progress.monthlyGoalReady;
    final claimed = _progress.monthlyRewardClaimed && !ready;
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
    return _tile(
      icon: '🌕',
      title: t('home_monthlyTitle'),
      subtitle: t(subtitleKey, {'n': '$target', 'r': '${quest.reward}'}),
      progress: target == 0 ? 0.0 : done / target,
      progressText: claimed
          ? t('home_monthlyClaimed')
          : t(progressKey, {'done': '$done', 'total': '$target'}),
      colors: const [Color(0xFF7E22CE), Color(0xFFBE185D)],
      rewardText: '+${quest.reward} ☄️',
      state: ready
          ? _TileState.claimable
          : claimed
              ? _TileState.claimed
              : _TileState.progress,
      onTap: ready ? _claimMonthlyReward : null,
      actionLabel: t('home_weeklyClaim'),
    );
  }

  Widget _buildConstellationTile() {
    final def = _progress.activeConstellation;
    final done = _progress.constellationProgress;
    final ready = _progress.constellationGoalReady;
    final claimed = _progress.weeklyConstellationClaimed && !ready;
    return _tile(
      icon: '✨',
      title: t('constellation_title'),
      subtitle: t(def.nameKey),
      extra: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(def.pointCount, (i) {
          final filled = i < done;
          return Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 15,
            color: filled ? _gold : Colors.white38,
          );
        }),
      ),
      progressText: claimed
          ? t('constellation_claimed')
          : t('constellation_progress',
              {'done': '$done', 'total': '${def.pointCount}'}),
      colors: const [Color(0xFF4338CA), Color(0xFF1E1B4B)],
      rewardText: def.badgeIcon,
      state: ready
          ? _TileState.claimable
          : claimed
              ? _TileState.claimed
              : _TileState.progress,
      onTap: ready ? _claimConstellationReward : null,
      actionLabel: t('home_weeklyClaim'),
    );
  }

  Widget _buildCometTile() {
    final active = PlayerProgress.cometEventActive();
    final done = _progress.cometCompletedThisEvent;
    final remaining = PlayerProgress.cometTimeRemaining();
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final timeLabel = hours > 0
        ? t('comet_timeHm', {'h': '$hours', 'm': '$minutes'})
        : t('comet_timeM', {'m': '$minutes'});
    final state = !active
        ? _TileState.locked
        : done
            ? _TileState.claimed
            : _TileState.play;
    return _tile(
      icon: '☄️',
      title: t('comet_title'),
      subtitle: t('comet_subtitle', {'r': '${EconomyConfig.cometMeteorReward}'}),
      progressText: !active
          ? t('comet_nextIn', {'time': timeLabel})
          : done
              ? t('comet_done')
              : t('comet_closesIn', {'time': timeLabel}),
      colors: const [Color(0xFFC2410C), Color(0xFF9D174D)],
      rewardText: '+${EconomyConfig.cometMeteorReward} ☄️',
      state: state,
      onTap: state == _TileState.play ? _openComet : null,
      actionLabel: t('comet_play'),
    );
  }

  // ---------------------------------------------------------------------
  // ÖDÜLLER sekmesi
  // ---------------------------------------------------------------------
  Widget _buildRewardsTab() {
    final lvl = _progress.passLevel;
    final claimable = _progress.passClaimableCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (claimable > 1) ...[
          GestureDetector(
            onTap: _claimAllLevels,
            child: Center(
              child: _pulseButton(t('pass_claimAll'), _green),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var l = 1; l <= PassConfig.maxLevel; l++) ...[
          _levelRow(l, lvl),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _levelRow(int level, int currentLevel) {
    final reward = PassConfig.rewards[level - 1];
    final unlocked = level <= currentLevel;
    final claimed = _progress.passClaimedLevels.contains(level);
    final canClaim = unlocked && !claimed;
    final isNext = level == currentLevel + 1;
    return Opacity(
      opacity: claimed ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF123B7A), Color(0xFF0C2554)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canClaim
                ? _gold
                : isNext
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A6B),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            _levelBadge(level, unlocked),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final it in _itemsFor(reward)) _rewardChip(it),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (canClaim)
              GestureDetector(
                onTap: () => _claimLevel(level),
                child: _pulseButton(t('pass_claim'), _green),
              )
            else if (claimed)
              const Text('✓',
                  style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w900,
                      fontSize: 22))
            else
              const Text('🔒', style: TextStyle(fontSize: 20)),
          ],
        ),
      ),
    );
  }

  Widget _rewardChip(RewardItem it) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(it.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text(
            '${it.amount}${it.icon == '✨' ? ' XP' : ''}',
            style: const TextStyle(
              color: Color(0xFFFFE082),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
