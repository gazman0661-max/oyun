import 'dart:math';

import 'package:flutter/material.dart';

import '../game/level_mode.dart';
import '../services/level_progress.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'planet_merge_screen.dart';

/// Bolum Modu: bolum secme ekrani (4 sutunlu izgara, yildizlar, kilitler).
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  final ScrollController _scroll = ScrollController();
  bool _didScroll = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await LevelProgress.instance.load();
    if (!mounted) return;
    setState(() {});
    // Ilk acilista siradaki bolume kaydir.
    if (!_didScroll) {
      _didScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final w = MediaQuery.of(context).size.width;
        final tileH = ((w - 32 - 36) / 4) / 0.8;
        final row = (LevelProgress.instance.nextLevel - 1) ~/ 4;
        final target = max(0.0, (row - 1) * (tileH + 12));
        _scroll.jumpTo(min(target, _scroll.position.maxScrollExtent));
      });
    }
  }

  Future<void> _play(int level) async {
    final progress = LevelProgress.instance;
    if (!progress.isUnlocked(level)) {
      SoundService.instance.invalid();
      return;
    }
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PlanetMergeScreen(mode: MergeMode.levels, level: level),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final progress = LevelProgress.instance;
    final next = progress.nextLevel;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.spaceTop,
              AppColors.spaceMid,
              AppColors.spaceBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: AppColors.textPrimary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        '🪐 ${t('lv_select_title')}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    Text(
                      '⭐ ${progress.totalStars}',
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  // Sonsuz: acik bolumun 12 ilerisine kadar goster, ilerledikce uzar.
                  itemCount: max(24, ((next + 12) / 4).ceil() * 4),
                  itemBuilder: (context, i) => _tile(i + 1, next),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(int n, int next) {
    final progress = LevelProgress.instance;
    final unlocked = progress.isUnlocked(n);
    final stars = progress.starsOf(n);
    final isNext = unlocked && n == next && stars == 0;
    final lv = LevelCatalog.level(n);
    const gold = Color(0xFFFFD54F);
    return GestureDetector(
      onTap: () => _play(n),
      child: Opacity(
        opacity: unlocked ? 1.0 : 0.45,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: stars > 0
                  ? const [Color(0xFF3B2A7A), Color(0xFF1E3A8A)]
                  : const [Color(0xFF1B2250), Color(0xFF111735)],
            ),
            border: Border.all(
              color: isNext ? gold : AppColors.tubeGlassBorder,
              width: isNext ? 2.2 : 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!unlocked)
                const Text('🔒', style: TextStyle(fontSize: 22))
              else
                Text(
                  '$n',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 3; i++)
                    Text(
                      i <= stars ? '⭐' : '·',
                      style: TextStyle(
                        fontSize: i <= stars ? 11 : 14,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${lv.hasIce ? '🧊' : ''}${lv.hasLocks ? '🔒' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
