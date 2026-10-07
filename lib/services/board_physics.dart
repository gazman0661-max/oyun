import 'dart:math';
import 'package:forge2d/forge2d.dart';

/// Forge2D (Box2D'nin Dart portu) uzerine kurulu, oyunun geri kalaniyla
/// (GameBoard) konusan ince bir sarmalayici katman.
///
/// TASARIM NOTU: masamiz piksel koordinatlarinda calisiyor ama Box2D
/// KUCUK sayilarla (tipik olarak 0.1-10 metre araliginda cisimler)
/// stabil calisir - dogrudan piksel (400-1000) kullanirsak cozucu
/// hatali/titrek davranabilir. Bu yuzden her yerde [kPixelsPerMeter]
/// ile piksel<->metre donusumu yapiyoruz; disariya (GameBoard'a) HER
/// ZAMAN piksel donuyoruz, GameBoard hic metre gormuyor.
const double kPixelsPerMeter = 60.0;

double pxToM(double px) => px / kPixelsPerMeter;
double mToPx(double m) => m * kPixelsPerMeter;

/// Her Body'nin userData'sinda tutulan hafif meta veri - hangi oyun
/// objesi (id/level) oldugunu ve o an "atilmis mi / oturmus mu"
/// oldugunu tasir (referans videodaki iki fazli his - surtunmesiz
/// ucus, sonra sert oturma - Box2D linearDamping ile taklit ediliyor).
class BallBodyData {
  final int id;
  int level;
  bool hasLanded; // ilk temastan sonra true olur, bir daha false olmaz
  bool isBoundary; // masa duvari/kenari mi (top degil)
  bool deflecting = false; // carpip yan boslua kayiyor - yavaslayinca normal damping'e doner
  final double radiusPx; // yuva (slot) hesabi icin
  double? targetX; // != null ise top bu yuvaya dogru suzuluyor (px)
  double? targetY;
  double glideT = 0; // suzulme suresi (zaman asimi icin)
  // UYKU: oturmus top bir sure (stillT) neredeyse hareketsiz kalinca uyur;
  // uyurken uzak-duvar cekimi UYGULANMAZ ve hizi sifirlanir. Eskiden bu cekim
  // her adim eklendigi icin yigin hic durmuyor, saniyede birkac px
  // surunmeye devam ediyordu ("yuvaya cok yavas yerlesiyor").
  double stillT = 0;
  // Son "darbe"den (atis carpmasi / top eklendi-cikti) beri gecen sure. maxAwakeSeconds'i
  // asinca top HIZINDAN BAGIMSIZ olarak uyutulur -> yigin en gec ~1.6 sn'de kesin durur.
  double awakeT = 0;
  // Konum tabanli durgunluk penceresi (hiz tabanli olcum yavas kaymayi 'durgun' sanip yigini YARIDA donduruyordu)
  double winT = 0;
  double winX = 0;
  double winY = 0;
  bool sleeping = false;
  bool get gliding => targetX != null;

  BallBodyData({
    required this.id,
    required this.level,
    this.hasLanded = false,
    this.isBoundary = false,
    this.radiusPx = 0,
  });
}

/// Bir "an" icin dislariya raporlanan top durumu (piksel biriminde).
class BallSnapshot {
  final int id;
  final int level;
  final double x;
  final double y;
  final double vx;
  final double vy;
  final bool atRest;
  BallSnapshot({
    required this.id,
    required this.level,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.atRest,
  });
}

/// Ayni seviyede iki topun temasa gectigini (merge edilmesi gerektigini)
/// bildiren olay.
class MergeEvent {
  final int idA;
  final int idB;
  final double midX;
  final double midY;
  MergeEvent(this.idA, this.idB, this.midX, this.midY);
}

/// Bir topun (masa kenari DAHIL) bir seye carptigini bildiren olay -
/// ses/titresim (GameFx) tetiklemek icin kullanilir.
class ImpactEvent {
  final int idA;
  final int? idB; // null ise duvar/kenar carpmasi
  final int? levelA;
  final int? levelB;
  final double speed; // px/s, carpisma anindaki bagil hiz
  ImpactEvent({required this.idA, this.idB, this.levelA, this.levelB, required this.speed});
}

