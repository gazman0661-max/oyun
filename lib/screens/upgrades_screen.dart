import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import '../models/game_progress.dart';
import '../localization/app_strings.dart';
import '../services/game_fx.dart';

/// Ana menudeki gorevler ikonunun YANINDAKI "Yukseltmeler" ikonuyla
/// acilan ekran. Eskiden bu 3 kart (atis hizi / sans / siparis slotu)
/// ana menude dogrudan, "Oyna" butonunun hemen altinda, sayfayi
/// asagi kaydirarak gorulen bir liste halinde duruyordu - simdi
/// Gorevler ekraniyla ayni mantikla ayri bir ekrana tasindi, ana
/// menude sadece kucuk bir kisayol ikonu var.
class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key});

  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  void _buyUpgrade(bool Function() buyFn, String successMessage) {
    final bought = buyFn();
    if (bought) {
      GameFx.instance.reward();
    } else {
      GameFx.instance.denied();
    }
    setState(() {});
    if (!mounted) return;
    showGamePopup(context, bought ? successMessage : AppStrings.instance.t('insufficient_coins'));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final progress = GameProgress.instance;

    return GameScaffold(
      title: s.t('shop_upgrades'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _UpgradeCard(
            icon: Icons.bolt,
            iconColor: Colors.orange,
            title: s.t('upgrade_throw_title'),
            description: s.t('upgrade_throw_desc'),
            level: progress.throwCooldownLevel,
            maxLevel: GameProgress.maxUpgradeLevel,
            nextCost: progress.throwCooldownLevel < GameProgress.maxUpgradeLevel
                ? GameProgress.throwCooldownCost[progress.throwCooldownLevel]
                : null,
            onBuy: () => _buyUpgrade(
              GameProgress.instance.buyThrowCooldownUpgrade,
              s.t('upgrade_success_throw'),
            ),
          ),
          const SizedBox(height: 12),
          _UpgradeCard(
            icon: Icons.auto_awesome,
            iconColor: Colors.purple,
            title: s.t('upgrade_luck_title'),
            description: s.t('upgrade_luck_desc'),
            level: progress.luckLevel,
            maxLevel: GameProgress.maxUpgradeLevel,
            nextCost: progress.luckLevel < GameProgress.maxUpgradeLevel
                ? GameProgress.luckCost[progress.luckLevel]
                : null,
            onBuy: () => _buyUpgrade(
              GameProgress.instance.buyLuckUpgrade,
              s.t('upgrade_success_luck'),
            ),
          ),
          const SizedBox(height: 12),
          _UpgradeCard(
            icon: Icons.receipt_long,
            iconColor: Colors.teal,
            title: s.t('upgrade_slot_title'),
            description: s.t('upgrade_slot_desc'),
            level: progress.extraOrderSlotLevel,
            maxLevel: GameProgress.maxOrderSlotLevel,
            nextCost: progress.extraOrderSlotLevel < GameProgress.maxOrderSlotLevel
                ? GameProgress.orderSlotCost[progress.extraOrderSlotLevel]
                : null,
            onBuy: () => _buyUpgrade(
              GameProgress.instance.buyOrderSlotUpgrade,
              s.t('upgrade_success_slot'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek bir yukseltme karti - ikon + baslik/aciklama + seviye + "satin
/// al" butonu (fiyat ya da MAX rozeti). (Eskiden main_menu_screen.dart
/// icindeydi, yukseltmeler ayri bir ekrana tasinirken buraya alindi -
/// gorunumu degismedi.)
class _UpgradeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final int level;
  final int maxLevel;
  final int? nextCost;
  final VoidCallback onBuy;

  const _UpgradeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.level,
    required this.maxLevel,
    required this.nextCost,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final isMaxed = nextCost == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 6),
                Text(
                  '${AppStrings.instance.t('level_of')} $level / $maxLevel',
                  style: TextStyle(fontSize: 11, color: Colors.brown.shade400, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CandyButton(
            width: 104,
            height: 42,
            fontSize: 14,
            style: CandyStyle.orange,
            leading: isMaxed ? null : Image.asset('assets/images/coin_icon.webp', width: 16, height: 16),
            label: isMaxed ? AppStrings.instance.t('max') : '$nextCost',
            onTap: isMaxed ? null : onBuy,
          ),
        ],
      ),
    );
  }
}
