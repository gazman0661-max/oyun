import 'package:flutter/material.dart';

import '../game/cosmic_powers.dart';
import '../game/milestones.dart';
import '../game/planet_merge_physics.dart' show PlanetMergeConfig;
import '../game/planet_skins.dart';
import '../game/ranks.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';
import '../widgets/planet_face.dart';
import '../widgets/reward_claim_dialog.dart';

/// Koleksiyon: oyuncunun rutbesi (XP seviyesinden), kesfettigi gezegenler
/// (bilgi kartlariyla, kilometre tasi odulleri) ve yerel basarimlar.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with SingleTickerProviderStateMixin {
  final PlayerProgress _progress = PlayerProgress.instance;
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
    _progress.addListener(_onChanged);
    // Yeni acilan gizli gezegenlerin kirmizi noktasi: ekran acilinca "goruldu".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _progress.markSkinsSeen();
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulse.dispose();
    _progress.removeListener(_onChanged);
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Odul alma
  // ---------------------------------------------------------------------
  Future<void> _claimRank() async {
    final idx = _progress.rankIndex;
    final meteors = await _progress.claimRankRewards();
    if (meteors <= 0 || !mounted) return;
    final rank = Ranks.all[idx];
    await showRewardClaim(
      context,
      title: t('retention_rankUp', {'rank': t(rank.nameKey)}),
      heroIcon: rank.icon,
      items: [RewardItem('☄️', meteors, t('reward_meteor'))],
    );
  }

  Future<void> _claimCollection(int threshold) async {
    final reward = await _progress.claimCollection(threshold);
    if (reward <= 0 || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleQuest'),
      heroIcon: '🪐',
      items: [RewardItem('☄️', reward, t('reward_meteor'))],
    );
  }

  Future<void> _claimAchievement(LocalAchievement a) async {
    final reward = await _progress.claimAchievement(a);
    if (reward <= 0 || !mounted) return;
    await showRewardClaim(
      context,
      title: t('reward_titleQuest'),
      heroIcon: a.icon,
      items: [RewardItem('☄️', reward, t('reward_meteor'))],
    );
  }

  /// Gezegenin ozel gucunu (varsa) gosteren kucuk kart.
  Widget _powerChip(PowerInfo info) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: info.color.withAlpha(34),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: info.color.withAlpha(150), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${info.icon}  ${t('pw_title')}: ${t(info.nameKey)}',
            style: TextStyle(
              color: info.color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t(info.descKey),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showPlanet(int tier) {
    final img = PlanetMergeConfig.tierImage[tier];
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
              SizedBox(
                width: 130,
                height: 130,
                child: PlanetFaced(img),
              ),
              const SizedBox(height: 10),
              Text(
                t('pm_planet_$tier'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('pm_fact_$tier'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (CosmicPowers.infoForTier(tier) != null) ...[
                const SizedBox(height: 12),
                _powerChip(CosmicPowers.infoForTier(tier)!),
              ],
              const SizedBox(height: 12),
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
  // Yapi
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _buildRankCard(),
                    const SizedBox(height: 14),
                    if (_tab == 0) ..._buildPlanets() else ..._buildAchievements(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4338CA), Color(0xFF7C3AED), Color(0xFF4338CA)],
        ),
        border: Border(bottom: BorderSide(color: _gold, width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 38),
          Expanded(
            child: Column(
              children: [
                const Text('🪐', style: TextStyle(fontSize: 26)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    t('col_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      shadows: [
                        Shadow(
                            color: Color(0xFF1E1B4B),
                            blurRadius: 2,
                            offset: Offset(0, 3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final planetDot = _progress.collectionClaimableCount > 0;
    final achDot = _progress.achievementClaimableCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(child: _tabButton(t('col_tabPlanets'), 0, planetDot)),
          const SizedBox(width: 8),
          Expanded(child: _tabButton(t('col_tabAch'), 1, achDot)),
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

  Widget _bar(double value, String text, {Color color = const Color(0xFF38BDF8)}) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0).toDouble(),
              minHeight: 20,
              backgroundColor: const Color(0xFF0A1433),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Rutbe karti
  // ---------------------------------------------------------------------
  Widget _buildRankCard() {
    final info = _progress.levelInfo();
    final idx = Ranks.indexForLevel(info.level);
    final rank = Ranks.all[idx];
    final hasNext = idx + 1 < Ranks.all.length;
    final next = hasNext ? Ranks.all[idx + 1] : null;
    final pending = _progress.rankRewardPending;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4338CA), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pending ? _gold : Colors.white24, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.3),
                  border: Border.all(color: _gold, width: 2.5),
                ),
                child: Text(rank.icon, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(rank.nameKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      t('pass_level', {'n': '${info.level}'}),
                      style: const TextStyle(
                          color: Color(0xFFC7D2FE),
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    _bar(info.progress, '${info.xpIntoLevel}/${info.xpForNext} XP',
                        color: const Color(0xFFA78BFA)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (pending)
            GestureDetector(
              onTap: _claimRank,
              child: _pulseButton(t('col_rankClaim'), _green),
            )
          else
            Text(
              next == null
                  ? t('col_maxRank')
                  : t('col_nextRank', {
                      'rank': t(next.nameKey),
                      'n': '${next.minLevel}',
                    }),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 12),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Gezegenler sekmesi
  // ---------------------------------------------------------------------
  List<Widget> _buildPlanets() {
    final found = _progress.discoveredPlanets.length;
    final total = PlanetMergeConfig.tierCount;
    return [
      Text(
        t('col_progress', {'a': '$found', 'b': '$total'}),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 8),
      _bar(found / total, '$found/$total', color: const Color(0xFF38BDF8)),
      const SizedBox(height: 10),
      Row(
        children: [
          for (final e in Milestones.collectionRewards.entries)
            Expanded(child: _milestoneChip(e.key, e.value)),
        ],
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
        children: [
          for (var tier = 0; tier < total; tier++) _planetCard(tier),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        t('skin_title'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        t('skin_subtitle'),
        style: const TextStyle(
          color: Color(0xFF9AA5D1),
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
      const SizedBox(height: 10),
      for (final sk in PlanetSkins.all) _skinCard(sk),
    ];
  }

  Future<void> _toggleSkin(PlanetSkin sk) async {
    SoundService.instance.buttonTap();
    await _progress.toggleSkin(sk);
  }

  Widget _skinCard(PlanetSkin sk) {
    final unlocked = _progress.skinUnlocked(sk);
    final equipped = _progress.skinEquipped(sk);
    final value = _progress.skinProgressValue(sk);
    final shown = value > sk.target ? sk.target : value;
    final image = PlanetFaced(sk.image);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF123B7A), Color(0xFF0C2554)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: equipped
              ? _gold
              : (unlocked ? const Color(0xFF7DB5E8) : const Color(0xFF1E3A6B)),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: unlocked
                ? image
                : Opacity(
                    opacity: 0.7,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                          Color(0xFF050B1F), BlendMode.srcIn),
                      child: image,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocked ? t(sk.nameKey) : '???',
                  style: TextStyle(
                    color: unlocked ? Colors.white : const Color(0xFF6B84B8),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t('skin_replaces', {'name': t('pm_planet_${sk.tier}')}),
                  style: const TextStyle(
                    color: Color(0xFF9AA5D1),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                if (!unlocked) ...[
                  Text(
                    t('skin_req_${sk.metric.name}', {'n': '${sk.target}'}),
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _bar(value / sk.target, '$shown/${sk.target}'),
                ] else
                  GestureDetector(
                    onTap: () => _toggleSkin(sk),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: equipped
                            ? const Color(0xFF0A1433)
                            : const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: equipped ? _gold : const Color(0xFF22C55E),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        equipped ? t('skin_remove') : t('skin_use'),
                        style: TextStyle(
                          color: equipped ? _gold : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestoneChip(int threshold, int reward) {
    final claimable = _progress.collectionClaimable(threshold);
    final claimed = _progress.collectionClaimed.contains(threshold);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: claimable ? () => _claimCollection(threshold) : null,
        child: Opacity(
          opacity: claimed ? 0.55 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF14284F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: claimable ? _gold : const Color(0xFF1E3A6B),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  t('col_milestone', {'n': '$threshold'}),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                if (claimable)
                  _pulseButton(t('pass_claim'), _green)
                else if (claimed)
                  const Text('✓',
                      style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w900,
                          fontSize: 20))
                else
                  Text('+$reward ☄️',
                      style: const TextStyle(
                          color: Color(0xFFFFE082),
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _planetCard(int tier) {
    final found = _progress.discoveredPlanets.contains(tier);
    final img = PlanetMergeConfig.tierImage[tier];
    final image = PlanetFaced(img);
    return GestureDetector(
      onTap: () {
        if (found) {
          _showPlanet(tier);
        } else {
          SoundService.instance.buttonTap();
          CustomToast.show(context, t('col_locked'),
              icon: '🔒', accentColor: AppColors.warning);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF123B7A), Color(0xFF0C2554)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: found ? const Color(0xFF7DB5E8) : const Color(0xFF1E3A6B),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: found
                  ? image
                  : Opacity(
                      opacity: 0.7,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                            Color(0xFF050B1F), BlendMode.srcIn),
                        child: image,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                found ? t('pm_planet_$tier') : '???',
                style: TextStyle(
                  color: found ? Colors.white : const Color(0xFF6B84B8),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Basarimlar sekmesi
  // ---------------------------------------------------------------------
  List<Widget> _buildAchievements() {
    return [
      for (final a in Milestones.achievements) ...[
        _achievementTile(a),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _achievementTile(LocalAchievement a) {
    final value = _progress.achievementValue(a.metric);
    final done = _progress.achievementDone(a);
    final claimed = _progress.achClaimed.contains(a.id);
    final shown = value > a.target ? a.target : value;
    return Opacity(
      opacity: claimed ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: (done && !claimed) ? () => _claimAchievement(a) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0B5CAD), Color(0xFF0A3A75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (done && !claimed) ? _gold : const Color(0xFF7DB5E8),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.28),
                  border: Border.all(color: _gold, width: 2),
                ),
                child: Text(a.icon, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(a.nameKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      t('ach_d_${a.metric.name}', {'n': '${a.target}'}),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    _bar(a.target == 0 ? 0.0 : shown / a.target,
                        '$shown/${a.target}'),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (claimed)
                const Text('✓',
                    style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w900,
                        fontSize: 24))
              else if (done)
                _pulseButton(t('pass_claim'), _green)
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _gold, width: 1.2),
                  ),
                  child: Text(
                    '+${a.rewardMeteors} ☄️',
                    style: const TextStyle(
                      color: Color(0xFFFFE082),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
