import 'ui_kit.dart';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../screens/gem_shop_screen.dart';
import '../services/game_fx.dart';

/// Enerji bittiğinde gösterilen dialog: mücevherle doldurma ya da
/// mağazayı açma seçeneği sunar. Ana harita, oyun ekranı ve menü ortak
/// kullanır. [onChanged] enerji/mücevher değişince çağrılır.
Future<void> showNoEnergyDialog(BuildContext context, {VoidCallback? onChanged}) {
  final s = AppStrings.instance;
  final gp = GameProgress.instance;
  final cost = GameProgress.energyRefillGemCost;
  final canPay = gp.gems >= cost;
  return showDialog<void>(
    context: context,
    builder: (ctx) => GameAlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(s.t('no_energy_title')),
      content: Text(s.t('no_energy_body')),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.t('ok'))),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            if (canPay && gp.refillEnergyWithGems()) {
              GameFx.instance.reward();
              onChanged?.call();
            } else {
              openGemShop(context).then((_) => onChanged?.call());
            }
          },
          child: Text(canPay ? '💎 $cost  ${s.t('energy_refill_gems')}' : s.t('gem_shop_open')),
        ),
      ],
    ),
  );
}

/// Mücevher yetmediğinde: iptal ya da mağazayı aç.
Future<void> showNotEnoughGemsDialog(BuildContext context, {VoidCallback? onChanged}) {
  final s = AppStrings.instance;
  return showDialog<void>(
    context: context,
    builder: (ctx) => GameAlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(s.t('not_enough_gems_title')),
      content: Text(s.t('not_enough_gems_body')),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.t('cancel'))),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            openGemShop(context).then((_) => onChanged?.call());
          },
          child: Text(s.t('gem_shop_open')),
        ),
      ],
    ),
  );
}

Future<void> openGemShop(BuildContext context) {
  GameFx.instance.uiTap();
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GemShopScreen()));
}

/// Güçlendirici ikon/isim/açıklama yardımcıları (oyun ve mağaza ortak).
IconData boosterIcon(BoosterType t) {
  switch (t) {
    case BoosterType.aimGuide:
      return Icons.my_location;
    case BoosterType.joker:
      return Icons.auto_awesome;
    case BoosterType.revive:
      return Icons.favorite;
  }
}

String boosterNameKey(BoosterType t) {
  switch (t) {
    case BoosterType.aimGuide:
      return 'booster_aim_name';
    case BoosterType.joker:
      return 'booster_joker_name';
    case BoosterType.revive:
      return 'booster_revive_name';
  }
}

String boosterDescKey(BoosterType t) {
  switch (t) {
    case BoosterType.aimGuide:
      return 'booster_aim_desc';
    case BoosterType.joker:
      return 'booster_joker_desc';
    case BoosterType.revive:
      return 'booster_revive_desc';
  }
}
