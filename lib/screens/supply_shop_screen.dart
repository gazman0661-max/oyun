import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';
import '../widgets/meteor_icon.dart';

/// "Malzeme Mağazası": Tüp ve Orbit modlarında oyun-içi kullanılan
/// sarf malzemelerini (İpucu/Geri Al/Çevir/Ekstra Tüp/Rıhtım Yuvası)
/// meteor karşılığında ÖNCEDEN satın alıp biriktirmeyi sağlar.
///
/// Bu ekran yeni bir satın alma mekanizması EKLEMİYOR — PlayerProgress
/// içindeki buyHintWithMeteors/buyUndoWithMeteors/buyFlipWithMeteors/
/// buyExtraTubeWithMeteors/buyDockSlotWithMeteors fonksiyonları (ve
/// bunların biriktiği bankedHints/bankedUndos/... sayaçları) zaten
/// mevcuttu; sadece bunlara dokunacak bir arayüz eksikti. Oyun
/// içinde (game_screen.dart / orbit_game_screen.dart) bu banka
/// zaten reklamdan ÖNCE kontrol ediliyor, yani burada stoklanan
/// malzeme oyunda reklam izlemeden otomatik kullanılıyor.
class SupplyShopScreen extends StatefulWidget {
  const SupplyShopScreen({super.key});

  @override
  State<SupplyShopScreen> createState() => _SupplyShopScreenState();
}

class _SupplyShopScreenState extends State<SupplyShopScreen> {
  final PlayerProgress _progress = PlayerProgress.instance;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onChanged);
  }

  @override
  void dispose() {
    _progress.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _buy({
    required int price,
    required Future<bool> Function() buy,
  }) async {
    SoundService.instance.buttonTap();
    if (_progress.meteors < price) {
      CustomToast.show(context, t('shop_notEnoughMeteors'),
          icon: '🌠', accentColor: AppColors.warning);
      return;
    }
    final ok = await buy();
    if (!mounted) return;
    if (ok) {
      CustomToast.show(context, t('supplyShop_buySuccess'),
          icon: '✅', accentColor: AppColors.success);
    } else {
      CustomToast.show(context, t('shop_notEnoughMeteors'),
          icon: '🌠', accentColor: AppColors.warning);
    }
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
                  const Text('🧰', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    t('supplyShop_title'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  MeteorBadge(amount: _progress.meteors),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                t('supplyShop_subtitle'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Text(
                    t('supplyShop_sectionTube'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SupplyTile(
                    icon: '🛰️',
                    name: t('supplyShop_itemHint'),
                    owned: _progress.bankedHints,
                    price: EconomyConfig.hintPrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.hintPrice,
                      buy: _progress.buyHintWithMeteors,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SupplyTile(
                    icon: '↩️',
                    name: t('supplyShop_itemUndo'),
                    owned: _progress.bankedUndos,
                    price: EconomyConfig.undoPrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.undoPrice,
                      buy: _progress.buyUndoWithMeteors,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SupplyTile(
                    icon: '🌀',
                    name: t('supplyShop_itemFlip'),
                    owned: _progress.bankedFlips,
                    price: EconomyConfig.flipPrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.flipPrice,
                      buy: _progress.buyFlipWithMeteors,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SupplyTile(
                    icon: '🧯',
                    name: t('supplyShop_itemExtraTube'),
                    owned: _progress.bankedExtraTubes,
                    price: EconomyConfig.extraTubePrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.extraTubePrice,
                      buy: _progress.buyExtraTubeWithMeteors,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SupplyTile(
                    icon: '🕳️',
                    name: t('supplyShop_itemBlackHole'),
                    owned: _progress.bankedBlackHoles,
                    price: EconomyConfig.blackHolePrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.blackHolePrice,
                      buy: _progress.buyBlackHoleWithMeteors,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t('supplyShop_sectionOrbit'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SupplyTile(
                    icon: '⚓',
                    name: t('supplyShop_itemDockSlot'),
                    owned: _progress.bankedOrbitDockSlots,
                    price: EconomyConfig.dockSlotShopPrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.dockSlotShopPrice,
                      buy: _progress.buyDockSlotWithMeteors,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplyTile extends StatelessWidget {
  final String icon;
  final String name;
  final int owned;
  final int price;
  final VoidCallback onBuy;

  const _SupplyTile({
    required this.icon,
    required this.name,
    required this.owned,
    required this.price,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tubeGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tubeGlassBorder),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t('supplyShop_owned', {'n': '$owned'}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onBuy,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$price'),
                const SizedBox(width: 4),
                const MeteorIcon(size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
