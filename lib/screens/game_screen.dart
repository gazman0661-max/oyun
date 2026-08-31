import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/economy_config.dart';
import '../game/game_controller.dart';
import '../services/ad_service.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/rate_prompt_service.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../widgets/action_chip.dart';
import '../widgets/action_info_dialog.dart';
import '../widgets/backgrounds/level_background.dart';
import '../widgets/coach_overlay.dart';
import '../widgets/custom_toast.dart';
import '../widgets/daily_result_dialog.dart';
import '../widgets/game_hud.dart';
import '../widgets/planet_codex.dart';
import '../widgets/rock_painter.dart';
import '../widgets/rocket_launch_overlay.dart';
import '../widgets/tube_widget.dart';
import '../widgets/win_dialog.dart';

/// Ucan bir tasin (pour animasyonu sirasinda) yol bilgisi. Konumu, ikinci
/// dereceden bir Bezier egrisi (start -> control -> end) uzerinden, kendi
/// gecikmesiyle (stagger) hesaplanir — HTML'deki --fx/--fy/--bx/--by/
/// animation-delay mantiginin Dart karsiligi.
class _FlyBall {
  final int colorIndex;
  final Offset start;
  final Offset control;
  final Offset end;
  final int delayMs;
  final Size size;
  final double spinDeg;

  _FlyBall({
    required this.colorIndex,
    required this.start,
    required this.control,
    required this.end,
    required this.delayMs,
    required this.size,
    required this.spinDeg,
  });
}

class GameScreen extends StatefulWidget {
  final int? startLevel;
  final bool isDaily;

  const GameScreen({super.key, this.startLevel, this.isDaily = false})
      : assert(startLevel != null || isDaily);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  late GameController _controller;
  final PlayerProgress _progress = PlayerProgress.instance;
  int? _hintFrom;
  int? _hintTo;
  Timer? _hintTimer;
  Timer? _clockTimer;
  Stopwatch _stopwatch = Stopwatch();
  bool _dialogShown = false;
  bool _busy = false;
  bool _flipMode = false;
  bool _blackHoleMode = false;

  /// Bu bolum denemesinde ipucu/geri al/cevir/ekstra tup/kara delik
  /// yardimlarindan HERHANGI biri kullanildi mi? "Temiz kazanim"
  /// (rate-prompt ve cleanStages haftalik gorevi) SADECE bu false iken
  /// sayilir — her yeni denemede (_loadController / _doRestart) sifirlanir.
  bool _usedAssistThisAttempt = false;

  // --- Pour (tuup egilip dokme) animasyonu icin durum ---
  final List<GlobalKey> _tubeKeys = [];
  final GlobalKey _arenaKey = GlobalKey();
  final GlobalKey _actionBarKey = GlobalKey();
  static const _tutorialPrefsKey = 'tube_tutorial_seen_v1';
  late final AnimationController _tiltCtrl;
  late final AnimationController _flyCtrl;
  int? _pouringFrom;
  int _hiddenFromTop = 0;
  double _pourAngle = 0;
  Offset _pourOffset = Offset.zero;
  List<_FlyBall> _flyingBalls = [];
  bool _animatingPour = false;
  RenderBox? _stackBoxAtAnimStart;

  // --- Inis ani "plazma kivilcimi" patlamasi (her tas tupe indiginde) ---
  late final AnimationController _burstCtrl;
  List<_SparkBurst> _bursts = [];

