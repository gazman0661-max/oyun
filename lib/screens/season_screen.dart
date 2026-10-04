import '../services/cloud_save_service.dart';
import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../models/season.dart';
import '../services/game_fx.dart';
import '../services/mock_iap.dart';

/// SEZON YOLU ekrani: 30 kademe, bedava (sol) + premium (sag) yol.
class SeasonScreen extends StatefulWidget {
  const SeasonScreen({super.key});

  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  final ScrollController _scroll = ScrollController();
  final SeasonService _season = SeasonService.instance;
  static const double _rowH = 92;

  bool get _tr => AppStrings.instance.language == AppLanguage.tr;

  @override
  void initState() {
    super.initState();
    // Acilista mevcut kademeye yakin bir yere kaydir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = ((_season.tier - 1) * _rowH).clamp(0, _scroll.position.maxScrollExtent).toDouble();
      _scroll.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _leftText(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    return _tr ? '${days}g ${hours}s' : '${days}d ${hours}h';
  }

  String _rewardText(SeasonReward r) {
    final parts = <String>[];
    if (r.coins > 0) parts.add('🪙${r.coins}');
    if (r.gems > 0) parts.add('💎${r.gems}');
    if (r.energy) parts.add('⚡');
    if (r.booster != null) {
      final icon = switch (r.booster!) {
        BoosterType.aimGuide => '🎯',
        BoosterType.joker => '🃏',
        BoosterType.revive => '❤️',
      };
      parts.add('$icon×${r.boosterCount}');
    }
    return parts.join('\n');
  }

  void _claim(int t, bool premiumTrack) {
    final r = _season.claim(t, premiumTrack: premiumTrack);
    if (r == null) {
      GameFx.instance.uiTap();
      return;
    }
    GameFx.instance.reward();
    setState(() {});
  }

  void _claimAll() {
    final n = _season.claimAll();
    if (n > 0) GameFx.instance.reward();
    setState(() {});
  }

  Future<void> _buyPremium() async {
    GameFx.instance.uiTap();
    final ok = await mockPurchase(
      context,
      const GemPack(SeasonService.premiumProductId, 0, SeasonService.premiumPriceLabel),
    );
    if (ok) {
      _season.unlockPremium();
      CloudSaveService.instance.uploadNow();
      GameFx.instance.reward();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final tier = _season.tier;
    final claimable = _season.claimableCount;
    return GameScaffold(
      title: s.t('season_title'),
      body: Column(
        children: [
          _header(tier, claimable),
          _trackLabels(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowH,
              itemCount: SeasonService.tierCount,
              itemBuilder: (_, i) => _tierRow(i + 1, tier),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(int tier, int claimable) {
    final s = AppStrings.instance;
    final left = _leftText(_season.timeLeft);
    final pInTier = _season.pointsInTier;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple.shade600, Colors.indigo.shade500]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('${s.t('season_tier')} $tier/${SeasonService.tierCount}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
              const Spacer(),
              const Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 18),
              const SizedBox(width: 4),
              Text(left, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 14,
              value: pInTier / SeasonService.spPerTier,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tier >= SeasonService.tierCount
                ? s.t('season_done')
                : '$pInTier/${SeasonService.spPerTier} SP  •  ${s.t('season_sp_hint')}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (kSeasonPremiumEnabled && !_season.premium)
                Expanded(
                  child: CandyButton(
                    height: 48,
                    fontSize: 15,
                    style: CandyStyle.orange,
                    label: '👑 ${s.t('season_premium_buy')}  ${iapPrice(SeasonService.premiumPriceLabel)}',
                    onTap: _buyPremium,
                  ),
                ),
              if (kSeasonPremiumEnabled && _season.premium)
                Expanded(
                  child: Text('👑 ${s.t('season_premium_on')}',
                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900)),
                ),
              if (claimable > 0) ...[
                const SizedBox(width: 8),
                CandyButton(
                  width: 150,
                  height: 48,
                  fontSize: 14,
                  label: '${s.t('season_claim_all')} ($claimable)',
                  onTap: _claimAll,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _trackLabels() {
    final s = AppStrings.instance;
    return Container(
      color: Colors.deepPurple.shade50,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Center(
                  child: Text(s.t('season_free'), style: const TextStyle(fontWeight: FontWeight.w900)))),
          const SizedBox(width: 56),
          Expanded(
              child: Center(
                  child: Text(kSeasonPremiumEnabled ? '👑 ${s.t('season_premium')}' : '',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber.shade800)))),
        ],
      ),
    );
  }

  Widget _tierRow(int t, int tier) {
    final reached = t <= tier;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Expanded(child: _rewardCard(t, false)),
          Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: reached ? Colors.deepPurple : Colors.grey.shade400,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text('$t', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          Expanded(child: kSeasonPremiumEnabled ? _rewardCard(t, true) : const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _rewardCard(int t, bool premiumTrack) {
    final r = premiumTrack ? SeasonService.premiumReward(t) : SeasonService.freeReward(t);
    final claimed = _season.isClaimed(t, premiumTrack: premiumTrack);
    final can = _season.canClaim(t, premiumTrack: premiumTrack);
    final locked = premiumTrack && !_season.premium;
    final base = premiumTrack ? Colors.amber : Colors.deepPurple;
    return GestureDetector(
      onTap: can ? () => _claim(t, premiumTrack) : null,
      child: Container(
        decoration: BoxDecoration(
          color: claimed
              ? Colors.grey.shade300
              : can
                  ? Colors.green.shade100
                  : base.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: can ? Colors.green : (claimed ? Colors.grey : base.shade200),
            width: can ? 3 : 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                _rewardText(r),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: claimed ? Colors.grey.shade600 : Colors.black87,
                ),
              ),
            ),
            if (claimed) const Positioned(right: 4, top: 2, child: Icon(Icons.check_circle, color: Colors.green, size: 20)),
            if (locked && !claimed) const Positioned(right: 4, top: 2, child: Icon(Icons.lock, color: Colors.black38, size: 18)),
          ],
        ),
      ),
    );
  }
}
