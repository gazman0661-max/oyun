import 'dart:math';

import 'package:flutter/material.dart';

import '../game/orbit_controller.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'fx/celebration_fx.dart';
import 'rock_painter.dart';

/// Ic ice gecmis donen yorunge halkalarini gosteren, SURUKLE-CEVIR ile
/// kontrol edilen oyun tahtasi widget'i.
///
/// Etkilesim: oyuncu parmagini bir halkanin cizildigi yaricap bandina
/// koyup istedigi yone (saga ya da sola, fark etmez) surukler; halka
/// gercek bir kadran/tekerlek gibi parmakla birlikte doner. Surukleme
/// belirli bir aciyi (bir hucre genisligini) gectiginde alttaki motorda
/// tek bir adim rotateRing() cagrisina donusturulur - uzun/hizli bir
/// surukleme boylece birden fazla adimi art arda tetikleyebilir. Parmak
/// kalkinca tamamlanmamis kismi gorsel olarak "yerine oturur" (snap-back).
/// Ustteki "toplama hunisi" (gate) her zaman sabit kalir; nesneler
/// halkalar donerken oraya dogru kayar.
///
/// Bir donus rihtim doluluğu yuzunden reddedilirse, o halka kisa
/// sureligine kirmizi yanip soner (blokaj geri bildirimi) ve o suruklemede
/// o yonde birikim durur.
///
/// GEZEGEN CIKIS ANIMASYONU: kapiya gelen bir gezegen halkadan ayrildiginda
/// (teslim edildi ya da rihtima kondu) artik aniden kaybolmuyor; kapi
/// noktasindan hedefine dogru kisa bir "suzulme" (glide) animasyonuyla
/// ucuyor — teslim edilenler yukari/disari, rihtima gidenler asagiya
/// (Kargo Rihtimi kutusuna dogru) suzulur. bkz. [OrbitController.lastExit].
class OrbitBoard extends StatefulWidget {
  final OrbitController controller;
  final void Function(int ringIndex) onBlockedTap;

  const OrbitBoard({
    super.key,
    required this.controller,
    required this.onBlockedTap,
  });

  @override
  State<OrbitBoard> createState() => _OrbitBoardState();
}

class _FlightItem {
  final int id;
  final int colorIndex;
  final Offset start;
  final Offset end;
  final bool matched;
  final AnimationController anim;

  _FlightItem({
    required this.id,
    required this.colorIndex,
    required this.start,
    required this.end,
    required this.matched,
    required this.anim,
  });
}

class _OrbitBoardState extends State<OrbitBoard> with TickerProviderStateMixin {
  int? _flashRing;
  int? _lastHandledExitId;
  final List<_FlightItem> _flights = [];

  // --- Eslesme "juice" efektleri (VFX/SFX gucu) ---
  // DUZELTME (retention): teslimat oncesinde sadece kayma animasyonu ve ses
  // vardi, gorsel bir "odul anlari" vurgusu yoktu. Bu, oyuncuda tatmin
  // hissi yerine "gorev tamamlama yorgunlugu" yaratma riski tasiyordu. Asagidaki
  // liste/controller'lar dusuk maliyetli (sabit sayida parcacik, tek
  // CustomPainter) bir patlama + combo esiklerinde alev efekti ekler.
  final List<MatchBurstItem> _bursts = [];
  int _nextBurstId = 0;