class BoardPhysics {
  late World _world;
  final Map<int, Body> _bodies = {};
  Body? _leftWall;
  Body? _rightWall;
  Body? _topWall;
  Body? _bottomWall;

  // Bu adimda toplanan olaylar - GameBoard her _simulate cagrisindan
  // sonra bunlari okuyup tuketir (consumeX metodlariyla).
  final List<MergeEvent> _pendingMerges = [];
  final List<ImpactEvent> _pendingImpacts = [];
  final Set<int> _mergeLocked = {}; // bu adimda zaten merge'e queue edilmis id'ler - ayni topu iki kez merge etme

  // --- Ayarlanabilir "his" sabitleri (eski elle yazilmis sistemdeki
  // karsiliklariyla ayni ruhta, ama artik Box2D'nin kendi cozucusune
  // veriliyor) ---
  static const double restitution = 0.08; // carpisma zipla(ma)masi (Box2D iki yuzeyden BUYUK olani alir - 0.32 iken ~3000px/s'lik atis duvardan/toptan sekip yigini dagitiyordu)
  static const double ballFriction = 0.15; // top-top/top-duvar surtunmesi (Box2D contact friction)
  static const double flightDamping = 0.0; // atilan top ucarken (ilk temasa kadar) surtunmesiz sabit hiz
  static const double settledDamping = 16.0; // ilk temastan SONRA: sert oturma. Kayma mesafesi ~ hiz/damping: 6 iken itilen obje yuzlerce px kayiyordu, 16 ile ~1 cap
  // --- FARKLI seviyeden carpisma: "misir tanesi" YERLESIMI (referans video, kare kare incelendi) ---
  // Videoda atilan bardak baska bir bardaga carpinca yana FIRLAMIYOR/dagilmiyor: onundeki iki bardagin
  // arasindaki COKURA (komsuya ve duvara/ikinci komsuya teget en yakin bos yuva) oturuyor. Once duvar
  // tarafindaki ilk sira doluyor, sonra ikinci sira sasirtmali (hex) diziliyor.
  // Burada: carpma anininda teget-teget "yuva" adaylari uretilir, en iyisi secilir, top oraya suzulur.
  static const double glideRate = 32.0; // 1/s - hedefe uzaklik * bu = hiz
  static const double glideMaxSpeedPx = 2400.0;
  static const double glideMinSpeedPx = 450.0; // kuyrukta takilmasin
  static const double glideArriveEpsPx = 3.0;
  static const double glideMaxSeconds = 0.8; // zaman asimi - her halukarda biter
  // YERLESME HIZLANDIRMA: top iki objenin arasina girince yavasca 1. siraya cikip komsulari yana itiyor
  // (videoda 8+ sn). Mekanigi DEGISTIRMEDEN ayni fizigi daha hizli kosuyoruz: yigin yerlesirken her
  // karede fizik bu kadar kat fazla adim atar. Ucan top varken 1x (atis hissi ayni kalir).
  static const int settleTimeScale = 8;
  // Simulasyon-zamani cinsinden guvenlik siniri (20 sn / 8 = ~2.5 sn gercek). Normalde yigin ondan once durur.
  static const double maxAwakeSeconds = 20.0;
  static const double settleWindowSeconds = 0.5; // bu pencerede ...
  static const double settleMoveEpsPx = 0.6; // ... bu kadardan az yer degistirdiyse uyu
  static const double slotUpWeight = 1.2; // uzak duvara (ust) yakin yuvayi tercih: ilk sira once dolsun
  static const double slotPathClearance = 0.6; // yol, baska topun merkezine bu * (r1+r2)'den fazla yaklasmasin
  static const double slotUnsupportedPenalty = 60.0; // tek temasli (destek bekleyen) aday cezasi
  // Oturmus toplar uzak duvara dogru HAFIFCE cekilir (yercekimi gibi): hicbir top havada asili kalmaz,
  // hepsi duvara ya da bir komsuya yaslanir -> sira sira dolu, bosluksuz yigin. Son hiz ~ ivme / damping.
  static const double packGravityPx = 2400.0; // px/s^2 (damping 16 ile ~150 px/s son hiz)
  final Random _rng = Random();
  static const double sleepSpeedPx = 14.0; // bunun altinda sayilan hiz "neredeyse durgun"
  static const double sleepAfterSeconds = 0.18; // bu sure durgun kalinca top uyur
  static const double restEpsilonPx = 6.0; // bunun altindaki hiz -> "durgun" sayilir

