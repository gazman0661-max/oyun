import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import '../models/game_progress.dart';
import '../localization/app_strings.dart';
import '../services/game_fx.dart';

/// Ana menudeki harita ikonunun SOLUNDAKI "Görevler" ikonuyla acilan
/// ekran. Eskiden gunluk gorevler ana menude 3 ayri kart olarak
/// duruyordu ve cok yer kapliyordu - simdi Gunluk/Haftalik/Aylik
/// sekmeleri halinde burada, ayri bir ekranda gosteriliyor.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Ekran acilirken gun/hafta/ay donumunu kontrol et - boylece
    // gece yarisini, hafta basini ya da ay basini gecmis bir ilerleme
    // hep guncel gorunur.
    GameProgress.instance.refreshMissions();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _claim(bool Function() claimFn) {
    if (claimFn()) {
      GameFx.instance.reward();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final progress = GameProgress.instance;

    return GameScaffold(
      title: s.t('missions_title'),
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.amber,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: [
          Tab(text: s.t('missions_tab_daily')),
          Tab(text: s.t('missions_tab_weekly')),
          Tab(text: s.t('missions_tab_monthly')),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MissionList(
            children: [
              _MissionRow(
                icon: Icons.local_shipping,
                label: s.missionProgressLabel(
                    progress.missionDeliverProgress, GameProgress.missionDeliverTarget, 'mission_deliver'),
                progress: progress.missionDeliverProgress,
                target: GameProgress.missionDeliverTarget,
                reward: GameProgress.missionDeliverReward,
                claimed: progress.missionDeliverClaimed,
                onClaim: () => _claim(GameProgress.instance.claimDeliverMission),
              ),
              _MissionRow(
                icon: Icons.merge_type,
                label: s.missionProgressLabel(
                    progress.missionMergeProgress, GameProgress.missionMergeTarget, 'mission_merge'),
                progress: progress.missionMergeProgress,
                target: GameProgress.missionMergeTarget,
                reward: GameProgress.missionMergeReward,
                claimed: progress.missionMergeClaimed,
                onClaim: () => _claim(GameProgress.instance.claimMergeMission),
              ),
              _MissionRow(
                icon: Icons.monetization_on,
                label: s.missionProgressLabel(
                    progress.missionCoinsProgress, GameProgress.missionCoinsTarget, 'mission_coins'),
                progress: progress.missionCoinsProgress,
                target: GameProgress.missionCoinsTarget,
                reward: GameProgress.missionCoinsReward,
                claimed: progress.missionCoinsClaimed,
                onClaim: () => _claim(GameProgress.instance.claimCoinsMission),
              ),
            ],
          ),
          _MissionList(
            children: [
              _MissionRow(
                icon: Icons.local_shipping,
                label: s.missionProgressLabel(progress.missionWeeklyDeliverProgress,
                    GameProgress.missionWeeklyDeliverTarget, 'mission_deliver'),
                progress: progress.missionWeeklyDeliverProgress,
                target: GameProgress.missionWeeklyDeliverTarget,
                reward: GameProgress.missionWeeklyDeliverReward,
                gems: GameProgress.weeklyMissionGems,
                claimed: progress.missionWeeklyDeliverClaimed,
                onClaim: () => _claim(GameProgress.instance.claimWeeklyDeliverMission),
              ),
              _MissionRow(
                icon: Icons.merge_type,
                label: s.missionProgressLabel(
                    progress.missionWeeklyMergeProgress, GameProgress.missionWeeklyMergeTarget, 'mission_merge'),
                progress: progress.missionWeeklyMergeProgress,
                target: GameProgress.missionWeeklyMergeTarget,
                reward: GameProgress.missionWeeklyMergeReward,
                gems: GameProgress.weeklyMissionGems,
                claimed: progress.missionWeeklyMergeClaimed,
                onClaim: () => _claim(GameProgress.instance.claimWeeklyMergeMission),
              ),
              _MissionRow(
                icon: Icons.monetization_on,
                label: s.missionProgressLabel(
                    progress.missionWeeklyCoinsProgress, GameProgress.missionWeeklyCoinsTarget, 'mission_coins'),
                progress: progress.missionWeeklyCoinsProgress,
                target: GameProgress.missionWeeklyCoinsTarget,
                reward: GameProgress.missionWeeklyCoinsReward,
                gems: GameProgress.weeklyMissionGems,
                claimed: progress.missionWeeklyCoinsClaimed,
                onClaim: () => _claim(GameProgress.instance.claimWeeklyCoinsMission),
              ),
            ],
          ),
          _MissionList(
            children: [
              _MissionRow(
                icon: Icons.local_shipping,
                label: s.missionProgressLabel(progress.missionMonthlyDeliverProgress,
                    GameProgress.missionMonthlyDeliverTarget, 'mission_deliver'),
                progress: progress.missionMonthlyDeliverProgress,
                target: GameProgress.missionMonthlyDeliverTarget,
                reward: GameProgress.missionMonthlyDeliverReward,
                gems: GameProgress.monthlyMissionGems,
                claimed: progress.missionMonthlyDeliverClaimed,
                onClaim: () => _claim(GameProgress.instance.claimMonthlyDeliverMission),
              ),
              _MissionRow(
                icon: Icons.merge_type,
                label: s.missionProgressLabel(
                    progress.missionMonthlyMergeProgress, GameProgress.missionMonthlyMergeTarget, 'mission_merge'),
                progress: progress.missionMonthlyMergeProgress,
                target: GameProgress.missionMonthlyMergeTarget,
                reward: GameProgress.missionMonthlyMergeReward,
                gems: GameProgress.monthlyMissionGems,
                claimed: progress.missionMonthlyMergeClaimed,
                onClaim: () => _claim(GameProgress.instance.claimMonthlyMergeMission),
              ),
              _MissionRow(
                icon: Icons.monetization_on,
                label: s.missionProgressLabel(
                    progress.missionMonthlyCoinsProgress, GameProgress.missionMonthlyCoinsTarget, 'mission_coins'),
                progress: progress.missionMonthlyCoinsProgress,
                target: GameProgress.missionMonthlyCoinsTarget,
                reward: GameProgress.missionMonthlyCoinsReward,
                gems: GameProgress.monthlyMissionGems,
                claimed: progress.missionMonthlyCoinsClaimed,
                onClaim: () => _claim(GameProgress.instance.claimMonthlyCoinsMission),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bir sekmenin icerigi: gorev kartlarini dikeyde listeler.
class _MissionList extends StatelessWidget {
  final List<Widget> children;
  const _MissionList({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => children[i],
    );
  }
}

/// Tek bir gorev karti - ilerleme cubugu + hedefe ulasilinca aktif
/// olan "Al" butonu. (Eskiden main_menu_screen.dart icindeydi, gorevler
/// ayri bir ekrana tasinirken buraya alindi - gorunumu degismedi.)
class _MissionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int progress;
  final int target;
  final int reward;
  final int gems; // ek mucevher odulu (0 = yok)
  final bool claimed;
  final VoidCallback onClaim;

  const _MissionRow({
    required this.icon,
    required this.label,
    required this.progress,
    required this.target,
    required this.reward,
    this.gems = 0,
    required this.claimed,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final done = progress >= target;
    final ratio = target == 0 ? 0.0 : (progress / target).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.brown.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(claimed ? Colors.grey.shade400 : Colors.green.shade400),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          CandyButton(
            width: 112,
            height: 42,
            fontSize: 11.5,
            style: CandyStyle.green,
            label: claimed
                ? s.t('mission_claimed')
                : '${s.t('mission_claim')} ${gems > 0 ? '+$reward +$gems💎' : '+$reward'}',
            onTap: (done && !claimed) ? onClaim : null,
          ),
        ],
      ),
    );
  }
}