  // DUZELTME (istek): tam ekran sari flas yerine, ekranin iki kenarindan
  // yukselen "alev" efekti. Once esik bazli tek seferlik bir animasyondu;
  // artik SUREKLI/KADEMELI: alev yuksekligi doğrudan mevcut combo degerine
  // baglı - combo arttikca alev yukselir, combo sifirlaninca (miss/jam)
  // yumusakca soner. `_flameLevelController` 0..1 arasinda "hedef seviyeyi"
  // tutar; her combo degisiminde animateTo ile yeni hedefe yumusakca kayar.
  static const int _comboFlameMaxCombo = 15; // bu combo'da alev tam boyda
  late final AnimationController _flameLevelController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  /// Mevcut combo degerine gore alev seviyesini (0..1) hesaplayip
  /// yumusak bir gecisle oraya animasyonla tasir. Hem yeni bir combo
  /// (teslimat basarili) hem de combo sifirlanmasi (yanlis teslimat/miss)
  /// sonrasi cagrilir - boylece alev hem kademeli yukselir hem de
  /// kademeli soner.
  void _updateComboFlame() {
    final combo = widget.controller.combo;
    final target = (combo / _comboFlameMaxCombo).clamp(0.0, 1.0);
    _flameLevelController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
    );
  }

  // DUZELTME (istek): rihtim dolulugu yuzunden bir donus reddedildiginde
  // (jam), artik sadece o halka degil, TUM ekran cok kisa/hafif kirmizi
  // yanip sonuyor. Ses zaten SoundService.instance.invalid() ile _flash()
  // cagrisiyla ayni anda calindigi icin ekstra ses eklemedik.
  late final AnimationController _jamFlashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _jamFlashAnim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
  ]).animate(CurvedAnimation(parent: _jamFlashController, curve: Curves.easeOut));

  // --- Hedef renk vurgusu (target highlight) ---
  // O an teslim edilmesi beklenen renkle (OrbitController.currentTarget)
  // eslesen TUM hucreler (kilitli halkalar dahil, tum halkalarda), oyuncu
  // saymak zorunda kalmadan nereye odaklanacagini hemen gorsun diye hafifce
  // "nefes alip veren" (pulse) bir parlaklikla isaretlenir. Surekli tekrar
  // eden yumusak bir animasyon - _OrbitPainter'a 0..1 araliginda bir deger
  // olarak aktarilir ve glow/stroke alfasini modüle etmek icin kullanilir.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  // --- Surukle-cevir (drag-to-rotate) durumu ---
  // Eski mekanik "sol yariya dokun / sag yariya dokun" seklindeydi; bu,
  // oyuncular icin tanidik olmayan/kesfedilemeyen bir kuraldi. Bunun yerine
  // oyuncu artik bir halkanin uzerine parmagini koyup, istedigi yone
  // (saga ya da sola) dogal bir sekilde surukleyerek halkayi cevirebiliyor
  // - fiziksel bir kadran/tekerlek cevirir gibi.
  int? _dragRing; // su an suruklenmekte olan halkanin indeksi
  double _dragAccumulated = 0; // son adimdan beri biriken aci (radyan)
  double? _lastPointerAngle; // onceki karedeki parmak acisi
  final Map<int, double> _visualOffset = {}; // halka basina anlik gorsel aci ofseti
  final List<AnimationController> _snapAnimations = [];

  // --- Kucuk ekranlarda dokunma bandi genisligi ---
  // Halka sayisi arttikca (stage 10'da tavan: 6 halka) her halkaya ayrilan
  // bant genisligi `step` kadar, ve step ekran genisligiyle sinirli. Kucuk
  // telefonlarda (ör. 360dp) step, Material/iOS'un onerdigi ~44dp dokunma
  // hedefinin altina dusebiliyor. Bandi ekranin sahip oldugundan daha genis
  // yapmanin fiziksel bir yolu yok - o yuzden bu durumda tahtayi mantiksal
  // olarak `_kMinRingStep` genisliginde bantlarla cizip, ekrana sigacak
  // sekilde otomatik kucultuyoruz (InteractiveViewer). Oyuncu isterse iki
  // parmakla yakinlastirip her halkaya rahat dokunabilir.
  static const double _kMinRingStep = 44.0;
  final TransformationController _viewerController = TransformationController();
  Object? _fitForLevel;

  // KOK NEDEN DUZELTMESI: dokunma isleyicileri (onPanStart/onPanUpdate)
  // eskiden `context.findRenderObject()` kullaniyordu - fakat oradaki
  // `context`, LayoutBuilder'in DIS context'iydi, GestureDetector'in kendi
  // context'i degildi. Zoom gerektiginde (kucuk ekran + cok halka, ornegin
  // ileri seviyelerde 5-6 halka) InteractiveViewer devreye girince bu dis
  // RenderBox, zoom/pan donusumunden ETKILENMEMIS oluyordu; ama `center` ve
  // halka bantlari donusum SONRASI buyutulmus mantiksal tuval uzerinden
  // hesaplaniyordu. Sonuc: parmak konumu ile hesaplanan aci arasinda sabit
  // bir kayma olusuyor, bu da ozellikle en ic (dar) bantlarda dokunusun
  // komsu halkaya kaymasina yol aciyordu. Bu key, GestureDetector'in KENDI
  // (donusum sonrasi dogru) RenderBox'ina erismek icin eklendi.
  final GlobalKey _boardKey = GlobalKey();

  void _flash(int ringIndex) {
    setState(() => _flashRing = ringIndex);
    _jamFlashController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted && _flashRing == ringIndex) {
        setState(() => _flashRing = null);
      }
    });
  }

  /// Yeni bir [OrbitController.lastExit] olayi tespit edilince cagrilir:
  /// kapi konumundan hedefine giden yeni bir "ucus" (flight) baslatir ve
  /// uygun ses efektini calar. Ayni build gecisinde birden fazla setState
  /// tetiklememek icin bir sonraki frame'e ertelenir.
  void _maybeSpawnFlight(Size size, double step) {
    final exit = widget.controller.lastExit;
    if (exit == null || exit.id == _lastHandledExitId) return;
    _lastHandledExitId = exit.id;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = step * (exit.ringIndex + 1.4);
    final start = center + const Offset(0, 0) + Offset(0, -radius);
    // Teslim edilen (matched) gezegen kapidan yukari/disari suzulerek
    // "gonderilir"; eslesmeyen gezegen ise asagidaki Kargo Rihtimi
    // kutusuna dogru suzulur.
    final end = exit.matched
        ? Offset(size.width / 2, -step * 0.8)
        : Offset(size.width / 2, size.height + step * 0.8);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      );
      final item = _FlightItem(
        id: exit.id,
        colorIndex: exit.colorIndex,
        start: start,
        end: end,
        matched: exit.matched,
        anim: animController,
      );
      setState(() => _flights.add(item));
      if (exit.matched) {
        SoundService.instance.orbitDeliver();
        _spawnBurst(start, AppColors.colorFor(exit.colorIndex));
      } else {
        SoundService.instance.orbitDock();
      }
      // Combo hem eslesince (arttiginda) hem de kacirilince (sifirlaninca)
      // degisir - alev seviyesini her iki durumda da guncelle.
      _updateComboFlame();
      animController.forward();
      animController.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _flights.remove(item));
          animController.dispose();
        }
      });
    });
  }

  /// Teslimat aninda kisa bir parcacik patlamasi baslatir (bkz.
  /// celebration_fx.dart). Sabit sureli (~420ms), kendi kendini listeden
  /// siler - bellekte birikmez.
  void _spawnBurst(Offset center, Color color) {
    final id = _nextBurstId++;
    final anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final item = MatchBurstItem(id: id, center: center, color: color, anim: anim);
    setState(() => _bursts.add(item));
    anim.forward();
    anim.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _bursts.remove(item));
        anim.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final item in _flights) {
      item.anim.dispose();
    }
    for (final controller in _snapAnimations) {
      controller.dispose();
    }
    for (final burst in _bursts) {
      burst.anim.dispose();
    }
    _flameLevelController.dispose();
    _jamFlashController.dispose();
    _pulseController.dispose();
    _viewerController.dispose();
    super.dispose();
  }

  /// Ekran, halkalari `_kMinRingStep` genisliginde rahatca gostermeye
  /// yetmiyorsa (kucuk ekran + cok halka), tahtayi mantiksal olarak daha
  /// buyuk cizip InteractiveViewer ile ekrana sigdiriyoruz. `scale < 1`
  /// donerse zoom gerekli demektir. Ayni seviye icin bu hesap/atama sadece
  /// bir kez yapilir ki oyuncunun kendi yakinlastirmasi surekli sifirlanmasin;
  /// yeni bir seviyeye gecildiginde (level nesnesi degisince) görünüm tekrar
  /// ekrana sigacak sekilde sifirlanir.
  double _ensureFitScale(int ringCount, double naturalStep) {
    if (naturalStep >= _kMinRingStep) return 1.0;
    final scale = naturalStep / _kMinRingStep;
    final level = widget.controller.level;
    if (!identical(_fitForLevel, level)) {
      _fitForLevel = level;
      _viewerController.value = Matrix4.identity()..scale(scale);
    }
    return scale;
  }

  double _angleAt(Offset local, Offset center) {
    return atan2(local.dy - center.dy, local.dx - center.dx);
  }

  /// Verilen dokunma noktasinin hangi halkanin uzerine dustugunu bulur
  /// (merkeze/hunuye ya da tahtanin disina dusenler icin null doner).
  int? _ringIndexAt(Offset local, Offset center, double step, int ringCount) {
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final radius = sqrt(dx * dx + dy * dy);
    // DUZELTME: halkalar _OrbitPainter icinde step*(i+1.4) yaricapinda
    // ciziliyor (bkz. asagidaki `radius = step * (i + 1.4)` satiri).
    // Dokunma bandinin merkezi de ayni step*(i+1.4)'e hizalanmali; eskiden
    // burada step*0.5 kullanildigi icin bant, gorunen halkadan %40 disari
    // kaymisti (bant merkezi step*(i+1.0) oluyordu). step*0.9 kullanarak
    // bant merkezini gorsel yaricapla ayni noktaya (step*(i+1.4)) getiriyoruz.
    if (radius < step * 0.9) return null;
    final idx = ((radius - step * 0.9) / step).floor();
    // En disteki halkanin disina tasan (ama tahtanin kendi alani icinde
    // kalan) dokunuslari yine en disteki halkaya say: kucuk ekranlarda
    // zaten dar olan bantlarda en azindan disari tasan pay bosa gitmesin.
    if (idx >= ringCount) return ringCount - 1;
    if (idx < 0) return null;
    return idx;
  }

  void _onPanStart(DragStartDetails details, RenderBox box, Offset center,
      double step, int ringCount) {
    final local = box.globalToLocal(details.globalPosition);
    final ringIndex = _ringIndexAt(local, center, step, ringCount);
    if (ringIndex == null) return;
    _dragRing = ringIndex;
    _dragAccumulated = 0;
    _lastPointerAngle = _angleAt(local, center);
  }

  void _onPanUpdate(DragUpdateDetails details, RenderBox box, Offset center) {
    final ringIndex = _dragRing;
    final lastAngle = _lastPointerAngle;
    if (ringIndex == null || lastAngle == null) return;

    final local = box.globalToLocal(details.globalPosition);
    final angle = _angleAt(local, center);
    var delta = angle - lastAngle;
    // -pi..pi araligina normalize et (180 derece sinirinda sicrama olmasin).
    if (delta > pi) delta -= 2 * pi;
    if (delta < -pi) delta += 2 * pi;
    _lastPointerAngle = angle;
    _dragAccumulated += delta;

    setState(() {
      _visualOffset[ringIndex] = (_visualOffset[ringIndex] ?? 0) + delta;
    });

    final ring = widget.controller.level.rings[ringIndex];
    final anglePerCell = 2 * pi / ring.cellCount;

    // Biriken surukleme acisi bir hucre genisligini gectikce, halkayi o
    // yonde birer adim dondur. Boylece kisa bir surukleme tek adim, uzun/
    // hizli bir surukleme birden fazla adim doner - dokunma yerine dogal
    // bir "cevirme" hissi verir.
    while (_dragAccumulated.abs() >= anglePerCell) {
      final clockwise = _dragAccumulated > 0;
      final ok = widget.controller.rotateRing(ringIndex, clockwise: clockwise);
      final consumed = clockwise ? anglePerCell : -anglePerCell;
      if (ok) {
        SoundService.instance.orbitRotate();
        _dragAccumulated -= consumed;
        setState(() {
          _visualOffset[ringIndex] = (_visualOffset[ringIndex] ?? 0) - consumed;
        });
      } else {
        // Rihtim dolu oldugu icin bu yonde daha fazla donus yok - kirmizi
        // yanip sonme geri bildirimini ver ve bu suruklemede bu yonde
        // birikmeyi durdur (aksi halde parmak hareket ettikce surekli
        // basarisiz denemeler tetiklenir).
        SoundService.instance.invalid();
        _flash(ringIndex);
        widget.onBlockedTap(ringIndex);
        _dragAccumulated = 0;
        break;
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final ringIndex = _dragRing;
    _dragRing = null;
    _lastPointerAngle = null;
    _dragAccumulated = 0;
    if (ringIndex != null) _snapBackVisual(ringIndex);
  }

  /// Parmak kalktiginda, tamamlanmamis (bir sonraki hucreye ulasmamis)
  /// gorsel donus miktarini yumusakca 0'a geri getirir - halka "yerine
  /// oturuyormus" gibi hissettirir.
  void _snapBackVisual(int ringIndex) {
    final current = _visualOffset[ringIndex] ?? 0;
    if (current == 0) return;
    final controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _snapAnimations.add(controller);
    final tween = Tween<double>(begin: current, end: 0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    );
    tween.addListener(() {
      if (!mounted) return;
      setState(() => _visualOffset[ringIndex] = tween.value);
    });
    controller.forward().whenComplete(() {
      _visualOffset.remove(ringIndex);
      _snapAnimations.remove(controller);
      controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DirectionLegend(),
        const SizedBox(height: 6),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([widget.controller, _pulseController]),
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final viewportSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final shortest = min(viewportSize.width, viewportSize.height);
                  final ringCount = widget.controller.level.rings.length;
                  final naturalStep = shortest / 2 / (ringCount + 1.4);
                  final fitScale = _ensureFitScale(ringCount, naturalStep);
                  final needsZoom = fitScale < 1.0;

                  // Zoom gerekiyorsa tahtayi `_kMinRingStep` bandiyla, ekran
                  // alanindan daha buyuk bir "mantiksal" alana ciziyoruz;
                  // InteractiveViewer bunu baslangicta tam ekrana sigdirir
                  // (fitScale kadar kucultur), oyuncu isterse yakinlastirir.
                  final step = needsZoom ? _kMinRingStep : naturalStep;
                  final logicalSize = needsZoom
                      ? Size(viewportSize.width / fitScale,
                          viewportSize.height / fitScale)
                      : viewportSize;

                  _maybeSpawnFlight(logicalSize, step);

                  final center =
                      Offset(logicalSize.width / 2, logicalSize.height / 2);
                  final board = GestureDetector(
                    key: _boardKey,
                    onPanStart: (details) {
                      final box = _boardKey.currentContext?.findRenderObject()
                          as RenderBox?;
                      if (box == null) return;
                      _onPanStart(details, box, center, step, ringCount);
                    },
                    onPanUpdate: (details) {
                      final box = _boardKey.currentContext?.findRenderObject()
                          as RenderBox?;
                      if (box == null) return;
                      _onPanUpdate(details, box, center);
                    },
                    onPanEnd: _onPanEnd,
                    onPanCancel: () {
                      final ringIndex = _dragRing;
                      _dragRing = null;
                      _lastPointerAngle = null;
                      _dragAccumulated = 0;
                      if (ringIndex != null) _snapBackVisual(ringIndex);
                    },
                    child: SizedBox(
                      width: logicalSize.width,
                      height: logicalSize.height,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: logicalSize,
                            painter: _OrbitPainter(
                              controller: widget.controller,
                              step: step,
                              flashRing: _flashRing,
                              visualOffset: _visualOffset,
                              targetPulse: _pulseController.value,
                            ),
                          ),
                          for (final flight in _flights)
                            _FlightWidget(key: ValueKey(flight.id), item: flight),
                          for (final burst in _bursts)
                            MatchBurstWidget(key: ValueKey('burst_${burst.id}'), item: burst),
                          ComboFlamesOverlay(level: _flameLevelController, flicker: _pulseController),
                          JamFlashOverlay(intensity: _jamFlashAnim),
                        ],
                      ),
                    ),
                  );

                  if (!needsZoom) return board;

                  return InteractiveViewer(
                    transformationController: _viewerController,
                    constrained: false,
                    minScale: fitScale,
                    maxScale: 1.0,
                    boundaryMargin: EdgeInsets.zero,
                    child: board,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Kapidan cikan tek bir gezegenin suzulme animasyonunu ciziyor:
/// baslangictan (kapi) bitise (yukari/asagi) konum, kucculme ve solma
/// (fade-out) ile birlikte hareket eder.
class _FlightWidget extends AnimatedWidget {
  final _FlightItem item;

  _FlightWidget({super.key, required this.item}) : super(listenable: item.anim);

  @override
  Widget build(BuildContext context) {
    final raw = item.anim.value;
    final t = Curves.easeInCubic.transform(raw);
    final pos = Offset.lerp(item.start, item.end, t)!;
    // DUZELTME (juice): teslim edilen gezegen artik duz kuculerek gitmiyor;
    // ucusun ilk ~%18'inde 1.0 -> ~1.3 -> normal kuculme egrisine "punch"
    // yapiyor. Bu, teslimat anina gorsel bir vurgu/tatmin hissi katiyor.
    double scale;
    if (item.matched && raw < 0.18) {
      final punchT = raw / 0.18;
      scale = 1.0 + sin(punchT * pi) * 0.32;
    } else {
      scale = 1.0 - (t * 0.45);
    }
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    const objectSize = 30.0;

    return Positioned(
      left: pos.dx - objectSize / 2,
      top: pos.dy - objectSize / 2,
      width: objectSize,
      height: objectSize,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: CustomPaint(
            painter: _FlightPlanetPainter(item.colorIndex),
          ),
        ),
      ),
    );
  }
}

class _FlightPlanetPainter extends CustomPainter {
  final int colorIndex;
  const _FlightPlanetPainter(this.colorIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = AppColors.colorFor(colorIndex).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.62, glow);
    paintRock(canvas, Offset.zero & size, colorIndex);
  }

  @override
  bool shouldRepaint(covariant _FlightPlanetPainter oldDelegate) =>
      oldDelegate.colorIndex != colorIndex;
}