  bool _boundsBuilt = false;
  double _lastBoundsW = -1, _lastBoundsH = -1;
  double Function(double y)? _leftAtFn;
  double Function(double y)? _rightAtFn;
  double _topYPx = 0;
  double _bottomYPx = 0;

  BoardPhysics() {
    // Yercekimi YOK: masa 2D usttten gorunum, objeler dusmuyor sadece
    // kayip surtunmeyle duruyor (eski sistemle ayni varsayim).
    _world = World(Vector2.zero());
    // Box2D'nin varsayilan onerdigi hiz/pozisyon iterasyon sayilari -
    // forge2d'de bunlar World'un DEGIL, kutuphanenin UST SEVIYE
    // (top-level) degiskenleri (world.settings gibi bir ara nesne YOK).
    velocityIterations = 8;
    positionIterations = 3;
    _world.setContactListener(_MergeContactListener(this));
  }

  /// Masanin trapezoid (perspektifli) sinirlarini static Body'lerle
  /// kurar/gunceller. [leftAt]/[rightAt] verilen y (px) icin masanin o
  /// satirdaki sol/sag kenarini dondurur - ayni GameBoard._tableLeftAt
  /// ile birebir ayni matematik. Ekran boyutu degismediyse tekrar
  /// insa etmez (ucuz bir no-op).
  void ensureBounds({
    required double topY,
    required double bottomY,
    required double Function(double y) leftAt,
    required double Function(double y) rightAt,
    required double boardWidth,
    required double boardHeight,
  }) {
    _leftAtFn = leftAt; // yuva kontrolu icin - her cagrida guncel tut
    _rightAtFn = rightAt;
    _topYPx = topY;
    _bottomYPx = bottomY;
    if (_boundsBuilt && _lastBoundsW == boardWidth && _lastBoundsH == boardHeight) {
      return;
    }
    _lastBoundsW = boardWidth;
    _lastBoundsH = boardHeight;
    _boundsBuilt = true;

    // Onceki sinir govdelerini kaldir (ekran donunce/boyut degisince
    // yeniden kuruyoruz).
    for (final b in [_leftWall, _rightWall, _topWall, _bottomWall]) {
      if (b != null) _world.destroyBody(b);
    }

    // Sol ve sag kenarlar egimli (perspektif) - birden fazla segmentle
    // (chain-benzeri, ardisik EdgeShape'ler) yaklastiriyoruz. 8 segment
    // trapezoidin egimini yeterince duzgun takip eder.
    const segments = 8;
    _leftWall = _buildEdgeChain(
      List.generate(segments + 1, (i) {
        final t = i / segments;
        final y = topY + (bottomY - topY) * t;
        return Vector2(pxToM(leftAt(y)), pxToM(y));
      }),
    );
    _rightWall = _buildEdgeChain(
      List.generate(segments + 1, (i) {
        final t = i / segments;
        final y = topY + (bottomY - topY) * t;
        return Vector2(pxToM(rightAt(y)), pxToM(y));
      }),
    );
    // Ust (uzak) ve alt (yakin/atis) duvar - duz cizgi yeterli.
    _topWall = _buildEdgeChain([
      Vector2(pxToM(leftAt(topY)), pxToM(topY)),
      Vector2(pxToM(rightAt(topY)), pxToM(topY)),
    ]);
    _bottomWall = _buildEdgeChain([
      Vector2(pxToM(leftAt(bottomY)), pxToM(bottomY)),
      Vector2(pxToM(rightAt(bottomY)), pxToM(bottomY)),
    ]);
  }

