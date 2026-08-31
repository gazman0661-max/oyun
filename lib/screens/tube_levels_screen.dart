import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/player_progress.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/custom_toast.dart';
import '../widgets/stage_button.dart';
import 'game_screen.dart';

/// Enerji Tupleri (klasik renk siralama) modunun kendi bolum secim
/// ekrani. Ana ekrandaki Orbit Jam izgarasinin ayni tasarimini kullanir;
/// bir bolume girildiginde asil oyun ekrani (GameScreen) zaten her acilista
/// rastgele bir arkaplan animasyonu (LevelBackground) secip gosterir.
class TubeLevelsScreen extends StatefulWidget {
  const TubeLevelsScreen({super.key});

  @override
  State<TubeLevelsScreen> createState() => _TubeLevelsScreenState();
}

class _TubeLevelsScreenState extends State<TubeLevelsScreen> {
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

  Future<void> _openStage(int stage) async {
    if (stage > _progress.unlockedStage) {
      CustomToast.show(context, t('tubeLevels_lockedToast'),
          icon: '🔒', accentColor: AppColors.warning);
      return;
    }
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(startLevel: stage)),
    );
    if (mounted) {
      SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxShown = math.max(20, _progress.unlockedStage + 8);
    return Scaffold(
      body: CosmicThemes.buildActive(
        _progress,
        child: SafeArea(
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
                    const Text('🧪', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(
                      t('tubeLevels_title'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Text(
                      t('tubeLevels_subtitle'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: maxShown,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.92,
                      ),
                      itemBuilder: (context, index) {
                        final stage = index + 1;
                        return StageButton(
                          stage: stage,
                          locked: stage > _progress.unlockedStage,
                          isCurrent: stage == _progress.unlockedStage,
                          stat: _progress.stageStats[stage],
                          onTap: () => _openStage(stage),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
