import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/custom_toast.dart';
import '../widgets/meteor_icon.dart';
import '../widgets/theme_preview_tile.dart';

/// "Dükkan": tüm arkaplan temalarını canlı önizlemeyle listeler,
/// meteorla satın almayı sağlar. Etkinleştirme burada YAPILMAZ — o iş
/// Kozmik Oda'ya ait (satın alma ile giyme/kullanma ayrı adımlar).
class ThemeShopScreen extends StatefulWidget {
  const ThemeShopScreen({super.key});

  @override
  State<ThemeShopScreen> createState() => _ThemeShopScreenState();
}

class _ThemeShopScreenState extends State<ThemeShopScreen> {
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

  Future<void> _tryBuy(CosmicTheme theme) async {
    SoundService.instance.buttonTap();
    if (!_progress.canAffordTheme) {
      CustomToast.show(context, t('shop_notEnoughMeteors'),
          icon: '🌠', accentColor: AppColors.warning);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('shop_buyConfirmTitle'),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          t('shop_buyConfirmBody', {'price': '${theme.price}'}),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('shop_buyConfirmCancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('shop_buyConfirmYes')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _progress.purchaseTheme(theme.id);
    if (!mounted) return;
    if (ok) {
      CustomToast.show(context, t('shop_buySuccess'),
          icon: '🎉', accentColor: AppColors.success);
      final applyNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(t('shop_applyNowTitle'),
              style: const TextStyle(color: AppColors.textPrimary)),
          content: Text(
            t('shop_applyNowBody'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('shop_applyNowLater')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('shop_applyNowYes')),
            ),
          ],
        ),
      );
      if (applyNow == true) {
        await _progress.setActiveTheme(theme.id);
        if (!mounted) return;
        CustomToast.show(context, t('shop_applySuccess'),
            icon: '✨', accentColor: AppColors.success);
      }
    } else {
      CustomToast.show(context, t('shop_notEnoughMeteors'),
          icon: '🌠', accentColor: AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 'default' zaten herkeste hazir ve satilik degil, dukkanda gosterilmez.
    final purchasable =
        CosmicThemes.all.where((t) => !t.isFree).toList(growable: false);

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
                  const Text('🛍️', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    t('shop_title'),
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
                t('shop_subtitle'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: purchasable.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final theme = purchasable[index];
                  final owned = _progress.ownsTheme(theme.id);
                  return ThemePreviewTile(
                    theme: theme,
                    footer: owned
                        ? Text(
                            t('shop_owned'),
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _tryBuy(theme),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      t('shop_buyFor', {'price': '${theme.price}'}),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const MeteorIcon(size: 14),
                                ],
                              ),
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
