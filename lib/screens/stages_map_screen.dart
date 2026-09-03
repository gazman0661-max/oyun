import 'dart:math';

import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/custom_toast.dart';
import '../widgets/stage_button.dart';
import 'orbit_game_screen.dart';

/// "Harita" ekranı: eskiden ana ekrana gömülü olan bölüm/görev ızgarasının
/// (bkz. eski home_screen.dart "Yörünge Vardiyası" bölümü) kendi başına,
/// tertemiz bir sayfaya taşınmış hali. Ana ekran artık sadece kartlar +
/// bu ekrana götüren bir "Harita" butonu gösteriyor; asıl bölüm seçimi
/// buradan yapılıyor.
class StagesMapScreen extends StatefulWidget {
  const StagesMapScreen({super.key});

  @override
  State<StagesMapScreen> createState() => _StagesMapScreenState();
}

class _StagesMapScreenState extends State<StagesMapScreen> {
  final PlayerProgress _progress = PlayerProgress.instance;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgressChanged);
  }

  @override
  void dispose() {
    _progress.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openStage(int stage) async {
    if (stage > _progress.orbitUnlockedStage) {
      CustomToast.show(context, t('home_lockedStage'),
          icon: '🔒', accentColor: AppColors.warning);
      return;
    }
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrbitGameScreen(startStage: stage)),
    );
    if (mounted) {
      SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxShown = max(20, _progress.orbitUnlockedStage + 8);

    return Scaffold(
      body: CosmicThemes.buildActive(
        _progress,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                      locked: stage > _progress.orbitUnlockedStage,
                      isCurrent: stage == _progress.orbitUnlockedStage,
                      stat: _progress.orbitStageStats[stage],
                      onTap: () => _openStage(stage),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              SoundService.instance.buttonTap();
              Navigator.of(context).pop();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tubeGlassBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🛰️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      t('home_orbitSectionTitle'),
                      style: const TextStyle(
                        color: AppColors.accentSoft,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  t('home_chooseStage'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                Text(
                  t('home_stageHint'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
