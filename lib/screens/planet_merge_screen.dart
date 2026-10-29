import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/daily_missions.dart';
import '../game/cosmic_powers.dart';
import '../game/economy_config.dart';
import '../game/level_mode.dart';
import '../game/merge_challenge.dart';
import '../game/planet_merge_physics.dart';
import '../game/weekly_rules.dart';
// forge2d sorun cikarirsa yukaridaki satiri su ile degistir (yedek fizik):
// import '../game/planet_merge_physics_custom.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/haptic_service.dart';
import '../services/level_progress.dart';
import '../services/localization.dart';
import '../services/planet_images.dart';
import '../services/player_progress.dart';
import '../services/rate_prompt_service.dart';
import '../services/sound_service.dart';
import '../services/tutorial_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/custom_toast.dart';
import '../widgets/daily_result_dialog.dart';
import '../widgets/meteor_icon.dart';
import '../widgets/planet_face.dart';
import '../widgets/reward_celebration.dart';
import '../widgets/tutorial_overlay.dart';

/// Oyun modu: sonsuz (ana mod), gunluk seri meydan okumasi ya da
/// kuyruklu yildiz etkinligi.
enum MergeMode { endless, daily, comet, levels }

/// "Gezegen Birlestir" (Suika tarzi) — uygulamanin ANA OYUNU.
///
/// Oyuncu kabin ustunden bir gezegen birakir; ayni kademedeki iki gezegen
/// temas edince bir ust kademeye (Merkur -> ... -> Gunes) birlesir. Bir
/// gezegen tehlike cizgisinin ustunde ~2 sn kalirsa oyun biter.
///
/// Modlar:
///  - [MergeMode.endless]: game over'a kadar suren sonsuz mod. XP/meteor/
///    rekorlar buradan.
///  - [MergeMode.daily]: gunluk seri. Herkese ayni tohumlu gezegen dizisi;
///    sinirli birakista hedef gezegene ulas (bkz. MergeChallenge.daily).
///    Basarinca seri artar.
///  - [MergeMode.comet]: kuyruklu yildiz etkinligi (MergeChallenge.comet),
///    pencere basina bir kez meteor/XP odulu.
///
/// Tum modlarda: odullu reklam/kurtarma hakkiyla bir kez "devam et"
/// (en ustteki 6 gezegen kaldirilir), gecis reklami sayaci, analytics.
class PlanetMergeScreen extends StatefulWidget {
  final MergeMode mode;

  /// Sadece [MergeMode.levels] icin: oynanacak bolum numarasi (1..).
  final int level;
  const PlanetMergeScreen({
    super.key,
    this.mode = MergeMode.endless,
    this.level = 1,
  });

  @override
  State<PlanetMergeScreen> createState() => _PlanetMergeScreenState();
}

class _Particle {
  double x, y, vx, vy, life;
  final double maxLife;
  final double size;
  final Color color;
  _Particle(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color)
      : maxLife = life;
}

/// Birlesmede, birlesme noktasindan yukari suzulup kaybolan "+puan" yazisi.
class _ScorePop {
  double x, y, life;
  final double maxLife;
  final String text;
  final double fontSize;
  final Color color;
  _ScorePop(this.x, this.y, this.life, this.text, this.fontSize, this.color)
      : maxLife = life;
}

/// Bir gezegen gucunun ekrandaki gecici gorsel efekti (dalga / patlama).
class _PowerFx {
  final CosmicPower power;
  final double x, y, radius;
  double life;
  final double maxLife;
  _PowerFx(this.power, this.x, this.y, this.radius, this.life)
      : maxLife = life;
}

