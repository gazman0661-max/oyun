import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/food_item.dart';
import '../models/game_theme.dart';
import '../models/food_order.dart';
import '../models/game_progress.dart';
import '../models/town.dart';
import '../localization/app_strings.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/game_fx.dart';
import '../services/board_physics.dart';
import 'order_card.dart';
import 'tutorial_coach.dart';
import 'gem_dialogs.dart';
import 'celebration.dart';
import 'ui_kit.dart';

class GameBoard extends StatefulWidget {
  /// Hangi tema kullanilacak (Fast Food, Kafe vs.).
  final GameTheme theme;

  /// Harita ekraninda gosterilen bolum numarasi (orn. 1, 2, 9...).
  final int chapterNumber;

  /// Hedef siparis sayisi - her bolumde zorlukla birlikte artar.
  final int chapterGoal;

  /// PRATIK MODU (Ayarlar > "Nasil Oynanir?"): Bolum 1 rehberi tekrar izlenir.
  /// Odul/coin/gorev/enerji/ilerleme HIC etkilenmez, ilk teslimatta biter.
  final bool practice;

  const GameBoard({
    super.key,
    GameTheme? theme,
    this.chapterNumber = 1,
    this.chapterGoal = 15,
    this.practice = false,
  }) : theme = theme ?? const FastFoodTheme();

  @override
  State<GameBoard> createState() => _GameBoardState();
}

/// Bolum 1 rehberli ogretici adimlari. Sadece DOGRU hareket bir sonraki
/// adima gecirir: drag = ilk atis, merge = iki ayni objenin birlesmesi,
/// deliver = birlesen objenin siparise (otomatik) teslimi.
enum _CoachStep { none, drag, merge, deliver }

/// Tahtadaki tek bir objenin GORUNTU (view) durumu - gercek fizik artik
/// BoardPhysics (Forge2D) icinde yasiyor; bu sinif her frame'de fizikten
/// okunan x/y/vx/vy'yi tutan hafif bir kopya. Cizim, siparis eslestirme,
/// oyun-sonu kontrolu gibi her sey bu sinifi okuyor - boylece geri kalan
/// UI/oyun mantigi neredeyse hic degismedi.
class _Ball {
  final int id;
  int level;
  double x;
  double y;
  double vx;
  double vy;
  double age = 0; // olusturuldugundan bu yana gecen sure (saniye)

  _Ball({
    required this.id,
    required this.level,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
  });
}

double _clampD(double v, double lo, double hi) {
  if (hi < lo) return lo;
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/// Coin kazanildiginda ekranda ustte "+5 coin" yazisi yerine gosterilen
/// altin fiskirma efektinin tek bir parcacigi.
class _CoinParticle {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;

  _CoinParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
  }) : maxLife = life;
}

class _GameBoardState extends State<GameBoard> with SingleTickerProviderStateMixin {
  // --- GERCEK FIZIK MOTORU (Forge2D/Box2D) ---
  // Eskiden burada ~200 satirlik elle yazilmis surtunme/carpisma/sapma-
  // dengeleme sabitleri (_frictionPerSecond, _settleDragK,
  // _strikerSettleDragK, _headOnThreshold, _scatterAngle...) vardi - hepsi
  // gercek bir fizik motoru olmadigi icin "carpisma hissini" elle taklit
  // etmeye calisan hack'lerdi. Artik bunlarin hepsi lib/services/
  // board_physics.dart icindeki BoardPhysics sinifina (Forge2D World,
  // Body, ContactListener) tasindi - carpisma cozumu, surtunme, momentum
  // aktarimi GERCEKTEN motor tarafindan hesaplaniyor.
  final BoardPhysics _physics = BoardPhysics();

  // --- Atis ucus suresi (referans video: Mystery Town) ---
  // Referansta atilan obje tum masayi ~0.3 sn'de SABIT hizla kat ediyor.
  // Atilan topun BoardPhysics'teki damping'i 0 oldugu icin (bkz.
  // spawnBall(thrown:true)) bu artik bir "hack" degil - top GERCEKTEN
  // surtunmesiz, sabit hizla ucuyor. Bu sabit sadece o sabit hizin
  // BUYUKLUGUNU (mesafe/sure) belirliyor.
  static const double _throwFlightSeconds = 0.35;

  // --- Birlesme "suzulmesi" ---
  // Iki obje birlesince yeni obje durgun DOGMUYOR, kisa bir mesafe
  // masanin UZAK ucuna dogru suzuluyor (referans videodaki gibi) - bu
  // baslangic hizi motoru VE bu hizin kendi damping'i (BoardPhysics.
  // settledDamping) tarafindan dogal olarak sonlendiriliyor.
  static const double _mergeGlideSpeed = 0.0; // px/s. Referans video: birlesen yeni obje duran hedefin yerinde belirir ve SUZULMEZ; komsulari Box2D ust uste binmeyi cozerek hafifce iter

  // --- Yanal sapma (yigin dagilmasi) ---
  // Motor artik GERCEK carpisma fizigi uyguladigi icin nesneler kendi
  // kendine dogal sekilde dagiliyor (eskisi gibi elle "tren vagonu"
  // duzeltmesi gerekmiyor) - bu iki sabit sadece BIRLESME aninda yeni
  // objenin hangi aciyla suzulecegini belirlemek icin kaldi.
  static const double _collisionScatterMin = 0.45; // rad (~26 derece) TABAN
  static const double _collisionScatterMax = 1.2; // rad (~69 derece) tavan

  // --- Yigin dengeleme ---
  // Birlesme suzulmesinin yonu (sol/sag) saf sansa birakilmiyor - temas
  // noktasinin etrafinda halihazirda az dolu olan tarafa dogru %78
  // ihtimalle egilim gosteriyor, boylece yigin kendini yatayda dengeler.
  static const double _scatterBalanceRadius = 130.0; // bu yaricap icindeki objeler sayilir
  static const double _scatterBalancePreference = 0.78; // az dolu tarafi secme ihtimali

  /// atX etrafinda sol/sag obje sayisina bakip az dolu tarafi -1 (sol) /
  /// +1 (sag) olarak, agirlikli rastgeleyle dondurur.
  int _balancedSide(double atX) {
    int left = 0, right = 0;
    for (final o in _balls) {
      final d = o.x - atX;
      if (d.abs() > _scatterBalanceRadius) continue;
      if (d < 0) {
        left++;
      } else if (d > 0) {
        right++;
      }
    }
    final preferLeft = left < right;
    final useBias = _random.nextDouble() < _scatterBalancePreference;
    final wantLeft = useBias ? preferLeft : _random.nextBool();
    return wantLeft ? -1 : 1;
  }

  /// Su an masada DURGUN (vx=vy=0) duran objelerden atis noktasina EN YAKIN
  /// olaninin y'si - yani "yigin" (rafta biriken objeler) su an atis
  /// noktasina ne kadar yaklasmis. Hicbir durgun obje yoksa masa henuz
  /// bomboş demektir, o zaman uzak duvari (_tableTopY) donduruyoruz.
  double get _stackFrontY {
    double maxY = _tableTopY;
    for (final b in _balls) {
      if (b.vx == 0 && b.vy == 0 && b.y > maxY) maxY = b.y;
    }
    return maxY;
  }

  /// 0.0 (masa bomboş) ile 1.0 (yigin neredeyse atis noktasina/tehlike
  /// cizgisine dayanmis) arasinda normalize edilmis "masa ne kadar dolu"
  /// degeri. Atislar arasi bekleme suresini (_throwCooldown) ve atis
  /// hizini videodaki gibi "oyun ilerledikce hizlanan" bir his vermek
  /// icin kademeli olarak etkiler.
  double get _boardFullness {
    final total = _padY - _tableTopY;
    if (total <= 0) return 0;
    return _clampD((_stackFrontY - _tableTopY) / total, 0.0, 1.0);
  }

  static const double _dangerLineFraction = 0.82; // masa yuzeyi ICINDE, ust siniirdan itibaren % kac -> oyun sonu siniri
  static const double _minDeliveryAge = 0.7; // saniye - obje en az bu kadar ekranda gorunmeden teslim edilmez

  /// Atislar arasi GERCEK bekleme suresi. TABAN deger dukkandan alinan
  /// "Hizli Atis" yukseltmesinden gelir; masa doldukca (_boardFullness)
  /// bunun ustune kucuk bir ek indirim daha uygulanir.
  Duration get _throwCooldown {
    final base = GameProgress.instance.throwCooldown;
    final reduceFactor = 1 - (_boardFullness * 0.4); // masa doluysa %40'a kadar daha kisa
    final ms = (base.inMilliseconds * reduceFactor).clamp(70, base.inMilliseconds).toInt();
    return Duration(milliseconds: ms);
  }

  // --- Masa yuzeyi siniri (trapezoid) ---
  // Arkaplan gorseli (table_background.jpg) artik SADECE duz bir ahsap
  // doku degil - gercek bir restoran sahnesi icinde perspektifle cizilmis
  // bir masa. Gorsel artik TAM EKRAN gosteriliyor (kirpilip kucuk bir
  // alana sikistirilmiyor), bu da BoxFit.cover'in ekranin en-boy oranina
  // gore gorselin bazen SOLUNDAN/SAGINDAN bazen de UST/ALTINDAN kirpma
  // yapabilecegi anlamina gelir. Bu yuzden masa sinirini artik sabit
  // fraksiyonlarla degil, gorselin GERCEK piksel boyutlari + BoxFit.cover
  // ile ayni matematiksel donusumu kullanarak hesapliyoruz - boylece
  // hangi ekran orani olursa olsun masa siniri gorseldeki gercek masa
  // kenarlariyla HER ZAMAN birebir eslesir.
  double get _imgW => widget.theme.imageWidth;
  double get _imgH => widget.theme.imageHeight;
  // Gorsel uzerinde elle kalibre edilmis masa yuzeyi kosesi (px):
  static const double _tableTopYImg = 400;
  static const double _tableBottomYImg = 1110;
  // Sol/sag kenarlar TEMAYA ozel (her dunyanin masasi farkli) - bkz. game_theme.dart
  double get _topLeftXImg => widget.theme.tableTopLeftX;
  double get _topRightXImg => widget.theme.tableTopRightX;
  double get _bottomLeftXImg => widget.theme.tableBottomLeftX;
  double get _bottomRightXImg => widget.theme.tableBottomRightX;

  /// BoxFit.cover'in uyguladigi olcegi hesaplar: gorsel, kutuyu (ekrani)
  /// tamamen kaplayacak sekilde olceklenir - iki oranin BUYUK olani
  /// kullanilir (kucuk olan boyut disari tasar ve kirpilir).
  double get _coverScale => max(_boardWidth / _imgW, _boardHeight / _imgH);

  /// Yatayda ne kadar kirpildigini (gorselin olceklenmis genisliginin
  /// kutudan ne kadar tastigini) verir - 0 ise yatayda kirpma yok demektir.
  double get _coverOffsetX => (_imgW * _coverScale - _boardWidth) / 2;

  /// Dikeyde ayni sekilde.
  double get _coverOffsetY => (_imgH * _coverScale - _boardHeight) / 2;

  double get _tableTopY => _tableTopYImg * _coverScale - _coverOffsetY;
  double get _tableBottomY => _tableBottomYImg * _coverScale - _coverOffsetY;

  /// Verilen y (ekran koordinati) icin masanin sol kenarinin x konumunu,
  /// uzak/yakin kenarlar arasinda dogrusal interpolasyonla hesaplar.
  /// Once hangi "yukseklik orani"nda oldugumuzu (t) buluyoruz, sonra
  /// gorseldeki ust/alt sol-kenar piksellerini ekrana donusturup
  /// aralarinda interpolasyon yapiyoruz.
  double _tableLeftAt(double y) {
    final topY = _tableTopY;
    final botY = _tableBottomY;
    final t = ((y - topY) / (botY - topY)).clamp(0.0, 1.0);
    final scale = _coverScale;
    final offsetX = _coverOffsetX;
    final topLeftScreen = _topLeftXImg * scale - offsetX;
    final botLeftScreen = _bottomLeftXImg * scale - offsetX;
    return topLeftScreen + (botLeftScreen - topLeftScreen) * t;
  }