  Body _buildEdgeChain(List<Vector2> pts) {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..userData = BallBodyData(id: -1, level: 0, isBoundary: true);
    final body = _world.createBody(bodyDef);
    for (int i = 0; i < pts.length - 1; i++) {
      final shape = EdgeShape()..set(pts[i], pts[i + 1]);
      final fixtureDef = FixtureDef(shape)
        ..friction = ballFriction
        ..restitution = 0.15; // duvara sekmesin, oldugu yerde dursun (eski davranisla ayni)
      body.createFixture(fixtureDef);
    }
    return body;
  }

  /// Yeni bir dinamik top govdesi olusturur. [thrown]=true ise
  /// (atis noktasindan firlatilan top) ilk temasa kadar surtunmesiz
  /// sabit hizla ucar - referans videodaki "havada yavaslamadan gider"
  /// hissi bu sayede ELLE hackliyor degil, GERCEKTEN surtunmesiz ucuyor.
  void spawnBall({
    required int id,
    required int level,
    required double xPx,
    required double yPx,
    required double vxPx,
    required double vyPx,
    required double radiusPx,
    bool thrown = false,
  }) {
    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = Vector2(pxToM(xPx), pxToM(yPx))
      ..linearVelocity = Vector2(pxToM(vxPx), pxToM(vyPx))
      ..linearDamping = thrown ? flightDamping : settledDamping
      ..bullet = thrown // hizli hareket eden top - tunelleme (icinden gecme) onlensin
      ..userData = BallBodyData(id: id, level: level, hasLanded: !thrown, radiusPx: radiusPx);
    final body = _world.createBody(bodyDef);
    final shape = CircleShape()..radius = pxToM(radiusPx);
    final fixtureDef = FixtureDef(shape)
      ..density = 1.0
      ..friction = ballFriction
      ..restitution = restitution;
    body.createFixture(fixtureDef);
    _bodies[id] = body;
    _wakeAll();
  }

  /// Yigindaki herkesi uyandirir (top eklendi/cikti -> komsular yeniden otursun).
  void _wakeAll() {
    for (final b in _bodies.values) {
      final d = b.userData as BallBodyData;
      d.sleeping = false;
      d.stillT = 0;
      d.awakeT = 0;
      d.winT = 0;
    }
  }

  void removeBall(int id) {
    final body = _bodies.remove(id);
    if (body != null) _world.destroyBody(body);
    _wakeAll();
    _mergeLocked.remove(id);
  }

  void clear() {
    for (final id in _bodies.keys.toList()) {
      removeBall(id);
    }
  }

  /// Fizigi [dt] saniye ilerletir. GameBoard tarafindan, eskiden
  /// _simulate() icindeki elle-entegrasyon yerine cagriliyor.
  void step(double dt) {
    _pendingMerges.clear();
    _mergeLocked.clear();
    // Hicbir top ucmuyor ve yigin hala oturuyorsa fizigi hizlandir (ayni mekanik, daha kisa surede).
    var n = 1;
    var anyFlying = false;
    var anySettling = false;
    for (final b in _bodies.values) {
      final d = b.userData as BallBodyData;
      if (!d.hasLanded) anyFlying = true;
      else if (!d.sleeping) anySettling = true;
    }
    if (!anyFlying && anySettling) n = settleTimeScale;
    for (int i = 0; i < n; i++) {
      _driveBodies(dt);
      // NOT: forge2d 0.13.x'te stepDt SADECE dt alir - hiz/pozisyon
      // iterasyon sayilari World.settings uzerinden ayarlaniyor (asagida
      // constructor'da bir kez ayarlandi).
      _world.stepDt(dt);
    }
  }