class _PlanetMergeScreenState extends State<PlanetMergeScreen>
    with SingleTickerProviderStateMixin {
  static const _tutorialKey = 'pm_tutorial_seen_v1';
  static const _dropCooldown = 0.5;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// Sadece tahta (CustomPaint) her frame yeniden cizilir; ust bilgi
  /// alanlari asagidaki kucuk notifier'lar DEGISINCE guncellenir.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<int> _scoreN = ValueNotifier<int>(0);
  final ValueNotifier<int> _nextN = ValueNotifier<int>(0);
  final ValueNotifier<int> _bestTierN = ValueNotifier<int>(0);
  final ValueNotifier<int> _dropsN = ValueNotifier<int>(0);

  Random _rng = Random();

  /// Parcacik efektleri icin AYRI rastgele uretec: meydan okumadaki
  /// tohumlu gezegen dizisini (_rng) bozmamak icin.
  final Random _fx = Random();
  late PlanetMergeWorld _world;
  final List<_Particle> _particles = [];
  final List<_ScorePop> _pops = [];

  /// Gezegen gucu efektleri + efekt animasyonlari icin gecen sure (sn).
  final List<_PowerFx> _powerFx = [];
  double _fxTime = 0;

  /// Bu oturumda tanitimi (toast) gosterilen gucler.
  static final Set<String> _powersAnnounced = <String>{};

  /// Oyun sonu "XP x2" reklami kullanildi mi (1 = evet).
  final ValueNotifier<int> _doubledN = ValueNotifier<int>(0);

  /// "Sil" guclendiricisi secim modunda mi (bir gezegene dokunulacak).
  final ValueNotifier<bool> _bombModeN = ValueNotifier<bool>(false);

  /// Combo: ust uste birlesme sayisi ve devam suresi sayaci.
  int _combo = 0;
  double _comboTimer = 0;

  /// Bu oyunun arkaplan temasi (her yeni oyunda yeniden secilir) ve bir
  /// onceki oyunda kullanilan tema (arka arkaya ayni tema gelmesin).
  String _themeId = 'default';
  static String? _lastThemeId;

  /// Bu oyunun haftalik kurali (sadece Sonsuz Mod; meydan okumada null).
  WeeklyRule? _rule;

  /// Oyun BASLARKEN ki rekorlar (oyun bitince PlayerProgress guncellenir,
  /// bu yuzden anlik gecis/yakin kacirma hesabi icin baslangic goruntusu).
  int _bestAtStart = 0;
  int _bestTodayAtStart = 0;
  int _bestWeekAtStart = 0;

  /// Bu oyunda hangi rekor basamagi kutlandi: 0 yok, 1 gunun, 2 haftanin,
  /// 3 tum zamanlarin.
  int _recordTier = 0;

  /// null = sonsuz mod.
  MergeChallenge? _challenge;

  int _currentTier = 0;
  int _nextTier = 0;
  double _aimX = PlanetMergeConfig.worldW / 2;
  double _cooldown = 0;
  int _drops = 0;
  double _elapsed = 0;

  bool _paused = false; // ogretici/giris diyalogu acikken
  final Map<int, double> _prevVy = {}; // inis algilama: onceki karedeki dikey hiz

  // ---- Adim adim ogretici (sadece ilk Sonsuz Mod oyunu) ----
  final GlobalKey _kBoard = GlobalKey();
  final GlobalKey _kNext = GlobalKey();
  final GlobalKey _kScore = GlobalKey();
  final GlobalKey _kPower = GlobalKey();
  final GlobalKey _kChain = GlobalKey();
  bool _tutorialRun = false;
  int _tutForceTier = 0; // ilk atislar hep en kucuk gezegen (birlesme garanti)
  int _tutStage = 0; // 1: ilk birakisi bekle, 2: ilk birlesmeyi bekle
  TutorialHandle? _tutHandle;
  bool _continueUsed = false;

  /// Bu oyun icin gecis reklami sayaci zaten arttirildi mi (geri tusu +
  /// diyalog cikisi ayni oyunu iki kez saymasin).
  bool _adCounted = false;
  bool _dialogShown = false;
  bool _runFinalized = false;

  // ---- Analitik: oyun ozeti sayaclari (run_end olayi icin) ----
  int _runMerges = 0;
  int _runMaxCombo = 0;
  int _runPowers = 0;
  bool _runIsTutorial = false;
  String _endReason = 'quit'; // quit | game_over | won | failed | out_of_drops
  bool _challengeWon = false;
  int _shownTier = -1;

  /// Son birakistan sonra tahta durulana kadar bekleme (birakis bitince).
  double _idleTime = 0;
  double _sinceLastDrop = 0;

  // Odul takibi (artimli: devam et sonrasi tekrar game over olursa
  // ayni puan iki kez odenmez).
  int _xpPaid = 0;
  int _runXp = 0;
  int _runMeteors = 0;

  String get _modeName => switch (widget.mode) {
        MergeMode.endless => 'merge',
        MergeMode.daily => 'merge_daily',
        MergeMode.comet => 'merge_comet',
        MergeMode.levels => 'merge_level',
      };

  bool get _outOfDrops {
    final ch = _challenge;
    return ch != null && _drops >= ch.maxDrops;
  }

  @override
  void initState() {
    super.initState();
    _challenge = switch (widget.mode) {
      MergeMode.endless => null,
      MergeMode.daily =>
        MergeChallenge.daily(null, PlayerProgress.instance.activeDailyStreak),
      MergeMode.comet => MergeChallenge.comet(),
      MergeMode.levels =>
        MergeChallenge.forLevel(LevelCatalog.level(widget.level)),
    };
    _tutorialRun = widget.mode == MergeMode.endless &&
        TutorialService.instance.phase == TutorialPhase.game;
    if (_tutorialRun) {
      _tutForceTier = 6;
      _paused = true; // ogretici balonu acilana kadar bekle
    }
    _resetRun();
    SoundService.instance.playBgm('audio/kinetic_overdrive.mp3');
    // Sayfa gecisi bittikten sonra bir kez daha garantiye al (zaten caliyorsa
    // hicbir sey yapmaz, calmiyorsa baslatir).
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) SoundService.instance.playBgm('audio/kinetic_overdrive.mp3');
    });
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showStartDialogs());
    Future<void>.delayed(const Duration(milliseconds: 700), _announceRule);
  }

  @override
  void dispose() {
    _tutHandle?.close();
    _ticker.dispose();
    _frame.dispose();
    _scoreN.dispose();
    _doubledN.dispose();
    _bombModeN.dispose();
    _nextN.dispose();
    _bestTierN.dispose();
    _dropsN.dispose();
    super.dispose();
  }

  void _resetRun() {
    final ch = _challenge;
    _rule = (ch == null && !_tutorialRun) ? WeeklyRules.current() : null;
    final prog = PlayerProgress.instance;
    _bestAtStart = prog.mergeBestScore;
    _bestTodayAtStart = prog.bestToday;
    _bestWeekAtStart = prog.bestWeek;
    _recordTier = 0;
    _prevVy.clear();
    _world = PlanetMergeWorld(
      dangerY: ch?.dangerY ?? _rule?.dangerY ?? PlanetMergeConfig.dangerY,
      gravity: _rule?.gravity ?? PlanetMergeConfig.gravity,
      restitution: _rule?.restitution ?? PlanetMergeConfig.restitution,
      // Gezegen gucleri sadece Sonsuz Modda (meydan okumalar dengeli kalsin).
      powers: ch == null && !_tutorialRun,
    );
    _powerFx.clear();
    final lv = ch?.level;
    if (lv != null) _world.setupLevel(lv); // buzlu + kilitli baslangic gezegenleri
    // Meydan okumada her deneme AYNI tohumla baslar -> ayni gezegen dizisi.
    _rng = ch != null ? ch.newRng() : Random();
    _particles.clear();
    _pops.clear();
    _adCounted = false;
    _themeId = _pickTheme();
    _doubledN.value = 0;
    _bombModeN.value = false;
    _combo = 0;
    _comboTimer = 0;
    _drops = 0;
    _elapsed = 0;
    _idleTime = 0;
    _sinceLastDrop = 0;
    _xpPaid = 0;
    _runXp = 0;
    _runMeteors = 0;
    _continueUsed = false;
    _dialogShown = false;
    _runFinalized = false;
    _runMerges = 0;
    _runMaxCombo = 0;
    _runPowers = 0;
    _endReason = 'quit';
    _runIsTutorial = _tutorialRun;
    _challengeWon = false;
    _shownTier = -1;
    _cooldown = 0;
    _currentTier = _pickTier();
    _nextTier = _pickTier();
    _scoreN.value = 0;
    _nextN.value = _nextTier;
    _bestTierN.value = 0;
    _dropsN.value = 0;
    unawaited(AnalyticsService.instance.logLevelStart(
        _modeName,
        widget.mode == MergeMode.daily
            ? PlayerProgress.dailyNumber()
            : widget.mode == MergeMode.levels
                ? widget.level
                : 1));
    unawaited(AnalyticsService.instance.log('run_start', {
      'mode': _modeName,
      'tutorial': _runIsTutorial,
      'best_score': PlayerProgress.instance.mergeBestScore,
      'theme': _themeId,
      'rule': _rule?.titleKey,
    }));
  }

  /// Sonsuz modda: kucuklere agirlikli (0..4). Meydan okumada:
  /// meydan okumanin kendi agirlik tablosu.
  int _pickTier() {
    if (_tutForceTier > 0) {
      _tutForceTier--;
      return 0;
    }
    final ch = _challenge;
    if (ch != null) return ch.pickTier(_rng);
    final weights = _endlessWeights();
    final total = weights.reduce((a, b) => a + b);
    var roll = _rng.nextDouble() * total;
    for (var i = 0; i < weights.length; i++) {
      if (roll < weights[i]) return i;
      roll -= weights[i];
    }
    return 0;
  }

  // ---- Sonsuz mod zorluk egrisi ---------------------------------------
  // Oyun ilerledikce (birakis sayisina gore) gelen gezegenlerin dagilimi
  // kucuklerden buyuklere kayar; [_rampDrops] birakista tepe noktaya
  // ulasir ve oradan sonra SABIT kalir (oyunun sonuna kadar ayni, zor
  // seviye). Tepe noktayi sertlestirmek/yumusatmak icin _hardWeights'i
  // oyna; egrinin uzunlugu icin _rampDrops'u degistir.
  static const int _rampDrops = 120;
  static const List<double> _easyWeights = [40, 28, 18, 10, 4, 0];
  static const List<double> _hardWeights = [10, 16, 22, 24, 17, 11];

  /// 0 (kolay baslangic) .. 1 (sabitlenmis zor seviye).
  double get _difficulty {
    final t = (_drops / _rampDrops).clamp(0.0, 1.0).toDouble();
    final d = t * t * (3 - 2 * t); // yumusak gecis
    final r = _rule;
    if (r == null) return d;
    return d.clamp(r.difficultyMin, r.difficultyMax).toDouble();
  }

  List<double> _endlessWeights() {
    final d = _difficulty;
    return List<double>.generate(
      _easyWeights.length,
      (i) => _easyWeights[i] + (_hardWeights[i] - _easyWeights[i]) * d,
    );
  }

  // ---------------------------------------------------------------------
  // Baslangic diyaloglari (ogretici + meydan okuma girisi)
  // ---------------------------------------------------------------------
  Future<void> _showStartDialogs() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_tutorialKey) ?? false;
    if (!mounted) return;
    if (_tutorialRun) {
      // Yeni adim adim ogretici eski 3 kurallik diyaloğun yerini alir.
      await prefs.setBool(_tutorialKey, true);
      unawaited(_runGameTutorial());
      return;
    }
    if (!seen) {
      _paused = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _TutorialDialog(),
      );
      await prefs.setBool(_tutorialKey, true);
      _paused = false;
    }
    final ch = _challenge;
    if (ch != null && mounted) {
      _paused = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChallengeIntroDialog(challenge: ch),
      );
      _paused = false;
    }
  }

  // ---------------------------------------------------------------------
  // Adim adim oyun ici ogretici
  // ---------------------------------------------------------------------
  bool get _tutOk =>
      mounted && TutorialService.instance.phase == TutorialPhase.game;

  /// Bilgi adimi: oyun duraklar, oyuncu "Devam"a basar. false = ogretici bitti
  /// (atlandi ya da ekrandan cikildi).
  Future<bool> _tutInfo(TutorialStep step) async {
    if (!_tutOk) return false;
    _paused = true;
    final h = TutorialOverlay.show(context, step);
    _tutHandle = h;
    final skipped = await h.done;
    if (skipped) {
      await TutorialService.instance.skip();
      _tutorialRun = false;
      if (mounted) _paused = false;
      return false;
    }
    return _tutOk;
  }

  /// Oyun olayi bekleyen (manuel kapanan) adim: oyun akar, tahta dokunulabilir.
  Future<bool> _tutWait(TutorialStep step, int stage) async {
    if (!_tutOk) return false;
    _paused = false;
    _tutStage = stage;
    final h = TutorialOverlay.show(context, step);
    _tutHandle = h;
    final skipped = await h.done;
    _tutStage = 0;
    if (skipped) {
      await TutorialService.instance.skip();
      _tutorialRun = false;
      return false;
    }
    return _tutOk;
  }

  Future<void> _runGameTutorial() async {
    try {
      await _runGameTutorialSteps();
    } finally {
      // Hangi yoldan bitirse bitsin oyun donuk kalmasin.
      if (mounted) _paused = false;
    }
  }

  Future<void> _runGameTutorialSteps() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_tutOk) return;
    const total = 10;
    var n = 0;
    String c() => '${++n}/$total';

    // 1) Ilk atis.
    if (!await _tutWait(
      TutorialStep(
        target: _kBoard,
        textKey: 'tut_g_drop',
        advance: TutorialAdvance.manual,
        holePadding: 0,
        counter: c(),
      ),
      1,
    )) {
      return;
    }
    // 2) Siradaki gezegen.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!await _tutInfo(TutorialStep(
        target: _kNext, textKey: 'tut_g_next', counter: c()))) {
      return;
    }
    // 3) Ilk birlesme.
    if (!await _tutWait(
      TutorialStep(
        target: _kBoard,
        textKey: 'tut_g_drop2',
        advance: TutorialAdvance.manual,
        holePadding: 0,
        counter: c(),
      ),
      2,
    )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // 4..10) Bilgi adimlari.
    if (!await _tutInfo(TutorialStep(textKey: 'tut_g_merge', counter: c()))) {
      return;
    }
    if (!await _tutInfo(TutorialStep(
        target: _kScore, textKey: 'tut_g_score', counter: c()))) {
      return;
    }
    if (!await _tutInfo(TutorialStep(
        target: _kChain, textKey: 'tut_g_chain', counter: c()))) {
      return;
    }
    if (!await _tutInfo(TutorialStep(
      target: _kBoard,
      textKey: 'tut_g_danger',
      holePadding: 6,
      holeBuilder: (r) {
        final y = r.top + r.height * (_world.dangerY / PlanetMergeConfig.worldH);
        return Rect.fromLTWH(r.left, y - 10, r.width, 20);
      },
      counter: c(),
    ))) {
      return;
    }
    if (!await _tutInfo(TutorialStep(
        target: _kPower, textKey: 'tut_g_power', counter: c()))) {
      return;
    }
    if (!await _tutInfo(TutorialStep(textKey: 'tut_g_combo', counter: c()))) {
      return;
    }
    if (!await _tutInfo(
        TutorialStep(textKey: 'tut_g_free', showSkip: false, counter: c()))) {
      return;
    }
    _paused = false;
    _tutorialRun = false;
    await TutorialService.instance.setPhase(TutorialPhase.home2);
  }

  // ---------------------------------------------------------------------
  // Frame dongusu
  // ---------------------------------------------------------------------
  void _onTick(Duration elapsed) {
    var dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    // Uygulama arka plandan donunce dev bir dt gelmesin (sure/fizik).
    if (dt > 0.1) dt = 0.1;

    _fxTime += dt;
    if (_cooldown > 0) _cooldown = max(0.0, _cooldown - dt);
    if (_comboTimer > 0) {
      _comboTimer -= dt;
      if (_comboTimer <= 0) {
        _comboTimer = 0;
        _combo = 0;
      }
    }

    if (!_paused && !_world.gameOver && !_challengeWon) {
      if (!_dialogShown) _elapsed += dt;
      _world.step(dt);
      final events = _world.takeEvents();
      if (events.isNotEmpty) _handleEvents(events);
      final powerEvents = _world.takePowerEvents();
      if (powerEvents.isNotEmpty) _handlePowerEvents(powerEvents);
      final obstacleEvents = _world.takeObstacleEvents();
      if (obstacleEvents.isNotEmpty) _handleObstacleEvents(obstacleEvents);
      // Inis sesi/titresimi: yeni birakilan gezegenin dikey hizi aniden dusunce (yigina/zemine carpti).
      for (final b in _world.bodies) {
        if (b.age > 3) {
          _prevVy.remove(b.id);
          continue;
        }
        final prev = _prevVy[b.id];
        if (prev != null && prev > 45 && b.vy < prev * 0.4) {
          SoundService.instance.landAt(prev);
          if (prev > 120) HapticService.instance.light();
        }
        _prevVy[b.id] = b.vy;
      }
      // Yigin tehlike cizgisine yaklasinca kalp atisi gibi hafif titresim.
      if (_world.dangerTimer > 0.3) HapticService.instance.tension();
      _scoreN.value = _world.score;
      _checkRecords(_world.score);
      _bestTierN.value = _world.bestTier;

      if (!_dialogShown) {
        if (_world.gameOver) {
          _dialogShown = true;
          unawaited(_challenge == null
              ? _onGameOver()
              : _onChallengeFailed(outOfDrops: false));
        } else if (_outOfDrops) {
          _checkOutOfDrops(dt);
        }
      }
    }
    _stepParticles(dt);
    _frame.value++;
  }

  /// Birakis hakki bitti: tahta durulana (birlesme zincirleri bitene) kadar
  /// bekle, hedefe ulasilmadiysa basarisiz say.
  void _checkOutOfDrops(double dt) {
    _sinceLastDrop += dt;
    var maxSpeed = 0.0;
    for (final b in _world.bodies) {
      maxSpeed = max(maxSpeed, max(b.vx.abs(), b.vy.abs()));
    }
    if (maxSpeed < 4) {
      _idleTime += dt;
    } else {
      _idleTime = 0;
    }
    if (_idleTime > 0.8 || _sinceLastDrop > 8) {
      _dialogShown = true;
      unawaited(_onChallengeFailed(outOfDrops: true));
    }
  }

  void _handleEvents(List<MergeEvent> events) {
    if (_tutStage == 2) {
      _tutStage = 0;
      _tutHandle?.close();
    }
    var played = false;
    var maxTier = -1;
    for (final e in events) {
      maxTier = max(maxTier, e.tier < 0 ? PlanetMergeConfig.tierCount : e.tier);
      final bonus = _applyCombo(e);
      _runMerges++;
      if (_combo > _runMaxCombo) _runMaxCombo = _combo;
      final prog = PlayerProgress.instance;
      prog.recordMission(MissionMetric.merges, 1);
      prog.recordMission(MissionMetric.bestTier,
          e.tier < 0 ? PlanetMergeConfig.tierCount : e.tier);
      prog.recordMission(MissionMetric.bestCombo, _combo);
      if (e.tier < 0) {
        // Iki Karanlik Kutle birlesti: yok oldu, buyuk kutlama.
        _burst(e.x, e.y, const Color(0xFFFFD54F), 36);
        _addPop(e, const Color(0xFFFFD54F), 26, bonus: bonus);
        SoundService.instance.fireworkPop();
        SoundService.instance.win();
        played = true;
        continue;
      }
      final color = AppColors.colorFor(PlanetMergeConfig.tierImage[e.tier]);
      _burst(e.x, e.y, color, 10 + e.tier);
      _addPop(e, Color.lerp(color, const Color(0xFFFFE082), 0.65)!,
          14.0 + e.tier * 1.1,
          bonus: bonus);
      if (!played) {
        SoundService.instance.orbitDeliver();
        played = true;
      }
      final ch = _challenge;
      if (ch != null &&
          e.tier >= ch.targetTier &&
          !_challengeWon &&
          !_dialogShown) {
        _challengeWon = true;
        _dialogShown = true;
        _burst(e.x, e.y, const Color(0xFFFFD54F), 40);
        SoundService.instance.fireworkPop();
        unawaited(_onChallengeWon());
      }
      if (e.tier > _shownTier) {
        _shownTier = e.tier;
        if (e.tier >= 3 && mounted) {
          CustomToast.show(
            context,
            t('pm_newPlanet', {'name': t('pm_planet_${e.tier}')}),
            icon: '🪐',
            accentColor: color,
          );
          if (e.tier >= 5) SoundService.instance.levelUp();
        }
      }
    }
    // Titresim + combo sesi (grup basina bir kez).
    if (maxTier >= 7 || _combo >= 4) {
      HapticService.instance.heavy();
    } else if (maxTier >= 3 || _combo >= 2) {
      HapticService.instance.medium();
    } else {
      HapticService.instance.light();
    }
    if (_combo >= 6) {
      HapticService.instance.pattern([
        [0, 2],
        [90, 2],
      ]);
    }
    if (_combo >= 2) SoundService.instance.combo(_combo - 1);
  }

  /// Gezegen gucu tetiklendi: gorsel efekt, ses, titresim, yazi + ilk
  /// keşifte kisa tanitim.
  void _handlePowerEvents(List<PowerEvent> events) {
    for (final e in events) {
      final info = CosmicPowers.info(e.power);
      switch (e.power) {
        case CosmicPower.ringPulse:
          _powerFx.add(_PowerFx(e.power, e.x, e.y, e.radius, 0.85));
          SoundService.instance.orbitRotate();
          HapticService.instance.medium();
          break;
        case CosmicPower.solarFlare:
          _powerFx.add(_PowerFx(e.power, e.x, e.y, e.radius, 1.0));
          SoundService.instance.fireworkPop();
          HapticService.instance.pattern([
            [0, 2],
            [90, 1],
          ]);
          for (final h in e.hits) {
            _burst(h.x, h.y, const Color(0xFFFFA24A), 9);
            _pops.add(_ScorePop(
              h.x.clamp(10.0, PlanetMergeConfig.worldW - 10).toDouble(),
              h.y,
              1.0,
              '+${h.points}',
              14,
              const Color(0xFFFFC46B),
            ));
          }
          break;
        case CosmicPower.singularity:
          _powerFx.add(_PowerFx(e.power, e.x, e.y, e.radius, 0.7));
          SoundService.instance.warpFlip();
          HapticService.instance.pattern([
            [0, 2],
            [110, 1],
            [110, 1],
          ]);
          break;
      }
      // Gucun adi tetiklendigi yerde kisa sure suzulur.
      _pops.add(_ScorePop(
        e.x.clamp(24.0, PlanetMergeConfig.worldW - 24).toDouble(),
        max(40.0, e.y - 16),
        1.7,
        '${info.icon} ${t(info.nameKey)}',
        16,
        info.color,
      ));
      while (_pops.length > 24) {
        _pops.removeAt(0);
      }
      unawaited(AnalyticsService.instance.log('planet_power', {
        'kind': info.id,
        'score': _world.score,
        'bodies': _world.bodies.length,
        'value': e.points,
      }));
      unawaited(_announcePower(info));
    }
  }

  /// Bolum Modu: buz catladi / kirildi, kilit acildi.
  void _handleObstacleEvents(List<ObstacleEvent> events) {
    for (final e in events) {
      final x = e.x.clamp(16.0, PlanetMergeConfig.worldW - 16).toDouble();
      switch (e.kind) {
        case ObstacleKind.iceCrack:
          _burst(e.x, e.y, const Color(0xFFBDE9FF), 8);
          SoundService.instance.land();
          HapticService.instance.light();
          _pops.add(_ScorePop(
              x, e.y, 0.9, '🧊 ${t('lv_crack')}', 13, const Color(0xFF9BDDFF)));
          break;
        case ObstacleKind.iceBreak:
          _burst(e.x, e.y, const Color(0xFFE6F7FF), 18);
          SoundService.instance.fireworkPop();
          HapticService.instance.medium();
          _pops.add(_ScorePop(
              x, e.y, 1.1, '✨ ${t('lv_thaw')}', 14, const Color(0xFFCDF1FF)));
          break;
        case ObstacleKind.unlock:
          _burst(e.x, e.y, const Color(0xFFFFD54F), 16);
          SoundService.instance.orbitDock();
          HapticService.instance.medium();
          _pops.add(_ScorePop(
              x, e.y, 1.2, '🔓 ${t('lv_unlock')}', 14, const Color(0xFFFFD54F)));
          break;
      }
    }
    while (_pops.length > 24) {
      _pops.removeAt(0);
    }
  }

  /// Bir gucun ilk keşfinde (cihaz basina bir kez) kisa aciklama gosterir.
  Future<void> _announcePower(PowerInfo info) async {
    if (!_powersAnnounced.add(info.id)) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'pm_power_seen_${info.id}';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    CustomToast.show(
      context,
      '${t('pw_new', {'name': t(info.nameKey)})}\n${t(info.descKey)}',
      icon: info.icon,
      accentColor: info.color,
      duration: const Duration(milliseconds: 4200),
    );
  }

  /// Yeni oyun icin arkaplan temasi: TUM temalardan rastgele (satin alma
  /// sarti yok; bir onceki hariç). Ayar kapaliysa aktif tema.
  String _pickTheme() {
    final progress = PlayerProgress.instance;
    if (!progress.randomThemePerGame) return progress.activeTheme;
    final pool = CosmicThemes.all.map((th) => th.id).toList();
    if (pool.length == 1) return pool.first;
    final candidates = pool.where((id) => id != _lastThemeId).toList();
    final pick = candidates[_fx.nextInt(candidates.length)];
    _lastThemeId = pick;
    return pick;
  }

  // ---------------------------------------------------------------------
  // Rekorlar: anlik gecis kutlamasi + header hedefi
  // ---------------------------------------------------------------------
  void _checkRecords(int score) {
    if (_challenge != null) return;
    var crossed = 0;
    if (_bestTodayAtStart > 0 && score > _bestTodayAtStart) crossed = 1;
    if (_bestWeekAtStart > 0 && score > _bestWeekAtStart) crossed = 2;
    if (_bestAtStart > 0 && score > _bestAtStart) crossed = 3;
    if (crossed > _recordTier) {
      _recordTier = crossed;
      _celebrateRecord(crossed);
    }
  }

  void _celebrateRecord(int level) {
    const gold = Color(0xFFFFD54F);
    final text = switch (level) {
      3 => t('pm_newRecord'),
      2 => t('pm_newWeekRecord'),
      _ => t('pm_newTodayRecord'),
    };
    _pops.add(_ScorePop(PlanetMergeConfig.worldW / 2, 52, 2.0, text,
        level == 3 ? 30.0 : 22.0, gold));
    _burst(PlanetMergeConfig.worldW / 2, 52, gold, 14.0.round() * level);
    if (level == 3) {
      SoundService.instance.win();
      HapticService.instance.heavy();
    } else {
      SoundService.instance.fireworkPop();
      HapticService.instance.medium();
    }
  }

  /// Header icin: skorun bir sonraki asilmamis rekor hedefi (yoksa null).
  _RecordTarget? _nextRecordTarget(int score) {
    final list = <_RecordTarget>[
      if (_bestTodayAtStart > 0)
        _RecordTarget(t('pm_recToday'), _bestTodayAtStart),
      if (_bestWeekAtStart > 0)
        _RecordTarget(t('pm_recWeek'), _bestWeekAtStart),
      if (_bestAtStart > 0) _RecordTarget(t('pm_recAll'), _bestAtStart),
    ]..sort((a, b) => a.value.compareTo(b.value));
    for (final r in list) {
      if (score <= r.value) return r;
    }
    return null;
  }

  Widget _buildRecordLine(int score) {
    final target = _nextRecordTarget(score);
    String text;
    var frac = 0.0;
    var hot = false;
    if (target == null) {
      if (_bestAtStart > 0) {
        text = '🏆 ${t('pm_newRecord')}';
        frac = 1.0;
        hot = true;
      } else {
        text = '${t('pm_best')}: $score';
      }
    } else {
      final remaining = target.value - score + 1;
      frac = (score / target.value).clamp(0.0, 1.0).toDouble();
      final close = remaining <= max(40, (target.value * 0.1).round());
      hot = close;
      text = close
          ? t('pm_closeTo', {'what': target.label, 'n': '$remaining'})
          : '${target.label}: ${target.value}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: hot ? const Color(0xFFFFD54F) : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: hot ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 130,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 3,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                hot ? const Color(0xFFFFD54F) : AppColors.accentSoft,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Oyun acilisinda haftalik kurali kisaca duyur.
  void _announceRule() {
    final r = _rule;
    if (r == null || !mounted || _tutorialRun) return;
    CustomToast.show(
      context,
      '${t(r.titleKey)}: ${t(r.descKey)}',
      icon: r.icon,
      accentColor: AppColors.accent,
    );
  }

  /// Birlesmeyi combo zincirine isler; eklenen bonus puani dondurur.
  /// Ayarlar: EconomyConfig.comboWindowSeconds / comboBonusPerStep /
  /// comboMaxSteps.
  int _applyCombo(MergeEvent e) {
    _combo = _comboTimer > 0 ? _combo + 1 : 1;
    _comboTimer = _rule?.comboWindow ?? EconomyConfig.comboWindowSeconds;
    final steps = min(_combo - 1, EconomyConfig.comboMaxSteps);
    if (steps <= 0 || e.points <= 0) return 0;
    final bonus = (e.points *
            steps *
            EconomyConfig.comboBonusPerStep *
            (_rule?.comboBonusMult ?? 1.0))
        .round();
    _world.score += bonus;
    return bonus;
  }

  void _addPop(MergeEvent e, Color color, double fontSize, {int bonus = 0}) {
    if (e.points <= 0) return;
    // Sinirdan tasmasin: dunya genisligi icinde tut.
    final x = e.x.clamp(10.0, PlanetMergeConfig.worldW - 10).toDouble();
    _pops.add(_ScorePop(x, e.y, 1.0, '+${e.points + bonus}', fontSize, color));
    if (_combo >= 2) {
      _pops.add(_ScorePop(
        x,
        e.y - 7,
        1.1,
        t('pm_combo', {'n': '$_combo'}),
        13.0 + min(_combo, 6) * 1.2,
        const Color(0xFFFF9A3C),
      ));
    }
    while (_pops.length > 18) {
      _pops.removeAt(0);
    }
  }

  void _burst(double x, double y, Color color, int count) {
    for (var i = 0; i < count; i++) {
      final a = _fx.nextDouble() * pi * 2;
      final sp = 12 + _fx.nextDouble() * 38;
      _particles.add(_Particle(
        x,
        y,
        cos(a) * sp,
        sin(a) * sp - 10,
        0.45 + _fx.nextDouble() * 0.4,
        0.6 + _fx.nextDouble() * 1.1,
        color,
      ));
    }
  }

  void _stepParticles(double dt) {
    if (_powerFx.isNotEmpty) {
      for (final f in _powerFx) {
        f.life -= dt;
      }
      _powerFx.removeWhere((f) => f.life <= 0);
    }
    if (_pops.isNotEmpty) {
      for (final q in _pops) {
        q.y -= 16 * dt;
        q.life -= dt;
      }
      _pops.removeWhere((q) => q.life <= 0);
    }
    if (_particles.isEmpty) return;
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 60 * dt;
      p.life -= dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
  }

  // ---------------------------------------------------------------------
  // Girdi
  // ---------------------------------------------------------------------
  void _aim(double localX, double scale) {
    _aimX = localX / scale;
  }

  /// Siradaki (birakilacak) gezegen buzlu mu? Bolum Modu: [LevelDef.isIceDrop].
  bool get _currentIsIce =>
      _challenge?.level?.isIceDrop(_drops + 1) ?? false;

  void _drop() {
    if (_paused || _world.gameOver || _challengeWon || _dialogShown) return;
    if (_cooldown > 0 || _outOfDrops) return;
    _world.drop(
      _currentTier,
      _aimX,
      ice: _currentIsIce ? (_challenge?.level?.iceHp ?? 2) : 0,
    );
    SoundService.instance.drop(); // inis sesi: gercek inista (bkz. _onTick)
    HapticService.instance.light();
    _currentTier = _nextTier;
    _nextTier = _pickTier();
    _nextN.value = _nextTier;
    _cooldown = _dropCooldown;
    _drops++;
    _dropsN.value = _drops;
    if (_tutStage == 1) {
      _tutStage = 0;
      _tutHandle?.close();
    }
    PlayerProgress.instance.recordMission(MissionMetric.drops, 1);
    _idleTime = 0;
    _sinceLastDrop = 0;
  }

  // ---------------------------------------------------------------------
  // Odul / oyun sonu
  // ---------------------------------------------------------------------

  /// SONSUZ MOD: o ana kadarki skorun XP/meteor/rekor odulunu (artimli,
  /// tekrar cagrilirsa ayni odul iki kez verilmez) oyuncuya yazar.
  Future<void> _settle() async {
    if (_challenge != null) return;
    final score = _world.score;
    if (score <= 0) return;
    final xpTotal = min(EconomyConfig.mergeXpMax,
        score ~/ EconomyConfig.mergeXpScoreDivisor);
    final xpDelta = max(0, xpTotal - _xpPaid);
    _xpPaid = max(_xpPaid, xpTotal);

    final meteors = await PlayerProgress.instance
        .settleMergeRecords(score: score, bestTier: _world.bestTier);
    _runXp += xpDelta;
    _runMeteors += meteors;
    if (xpDelta > 0 || meteors > 0) {
      await PlayerProgress.instance
          .addXpAndMeteors(xpDelta, meteors, source: 'run_tier_record');
    }
  }

  /// Oyun KESIN bitti (tekrar oyna / cik / geri): gorev sayaclari, toplam
  /// skor ve takimyildiz puani bir kez islenir.
  Future<void> _finalizeRun() async {
    if (_runFinalized) return;
    _runFinalized = true;
    await PlayerProgress.instance.recordMergeRun(
      score: _world.score,
      bestTier: _world.bestTier,
      drops: _drops,
      usedContinue: _continueUsed,
    );
    unawaited(AnalyticsService.instance.logLevelComplete(
      _modeName,
      widget.mode == MergeMode.daily
          ? PlayerProgress.dailyNumber()
          : widget.mode == MergeMode.levels
              ? widget.level
              : 1,
      stars: _world.bestTier,
      moves: _drops,
    ));
    if (_drops > 0) {
      unawaited(AnalyticsService.instance.log('run_end', {
        'mode': _modeName,
        'end_reason': _endReason,
        'score': _world.score,
        'best_tier': _world.bestTier,
        'drops': _drops,
        'merges': _runMerges,
        'max_combo': _runMaxCombo,
        'duration_s': _elapsed.round(),
        'continue_used': _continueUsed,
        'powers_used': _runPowers,
        'new_record': _world.score > _bestAtStart,
        'run_xp': _runXp,
        'run_meteors': _runMeteors,
        'tutorial': _runIsTutorial,
        'theme': _themeId,
      }));
    }
    if (_challenge == null && _world.bestTier >= 7) {
      unawaited(RatePromptService.instance.maybePromptAfterCleanWin(
        totalStagesCleared: PlayerProgress.instance.mergeRunsPlayed,
        cleanWin: !_continueUsed,
      ));
    }
  }

  Future<void> _settleAndFinalize() async {
    await _settle();
    await _finalizeRun();
  }

  /// Gecis reklami sayacini sadece "gercek" oyunlarda ilerlet (birkac
  /// saniyelik denemeler reklam tetiklemesin).
  Future<void> _maybeCountInterstitial() async {
    if (_adCounted) return;
    if (_drops >= EconomyConfig.mergeMinDropsForRun) {
      _adCounted = true;
      await AdService.instance.notifyStageCompleted();
    }
  }

  // ---- Sonsuz mod game over ----
  Future<void> _onGameOver() async {
    _endReason = 'game_over';
    SoundService.instance.invalid();
    HapticService.instance.pattern([
      [0, 2],
      [180, 2],
      [420, 1],
    ]);
    unawaited(AnalyticsService.instance.logGameStuckShown(_modeName));
    await _settle();
    if (!mounted) return;
    final finalScore = _world.score;
    String? recordNote;
    var isRecord = false;
    if (_bestAtStart > 0 && finalScore > _bestAtStart) {
      isRecord = true;
      recordNote =
          t('pm_newRecordDelta', {'n': '${finalScore - _bestAtStart}'});
    } else if (_bestAtStart > 0) {
      final need = _bestAtStart - finalScore + 1;
      if (need <= max(30, (_bestAtStart * 0.15).round())) {
        recordNote = t('pm_nearMiss', {'n': '$need'});
      }
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE6050616),
      builder: (ctx) => PopScope(
        canPop: false,
        child: _GameOverDialog(
          title: t('pm_gameOverTitle'),
          recordNote: recordNote,
          isRecord: isRecord,
          score: _world.score,
          bestScore: PlayerProgress.instance.mergeBestScore,
          bestTier: _world.bestTier,
          xp: _runXp,
          meteors: _runMeteors,
          xpBefore: max(0, PlayerProgress.instance.xp - _runXp),
          canContinue: !_continueUsed,
          rescues: PlayerProgress.instance.bankedRescues,
          doubledN: _doubledN,
          onDouble: () => _doubleReward(ctx),
          onContinue: () => _continueWithAd(ctx),
          onRetry: () => _retryFromDialog(ctx),
          onExit: () => _exitFromDialog(ctx),
        ),
      ),
    );
  }

  // ---- Meydan okuma: basarisiz ----
  Future<void> _onChallengeFailed({required bool outOfDrops}) async {
    final ch = _challenge!;
    _endReason = outOfDrops ? 'out_of_drops' : 'failed';
    SoundService.instance.invalid();
    HapticService.instance.heavy();
    unawaited(AnalyticsService.instance.logGameStuckShown(_modeName));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: _GameOverDialog(
          title: t('mc_failTitle'),
          message: outOfDrops ? t('mc_failOutOfDrops') : t('pm_gameOverTitle'),
          goalTier: ch.targetTier,
          score: _world.score,
          bestScore: 0,
          bestTier: _world.bestTier,
          xp: 0,
          meteors: 0,
          // Birakis hakki bittiyse "devam et" anlamsiz (kabin dolu degil).
          canContinue: !_continueUsed && !outOfDrops,
          rescues: PlayerProgress.instance.bankedRescues,
          onContinue: () => _continueWithAd(ctx),
          onRetry: () => _retryFromDialog(ctx),
          onExit: () => _exitFromDialog(ctx),
        ),
      ),
    );
  }

  // ---- Meydan okuma: basari ----
  Future<void> _onChallengeWon() async {
    final ch = _challenge!;
    _endReason = 'won';
    SoundService.instance.win();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    await _finalizeRun();
    if (!mounted) return;
    if (ch.kind == MergeChallengeKind.level) {
      await _onLevelWon(ch);
      return;
    }
    if (ch.kind == MergeChallengeKind.daily) {
      await PlayerProgress.instance.recordDailyResult(
        moves: _drops,
        optimal: ch.parDrops,
        timeSeconds: _elapsed.round(),
        score: _world.score,
        bestTier: _world.bestTier,
      );
      unawaited(RatePromptService.instance.maybePromptAfterCleanWin(
        totalStagesCleared: PlayerProgress.instance.mergeRunsPlayed,
        cleanWin: !_continueUsed,
      ));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DailyResultDialog(isReplay: false),
      );
    } else {
      final granted = await PlayerProgress.instance.recordCometEventComplete();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0xE6050616),
        builder: (_) => _CometWinDialog(
          targetTier: ch.targetTier,
          rewarded: granted,
          xpBefore: max(
            0,
            PlayerProgress.instance.xp -
                (granted ? EconomyConfig.cometXpReward : 0),
          ),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ---- Bolum Modu: bolum gecildi ----
  Future<void> _onLevelWon(MergeChallenge ch) async {
    final no = ch.levelNumber;
    final stars = LevelProgress.starsFor(
      drops: _drops,
      par: ch.parDrops,
      max: ch.maxDrops,
    );
    final res = await LevelProgress.instance.recordClear(no, stars);
    // Odul: ilk gecista 3 meteor + 30 XP, her yeni yildiz icin +1 meteor.
    final meteors = (res.firstClear ? 3 : 0) + res.newStars;
    final xp = res.firstClear ? 30 : 0;
    if (meteors > 0 || xp > 0) {
      await PlayerProgress.instance
          .addXpAndMeteors(xp, meteors, source: 'level_clear');
    }
    unawaited(AnalyticsService.instance.log('level_clear', {
      'level': no,
      'stars': stars,
      'drops': _drops,
      'max_drops': ch.maxDrops,
      'first_clear': res.firstClear,
      'continue_used': _continueUsed,
    }));
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE6050616),
      builder: (_) => _LevelWinDialog(
        level: no,
        stars: stars,
        meteors: meteors,
        xp: xp,
        hasNext: true, // bolumler sonsuz
      ),
    );
    if (!mounted) return;
    await _maybeCountInterstitial();
    if (!mounted) return;
    if (action == 'next') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            PlanetMergeScreen(mode: MergeMode.levels, level: no + 1),
      ));
    } else if (action == 'retry') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PlanetMergeScreen(mode: MergeMode.levels, level: no),
      ));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _continueWithAd(BuildContext dialogCtx) async {
    final progress = PlayerProgress.instance;
    bool granted;
    var via = 'ad';
    if (progress.bankedRescues > 0) {
      // Magazadan stoklanan hak: reklam izletmeden kullan.
      via = 'banked';
      await progress.spendBankedRescue();
      granted = true;
    } else {
      granted = await AdService.instance.showRewardedAdFlow(
            dialogCtx,
            icon: '🪐',
            title: t('pm_continueTitle'),
            subtitle: t('pm_continueSubtitle'),
            placementId: 'planet_merge_continue',
          ) ==
          true;
    }
    if (!granted) return;
    unawaited(AnalyticsService.instance.log('continue_used', {
      'via': via,
      'score': _world.score,
      'drops': _drops,
      'best_tier': _world.bestTier,
    }));
    _continueUsed = true;
    SoundService.instance.reward();
    _world.rescue(count: 6);
    _cooldown = 0.3;
    _dialogShown = false;
    _idleTime = 0;
    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
  }

  Future<void> _retryFromDialog(BuildContext dialogCtx) async {
    SoundService.instance.buttonTap();
    await _settleAndFinalize();
    await _maybeCountInterstitial();
    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
    if (mounted) setState(_resetRun);
  }

  Future<void> _exitFromDialog(BuildContext dialogCtx) async {
    SoundService.instance.buttonTap();
    await _settleAndFinalize();
    await _maybeCountInterstitial();
    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Geri tusu / cikis: o ana kadarki oyunun odulunu/sayacini isle.
        if (didPop) {
          unawaited(() async {
            await _settleAndFinalize();
            await _maybeCountInterstitial();
          }());
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
                child: CosmicThemes.byId(_themeId)
                    .builder(key: ValueKey<String>(_themeId)),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  if (_challenge != null) _buildGoalBar(_challenge!),
                  Expanded(child: _buildBoard()),
                  _buildHint(),
                  if (_challenge == null)
                    KeyedSubtree(key: _kPower, child: _buildPowerBar()),
                  KeyedSubtree(key: _kChain, child: _buildChainStrip()),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isChallenge = _challenge != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 14, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              SoundService.instance.buttonTap();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
          ),
          Expanded(
            child: KeyedSubtree(
              key: _kScore,
              child: ValueListenableBuilder<int>(
              valueListenable: _scoreN,
              builder: (context, score, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnimatedScore(score: score),
                    const SizedBox(height: 2),
                    if (isChallenge)
                      Text(
                        _challenge!.difficultyLevel > 0
                            ? '${_challenge!.title} · 🔥 ${t('streak_diffTag', {'n': '${_challenge!.difficultyLevel}'})}'
                            : _challenge!.title,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      _buildRecordLine(score),
                  ],
                );
              },
            ),
            ),
          ),
          KeyedSubtree(
            key: _kNext,
            child: ValueListenableBuilder<int>(
            valueListenable: _nextN,
            builder: (context, next, child) {
              return Column(
                children: [
                  Text(
                    t('pm_next'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _PlanetIcon(tier: next, size: 36),
                ],
              );
            },
          ),
          ),
        ],
      ),
    );
  }

  /// Meydan okuma modunda: hedef gezegen + kalan birakis sayisi.
  Widget _buildGoalBar(MergeChallenge ch) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.tubeGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.tubeGlassBorder),
        ),
        child: Row(
          children: [
            const Text('🎯', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            _PlanetIcon(tier: ch.targetTier, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t('pm_planet_${ch.targetTier}'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _dropsN,
              builder: (context, drops, child) {
                final left = max(0, ch.maxDrops - drops);
                return Text(
                  t('mc_dropsLeft', {'n': '$left', 'max': '${ch.maxDrops}'}),
                  style: TextStyle(
                    color: left <= 5 ? AppColors.danger : AppColors.accentSoft,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth - 24;
        final maxH = c.maxHeight - 6;
        const aspect = PlanetMergeConfig.worldW / PlanetMergeConfig.worldH;
        var w = maxW;
        var h = w / aspect;
        if (h > maxH) {
          h = maxH;
          w = h * aspect;
        }
        final scale = w / PlanetMergeConfig.worldW;
        return Center(
          child: SizedBox(
            key: _kBoard,
            width: w,
            height: h,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _aim(e.localPosition.dx, scale),
              onPointerMove: (e) => _aim(e.localPosition.dx, scale),
              onPointerUp: (e) {
                if (_bombModeN.value) {
                  unawaited(_tryBomb(e.localPosition, scale));
                  return;
                }
                _aim(e.localPosition.dx, scale);
                _drop();
              },
              child: CustomPaint(
                size: Size(w, h),
                painter: _MergePainter(this, _frame),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Guclendiriciler (sadece Sonsuz Mod): sil / degistir / salla
  // ---------------------------------------------------------------------
  Widget _buildPowerBar() {
    return AnimatedBuilder(
      animation: Listenable.merge([PlayerProgress.instance, _bombModeN]),
      builder: (context, _) {
        final p = PlayerProgress.instance;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: SizedBox(
            height: 44,
            child: _bombModeN.value
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.tubeGlass,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.warning),
                    ),
                    child: Row(
                      children: [
                        const Text('💥', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t('power_bombHint'),
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _bombModeN.value = false,
                          child: Text(
                            t('power_cancel'),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      _powerButton('bomb', '💥', p.powerBombs),
                      _powerButton('swap', '🔄', p.powerSwaps),
                      _powerButton('shake', '🌀', p.powerShakes),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _powerButton(String kind, String emoji, int count) {
    final has = count > 0;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_onPowerTap(kind)),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.tubeGlass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: has ? AppColors.accentSoft : AppColors.tubeGlassBorder,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 5),
                  Text(
                    t('power_$kind'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: has ? AppColors.accent : AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      has ? '$count' : '+',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onPowerTap(String kind) async {
    if (_paused || _world.gameOver || _challengeWon || _dialogShown) return;
    if (PlayerProgress.instance.powerCount(kind) <= 0) {
      await _offerPower(kind);
      return;
    }
    switch (kind) {
      case 'bomb':
        _beginBomb();
      case 'swap':
        await _usePowerSwap();
      default:
        await _usePowerShake();
    }
  }

  void _beginBomb() {
    if (_world.bodies.isEmpty) return;
    SoundService.instance.buttonTap();
    HapticService.instance.tick();
    _bombModeN.value = true;
  }

  /// Bomba modunda tahtaya dokunuldu: dokunulan gezegeni sil.
  Future<void> _tryBomb(Offset local, double scale) async {
    final hit = _world.removeAt(local.dx / scale, local.dy / scale);
    if (hit == null) return; // bos yere dokundu: modda kal
    _bombModeN.value = false;
    _burst(hit.x, hit.y,
        AppColors.colorFor(PlanetMergeConfig.tierImage[hit.tier]), 18);
    SoundService.instance.fireworkPop();
    HapticService.instance.medium();
    await PlayerProgress.instance.usePower('bomb');
    _logPowerUse('bomb');
  }

  void _logPowerUse(String kind) {
    _runPowers++;
    unawaited(AnalyticsService.instance.log('power_use', {
      'kind': kind,
      'score': _world.score,
      'drops': _drops,
      'bodies': _world.bodies.length,
      'left': PlayerProgress.instance.powerCount(kind),
    }));
  }

  Future<void> _usePowerSwap() async {
    if (_currentTier == _nextTier) return; // bosa harcama
    if (!await PlayerProgress.instance.usePower('swap')) return;
    _logPowerUse('swap');
    final tmp = _currentTier;
    _currentTier = _nextTier;
    _nextTier = tmp;
    _nextN.value = _nextTier;
    SoundService.instance.undo();
    HapticService.instance.tick();
  }

  Future<void> _usePowerShake() async {
    if (_world.bodies.isEmpty) return;
    if (!await PlayerProgress.instance.usePower('shake')) return;
    _logPowerUse('shake');
    _world.shake(_fx);
    SoundService.instance.warpFlip();
    HapticService.instance.pattern([
      [0, 1],
      [90, 0],
      [180, 1],
    ]);
  }

  /// Hakki biten guclendirici: meteorla al ya da reklam izleyip +1 kazan.
  Future<void> _offerPower(String kind) async {
    _paused = true;
    try {
      final price = PlayerProgress.powerPrice(kind);
      final choice = await showDialog<int>(
        context: context,
        builder: (ctx) => _PowerOfferDialog(
          name: t('power_$kind'),
          price: price,
          meteors: PlayerProgress.instance.meteors,
        ),
      );
      unawaited(AnalyticsService.instance.log('power_offer_result', {
        'kind': kind,
        'choice': choice == 1 ? 'buy' : (choice == 2 ? 'ad' : 'dismiss'),
        'meteors': PlayerProgress.instance.meteors,
        'price': price,
      }));
      if (!mounted) return;
      if (choice == 1) {
        final ok = await PlayerProgress.instance.buyPowerWithMeteors(kind);
        if (!mounted) return;
        if (ok) {
          SoundService.instance.reward();
        } else {
          CustomToast.show(
            context,
            t('power_noMeteor'),
            icon: '☄️',
            accentColor: AppColors.warning,
          );
        }
      } else if (choice == 2) {
        final granted = await AdService.instance.showRewardedAdFlow(
          context,
          icon: '🎬',
          title: t('power_$kind'),
          placementId: 'power_$kind',
        );
        if (granted == true) {
          await PlayerProgress.instance.grantPower(kind, 1, 'ad');
          SoundService.instance.reward();
        }
      }
    } finally {
      _paused = false;
    }
  }

  /// Oyun sonu "XP x2" odullu reklami (sadece Sonsuz Mod).
  Future<void> _doubleReward(BuildContext dialogCtx) async {
    if (_doubledN.value > 0 || _runXp <= 0) return;
    final granted = await AdService.instance.showRewardedAdFlow(
      dialogCtx,
      icon: '🎬',
      title: t('pm_doubleTitle'),
      placementId: 'planet_merge_double',
    );
    if (granted != true) return;
    _doubledN.value = 1;
    await PlayerProgress.instance.addXpAndMeteors(
        _runXp, EconomyConfig.winDoubleXpMeteorBonus,
        source: 'ad_double');
    unawaited(AnalyticsService.instance
        .log('double_reward', {'xp': _runXp, 'score': _world.score}));
    SoundService.instance.reward();
  }

  Widget _buildHint() {
    return ValueListenableBuilder<int>(
      valueListenable: _dropsN,
      builder: (context, drops, child) {
        return SizedBox(
          height: 22,
          child: drops < 3
              ? Center(
                  child: Text(
                    t('pm_hint'),
                    style: const TextStyle(
                      color: AppColors.accentSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : (_rule == null
                  ? null
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_rule!.icon} ${t(_rule!.titleKey)}',
                          style: const TextStyle(
                            color: AppColors.accentSoft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )),
        );
      },
    );
  }

  /// Evrim zinciri: hangi gezegenin neye donustugunu gosterir; bu oyunda
  /// henuz ulasilmayan kademeler soluk gorunur. Meydan okumada hedef
  /// gezegen cerceveyle vurgulanir.
  Widget _buildChainStrip() {
    return ValueListenableBuilder<int>(
      valueListenable: _bestTierN,
      builder: (context, bestTier, child) {
        final target = _challenge?.targetTier;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (var i = 0; i < PlanetMergeConfig.tierCount; i++)
                Expanded(
                  child: Center(
                    child: _PlanetIcon(
                      tier: i,
                      size: 24,
                      dim: i > bestTier,
                      highlight: i == target,
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

// -----------------------------------------------------------------------
// Cizim
// -----------------------------------------------------------------------

/// [tier] kademesindeki gezegeni (gorseli, yoksa duz renkli daire) [c]
/// merkezli, [radius] piksel yaricapli collision dairesine oturtarak cizer.
void _drawPlanet(
  Canvas canvas,
  int tier,
  Offset c,
  double radius, {
  double opacity = 1,
  double scaleMul = 1,
  bool faces = true,
  int seed = 0,
  FaceMood mood = FaceMood.idle,
  double lookX = 0,
  double lookY = 0,
  double? timeSec,
}) {
  // Takili gizli gezegen (skin) varsa onun gorseli/olcegi kullanilir.
  final imgIndex = PlayerProgress.instance.activeImage(tier);
  final img = PlanetImages.forIndex(imgIndex);
  final alpha = (255 * opacity).round().clamp(0, 255).toInt();
  if (img == null) {
    canvas.drawCircle(
      c,
      radius * scaleMul,
      Paint()..color = AppColors.colorFor(imgIndex).withAlpha(alpha),
    );
    return;
  }
  final half = radius * PlayerProgress.instance.activeDrawScale(tier) * scaleMul;
  final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
  final dst = Rect.fromCircle(center: c, radius: half);
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromARGB(alpha, 255, 255, 255);
  canvas.drawImageRect(img, src, dst, paint);
  if (faces) {
    drawPlanetFace(
      canvas,
      imgIndex,
      c,
      half,
      opacity: opacity,
      seed: seed + tier,
      timeSec: timeSec ?? DateTime.now().millisecondsSinceEpoch / 1000.0,
      mood: mood,
      lookX: lookX,
      lookY: lookY,
    );
  }
}

/// Buzlu gezegen: gezegenin ustune yari saydam buz kabugu; [hp] 1 ise catlak.
void _drawIce(Canvas canvas, Offset c, double r, int hp) {
  final rr = r * 1.04;
  final rect = Rect.fromCircle(center: c, radius: rr);
  canvas.drawCircle(
    c,
    rr,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.4),
        radius: 1.0,
        colors: [Color(0xAAE6F7FF), Color(0x887CC8F0), Color(0xCC3A86C8)],
        stops: [0.0, 0.6, 1.0],
      ).createShader(rect),
  );
  canvas.drawCircle(
    c,
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, r * 0.07)
      ..color = const Color(0xDDEAF8FF),
  );
  // Parlama yayi.
  canvas.drawArc(
    Rect.fromCircle(center: c, radius: r * 0.78),
    pi * 1.05,
    pi * 0.5,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.5, r * 0.09)
      ..color = const Color(0xC8FFFFFF),
  );
  if (hp <= 1) {
    final crack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = max(1.0, r * 0.05)
      ..color = const Color(0xF2FFFFFF);
    final path = Path()
      ..moveTo(c.dx - r * 0.1, c.dy - r * 0.62)
      ..lineTo(c.dx + r * 0.05, c.dy - r * 0.2)
      ..lineTo(c.dx - r * 0.15, c.dy + r * 0.1)
      ..lineTo(c.dx + r * 0.1, c.dy + r * 0.48)
      ..moveTo(c.dx + r * 0.05, c.dy - r * 0.2)
      ..lineTo(c.dx + r * 0.46, c.dy - r * 0.04);
    canvas.drawPath(path, crack);
  }
}

/// Kilitli (sabit) gezegen: celik halka + ortada kalan birlesme sayaci.
void _drawLock(Canvas canvas, Offset c, double r, int left) {
  canvas.drawCircle(c, r, Paint()..color = const Color(0x66101830));
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.0, r * 0.12)
      ..color = const Color(0xFF8FA3BF),
  );
  final link = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = max(1.5, r * 0.07)
    ..color = const Color(0xFFB6C4D8);
  for (var k = 0; k < 16; k++) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.84),
      k * (pi * 2 / 16),
      0.22,
      false,
      link,
    );
  }
  final badgeR = max(8.0, r * 0.36);
  canvas.drawCircle(c, badgeR, Paint()..color = const Color(0xEE12203F));
  canvas.drawCircle(
    c,
    badgeR,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFD54F),
  );
  final tp = TextPainter(
    text: TextSpan(
      text: '$left',
      style: TextStyle(
        color: const Color(0xFFFFD54F),
        fontWeight: FontWeight.w900,
        fontSize: badgeR * 1.15,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  final lockIcon = TextPainter(
    text: TextSpan(text: '🔒', style: TextStyle(fontSize: max(9.0, r * 0.3))),
    textDirection: TextDirection.ltr,
  )..layout();
  lockIcon.paint(
      canvas, c + Offset(-lockIcon.width / 2, -r * 0.62 - lockIcon.height / 2));
}

/// Kutlecekim alanlari: acik mor isik hale, govdenin etrafinda donen girdap
/// yaylari ve icine akan toz. Gezegenlerin ARKASINA cizilir.
void _paintWells(
    Canvas canvas, double sc, PlanetMergeWorld world, double time) {
  for (final w in world.wells) {
    MergeBody? c;
    for (final b in world.bodies) {
      if (b.id == w.bodyId) {
        c = b;
        break;
      }
    }
    if (c == null) continue;
    final inA = ((w.total - w.remaining) / 0.35).clamp(0.0, 1.0).toDouble();
    final outA = (w.remaining / 0.7).clamp(0.0, 1.0).toDouble();
    final a = min(inA, outA);
    final center = Offset(c.x * sc, c.y * sc);
    final body = c.r * sc;
    final outer = body + w.reach * sc;

    // Isik hale.
    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromARGB((120 * a).round(), 110, 60, 230),
            Color.fromARGB((52 * a).round(), 90, 40, 190),
            const Color(0x00281078),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: outer)),
    );

    // Etki alani halkasi (hafif nabiz).
    canvas.drawCircle(
      center,
      outer * (0.93 + 0.04 * sin(time * 4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.fromARGB((70 * a).round(), 190, 150, 255),
    );

    // Icine akan toz (spiral).
    for (var k = 0; k < 14; k++) {
      final u = (time * 0.7 + k * 0.0714) % 1.0; // 0: dis, 1: govde
      final ang = time * 1.3 + k * 2.399 + u * 2.2;
      final rr = outer - (outer - body * 1.05) * u;
      final pt = center + Offset(cos(ang) * rr, sin(ang) * rr);
      canvas.drawCircle(
        pt,
        1.0 + 1.6 * (1 - u),
        Paint()
          ..color = Color.fromARGB(
              (200 * a * (0.25 + 0.75 * u)).round(), 205, 175, 255),
      );
    }

    // Govdenin etrafinda donen isikli yaylar.
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: body * (1.14 + 0.1 * i)),
        time * (2.4 - 0.5 * i) + i * 2.09,
        1.5 - 0.3 * i,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3.0 - 0.7 * i
          ..color = Color.fromARGB((230 * a).round(), 200, 160, 255)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
  }
}

/// Gezegen gucunun tetiklenme anindaki tek seferlik efekti.
void _paintPowerFx(Canvas canvas, Size size, double sc, _PowerFx fx) {
  final p = (1 - fx.life / fx.maxLife).clamp(0.0, 1.0).toDouble();
  final center = Offset(fx.x * sc, fx.y * sc);
  final reach = fx.radius * sc;
  switch (fx.power) {
    case CosmicPower.ringPulse:
      {
        // Disa yayilan iki altin halka dalgasi.
        for (var i = 0; i < 2; i++) {
          final q = (p * 1.15 - i * 0.18).clamp(0.0, 1.0).toDouble();
          if (q <= 0 || q >= 1) continue;
          final ease = Curves.easeOutCubic.transform(q);
          canvas.drawCircle(
            center,
            reach * (0.25 + 0.75 * ease),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 + 6.0 * (1 - q)
              ..color = Color.fromARGB((235 * (1 - q)).round(), 255, 220, 140)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
        break;
      }
    case CosmicPower.solarFlare:
      {
        final ease = Curves.easeOutCubic.transform(p);
        final fade = 1 - p;
        // Hafif ekran flasi.
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..color = Color.fromARGB((46 * fade * fade).round(), 255, 190, 90),
        );
        // Genisleyen sicak isik.
        final glowR = reach * (0.35 + 0.65 * ease);
        canvas.drawCircle(
          center,
          glowR,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Color.fromARGB((200 * fade).round(), 255, 236, 170),
                Color.fromARGB((120 * fade).round(), 255, 140, 40),
                const Color(0x00FF6F00),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(Rect.fromCircle(center: center, radius: glowR)),
        );
        // Donen isinlar.
        final rays = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.6 * fade + 0.6
          ..color = Color.fromARGB((230 * fade).round(), 255, 205, 110)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        for (var k = 0; k < 14; k++) {
          final ang = k * (pi * 2 / 14) + p * 0.9;
          final r0 = reach * (0.28 + 0.3 * ease);
          final r1 = reach * (0.45 + 0.55 * ease);
          canvas.drawLine(
            center + Offset(cos(ang) * r0, sin(ang) * r0),
            center + Offset(cos(ang) * r1, sin(ang) * r1),
            rays,
          );
        }
        break;
      }
    case CosmicPower.singularity:
      {
        // Merkeze dogru ceken (kuculen) mor halka.
        final ease = Curves.easeInCubic.transform(p);
        canvas.drawCircle(
          center,
          reach * (1 - 0.75 * ease),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 + 5.0 * (1 - p)
            ..color = Color.fromARGB((220 * (1 - p)).round(), 190, 150, 255)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        break;
      }
  }
}

class _MergePainter extends CustomPainter {
  final _PlanetMergeScreenState s;

  _MergePainter(this.s, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final sc = size.width / PlanetMergeConfig.worldW;
    final world = s._world;

    // Kabin.
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0x1AFFFFFF));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.tubeGlassBorder,
    );

    // Tehlike cizgisi (tehlike sayaci ilerledikce kirmiziya doner).
    final ratio =
        (world.dangerTimer / PlanetMergeConfig.dangerSeconds).clamp(0.0, 1.0);
    final lineColor =
        Color.lerp(const Color(0x55FFFFFF), AppColors.danger, ratio.toDouble())!;
    final lineY = world.dangerY * sc;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.8;
    for (double x = 8; x < size.width - 8; x += 14) {
      canvas.drawLine(
        Offset(x, lineY),
        Offset(min(x + 7, size.width - 8), lineY),
        linePaint,
      );
    }

    // Nisan cizgisi + birakilacak gezegen onizlemesi.
    final showAim = !world.gameOver && !s._outOfDrops && !s._challengeWon;
    double aimPx = 0, aimYpx = 0, aimR = 0;
    if (showAim) {
      aimR = PlanetMergeConfig.radiusOf(s._currentTier);
      final ax =
          s._aimX.clamp(aimR, PlanetMergeConfig.worldW - aimR).toDouble();
      aimPx = ax * sc;
      aimYpx = (world.dangerY - aimR - 2) * sc;
      final guide = Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1;
      for (double gy = aimYpx + aimR * sc; gy < size.height - 6; gy += 10) {
        canvas.drawLine(Offset(aimPx, gy), Offset(aimPx, gy + 4), guide);
      }
    }

    // Kutlecekim alanlari (gezegenlerin arkasinda).
    _paintWells(canvas, sc, world, s._fxTime);

    // Gezegenler.
    for (final b in world.bodies) {
      final k = 1 + 0.22 * sin(b.pop * pi);
      final bc = Offset(b.x * sc, b.y * sc);
      // Yuz ifadesi: yeni birlesen sevinir, dusen sasirir, tehlike cizgisine
      // yakin yigilan endiselenir; gozbebekleri hareket yonune bakar.
      var mood = FaceMood.idle;
      if (b.joy > 0) {
        mood = FaceMood.happy;
      } else if (b.surprise > 0) {
        mood = FaceMood.surprised;
      } else if (b.worried) {
        mood = FaceMood.worried;
      }
      _drawPlanet(
        canvas,
        b.tier,
        bc,
        b.r * sc,
        scaleMul: k,
        seed: b.id,
        timeSec: s._fxTime,
        mood: mood,
        lookX: b.vx / 60,
        lookY: b.vy / 60,
      );
      if (b.ice > 0) _drawIce(canvas, bc, b.r * sc * k, b.ice);
      if (b.locked) _drawLock(canvas, bc, b.r * sc, b.lockLeft);
    }

    if (showAim) {
      final ap = Offset(aimPx, aimYpx);
      _drawPlanet(
        canvas,
        s._currentTier,
        ap,
        aimR * sc,
        opacity: s._cooldown > 0 ? 0.35 : 1,
        timeSec: s._fxTime,
      );
      if (s._currentIsIce) {
        if (s._cooldown > 0) {
          canvas.saveLayer(null, Paint()..color = const Color(0x59FFFFFF));
          _drawIce(canvas, ap, aimR * sc, 2);
          canvas.restore();
        } else {
          _drawIce(canvas, ap, aimR * sc, 2);
        }
      }
    }

    // Gezegen gucu efektleri (dalga / patlama).
    for (final fx in s._powerFx) {
      _paintPowerFx(canvas, size, sc, fx);
    }

    // Parcaciklar.
    for (final p in s._particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x * sc, p.y * sc),
        p.size * sc,
        Paint()..color = p.color.withAlpha((255 * a).round()),
      );
    }

    // Skor yazilari (+puan): hafif buyuyup yukari suzulur, sonda solar.
    for (final q in s._pops) {
      final t = (1 - q.life / q.maxLife).clamp(0.0, 1.0);
      final fade = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
      final pop = t < 0.18 ? 0.6 + (t / 0.18) * 0.7 : 1.3 - 0.3 * min(1.0, (t - 0.18) / 0.3);
      final fs = q.fontSize * pop;
      final tp = TextPainter(
        text: TextSpan(
          text: q.text,
          style: TextStyle(
            fontSize: fs,
            fontWeight: FontWeight.w900,
            color: q.color.withAlpha((255 * fade).round()),
            shadows: [
              Shadow(
                color: q.color.withAlpha((170 * fade).round()),
                blurRadius: 10,
              ),
              Shadow(
                color: Color.fromARGB((200 * fade).round(), 0, 0, 0),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = q.x * sc - tp.width / 2;
      dx = dx.clamp(4.0, max(4.0, size.width - tp.width - 4)).toDouble();
      tp.paint(canvas, Offset(dx, q.y * sc - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MergePainter oldDelegate) => true;
}

/// Ust bilgideki skor: puan artinca sayi yukari sayar, kisa bir altin
/// parlama ve "pop" (buyume) animasyonu oynar.
class _AnimatedScore extends StatefulWidget {
  final int score;
  const _AnimatedScore({required this.score});

  @override
  State<_AnimatedScore> createState() => _AnimatedScoreState();
}

class _AnimatedScoreState extends State<_AnimatedScore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  int _from = 0;
  int _to = 0;
  double _gain = 0;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.score;
  }

  int get _shown {
    final t = Curves.easeOutCubic.transform(_c.value);
    return (_from + (_to - _from) * t).round();
  }

  @override
  void didUpdateWidget(covariant _AnimatedScore old) {
    super.didUpdateWidget(old);
    if (widget.score == old.score) return;
    if (widget.score < _to) {
      // Yeni oyun / sifirlama: animasyonsuz.
      _from = _to = widget.score;
      _c.value = 1;
      return;
    }
    _from = _shown;
    _gain = (widget.score - _to).toDouble();
    _to = widget.score;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final running = _c.isAnimating;
        // 0..1..0 arasi vurgu egrisi (hizli yukselir, yavasca soner).
        final glow = running ? sin(pi * pow(_c.value, 0.6)).toDouble() : 0.0;
        final power = (0.12 + min(0.2, _gain / 600)) * glow;
        return Transform.scale(
          scale: 1 + power,
          alignment: Alignment.centerLeft,
          child: Text(
            '$_shown',
            style: TextStyle(
              color: Color.lerp(
                  AppColors.textPrimary, const Color(0xFFFFD54F), glow)!,
              fontWeight: FontWeight.w900,
              fontSize: 26,
              height: 1.0,
              shadows: glow > 0.01
                  ? [
                      Shadow(
                        color: const Color(0xFFFFB300)
                            .withAlpha((200 * glow).round()),
                        blurRadius: 14 * glow,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Kucuk gezegen ikonu (sonraki gezegen, evrim zinciri, game over).
class _PlanetIcon extends StatelessWidget {
  final int tier;
  final double size;
  final bool dim;

  /// Hedef gezegeni vurgulayan ince cerceve (meydan okuma modu).
  final bool highlight;

  const _PlanetIcon({
    required this.tier,
    required this.size,
    this.dim = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _IconPainter(tier, dim)),
    );
    if (!highlight) return icon;
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.warning, width: 1.6),
      ),
      child: icon,
    );
  }
}

class _IconPainter extends CustomPainter {
  final int tier;
  final bool dim;
  _IconPainter(this.tier, this.dim);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 / PlayerProgress.instance.activeDrawScale(tier);
    _drawPlanet(
      canvas,
      tier,
      Offset(size.width / 2, size.height / 2),
      r,
      opacity: dim ? 0.28 : 1,
      faces: false, // 24px'te yuz okunmaz
    );
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) =>
      old.tier != tier || old.dim != dim;
}

// -----------------------------------------------------------------------
// Diyaloglar
// -----------------------------------------------------------------------

/// Oyun sonu diyalogu: sonsuz mod game over'i VE meydan okuma basarisizligi
/// icin ortak. Meydan okumada [goalTier] hedefi gosterilir, rekor satiri
/// ve XP/meteor satiri gizlenir.
class _GameOverDialog extends StatelessWidget {
  final String title;
  final String? message;
  final int? goalTier;
  final int score;
  final int bestScore;
  final int bestTier;
  final int xp;
  final int meteors;

  /// Bu oyundan ONCEKI toplam XP (seviye cubugunun baslangic konumu).
  final int xpBefore;
  final bool canContinue;
  final int rescues;
  final VoidCallback onContinue;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  /// Sadece Sonsuz Mod: oyun sonu "XP x2" reklami (null ise gosterilmez).
  final VoidCallback? onDouble;
  final ValueListenable<int>? doubledN;

  /// Rekor mesaji (yeni rekor / rekora yakin kaldin) ve rekor mu.
  final String? recordNote;
  final bool isRecord;

  const _GameOverDialog({
    required this.title,
    this.recordNote,
    this.isRecord = false,
    this.message,
    this.goalTier,
    required this.score,
    required this.bestScore,
    required this.bestTier,
    required this.xp,
    required this.meteors,
    this.xpBefore = 0,
    required this.canContinue,
    required this.rescues,
    required this.onContinue,
    required this.onRetry,
    required this.onExit,
    this.onDouble,
    this.doubledN,
  });

  @override
  Widget build(BuildContext context) {
    // Meydan okuma basarisizligi kutlama DEGIL: eski sade kart kalir.
    if (goalTier != null) return _classic(context);
    return _celebration(context);
  }

  static double _xpPos(int totalXp) {
    final i = PlayerProgress.levelInfoForXp(max(0, totalXp));
    return (i.level - 1) + i.progress;
  }

  Widget _celebration(BuildContext context) {
    final hasReward = xp > 0 || meteors > 0;
    final fxLevel = isRecord
        ? CelebrationLevel.full
        : (hasReward ? CelebrationLevel.soft : CelebrationLevel.none);
    const gold = Color(0xFFFFD54F);

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: CelebrationFx(level: fxLevel, sound: isRecord),
          ),
          SafeArea(
            // Kaydirma YOK: icerik her ekranda, ne kadar yer varsa ona
            // sigacak sekilde olceklenir (butonlar daima gorunur).
            child: LayoutBuilder(
              builder: (context, box) {
                final w = min(380.0, max(240.0, box.maxWidth - 48));
                // Kisa ekranlarda gorselleri kucult; FittedBox son guvenlik
                // agi olarak kalan farki olcekler.
                final compact = box.maxHeight < 720;
                final tiny = box.maxHeight < 560;
                final planetBox = tiny ? 96.0 : (compact ? 136.0 : 190.0);
                final raysSize = planetBox * 1.2;
                final planetSize = planetBox * 0.55;
                final titleSize = tiny ? 28.0 : (compact ? 32.0 : 38.0);
                final scoreSize = tiny ? 42.0 : (compact ? 48.0 : 58.0);
                final gap = tiny ? 6.0 : (compact ? 10.0 : 14.0);
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: w,
                        child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Baslik
                      PopIn(
                        child: ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFF176), Color(0xFFFFB020)],
                          ).createShader(r),
                          child: Text(
                            isRecord ? t('rc_congrats') : title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: titleSize,
                              shadows: [
                                Shadow(
                                  color: Color(0xFFFF5CC8),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isRecord && recordNote != null) ...[
                        const SizedBox(height: 4),
                        PopIn(
                          delay: const Duration(milliseconds: 1500),
                          child: Text(
                            recordNote!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: gold,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: gap - 4),
                      // En yuksek gezegen + arkasinda isik huzmeleri
                      PopIn(
                        delay: const Duration(milliseconds: 250),
                        child: SizedBox(
                          height: planetBox,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              RewardRays(size: raysSize),
                              _PlanetIcon(tier: bestTier, size: planetSize),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        t('pm_planet_$bestTier'),
                        style: const TextStyle(
                          color: AppColors.accentSoft,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Puan: sayarak artar
                      Text(
                        t('rc_score'),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 2,
                        ),
                      ),
                      AnimatedCount(
                        value: score,
                        delay: const Duration(milliseconds: 500),
                        duration: Duration(
                          milliseconds: (900 + score ~/ 8).clamp(900, 1800),
                        ),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: scoreSize,
                          height: 1.05,
                          shadows: [
                            Shadow(color: Color(0xFFFFB020), blurRadius: 22),
                          ],
                        ),
                        onDone: () {
                          HapticService.instance.medium();
                          if (isRecord) SoundService.instance.starWin();
                        },
                      ),
                      if (!isRecord && recordNote != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          recordNote!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFF9A3C),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        '${t('pm_best')}: $bestScore',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasReward) ...[
                        SizedBox(height: gap),
                        ValueListenableBuilder<int>(
                          valueListenable: doubledN ?? _noDouble,
                          builder: (context, d, _) {
                            final xpShown = d > 0 ? xp * 2 : xp;
                            final mShown = d > 0
                                ? meteors + EconomyConfig.winDoubleXpMeteorBonus
                                : meteors;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (xpShown > 0)
                                  PopIn(
                                    delay: const Duration(milliseconds: 1900),
                                    onShown: SoundService.instance.reward,
                                    child: _RewardChip(
                                      child: AnimatedCount(
                                        value: xpShown,
                                        prefix: '+',
                                        suffix: ' XP',
                                        delay: const Duration(milliseconds: 1900),
                                        duration:
                                            const Duration(milliseconds: 700),
                                        style: _chipStyle,
                                      ),
                                    ),
                                  ),
                                if (xpShown > 0 && mShown > 0)
                                  const SizedBox(width: 10),
                                if (mShown > 0)
                                  PopIn(
                                    delay: const Duration(milliseconds: 2150),
                                    child: _RewardChip(
                                      leading: const MeteorIcon(size: 20),
                                      child: AnimatedCount(
                                        value: mShown,
                                        prefix: '+',
                                        delay: const Duration(milliseconds: 2150),
                                        duration:
                                            const Duration(milliseconds: 700),
                                        style: _chipStyle,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                      if (xp > 0) ...[
                        SizedBox(height: gap),
                        PopIn(
                          delay: const Duration(milliseconds: 2300),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A1650),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: gold, width: 1.6),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t('rc_progress'),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ValueListenableBuilder<int>(
                                  valueListenable: doubledN ?? _noDouble,
                                  builder: (context, d, _) => XpLevelBar(
                                    fromPos: _xpPos(xpBefore),
                                    toPos: _xpPos(xpBefore + (d > 0 ? xp * 2 : xp)),
                                    delay: const Duration(milliseconds: 2500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (onDouble != null && xp > 0)
                        ValueListenableBuilder<int>(
                          valueListenable: doubledN ?? _noDouble,
                          builder: (context, d, _) {
                            if (d > 0) return const SizedBox.shrink();
                            return Padding(
                              padding: EdgeInsets.only(top: gap),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.warning,
                                    foregroundColor: Colors.black87,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: onDouble,
                                  child: Text(
                                    t('pm_doubleButton', {
                                      'm': '${EconomyConfig.winDoubleXpMeteorBonus}',
                                    }),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      SizedBox(height: gap),
                      if (canContinue)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: onContinue,
                            child: Text(
                              rescues > 0
                                  ? '🆘 ${t('pm_continueUseRescue', {'n': '$rescues'})}'
                                  : '▶ ${t('pm_continueButton')}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      if (canContinue) const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3DDC4A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(color: gold, width: 2),
                            ),
                          ),
                          onPressed: onRetry,
                          child: Text(
                            t('pm_retry'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onExit,
                        child: Text(
                          t('pm_exit'),
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _chipStyle = TextStyle(
    color: Color(0xFFFFD54F),
    fontWeight: FontWeight.w900,
    fontSize: 20,
  );

  Widget _classic(BuildContext context) {
    final isChallenge = goalTier != null;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _PlanetIcon(tier: bestTier, size: 72),
            const SizedBox(height: 4),
            Text(
              t('pm_planet_$bestTier'),
              style: const TextStyle(
                color: AppColors.accentSoft,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            if (isChallenge) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎯 ', style: TextStyle(fontSize: 13)),
                  Text(
                    t('pm_planet_${goalTier!}'),
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '$score',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 34,
                height: 1.0,
              ),
            ),
            if (!isChallenge && recordNote != null) ...[
              const SizedBox(height: 6),
              Text(
                recordNote!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isRecord
                      ? const Color(0xFFFFD54F)
                      : const Color(0xFFFF9A3C),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
            if (!isChallenge) ...[
              const SizedBox(height: 2),
              Text(
                '${t('pm_best')}: $bestScore',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (xp > 0 || meteors > 0) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: doubledN ?? _noDouble,
                builder: (context, d, _) {
                  final xpShown = d > 0 ? xp * 2 : xp;
                  final mShown = d > 0
                      ? meteors + EconomyConfig.winDoubleXpMeteorBonus
                      : meteors;
                  return Text(
                    [
                      if (xpShown > 0) '+$xpShown XP',
                      if (mShown > 0) '+$mShown ☄️',
                    ].join('   '),
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  );
                },
              ),
            ],
            if (onDouble != null && xp > 0)
              ValueListenableBuilder<int>(
                valueListenable: doubledN ?? _noDouble,
                builder: (context, d, _) {
                  if (d > 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: onDouble,
                        child: Text(
                          t('pm_doubleButton', {
                            'm': '${EconomyConfig.winDoubleXpMeteorBonus}',
                          }),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 16),
            if (canContinue)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onContinue,
                  child: Text(
                    rescues > 0
                        ? '🆘 ${t('pm_continueUseRescue', {'n': '$rescues'})}'
                        : '▶ ${t('pm_continueButton')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            if (canContinue) const SizedBox(height: 8),
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
                onPressed: onRetry,
                child: Text(
                  isChallenge ? t('mc_retry') : t('pm_retry'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: onExit,
              child: Text(
                t('pm_exit'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Odul satirindaki yuvarlak rozet (+XP / +meteor).
class _RewardChip extends StatelessWidget {
  final Widget? leading;
  final Widget child;
  const _RewardChip({this.leading, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FFD54F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          child,
        ],
      ),
    );
  }
}

final ValueNotifier<int> _noDouble = ValueNotifier<int>(0);

/// Header'daki rekor hedefi (etiket + deger).
class _RecordTarget {
  final String label;
  final int value;
  const _RecordTarget(this.label, this.value);
}

/// Hakki biten guclendirici icin: meteorla al (1) / reklam izle (2).
class _PowerOfferDialog extends StatelessWidget {
  final String name;
  final int price;
  final int meteors;
  const _PowerOfferDialog({
    required this.name,
    required this.price,
    required this.meteors,
  });

  @override
  Widget build(BuildContext context) {
    final canBuy = meteors >= price;
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
            Text(
              t('power_buyTitle', {'name': name}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: canBuy ? () => Navigator.of(context).pop(1) : null,
                child: Text(
                  t('power_buyMeteor', {'n': '$price'}),
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
                onPressed: () => Navigator.of(context).pop(2),
                child: Text(
                  t('power_buyAd'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(0),
              child: Text(
                t('power_cancel'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kuyruklu yildiz meydan okumasi tamamlaninca gosterilen ozet.
/// Bolum Modu: bolum gecildi (yildizlar, oduller, sonraki / tekrar / menu).
class _LevelWinDialog extends StatelessWidget {
  final int level;
  final int stars;
  final int meteors;
  final int xp;
  final bool hasNext;
  const _LevelWinDialog({
    required this.level,
    required this.stars,
    required this.meteors,
    required this.xp,
    required this.hasNext,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD54F);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: gold, width: 1.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🪐 ${t('lv_winTitle', {'n': '$level'})}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: gold,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      i <= stars ? '⭐' : '☆',
                      style: TextStyle(
                        fontSize: i == 2 ? 44 : 36,
                        color: Colors.white38,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (meteors > 0 || xp > 0)
              Text(
                t('lv_rewardLine', {'m': '$meteors', 'x': '$xp'}),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 16),
            if (hasNext)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop('next'),
                  child: Text(t('lv_next')),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop('retry'),
                    child: Text(t('pm_retry')),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop('exit'),
                    child: Text(t('lv_menu')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CometWinDialog extends StatelessWidget {
  final int targetTier;
  final bool rewarded;

  /// Odul verilmeden ONCEKI toplam XP (seviye cubugu baslangici).
  final int xpBefore;
  const _CometWinDialog({
    required this.targetTier,
    required this.rewarded,
    required this.xpBefore,
  });

  static double _xpPos(int totalXp) {
    final i = PlayerProgress.levelInfoForXp(max(0, totalXp));
    return (i.level - 1) + i.progress;
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD54F);
    const chipStyle = TextStyle(
      color: gold,
      fontWeight: FontWeight.w900,
      fontSize: 22,
    );
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CelebrationFx(level: CelebrationLevel.full),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopIn(
                        child: ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFF176), Color(0xFFFFB020)],
                          ).createShader(r),
                          child: Text(
                            '☄️ ${t('mc_winTitle')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 34,
                              shadows: [
                                Shadow(
                                  color: Color(0xFFFF5CC8),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PopIn(
                        delay: const Duration(milliseconds: 250),
                        child: SizedBox(
                          height: 200,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const RewardRays(size: 240),
                              _PlanetIcon(tier: targetTier, size: 110),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        t('pm_planet_$targetTier'),
                        style: const TextStyle(
                          color: AppColors.accentSoft,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (rewarded) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            PopIn(
                              delay: const Duration(milliseconds: 700),
                              onShown: SoundService.instance.reward,
                              child: _RewardChip(
                                leading: const MeteorIcon(size: 24),
                                child: AnimatedCount(
                                  value: EconomyConfig.cometMeteorReward,
                                  prefix: '+',
                                  delay: const Duration(milliseconds: 700),
                                  duration: const Duration(milliseconds: 900),
                                  style: chipStyle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            PopIn(
                              delay: const Duration(milliseconds: 950),
                              child: _RewardChip(
                                child: AnimatedCount(
                                  value: EconomyConfig.cometXpReward,
                                  prefix: '+',
                                  suffix: ' XP',
                                  delay: const Duration(milliseconds: 950),
                                  duration: const Duration(milliseconds: 900),
                                  style: chipStyle,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PopIn(
                          delay: const Duration(milliseconds: 1300),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A1650),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: gold, width: 1.6),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t('rc_progress'),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                XpLevelBar(
                                  fromPos: _xpPos(xpBefore),
                                  toPos: _xpPos(
                                      xpBefore + EconomyConfig.cometXpReward),
                                  delay: const Duration(milliseconds: 1500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else
                        Text(
                          t('mc_cometAlready'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3DDC4A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(color: gold, width: 2),
                            ),
                          ),
                          onPressed: () {
                            SoundService.instance.buttonTap();
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            t('pm_gotIt'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gunluk / kuyruklu yildiz meydan okumasi baslarken: hedef, birakis hakki
/// ve o gunun ozel kurali.
class _ChallengeIntroDialog extends StatelessWidget {
  final MergeChallenge challenge;
  const _ChallengeIntroDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final isDaily = challenge.kind == MergeChallengeKind.daily;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${challenge.kind == MergeChallengeKind.level ? '🪐' : isDaily ? '🌌' : '☄️'} ${challenge.title}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 14),
            _PlanetIcon(tier: challenge.targetTier, size: 76),
            const SizedBox(height: 6),
            Text(
              t('mc_goalLine',
                  {'name': t('pm_planet_${challenge.targetTier}')}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            if (isDaily && challenge.difficultyLevel > 0) ...[
              Text(
                t('streak_diffLine', {'n': '${challenge.difficultyLevel}'}),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              t('mc_dropsLine', {'n': '${challenge.maxDrops}'}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t(challenge.ruleKey),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  SoundService.instance.buttonTap();
                  Navigator.of(context).pop();
                },
                child: Text(
                  t('mc_start'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ilk acilista 3 kuralli kisa ogretici.
class _TutorialDialog extends StatelessWidget {
  const _TutorialDialog();

  Widget _rule(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('pm_tutorialTitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            _rule('👆', t('pm_tutorialRule1')),
            _rule('🪐', t('pm_tutorialRule2')),
            _rule('⚠️', t('pm_tutorialRule3')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  SoundService.instance.buttonTap();
                  Navigator.of(context).pop();
                },
                child: Text(
                  t('pm_gotIt'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
