import 'dart:async';
import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import '../utils/duration_format.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../services/game_fx.dart';
import '../services/billing_service.dart';
import '../services/ad_service.dart';
import '../widgets/gem_dialogs.dart';

/// Mücevher mağazası: başlangıç paketi, mücevher paketleri (IAP,
/// Play Billing ile, bkz. services/billing_service.dart), mücevherle enerji doldurma
/// ve güçlendirici satın alma.
class GemShopScreen extends StatefulWidget {
  const GemShopScreen({super.key});

  @override
  State<GemShopScreen> createState() => _GemShopScreenState();
}

class _GemShopScreenState extends State<GemShopScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    BillingService.instance.addListener(_onBilling); // fiyatlar/teslimat gelince yenile
    // Reklam sayaci canli aksin.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (GameProgress.instance.adGemsCooldownRemaining != null || GameProgress.instance.starterOfferRemaining != null)) setState(() {});
    });
  }

  void _onBilling() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BillingService.instance.removeListener(_onBilling);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _buyPack(GemPack pack) async {
    GameFx.instance.uiTap();
    final ok = await BillingService.instance.buy(context, pack.id); // verme + bulut yedegi serviste
    if (!ok || !mounted) return;
    GameFx.instance.reward();
    setState(() {});
  }

  Future<void> _buyStarter() async {
    GameFx.instance.uiTap();
    final ok = await BillingService.instance.buy(context, kStarterPack.id);
    if (!ok || !mounted) return;
    GameFx.instance.reward();
    setState(() {});
  }

  Future<void> _watchGemAd() async {
    final gp = GameProgress.instance;
    if (gp.adGemsRemaining <= 0) return;
    GameFx.instance.uiTap();
    final watched = await watchRewardedAd(context);
    if (!watched || !mounted) return;
    final got = gp.claimAdGems();
    if (got > 0) {
      GameFx.instance.reward();
      setState(() {});
      showGamePopup(context, '+$got 💎', autoCloseMs: 1600);
    }
  }

  void _refillEnergy() {
    final gp = GameProgress.instance;
    if (gp.energy >= GameProgress.maxEnergy) return;
    if (gp.gems < GameProgress.energyRefillGemCost) {
      showNotEnoughGemsDialog(context).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    if (gp.refillEnergyWithGems()) {
      GameFx.instance.reward();
      setState(() {});
    }
  }

  void _buyBooster(BoosterType t) {
    final gp = GameProgress.instance;
    final cost = GameProgress.boosterGemCost[t]!;
    if (gp.gems < cost) {
      showNotEnoughGemsDialog(context).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    if (gp.buyBooster(t)) {
      GameFx.instance.reward();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final gp = GameProgress.instance;
    final energyFull = gp.energy >= GameProgress.maxEnergy;

    return GameScaffold(
      title: s.t('gem_shop_title'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (gp.starterOfferRemaining != null) ...[
            _Card(
              highlight: true,
              child: Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.t('starter_pack_title'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(s.t('starter_pack_desc'), style: TextStyle(fontSize: 12, color: Colors.brown.shade600)),
                        const SizedBox(height: 2),
                        Text('⏳ ${s.t('starter_pack_timer')} ${formatCountdown(gp.starterOfferRemaining ?? Duration.zero)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD84315))),
                      ],
                    ),
                  ),
                  CandyButton(width: 100, height: 42, fontSize: 14, style: CandyStyle.orange, label: BillingService.instance.priceOf(kStarterPack.id), onTap: _buyStarter),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _SectionTitle(s.t('gem_shop_free')),
          _Card(
            child: Row(
              children: [
                Icon(Icons.smart_display_outlined, color: Colors.green.shade600, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    gp.adGemsRemaining > 0
                        ? '${s.t('gem_shop_watch_ad')}  (${gp.adGemsRemaining}/${GameProgress.adGemsPerWindow})'
                        : (gp.adGemsCooldownRemaining != null
                            ? '${s.t('gem_shop_watch_ad')}  ${formatCountdown(gp.adGemsCooldownRemaining!)}'
                            : s.t('gem_shop_watch_ad')),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                CandyButton(
                  width: 96,
                  height: 42,
                  fontSize: 14,
                  label: '${GameProgress.adGemMin}-${GameProgress.adGemMax} 💎',
                  onTap: gp.adGemsRemaining > 0 ? _watchGemAd : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionTitle(s.t('gem_shop_packs')),
          for (final pack in kGemPacks)
            _Card(
              child: Row(
                children: [
                  const Text('💎', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Text('${pack.gems}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        if (pack.best) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade500,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(s.t('gem_shop_best'),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  CandyButton(width: 100, height: 42, fontSize: 14, style: CandyStyle.orange, label: BillingService.instance.priceOf(pack.id), onTap: () => _buyPack(pack)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          _SectionTitle(s.t('gem_shop_energy')),
          _Card(
            child: Row(
              children: [
                Icon(Icons.bolt, color: Colors.amber.shade700, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${s.t('energy_title')}  ${gp.energy}/${GameProgress.maxEnergy}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                CandyButton(
                  width: 96,
                  height: 42,
                  fontSize: 14,
                  style: CandyStyle.blue,
                  label: '💎 ${GameProgress.energyRefillGemCost}',
                  onTap: energyFull ? null : _refillEnergy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionTitle(s.t('gem_shop_boosters')),
          for (final t in BoosterType.values)
            _Card(
              child: Row(
                children: [
                  Icon(boosterIcon(t), color: Colors.deepPurple.shade400, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s.t(boosterNameKey(t))}  (${s.t('booster_owned')}: ${gp.boosterCount(t)})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(s.t(boosterDescKey(t)), style: TextStyle(fontSize: 12, color: Colors.brown.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CandyButton(
                    width: 96,
                    height: 42,
                    fontSize: 14,
                    style: CandyStyle.blue,
                    label: '💎 ${GameProgress.boosterGemCost[t]}',
                    onTap: () => _buyBooster(t),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.brown.shade700)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool highlight;
  const _Card({required this.child, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: highlight ? Colors.orange.shade400 : Colors.brown.shade200, width: 2),
        ),
        child: child,
      );
}