  /// Her adimdan once: yuvaya suzulen toplari hedefe surer, oturmus toplari uzak duvara dogru hafifce ceker.
  void _driveBodies(double dt) {
    for (final body in _bodies.values) {
      final d = body.userData as BallBodyData;
      if (!d.sleeping) d.awakeT += dt;
      final tx = d.targetX;
      final ty = d.targetY;
      if (tx != null && ty != null) {
        d.glideT += dt;
        final dx = tx - mToPx(body.position.x);
        final dy = ty - mToPx(body.position.y);
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < glideArriveEpsPx || d.glideT > glideMaxSeconds) {
          d.targetX = null;
          d.targetY = null;
          d.deflecting = false;
          body.linearVelocity = Vector2.zero();
          body.linearDamping = settledDamping;
        } else {
          var sp = (dist * glideRate).clamp(glideMinSpeedPx, glideMaxSpeedPx).toDouble();
          if (dt > 0 && sp > dist / dt) sp = dist / dt; // hedefi asma: bir adimda tam varir
          body.linearVelocity = Vector2(pxToM(dx / dist * sp), pxToM(dy / dist * sp));
        }
      } else if (d.hasLanded) {
        if (d.sleeping) {
          body.linearVelocity = Vector2.zero();
          continue;
        }
        // SERT ZAMAN SINIRI: hiz ne olursa olsun (solver'in yavas itme/kayma artigi dahil) dur.
        if (d.awakeT >= maxAwakeSeconds) {
          d.sleeping = true;
          body.linearVelocity = Vector2.zero();
          continue;
        }
        final v = body.linearVelocity;
        // Konum tabanli durgunluk: pencere boyunca neredeyse yer degistirmediyse uyu.
        final px = mToPx(body.position.x);
        final py = mToPx(body.position.y);
        if (d.winT == 0) {
          d.winX = px;
          d.winY = py;
        }
        d.winT += dt;
        if (d.winT >= settleWindowSeconds) {
          final mx = px - d.winX;
          final my = py - d.winY;
          d.winT = 0;
          if (mx * mx + my * my < settleMoveEpsPx * settleMoveEpsPx) {
            d.sleeping = true;
            body.linearVelocity = Vector2.zero();
            continue;
          }
        }
        body.linearVelocity = Vector2(v.x, v.y - pxToM(packGravityPx * dt));
      }
    }
  }

  /// Su anki tum top durumlarini (piksel biriminde) dondurur.
  Iterable<BallSnapshot> snapshots() sync* {
    for (final entry in _bodies.entries) {
      final body = entry.value;
      final data = body.userData as BallBodyData;
      final v = body.linearVelocity;
      final vxPx = mToPx(v.x);
      final vyPx = mToPx(v.y);
      final atRest = vxPx.abs() < restEpsilonPx && vyPx.abs() < restEpsilonPx;
      if (data.deflecting && (vxPx * vxPx + vyPx * vyPx) < 60 * 60) {
        data.deflecting = false;
        body.linearDamping = settledDamping; // yerine oturdu - normal sert oturma
      }
      if (atRest && data.hasLanded) {
        // Titremeyi onlemek icin gercekten durdur (eski _restEpsilon mantigi).
        body.linearVelocity = Vector2.zero();
      }
      yield BallSnapshot(
        id: entry.key,
        level: data.level,
        x: mToPx(body.position.x),
        y: mToPx(body.position.y),
        vx: atRest ? 0 : vxPx,
        vy: atRest ? 0 : vyPx,
        atRest: atRest,
      );
    }
  }

  List<MergeEvent> consumeMerges() {
    final out = List<MergeEvent>.from(_pendingMerges);
    _pendingMerges.clear();
    return out;
  }

  List<ImpactEvent> consumeImpacts() {
    final out = List<ImpactEvent>.from(_pendingImpacts);
    _pendingImpacts.clear();
    return out;
  }

  // --- ContactListener'in cagirdigi ic metodlar ---

  void _onBeginContact(BallBodyData a, BallBodyData b, double relSpeedPx) {
    // Temastan ONCE hangisi hala "ucuyor" (atilmis, henuz hicbir seye degmemis)?
    final aFlying = !a.isBoundary && !a.hasLanded;
    final bFlying = !b.isBoundary && !b.hasLanded;
    // Yeni temas: iki taraf da uyaniksin (yigin yeniden dengelensin).
    if (!a.isBoundary) {
      a.sleeping = false;
      a.stillT = 0;
    }
    if (!b.isBoundary) {
      b.sleeping = false;
      b.stillT = 0;
    }
    // ATIS carpmasinda butun yigin uyanir (komsular yana itilebilsin, top 1. siraya cikabilsin) ve
    // sureler sifirlanir. Jitter temaslari bunu tetiklemez.
    if (aFlying || bFlying) {
      _wakeAll();
    }
    if (!a.isBoundary) a.hasLanded = true;
    if (!b.isBoundary) b.hasLanded = true;

    if (!a.isBoundary && !b.isBoundary) {
      if (a.level == b.level && !_mergeLocked.contains(a.id) && !_mergeLocked.contains(b.id)) {
        _mergeLocked.add(a.id);
        _mergeLocked.add(b.id);
        final bodyA = _bodies[a.id];
        final bodyB = _bodies[b.id];
        if (bodyA != null && bodyB != null) {
          // Referans video: atilan bardak duran ayniya carpinca yeni (birlesmis) bardak
          // DURAN hedefin yerinde belirir (ortada degil). Iki taraf da hareketliyse orta nokta.
          var midX = mToPx((bodyA.position.x + bodyB.position.x) / 2);
          var midY = mToPx((bodyA.position.y + bodyB.position.y) / 2);
          if (aFlying && !bFlying) {
            midX = mToPx(bodyB.position.x);
            midY = mToPx(bodyB.position.y);
          } else if (bFlying && !aFlying) {
            midX = mToPx(bodyA.position.x);
            midY = mToPx(bodyA.position.y);
          }
          _pendingMerges.add(MergeEvent(a.id, b.id, midX, midY));
        }
      } else {
        _pendingImpacts.add(ImpactEvent(idA: a.id, idB: b.id, levelA: a.level, levelB: b.level, speed: relSpeedPx));
        // Referans videodaki "sert carpip hemen oturma" hissi: temastan
        // sonra iki topun da damping'i yukseliyor (artik "settled" fazina
        // gectiler - bir daha dusmuyor, kalici).
        _bumpDamping(a.id);
        _bumpDamping(b.id);
        // Atilan top baska bir topa carptiysa en yakin bos "cokur" yuvaya otursun.
        if (aFlying && !bFlying) {
          _seekSlot(a);
        } else if (bFlying && !aFlying) {
          _seekSlot(b);
        } else if (aFlying && bFlying) {
          _seekSlot(a);
          _seekSlot(b);
        }
      }
    } else {
      // Duvar/kenar carpmasi - ses icin bildir, top tarafinin damping'ini yukselt.
      final ballData = a.isBoundary ? b : a;
      _pendingImpacts.add(ImpactEvent(idA: ballData.id, levelA: ballData.level, speed: relSpeedPx));
      _bumpDamping(ballData.id);
    }
  }

  /// [striker] (atilan top) FARKLI seviyeden bir topa carpti: en iyi yuvayi bul, oraya suzul.
  /// Yuva bulunamazsa carpma noktasinda durur.
  void _seekSlot(BallBodyData striker) {
    final sb = _bodies[striker.id];
    if (sb == null) return;
    final slot = _findPackSlot(sb, striker);
    sb.linearDamping = settledDamping;
    if (slot == null) {
      sb.linearVelocity = Vector2.zero();
      return;
    }
    striker.targetX = slot.x;
    striker.targetY = slot.y;
    striker.glideT = 0;
    striker.deflecting = true;
  }

  /// Teget-teget yuva adaylari:
  ///  A) uzak duvara + bir topa teget, B) iki topa teget (iki komsunun arasindaki cokur),
  ///  C) bir topa + yan duvara teget, D) tek topa teget (destek bekleyen, cezali).
  /// Gecerli (cakismayan, masa icinde, yolu acik) olanlardan en dusuk maliyetli secilir:
  /// maliyet = carpma noktasina uzaklik + slotUpWeight * (duvardan uzaklik) -> yakin ve duvara yakin.
  _Disc? _findPackSlot(Body sb, BallBodyData striker) {
    final leftAt = _leftAtFn;
    final rightAt = _rightAtFn;
    if (leftAt == null || rightAt == null) return null;
    final rs = striker.radiusPx;
    final hx = mToPx(sb.position.x);
    final hy = mToPx(sb.position.y);
    final obs = <_Disc>[];
    for (final e in _bodies.entries) {
      if (e.key == striker.id) continue;
      final od = e.value.userData as BallBodyData;
      obs.add(_Disc(mToPx(e.value.position.x), mToPx(e.value.position.y), od.radiusPx));
    }
    final yMin = _topYPx + rs;
    final yMax = _bottomYPx - rs;
    final wallR = rs * 1.03; // egimli yan duvar icin kucuk pay
    // Yuva, komsuyla ~0.8px ic ice: tam teget (mesafe == r1+r2) Box2D'de temas sayilmayabilir -> ayni
    // seviyeden komsuyla birlesme tetiklenmezdi.
    const embed = 0.8;
    final cands = <_Disc>[];
    final unsupported = <_Disc>[]; // cezali adaylar

    // A) uzak duvara + bir topa teget
    for (final o in obs) {
      final rr = rs + o.r - embed;
      final dy = o.y - yMin;
      if (dy.abs() < rr) {
        final dx = sqrt(rr * rr - dy * dy);
        cands.add(_Disc(o.x - dx, yMin, 0));
        cands.add(_Disc(o.x + dx, yMin, 0));
      }
    }
    cands.add(_Disc(leftAt(yMin) + wallR, yMin, 0));
    cands.add(_Disc(rightAt(yMin) - wallR, yMin, 0));

    // B) iki topa teget
    for (int i = 0; i < obs.length; i++) {
      for (int j = i + 1; j < obs.length; j++) {
        final a = obs[i];
        final b = obs[j];
        final ra = rs + a.r - embed;
        final rb = rs + b.r - embed;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final d = sqrt(dx * dx + dy * dy);
        if (d < 1e-6 || d > ra + rb + 0.5 || d < (ra - rb).abs()) continue;
        final t = (ra * ra - rb * rb + d * d) / (2 * d);
        var h2 = ra * ra - t * t;
        if (h2 < 0) {
          if (h2 < -4) continue;
          h2 = 0;
        }
        final h = sqrt(h2);
        final mx = a.x + dx * t / d;
        final my = a.y + dy * t / d;
        cands.add(_Disc(mx + dy / d * h, my - dx / d * h, 0));
        cands.add(_Disc(mx - dy / d * h, my + dx / d * h, 0));
      }
    }

    // C) bir topa + yan duvara teget (cember uzerinde ornekle, isaret degisimini enterpole et)
    for (final o in obs) {
      final rr = rs + o.r - embed;
      for (final side in const [-1, 1]) {
        double? prevY;
        double? prevF;
        for (int k = 0; k <= 32; k++) {
          final y = o.y - rr + 2 * rr * k / 32;
          final inner = rr * rr - (y - o.y) * (y - o.y);
          if (inner < 0) continue;
          final x = o.x + side * sqrt(inner);
          final f = side < 0 ? x - (leftAt(y) + wallR) : (rightAt(y) - wallR) - x;
          if (prevF != null && prevY != null && prevF * f <= 0 && prevF != f) {
            final t = prevF / (prevF - f);
            final ys = prevY + t * (y - prevY);
            final inn = rr * rr - (ys - o.y) * (ys - o.y);
            if (inn >= 0) cands.add(_Disc(o.x + side * sqrt(inn), ys, 0));
          }
          prevY = y;
          prevF = f;
        }
      }
    }

    // D) tek topa teget: yan ve yukari-yan (destek bekler, duvara dogru cekim tamamlar)
    for (final o in obs) {
      final rr = rs + o.r - embed;
      for (final deg in const [0.0, 30.0, 60.0]) {
        final rad = deg * pi / 180.0;
        for (final sd in const [-1, 1]) {
          unsupported.add(_Disc(o.x + sd * rr * cos(rad), o.y - rr * sin(rad), 0));
        }
      }
    }

    _Disc? best;
    var bestCost = double.infinity;
    void consider(_Disc c, double penalty) {
      if (c.y < yMin - 0.75 || c.y > yMax) return;
      if (c.x < leftAt(c.y) + wallR - 0.75 || c.x > rightAt(c.y) - wallR + 0.75) return;
      for (final o in obs) {
        final dx = c.x - o.x;
        final dy = c.y - o.y;
        final need = rs + o.r - 1.0;
        if (dx * dx + dy * dy < need * need) return;
      }
      for (final o in obs) {
        if (_segDist(hx, hy, c.x, c.y, o.x, o.y) < (rs + o.r) * slotPathClearance) return;
      }
      final dxh = c.x - hx;
      final dyh = c.y - hy;
      final cost = sqrt(dxh * dxh + dyh * dyh) + slotUpWeight * (c.y - yMin) + penalty;
      if (cost < bestCost) {
        bestCost = cost;
        best = c;
      }
    }

    for (final c in cands) {
      consider(c, 0);
    }
    for (final c in unsupported) {
      consider(c, slotUnsupportedPenalty);
    }
    return best;
  }

  static double _segDist(double ax, double ay, double bx, double by, double px, double py) {
    final dx = bx - ax;
    final dy = by - ay;
    final l2 = dx * dx + dy * dy;
    if (l2 < 1e-9) {
      final ex = px - ax;
      final ey = py - ay;
      return sqrt(ex * ex + ey * ey);
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / l2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final qx = px - (ax + t * dx);
    final qy = py - (ay + t * dy);
    return sqrt(qx * qx + qy * qy);
  }

  void _bumpDamping(int id) {
    final body = _bodies[id];
    if (body != null) body.linearDamping = settledDamping;
  }

  /// Ayni seviyeden iki top temas ettiginde Box2D'nin normal carpisma
  /// tepkisini (sekmesini) devre disi birakir - boylece birbirlerine
  /// hafifce gomulup GameBoard tarafindan "merge" olarak kaldirilana
  /// kadar sekmeden bekler (goze carpan bir "zipla sonra kaybol"
  /// tuhafligi olmasin diye).
  bool _shouldDisableContact(BallBodyData a, BallBodyData b) {
    // Suzulen top (yuvasina gidiyor) komsulari itmez/sekmez; yuva zaten cakismasiz secildi.
    return !a.isBoundary && !b.isBoundary && (a.level == b.level || a.gliding || b.gliding);
  }
}

