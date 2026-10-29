import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';
import '../widgets/meteor_icon.dart';

/// "Malzeme Mağazası": Gezegen Birleştir'de oyun bitince kullanılan
/// "Kurtarma Hakkı"nı (en üstteki 6 gezegeni kaldırıp devam et) meteor
/// karşılığında ÖNCEDEN satın alıp biriktirmeyi sağlar.
///
/// Stoklanan hak (PlayerProgress.bankedRescues), oyunda (planet_merge_
/// screen.dart) reklamdan ÖNCE kontrol edilir; yani burada alınan hak
/// reklam izlemeden otomatik kullanılır.
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
                  _SupplyTile(
                    // 🛟 emojisi eski Android emoji fontlarinda yok (kutu gorunuyordu) -> Material ikon.
                    icon: const Icon(Icons.support,
                        color: Color(0xFFFFB74D), size: 28),
                    name: t('supplyShop_itemRescue'),
                    owned: _progress.bankedRescues,
                    price: EconomyConfig.rescueShopPrice,
                    onBuy: () => _buy(
                      price: EconomyConfig.rescueShopPrice,
                      buy: _progress.buyRescueWithMeteors,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SupplyTile(
                    icon: const Text('🛡️', style: TextStyle(fontSize: 26)),
                    name: t('supplyShop_itemShield'),
                    owned: _progress.streakShields,
                    price: EconomyConfig.streakShieldPrice,
                    onBuy: () {
                      if (_progress.streakShields >=
                          EconomyConfig.streakShieldMax) {
                        SoundService.instance.buttonTap();
                        CustomToast.show(
                            context,
                            t('supplyShop_shieldMax', {
                              'n': '${EconomyConfig.streakShieldMax}'
                            }),
                            icon: '🛡️',
                            accentColor: AppColors.warning);
                        return;
                      }
                      _buy(
                        price: EconomyConfig.streakShieldPrice,
                        buy: _progress.buyStreakShield,
                      );
                    },
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
  final Widget icon;
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
          SizedBox(width: 32, child: Center(child: icon)),
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
