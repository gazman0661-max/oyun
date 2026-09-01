import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/cloud_progress_sync.dart';
import '../services/gdpr_service.dart';
import '../services/legal_links.dart';
import '../services/localization.dart';
import '../services/play_games_service.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/consent_dialog.dart';
import '../widgets/custom_toast.dart';
import '../widgets/daily_result_dialog.dart';
import '../widgets/meteor_icon.dart';
import '../widgets/stage_button.dart';
import '../widgets/weekly_reward_strip.dart';
import 'cosmic_room_screen.dart';
import 'legal_webview_screen.dart';
import 'orbit_game_screen.dart';
import 'supply_shop_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerProgress _progress = PlayerProgress.instance;
  final AppLocale _locale = AppLocale.instance;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgressChanged);
    _locale.addListener(_onProgressChanged);
    // Ikmal geri sayimini ve gunluk kartini canli tutmak icin periyodik
    // yenileme (yeni bir olay olmasa bile).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Dil secimi tamamlandiktan hemen sonra (veya bu ekrana her donuste,
    // henuz onaylanmadiysa) Kullanim Sartlari + GDPR onay popup'ini goster.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLaunchPopups());
    // Ana ekran muzigi: basa sardirilarak sonsuz dongude calar.
    SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
  }

  /// Açılışta sırayla gösterilecek popup'ları yönetir: önce Kullanım
  /// Şartları/GDPR onayı (varsa), o kapandıktan SONRA — bugünün haftalık
  /// ödülü henüz alınmadıysa — haftalık ödül takvimi popup'ı. Bu metot
  /// sadece initState'ten (bir kere, uygulama açılışında) çağrılır; ekran
  /// içindeki başka bir yerden tekrar tetiklenmez.
  Future<void> _runLaunchPopups() async {
    await _maybeShowConsent();
    if (!mounted) return;
    if (!_progress.weeklyRewardIsTodayClaimed()) {
      await WeeklyRewardStrip.showPopup(context);
    }
  }

  Future<void> _maybeShowConsent() async {
    if (!mounted) return;
    if (!GdprService.instance.loaded) {
      await GdprService.instance.load();
    }
    if (!mounted) return;
    if (GdprService.instance.needsConsentPrompt) {
      await ConsentDialog.show(context);
    }
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _progress.removeListener(_onProgressChanged);
    _locale.removeListener(_onProgressChanged);
    SoundService.instance.stopBgm();
    super.dispose();
  }

  /// Bir bolum/gorev ekranindan (kinetic_overdrive calan) ana ekrana geri
  /// donulduginde menu muzigini yeniden baslatir (playBgm zaten ayni
  /// track'i tekrar tekrar baslatmaz, sadece degistiginde tepki verir).
  void _resumeMenuMusic() {
    SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
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
      _resumeMenuMusic();
      setState(() {});
    }
  }

  Future<void> _openDaily() async {
    SoundService.instance.buttonTap();
    if (_progress.dailyCompletedToday) {
      await showDialog(
        context: context,
        builder: (_) => const DailyResultDialog(isReplay: true),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrbitGameScreen(isDaily: true)),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
    }
  }

  Future<void> _claimResupply() async {
    if (!_progress.isResupplyReady) {
      unawaited(AnalyticsService.instance.logResupplyNotReady());
      CustomToast.show(
          context, '⏳ ${_progress.resupplyCountdownText()}',
          icon: '🛰️', accentColor: AppColors.accent);
      return;
    }
    SoundService.instance.buttonTap();
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🎁',
      title: t('home_resupplyTitle'),
      subtitle: t('ad_defaultSubtitle'),
      placementId: 'resupply',
    );
    if (granted != true || !mounted) return;
    final reward = await _progress.grantResupplyReward(Random());
    if (!mounted) return;
    SoundService.instance.reward();
    final rewardText = switch (reward.kind) {
      ResupplyRewardKind.xp => t('resupply_rewardXp', {'n': '${reward.amount}'}),
      ResupplyRewardKind.orbitDockSlot =>
        t('resupply_rewardOrbitDockSlot', {'n': '${reward.amount}'}),
      // Meteor dilimi kazanıldığında taban miktar + bonus meteor tek
      // satırda toplu gösterilir (ör. "7 Meteor" = 5 taban + 2 bonus).
      ResupplyRewardKind.meteor => t('resupply_rewardMeteor',
          {'n': '${reward.amount + reward.bonusMeteors}'}),
    };
    // Meteor dışındaki her ödül türünde, üstüne eklenen rastgele bonus
    // meteor AYRI bir satırda gösterilir (ör. "100 XP" + "+3 Meteor").
    final showsSeparateBonus =
        reward.kind != ResupplyRewardKind.meteor && reward.bonusMeteors > 0;
    final rewardIcon = switch (reward.kind) {
      ResupplyRewardKind.xp => '✨',
      ResupplyRewardKind.orbitDockSlot => '⚓',
      ResupplyRewardKind.meteor => '☄️',
    };
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rewardIcon, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                t('resupply_rewardTitle'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.tubeGlass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.tubeGlassBorder),
                ),
                child: Text(
                  rewardText,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (showsSeparateBonus) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.35)),
                  ),
                  child: Text(
                    '☄️ ${t('resupply_bonusMeteor', {
                          'n': '${reward.bonusMeteors}'
                        })}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(t('resupply_close'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    showDialog(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: _locale,
        builder: (context, _) {
          final info = _progress.levelInfo();
          return Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.accent,
                backgroundImage: AssetImage('assets/icon/profile_icon.jpg'),
              ),
              const SizedBox(height: 14),
              // --- Seviye ilerleme cubugu (HTML'deki level-progress-track/fill) ---
              Row(
                children: [
                  Text('🎖️ ${t('profile_level')} ${info.level}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const Spacer(),
                  Text('${info.xpIntoLevel} / ${info.xpForNext} XP',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 10,
                  child: Stack(
                    children: [
                      Container(color: AppColors.surfaceBorder),
                      FractionallySizedBox(
                        widthFactor: info.progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.accentSoft,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tubeGlass,
                  border: Border.all(color: AppColors.tubeGlassBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _profileStat('⭐', '${_progress.totalStars}',
                        t('profile_totalStars')),
                    _profileStat('🏆', '${_progress.orbitStageStats.length}',
                        t('profile_stagesCleared')),
                    _profileStat('💯', '${_progress.totalScore}',
                        t('profile_totalScore')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // --- Dil secici (TR / EN / RU) ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_language'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _langButton(ctx, AppLanguage.tr, '🇹🇷 TR'),
                  const SizedBox(width: 8),
                  _langButton(ctx, AppLanguage.en, '🇬🇧 EN'),
                  const SizedBox(width: 8),
                  _langButton(ctx, AppLanguage.ru, '🇷🇺 RU'),
                ],
              ),
              const SizedBox(height: 16),
              // --- Ses ayarlari: muzik / efekt anahtarlari ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_soundSettings'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: SoundService.instance,
                builder: (context, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.tubeGlass,
                      border: Border.all(color: AppColors.tubeGlassBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('profile_musicLabel'),
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                            ),
                            Switch(
                              value: SoundService.instance.musicEnabled,
                              activeThumbColor: AppColors.success,
                              onChanged: (val) {
                                SoundService.instance.setMusicEnabled(val);
                              },
                            ),
                          ],
                        ),
                        const Divider(
                            height: 1, color: AppColors.tubeGlassBorder),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('profile_sfxLabel'),
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                            ),
                            Switch(
                              value: SoundService.instance.sfxEnabled,
                              activeThumbColor: AppColors.success,
                              onChanged: (val) {
                                SoundService.instance.setSfxEnabled(val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // --- Play Games baglantisi (sadece giris + ilerleme kaydi) ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_playGames'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              StatefulBuilder(
                builder: (ctx2, setDialogState) {
                  final connected = PlayGamesService.instance.isSignedIn;
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: connected
                          ? null
                          : () async {
                              final ok =
                                  await PlayGamesService.instance.signIn();
                              if (ok) {
                                await CloudProgressSync.instance
                                    .syncAfterSignIn();
                              }
                              setDialogState(() {});
                              if (!ok && ctx2.mounted) {
                                CustomToast.show(
                                    ctx2, t('profile_playGamesFailed'),
                                    icon: '⚠️', accentColor: AppColors.danger);
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            connected ? AppColors.success : AppColors.textPrimary,
                        side: BorderSide(
                          color: connected
                              ? AppColors.success
                              : AppColors.tubeGlassBorder,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        connected
                            ? t('profile_playGamesConnected')
                            : t('profile_playGamesConnect'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              // --- Skor tablosu (Play Games'in kendi Gunluk/Haftalik/
              //     Tum-zamanlar ekrani; ayrica bir custom UI gerektirmez) ---
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => PlayGamesService.instance.showLeaderboard(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.tubeGlassBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(t('profile_leaderboard')),
                ),
              ),
              const SizedBox(height: 16),
              // --- Gizlilik Politikasi & Kullanim Sartlari (in-app) ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_legal'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.tubeGlassBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        SoundService.instance.buttonTap();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalWebViewScreen(
                              url: LegalLinks.privacyPolicyUrl,
                              title: t('legal_privacyPolicy'),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        t('legal_privacyPolicy'),
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.tubeGlassBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        SoundService.instance.buttonTap();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalWebViewScreen(
                              url: LegalLinks.termsUrl,
                              title: t('legal_terms'),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        t('legal_terms'),
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              // --- Reklam rizasini yonetme (Appodeal'in KENDI resmi
              // Google UMP tabanli onay formunu tekrar acar) — artik AB
              // bolgesine gore manuel gizlenmiyor, herkese gosteriliyor;
              // Appodeal formu gerekli degilse zaten kendi icinde no-op
              // davranir. ---
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tubeGlass,
                  border: Border.all(color: AppColors.tubeGlassBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('profile_gdprSettingLabel'),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('profile_gdprSettingHint'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.accentSoft),
                          foregroundColor: AppColors.accentSoft,
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          SoundService.instance.buttonTap();
                          GdprService.instance.openAdConsentForm();
                        },
                        child: Text(
                          t('profile_gdprManageButton'),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t('profile_close'),
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ],
            ),
          ),
        ),
      );
        },
      ),
    );
  }

  Widget _langButton(BuildContext ctx, AppLanguage lang, String label) {
    final active = _locale.language == lang;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          SoundService.instance.buttonTap();
          _locale.setLanguage(lang);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.tubeGlass,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.tubeGlassBorder,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileStat(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
        Text(label,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _progress.levelInfo();
    final maxShown = max(20, _progress.orbitUnlockedStage + 8);

    return Scaffold(
      body: CosmicThemes.buildActive(
        _progress,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(info),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildResupplyCard()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTasksNavCard()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDailyCard(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text('🛰️', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Text(
                          t('home_orbitSectionTitle'),
                          style: const TextStyle(
                            color: AppColors.accentSoft,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('home_chooseStage'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('home_stageHint'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
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
                          locked: stage > _progress.orbitUnlockedStage,
                          isCurrent: stage == _progress.orbitUnlockedStage,
                          stat: _progress.orbitStageStats[stage],
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

  Widget _buildHeader(LevelInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          const Spacer(),
          MeteorBadge(amount: _progress.meteors),
          const SizedBox(width: 8),
          _headerBadge('🎖️ ${info.level}'),
          const SizedBox(width: 8),
          _headerBadge('⭐ ${_progress.totalStars}'),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              SoundService.instance.buttonTap();
              PlayGamesService.instance.showLeaderboard();
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tubeGlassBorder),
              ),
              child: const Text('🏆', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              SoundService.instance.buttonTap();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupplyShopScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tubeGlassBorder),
              ),
              child: const Text('🧰', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              SoundService.instance.buttonTap();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CosmicRoomScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tubeGlassBorder),
              ),
              child: const Text('🛋️', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openProfile,
            child: const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.accent,
              child: Icon(Icons.person_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tubeGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.tubeGlassBorder),
      ),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }

  /// "Görevler" kartı: artık Tüp Modu kartının yerinde, aynı boyutta bir
  /// hızlı-gezinme kartı. Haftalık/aylık/takımyıldız/kuyruklu yıldız
  /// görevlerinin detayı burada AÇILIP KAPANMIYOR — dokununca ayrı, tam
  /// ekran bir sayfaya (bkz. TasksScreen) yönlendiriyor. Kapalıyken bile
  /// kaç ödülün alınmaya hazır olduğu küçük bir rozetle görünür, böylece
  /// hiçbir ödül gözden kaçmaz.
  Widget _buildTasksNavCard() {
    final weeklyReady = _progress.weeklyGoalReady;
    final monthlyReady = _progress.monthlyGoalReady;
    final constellationReady = _progress.constellationGoalReady;
    final cometActive = PlayerProgress.cometEventActive();
    final cometDone = _progress.cometCompletedThisEvent;
    final cometPlayable = cometActive && !cometDone;

    final readyCount = [weeklyReady, monthlyReady, constellationReady]
        .where((r) => r)
        .length;

    final subtitle = readyCount > 0
        ? t('home_tasksSubtitle_ready', {'n': '$readyCount'})
        : cometPlayable
            ? t('home_tasksSubtitle_comet')
            : t('home_tasksSubtitle_default');

    return GestureDetector(
      onTap: _openTasks,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C5CFF), Color(0xFF22C55E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🎯', style: TextStyle(fontSize: 26)),
                Row(
                  children: [
                    if (readyCount > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$readyCount',
                          style: const TextStyle(
                              color: Color(0xFF7C5CFF),
                              fontWeight: FontWeight.w800,
                              fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t('home_tasksTitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTasks() async {
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TasksScreen()),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
    }
  }

  Widget _buildResupplyCard() {
    final ready = _progress.isResupplyReady;
    final watched = _progress.resupplyAdsWatched;
    return Stack(
      children: [
        GestureDetector(
          onTap: _claimResupply,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFA855F7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Opacity(
              opacity: ready ? 1.0 : 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 26)),
                  const SizedBox(height: 8),
                  Text(t('home_resupplyTitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    t('home_resupplySubtitle'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ready
                        ? '${t('home_resupplyReady')} ($watched/3)'
                        : '⏳ ${_progress.resupplyCountdownText()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _showResupplyOdds,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              alignment: Alignment.center,
              child: const Text('i',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
            ),
          ),
        ),
      ],
    );
  }

  /// Kozmik Ikmal karti sagustundeki "i" butonundan acilan, odul
  /// reklaminin hangi ihtimallerle hangi odulu verdigini gosteren ozel
  /// (custom) popup. Sistem uyarisi/AlertDialog gibi degil, uygulamanin
  /// kendi cam/gradyan temasiyla uyumlu bir Dialog kullanir.
  void _showResupplyOdds() {
    SoundService.instance.buttonTap();
    final rows = <(double, String, String)>[
      (EconomyConfig.pMeteor10, '', t('resupply_rewardMeteor', {'n': '10'})),
      (EconomyConfig.pMeteor5, '', t('resupply_rewardMeteor', {'n': '5'})),
      (EconomyConfig.pMeteor3, '', t('resupply_rewardMeteor', {'n': '3'})),
      (EconomyConfig.pMeteor2, '', t('resupply_rewardMeteor', {'n': '2'})),
      (
        EconomyConfig.pXp,
        '💯',
        t('resupply_rewardXp', {'n': '${EconomyConfig.xpRewardAmount}'})
      ),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t('resupply_oddsTitle'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t('resupply_oddsHint'),
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4),
              ),
              const SizedBox(height: 14),
              ...rows.map((row) {
                final percentText = t('resupply_oddsPercent',
                    {'p': (row.$1 * 100).toStringAsFixed(0)});
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.tubeGlass,
                      border: Border.all(color: AppColors.tubeGlassBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (row.$2.isNotEmpty) ...[
                          Text(row.$2, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                        ],
                        Text(percentText,
                            style: const TextStyle(
                                color: AppColors.accentSoft,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(row.$3,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    SoundService.instance.buttonTap();
                    Navigator.of(ctx).pop();
                  },
                  child: Text(t('resupply_oddsClose'),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyCard() {
    final completed = _progress.dailyCompletedToday;
    return GestureDetector(
      onTap: _openDaily,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Text(completed ? '✅' : '🌌', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completed ? t('home_dailyDoneTitle') : t('home_dailyTitle'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    completed
                        ? t('home_dailyDoneSubtitle')
                        : t('home_dailySubtitle'),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('🔥${_progress.dailyStreak}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

}

