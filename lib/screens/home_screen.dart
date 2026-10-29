import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/economy_config.dart';
import '../game/planet_merge_physics.dart' show PlanetMergeConfig;
import '../game/ranks.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/cloud_progress_sync.dart';
import '../services/gdpr_service.dart';
import '../services/legal_links.dart';
import '../services/level_progress.dart';
import '../services/localization.dart';
import '../services/play_games_service.dart';
import '../services/player_progress.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/consent_dialog.dart';
import '../widgets/custom_toast.dart';
import '../widgets/daily_result_dialog.dart';
import '../widgets/meteor_icon.dart';
import '../widgets/reward_claim_dialog.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/weekly_reward_strip.dart';
import 'collection_screen.dart';
import 'cosmic_room_screen.dart';
import 'leaderboard_screen.dart';
import 'level_select_screen.dart';
import 'legal_webview_screen.dart';
import 'planet_merge_screen.dart';
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

  // ---- Ogretici hedef anahtarlari + durum ----
  final GlobalKey _kMeteor = GlobalKey();
  final GlobalKey _kRank = GlobalKey();
  final GlobalKey _kBoard = GlobalKey();
  final GlobalKey _kPlay = GlobalKey();
  final GlobalKey _kResupply = GlobalKey();
  final GlobalKey _kTasks = GlobalKey();
  final GlobalKey _kShop = GlobalKey();
  final GlobalKey _kComet = GlobalKey();
  final GlobalKey _kDaily = GlobalKey();
  final GlobalKey _kRoom = GlobalKey();
  bool _tutRunning = false;
  TutorialHandle? _tutHandle;
  Completer<void>? _tutRoute;

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
    // Son acilistan bu yana kac gun gectigini isle (donus hediyesi icin).
    await _progress.noteAppOpen();
    if (!mounted) return;
    // Yeni oyuncu: adim adim ogretici. Bitene kadar diger popup'lar bekler.
    await TutorialService.instance.load();
    if (!mounted) return;
    if (TutorialService.instance.isActive) {
      await _runHomeTutorial();
      return;
    }
    await _maybeShowComebackGift();
    if (!mounted) return;
    if (!_progress.weeklyRewardIsTodayClaimed()) {
      await WeeklyRewardStrip.showPopup(context);
    }
    if (!mounted) return;
    await _maybeOfferStreakRescue();
    if (!mounted) return;
    await _maybeShowRankUp();
  }

  /// Uzun suredir gelmeyen oyuncuya "tekrar hos geldin" hediyesi.
  Future<void> _maybeShowComebackGift() async {
    if (_progress.comebackGiftPending == 0 || !mounted) return;
    final r = await _progress.claimComebackGift();
    if (r == null || !mounted) return;
    await showRewardClaim(
      context,
      title: t('retention_welcomeBack'),
      heroIcon: '🚀',
      items: rewardItemsFor(r),
    );
  }

  /// Seri kopmak uzereyse (en az 3 gunluk): reklam ya da meteorla kurtarma teklifi.
  Future<void> _maybeOfferStreakRescue() async {
    if (!mounted || !_progress.streakRescueAvailable) return;
    final streak = _progress.dailyStreak;
    await _progress.markStreakRescueOffered();
    if (!mounted) return;
    final choice = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StreakRescueDialog(
        streak: streak,
        cost: _progress.streakRescueCurrentCost,
        meteors: _progress.meteors,
      ),
    );
    if (!mounted) return;
    if (choice == 1) {
      final ok = await _progress.rescueStreakWithMeteors();
      if (!mounted) return;
      if (ok) {
        CustomToast.show(context, t('retention_rescued'),
            icon: '🔥', accentColor: AppColors.success);
      } else {
        CustomToast.show(context, t('power_noMeteor'),
            icon: '☄️', accentColor: AppColors.warning);
      }
    } else if (choice == 2) {
      final granted = await AdService.instance.showRewardedAdFlow(
        context,
        icon: '🔥',
        title: t('retention_rescueTitle'),
        placementId: 'streak_rescue',
      );
      if (granted == true) {
        await _progress.rescueStreakFree();
        if (!mounted) return;
        CustomToast.show(context, t('retention_rescued'),
            icon: '🔥', accentColor: AppColors.success);
      }
    }
  }

  /// Yeni rutbeye ulasildiysa kutlama + meteor odulu.
  Future<void> _maybeShowRankUp() async {
    if (!mounted || !_progress.rankRewardPending) return;
    final idx = _progress.rankIndex;
    final meteors = await _progress.claimRankRewards();
    if (meteors <= 0 || !mounted) return;
    final rank = Ranks.all[idx];
    await showRewardClaim(
      context,
      title: t('retention_rankUp', {'rank': t(rank.nameKey)}),
      heroIcon: rank.icon,
      items: [RewardItem('☄️', meteors, t('reward_meteor'))],
    );
  }

  /// Bir oyundan ana ekrana donuldugunde: rutbe atladiysa kutla, seri
  /// koruyucu kurtardiysa haber ver.
  Future<void> _postReturnChecks() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    if (_progress.consumeShieldNotice()) {
      CustomToast.show(context, t('retention_shieldUsed'),
          icon: '🛡️', accentColor: AppColors.success);
    }
    await _maybeShowRankUp();
  }

  // =====================================================================
  // Adim adim ogretici (ana ekran evreleri: home1 / game'e gecis / home2)
  // =====================================================================

  /// Tek bir "Devam" adimi gosterir. Oyuncu ogreticiyi atladiysa false doner.
  Future<bool> _tutStep(TutorialStep step) async {
    if (!mounted) return false;
    final h = TutorialOverlay.show(context, step);
    _tutHandle = h;
    final skipped = await h.done;
    if (skipped) {
      await TutorialService.instance.skip();
      return false;
    }
    return mounted;
  }

  Future<void> _runHomeTutorial() async {
    if (_tutRunning) return;
    final tut = TutorialService.instance;
    _tutRunning = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      if (tut.phase == TutorialPhase.home1) {
        unawaited(AnalyticsService.instance.log('tutorial_begin'));
        if (!await _tutStep(const TutorialStep(textKey: 'tut_welcome'))) return;
        if (!await _tutStep(
            TutorialStep(target: _kMeteor, textKey: 'tut_meteor'))) {
          return;
        }
        await tut.setPhase(TutorialPhase.game);
      }
      if (tut.phase == TutorialPhase.game) {
        // Oyuncu OYNA'ya dokunur; dokunus butona da ulasir ve oyun acilir.
        final h = TutorialOverlay.show(
          context,
          TutorialStep(
            target: _kPlay,
            textKey: 'tut_play',
            advance: TutorialAdvance.targetTap,
          ),
        );
        _tutHandle = h;
        if (await h.done) await tut.skip();
        return;
      }
      if (tut.phase == TutorialPhase.home2) {
        await _runHomeTour();
      }
    } finally {
      _tutRunning = false;
      _tutHandle = null;
    }
  }

  Future<void> _runHomeTour() async {
    final tut = TutorialService.instance;
    const total = 9;
    var n = 0;
    String counter() => '${++n}/$total';

    if (!await _tutStep(TutorialStep(textKey: 'tut_h_back', counter: counter()))) {
      return;
    }
    if (!await _tutStep(TutorialStep(
        target: _kResupply, textKey: 'tut_h_resupply', counter: counter()))) {
      return;
    }

    // Gorevler: oyuncu dokunur, ekranin icinde mini tur, geri donunce devam.
    _tutRoute = Completer<void>();
    final th = TutorialOverlay.show(
      context,
      TutorialStep(
        target: _kTasks,
        textKey: 'tut_h_tasks',
        advance: TutorialAdvance.targetTap,
        counter: counter(),
      ),
    );
    _tutHandle = th;
    if (await th.done) {
      await tut.skip();
      return;
    }
    TutorialService.instance.tasksTourPending = true;
    await _tutRoute!.future;
    if (!mounted || !tut.isActive) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final rest = <(GlobalKey, String)>[
      (_kDaily, 'tut_h_daily'),
      (_kComet, 'tut_h_comet'),
      (_kShop, 'tut_h_shop'),
      (_kRoom, 'tut_h_room'),
      (_kRank, 'tut_h_rank'),
      (_kBoard, 'tut_h_board'),
    ];
    for (final (key, text) in rest) {
      if (!await _tutStep(
          TutorialStep(target: key, textKey: text, counter: counter()))) {
        return;
      }
    }
    if (!await _tutStep(const TutorialStep(textKey: 'tut_h_done', showSkip: false))) {
      return;
    }
    unawaited(AnalyticsService.instance.log('tutorial_complete'));
    await _giveTutorialReward();
    await tut.setPhase(TutorialPhase.done);
    if (mounted) {
      unawaited(_postReturnChecks());
      setState(() {});
    }
  }

  Future<void> _giveTutorialReward() async {
    final tut = TutorialService.instance;
    if (tut.rewardClaimed) return;
    await tut.markRewardClaimed();
    await _progress.addXpAndMeteors(0, 25, source: 'tutorial');
    await _progress.grantPower('bomb', 1, 'tutorial');
    await _progress.grantPower('swap', 1, 'tutorial');
    await _progress.grantPower('shake', 1, 'tutorial');
    if (!mounted) return;
    await showRewardClaim(
      context,
      title: t('tut_reward_title'),
      heroIcon: '🎓',
      items: [
        RewardItem('☄️', 25, t('reward_meteor')),
        RewardItem('💥', 1, t('power_bomb')),
        RewardItem('🔄', 1, t('power_swap')),
        RewardItem('🌀', 1, t('power_shake')),
      ],
    );
  }

  Future<void> _openCollection() async {
    unawaited(AnalyticsService.instance.logScreen('collection'));
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CollectionScreen()),
    );
    if (mounted) setState(() {});
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
    _tutHandle?.close();
    _progress.removeListener(_onProgressChanged);
    _locale.removeListener(_onProgressChanged);
    SoundService.instance.stopBgm();
    super.dispose();
  }

  /// Bir bolum/gorev ekranindan (kinetic_overdrive calan) ana ekrana geri
  /// donulduginde menu muzigini yeniden baslatir (playBgm zaten ayni
  /// track'i tekrar tekrar baslatmaz, sadece degistiginde tepki verir).
  void _resumeMenuMusic() {
    const track = 'audio/where_the_gravity_bends.mp3';
    SoundService.instance.ensureBgm(track);
    unawaited(_postReturnChecks());
    // Gecis animasyonu / ekran kapanisi / (varsa) gecis reklami bittikten
    // sonra tekrar garantiye al. Reklam kapaninca muzik duraklamis ya da
    // durmus kalabiliyordu.
    for (final ms in const [900, 2500, 6000]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (!mounted) return;
        // DUZELTME: kullanici ana ekrana donup bu sure icinde hemen yeni bir
        // oyuna girdiyse (oyun parcasi 'kinetic_overdrive' istenmis olur),
        // menu muzigi oyunun ustune binip onu kesmesin.
        final cur = SoundService.instance.currentBgmAsset;
        if (cur != null && cur != track) return;
        SoundService.instance.ensureBgm(track);
      });
    }
  }

  /// Ilk gunler: ogretici bittikten sonra OYNA, yeni oyuncuyu once Bolum 1'e
  /// goturur (kisa hedef, "bir bolum daha" dongusu). Bolum 1 gecilince ya da
  /// 2 deneme sonra OYNA normale (Sonsuz Mod) doner; Bolumler butonu hep acik.
  Future<Widget> _playScreen() async {
    if (TutorialService.instance.isActive) return const PlanetMergeScreen();
    final prefs = await SharedPreferences.getInstance();
    await LevelProgress.instance.load();
    final tries = prefs.getInt('lv_intro_tries_v1') ?? 0;
    if (tries < 2 && LevelProgress.instance.starsOf(1) == 0) {
      await prefs.setInt('lv_intro_tries_v1', tries + 1);
      unawaited(AnalyticsService.instance
          .log('level_intro_start', {'try': tries + 1}));
      return const PlanetMergeScreen(mode: MergeMode.levels, level: 1);
    }
    return const PlanetMergeScreen();
  }

  Future<void> _openMerge() async {
    SoundService.instance.buttonTap();
    final screen = await _playScreen();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
      // Oyun ici ogretici bittiyse (home2) ya da yarida kaldiysa (game)
      // ana ekran ogreticisi devam eder.
      if (TutorialService.instance.isActive) unawaited(_runHomeTutorial());
    }
  }

  Future<void> _openCosmicRoom() async {
    unawaited(AnalyticsService.instance.logScreen('cosmic_room'));
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CosmicRoomScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openShop() async {
    unawaited(AnalyticsService.instance.logScreen('supply_shop'));
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SupplyShopScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openDaily() async {
    unawaited(AnalyticsService.instance.logScreen('daily'));
    SoundService.instance.buttonTap();
    if (_progress.dailyCompletedToday) {
      await showDialog(
        context: context,
        builder: (_) => const DailyResultDialog(isReplay: true),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const PlanetMergeScreen(mode: MergeMode.daily)),
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
    unawaited(AnalyticsService.instance.logScreen('profile'));
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
                    _profileStat(
                        '🪐',
                        '${_progress.discoveredPlanets.length}/${PlanetMergeConfig.tierCount}',
                        t('profile_totalStars')),
                    _profileStat('🏆', '${_progress.mergeRunsPlayed}',
                        t('profile_stagesCleared')),
                    _profileStat('💯', '${_progress.totalScore}',
                        t('profile_totalScore')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // --- Dil secici (TR / EN / RU / ES / PT / JA) ---
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
              const SizedBox(height: 8),
              Row(
                children: [
                  _langButton(ctx, AppLanguage.es, '🇪🇸 ES'),
                  const SizedBox(width: 8),
                  _langButton(ctx, AppLanguage.pt, '🇧🇷 PT'),
                  const SizedBox(width: 8),
                  _langButton(ctx, AppLanguage.ja, '🇯🇵 JA'),
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
                              activeColor: AppColors.success,
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
                              activeColor: AppColors.success,
                              onChanged: (val) {
                                SoundService.instance.setSfxEnabled(val);
                              },
                            ),
                          ],
                        ),
                        const Divider(
                            height: 1, color: AppColors.tubeGlassBorder),
                        AnimatedBuilder(
                          animation: HapticService.instance,
                          builder: (context, _) => Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t('profile_hapticsLabel'),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12),
                                ),
                              ),
                              Switch(
                                value: HapticService.instance.enabled,
                                activeColor: AppColors.success,
                                onChanged: (val) {
                                  HapticService.instance.setEnabled(val);
                                },
                              ),
                            ],
                          ),
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
                  onPressed: () => LeaderboardScreen.open(context),
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
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await TutorialService.instance.restart();
                  if (mounted) unawaited(_runHomeTutorial());
                },
                child: Text(t('tut_replay'),
                    style: const TextStyle(color: AppColors.accentSoft)),
              ),
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

    return Scaffold(
      body: CosmicThemes.buildActive(
        _progress,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(info),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          KeyedSubtree(
                              key: _kResupply, child: _buildResupplyDock()),
                          KeyedSubtree(key: _kTasks, child: _buildTasksDock()),
                          KeyedSubtree(key: _kShop, child: _buildShopDock()),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _FloatingStation(),
                              const SizedBox(height: 22),
                              KeyedSubtree(
                                  key: _kPlay, child: _buildPlayButton()),
                              const SizedBox(height: 14),
                              _buildStreakStrip(),
                            ],
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildLevelsDock(),
                          KeyedSubtree(key: _kComet, child: _buildCometDock()),
                          KeyedSubtree(key: _kDaily, child: _buildDailyDock()),
                          KeyedSubtree(
                              key: _kRoom, child: _buildCosmicRoomDock()),
                        ],
                      ),
                    ],
                  ),
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
          KeyedSubtree(
            key: _kMeteor,
            child: MeteorBadge(amount: _progress.meteors),
          ),
          const SizedBox(width: 8),
          Row(
            key: _kRank,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _openCollection,
                child: _headerBadge(
                    '${Ranks.forLevel(info.level).icon} ${info.level}'),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _openCollection,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _headerBadge('🪐 ${_progress.discoveredPlanets.length}/${PlanetMergeConfig.tierCount}'),
                    if (_progress.collectionBadgeCount > 0)
                      Positioned(top: -3, right: -3, child: _dotRedBadge()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          KeyedSubtree(
            key: _kBoard,
            child: GestureDetector(
              onTap: () {
                unawaited(AnalyticsService.instance.logScreen('leaderboard'));
                LeaderboardScreen.open(context);
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

  // =====================================================================
  // Ana ekran v3: eski dikdörtgen kartlar yerine, ekranın sol/sağ
  // kenarlarına dizilmiş küçük yuvarlak "dock" ikonları + ortada asılı
  // duran Kozmik İstasyon. Kartların altında duran ikon görselleri
  // (UFO/kargo gemisi) AYNEN korunuyor, sadece boyutu küçültülüp daire
  // içine alındı — durum metinleri (ör. "Hazır! (1/3)") kaldırıldı,
  // dokununca açılan ekranda/diyalogda zaten görünüyor. Merkezdeki
  // istasyon SABİT bir dekor; oyuncunun Kozmik Oda'dan seçtiği tema
  // (bkz. CosmicThemes.buildActive, tüm ekranı zaten sarıyor) arka
  // planda değişerek "dönüşüm" hissini veriyor — bunun için ayrıca bir
  // bağlama gerekmiyor.
  // =====================================================================

  Widget _buildResupplyDock() {
    final ready = _progress.isResupplyReady;
    return _DockIcon(
      icon: _ResupplyPulseIcon(ready: ready),
      label: t('home_resupplyTitle'),
      badge: ready ? _dotBadge() : null,
      onTap: _claimResupply,
      onLongPress: _showResupplyOdds,
    );
  }

  Widget _buildTasksDock() {
    final weeklyReady = _progress.weeklyGoalReady;
    final monthlyReady = _progress.monthlyGoalReady;
    final constellationReady = _progress.constellationGoalReady;
    final readyCount = [weeklyReady, monthlyReady, constellationReady]
            .where((r) => r)
            .length +
        _progress.missionClaimableCount +
        _progress.passClaimableCount;

    return _DockIcon(
      icon: _imageCircleIcon(
        'assets/fx/tasks_ship_card.png',
        background: const LinearGradient(
          colors: [Color(0xFF241947), Color(0xFF0F3D2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      label: t('home_tasksTitle'),
      badge: readyCount > 0 ? _countBadge('$readyCount') : null,
      onTap: _openTasks,
    );
  }

  Future<void> _openTasks() async {
    unawaited(AnalyticsService.instance.logScreen('tasks'));
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TasksScreen()),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
    }
    final r = _tutRoute;
    if (r != null && !r.isCompleted) r.complete();
  }

  /// Kozmik Ikmal karti sagustundeki "i" butonundan acilan, odul
  /// reklaminin hangi ihtimallerle hangi odulu verdigini gosteren ozel
  /// (custom) popup. Sistem uyarisi/AlertDialog gibi degil, uygulamanin
  /// kendi cam/gradyan temasiyla uyumlu bir Dialog kullanir. Artik "i"
  /// butonu yok - ayni diyalog, ikmal ikonuna UZUN BASINCA aciliyor.
  void _showResupplyOdds() {
    SoundService.instance.buttonTap();
    final rows = <(double, String, String)>[
      (EconomyConfig.pMeteor10, '', t('resupply_rewardMeteor', {'n': '10'})),
      (EconomyConfig.pMeteor5, '', t('resupply_rewardMeteor', {'n': '5'})),
      (EconomyConfig.pMeteor3, '', t('resupply_rewardMeteor', {'n': '3'})),
      (EconomyConfig.pMeteor2, '', t('resupply_rewardMeteor', {'n': '2'})),
      (EconomyConfig.pMeteor1, '', t('resupply_rewardMeteor', {'n': '1'})),
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

  /// Ana oyun: Gezegen Birlestir (sonsuz mod). Buyuk "OYNA" dugmesi.
  Widget _buildPlayButton() {
    final best = _progress.mergeBestScore;
    return GestureDetector(
      onTap: _openMerge,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF97316), Color(0xFFEC4899)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEC4899).withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪐', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  t('home_play'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            if (best > 0) ...[
              const SizedBox(height: 2),
              Text(
                '🏆 $best',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Kuyruklu Yildiz kisayolu: etkinlik aciksa ve tamamlanmadiysa yesil nokta,
  /// tamamlandiysa tik, kapaliysa soluk gorunur.
  Widget _buildCometDock() {
    final active = PlayerProgress.cometEventActive();
    final done = _progress.cometCompletedThisEvent;
    return Opacity(
      opacity: active ? 1.0 : 0.55,
      child: _DockIcon(
        icon: _emojiCircleIcon(
          done ? '✅' : '☄️',
          background: const LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFF9D174D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        label: t('home_cometDock'),
        badge: (active && !done) ? _dotBadge() : null,
        onTap: _openComet,
      ),
    );
  }

  Future<void> _openComet() async {
    unawaited(AnalyticsService.instance.logScreen('comet'));
    SoundService.instance.buttonTap();
    final remaining = PlayerProgress.cometTimeRemaining();
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final timeLabel = hours > 0
        ? t('comet_timeHm', {'h': '$hours', 'm': '$minutes'})
        : t('comet_timeM', {'m': '$minutes'});
    if (!PlayerProgress.cometEventActive()) {
      CustomToast.show(context, t('comet_nextIn', {'time': timeLabel}),
          icon: '☄️', accentColor: AppColors.warning);
      return;
    }
    if (_progress.cometCompletedThisEvent) {
      CustomToast.show(context, t('comet_alreadyDone'),
          icon: '☄️', accentColor: AppColors.success);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const PlanetMergeScreen(mode: MergeMode.comet)),
    );
    if (!mounted) return;
    _resumeMenuMusic();
    setState(() {});
  }

  /// Bolum Modu kisayolu (buzlu / kilitli gezegenli sabit bolumler).
  Widget _buildLevelsDock() {
    return _DockIcon(
      icon: _emojiCircleIcon(
        '🪐',
        background: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      label: t('home_levelsDock'),
      onTap: _openLevels,
    );
  }

  Future<void> _openLevels() async {
    unawaited(AnalyticsService.instance.logScreen('levels'));
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LevelSelectScreen()),
    );
    if (!mounted) return;
    _resumeMenuMusic();
    setState(() {});
  }

  Widget _buildShopDock() {
    return _DockIcon(
      icon: _emojiCircleIcon('🧰'),
      label: t('home_shopCardTitle'),
      onTap: _openShop,
    );
  }

  Widget _buildCosmicRoomDock() {
    return _DockIcon(
      icon: _emojiCircleIcon('🛋️'),
      label: t('cosmicRoom_title'),
      onTap: _openCosmicRoom,
    );
  }

  /// Ana ekrandaki seri seridi: alev + seri sayisi, siradaki kilometre
  /// tasina ilerleme cubugu, odul onizlemesi ve zorluk seviyesi.
  Widget _buildStreakStrip() {
    final streak = _progress.activeDailyStreak;
    final next = _progress.nextStreakMilestone;
    final level = _progress.streakDifficultyLevel;
    final titleKey = _progress.streakTitleKey;
    double ratio = 0;
    int daysLeft = 0;
    if (next != null) {
      final prev = EconomyConfig.previousStreakMilestoneDay(streak);
      final span = next.day - prev;
      ratio = span <= 0 ? 0.0 : ((streak - prev) / span).clamp(0.0, 1.0).toDouble();
      daysLeft = next.day - streak;
    }
    final done = _progress.dailyCompletedToday;
    return GestureDetector(
      onTap: _openDaily,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          color: AppColors.tubeGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.tubeGlassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(streak > 0 ? '🔥' : '🕯️',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 5),
                Text(
                  t('daily_streakLine', {'n': '$streak'}),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                if (_progress.streakShields > 0) ...[
                  const SizedBox(width: 4),
                  Text('🛡️${_progress.streakShields}',
                      style: const TextStyle(fontSize: 11.5)),
                ],
                const Spacer(),
                if (level > 0)
                  Text(
                    t('streak_diffTag', {'n': '$level'}),
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  )
                else if (done)
                  const Text('✅', style: TextStyle(fontSize: 12)),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: AppColors.surfaceBorder,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.warning),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                t('streak_nextLine',
                    {'d': '$daysLeft', 'r': next.summary}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (titleKey != null) ...[
              const SizedBox(height: 3),
              Text(
                '🏅 ${t(titleKey)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDailyDock() {
    final completed = _progress.dailyCompletedToday;
    return _DockIcon(
      icon: _emojiCircleIcon(
        completed ? '✅' : '🌌',
        background: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      label: t('home_dailyTitle'),
      badge: _countBadge(
          '🔥${_progress.activeDailyStreak}'
          '${_progress.streakShields > 0 ? '🛡️' : ''}',
          background: AppColors.warning, textColor: const Color(0xFF3A2400)),
      onTap: _openDaily,
    );
  }

  /// Emoji tabanlı basit dock ikonu (Mağaza, Kozmik Oda, Harita, Günlük
  /// Sinyal). `background` verilmezse cam/panel (tubeGlass) rengiyle
  /// notr bir daire olur.
  Widget _emojiCircleIcon(String emoji, {Gradient? background}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: background,
        color: background == null ? AppColors.tubeGlass : null,
        border: Border.all(color: AppColors.tubeGlassBorder, width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 20)),
    );
  }

  /// Gerçek kart görselini (UFO/kargo gemisi PNG'si — DEĞİŞTİRİLMEDİ,
  /// sadece daire içine küçültüldü) kullanan dock ikonu — Kozmik İkmal
  /// ve Görevler için.
  Widget _imageCircleIcon(String asset, {required Gradient background}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: background,
        border: Border.all(color: AppColors.tubeGlassBorder, width: 1.4),
      ),
      padding: const EdgeInsets.all(7),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }

  /// Koleksiyon rozeti icin kucuk kirmizi nokta.
  Widget _dotRedBadge() => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.spaceTop, width: 2),
        ),
      );

  /// Küçük yeşil "hazır" noktası (Kozmik İkmal hazır olduğunda).
  Widget _dotBadge() => Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.spaceTop, width: 2),
        ),
      );

  /// Sayı/metin rozeti (Görevler'de kaç ödül hazır, Harita'da mevcut
  /// bölüm no, Günlük Sinyal'de seri sayısı).
  Widget _countBadge(String text,
      {Color background = AppColors.danger, Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.spaceTop, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: textColor, fontWeight: FontWeight.w800, fontSize: 9)),
    );
  }
}

/// Kopmak uzere olan gunluk seri icin kurtarma teklifi:
/// 1 = meteorla kurtar, 2 = reklam izle, 0 = vazgec.
class _StreakRescueDialog extends StatelessWidget {
  final int streak;
  final int cost;
  final int meteors;
  const _StreakRescueDialog({
    required this.streak,
    required this.cost,
    required this.meteors,
  });

  @override
  Widget build(BuildContext context) {
    final canBuy = meteors >= cost;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 6),
            Text(
              t('retention_rescueTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('retention_rescueBody', {'n': '$streak'}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(2),
                child: Text(
                  t('retention_rescueAd'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentSoft,
                  side: const BorderSide(color: AppColors.accentSoft),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: canBuy ? () => Navigator.of(context).pop(1) : null,
                child: Text(
                  t('retention_rescueMeteor', {'n': '$cost'}),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(0),
              child: Text(
                t('retention_rescueDecline'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sol/sağ kenarlardaki tek bir "dock" ikonu: yuvarlak görsel + altında
/// tek satır isim + (varsa) sağ üst köşede küçük bir durum rozeti.
/// Kozmik İkmal, Görevler, Harita, Mağaza, Kozmik Oda ve Günlük Sinyal
/// hepsi bu ortak kalıbı kullanıyor; içerideki `icon` değişiyor.
class _DockIcon extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  const _DockIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: icon),
                if (badge != null) Positioned(top: -4, right: -4, child: badge!),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 66,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kozmik İkmal ikonunun İÇİ — uzaylı-gemisi görseli (resupply_ufo_card.png,
/// DEĞİŞTİRİLMEDİ) artık küçük bir daire içinde. Hazır olduğunda önceki
/// karttaki gibi çok hafif bir "kalp atışı" (ölçek nefes alma) ve yeşilimsi
/// bir parlama (glow) ile dikkat çeker; hazır değilken sakin durur.
/// Durum METNİ artık YOK (ör. "Hazır! (1/3)") — bu bilgi artık dokununca
/// açılan ödül akışında / uzun basınca açılan "ihtimaller" penceresinde
/// görünüyor, ikonun altında sadece "Kozmik İkmal" ismi kalıyor.
class _ResupplyPulseIcon extends StatefulWidget {
  final bool ready;

  const _ResupplyPulseIcon({required this.ready});

  @override
  State<_ResupplyPulseIcon> createState() => _ResupplyPulseIconState();
}

class _ResupplyPulseIconState extends State<_ResupplyPulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final wave = widget.ready ? sin(_pulse.value * pi) : 0.0;
        final scale = 1.0 + wave * 0.06;
        final glowAlpha = (0.18 + wave * 0.35).clamp(0.0, 1.0);

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0B1640), Color(0xFF1A3A7A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.tubeGlassBorder, width: 1.4),
              boxShadow: widget.ready
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7EE06A)
                            .withValues(alpha: glowAlpha),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(7),
            child: Opacity(
              opacity: widget.ready ? 1.0 : 0.75,
              child: Image.asset(
                'assets/fx/resupply_ufo_card.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ana ekranın merkezindeki, boşlukta asılı duran Kozmik İstasyon.
/// Kullanıcının gönderdiği referans görsele göre hazırlanmış istasyon
/// çizimi (assets/fx/cosmic_station.png, arka planı temizlenmiş) bir
/// parlama/zemin halkasının üzerinde oturuyor; ikisi birlikte çok hafif,
/// yumuşak bir sinüs hareketiyle sağa-sola / yukarı-aşağı süzülüyor —
/// amaç "uzayda asılı durma" hissini vermek, dikkat dağıtacak kadar
/// belirgin olmamak. İstasyonun kendisi SABİT bir dekor: temaya göre
/// değişmiyor. Görsel "dönüşüm" hissi, bu ekranı zaten saran
/// CosmicThemes.buildActive arka planından (bkz. HomeScreen.build)
/// geliyor — Kozmik Oda'dan yeni bir tema aktif edildiğinde otomatik
/// olarak burada da görünür.
class _FloatingStation extends StatefulWidget {
  const _FloatingStation();

  @override
  State<_FloatingStation> createState() => _FloatingStationState();
}

class _FloatingStationState extends State<_FloatingStation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    // 7 saniyelik yavaş, surekli bir dongu - "cok yumusak" istegine
    // uygun olsun diye genlik kucuk tutuldu (bkz. asagidaki dx/dy).
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ekranin en kisa kenarina oranli, SABIT bir aralikta kalan hedef
    // boyut - "orta halli" istegine uygun, onceki sabit 220px'den
    // kucultuldu. Ayrica LayoutBuilder ile gercekten ayrilan alanin
    // (sol/sag dock ikonlari arasinda kalan bosluk) genisligini de
    // hesaba katip onu asmiyoruz - dar telefonlarda tasma olmasin diye.
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final target = (shortestSide * 0.30).clamp(110.0, 175.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth - 24
            : target;
        final stationWidth = target < available ? target : available.clamp(70.0, target);
        final glowWidth = stationWidth * 0.86;
        final glowHeight = stationWidth * 0.19;

        return AnimatedBuilder(
          animation: _drift,
          builder: (context, child) {
            final t = _drift.value * 2 * pi;
            final dx = sin(t) * 6;
            final dy = cos(t * 0.8) * 5;
            return Transform.translate(offset: Offset(dx, dy), child: child);
          },
          child: SizedBox(
            width: stationWidth + 24,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                // Istasyonun altindaki asili "zemin" - gercek bir platform
                // gorseli yerine, yumusak bir isik halkasi ile temsil
                // ediliyor; boylece hangi tema aktif olursa olsun uyumlu
                // kalıyor.
                Container(
                  width: glowWidth,
                  height: glowHeight,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.32),
                        AppColors.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image.asset(
                    'assets/fx/cosmic_station.png',
                    fit: BoxFit.contain,
                    width: stationWidth,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