class _MergeContactListener implements ContactListener {
  final BoardPhysics owner;
  _MergeContactListener(this.owner);

  @override
  void beginContact(Contact contact) {
    final a = contact.fixtureA.body.userData as BallBodyData?;
    final b = contact.fixtureB.body.userData as BallBodyData?;
    if (a == null || b == null) return;
    final va = contact.fixtureA.body.linearVelocity;
    final vb = contact.fixtureB.body.linearVelocity;
    final relSpeed = mToPx((va - vb).length);
    owner._onBeginContact(a, b, relSpeed);
  }

  @override
  void endContact(Contact contact) {}

  @override
  void preSolve(Contact contact, Manifold oldManifold) {
    final a = contact.fixtureA.body.userData as BallBodyData?;
    final b = contact.fixtureB.body.userData as BallBodyData?;
    if (a == null || b == null) return;
    if (owner._shouldDisableContact(a, b)) {
      // Ayni seviye -> fiziksel sekme yerine merge'e birak.
      // NOT: forge2d'de bu bir metod degil (Contact.setEnabled YOK),
      // isEnabled adinda bir getter/setter property.
      contact.isEnabled = false;
    }
  }

  @override
  void postSolve(Contact contact, ContactImpulse impulse) {}
}

/// Yuva hesabi icin kucuk bir daire (veya r=0 ile nokta).
class _Disc {
  final double x;
  final double y;
  final double r;
  const _Disc(this.x, this.y, this.r);
}