  /// Ayni sekilde masanin sag kenari.
  double _tableRightAt(double y) {
    final topY = _tableTopY;
    final botY = _tableBottomY;
    final t = ((y - topY) / (botY - topY)).clamp(0.0, 1.0);
    final scale = _coverScale;
    final offsetX = _coverOffsetX;
    final topRightScreen = _topRightXImg * scale - offsetX;
    final botRightScreen = _bottomRightXImg * scale - offsetX;
    return topRightScreen + (botRightScreen - topRightScreen) * t;
  }

  final List<_Ball> _balls = [];
  final Random _random = Random();
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _boardWidth = 360;
  double _boardHeight = 560;

  int _nextId = 0;
  int _pendingLevel = 1; // atis noktasinda bekleyen, henuz firlatilmamis obje
  int _nextLevel = 1; // BIR SONRAKI obje - kucuk bir onizleme rozetinde gosterilir
  double _aimX = 180;
  bool _canThrow = true;

  // ── OGRETICI (v89) ──────────────────────────────────────────────────
  // Bolum 1 rehberli 3 adim (sadece ilk kez / pratik modunda), ilk bolumde
  // kaybetme yok, Bolum 2-3 ipuclari, ilk "Masa Doldu" karti. Hepsi tek
  // seferlik (GameProgress.tutSeen). Olcum: AnalyticsService huni olaylari.
  bool get _practice => widget.practice;
  late final bool _guidedRun; // bu giriste 3 adimli rehber calisiyor mu
  late final bool _tutorialRun; // ilk kez Bolum 1 (huni olcumu icin)
  _CoachStep _coach = _CoachStep.none;
  bool get _guided => _coach != _CoachStep.none;
  bool _touching = false; // parmak ekranda: el animasyonu gizlenir
  String? _coachNote; // kisa gecici balon (Harika!, kombo ipucu)
  bool _dangerHintOn = false; // tehlike cizgisi ipucu aktif

  /// Ilk bolumde (ogretici bitene kadar) ve pratikte KAYBETME YOK: masa
  /// dolacak olursa alt bolge sessizce temizlenir.
  bool get _noLose => _practice || (widget.chapterNumber == 1 && !GameProgress.instance.tutSeen('ch1'));
  bool _gameOver = false;
  int _coins = GameProgress.instance.coins;
  // Bu denemede (bolumde) kazanilan coin - bitis ekraninda gosterilir ve x2 bonusun temelidir.
  int _chapterCoins = 0;
  // Reklamla x2 coin: bonus miktari, reklam hazir mi, alindi mi, reklam suruyor mu.
  int _doubleBonus = 0;
  bool _doubleAdReady = false;
  bool _doubleClaimed = false;
  bool _doubleBusy = false;
  String? _toast;

  // --- Bolum 2: Siparis sistemi ---
  int get _orderSlotCount => GameProgress.instance.orderSlotCount; // dukkandan alinan "Ekstra Sipariş Slotu" yukseltmesiyle 3'ten 5'e cikabilir

  // null = slot su an bos, yeni siparis gelmek uzere bekliyor. Bunu
  // BILEREK anlik doldurmuyoruz: eskiden bir siparis teslim edilir
  // edilmez yerine HEMEN yeni siparis geliyordu ve bu yeni siparis
  // bazen tahtada zaten duran, o ana kadar hicbir siparisle ilgisi
  // olmayan baska bir objeyle rastgele eslesip onu da AYNI KAREDE
  // supurup goturuyordu - zincirleme "patlama" hissi buradan geliyordu.
  final List<FoodOrder?> _orders = [];
  int _orderIdCounter = 0;
  static const Duration _orderRefillDelay = Duration(milliseconds: 380);

  // --- Bolum hedefi: X siparis tamamlayinca "Bolum 1 Tamamlandi" ---
  static const int _chapterNumber = 1; // sol ustteki "Level" ve ortadaki "Bolum" rozetinde kullanilan numara
  int get _chapterGoal => widget.chapterGoal;
  int _ordersCompleted = 0;
  bool _chapterComplete = false;

  // --- Enerji: reklamla "tekrar dene" hakki bu deneme (attempt) icin
  // sadece BIR KEZ kullanilabilir. Yeni bir bolume girildiginde (yeni
  // GameBoard ornegi) ya da normal "tekrar oyna" ile taze bir denemeye
  // baslandiginda false'a doner. ---
  bool _usedAdRetryThisAttempt = false;

  // --- Guclendiriciler (mucevher ekonomisi) ---
  static const int _aimGuideShots = 5; // Nisan Rehberi kac atis boyunca acik kalir
  static const int _maxContinuesPerAttempt = 2; // "Devam Et" bir denemede en cok 2 kez
  static const int _jokerMaxLevel = 5; // Joker ile secilebilecek en yuksek seviye
  int _aimGuideShotsLeft = 0;
  bool _pendingIsJoker = false; // joker top albumde yeni kart ACMAZ (album emek ister)
  int _continuesUsed = 0;
  bool _adContinueUsed = false; // "Reklam izle, devam et" bir denemede en cok 1 kez
  bool _lossEnergyCharged = false; // kayipta enerji bir denemede en cok 1 kez harcansin
  int _gemsFromClear = 0; // bolum ilk kez gecilince kazanilan mucevher (bitis ekraninda gosterilir)

  // --- Bolum sonu "sov": yildiz + XP + seviye atlama ---
  // Yildiz kurali (masa ne kadar temiz kaldi): turdaki EN yuksek doluluk
  // (_boardFullness, 0..1) esiklerin altindaysa 3 / 2 yildiz, degilse 1.
  // "Devam Et" kullanildiysa en fazla 2 yildiz. Esikleri buradan ayarla.
  // Esikler TEHLIKE CIZGISINE gore oranlanir: 3 yildiz icin yigin hic
  // tehlike cizgisinin %50'sine cikmamali, 2 yildiz icin %80'ine.
  static const double _threeStarDangerRatio = 0.50;
  static const double _twoStarDangerRatio = 0.80;
  double get _dangerFullness {
    final total = _padY - _tableTopY;
    if (total <= 0) return 1;
    final dangerY = _tableTopY + (_tableBottomY - _tableTopY) * _dangerLineFraction;
    return _clampD((dangerY - _tableTopY) / total, 0.05, 1.0);
  }
  double _peakFullness = 0;
  int _starsEarned = 0;
  // KOMBO: birbirine yakin zamanda gelen merge'ler zincir sayilir; 3. ve
  // sonraki zincir merge'lerde kucuk coin bonusu + bildirim verilir.
  static const int _comboWindowMs = 2500;
  static const int _comboMinForBonus = 3;
  static const int _comboBonusPerStep = 2; // coin
  int _comboCount = 0;
  int _lastMergeMs = 0;

