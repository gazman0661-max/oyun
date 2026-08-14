import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/custom_toast.dart';
import '../widgets/theme_preview_tile.dart';
import 'theme_shop_screen.dart';

/// "Kozmik Oda": oyuncunun SAHIP OLDUGU arkaplan temalarini (varsayilan
/// dahil) gosterir, birini secip ana ekranda etkinlestirmesini saglar.
/// Satin alma burada YAPILMAZ — "Dükkana Git" butonuyla ThemeShopScreen'e
/// yonlendirilir.
class CosmicRoomScreen extends StatefulWidget {
  const CosmicRoomScreen({super.key});

  @override
  State<CosmicRoomScreen> createState() => _CosmicRoomScreenState();
}

class _CosmicRoomScreenState extends State<CosmicRoomScreen> {
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

  Future<void> _activate(CosmicTheme theme) async {
    if (_progress.activeTheme == theme.id) return;
    SoundService.instance.buttonTap();
    await _progress.setActiveTheme(theme.id);
    if (!mounted) return;
    CustomToast.show(
      context,
      '${t(theme.nameKey)} ${t('cosmicRoom_active')}',
      icon: '✨',
      accentColor: AppColors.success,
    );
  }

  /// Takımyıldız rozetleri: meteor havuzundan BAĞIMSIZ, kalıcı bir
  /// koleksiyon (bkz. PlayerProgress.unlockedConstellationBadges). Kozmik
  /// Oda zaten oyuncunun "sahip olduklarını" gösterdiği ekran olduğu için
  /// tema listesinin hemen üstüne, ayrı bir koleksiyon şeridi olarak
  /// oturuyor.
  Widget _buildBadgesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('badges_title'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            t('badges_hint'),
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: EconomyConfig.constellationRotation
                .map((def) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _buildBadgeTile(def),
                    ))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeTile(ConstellationDef def) {
    final unlocked = _progress.hasConstellationBadge(def.id);
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: unlocked ? AppColors.accent.withValues(alpha: 0.15) : null,
            border: Border.all(
              color: unlocked
                  ? AppColors.accent
                  : AppColors.tubeGlassBorder,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Opacity(
            opacity: unlocked ? 1.0 : 0.3,
            child: Text(def.badgeIcon, style: const TextStyle(fontSize: 24)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          unlocked ? t(def.nameKey) : t('badges_locked'),
          style: TextStyle(
            color: unlocked ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final owned = CosmicThemes.all
        .where((t) => _progress.ownsTheme(t.id))
        .toList(growable: false);

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
                  const Text('🛋️', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    t('cosmicRoom_title'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                t('cosmicRoom_materialsHint'),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            _buildBadgesSection(),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                itemCount: owned.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, index) {
                  final theme = owned[index];
                  final active = _progress.activeTheme == theme.id;
                  return ThemePreviewTile(
                    theme: theme,
                    highlight: active,
                    footer: active
                        ? Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: AppColors.success, size: 15),
                              const SizedBox(width: 4),
                              Text(
                                t('cosmicRoom_active'),
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _activate(theme),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(
                                    color: AppColors.tubeGlassBorder),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                textStyle: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700),
                              ),
                              child: Text(t('cosmicRoom_activate')),
                            ),
                          ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    SoundService.instance.buttonTap();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ThemeShopScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(t('cosmicRoom_goToShop')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