/// Tahtanin uzerinde sabit duran, "hangi taraf hangi yone dondurur"
/// hatirlaticisi. Sadece bir kez okunmasi yeterli olacak sekilde kucuk ve
/// surekli gorunur tutuluyor.
class _DirectionLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.pan_tool_alt_rounded, color: AppColors.accentSoft, size: 16),
        const SizedBox(width: 6),
        Text(t('orbit_dragHint'),
            style: const TextStyle(
                color: AppColors.accentSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final OrbitController controller;
  final double step;
  final int? flashRing;
  final Map<int, double> visualOffset;
  final double targetPulse;

  _OrbitPainter({
    required this.controller,
    required this.step,
    this.flashRing,
    this.visualOffset = const {},
    this.targetPulse = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rings = controller.level.rings;
    final maxRadius = step * (rings.length + 1.4) + step * 0.6;
    // O an teslim edilmesi beklenen renk — tum halkalarda bu renkle
    // eslesen hucreleri vurgulamak icin (bkz. _OrbitBoardState._pulseController).
    final currentTarget = controller.currentTarget;
    // 0..1 pulseController degerini yumusak bir "nefes alma" egrisine
    // (ease-in-out benzeri, sin ile) cevirir; boylece parlama aniden degil
    // akici bir sekilde artip azalir.
    final pulseT = (sin(targetPulse * pi) * 0.5 + 0.5);

    // Tum tahtayi ikiye bolen, "sol = ters yon / sag = saat yonu"
    // kuralini surekli hatirlatan kesikli dikey cizgi.
    _drawDashedVerticalLine(canvas, center, maxRadius);

    // Merkez gunes.
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.warning, AppColors.warning.withValues(alpha: 0.15)],
      ).createShader(Rect.fromCircle(center: center, radius: step * 0.55));
    canvas.drawCircle(center, step * 0.42, sunPaint);

    for (var i = 0; i < rings.length; i++) {
      final ring = rings[i];
      final radius = step * (i + 1.4);
      final isFlashing = flashRing == i;
      final isLocked = ring.locked;

      // Halkanin kendisi: sol yari mavi (ters yon), sag yari turuncu (saat
      // yonu) olacak sekilde iki ayri yay olarak ciziliyor, boylece her
      // halka kendi uzerinde yon ipucunu tasiyor. Kilitli halkalarda bu
      // renkler soluk griye doner ki "şu an dokunulamaz" hissi versin.
      final leftArcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFlashing ? 3.4 : 2.0
        ..color = isFlashing
            ? AppColors.danger
            : isLocked
                ? AppColors.textSecondary.withValues(alpha: 0.35)
                : AppColors.accentSoft.withValues(alpha: 0.55);
      final rightArcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFlashing ? 3.4 : 2.0
        ..color = isFlashing
            ? AppColors.danger
            : isLocked
                ? AppColors.textSecondary.withValues(alpha: 0.35)
                : AppColors.warning.withValues(alpha: 0.55);

      final ringRect = Rect.fromCircle(center: center, radius: radius);
      // Sag yari: -90° (tepe) -> +90° (dip), saat yonunde.
      canvas.drawArc(ringRect, -pi / 2, pi, false, rightArcPaint);
      // Sol yari: -90° (tepe) -> -270°/+90° (dip), saat yonunun tersine.
      canvas.drawArc(ringRect, -pi / 2, -pi, false, leftArcPaint);

      final n = ring.cellCount;
      final offset = visualOffset[i] ?? 0;
      final objectRadius = (step * 0.46).clamp(13.0, 30.0).toDouble();
      for (var c = 0; c < n; c++) {
        // Surukleme sirasinda `offset`, henuz bir sonraki hucreye
        // "kilitlenmemis" kismi doner - gezegenler parmakla birlikte
        // yumusakca doner, salt-tik-tik atlamaz.
        final angle = (-pi / 2) + (c * 2 * pi / n) + offset;
        final pos = center + Offset(cos(angle), sin(angle)) * radius;
        final value = ring.cells[c];
        if (value == null) {
          final emptyPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = AppColors.tubeGlassBorder.withValues(alpha: 0.5);
          canvas.drawCircle(pos, objectRadius * 0.7, emptyPaint);
        } else {
          final isTargetMatch = currentTarget != null && value == currentTarget;
          final glow = Paint()
            ..color =
                AppColors.colorFor(value).withValues(alpha: isLocked ? 0.22 : 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
          canvas.drawCircle(pos, objectRadius * 1.15, glow);
          if (isTargetMatch) {
            // Hedeflenen renkle eslesen hucre: yumusakca "nefes alan" bir
            // vurgu halkasi + parlaklik — oyuncu saymadan nereye
            // odaklanacagini hemen gorsun. Kilitli halkalarda bile isaretlenir
            // (o an dondurulemese de oyuncuya nerede oldugunu gosterir), ama
            // biraz daha soluk cizilir.
            final ringAlpha = (isLocked ? 0.35 : 0.55) + pulseT * 0.35;
            final highlightRing = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2 + pulseT * 1.4
              ..color = AppColors.warning.withValues(alpha: ringAlpha.clamp(0.0, 1.0).toDouble());
            canvas.drawCircle(
              pos,
              objectRadius * (1.35 + pulseT * 0.18),
              highlightRing,
            );
            final extraGlow = Paint()
              ..color = AppColors.warning.withValues(alpha: (0.18 + pulseT * 0.22) * (isLocked ? 0.6 : 1.0))
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
            canvas.drawCircle(pos, objectRadius * 1.6, extraGlow);
          }
          final rect = Rect.fromCenter(
            center: pos,
            width: objectRadius * 2,
            height: objectRadius * 2,
          );
          if (isLocked) {
            // ONCEDEN alpha 0.55 idi: gezegen neredeyse gorunmez oluyordu,
            // oyuncular "gezegen halkada yokmus gibi" hissettigini soyledi.
            // Kilitli oldugu zaten kilit ikonuyla belli - burada amac
            // "dokunulamaz" hissi vermek, "gorunmez" degil. 0.85'e cikarildi.
            canvas.saveLayer(rect.inflate(6), Paint()..color = Colors.white.withValues(alpha: 0.85));
            paintRock(canvas, rect, value);
            canvas.restore();
          } else {
            paintRock(canvas, rect, value);
          }
        }
      }

      // Bu halkanin "kapi" isaretcisi (her zaman tepede, index 0).
      final gatePos = center + Offset(0, -radius);
      if (isLocked) {
        // Kilitli halkalarda kapi vurgusu yerine kucuk bir asma kilit
        // cizilir — oyuncu neden dokunamadigini gorsel olarak anlar.
        _drawLockGlyph(canvas, gatePos, objectRadius * 0.62);
      } else {
        final gateHighlight = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = AppColors.accentSoft.withValues(alpha: 0.8);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          (-pi / 2) - 0.18,
          0.36,
          false,
          gateHighlight,
        );
        canvas.drawCircle(gatePos, 2.4, Paint()..color = AppColors.accentSoft);
      }
    }
  }

  /// Kucuk, vektorel bir asma kilit sembolu (kavis + govde) — dis kaynak
  /// gerektirmez, projenin "her sey Canvas'la cizilir" ilkesine uyar.
  void _drawLockGlyph(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round
      ..color = AppColors.textSecondary;
    final shacklePath = Path()
      ..addArc(
        Rect.fromCenter(
            center: center + Offset(0, -r * 0.15), width: r * 1.1, height: r * 1.3),
        pi,
        pi,
      );
    canvas.drawPath(shacklePath, paint);
    final bodyPaint = Paint()..color = AppColors.textSecondary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, r * 0.35), width: r * 1.5, height: r * 1.15),
        Radius.circular(r * 0.25),
      ),
      bodyPaint,
    );
  }

  void _drawDashedVerticalLine(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.surfaceBorder.withValues(alpha: 0.6);
    const dashLength = 5.0;
    const gapLength = 4.0;
    var y = center.dy - maxRadius;
    final endY = center.dy + maxRadius;
    while (y < endY) {
      final segmentEnd = min(y + dashLength, endY);
      canvas.drawLine(Offset(center.dx, y), Offset(center.dx, segmentEnd), paint);
      y = segmentEnd + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => true;
}