  void _registerMergeCombo(double x, double y) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastMergeMs <= _comboWindowMs) {
      _comboCount++;
    } else {
      _comboCount = 1;
    }
    _lastMergeMs = nowMs;
    if (_comboCount == _comboMinForBonus && !_practice) GameProgress.instance.reportCombo();
    if (_comboCount >= _comboMinForBonus) {
      final bonus = (_comboCount - _comboMinForBonus + 1) * _comboBonusPerStep;
      _addCoins(bonus);
      _spawnCoinBurst(x, y, count: 6 + min(_comboCount, 10));
      _showToast('🔥 x$_comboCount  +$bonus');
    }
  }
  int _xpGained = 0;
  double _barFrom = 0;
  double _barTo = 0;
  int _levelAfter = 1;
  List<LevelUpReward> _levelUps = const [];
  int _completeRunId = 0; // her bolum bitisinde artar -> kutlama animasyonu bastan calar
  bool _awaitingLevelUp = false; // seviye atlama kutlamasi bitmeden butonlar gizli

  int _computeStars() {
    // Bolum 1'in ilk gecisi: kaybetme yoktu (masa temizlenebilirdi), bu yuzden
    // ilk galibiyet her zaman 3 yildiz - ogretici cezalandirmasin.
    if (_tutorialRun) return 3;
    int stars;
    if (_peakFullness <= _dangerFullness * _threeStarDangerRatio) {
      stars = 3;
    } else if (_peakFullness <= _dangerFullness * _twoStarDangerRatio) {
      stars = 2;
    } else {
      stars = 1;
    }
    if (_continuesUsed > 0 && stars > 2) stars = 2;
    return stars;
  }

  // --- Ses/titresim: bu turda ulasilan EN yuksek seviye. Bir merge bunu
  // asarsa "yeni seviye" efekti (ekstra parlak ses + guclu titresim)
  // calar. 2 ile baslar cunku atislarda sadece Lv1/Lv2 gelir. ---
  int _bestTierThisRound = 2;

  // --- Altin parcacik (coin burst) efekti ---
  final List<_CoinParticle> _particles = [];

  // --- Gercek illustrasyon gorselleri (kullanicinin urettigi asset'ler) ---
  // CustomPainter dogrudan Image.asset widget'i kullanamaz, bu yuzden
  // ham ui.Image olarak onceden yukleniyor. Yuklenene kadar _BallsPainter
  // eski prosedurel (renkli daire + emoji) cizime otomatik geri duser.
  final Map<int, ui.Image> _tierImages = {};
  ui.Image? _coinImage;

  double get _padY => _tableBottomY - 34; // atis noktasinin dikey konumu - masanin on kenarina yakin ama uzerinde

  /// Tur bitti mi (kaybettin ya da bolumu tamamladin)? Her iki durumda da
  /// fizik durur ve nisan/atis girdileri devre disi kalir.
  bool get _roundOver => _gameOver || _chapterComplete;

  @override
  void initState() {
    super.initState();
    final gp = GameProgress.instance;
    _guidedRun = _practice || (widget.chapterNumber == 1 && !gp.tutSeen('ch1_steps'));
    _tutorialRun = !_practice && widget.chapterNumber == 1 && !gp.tutSeen('ch1');
    if (_guidedRun) {
      _coach = _CoachStep.drag;
      AnalyticsService.instance.log(_practice ? 'tut_replay_start' : 'tut_start');
    }
    _pendingLevel = _rollLevel();
    _nextLevel = _rollLevel();
    _aimX = _boardWidth / 2;
    for (int i = 0; i < _orderSlotCount; i++) {
      _orders.add(_firstOrder(i));
    }
    // Tehlike cizgisi ipucu: ilk kez Bolum 2+ acilinca bir kez.
    if (!_practice && widget.chapterNumber >= 2 && !gp.tutSeen('danger')) {
      gp.markTutSeen('danger');
      AnalyticsService.instance.log('tut_danger_hint');
      _dangerHintOn = true;
      Future<void>.delayed(const Duration(seconds: 7), () {
        if (mounted) setState(() => _dangerHintOn = false);
      });
    }
    _rebuildBounds(); // varsayilan _boardWidth/_boardHeight ile - build() gercek boyutla tekrar cagirir
    _ticker = createTicker(_onTick)..start();
    _loadTierImages();
    final kind = ChapterConfig.kindFor(widget.chapterNumber);
    if (kind != ChapterKind.normal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _showToast(AppStrings.instance.t(kind == ChapterKind.boss ? 'kind_boss_toast' : 'kind_easy_toast')));
      });
    }
  }

  /// Masa sinirlarinin (Forge2D static duvarlari) ekran boyutuyla eslesmesini
  /// saglar. LayoutBuilder gercek boyutu verdiginde (build icinde) ve
  /// initState'te varsayilan boyutla bir kez cagrilir; ayni boyutta tekrar
  /// cagrilirsa BoardPhysics.ensureBounds ucuz bir no-op yapar.
  void _rebuildBounds() {
    _physics.ensureBounds(
      topY: _tableTopY,
      bottomY: _tableBottomY,
      leftAt: _tableLeftAt,
      rightAt: _tableRightAt,
      boardWidth: _boardWidth,
      boardHeight: _boardHeight,
    );
  }

  // Decode edilmis gorseller BOLUMLER ARASI paylasilir (statik onbellek):
  // eskiden her bolumde 1254x1254'e kadar tam cozunurlukte yeniden decode
  // ediliyor ve hic dispose edilmiyordu -> bellek sisip oyun donuyordu.
  static final Map<String, ui.Image> _imageCache = {};

  Future<ui.Image> _loadUiImage(String assetPath) async {
    final cached = _imageCache[assetPath];
    if (cached != null) return cached;
    final data = await rootBundle.load(assetPath);
    // Toplar ekranda en fazla ~120 px; 320 px genis decode fazlasiyla yeterli.
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 320);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return _imageCache[assetPath] = frame.image;
  }

  Future<void> _loadTierImages() async {
    for (int lvl = 1; lvl <= widget.theme.maxLevel; lvl++) {
      final tier = widget.theme.byLevel(lvl);
      final image = await _loadUiImage(tier.imagePath);
      if (!mounted) return;
      setState(() {
        _tierImages[lvl] = image;
      });
    }
    final coin = await _loadUiImage('assets/images/coin_icon.webp');
    if (!mounted) return;
    setState(() {
      _coinImage = coin;
    });
  }

  @override
  void dispose() {
    // Huni olcumu: Bolum 1'i bitirmeden cikanlar hangi adimda birakti?
    if (_tutorialRun && !_chapterComplete) {
      AnalyticsService.instance.log('tut_ch1_quit', {'step': _coach.name});
    }
    _physics.clear();
    _ticker.dispose();
    super.dispose();
  }

  /// Rastgele gelen obje: cogunlukla Seviye 1, ara sira Seviye 2.
  /// Onceden bir "Siradaki" gostergesi YOK - obje atis noktasinda
  /// belirdigi an ne oldugu ortaya cikar.
  int _rollLevel() {
    // Rehberli adimlarda (atis, birlestirme) hep Seviye 1: ayni objeyi bulmak kolay olsun.
    if (_coach == _CoachStep.drag || _coach == _CoachStep.merge) return 1;
    return _random.nextDouble() < (1 - GameProgress.instance.level2Chance) ? 1 : 2;
  }

  /// Rehberli turda ilk siparisler SABIT: Seviye 2 (ilk birlesmenin sonucu)
  /// ve Seviye 3. Boylece ilk atis kendi kendine teslim olmaz, birlesen obje
  /// mutlaka parlayan bir siparisle eslesir. Rehber yoksa normal uretim.
  FoodOrder _firstOrder(int slot) {
    if (_coach == _CoachStep.none) return _generateOrder();
    const levels = [2, 2, 3, 2, 3];
    final level = levels[slot % levels.length];
    return FoodOrder(
      id: _orderIdCounter++,
      level: level,
      reward: _scaleCoins(widget.theme.byLevel(level).coinReward),
    );
  }

  /// Yeni bir musteri siparisi uretir. Dusuk seviyeler daha sik istenir
  /// (oyuncunun kisa surede karsilayabilecegi siparişler cogunlukta),
  /// yuksek seviyeler nadiren cikar ve daha buyuk odul verir.
  ///
  /// ZORLUK EGRISI: agirliklar sabit degil - widget.chapterNumber'a gore
  /// [ChapterConfig.difficultyT] ile 0..1 arasinda kayan bir katsayi,
  /// dusuk seviyelerin agirligini azaltip yuksek seviyelerinkini artirir.
  /// Boylece ayni "15 siparis" hedefi bile ilerideki bolumlerde daha
  /// zor siparislerle doluyor - sadece hedef sayisi degil, siparisin
  /// kendisi de zorlasiyor. ~40. bolumde platoya oturur, sonsuza kadar
  /// oynanamaz hale gelmez.
  FoodOrder _generateOrder() {
    const levels = [1, 2, 3, 4, 5, 6];
    final kind = ChapterConfig.kindFor(widget.chapterNumber);
    final t = ChapterConfig.difficultyT(widget.chapterNumber);
    final List<double> weights = kind == ChapterKind.boss
        ? [0, 0, 8, 35, 35, 22] // BOSS: sadece yuksek seviyeler
        : [
            30 - 20 * t, // Lv1: 30 -> 10
            25 - 10 * t, // Lv2: 25 -> 15
            20 + 2 * t, // Lv3: 20 -> 22
            13 + 10 * t, // Lv4: 13 -> 23
            8 + 14 * t, // Lv5: 8  -> 22
            4 + 16 * t, // Lv6: 4  -> 20
          ];
    final total = weights.reduce((a, b) => a + b);
    double roll = _random.nextDouble() * total;
    int chosenLevel = levels.first;
    for (int i = 0; i < levels.length; i++) {
      if (roll < weights[i]) {
        chosenLevel = levels[i];
        break;
      }
      roll -= weights[i];
    }
    // KURAL SIPARISI: 6. bolumden itibaren "Lv N+ herhangi biri" (bosstan sonra
    // daha sik). Boss'ta yok. Oyuncuya strateji secimi verir.
    if (kind != ChapterKind.boss && widget.chapterNumber >= 6) {
      final ruleChance = 0.12 + 0.18 * t;
      if (_random.nextDouble() < ruleChance) {
        final minLevel = 3 + _random.nextInt(3); // 3, 4 veya 5
        final base = widget.theme.byLevel(minLevel).coinReward;
        return FoodOrder(
          id: _orderIdCounter++,
          level: minLevel,
          reward: _scaleCoins((base * (100 + FoodOrder.bonusPercent) / 100).round()),
          anyAbove: true,
        );
      }
    }
    var reward = widget.theme.byLevel(chosenLevel).coinReward;
    if (kind == ChapterKind.boss) reward *= 2;
    reward = _scaleCoins(reward);
    return FoodOrder(id: _orderIdCounter++, level: chosenLevel, reward: reward);
  }

  /// Bir siparis slotu bosaldiktan _orderRefillDelay kadar sonra oraya
  /// yeni bir siparis atar. Bu gecikme, zincirleme "anlik teslimat"
  /// hissini (bkz. yukaridaki yorum) engelliyor.
  void _scheduleOrderRefill(int slotIndex) {
    Future.delayed(_orderRefillDelay, () {
      if (!mounted || slotIndex >= _orders.length) return;
      setState(() {
        _orders[slotIndex] = _generateOrder();
      });
    });
  }

  void _onTick(Duration elapsed) {
    if (_roundOver) return;
    double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    // Uygulama kisa sureligine arka plana atildiysa vb. asiri buyuk bir
    // dt gelebilir - bunu makul bir ust sinira kirp.
    if (dt > 0.05) dt = 0.05;

    // ONEMLI: Box2D SABIT kucuk adimlarla calistirilmali (bu onerilen
    // kullanim sekli) - degisken/buyuk dt cozucuyu kararsizlastirabilir.
    // Ucusta hizli top varsa (bullet=true zaten ayarli, bkz. BoardPhysics)
    // yine de kucuk adimlarla daha pürüzsüz gorunur.
    final hasFlyer = _balls.any((b) => b.vx * b.vx + b.vy * b.vy > 250 * 250);
    final step = hasFlyer ? 1 / 240.0 : 1 / 120.0;
    final steps = (dt / step).ceil().clamp(1, hasFlyer ? 12 : 4);
    final subDt = dt / steps;
    for (int i = 0; i < steps; i++) {
      _simulate(subDt);
      _updateParticles(subDt);
    }
    // Yildiz hesabi icin turdaki en yuksek masa dolulugu
    final fullNow = _boardFullness;
    if (fullNow > _peakFullness) _peakFullness = fullNow;
    if (mounted) setState(() {});
  }

  void _simulate(double dt) {
    // Tur bittiyse (kayip/bolum tamam) kalan alt-adimlarda hicbir sey
    // yapma - aksi halde ayni karede oyun sonu/bolum sonu (ses, titresim,
    // enerji harcama) birden fazla kez tetiklenebiliyordu.
    if (_roundOver) return;

    // 1) Gercek fizik motorunu ilerlet (duvar/top-top carpismalari,
    //    surtunme, momentum aktarimi artik BURADA, Forge2D tarafindan
    //    cozuluyor).
    _physics.step(dt);

    // 2) Fizikten donen durumu _balls (view-model) listesine yansit.
    final snaps = <int, BallSnapshot>{};
    for (final s in _physics.snapshots()) {
      snaps[s.id] = s;
    }
    for (final b in _balls) {
      final s = snaps[b.id];
      if (s == null) continue; // (teorik olarak olmamali, guvenlik)
      b.x = s.x;
      b.y = s.y;
      b.vx = s.vx;
      b.vy = s.vy;
      b.age += dt;
    }

    // 3) Duvar/carpisma sesleri - BoardPhysics bu adimda olan temaslari
    //    bir kuyrukta biriktirdi, burada tuketiyoruz.
    double wallSpeed = 0;
    for (final impact in _physics.consumeImpacts()) {
      if (impact.idB == null) {
        if (impact.speed > wallSpeed) wallSpeed = impact.speed;
      } else {
        GameFx.instance.impact(levelA: impact.levelA!, levelB: impact.levelB!, speed: impact.speed);
      }
    }
    if (wallSpeed > 0) GameFx.instance.wallHit(wallSpeed);

    // 4) Birlesmeleri uygula - ayni seviyeden iki topun temas ettigini
    //    BoardPhysics'in ContactListener'i (preSolve'da fiziksel sekmeyi
    //    devre disi birakarak) tespit etti, burada oyun tarafi (coin,
    //    ses, yeni obje dogurma) isleniyor.
    final merges = _physics.consumeMerges();
    for (int mi = 0; mi < merges.length; mi++) {
      final ev = merges[mi];
      final aIndex = _balls.indexWhere((b) => b.id == ev.idA);
      if (aIndex == -1) continue; // ayni karede baska bir merge tarafindan zaten kaldirilmis olabilir
      final level = _balls[aIndex].level;
      _balls.removeWhere((b) => b.id == ev.idA || b.id == ev.idB);
      _physics.removeBall(ev.idA);
      _physics.removeBall(ev.idB);

      if (level >= widget.theme.maxLevel) {
        final bonus = _scaleCoins(widget.theme.byLevel(level).coinReward);
        _addCoins(bonus);
        if (!_practice) GameProgress.instance.reportMerge();
        _spawnCoinBurst(ev.midX, ev.midY, count: 14); // max seviye - daha buyuk fiskirma
        GameFx.instance.mergeMax(delayMs: mi * 70);
        continue;
      }

      final newLevel = level + 1;
      final reward = _scaleCoins(widget.theme.byLevel(newLevel).coinReward);
      if (!_practice) _discoverInAlbum(newLevel);
      _addCoins(reward);
      if (!_practice) GameProgress.instance.reportMerge();
      _registerMergeCombo(ev.midX, ev.midY);
      _maybeComboHint();
      // Rehber Adim 2 -> 3: ilk dogru birlesme gerceklesti.
      if (_coach == _CoachStep.merge && newLevel == 2) {
        _coach = _CoachStep.deliver;
        _coachStepDone('tut_step2_merge');
      }
      // Suzulme yonu tamamen dikey olmasin - az dolu tarafa egilimli bir
      // aciyla saparak masaya yayilsin (bkz. _balancedSide).
      final glideMag = _collisionScatterMin +
          _random.nextDouble() * (_collisionScatterMax - _collisionScatterMin);
      final glideSide = _balancedSide(ev.midX);
      final glideAngle = glideSide < 0 ? -glideMag : glideMag;
      final vx = _mergeGlideSpeed * sin(glideAngle);
      final vy = -_mergeGlideSpeed * cos(glideAngle); // uzak duvara dogru suzul
      final merged = _Ball(id: _nextId++, level: newLevel, x: ev.midX, y: ev.midY, vx: vx, vy: vy);
      _balls.add(merged);
      _physics.spawnBall(
        id: merged.id,
        level: newLevel,
        xPx: ev.midX,
        yPx: ev.midY,
        vxPx: vx,
        vyPx: vy,
        radiusPx: widget.theme.byLevel(newLevel).radius,
        thrown: false, // birlesme suzulmesi - dogar dogmaz "oturma" damping'iyle baslar
      );
      _spawnCoinBurst(ev.midX, ev.midY);

      // Ses + titresim. Ayni karede birden fazla merge olursa (zincirleme)
      // 70 ms arayla kademelendirilir -> kendiliginden bir "arpej" olur.
      final isNewBest = newLevel > _bestTierThisRound && newLevel >= 4;
      if (newLevel > _bestTierThisRound) _bestTierThisRound = newLevel;
      GameFx.instance.merge(newLevel, isNewBest: isNewBest, delayMs: mi * 70);
    }

    // 5) Otomatik siparis teslimati: durgun bir obje ACIK (null olmayan)
    //    bir siparisle ayni seviyedeyse DOKUNMAYA GEREK KALMADAN otomatik
    //    teslim edilir. (Ucan/hareket halindeki objeler beklenir - aniden
    //    havada kaybolmasin, once yerine otursun. Ayrica YENI birlesen
    //    bir obje olusur olusmaz vx=vy=0 oldugu icin, yas kontrolu
    //    olmadan AYNI KAREDE gorunmeden patliyordu - simdi en az
    //    _minDeliveryAge kadar ekranda gorunmesi sart kosuluyor.)
    if (!_chapterComplete) {
      for (int i = _balls.length - 1; i >= 0; i--) {
        final ball = _balls[i];
        if (ball.vx != 0 || ball.vy != 0) continue; // henuz durmadi, bekle
        if (ball.age < _minDeliveryAge) continue; // henuz yeterince gorunmedi, bekle

        // Once birebir eslesen siparis, yoksa kural siparisi (Lv N+).
        var orderIndex = _orders.indexWhere((o) => o != null && !o.anyAbove && o.level == ball.level);
        if (orderIndex == -1) {
          orderIndex = _orders.indexWhere((o) => o != null && o.anyAbove && o.accepts(ball.level));
        }
        if (orderIndex == -1) continue;

        final order = _orders[orderIndex]!;
        final bx = ball.x;
        final by = ball.y;
        _balls.removeAt(i);
        _physics.removeBall(ball.id);
        // Kural siparisinde odul, teslim edilen objenin seviyesine gore.
        final payout = order.anyAbove
            ? _scaleCoins((widget.theme.byLevel(ball.level).coinReward * (100 + FoodOrder.bonusPercent) / 100).round())
            : order.reward;
        _addCoins(payout);
        if (!_practice) GameProgress.instance.reportOrderDelivered();
        _orders[orderIndex] = null; // slot bosaldi - yeni siparis GECIKMELI gelecek
        _scheduleOrderRefill(orderIndex);
        _ordersCompleted++;
        _spawnCoinBurst(bx, by);
        // Rehber Adim 3: birlesen obje siparise teslim edildi (coin patlamasi yukarida).
        if (_coach == _CoachStep.deliver) {
          _coach = _CoachStep.none;
          if (!_practice) GameProgress.instance.markTutSeen('ch1_steps');
          _coachStepDone('tut_step3_deliver', cheer: false);
          _showCoachNote(AppStrings.instance.t('tut_nice'));
          if (_practice) {
            // Pratik: tek teslimatla biter, ilerleme/odul yok.
            GameFx.instance.orderDelivered();
            AnalyticsService.instance.log('tut_replay_done');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _finishPractice();
            });
            break;
          }
        }
        if (_ordersCompleted < _chapterGoal) {
          GameFx.instance.orderDelivered();
        }
        if (_ordersCompleted >= _chapterGoal) {
          _chapterComplete = true;
          GameFx.instance.chapterComplete(); // fanfar zaten "ka-ching" iceriyor
          final gemsBefore = GameProgress.instance.gems;
          GameProgress.instance.reportChapterComplete(widget.chapterNumber);
          if (_tutorialRun) {
            // Bolum 1 ilk kez bitti: artik kaybetme serbest, huniye yaz.
            GameProgress.instance.markTutSeen('ch1');
            AnalyticsService.instance.log('tut_ch1_complete');
          }
          _gemsFromClear = GameProgress.instance.gems - gemsBefore;
          _completeRunId++;
          _doubleBonus = _chapterCoins;
          _doubleClaimed = false;
          _doubleBusy = false;
          _doubleAdReady = false;
          unawaited(_checkDoubleReady());
          _starsEarned = _computeStars();
          final firstClear = GameProgress.instance.starsFor(widget.chapterNumber) == 0;
          GameProgress.instance.reportChapterStars(widget.chapterNumber, _starsEarned);
          _xpGained = GameProgress.instance.applyXpBonus(
              GameProgress.xpForChapter(goal: _chapterGoal, firstClear: firstClear, stars: _starsEarned));
          // Kazanmak da 1 enerji harcar - reklamla-tekrar-dene hakki
          // sadece KAYIPTA var, kazaninca her zaman harcanir.
          // ONEMLI: XP/seviye atlama ONCEDEN degil SONRADAN gelmeli; seviye
          // atlayinca enerji fulleniyor, harcama sonra olursa full'u siliyordu.
          if (!_lossEnergyCharged) {
            _lossEnergyCharged = true;
            GameProgress.instance.spendEnergy();
          }
          _barFrom = GameProgress.instance.levelProgress;
          final levelBefore = GameProgress.instance.playerLevel;
          _levelUps = GameProgress.instance.addXp(_xpGained);
          _levelAfter = GameProgress.instance.playerLevel;
          _barTo = _levelAfter > levelBefore ? 1.0 : GameProgress.instance.levelProgress;
          _awaitingLevelUp = _levelUps.isNotEmpty;
          if (_awaitingLevelUp) {
            Future.delayed(const Duration(milliseconds: 3000), () async {
              if (!mounted || !_chapterComplete) return;
              await showLevelUpCelebrations(context, _levelUps);
              if (mounted) setState(() => _awaitingLevelUp = false);
            });
          }
          break;
        }
      }
    }

    // 6) Oyun sonu kontrolu: atis noktasina yakin bolgede durgun obje var mi?
    //    (Bu adimda bolum tamamlandiysa oyun sonu kontrolu yapilmaz.)
    if (_roundOver) return;
    final dangerY = _tableTopY + (_tableBottomY - _tableTopY) * _dangerLineFraction;
    for (final b in _balls) {
      final atRest = b.vx == 0 && b.vy == 0;
      if (atRest && b.y > dangerY) {
        if (_noLose) {
          // Ilk bolum / pratik: kaybetme yok, alt bolgeyi sessizce rahatlat.
          // (break hemen ardindan geldigi icin liste degisimi guvenli.)
          _relieveTable(dangerY);
          break;
        }
        _gameOver = true;
        GameFx.instance.gameOver();
        _maybeFirstFullCard();
        // Enerji harcama zamanlamasi: bu deneme icin reklam-tekrar-
        // dene hakki ZATEN kullanilmissa (yani bu ikinci kayip), artik
        // baska secenek yok - enerji simdi harcanir. Ilk kayipta ise
        // henuz harcamiyoruz; oyuncu once "reklam izle" ya da "menuye
        // don" sececek (bkz. _menuAfterLoss / _adRetry).
        if (_usedAdRetryThisAttempt && !_lossEnergyCharged) {
          _lossEnergyCharged = true;
          GameProgress.instance.spendEnergy();
        }
        break;
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  // Ogretici yardimcilari (v89)
  // ────────────────────────────────────────────────────────────

  /// Bir rehber adimi tamamlandi: huni olayi (pratikte yazilmaz) + kucuk odul sesi.
  void _coachStepDone(String event, {bool cheer = true}) {
    if (!_practice) AnalyticsService.instance.log(event);
    if (cheer) GameFx.instance.reward();
  }

  /// Ekranin ortasinda kisa sure duran balon (Harika!, kombo ipucu...).
  void _showCoachNote(String text) {
    _coachNote = text;
    Future<void>.delayed(const Duration(milliseconds: 2800), () {
      if (mounted && _coachNote == text) setState(() => _coachNote = null);
    });
  }

  void _setTouching(bool v) {
    if (_touching == v || !_guided) return;
    setState(() => _touching = v);
  }

  /// Adim 2'de parlayan hedef: durgun Seviye 1 objelerinden en yeni olan.
  _Ball? _coachTargetBall() {
    _Ball? best;
    for (final b in _balls) {
      if (b.level != 1 || b.vx != 0 || b.vy != 0) continue;
      if (best == null || b.id > best.id) best = b;
    }
    return best;
  }

  /// Ilk bolum / pratik: masa dolacak olursa durgun alt-bolge objelerini coin
  /// parlamasiyla kaldirir (oyuncu hicbir sey kaybetmez).
  void _relieveTable(double dangerY) {
    final cutoff = dangerY - 70;
    final doomed = _balls.where((b) => b.vx == 0 && b.vy == 0 && b.y > cutoff).toList();
    for (final b in doomed) {
      _spawnCoinBurst(b.x, b.y, count: 5);
      _physics.removeBall(b.id);
    }
    _balls.removeWhere((b) => doomed.contains(b));
  }

  /// Kombo ipucu: Bolum 3-6'da ilk birlesmede bir kez.
  void _maybeComboHint() {
    final gp = GameProgress.instance;
    if (_practice || widget.chapterNumber < 3 || widget.chapterNumber > 6 || gp.tutSeen('combo')) return;
    gp.markTutSeen('combo');
    AnalyticsService.instance.log('tut_combo_hint');
    _showCoachNote(AppStrings.instance.t('tut_combo'));
  }

  /// Hayatinda ILK "Masa Doldu"da: Nisan Rehberi + Devam Et'i tanitan tek kart.
  void _maybeFirstFullCard() {
    final gp = GameProgress.instance;
    if (_practice || gp.tutSeen('first_full')) return;
    gp.markTutSeen('first_full');
    AnalyticsService.instance.log('tut_first_full_card');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showFirstFullCard();
    });
  }

  Widget _tipRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 30, color: const Color(0xFFFF8A1F)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        ],
      );

  Future<void> _showFirstFullCard() {
    final s = AppStrings.instance;
    return showDialog<void>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(s.t('tut_full_title'), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tipRow(boosterIcon(BoosterType.aimGuide), s.t('tut_full_aim')),
            const SizedBox(height: 12),
            _tipRow(boosterIcon(BoosterType.revive), s.t('tut_full_continue')),
          ],
        ),
        actions: [
          CandyButton(
            height: 50,
            fontSize: 18,
            label: s.t('tut_full_btn'),
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  /// Pratik modu bitti (ilk teslimat): kisa kapanis karti, sonra ekrandan cik.
  Future<void> _finishPractice() async {
    final s = AppStrings.instance;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(s.t('howto_done_title'), textAlign: TextAlign.center),
        content: Text(s.t('howto_done_body'), textAlign: TextAlign.center),
        actions: [
          CandyButton(
            height: 50,
            fontSize: 18,
            label: s.t('howto_done_btn'),
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Koleksiyon albumu: bu tema+seviye ilk kez uretildiyse karti ac.
  /// Seviye 1 her atista cikacagi icin sessiz; 2+ icin kisa bir bildirim.
  void _discoverInAlbum(int level) {
    final isNew = GameProgress.instance.discoverItem(widget.theme.themeNameKey, level);
    if (isNew && level >= 2) {
      _showToast('${AppStrings.instance.t('album_new_toast')} ${widget.theme.byLevel(level).name}');
    }
  }

  void _showToast(String message) {
    _toast = message;
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _toast == message) {
        setState(() => _toast = null);
      }
    });
  }

  /// Coin kazanildiginda cagrilir: verilen noktadan disariya dogru
  /// altin parcaciklar fiskirtir. Metin yerine gorsel efekt kullanmak,
  /// ust bardaki "+5 coin" yazisinin layout'u buyutup kucultmesini
  /// (istenmeyen "sapitma" hissini) onler.
  void _spawnCoinBurst(double x, double y, {int count = 10}) {
    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * pi * 2;
      final speed = 90 + _random.nextDouble() * 160;
      _particles.add(_CoinParticle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 80, // hafif yukari yonlu fiskirma
        life: 0.45 + _random.nextDouble() * 0.35,
      ));
    }
  }

  void _updateParticles(double dt) {
    if (_particles.isEmpty) return;
    for (final p in _particles) {
      p.vy += 420 * dt; // hafif yercekimi - parcaciklar dusup soner
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.life -= dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
  }

  /// Nisanlanan objeyi masanin uzak ucuna dogru (yukari) firlatir.
  void _throwCurrent() {
    if (!_canThrow || _roundOver) return;

    setState(() {
      _touching = false;
      // Rehber Adim 1 -> 2: oyuncu kendi eliyle ilk atisi yapti.
      if (_coach == _CoachStep.drag) {
        _coach = _CoachStep.merge;
        _coachStepDone('tut_step1_throw', cheer: false);
      }
      final id = _nextId++;
      // yukari, sabit hizli ucus - masa doldukca (_boardFullness) biraz
      // daha canli/hizli hissettirsin (referans videodaki gibi).
      final vy = -(_padY - _tableTopY) / _throwFlightSeconds * (1 + _boardFullness * 0.15);
      _balls.add(_Ball(id: id, level: _pendingLevel, x: _aimX, y: _padY, vx: 0, vy: vy));
      if (!_pendingIsJoker && !_practice) _discoverInAlbum(_pendingLevel);
      _physics.spawnBall(
        id: id,
        level: _pendingLevel,
        xPx: _aimX,
        yPx: _padY,
        vxPx: 0,
        vyPx: vy,
        radiusPx: widget.theme.byLevel(_pendingLevel).radius,
        thrown: true, // ilk temasa kadar surtunmesiz, sabit hizli ucus
      );
      _pendingLevel = _nextLevel; // onizlemede gosterilen obje simdi atis noktasina gecer
      _pendingIsJoker = false;
      if (_aimGuideShotsLeft > 0) _aimGuideShotsLeft--;
      _nextLevel = _rollLevel(); // yeni bir "sonraki" rastgele belirlenir
      _canThrow = false;
    });
    GameFx.instance.throwBall();

    Future.delayed(_throwCooldown, () {
      if (mounted) setState(() => _canThrow = true);
    });
  }

  void _updateAim(double dx) {
    final r = widget.theme.byLevel(_pendingLevel).radius;
    // Nisan, atis noktasinin bulundugu satirdaki masa genisligiyle
    // sinirlandirilir - boylece obje daha firlatilmadan masanin
    // disina nisanlanamiyor.
    setState(() {
      _aimX = _clampD(dx, _tableLeftAt(_padY) + r, _tableRightAt(_padY) - r);
    });
  }

  /// Kaybedince (masa dolunca) kullanilan sifirlama: ayni bolume baştan
  /// baslar.
  /// Coin kazandiginda hem yerel state'i hem de uygulama genelindeki
  /// GameProgress singleton'ini gunceller - boylece dukkanda harcanabilir
  /// ve bolumler arasi kalici kalir.
  /// Bolum derinligine gore coin carpani (ChapterConfig.coinMultiplier).
  int _scaleCoins(int v) => max(1, (v * ChapterConfig.coinMultiplier(widget.chapterNumber)).round());

  void _addCoins(int rawAmount) {
    if (_practice) return; // pratik modu: cuzdana/goreve hicbir sey yazilmaz
    final amount = GameProgress.instance.applyCoinBonus(rawAmount); // Kasaba: Lezzet Duragi bonusu
    _coins += amount;
    _chapterCoins += amount;
    GameProgress.instance.coins = _coins;
    GameProgress.instance.reportCoinsEarned(amount);
  }

  /// Bolum bitince reklam hazir mi bak (hazir degilse x2 butonu hic cikmaz).
  /// Reklam hala yukleniyor olabilir: 3 kez (0 / 2.5 / 5 sn) dener.
  Future<void> _checkDoubleReady() async {
    final runId = _completeRunId;
    for (int i = 0; i < 3; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 2500));
      final ready = await AdService.instance.isRewardedReady();
      if (!mounted || runId != _completeRunId || !_chapterComplete || _doubleClaimed) return;
      if (ready) {
        setState(() => _doubleAdReady = true);
        return;
      }
    }
  }

  /// "x2 Coin" butonu: reklam GERCEKTEN izlenirse bu bolumde kazanilan coin kadar
  /// bonus cuzdana eklenir (gorev/etkinlik/elmas/XP'ye dokunmaz). Bolum basina bir kez.
  Future<void> _claimDoubleCoins() async {
    if (_doubleBusy || _doubleClaimed || _doubleBonus <= 0 || !_chapterComplete) return;
    GameFx.instance.uiTap();
    setState(() => _doubleBusy = true);
    final runId = _completeRunId;
    bool ok = false;
    try {
      if (await AdService.instance.isRewardedReady() && mounted) {
        ok = await AdService.instance.showRewarded(context, strict: true);
      }
    } catch (_) {}
    if (!mounted) return;
    if (runId != _completeRunId || !_chapterComplete) {
      setState(() => _doubleBusy = false);
      return;
    }
    setState(() {
      _doubleBusy = false;
      if (ok) {
        GameProgress.instance.addBonusCoins(_doubleBonus);
        _coins = GameProgress.instance.coins;
        _chapterCoins += _doubleBonus;
        _doubleClaimed = true;
        AdService.instance.resetInterstitialCounter(); // hemen arkasindan gecis reklami cikmasin
      } else {
        _doubleAdReady = false; // reklam gelmediyse buton kalkar
      }
    });
  }

  /// Tahtayi sifirlayan asil mantik - _restart() (yeni/taze bir deneme)
  /// ve _adRetry() (ayni denemenin devami, reklam-tekrar-dene) ikisi
  /// de bunu cagirir. _usedAdRetryThisAttempt bayragina KASITLI
  /// dokunmuyor - onu kim cagirdiysa o karar veriyor.
  void _resetBoard() {
    setState(() {
      _balls.clear();
      _physics.clear(); // butun Forge2D govdelerini de temizle
      // NOT: Coin ARTIK sifirlanmiyor - GameProgress'te kalici bir
      // para birimi, dukkanda harcanip biriktiriliyor.
      _gameOver = false;
      _pendingLevel = _rollLevel();
      _nextLevel = _rollLevel();
      _orders.clear();
      for (int i = 0; i < _orderSlotCount; i++) {
        _orders.add(_firstOrder(i));
      }
      _ordersCompleted = 0;
      _chapterComplete = false;
      _gemsFromClear = 0;
      _chapterCoins = 0;
      _doubleBonus = 0;
      _doubleAdReady = false;
      _doubleClaimed = false;
      _doubleBusy = false;
      _peakFullness = 0;
      _starsEarned = 0;
      _levelUps = const [];
      _pendingIsJoker = false;
      _bestTierThisRound = 2;
      _lastElapsed = Duration.zero;
    });
  }

  /// "Tekrar Oyna" (kazandiktan sonra) ya da eski akislarda duz
  /// "Yeniden Basla" - TAZE bir deneme baslatir, bu yuzden reklam-
  /// tekrar-dene hakki da sifirlanir.
  ///
  /// ONEMLI: burada da enerji kontrolu YAPILIYOR - eskiden sadece
  /// Bolum Haritasi'ndan ilk girişte kontrol ediliyordu, ama "Sonraki
  /// Bölüm"/"Tekrar Oyna" ile zincirleme oynarken haritaya hiç
  /// uğranmadığı için oyuncu enerjisi bitse bile sınırsız oynayabiliyordu.
  void _restart() {
    GameFx.instance.uiTap();
    if (!GameProgress.instance.hasEnergy) {
      _showNoEnergyDialog();
      return;
    }
    _usedAdRetryThisAttempt = false;
    _lossEnergyCharged = false;
    _continuesUsed = 0;
    _adContinueUsed = false;
    _resetBoard();
  }

  /// Kayip ekranindaki "Reklam Izle, Enerji Harcamadan Tekrar Dene"
  /// butonu - reklam basariyla izlenirse enerji HARCANMADAN ayni
  /// denemeye (attempt) devam edilir, ama bu hak bir daha
  /// kullanilamaz (bir sonraki kayipta enerji harcanir).
  Future<void> _adRetry() async {
    GameFx.instance.uiTap();
    final watched = await watchRewardedAd(context);
    if (!watched || !mounted) return;
    _usedAdRetryThisAttempt = true;
    _resetBoard();
  }

  /// Kayip ekranindaki "Ana Menuye Don" butonu. Reklam-tekrar-dene
  /// hakki henuz kullanilmadiysa (yani bu ilk kayipsa ve oyuncu
  /// reklam izlemeden dogrudan cikmayi sectiyse) enerji BURADA
  /// harcanir - ikinci kayipta ise enerji zaten fizik adiminda
  /// harcanmis olur, burada tekrar dokunulmaz.
  void _menuAfterLoss() {
    GameFx.instance.uiTap();
    if (!_usedAdRetryThisAttempt) {
      GameProgress.instance.spendEnergy();
    }
    Navigator.of(context).maybePop();
  }

  /// Bolum Haritasi'ndaki ayniyla ayni davranan, enerji bittiginde
  /// gosterilen bilgi dialogu - burada da (oyun ekraninin icinde,
  /// "Sonraki Bölüm"/"Tekrar Oyna" akışında) aynı deneyim olsun diye.
  void _showNoEnergyDialog() {
    showNoEnergyDialog(context, onChanged: () {
      if (mounted) setState(() {});
    });
  }

  // ────────────────────────────────────────────────────────────
  // Guclendiriciler
  // ────────────────────────────────────────────────────────────

  /// Guclendirici elde varsa true doner; yoksa mucevherle satin alma
  /// onayi ister (yetmiyorsa magaza dialogu). Kullanim (tuketme)
  /// cagiran tarafta yapilir.
  Future<bool> _obtainBooster(BoosterType type) async {
    final gp = GameProgress.instance;
    if (gp.boosterCount(type) > 0) return true;
    final s = AppStrings.instance;
    final cost = GameProgress.boosterGemCost[type]!;
    final canAfford = gp.gems >= cost;
    final adLeft = gp.boosterAdsRemaining;
    // 'buy' = elmasla al, 'ad' = reklam izle, 'shop' = elmas yetmiyor -> magaza
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(s.t(boosterNameKey(type))),
        content: Text(s.t(boosterDescKey(type))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: Text(s.t('cancel'))),
          if (adLeft > 0)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop('ad'),
              icon: const Icon(Icons.smart_display_outlined, size: 18),
              label: Text('${s.t('booster_ad_btn')} ($adLeft/${GameProgress.boosterAdsPerDay})'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(canAfford ? 'buy' : 'shop'),
            child: Text(canAfford ? '${s.t('booster_buy_title')}  💎 $cost' : s.t('booster_get_gems')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return false;
    if (choice == 'shop') {
      await showNotEnoughGemsDialog(context, onChanged: () {
        if (mounted) setState(() {});
      });
      return false;
    }
    if (choice == 'ad') {
      final watched = await watchRewardedAd(context);
      if (!watched || !mounted) return false;
      return gp.claimBoosterAd(type);
    }
    return gp.buyBooster(type);
  }

  Future<void> _onAimGuidePressed() async {
    GameFx.instance.uiTap();
    if (_roundOver) return;
    if (_aimGuideShotsLeft > 0) {
      _showToast(AppStrings.instance.t('booster_aim_active'));
      setState(() {});
      return;
    }
    if (!await _obtainBooster(BoosterType.aimGuide)) return;
    if (!mounted || _roundOver) return;
    if (!GameProgress.instance.useBooster(BoosterType.aimGuide)) return;
    setState(() => _aimGuideShotsLeft = _aimGuideShots);
  }

  Future<void> _onJokerPressed() async {
    GameFx.instance.uiTap();
    if (_roundOver) return;
    if (!await _obtainBooster(BoosterType.joker)) return;
    if (!mounted || _roundOver) return;
    final level = await _pickJokerLevel();
    if (level == null || !mounted || _roundOver) return;
    if (!GameProgress.instance.useBooster(BoosterType.joker)) return;
    setState(() {
      _pendingLevel = level;
      _pendingIsJoker = true;
    });
  }

  Future<int?> _pickJokerLevel() {
    final s = AppStrings.instance;
    final maxPick = widget.theme.maxLevel < _jokerMaxLevel ? widget.theme.maxLevel : _jokerMaxLevel;
    return showDialog<int>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        title: Text(s.t('booster_joker_pick')),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (int lvl = 1; lvl <= maxPick; lvl++)
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(lvl),
                child: Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade300, width: 2),
                  ),
                  child: Image.asset(widget.theme.byLevel(lvl).imagePath, fit: BoxFit.contain),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.t('cancel'))),
        ],
      ),
    );
  }

  /// Masa dolunca: alt bolgedeki topları temizleyip ayni denemeye devam.
  Future<void> _continueAfterLoss() async {
    GameFx.instance.uiTap();
    if (!_gameOver || _chapterComplete) return;
    if (!await _obtainBooster(BoosterType.revive)) return;
    if (!mounted || !_gameOver || _chapterComplete) return;
    if (!GameProgress.instance.useBooster(BoosterType.revive)) return;
    _applyContinue();
  }

  /// Kayip ekraninda "Reklam izle, devam et": elmas/guclendirici harcamadan devam.
  Future<void> _adContinueAfterLoss() async {
    GameFx.instance.uiTap();
    if (!_gameOver || _chapterComplete || _adContinueUsed) return;
    final watched = await watchRewardedAd(context);
    if (!watched || !mounted || !_gameOver || _chapterComplete) return;
    _adContinueUsed = true;
    _applyContinue();
  }

  /// Masayi temizleyip ayni denemeye devam eder (hem revive hem reklam icin ortak).
  void _applyContinue() {
    _continuesUsed++;
    final dangerY = _tableTopY + (_tableBottomY - _tableTopY) * _dangerLineFraction;
    final cutoff = dangerY - 70; // tehlike cizgisinin biraz ustune kadar temizle
    setState(() {
      final doomed = _balls.where((b) => b.y > cutoff).map((b) => b.id).toList();
      for (final id in doomed) {
        _physics.removeBall(id);
      }
      _balls.removeWhere((b) => doomed.contains(b.id));
      _gameOver = false;
      _canThrow = true;
    });
    GameFx.instance.reward();
  }

  String _continueLabel() {
    final gp = GameProgress.instance;
    final owned = gp.boosterCount(BoosterType.revive);
    final cost = GameProgress.boosterGemCost[BoosterType.revive]!;
    final name = AppStrings.instance.t('booster_continue_btn');
    return owned > 0 ? '$name  (x$owned)' : '$name  💎 $cost';
  }

  /// Nisan Rehberi: atis noktasindan dikey giden topun ilk temas noktasi.
  _AimGuide? _computeAimGuide() {
    if (_aimGuideShotsLeft <= 0 || _roundOver) return null;
    final rp = widget.theme.byLevel(_pendingLevel).radius;
    double bestY = _tableTopY + rp;
    _Ball? target;
    for (final b in _balls) {
      final rb = widget.theme.byLevel(b.level).radius;
      final dx = (b.x - _aimX).abs();
      final reach = rb + rp;
      if (dx >= reach) continue;
      final cy = b.y + sqrt(reach * reach - dx * dx);
      if (cy > _padY) continue;
      if (cy > bestY) {
        bestY = cy;
        target = b;
      }
    }
    return _AimGuide(
      y: bestY,
      merge: target != null && target.level == _pendingLevel,
      targetX: target?.x,
      targetY: target?.y,
      targetR: target == null ? 0 : widget.theme.byLevel(target.level).radius,
    );
  }

  bool _leavingChapter = false;

  /// Bolum bitis ekranindan cikarken (harita) gecis reklamini gosterip sonra
  /// [go]'yu calistirir.
  Future<void> _leaveAfterClear(void Function() go) async {
    if (_leavingChapter) return;
    _leavingChapter = true;
    await AdService.instance.notifyChapterCompleted();
    if (!mounted) return;
    _leavingChapter = false;
    go();
  }

  /// "Sonraki Bölüm" butonu: harita ekranına hiç uğramadan bir sonraki
  /// bölümü açar. Sınırsız ilerleme mantığının kalbi burası - oyuncu
  /// ne kadar devam etmek isterse o kadar bölüm zincirleme oynanabilir.
  /// reportChapterComplete() zaten bu bölüm bitince bir sonrakini
  /// açtığı için burada ekstra bir kilit kontrolüne gerek yok - ama
  /// enerji kontrolu GEREKLI (bkz. _restart üzerindeki not).
  Future<void> _goNextChapter() async {
    if (_leavingChapter) return; // reklam sirasinda cift dokunus
    GameFx.instance.uiTap();
    // Bolgenin 8. bolumu bitti: dogrudan sonraki bolgenin 1. bolumune atlama,
    // haritaya don (yeni bolge orada acik/vurgulu gorunur).
    if (isLastChapterOfRegion(widget.chapterNumber)) {
      await _leaveAfterClear(() => Navigator.of(context).maybePop());
      return;
    }
    if (!GameProgress.instance.hasEnergy) {
      _showNoEnergyDialog();
      return;
    }
    _leavingChapter = true;
    await AdService.instance.notifyChapterCompleted(); // gecis reklami (N bolumde 1)
    if (!mounted) return;
    final next = widget.chapterNumber + 1;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameBoard(
          theme: ChapterConfig.themeFor(next),
          chapterNumber: next,
          chapterGoal: ChapterConfig.goalFor(next),
        ),
      ),
    );
  }

  /// Ust sagdaki kirmizi X butonuna basilinca cikan onay dialogu.
  /// Artik ana menu/harita yapisi eklendigi icin uygulamadan TAMAMEN
  /// cikmiyor, bir onceki ekrana (Bolum Haritasi) donuyor. Coin zaten
  /// her kazanildiginda GameProgress'e yazildigi icin ilerleme kaybolmaz.
  void _confirmExit() {
    GameFx.instance.uiTap();
    final s = AppStrings.instance;
    showDialog(
      context: context,
      builder: (ctx) => GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(s.t('exit_chapter_title')),
        content: Text(s.t('exit_chapter_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.t('cancel')),
          ),
          CandyButton(
            style: CandyStyle.orange,
            height: 50,
            fontSize: 17,
            label: s.t('exit'),
            onTap: () {
              Navigator.of(ctx).pop();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dangerY = _tableTopY + (_tableBottomY - _tableTopY) * _dangerLineFraction;
    final coachTarget = _coach == _CoachStep.merge ? _coachTargetBall() : null;
    return Scaffold(
      // fit: expand -> Scaffold govdeye GEVSEK (loose) kisit veriyor; bu
      // olmadan Stack sadece HUD'un yuksekligine (~yarim ekran) cokuyordu.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1) ARKAPLAN + FIZIK KATMANI: verilen gorsel artik TAM EKRANI
          // kaplar - kirpilip kucuk bir kutuya sikistirilmiyor. Ustune
          // binen HUD (baslik/hedef/siparisler/ipucu) bu katmanin
          // yuksekligini/genisligini HIC etkilemiyor, sadece resmin
          // UZERINDE yari saydam olarak duruyor (bkz. asagidaki 2. ve
          // 3. katmanlar).
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _boardWidth = constraints.maxWidth;
                _boardHeight = constraints.maxHeight;
                _rebuildBounds(); // ekran boyutu (ilk build/donme) degistiyse Forge2D duvarlarini tazele
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: _roundOver ? null : (_) => _setTouching(true),
                  onPanStart: _roundOver ? null : (details) => _updateAim(details.localPosition.dx),
                  onPanUpdate: _roundOver ? null : (details) => _updateAim(details.localPosition.dx),
                  onPanEnd: _roundOver
                      ? null
                      : (_) {
                          _setTouching(false);
                          _throwCurrent();
                        },
                  onPanCancel: () => _setTouching(false),
                  onTapDown: _roundOver ? null : (_) => _setTouching(true),
                  onTapUp: _roundOver
                      ? null
                      : (details) {
                          _setTouching(false);
                          _updateAim(details.localPosition.dx);
                          _throwCurrent();
                        },
                  child: Stack(
                    children: [
                      // Gercek restoran/masa fotografi - BoxFit.cover ile
                      // TUM ekrani, hicbir yaninda bosluk birakmadan ve
                      // gorselin kendisini KIRPMADAN (sadece ekranin en-boy
                      // orani gorselinkinden farkliysa, tasan kenarlardan
                      // dogal bir cover-kirpma olur; bu kirpma miktari da
                      // asagidaki masa siniri hesabina otomatik yansitiliyor).
                      Positioned.fill(
                        child: Image.asset(
                          widget.theme.tableImagePath,
                          fit: BoxFit.cover,
                        ),
                      ),
                      CustomPaint(
                        size: Size(_boardWidth, _boardHeight),
                        painter: _TablePainter(
                          dangerY: dangerY,
                          dangerLeftX: _tableLeftAt(dangerY),
                          dangerRightX: _tableRightAt(dangerY),
                          showLine: !_noLose, // ilk bolumde kaybetme yok -> kirmizi cizgi de yok
                          pulse: _dangerHintOn ? 0.5 + 0.5 * sin(_lastElapsed.inMilliseconds / 1000.0 * 5) : 0.0,
                        ),
                        foregroundPainter: _roundOver
                            ? null
                            : _BallsPainter(
                                balls: _balls,
                                particles: _particles,
                                pendingLevel: _pendingLevel,
                                padX: _aimX,
                                padY: _padY,
                                pendingOpacity: _canThrow ? 1 : 0.4,
                                aimLineBottom: _padY,
                                aimLineTop: _tableTopY,
                                tierImages: _tierImages,
                                coinImage: _coinImage,
                                theme: widget.theme,
                                aimGuide: _computeAimGuide(),
                              ),
                        child: SizedBox(
                          width: _boardWidth,
                          height: _boardHeight,
                          child: _gameOver
                                  ? _EndScreen(
                                      title: AppStrings.instance.t('table_full_title'),
                                      subtitle: AppStrings.instance.tableFullSubtitle(_ordersCompleted, _chapterGoal, _coins),
                                      // Duz "restart" butonu artik yok - ilk
                                      // kayipta reklamla-tekrar-dene VEYA
                                      // menuye don var; hak kullanildiktan
                                      // sonraki kayipta sadece menuye don var.
                                      onAdRetryPressed: _usedAdRetryThisAttempt ? null : _adRetry,
                                      onContinuePressed: _continuesUsed < _maxContinuesPerAttempt ? _continueAfterLoss : null,
                                      continueLabel: _continueLabel(),
                                      onAdContinuePressed: (!_adContinueUsed &&
                                              _continuesUsed < _maxContinuesPerAttempt &&
                                              GameProgress.instance.boosterCount(BoosterType.revive) <= 0)
                                          ? _adContinueAfterLoss
                                          : null,
                                      onMapPressed: _menuAfterLoss,
                                      mapButtonLabelKey: 'return_to_menu',
                                    )
                                  : null,
                        ),
                      ),
                      // ── REHBERLI OGRETICI (Bolum 1, ilk kez / pratik) ──
                      // Kozmetik katman: gercek fizige dokunmaz, hepsi IgnorePointer.
                      // Adim 1: el surukle-birak gosterir. Adim 2: hedef obje parlar.
                      // Adim 3: siparis karti parlar (kartta, asagidaki HUD'da).
                      if (_coach == _CoachStep.drag)
                        CoachHand(
                          from: Offset(_aimX, _padY),
                          to: Offset(_clampD(_aimX + (_aimX < _boardWidth / 2 ? 70 : -70), 40, _boardWidth - 40), _padY),
                          visible: !_touching,
                        ),
                      if (_coach == _CoachStep.merge) ...[
                        if (coachTarget != null)
                          PulseRing(
                            center: Offset(coachTarget.x, coachTarget.y),
                            diameter: widget.theme.byLevel(coachTarget.level).radius * 2 + 10,
                          ),
                        if (coachTarget != null)
                          CoachHand(
                            from: Offset(_aimX, _padY),
                            to: Offset(coachTarget.x, _padY),
                            visible: !_touching,
                          ),
                      ],
                      if (_guided)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: _coach == _CoachStep.deliver
                              ? MediaQuery.of(context).padding.top + 150
                              : (_tableTopY + _padY) / 2 - 40,
                          child: IgnorePointer(
                            child: Center(
                              child: CoachBubble(
                                text: AppStrings.instance.t(switch (_coach) {
                                  _CoachStep.drag => 'tut_drag',
                                  _CoachStep.merge => 'tut_merge',
                                  _ => 'tut_deliver',
                                }),
                                arrow: _coach == _CoachStep.deliver ? CoachArrow.up : CoachArrow.none,
                              ),
                            ),
                          ),
                        )
                      else if (_coachNote != null && !_roundOver)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_tableTopY + _padY) / 2 - 40,
                          child: IgnorePointer(child: Center(child: CoachBubble(text: _coachNote!, fontSize: 18))),
                        ),
                      // Tehlike cizgisi ipucu (ilk kez Bolum 2+): cizginin ustunde kisa etiket.
                      if (_dangerHintOn && !_roundOver)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: dangerY - 96,
                          child: IgnorePointer(
                            child: Center(
                              child: CoachBubble(
                                text: '${AppStrings.instance.t('tut_danger')}\n${AppStrings.instance.t('tut_danger_sub')}',
                                arrow: CoachArrow.down,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      // Sonraki obje onizlemesi - atis noktasinin sag
                      // ustunde SABIT bir rozet (nisanla birlikte
                      // hareket etmez). Benzer merge oyunlarindaki
                      // "next piece" onizlemesiyle ayni mantik.
                      Positioned(
                        right: 14,
                        top: _padY - 50,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: (_roundOver || _guided) ? 0 : 0.92,
                            child: Column(
                              children: [
                                Text(
                                  AppStrings.instance.t('next_label'),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 38,
                                  height: 38,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.85),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 5, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: Image.asset(widget.theme.byLevel(_nextLevel).imagePath, fit: BoxFit.contain),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 2) UST HUD: sol ustte "Level", sag ustte "Coin", ortada
          // "Bolum" rozeti - ve onun hemen altinda, ARKAPLANI SEFFAF
          // (ayri bir kutu/kart olmadan) eslesme bekleyen siparis
          // kartlari. Buyuk tek parca panel kaldirildi; her eleman
          // kendi kucuk kapsulunde dogrudan sahnenin UZERINE biniyor.
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                SizedBox(
                  height: 46,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Sol ust: teslim edilen / hedef siparis sayisi (bitise ne kadar kaldi)
                      Positioned(
                        left: 12,
                        top: 0,
                        child: _CornerPill(
                          background: const Color(0xFFE8F6E0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.assignment_turned_in_rounded, size: 18, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 5),
                              Text(
                                '$_ordersCompleted/$_chapterGoal',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Canli yildiz gostergesi (Bolum 2+): masa doldukca 3 -> 2 -> 1.
                      // "Masayi bos tut = yildiz" hissini her an gosterir.
                      if (!_noLose)
                        Positioned(
                          left: 16,
                          top: 32,
                          child: _LiveStars(stars: _computeStars()),
                        ),
                      // Sag ust: Coin
                      Positioned(
                        right: 12,
                        top: 0,
                        child: _CornerPill(
                          background: const Color(0xFFFFF1D6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset('assets/images/coin_icon.webp', width: 18, height: 18),
                              const SizedBox(width: 5),
                              Text(
                                '$_coins',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFB4790C)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Kucuk cikis (X) butonu - coin kapsulunun hemen
                      // solunda, tasarimi bozmayacak kadar kucuk.
                      Positioned(
                        right: 92,
                        top: 11,
                        child: GestureDetector(
                          onTap: _confirmExit,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF8A8A), Color(0xFFE94F4F)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 3, offset: const Offset(0, 1)),
                              ],
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                      // Orta ust: "Bolum" rozeti
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD98E7B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF7DEC2), width: 3),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 6, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Text(
                            '${switch (ChapterConfig.kindFor(widget.chapterNumber)) {
                              ChapterKind.boss => '👑 ',
                              ChapterKind.easy => '🌿 ',
                              ChapterKind.normal => '',
                            }}${AppStrings.instance.chapterLabel(widget.chapterNumber)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFF3DC),
                              letterSpacing: 0.4,
                              shadows: [
                                Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Bolumun hemen alti: eslesme bekleyen siparis kartlari.
                // Arkaplan SEFFAF - ayri bir kart/kutu yok, kartlar
                // dogrudan sahnenin uzerinde duruyor.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final order in _orders)
                        order == null
                            ? const _EmptyOrderSlot()
                            // Yeni siparis ani belirmesin: kisa "pop" ile yerine otursun.
                            : TweenAnimationBuilder<double>(
                                key: ValueKey(order.id),
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutBack,
                                builder: (context, t, child) => Opacity(
                                  opacity: t.clamp(0.0, 1.0).toDouble(),
                                  child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
                                ),
                                child: PulseGlow(
                                  // Adim 3: birlesen objenin gidecegi (Seviye 2) kartlar parlar.
                                  active: _coach == _CoachStep.deliver && order.level == 2 && !order.anyAbove,
                                  radius: 14,
                                  child: OrderCardView(
                                    order: order,
                                    theme: widget.theme,
                                    deliverable: _balls.any((b) => order.accepts(b.level)),
                                  ),
                                ),
                              ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _toast == null ? 0 : 1,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _toast ?? ' ',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 2b) GUCLENDIRICI CUBUGU (alt): Nisan Rehberi + Joker Top.
          // (Devam Et guclendiricisi kayip ekraninda cikar.)
          if (!_roundOver && !_guided)
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BoosterButton(
                        type: BoosterType.aimGuide,
                        badge: _aimGuideShotsLeft > 0 ? 'x$_aimGuideShotsLeft' : null,
                        active: _aimGuideShotsLeft > 0,
                        onTap: _onAimGuidePressed,
                      ),
                      const SizedBox(width: 14),
                      _BoosterButton(
                        type: BoosterType.joker,
                        active: _pendingIsJoker,
                        onTap: _onJokerPressed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 4) BOLUM BITTI: tahtanin ICINDE degil, TUM EKRANI kaplayan en
          // ust katman. HUD'un altinda kalmaz, kesilmez; butonlar her
          // zaman gorunur ve dokunulabilir. Arkadaki oyuna dokunuslari yutar.
          if (_chapterComplete)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: ChapterCompleteCelebration(
                  key: ValueKey('cc_${widget.chapterNumber}_$_completeRunId'),
                  title: AppStrings.instance.chapterCompleteTitle(widget.chapterNumber),
                  chapterLabel: AppStrings.instance.chapterLabel(widget.chapterNumber),
                  stars: _starsEarned,
                  coins: _chapterCoins,
                  gems: _gemsFromClear,
                  xpGained: _xpGained,
                  level: _levelAfter,
                  barFrom: _barFrom,
                  barTo: _barTo,
                  buttonsEnabled: !_awaitingLevelUp,
                  doubleBonus: (_doubleAdReady && !_doubleClaimed) ? _doubleBonus : 0,
                  doubleBusy: _doubleBusy,
                  onDoublePressed: (_doubleAdReady && !_doubleClaimed) ? _claimDoubleCoins : null,
                  onReplayPressed: _restart,
                  onMapPressed: () {
                    GameFx.instance.uiTap();
                    _leaveAfterClear(() => Navigator.of(context).maybePop());
                  },
                  onNextPressed: _goNextChapter,
                  nextLabel: isLastChapterOfRegion(widget.chapterNumber) ? AppStrings.instance.t('next_region') : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sol-ust "Level" ve sag-ust "Coin" kapsulleri icin ortak kucuk kart:
/// hafif yuvarlatilmis, yari saydam acik renkli bir arkaplan - resmin
/// dogrudan uzerine biner, ayri bir buyuk panel gerektirmez.
class _CornerPill extends StatelessWidget {
  final Widget child;
  final Color background;

  const _CornerPill({required this.child, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

/// Canli yildiz gostergesi: o an masa dolulugu yuzunden kac yildiz
/// kazanilacagini gosterir (masa doldukca yildiz solar).
class _LiveStars extends StatelessWidget {
  final int stars;
  const _LiveStars({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 1; i <= 3; i++)
            AnimatedScale(
              duration: const Duration(milliseconds: 250),
              scale: i <= stars ? 1.0 : 0.8,
              child: Image.asset(
                i <= stars ? 'assets/images/ui/star_full.webp' : 'assets/images/ui/star_empty.webp',
                width: 14,
                height: 14,
              ),
            ),
        ],
      ),
    );
  }
}

/// Bir siparis teslim edildikten sonra, yenisi gelene kadar (kisa bir
/// gecikme boyunca) o slotta gosterilen bos/bekleyen kart. Boylece
/// oyuncu "bu slot bosaldi, yeni siparis geliyor" diye anlar - ve daha
/// onemlisi, o kisa surede baska hicbir obje bu slotla eslesemez
/// (zincirleme anlik teslimati onler).
class _EmptyOrderSlot extends StatelessWidget {
  const _EmptyOrderSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: Colors.brown.shade100.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.brown.shade200, width: 1),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.brown.shade300,
        ),
      ),
    );
  }
}

/// Bolum sonu (kazanma ya da kaybetme) icin ortak, sade bir overlay.
class _EndScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  // Ana buton artik opsiyonel: kayip ekraninda (reklam-tekrar-dene
  // akisinda) duz bir "restart" butonu YOK - sadece reklam-tekrar-dene
  // ve/veya menuye don var.
  final String? buttonLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onMapPressed;
  final String mapButtonLabelKey;
  final VoidCallback? onNextPressed;
  // Kayip ekraninda, enerji harcamadan tekrar denemek icin reklam
  // butonu - sadece bu turda henuz kullanilmadiysa gosterilir.
  final VoidCallback? onAdRetryPressed;
  // Mucevher/guclendirici ile ayni denemeye devam (kayip ekrani).
  final VoidCallback? onContinuePressed;
  final VoidCallback? onAdContinuePressed; // reklam izleyerek ayni denemeye devam
  final String? continueLabel;

  const _EndScreen({
    required this.title,
    required this.subtitle,
    this.buttonLabel,
    this.onPressed,
    this.onMapPressed,
    this.mapButtonLabelKey = 'return_to_map',
    this.onNextPressed,
    this.onAdRetryPressed,
    this.onContinuePressed,
    this.onAdContinuePressed,
    this.continueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: PanelFrame(
            padding: const EdgeInsets.fromLTRB(34, 30, 34, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF5D2E00)),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF6B4A32), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                if (onNextPressed != null) ...[
                  CandyButton(
                    label: AppStrings.instance.t('next_chapter'),
                    height: 54,
                    fontSize: 18,
                    onTap: onNextPressed,
                  ),
                  const SizedBox(height: 10),
                ],
                if (onContinuePressed != null) ...[
                  CandyButton(
                    label: continueLabel ?? '',
                    icon: Icons.favorite,
                    style: CandyStyle.blue,
                    height: 54,
                    fontSize: 15,
                    onTap: onContinuePressed,
                  ),
                  const SizedBox(height: 10),
                ],
                if (onAdContinuePressed != null) ...[
                  CandyButton(
                    label: AppStrings.instance.t('ad_continue_watch'),
                    icon: Icons.smart_display_outlined,
                    style: CandyStyle.orange,
                    height: 54,
                    fontSize: 15,
                    onTap: onAdContinuePressed,
                  ),
                  const SizedBox(height: 10),
                ],
                if (onAdRetryPressed != null) ...[
                  CandyButton(
                    label: AppStrings.instance.t('ad_retry_watch'),
                    icon: Icons.smart_display_outlined,
                    style: CandyStyle.orange,
                    height: 54,
                    fontSize: 15,
                    onTap: onAdRetryPressed,
                  ),
                  const SizedBox(height: 10),
                ],
                if (buttonLabel != null && onPressed != null)
                  CandyButton(
                    label: buttonLabel!,
                    height: 54,
                    fontSize: 18,
                    onTap: onPressed,
                  ),
                if (onMapPressed != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: onMapPressed,
                    child: Text(
                      AppStrings.instance.t(mapButtonLabelKey),
                      style: const TextStyle(color: Color(0xFF6B4A32), fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Artik masanin kendisini CIZMIYOR - o is gercek illustrasyon gorseline
/// (assets/images/table_background.jpg) devredildi. Bu painter sadece
/// oyun mantigi icin gerekli olan tehlike (foul) cizgisini, gorselin
/// UZERINE ciziyor.
class _TablePainter extends CustomPainter {
  final double dangerY;
  final double dangerLeftX;
  final double dangerRightX;
  final bool showLine; // false: cizgi hic cizilmez (ilk bolum, kaybetme yok)
  final double pulse; // 0..1: tehlike ipucu aktifken cizgi nabiz gibi parlar (0 = kapali)

  _TablePainter({
    required this.dangerY,
    required this.dangerLeftX,
    required this.dangerRightX,
    this.showLine = true,
    this.pulse = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showLine) return;
    if (pulse > 0) {
      final glow = Paint()
        ..color = Colors.redAccent.withOpacity(0.25 + 0.35 * pulse)
        ..strokeWidth = 6 + 5 * pulse
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawLine(Offset(dangerLeftX + 6, dangerY), Offset(dangerRightX - 6, dangerY), glow);
    }
    // Tehlike (foul) cizgisi - kesikli. Artik tum genislik yerine SADECE
    // o satirdaki masa yuzeyi genisliginde ciziliyor - boylece cizgi
    // masanin disina (tezgah/kat alanina) tasmiyor.
    final dashPaint = Paint()
      ..color = Colors.red.shade300
      ..strokeWidth = 2;
    const dashWidth = 8.0;
    const dashSpace = 6.0;
    final leftEdge = dangerLeftX + 6;
    final rightEdge = dangerRightX - 6;
    double startX = leftEdge;
    while (startX < rightEdge) {
      canvas.drawLine(
        Offset(startX, dangerY),
        Offset(min(startX + dashWidth, rightEdge), dangerY),
        dashPaint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _TablePainter oldDelegate) {
    return oldDelegate.dangerY != dangerY ||
        oldDelegate.dangerLeftX != dangerLeftX ||
        oldDelegate.dangerRightX != dangerRightX ||
        oldDelegate.showLine != showLine ||
        oldDelegate.pulse != pulse;
  }
}

/// Tum objeleri (firlatilmis olanlar + atis noktasindaki bekleyen obje +
/// nisan hatti) TEK bir canvas gecisinde cizer. Onceki surumde her obje
/// ayri bir widget'ti (Positioned + Container + FittedBox + Column...) ve
/// bu agac saniyede ~60 kez yeniden kuruluyordu - "donuk" / takilmali
/// gorunmenin sebebi buydu. CustomPainter ile widget agaci hic
/// degismiyor, sadece Canvas'a cizim komutlari gonderiliyor: cok daha
/// akici ("yag gibi") bir hareket veriyor.
class _BallsPainter extends CustomPainter {
  final List<_Ball> balls;
  final List<_CoinParticle> particles;
  final int? pendingLevel;
  final double padX;
  final double padY;
  final double pendingOpacity;
  final double aimLineBottom;
  final double aimLineTop;
  final _AimGuide? aimGuide;
  final Map<int, ui.Image> tierImages;
  final ui.Image? coinImage;
  final GameTheme theme;

  _BallsPainter({
    required this.balls,
    required this.particles,
    required this.pendingLevel,
    required this.padX,
    required this.padY,
    required this.pendingOpacity,
    required this.aimLineBottom,
    required this.aimLineTop,
    required this.tierImages,
    required this.coinImage,
    required this.theme,
    this.aimGuide,
  });

  static final Map<String, TextPainter> _badgeCache = {};

  void _drawBall(Canvas canvas, double x, double y, int level, double opacity) {
    final tier = theme.byLevel(level);
    final r = tier.radius;
    final center = Offset(x, y);
    final image = tierImages[level];

    // Golge (hem gercek gorsel hem de eski cizim icin ortak)
    canvas.drawCircle(
      center.translate(0, 3),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.22 * opacity),
    );

    if (image != null) {
      // GERCEK illustrasyon gorseli (kullanicinin urettigi asset).
      // Sticker'in kendi beyaz cizgisi/golgesi zaten var, ekstra
      // cerceve/highlight cizmiyoruz - dogrudan kareye sigdiriyoruz.
      final diameter = r * 2;
      final destRect = Rect.fromCenter(center: center, width: diameter, height: diameter);
      final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      canvas.drawImageRect(
        image,
        srcRect,
        destRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withOpacity(opacity),
      );

      // Kucuk seviye rozeti (sag-alt kose) - gorsel karisik oldugunda
      // (ornegin tekli/cift burger) seviyeyi net ayirt etmek icin.
      final badgeR = (r * 0.24).clamp(8.0, 16.0).toDouble();
      final badgeCenter = Offset(x + r * 0.62, y + r * 0.62);
      canvas.drawCircle(badgeCenter, badgeR, Paint()..color = Colors.black87.withOpacity(opacity));
      canvas.drawCircle(
        badgeCenter,
        badgeR,
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final badgeKey = '${tier.level}_${badgeR.toStringAsFixed(1)}_${opacity.toStringAsFixed(2)}';
      final badgePainter = _badgeCache.putIfAbsent(badgeKey, () {
        if (_badgeCache.length > 200) _badgeCache.clear();
        return TextPainter(
          text: TextSpan(
            text: '${tier.level}',
            style: TextStyle(
              fontSize: badgeR * 1.15,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(opacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });
      badgePainter.paint(
        canvas,
        Offset(badgeCenter.dx - badgePainter.width / 2, badgeCenter.dy - badgePainter.height / 2),
      );
      return;
    }

    // FALLBACK: gorsel henuz yuklenmediyse (uygulama daha yeni acildi)
    // eski prosedurel cizime gec - boylece ekran hicbir zaman bos kalmaz.
    final bodyRect = Rect.fromCircle(center: center, radius: r);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 1.0,
        colors: [
          Color.lerp(tier.color, Colors.white, 0.55)!.withOpacity(opacity),
          tier.color.withOpacity(opacity),
          Color.lerp(tier.color, Colors.black, 0.15)!.withOpacity(opacity),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, r, bodyPaint);

    canvas.drawCircle(
      Offset(x - r * 0.35, y - r * 0.4),
      r * 0.28,
      Paint()..color = Colors.white.withOpacity(0.5 * opacity),
    );

    canvas.drawCircle(
      center,
      r - 1,
      Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final emojiPainter = TextPainter(
      text: TextSpan(
        text: tier.emoji,
        style: TextStyle(fontSize: 14 + tier.level * 2.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    emojiPainter.paint(
      canvas,
      Offset(x - emojiPainter.width / 2, y - r * 0.55 - emojiPainter.height / 2),
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'Lv${tier.level}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white.withOpacity(opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(x - labelPainter.width / 2, y + r * 0.2),
    );
  }

  /// Tek bir altin parcayi (coin burst efektinin bir parcasi) cizer.
  void _drawParticle(Canvas canvas, _CoinParticle p) {
    final opacity = (p.life / p.maxLife).clamp(0.0, 1.0).toDouble();
    final center = Offset(p.x, p.y);
    const r = 8.0;

    if (coinImage != null) {
      final destRect = Rect.fromCenter(center: center, width: r * 2, height: r * 2);
      final srcRect = Rect.fromLTWH(0, 0, coinImage!.width.toDouble(), coinImage!.height.toDouble());
      canvas.drawImageRect(
        coinImage!,
        srcRect,
        destRect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withOpacity(opacity),
      );
      return;
    }

    // FALLBACK: coin gorseli henuz yuklenmediyse eski prosedurel daire
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.yellow.shade200.withOpacity(opacity),
            Colors.amber.shade600.withOpacity(opacity),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.orange.shade900.withOpacity(opacity * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Nisan hatti (dikey) - masanin tezgah/kat gorunen ust kismina degil,
    // sadece masa yuzeyinin ustune cizilir.
    if (pendingLevel != null) {
      // Normal nisan hatti: atis noktasindan yukari, uzunlugun %40'i kadar,
      // yukari dogru kuculup solan parlak noktalardan olusur (duz cizgi yerine).
      const aimLineFraction = 0.4;
      final pr0 = theme.byLevel(pendingLevel!).radius;
      final fullLen = (aimLineBottom - aimLineTop) * aimLineFraction;
      final startY = aimLineBottom - pr0 - 8; // top objesinin hemen ustunden basla
      final len = fullLen - pr0 - 8;
      if (len > 0) {
        const spacing = 17.0;
        final count = (len / spacing).floor();
        for (var i = 0; i <= count; i++) {
          final t = count == 0 ? 0.0 : i / count; // 0 (alt) -> 1 (uc)
          final y = startY - i * spacing;
          final fade = 1.0 - t * 0.65; // uca dogru solar
          final r = 5.2 - t * 2.2; // uca dogru kuculur
          final c = Offset(padX, y);
          // yumusak parlama
          canvas.drawCircle(c, r * 2.2, Paint()..color = const Color(0xFFFFF0BE).withOpacity(0.30 * fade));
          // koyu kenar (ahsap uzerinde gorunur kalsin)
          canvas.drawCircle(c, r + 1.6, Paint()..color = const Color(0xFF462614).withOpacity(0.6 * fade));
          // beyaz nokta
          canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(fade));
        }
        // ucta kucuk ok ucu
        final tipY = startY - count * spacing - spacing * 0.9;
        final tip = Path()
          ..moveTo(padX, tipY - 8)
          ..lineTo(padX - 7, tipY + 4)
          ..lineTo(padX + 7, tipY + 4)
          ..close();
        canvas.drawPath(tip, Paint()..color = Colors.white.withOpacity(0.55));
        canvas.drawPath(
          tip,
          Paint()
            ..color = const Color(0xFF462614).withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    final g = aimGuide;
    if (g != null && pendingLevel != null) {
      final color = g.merge ? const Color(0xFF3DDC84) : Colors.white;
      final pr = theme.byLevel(pendingLevel!).radius;
      canvas.drawLine(
        Offset(padX, padY),
        Offset(padX, g.y),
        Paint()
          ..color = color.withOpacity(0.85)
          ..strokeWidth = 3,
      );
      canvas.drawCircle(Offset(padX, g.y), pr, Paint()..color = color.withOpacity(0.22));
      canvas.drawCircle(
        Offset(padX, g.y),
        pr,
        Paint()
          ..color = color.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (g.targetX != null && g.targetY != null) {
        canvas.drawCircle(
          Offset(g.targetX!, g.targetY!),
          g.targetR + 4,
          Paint()
            ..color = color.withOpacity(0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }

    for (final b in balls) {
      _drawBall(canvas, b.x, b.y, b.level, 1);
    }

    if (pendingLevel != null) {
      _drawBall(canvas, padX, padY, pendingLevel!, pendingOpacity);
    }

    // Altin parcacik (coin burst) efekti - metin yerine bu gosteriliyor
    for (final p in particles) {
      _drawParticle(canvas, p);
    }
  }

  @override
  bool shouldRepaint(covariant _BallsPainter oldDelegate) => true;
}


/// Nisan Rehberi'nin cizecegi bilgi: topun ilk temas edecegi nokta.
class _AimGuide {
  final double y; // atilan topun temas anindaki merkez y'si
  final bool merge; // temas edilen top ayni seviyeyse birlesme olur
  final double? targetX;
  final double? targetY;
  final double targetR;
  const _AimGuide({
    required this.y,
    required this.merge,
    this.targetX,
    this.targetY,
    this.targetR = 0,
  });
}

/// Oyun ekraninin altindaki yuvarlak guclendirici butonu. Elde kalan
/// adedi rozet olarak gosterir; 0 ise mucevher fiyatini gosterir
/// (dokununca satin alma onayi cikar).
class _BoosterButton extends StatelessWidget {
  final BoosterType type;
  final String? badge;
  final bool active;
  final VoidCallback onTap;

  const _BoosterButton({
    required this.type,
    required this.onTap,
    this.badge,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = GameProgress.instance;
    final owned = gp.boosterCount(type);
    final cost = GameProgress.boosterGemCost[type]!;
    final label = badge ?? (owned > 0 ? 'x$owned' : '💎$cost');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: active ? const Color(0xFF3DDC84) : Colors.white70,
            width: active ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(boosterIcon(type), color: Colors.white, size: 22),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
