import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/economy_config.dart';
import '../game/orbit_controller.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/rate_prompt_service.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/daily_result_dialog.dart';
import '../widgets/custom_toast.dart';
import '../widgets/coach_overlay.dart';
import '../widgets/meteor_icon.dart';
import '../widgets/orbit_board.dart';
import '../widgets/orbit_planet_chip.dart';
import '../widgets/backgrounds/level_background.dart';
import '../widgets/fx/celebration_fx.dart';

class OrbitGameScreen extends StatefulWidget {
  final int? startStage;
  final bool isDaily;
  final bool isComet;
  const OrbitGameScreen({
    super.key,
    this.startStage,
    this.isDaily = false,
    this.isComet = false,
  }) : assert(startStage != null || isDaily || isComet);

  @override
  State<OrbitGameScreen> createState() => _OrbitGameScreenState();
}

class _OrbitGameScreenState extends State<OrbitGameScreen> {
  late int _stage;
  late OrbitController _controller;
  bool _dialogShown = false;
  int? _lastUnlockNotified;
  Stopwatch _stopwatch = Stopwatch();

  /// Bu bölüm denemesinde rıhtım genişletme için reklam/meteor/banka
  /// kurtarması kullanıldı mı? "Temiz kazanım" (rate-prompt ve
  /// cleanStages haftalık görevi) SADECE bu false iken sayılır — her
  /// yeni denemede (_startLevel) sıfırlanır.
  bool _usedAssistThisAttempt = false;

  static const _tutorialPrefsKey = 'orbit_tutorial_seen_v2';
  final GlobalKey _boardKey = GlobalKey();
  final GlobalKey _targetStripKey = GlobalKey();
  final GlobalKey _dockKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _stage = widget.startStage ?? 1;
    _startLevel(_stage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
    // Bolum ekrani muzigi: sonsuz dongude calar (ana ekrandaki menu
    // muzigini otomatik olarak durdurup yerini alir).
    SoundService.instance.playBgm('audio/kinetic_overdrive.mp3');
  }