  // --- Yorunge halkasi arka planinin yavas, surekli donusu (sadece
  // dekoratif katman; tup konumlarini/hit-test'i ETKILEMEZ) ---
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    // Bolum ekrani muzigi: sonsuz dongude calar.
    SoundService.instance.playBgm('audio/kinetic_overdrive.mp3');
    _tiltCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _flyCtrl = AnimationController(vsync: this);
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
    _loadController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
  }

  Future<void> _maybeShowTutorial() async {
    // Gunluk modda ya da devam eden bir bolumde ogretici GOSTERILMEZ —
    // sadece normal Tup akisinda ve daha once hic gorulmediyse.
    if (widget.isDaily) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_tutorialPrefsKey) ?? false;
    if (seen || !mounted) return;
    await prefs.setBool(_tutorialPrefsKey, true);
    if (!mounted) return;
    _showTutorial();
  }

  void _showTutorial() {
    CoachOverlay.show(
      context,
      steps: [
        CoachStep(
          targetKey: _arenaKey,
          title: t('tube_coach1Title'),
          body: t('tube_coach1Body'),
        ),
        CoachStep(
          targetKey: _actionBarKey,
          title: t('tube_coach2Title'),
          body: t('tube_coach2Body'),
        ),
      ],
    );
  }

  void _loadController() {
    if (widget.isDaily) {
      _controller = GameController.daily(
        dailyNumber: PlayerProgress.dailyNumber(),
        seed: PlayerProgress.dailySeed(),
      );
    } else {
      _controller = GameController(startLevel: widget.startLevel!);
    }
    _controller.addListener(_onControllerChanged);
    _stopwatch = Stopwatch()..start();
    _usedAssistThisAttempt = false;
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _ensureKeys() {
    while (_tubeKeys.length < _controller.tubes.length) {
      _tubeKeys.add(GlobalKey());
    }
  }

  void _onControllerChanged() {
    setState(() {});
    if (_controller.won && !_dialogShown) {
      _dialogShown = true;
      Future.delayed(const Duration(milliseconds: 260), _onWin);
    }
  }

  String get _timeLabel {
    final s = _stopwatch.elapsed.inSeconds;
    final m = s ~/ 60, ss = s % 60;
    return '$m:${ss.toString().padLeft(2, '0')}';
  }

  // -----------------------------------------------------------------
  // Tup tiklama: secim / iptal / animasyonlu dokme
  // -----------------------------------------------------------------
  void _handleTubeTap(int index) {
    if (_animatingPour || _busy || _controller.won) return;
    if (_flipMode) {
      if (_controller.tubes[index].isEmpty) return;
      setState(() => _flipMode = false);
      SoundService.instance.warpFlip();
      _controller.flipTube(index);
      return;
    }
    if (_blackHoleMode) {
      if (_controller.tubes[index].isEmpty) return;
      setState(() => _blackHoleMode = false);
      SoundService.instance.warpFlip();
      _controller.pullIntoBlackHole(index);
      return;
    }
    if (_controller.blackHoleHeldColor != null) {
      SoundService.instance.pour();
      _controller.releaseFromBlackHole(index);
      return;
    }
    final sel = _controller.selectedIndex;
    if (sel == null) {
      if (_controller.tubes[index].isEmpty) return;
      SoundService.instance.selectTube();
      _controller.setSelected(index);
      return;
    }
    if (sel == index) {
      _controller.setSelected(null);
      return;
    }
    final preview = _controller.previewPour(sel, index);
    if (preview == null) {
      if (_controller.tubes[index].isEmpty) {
        _controller.setSelected(null);
      } else {
        SoundService.instance.selectTube();
        _controller.setSelected(index);
      }
      return;
    }
    _controller.setSelected(null);
    _playPourAnimation(sel, index, preview.color, preview.moveCount);
  }

  Future<void> _playPourAnimation(
    int from,
    int to,
    int colorIndex,
    int moveCount,
  ) async {
    setState(() => _animatingPour = true);

    final fromBox =
        _tubeKeys[from].currentContext?.findRenderObject() as RenderBox?;
    final toBox =
        _tubeKeys[to].currentContext?.findRenderObject() as RenderBox?;
    final stackBox =
        _arenaKey.currentContext?.findRenderObject() as RenderBox?;

    if (fromBox == null || toBox == null || stackBox == null) {
      // Konum olculemedi (nadir bir durum) — animasyonsuz, direkt uygula.
      _controller.commitPour(from, to);
      setState(() => _animatingPour = false);
      return;
    }

    _stackBoxAtAnimStart = stackBox;

    final fromTopLeft = fromBox.localToGlobal(Offset.zero);
    final fromSize = fromBox.size;
    final toTopLeft = toBox.localToGlobal(Offset.zero);
    final toSize = toBox.size;

    final fromCenterX = fromTopLeft.dx + fromSize.width / 2;
    final toCenterX = toTopLeft.dx + toSize.width / 2;
    final goingRight = toCenterX >= fromCenterX;
    final angleDeg = goingRight ? 55.0 : -55.0;
    final angleRad = angleDeg * math.pi / 180;
    final tubeHeight = fromSize.height;

    // Kaynak tupun donme pivotu: alt-orta nokta.
    final pivotX = fromCenterX;
    final pivotY = fromTopLeft.dy + fromSize.height;
    final mouthTargetX =
        toCenterX + (goingRight ? -toSize.width * 0.22 : toSize.width * 0.22);
    final mouthTargetY = toTopLeft.dy - 18;
    final xOff = tubeHeight * math.sin(angleRad);
    final yOff = -tubeHeight * math.cos(angleRad);
    final tx = mouthTargetX - pivotX - xOff;
    final ty = mouthTargetY - pivotY - yOff;

    setState(() {
      _pouringFrom = from;
      _pourAngle = angleRad;
      _pourOffset = Offset(tx, ty);
      _hiddenFromTop = 0;
      _flyingBalls = [];
    });
    SoundService.instance.pour();

    await _tiltCtrl.forward(from: 0);
    if (!mounted) return;

    // Tup "vardi" — simdi ucan taslari olustur ve kaynaktaki ilgili
    // taslari gizle (klonlar onlarin yerini aldi).
    const flightMs = 420;
    const staggerMs = 130;
    final destGeom = tubeBodyGeometry(toSize, _controller.tubes[to].capacity);
    final fromGeom =
        tubeBodyGeometry(fromSize, _controller.tubes[from].capacity);
    final destLen = _controller.tubes[to].balls.length;
    final ballSize = Size(
      fromGeom.bodyWidth - fromGeom.padding * 2,
      fromGeom.slotHeight - fromGeom.padding * 1.2,
    );

    final rnd = math.Random();
    final balls = <_FlyBall>[];
    for (var k = 0; k < moveCount; k++) {
      final orderIdx = moveCount - 1 - k; // 0 = ilk firlayan (en usttteki tas)
      final landSlot = destLen + orderIdx;
      final start = Offset(mouthTargetX, mouthTargetY + k * 4.0);
      final landX = toTopLeft.dx + destGeom.left + destGeom.bodyWidth / 2;
      final landY = toTopLeft.dy +
          destGeom.bodyBottom -
          (landSlot + 1) * destGeom.slotHeight +
          destGeom.slotHeight / 2;
      final end = Offset(landX, landY);
      final fx = end.dx - start.dx, fy = end.dy - start.dy;
      // Yorungeyi yukari dogru sisirerek gercek bir "firlatma" yayi verir.
      final control = Offset(start.dx + fx * 0.5, start.dy + fy * 0.5 - 46);
      final spin = (goingRight ? 1 : -1) * (60 + rnd.nextDouble() * 40);
      balls.add(_FlyBall(
        colorIndex: colorIndex,
        start: start,
        control: control,
        end: end,
        delayMs: orderIdx * staggerMs,
        size: ballSize,
        spinDeg: spin,
      ));
    }

    setState(() {
      _hiddenFromTop = moveCount;
      _flyingBalls = balls;
    });

    final totalFlyMs = (moveCount - 1) * staggerMs + flightMs;
    _flyCtrl.duration = Duration(milliseconds: totalFlyMs);
    await _flyCtrl.forward(from: 0);
    if (!mounted) return;
    SoundService.instance.land();

    setState(() {
      _flyingBalls = [];
      _bursts = [for (final b in balls) _SparkBurst(b.end, b.colorIndex)];
    });
    unawaited(_burstCtrl.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _bursts = []);
    }));

    await _tiltCtrl.reverse();
    if (!mounted) return;

    setState(() {
      _pouringFrom = null;
      _hiddenFromTop = 0;
    });

    _controller.commitPour(from, to);
    setState(() => _animatingPour = false);
  }

  double _ballLocalProgress(_FlyBall b) {
    final totalMs = _flyCtrl.duration?.inMilliseconds ?? 1;
    final elapsedMs = _flyCtrl.value * totalMs;
    const flightMs = 420.0;
    return ((elapsedMs - b.delayMs) / flightMs).clamp(0.0, 1.0).toDouble();
  }

  Offset _ballPosition(_FlyBall b, double t) {
    final a = Offset.lerp(b.start, b.control, t)!;
    final c = Offset.lerp(b.control, b.end, t)!;
    return Offset.lerp(a, c, t)!;
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _clockTimer?.cancel();
    _tiltCtrl.dispose();
    _flyCtrl.dispose();
    _burstCtrl.dispose();
    _ringCtrl.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // Kazanma akisi
  // -----------------------------------------------------------------
  Future<void> _onWin() async {
    _stopwatch.stop();
    _clockTimer?.cancel();
    final elapsed = _stopwatch.elapsed.inSeconds;

    if (widget.isDaily) {
      await _progress.recordDailyResult(
        moves: _controller.moveCount,
        optimal: _controller.optimalMoves,
        timeSeconds: elapsed,
      );
      SoundService.instance.win();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DailyResultDialog(isReplay: false),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final stars = _controller.stars;
    if (stars == 3) {
      SoundService.instance.starWin();
      await playRocketLaunch(context);
    } else {
      SoundService.instance.win();
    }
    if (!mounted) return;
    final levelBefore = _progress.levelInfo().level;
    final score = (500 - (_controller.moveCount - _controller.optimalMoves) * 10)
        .clamp(50, 500)
        .toInt();
    final (gainedXp, leveledUp) = await _progress.recordStageResult(
      stage: _controller.level,
      stars: stars,
      moves: _controller.moveCount,
      optimalMoves: _controller.optimalMoves,
      usedAssist: _usedAssistThisAttempt,
    );
    final newLevel = leveledUp ? _progress.levelInfo().level : levelBefore;
    if (leveledUp) SoundService.instance.levelUp();

    // Rate-prompt: SADECE temiz (yardimsiz + 3 yildiz) bir kazanimin
    // hemen ardindan, baglamsal kurallar (bkz. RatePromptService)
    // uygunsa native puanlama diyalogunu tetikler. (Orbit ekraniyla
    // ayni mantik — daha once Tup modunda bu cagri hic yoktu.)
    unawaited(RatePromptService.instance.maybePromptAfterCleanWin(
      totalStagesCleared: _controller.level,
      cleanWin: !_usedAssistThisAttempt && stars == 3,
    ));

    // Gunes Sistemi Koleksiyonu: bu bolumde kullanilan gezegen
    // renklerinden ilk kez kesfedilenler varsa, kazanma ekranindan once
    // kisa bir "yeni gezegen kesfedildi" diyalogu goster.
    final newlyDiscovered =
        await _progress.markPlanetsDiscovered(_controller.colorCount);
    if (!mounted) return;
    if (newlyDiscovered.isNotEmpty) {
      SoundService.instance.reward();
      await showPlanetDiscoveryDialog(context, newlyDiscovered);
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WinDialog(
        stage: _controller.level,
        stars: stars,
        moveCount: _controller.moveCount,
        timeLabel: _timeLabel,
        score: score,
        gainedXp: gainedXp,
        leveledUp: leveledUp,
        newLevel: newLevel,
        doubleXpPlacementId: 'tube_win_double_xp',
        onXpDoubled: () => unawaited(_progress.addXpAndMeteors(
            gainedXp, EconomyConfig.winDoubleXpMeteorBonus)),
        onNextStage: () async {
          Navigator.of(context).pop();
          _dialogShown = false;
          final nextLevel = _controller.level + 1;

          // Orbit + Tup ORTAK sayaci: toplamda her 2 bolumde 1 gecis
          // reklami (bkz. AdService.notifyStageCompleted).
          await AdService.instance.notifyStageCompleted();
          if (!mounted) return;

          _controller.removeListener(_onControllerChanged);
          _controller.dispose();
          setState(() {
            _controller = GameController(startLevel: nextLevel);
            _controller.addListener(_onControllerChanged);
          });
          _stopwatch = Stopwatch()..start();
          _usedAssistThisAttempt = false;
          _clockTimer?.cancel();
          _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        },
        onClose: () {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _onHint() async {
    if (_busy || _animatingPour) return;
    if (_progress.bankedHints > 0) {
      await _progress.spendBankedHint();
      _usedAssistThisAttempt = true;
      _showHint();
      return;
    }
    setState(() => _busy = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🛰️',
      title: t('game_signal'),
      placementId: 'tube_hint',
    );
    setState(() => _busy = false);
    if (granted == true) {
      _usedAssistThisAttempt = true;
      _showHint();
    }
  }

  void _showHint() {
    final hint = _controller.findHint();
    _hintTimer?.cancel();
    if (hint == null) {
      CustomToast.show(context, t('game_noMoveFound'),
          icon: '🔍',
          accentColor: AppColors.warning,
          duration: const Duration(seconds: 2));
      return;
    }
    setState(() {
      _hintFrom = hint.$1;
      _hintTo = hint.$2;
    });
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _hintFrom = null;
          _hintTo = null;
        });
      }
    });
  }

  Future<void> _onUndo() async {
    if (_busy || _animatingPour) return;
    if (!_controller.canUndo) return;
    if (_progress.bankedUndos > 0) {
      await _progress.spendBankedUndo();
      _usedAssistThisAttempt = true;
      SoundService.instance.undo();
      _controller.undo();
      return;
    }
    setState(() => _busy = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '↩️',
      title: t('game_undo'),
      placementId: 'tube_undo',
    );
    setState(() => _busy = false);
    if (granted == true) {
      _usedAssistThisAttempt = true;
      SoundService.instance.undo();
      _controller.undo();
    }
  }

  Future<void> _onExtraTube() async {
    if (_busy || _animatingPour) return;
    if (_controller.extraTubesUsed >= GameController.maxExtraTubes) {
      CustomToast.show(context, t('game_noMoreExtraTubes'),
          icon: '🧯', accentColor: AppColors.warning);
      return;
    }
    if (_progress.bankedExtraTubes > 0) {
      await _progress.spendBankedExtraTube();
      _usedAssistThisAttempt = true;
      SoundService.instance.buttonTap();
      _controller.addExtraTube();
      return;
    }
    setState(() => _busy = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🧯',
      title: t('game_extraTank'),
      placementId: 'tube_extra_tube',
    );
    setState(() => _busy = false);
    if (granted == true) {
      _usedAssistThisAttempt = true;
      SoundService.instance.buttonTap();
      _controller.addExtraTube();
    }
  }

  Future<void> _onFlip() async {
    if (_busy || _animatingPour) return;
    if (_flipMode) {
      // Zaten secim modundaysa, tekrar basmak iptal eder.
      setState(() => _flipMode = false);
      return;
    }
    if (_controller.flipsUsed >= GameController.maxFlips) {
      CustomToast.show(context, t('game_noMoreFlips'),
          icon: '🌀', accentColor: AppColors.warning);
      return;
    }
    if (_progress.bankedFlips > 0) {
      await _progress.spendBankedFlip();
      _usedAssistThisAttempt = true;
      _enterFlipMode();
      return;
    }
    setState(() => _busy = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🌀',
      title: t('game_flip'),
      placementId: 'tube_flip',
    );
    setState(() => _busy = false);
    if (granted == true) {
      _usedAssistThisAttempt = true;
      _enterFlipMode();
    }
  }

  void _enterFlipMode() {
    setState(() => _flipMode = true);
    CustomToast.show(context, t('game_flipPickTube'),
        icon: '🌀',
        accentColor: AppColors.zeroGGlow,
        duration: const Duration(seconds: 2));
  }

  Future<void> _onBlackHole() async {
    if (_busy || _animatingPour) return;
    if (_controller.blackHoleHeldColor != null) {
      CustomToast.show(context, t('game_blackHolePickTarget'),
          icon: '🕳️', accentColor: AppColors.accent);
      return;
    }
    if (_blackHoleMode) {
      // Zaten secim modundaysa, tekrar basmak iptal eder.
      setState(() => _blackHoleMode = false);
      return;
    }
    if (_controller.blackHoleUsed >= GameController.maxBlackHole) {
      CustomToast.show(context, t('game_noMoreBlackHole'),
          icon: '🕳️', accentColor: AppColors.warning);
      return;
    }
    // DUZELTME: Kara Delik daha once bankayi HIC kontrol etmiyordu — ne
    // yaparsa yapsin dogrudan reklama gidiyordu, bu yuzden Meteor
    // Magazasi'ndan satin alinan stok hicbir zaman kullanilamiyordu (rozet
    // de yanlislikla "bolum basina ucretsiz hak" sayisini gosteriyordu,
    // sahip olunan stogu degil). Simdi Ekstra Tup/Cevir ile AYNI duzen:
    // once banka, o bossa reklam.
    if (_progress.bankedBlackHoles > 0) {
      await _progress.spendBankedBlackHole();
      _usedAssistThisAttempt = true;
      SoundService.instance.buttonTap();
      _enterBlackHoleMode();
      return;
    }
    setState(() => _busy = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🕳️',
      title: t('game_blackHole'),
      placementId: 'tube_black_hole',
    );
    setState(() => _busy = false);
    if (granted == true) {
      _usedAssistThisAttempt = true;
      _enterBlackHoleMode();
    }
  }

  void _enterBlackHoleMode() {
    setState(() => _blackHoleMode = true);
    CustomToast.show(context, t('game_blackHolePickSource'),
        icon: '🕳️',
        accentColor: AppColors.accent,
        duration: const Duration(seconds: 2));
  }

  Future<void> _onRestart() async {
    if (_busy || _animatingPour) return;
    if (_progress.getResetsLeftToday() > 0) {
      await _progress.useFreeReset();
      SoundService.instance.buttonTap();
      _doRestart();
      return;
    }
    setState(() => _busy = true);
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🔁',
      title: t('game_restartTitle'),
      subtitle: t('game_resetsExhausted'),
      placementId: 'tube_restart',
    );
    setState(() => _busy = false);
    if (granted == true) {
      SoundService.instance.buttonTap();
      _doRestart();
    }
  }

  void _doRestart() {
    _controller.restartToInitial();
    _stopwatch = Stopwatch()..start();
    _usedAssistThisAttempt = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    final stageLabel = widget.isDaily
        ? '🌌 #${PlayerProgress.dailyNumber()}'
        : '${_controller.level}';
    return Scaffold(
      body: LevelBackground(
        key: ValueKey(widget.isDaily ? 'daily' : _controller.level),
        child: SafeArea(
          child: Column(
            children: [
              GameHud(
                stageLabel: stageLabel,
                moveCount: _controller.moveCount,
                timeLabel: _timeLabel,
                onRestart: _onRestart,
                onBack: () => Navigator.of(context).pop(),
                onHelp: _showTutorial,
                resetsLeft: _progress.getResetsLeftToday(),
              ),
              Expanded(
                child: Stack(
                  key: _arenaKey,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildOrbitalArena(constraints),
                      ),
                    ),
                    if (_flyingBalls.isNotEmpty) _buildFlyingBallsLayer(),
                    if (_bursts.isNotEmpty) _buildBurstLayer(),
                  ],
                ),
              ),
              Padding(
                key: _actionBarKey,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Row(
                  children: [
                    GameActionChip(
                      icon: '↩️',
                      label: t('game_undo'),
                      badgeCount: _progress.bankedUndos,
                      enabled: _controller.canUndo,
                      onTap: _onUndo,
                      onInfoTap: () => showActionInfoDialog(
                        context,
                        icon: '↩️',
                        title: t('game_undo'),
                        description: t('game_undoDesc'),
                        lines: [
                          '${t('game_bankLabel')}: ${_progress.bankedUndos}',
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GameActionChip(
                      icon: '🛰️',
                      label: t('game_signal'),
                      badgeCount: _progress.bankedHints,
                      onTap: _onHint,
                      onInfoTap: () => showActionInfoDialog(
                        context,
                        icon: '🛰️',
                        title: t('game_signal'),
                        description: t('game_signalDesc'),
                        lines: [
                          '${t('game_bankLabel')}: ${_progress.bankedHints}',
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GameActionChip(
                      icon: '🧯',
                      label: t('game_extraTank'),
                      badgeCount: _progress.bankedExtraTubes,
                      enabled: _controller.extraTubesUsed <
                          GameController.maxExtraTubes,
                      onTap: _onExtraTube,
                      onInfoTap: () => showActionInfoDialog(
                        context,
                        icon: '🧯',
                        title: t('game_extraTank'),
                        description: t('game_extraTankDesc'),
                        lines: [
                          '${t('game_bankLabel')}: ${_progress.bankedExtraTubes}',
                          '${t('game_maxPerMission')}: '
                              '${GameController.maxExtraTubes} '
                              '(${_controller.extraTubesUsed}/${GameController.maxExtraTubes})',
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GameActionChip(
                      icon: '🌀',
                      label: t('game_flip'),
                      badgeCount: _progress.bankedFlips,
                      enabled: _flipMode ||
                          _controller.flipsUsed < GameController.maxFlips,
                      onTap: _onFlip,
                      onInfoTap: () => showActionInfoDialog(
                        context,
                        icon: '🌀',
                        title: t('game_flip'),
                        description: t('game_flipDesc'),
                        lines: [
                          '${t('game_bankLabel')}: ${_progress.bankedFlips}',
                          '${t('game_maxPerMission')}: '
                              '${GameController.maxFlips} '
                              '(${_controller.flipsUsed}/${GameController.maxFlips})',
                        ],
                      ),
                    ),
                    if (_controller.blackHoleUnlocked) ...[
                      const SizedBox(width: 10),
                      GameActionChip(
                        icon: '🕳️',
                        label: t('game_blackHole'),
                        badgeCount: _progress.bankedBlackHoles,
                        enabled: _blackHoleMode ||
                            (_controller.blackHoleUsed <
                                    GameController.maxBlackHole &&
                                _controller.blackHoleHeldColor == null),
                        onTap: _onBlackHole,
                        onInfoTap: () => showActionInfoDialog(
                          context,
                          icon: '🕳️',
                          title: t('game_blackHole'),
                          description: t('game_blackHoleDesc'),
                          lines: [
                            '${t('game_bankLabel')}: ${_progress.bankedBlackHoles}',
                            '${t('game_maxPerMission')}: '
                                '${GameController.maxBlackHole} '
                                '(${_controller.blackHoleUsed}/${GameController.maxBlackHole})',
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tupleri (artik "yakit modulleri") duz bir sirada degil, merkezi bir
  /// istasyon cekirdeginin CEVRESINDE bir yorunge halkasi gibi dizer.
  /// Her modulun kendisi hala dikey duruyor (mevcut, test edilmis dokme
  /// animasyonu top/pivot matematigini bozmamak icin) — sadece PLANDAKI
  /// KONUMU dairesel. Bu, "bir dizi tup" yerine "istasyon etrafinda
  /// dizili modul agi" hissi verir.
  Widget _buildOrbitalArena(BoxConstraints constraints) {
    final n = _controller.tubes.length;
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    if (n == 0 || !w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
      return const SizedBox.shrink();
    }
    final centerX = w / 2;
    final centerY = h / 2;

    // --- Modul boyutunu KOMSU CAKISMASINI ONLEYECEK sekilde COZUYORUZ ---
    // Modul dikey durdugu ve boyu eninden (3.15x) cok daha uzun oldugu
    // icin, en riskli cakisma halkanin YANLARINDA (saat 3/9 yonu) olusur:
    // orada komsu iki modul birbirine dikey yonde yaklasir. O yuzden
    // "komsu merkezler arasi kiris uzunlugu >= modul boyu" sartini
    // (biraz payla) saglayan en buyuk modul genisligini hesaplariz.
    // Eskiden sabit 56/48/40 esikleri kullaniliyordu ve bu, n=6 gibi
    // sik bir durumda bile fiilen cakisiyordu — bu yuzden formule
    // gecildi.
    final screenSpan = math.min(w, h);
    final safeN = math.max(n, 3);
    final sinHalfGap = math.sin(math.pi / safeN).clamp(0.05, 1.0).toDouble();
    // Not: bu degerler (2.55 / 1.05) once 3.15 / 1.12 idi — tupler "cok
    // kucuk" geri bildirimi uzerine daha bodur (daha az uzun) ve daha az
    // guvenlik payiyla yeniden ayarlandi. Formulun kendisi hala tam/exact
    // oldugu icin (komsu merkezler arasi kiris >= modul boyu esitligini
    // cozuyor), cakisma onleme garantisi bozulmuyor — sadece daha az
    // "bosluk" birakiyoruz.
    const aspect = 2.55; // tubeH = tubeW * aspect
    const safetyMargin = 1.05; // %5 ekstra pay

    var tubeW = (screenSpan / 2 - 4) /
        (aspect * (safetyMargin / (2 * sinHalfGap) + 0.5));
    tubeW = tubeW.clamp(38.0, 92.0).toDouble();
    final tubeH = tubeW * aspect;

    final overlapSafeRadius = (tubeH / (2 * sinHalfGap)) * safetyMargin;
    final onScreenMaxRadius = screenSpan / 2 - tubeH / 2 - 4;
    // Normalde ikisi de ayni anda saglanir (formul bunun icin cozuldu);
    // asiri kucuk ekran gibi bir uc durumda ekrandan tasmamayi tercih
    // ediyoruz (cakisma riskini kucuk oranli modullerde kabul ederiz).
    final radius = math.min(overlapSafeRadius, math.max(onScreenMaxRadius, tubeW * 0.9));


    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Dekoratif, yavasca donen yorunge halkalari + enerji noktalari.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ringCtrl,
              builder: (context, _) => CustomPaint(
                painter: _OrbitRingPainter(
                  center: Offset(centerX, centerY),
                  radius: radius,
                  progress: _ringCtrl.value,
                  nodeCount: n,
                ),
              ),
            ),
          ),
        ),
        // Merkezi istasyon cekirdegi (sadece dekor).
        Positioned(
          left: centerX - _hubRadius(tubeW),
          top: centerY - _hubRadius(tubeW),
          child: IgnorePointer(child: _buildHub(tubeW)),
        ),
        for (var i = 0; i < n; i++)
          Builder(builder: (context) {
            final angle = (2 * math.pi * i / n) - math.pi / 2;
            final cx = centerX + radius * math.cos(angle) - tubeW / 2;
            final cy = centerY + radius * math.sin(angle) - tubeH / 2;
            return Positioned(
              left: cx,
              top: cy,
              child: _buildTube(i, width: tubeW, height: tubeH),
            );
          }),
      ],
    );
  }

  double _hubRadius(double tubeW) => tubeW * 0.62;

  Widget _buildHub(double tubeW) {
    final r = _hubRadius(tubeW);
    return Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.zeroGGlow.withValues(alpha: 0.55),
            AppColors.tubeGlass.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.35),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: AppColors.zeroGGlow.withValues(alpha: 0.6),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.zeroGGlow.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '🛰️',
        style: TextStyle(fontSize: r * 0.9),
      ),
    );
  }

  Widget _buildTube(int i, {double width = 56, double height = 190}) {
    final tubeWidget = TubeWidget(
      key: _tubeKeys[i],
      tube: _controller.tubes[i],
      selected: _controller.selectedIndex == i ||
          _hintFrom == i ||
          _hintTo == i ||
          (_flipMode && !_controller.tubes[i].isEmpty) ||
          (_blackHoleMode && !_controller.tubes[i].isEmpty) ||
          (_controller.blackHoleHeldColor != null &&
              !_controller.tubes[i].isFull),
      hiddenFromTop: _pouringFrom == i ? _hiddenFromTop : 0,
      width: width,
      height: height,
      onTap: () => _handleTubeTap(i),
    );

    if (_pouringFrom != i) return tubeWidget;

    // Kaynak tup: pivot alt-orta noktadan, hedefe dogru egiliyor.
    return AnimatedBuilder(
      animation: _tiltCtrl,
      builder: (context, child) {
        final t = Curves.easeOutBack
            .transform(_tiltCtrl.value.clamp(0.0, 1.0).toDouble());
        final offset = Offset.lerp(Offset.zero, _pourOffset, t)!;
        final angle = _pourAngle * t;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..translateByDouble(offset.dx, offset.dy, 0.0, 1.0)
            ..rotateZ(angle),
          child: child,
        );
      },
      child: tubeWidget,
    );
  }

  Widget _buildBurstLayer() {
    final stackBox = _stackBoxAtAnimStart;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _burstCtrl,
        builder: (context, _) {
          return Stack(
            clipBehavior: Clip.none,
            children: _bursts.map((burst) {
              final localCenter = stackBox != null
                  ? stackBox.globalToLocal(burst.center)
                  : burst.center;
              return Positioned(
                left: localCenter.dx - 30,
                top: localCenter.dy - 30,
                width: 60,
                height: 60,
                child: CustomPaint(
                  painter: _SparkBurstPainter(
                    colorIndex: burst.colorIndex,
                    t: _burstCtrl.value,
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildFlyingBallsLayer() {
    final stackBox = _stackBoxAtAnimStart;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _flyCtrl,
        builder: (context, _) {
          return Stack(
            clipBehavior: Clip.none,
            children: _flyingBalls.map((b) {
              final t = _ballLocalProgress(b);
              final globalPos = _ballPosition(b, t);
              final localPos = stackBox != null
                  ? stackBox.globalToLocal(globalPos)
                  : globalPos;
              return Positioned(
                left: localPos.dx - b.size.width / 2,
                top: localPos.dy - b.size.height / 2,
                width: b.size.width,
                height: b.size.height,
                child: Transform.rotate(
                  angle: b.spinDeg * t * math.pi / 180,
                  child: CustomPaint(
                    painter: _FlyBallPainter(colorIndex: b.colorIndex),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// Modullerin dizildigi yorungeyi ve uzerinde yavasca kayan enerji
/// noktalarini ciziyor. Tamamen dekoratif — hicbir hit-test/konum
/// hesabini etkilemez, bu yuzden dokme animasyonu icin risksiz.
class _OrbitRingPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double progress; // 0..1, surekli donen
  final int nodeCount;

  _OrbitRingPainter({
    required this.center,
    required this.radius,
    required this.progress,
    required this.nodeCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.zeroGGlow.withValues(alpha: 0.28);
    canvas.drawCircle(center, radius, ringPaint);

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.tubeGlassBorder.withValues(alpha: 0.35);
    canvas.drawCircle(center, radius * 0.7, innerPaint);

    // Halka boyunca yavasca kayan birkac kucuk "enerji" noktasi.
    const dotCount = 3;
    for (var i = 0; i < dotCount; i++) {
      final t = progress + i / dotCount;
      final angle = 2 * math.pi * t;
      final pos = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final dotPaint = Paint()
        ..color = AppColors.zeroGGlow.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(pos, 2.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.radius != radius ||
      oldDelegate.center != center;
}

class _FlyBallPainter extends CustomPainter {
  final int colorIndex;
  _FlyBallPainter({required this.colorIndex});

  @override
  void paint(Canvas canvas, Size size) {
    paintRock(canvas, Offset.zero & size, colorIndex);
  }

  @override
  bool shouldRepaint(covariant _FlyBallPainter oldDelegate) => false;
}

/// Bir tasin tupe indigi anda cizilen "plazma kivilcimi" patlamasinin
/// konum + renk bilgisi. [center] arena'nin GLOBAL koordinatinda tutulur;
/// cizim sirasinda yerel koordinata cevrilir (bkz. _buildBurstLayer).
class _SparkBurst {
  final Offset center;
  final int colorIndex;
  const _SparkBurst(this.center, this.colorIndex);
}

/// Merkezden disari dogru sacilan, solup kucumsememesi icin buyuyup
/// solan birkac kucuk kivilcim parcaciği ciziyor. Tamamen Canvas ile,
/// harici asset/parcacik kutuphanesi kullanmadan.
class _SparkBurstPainter extends CustomPainter {
  final int colorIndex;
  final double t; // 0..1 patlama ilerlemesi
  static const int _particleCount = 7;

  _SparkBurstPainter({required this.colorIndex, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final baseColor = AppColors.colorFor(colorIndex);
    final eased = Curves.easeOut.transform(t);
    final fadeOut = (1 - t).clamp(0.0, 1.0).toDouble();

    // Merkezde kisa omurlu bir parlama (flash).
    final flashPaint = Paint()
      ..color = Colors.white.withValues(alpha: (1 - t) * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, 10 * (1 - t * 0.6), flashPaint);

    for (var i = 0; i < _particleCount; i++) {
      final angle = (2 * math.pi * i / _particleCount) +
          (colorIndex * 0.37); // her renk icin hafif farkli aci deseni
      final distance = eased * 24;
      final pos = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      final radius = (1 - eased) * 3.4 + 1.0;
      final paint = Paint()
        ..color = baseColor.withValues(alpha: fadeOut * 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkBurstPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.colorIndex != colorIndex;
}