  Future<void> _maybeShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_tutorialPrefsKey) ?? false;
    if (seen || !mounted) return;
    await prefs.setBool(_tutorialPrefsKey, true);
    if (!mounted) return;
    _showTutorialDialog();
  }

  /// DUZELTME (onboarding/retention iyilestirmesi): Bu tutorial artik 3
  /// ekrani art arda OKUTUP gecirmiyor. Ozellikle "hangi yon" kurali
  /// (dokunulan noktanin halkaya gore sol/sag konumu) salt metinle
  /// anlatilmasi zor, sezgisel olmayan bir kural — reels/TikTok'tan
  /// meraktan gelen, hizli tatmin bekleyen bir oyuncu icin bu, ilk 2
  /// dakikada birakip gitme riskini artiran bir surtunme noktasiydi.
  ///
  /// Yeni akis:
  ///   1) "Hangi halka?" — kisa, statik aciklama (basit kavram).
  ///   2) "Hangi yon?" — ARTIK INTERAKTIF: overlay ekrani bloke etmiyor,
  ///      oyuncu GERCEKTEN bir halkaya dokunup deneyene kadar bekliyor
  ///      (bkz. CoachOverlay.waitForAction + actionListenable/actionValue,
  ///      _controller.rotations sayacindaki degisim algilaniyor) ve
  ///      hamle yapilinca otomatik ilerliyor. Okuyarak degil, yaparak
  ///      ogreniliyor.
  ///   3) "Kapı ve rıhtım" — kademeli acilma (progressive disclosure):
  ///      oyuncu daha ilk hamlesini YENI yapmisken, taze deneyiminin
  ///      hemen ardindan gosteriliyor; boylece 3 kural bir anda ustune
  ///      bosaltilmiyor.
  void _showTutorialDialog() {
    CoachOverlay.show(
      context,
      steps: [
        CoachStep(
          targetKey: _boardKey,
          title: t('orbit_rule1Title'),
          body: t('orbit_rule1Body'),
        ),
        CoachStep(
          targetKey: _boardKey,
          title: t('orbit_rule2Title'),
          body: t('orbit_rule2TryBody'),
          waitForAction: true,
        ),
        CoachStep(
          targetKey: _dockKey,
          title: t('orbit_rule3TryTitle'),
          body: t('orbit_rule3Body'),
        ),
      ],
      // Oyuncunun gercekten bir halka dondurup dondurmedigini anlamak
      // icin OrbitController'i (zaten bir ChangeNotifier) dinliyoruz;
      // "ilerleme sayaci" olarak da controller.rotations'i kullaniyoruz.
      actionListenable: _controller,
      actionValue: () => _controller.rotations,
    );
  }

  void _startLevel(int stage) {
    if (widget.isDaily) {
      _controller = OrbitController.daily(
        dailyNumber: PlayerProgress.dailyNumber(),
        seed: PlayerProgress.dailySeed(),
      );
    } else if (widget.isComet) {
      _controller =
          OrbitController.cometEvent(PlayerProgress.cometEventNumber());
    } else {
      _controller = OrbitController.forStage(stage, random: Random());
    }
    _dialogShown = false;
    _usedAssistThisAttempt = false;
    _stopwatch = Stopwatch()..start();
    _controller.addListener(_onStateChanged);
    if (!widget.isDaily && !widget.isComet) {
      unawaited(AnalyticsService.instance.logLevelStart('orbit', stage));
    }
  }

  void _onStateChanged() {
    if (_controller.lastUnlockedRing != null &&
        _controller.lastUnlockedRing != _lastUnlockNotified) {
      _lastUnlockNotified = _controller.lastUnlockedRing;
      SoundService.instance.reward();
      if (mounted) {
        CustomToast.show(context, t('orbit_ringUnlocked'),
            icon: '🔓',
            accentColor: AppColors.success,
            duration: const Duration(milliseconds: 1100));
      }
    }
    if (_dialogShown) return;
    if (_controller.status == OrbitStatus.won) {
      _dialogShown = true;
      _handleWin();
    } else if (_controller.status == OrbitStatus.jammed) {
      _dialogShown = true;
      _showJamDialog();
    }
    if (mounted) setState(() {});
  }

  /// DUZELTME (istek/sıralama): bolum basariyla tamamlaninca sıralama artik
  /// soyle: 1) konfeti + havai fisek + ucan uzaylilar TAM EKRAN oynar,
  /// 2) bu kutlama TAMAMEN bitince ANCAK O ZAMAN ozel sonuc popup'i (yildizlar,
  /// 2x XP / Sonraki Bolum butonlari) acilir. Kutlama, `Navigator`/`Overlay`
  /// uzerine gecici bir `OverlayEntry` olarak eklenir; oyun tahtasinin
  /// UZERINDE gorunur ve bittiginde kendini kaldirir.
  Future<void> _playCelebrationOverlay(int stars) async {
    final overlayState = Overlay.of(context);
    final completer = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => LevelCompleteCelebration(
        stars: stars,
        onComplete: () {
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    overlayState.insert(entry);
    try {
      await completer.future;
    } finally {
      entry.remove();
    }
  }

  Future<void> _handleWin() async {
    _stopwatch.stop();
    final stars = _controller.starsForResult();
    final colorCount = _controller.level.targetQueue.toSet().length;
    await PlayerProgress.instance.markPlanetsDiscovered(colorCount);

    if (widget.isDaily) {
      await PlayerProgress.instance.recordDailyResult(
        moves: _controller.rotations,
        optimal: _controller.level.parRotations,
        timeSeconds: _stopwatch.elapsed.inSeconds,
      );
      SoundService.instance.win();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DailyResultDialog(isReplay: false),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (widget.isComet) {
      final granted = await PlayerProgress.instance.recordCometEventComplete();
      SoundService.instance.win();
      unawaited(AnalyticsService.instance.logLevelComplete(
        'orbit_comet',
        _stage,
        stars: stars,
        moves: _controller.rotations,
      ));
      if (!mounted) return;
      await _playCelebrationOverlay(stars);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ResultDialog(
          success: true,
          stars: stars,
          rotations: _controller.rotations,
          par: _controller.level.parRotations,
          gainedXp: granted ? EconomyConfig.cometXpReward : null,
          onXpDoubled: granted
              ? () => unawaited(PlayerProgress.instance.addXpAndMeteors(
                  EconomyConfig.cometXpReward,
                  EconomyConfig.winDoubleXpMeteorBonus))
              : null,
          onNext: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
          },
          onExit: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
          },
        ),
      );
      return;
    }

    SoundService.instance.win();
    unawaited(AnalyticsService.instance.logLevelComplete(
      'orbit',
      _stage,
      stars: stars,
      moves: _controller.rotations,
    ));
    final (gainedXp, _) = await PlayerProgress.instance.recordOrbitStageResult(
      stage: _stage,
      stars: stars,
      moves: _controller.rotations,
      optimalMoves: _controller.level.parRotations,
      usedAssist: _usedAssistThisAttempt,
    );

    // Rate-prompt: SADECE temiz (yardımsız + 3 yıldız) bir kazanımın
    // hemen ardından, bağlamsal kurallar (bkz. RatePromptService)
    // uygunsa native puanlama diyaloğunu tetikler.
    unawaited(RatePromptService.instance.maybePromptAfterCleanWin(
      totalStagesCleared: _stage,
      cleanWin: !_usedAssistThisAttempt && stars == 3,
    ));

    if (!mounted) return;
    await _playCelebrationOverlay(stars);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ResultDialog(
        success: true,
        stars: stars,
        rotations: _controller.rotations,
        par: _controller.level.parRotations,
        gainedXp: gainedXp,
        onXpDoubled: () => unawaited(PlayerProgress.instance.addXpAndMeteors(
            gainedXp, EconomyConfig.winDoubleXpMeteorBonus)),
        onNext: () async {
          Navigator.of(ctx).pop();

          // Orbit + Tup ORTAK sayaci: toplamda her 2 bolumde 1 gecis
          // reklami (bkz. AdService.notifyStageCompleted).
          await AdService.instance.notifyStageCompleted();
          if (!mounted) return;

          setState(() {
            _controller.removeListener(_onStateChanged);
            _stage++;
            _startLevel(_stage);
          });
        },
        onExit: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _showJamDialog() async {
    SoundService.instance.buttonTap();
    unawaited(AnalyticsService.instance.logGameStuckShown('orbit'));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ResultDialog(
        success: false,
        stars: 0,
        rotations: _controller.rotations,
        par: _controller.level.parRotations,
        // DUZELTME: Rihtim genisletme artik SINIRSIZ/tekrarlanabilir
        // odullu reklamla yapiliyor — "1. hak ucretsiz reklam, 2.+ hak
        // meteorla kademeli fiyat" kisitlamasi kaldirildi. Meteor satin
        // alma yolu bu ekrandan tamamen cikarildi (bkz. asagidaki
        // meteorPrice/onBuyWithMeteors: null).
        onWatchAd: () => _watchAdAndExpandDock(ctx),
        bankedDockSlots: PlayerProgress.instance.bankedOrbitDockSlots,
        onUseBankedSlot: PlayerProgress.instance.bankedOrbitDockSlots > 0
            ? () => _useBankedDockSlot(ctx)
            : null,
        meteorPrice: null,
        meteorBalance: PlayerProgress.instance.meteors,
        onBuyWithMeteors: null,
        onNext: () {
          unawaited(
              AnalyticsService.instance.logJamDialogOutcome('orbit', _stage, 'retry'));
          Navigator.of(ctx).pop();
          setState(() {
            _controller.removeListener(_onStateChanged);
            _startLevel(_stage);
          });
        },
        onExit: () {
          unawaited(
              AnalyticsService.instance.logJamDialogOutcome('orbit', _stage, 'exit'));
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Kozmik Ikmal'den biriktirilen "rihtim yuvasi" hakkini reklamsiz
  /// harcar; sikisma diyalogunu kapatip oyuna kaldigi yerden devam
  /// ettirir.
  Future<void> _useBankedDockSlot(BuildContext dialogContext) async {
    await PlayerProgress.instance.spendBankedOrbitDockSlot();
    _usedAssistThisAttempt = true;
    SoundService.instance.reward();
    _controller.expandDock();
    _dialogShown = false;
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    if (mounted) setState(() {});
  }

  /// Odullu reklami izletir, basariliysa rihtime +1 yuva ekler ve — oyun
  /// sikismis haldeyse — sikisma diyalogunu kapatip oyuna kaldigi yerden
  /// devam ettirir (Pixel Flow'daki "tampon genislet" odul-devam akisiyla
  /// ayni fikir).
  /// DUZELTME: Artik SINIRSIZ tekrarlanabilir — daha once sadece "ilk
  /// hak" icin cagrilip sonrasinda meteor akisina devrediliyordu; su an
  /// rihtim her doldugunda ayni yoldan tekrar tekrar reklam izlenebilir.
  Future<void> _watchAdAndExpandDock(BuildContext dialogContext) async {
    final granted = await AdService.instance.showRewardedAdFlow(
      dialogContext,
      icon: '🛰️',
      title: t('orbit_expandDockTitle'),
      subtitle: t('orbit_expandDockSubtitle'),
      placementId: 'orbit_dock_expand',
    );
    if (granted != true) return;
    _usedAssistThisAttempt = true;
    SoundService.instance.reward();
    _controller.expandDock();
    _dialogShown = false;
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    if (mounted) setState(() {});
  }

  /// DUZELTME: Artik SINIRSIZ tekrarlanabilir (bkz. yukaridaki not) —
  /// canli rihtim satirindaki chip de her doluşta ayni reklam akisini
  /// tekrar tekrar sunar, meteor secenegine hic dusmez.
  /// DUZELTME: Bu buton daha once bankadaki (Meteor Magazasi'ndan
  /// stoklanmis) rihtim yuvalarini HIC KONTROL ETMEDEN direkt reklama
  /// gidiyordu — oyuncu magazadan satin alsa bile burada yine "Reklam
  /// Izle" cikiyordu (bkz. jam diyalogundaki onUseBankedSlot ile ayni
  /// mantik simdi burada da uygulaniyor). Once banka kontrol edilir,
  /// varsa reklamsiz harcanir; yoksa eskisi gibi reklam akisina duser.
  Future<void> _watchAdFromDockRow() async {
    if (!mounted) return;
    if (PlayerProgress.instance.bankedOrbitDockSlots > 0) {
      await PlayerProgress.instance.spendBankedOrbitDockSlot();
      _usedAssistThisAttempt = true;
      SoundService.instance.reward();
      if (mounted) {
        setState(() {
          _controller.expandDock();
        });
      }
      return;
    }
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🛰️',
      title: t('orbit_expandDockTitle'),
      subtitle: t('orbit_expandDockSubtitle'),
      placementId: 'orbit_dock_expand_row',
    );
    if (granted != true || !mounted) return;
    _usedAssistThisAttempt = true;
    SoundService.instance.reward();
    setState(() {
      _controller.expandDock();
    });
  }

  void _onBlockedTap(int ringIndex) {
    final isLocked = _controller.lastLockedRingAttempt == ringIndex &&
        _controller.level.rings[ringIndex].locked;
    CustomToast.show(
      context,
      isLocked ? t('orbit_lockedRingToast') : t('orbit_dockFullToast'),
      icon: isLocked ? '🔒' : '🚧',
      accentColor: isLocked ? AppColors.warning : AppColors.danger,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _controller.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LevelBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              KeyedSubtree(key: _targetStripKey, child: _buildTargetStrip()),
              Expanded(
                child: Padding(
                  key: _boardKey,
                  padding: const EdgeInsets.all(6),
                  child: OrbitBoard(
                    controller: _controller,
                    onBlockedTap: _onBlockedTap,
                  ),
                ),
              ),
              KeyedSubtree(key: _dockKey, child: _buildDockRow()),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text('🪐', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.isDaily
                    ? t('orbit_dailyTitle')
                    : widget.isComet
                        ? t('comet_title')
                        : t('orbit_stageTitle', {'n': '$_stage'}),
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: _showTutorialDialog,
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              if (!_controller.level.comboEnabled) {
                return _headerBadge('🔄 ${_controller.rotations}');
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerBadge('🔄 ${_controller.rotations}'),
                  const SizedBox(width: 6),
                  _headerBadge(
                    _controller.combo > 1
                        ? '🔥 ${_controller.score} · x${_controller.combo}'
                        : '🔥 ${_controller.score}',
                  ),
                ],
              );
            },
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

  Widget _buildTargetStrip() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final upcoming = _controller.upcomingTargets(6);
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.tubeGlass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.tubeGlassBorder),
          ),
          child: Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(t('orbit_requestedOrder'),
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(upcoming.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: PlanetChip(
                          colorIndex: upcoming[i],
                          size: i == 0 ? 24 : 18,
                          highlighted: i == 0,
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_controller.deliveredCount}/${_controller.totalCount}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDockRow() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.tubeGlass,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.tubeGlassBorder),
          ),
          child: Row(
            children: [
              const Text('🛰️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(t('orbit_cargoDock'),
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _controller.dock.map((slot) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: slot == null
                            ? Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: AppColors.surfaceBorder),
                                ),
                              )
                            : PlanetChip(
                                colorIndex: slot, size: 26, highlighted: true),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // DUZELTME: Rihtim genisletme artik daima odullu reklamla
              // yapiliyor — daha once burada "ilk hak reklam, sonrasi
              // meteor" diye ikiye ayrilan chip, tek ve SINIRSIZ
              // tekrarlanabilir reklam chip'ine indirgendi.
              GestureDetector(
                onTap: _watchAdFromDockRow,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accentSoft),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PlayerProgress.instance.bankedOrbitDockSlots > 0
                            ? Icons.inventory_2_rounded
                            : Icons.play_circle_fill_rounded,
                        color: AppColors.accentSoft,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        PlayerProgress.instance.bankedOrbitDockSlots > 0
                            ? t('orbit_useBankedSlot',
                                {'n': '${PlayerProgress.instance.bankedOrbitDockSlots}'})
                            : t('orbit_plusSlot'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Oyuncuya Yorunge Sikismasi'nin dokunma kuralini gosteren interaktif
/// spot-isikli ogretici artik CoachOverlay uzerinden calisiyor (bkz.
/// _showTutorialDialog). Eski statik metin diyalogu kaldirildi.

class _ResultDialog extends StatefulWidget {
  final bool success;
  final int stars;
  final int rotations;
  final int par;
  final VoidCallback onNext;
  final VoidCallback onExit;
  final VoidCallback? onWatchAd;
  final VoidCallback? onUseBankedSlot;
  final int bankedDockSlots;
  final int? meteorPrice;
  final int meteorBalance;
  final VoidCallback? onBuyWithMeteors;
  // 2x XP: sadece success==true iken anlamli. gainedXp null/0 ise buton
  // hic gosterilmez (ornegin Daily akisinda bu dialog kullanilmiyor zaten).
  final int? gainedXp;
  final VoidCallback? onXpDoubled;
  final String doubleXpPlacementId;

  const _ResultDialog({
    required this.success,
    required this.stars,
    required this.rotations,
    required this.par,
    required this.onNext,
    required this.onExit,
    this.onWatchAd,
    this.onUseBankedSlot,
    this.bankedDockSlots = 0,
    this.meteorPrice,
    this.meteorBalance = 0,
    this.onBuyWithMeteors,
    this.gainedXp,
    this.onXpDoubled,
    this.doubleXpPlacementId = 'orbit_win_double_xp',
  });

  @override
  State<_ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<_ResultDialog> {
  bool _doubling = false;
  bool _doubled = false;

  Future<void> _handleDoubleXp() async {
    setState(() => _doubling = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🎬',
      title: t('win_doubleXpTitle'),
      placementId: widget.doubleXpPlacementId,
    );
    if (!mounted) return;
    if (granted == true) {
      widget.onXpDoubled?.call();
      SoundService.instance.reward();
      setState(() {
        _doubling = false;
        _doubled = true;
      });
    } else {
      setState(() => _doubling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = widget.success;
    final stars = widget.stars;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      // DUZELTME (retention/juice): bolum basariyla tamamlaninca artik sadece
      // yildiz ikonlari degil, dusen konfeti + kosede zipleyip alkislayan iki
      // uzayli da gosteriliyor (bkz. celebration_fx.dart). ClipRRect, konfetinin
      // yuvarlatilmis kart kenarlarindan tasmasini engeller.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(context),
            ),
            // DUZELTME (istek/sıralama): kutlama (konfeti + havai fisek +
            // ucan uzaylilar) artik bu popup ACILMADAN ONCE, ayri bir tam
            // ekran overlay olarak oynatiliyor (bkz. _playCelebrationOverlay
            // ve _handleWin). Bu yuzden burada TEKRAR gosterilmiyor.
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final success = widget.success;
    final stars = widget.stars;
    final rotations = widget.rotations;
    final par = widget.par;
    final onUseBankedSlot = widget.onUseBankedSlot;
    final onWatchAd = widget.onWatchAd;
    final onBuyWithMeteors = widget.onBuyWithMeteors;
    final meteorPrice = widget.meteorPrice;
    final meteorBalance = widget.meteorBalance;
    final bankedDockSlots = widget.bankedDockSlots;
    return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(success ? '🪐' : '🚧', style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            Text(
              success ? t('orbit_systemComplete') : t('orbit_dockJammed'),
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
            const SizedBox(height: 6),
            if (success)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final filled = i < stars;
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled ? AppColors.warning : AppColors.textSecondary,
                    size: 28,
                  );
                }),
              )
            else
              Text(
                t('orbit_jamDesc'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            const SizedBox(height: 6),
            Text(
              t('orbit_rotationsTarget', {'rotations': '$rotations', 'par': '$par'}),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (success && widget.gainedXp != null && widget.gainedXp! > 0) ...[
              const SizedBox(height: 12),
              if (!_doubled)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _doubling ? null : _handleDoubleXp,
                    icon: const Icon(Icons.movie_filter_rounded,
                        size: 18, color: Colors.black87),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            t('win_doubleXp', {
                              'n': '${widget.gainedXp}',
                              'm': '${EconomyConfig.winDoubleXpMeteorBonus}',
                            }),
                            style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const MeteorIcon(size: 16),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '✅ ${t('win_doubleXpClaimed', {
                              'm': '${EconomyConfig.winDoubleXpMeteorBonus}',
                            })}',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const MeteorIcon(size: 14),
                  ],
                ),
            ],
            if (onUseBankedSlot != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentSoft,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onUseBankedSlot,
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: Text(t('orbit_useBankedSlot', {'n': '$bankedDockSlots'})),
                ),
              ),
            ],
            if (onWatchAd != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onWatchAd,
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  label: Text(t('orbit_watchAdExpand')),
                ),
              ),
            ],
            if (onBuyWithMeteors != null && meteorPrice != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: meteorBalance >= meteorPrice
                        ? AppColors.meteorEdge
                        : AppColors.surfaceBorder,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onBuyWithMeteors,
                  icon: const MeteorIcon(size: 18),
                  label: Text(
                    t('orbit_buyDockMeteorFull', {
                      'price': '$meteorPrice',
                      'balance': '$meteorBalance',
                    }),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onExit,
                    child: Text(t('orbit_exit')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    onPressed: widget.onNext,
                    child: Text(success ? t('orbit_nextStage') : t('orbit_tryAgain')),
                  ),
                ),
              ],
            ),
          ],
        );
  }
}
