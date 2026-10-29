import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import 'cosmic_powers.dart';
import 'level_mode.dart';

/// Gezegen Birlestir (Suika tarzi) modunun fizigi — forge2d (Box2D) ile.
///
/// forge2d ^0.14.x kullaniliyor (saf Dart, native derleme gerektirmez).
/// 0.15+ surumleri Box2D v3 + FFI/native assets'e gecti ve API'si
/// tamamen farkli; bu dosya 0.14 API'sine gore yazildi.
///
/// UI tarafi eskisiyle ayni arayuzu kullanir: dunya birimleri genislik
/// [PlanetMergeConfig.worldW] x yukseklik [PlanetMergeConfig.worldH],
/// y asagi dogru artar. Box2D metre olcegini sever (cisimler ~0.1-10 m),
/// bu yuzden fizige giderken [_k] ile 10'a bolunur (100 birim = 10 m).
///
/// Birlesme tespiti BILEREK forge2d contact listener'iyla degil, her
/// adimdan sonra konum kontroluyle yapilir: boylece "ayni anda iki
/// birlesmeye giren gezegen" gibi kenar durumlarda temas olayi kacirilip
/// iki es gezegenin sonsuza dek yan yana kalmasi riski olmaz.
class MergeBody {
  final int id;
  int tier;
  double x, y, vx, vy;

  /// forge2d govdesi (dunyaya eklenince dolar).
  Body? phys;

  /// Olusturulduktan sonra gecen sure (sn) — game over kontrolunde
  /// "yeni birakilan" gezegeni saymamak icin.
  double age = 0;

  /// Bolum Modu engelleri: ice > 0 buzlu (birlesemez), locked = sabit
  /// kilitli gezegen ([lockLeft] birlesme sonra acilir).
  int ice = 0;
  bool locked = false;
  int lockLeft = 0;

  /// 0..1 arasi "pop" animasyonu (merge ile olusunca 1'den 0'a iner).
  double pop = 0;

  /// Sevinc suresi (sn): yeni birlesen / kilidi acilan gezegen yuzu guler.
  double joy = 0;

  /// Saskinlik suresi (sn): dusen / hizli gezegen son tetiklenmeden sonra bu
  /// kadar sasirmis kalir (esik civarinda ifade titremesin diye).
  double surprise = 0;

  /// Tehlike cizgisine yakin mi (endiseli yuz). Histerezisli: girerken +12,
  /// cikarken +26 birim mesafe (cizgi civarinda ifade titremesin diye).
  bool worried = false;

  MergeBody({
    required this.id,
    required this.tier,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
  });

  double get r => PlanetMergeConfig.radiusOf(tier);
}

/// Bir birlesme olayi — UI'in ses/parcacik/skor gostermesi icin.
class MergeEvent {
  final int tier; // OLUSAN yeni gezegenin kademesi (en ust ise -1: yok oldu)
  final double x, y;
  final int points;
  const MergeEvent(this.tier, this.x, this.y, this.points);
}

class PlanetMergeConfig {
  PlanetMergeConfig._();

  static const double worldW = 100;
  static const double worldH = 150;

  /// Bu cizginin (y) ustune tasan ve oturmus gezegen varsa game over
  /// sayaci isler.
  static const double dangerY = 24;

  /// Bir gezegen cizginin ustunde bu kadar sn kalirsa oyun biter.
  static const double dangerSeconds = 2.0;

  /// Kademeler: kucukten buyuge. Deger = assets/planets index'i
  /// (bkz. PlanetImages.assetPaths). 13 kademe; son kademe Karanlik Kutle (Gunes + Gunes -> Karanlik Kutle).
  /// mercury, kizil cuce, bakir asteroit, buz ay, mars, dunya, gaia,
  /// neptun, uranus, saturn, pembe gaz devi, gunes, karanlik kutle.
  static const List<int> tierImage = [8, 11, 14, 13, 5, 1, 2, 9, 6, 3, 7, 0, 15];

  static const int tierCount = 13;

  /// Gorselin collision dairesine oturmasi icin cizim carpani (halkali
  /// gezegenlerde govde dairesi %53, parlamali olanlarda ~%87-91).
  static const List<double> tierDrawScale = [
    1.06, 1.12, 1.12, 1.12, 1.06, 1.12, 1.06, 1.06, 1.55, 1.55, 1.06, 1.12, 1.12,
  ];

  /// Birakilabilen en buyuk baslangic kademesi (0..4 arasi rastgele).
  static const int maxDropTier = 5;

  static double radiusOf(int tier) {
    const base = 4.2;
    return base * math.pow(1.2, tier).toDouble();
  }

  /// Kademe t olusunca eklenen puan (1,3,6,10,...).
  static int pointsForTier(int tier) => (tier + 1) * (tier + 2) ~/ 2;

  /// Iki Gunes birlesince yok olur: buyuk bonus.
  static const int sunVanishBonus = 150;

  // ---- forge2d ayarlari (hissi degistirmek icin sadece bunlari oyna) ----
  /// Yercekimi (m/sn^2, fizik biriminde). 10 = Dunya; 15 daha tok/hizli.
  static const double gravity = 15;

  /// Ziplama (0 = yapisik, 0.3 = lastik top). Suika'da cok dusuk olmali.
  static const double restitution = 0.05;

  /// Surtunme: yuksek = gezegenler yigin yapar, dusuk = kayip dagilir.
  static const double friction = 0.3;

  /// Sabit fizik adimi (sn). 1/120 = 60 fps cihazda frame basina 2 adim.
  static const double fixedDt = 1 / 120;
}

class PlanetMergeWorld {
  /// Oyun birimi -> forge2d metre carpani.
  static const double _k = 0.1;

  late final World _phys;
  final List<MergeBody> bodies = [];
  final List<MergeEvent> pendingEvents = [];

  /// Gezegen guclari (bkz. cosmic_powers.dart). Kapaliysa hic tetiklenmez.
  final bool powers;
  final List<GravityWell> wells = [];
  final List<PowerEvent> pendingPowerEvents = [];
  final List<ObstacleEvent> pendingObstacleEvents = [];

  /// Birlesme noktasina bu kadar yakin (govde yuzeyinden) buzlu gezegenler catlar.
  static const double _iceBreakReach = 18;
  int _nextId = 1;
  double _acc = 0;

  int score = 0;
  int bestTier = 0;
  bool gameOver = false;

  /// Cizginin ustunde kesintisiz kalma suresi (en kotu gezegenin).
  double dangerTimer = 0;

  /// [dangerY]: tehlike cizgisinin y konumu (dunya birimi). Meydan okuma
  /// modlarinda (dar kabin) varsayilandan asagida olabilir.
  final double dangerY;

  /// Haftalik kural icin ayarlanabilir yercekimi ve ziplama.
  final double gravity;
  final double restitution;

  PlanetMergeWorld({
    this.dangerY = PlanetMergeConfig.dangerY,
    this.gravity = PlanetMergeConfig.gravity,
    this.restitution = PlanetMergeConfig.restitution,
    this.powers = false,
  }) {
    _phys = World(Vector2(0, gravity));
    _buildWalls();
  }

  /// Zemin + iki yan duvar (tek statik govde, uc kenar).
  void _buildWalls() {
    final w = PlanetMergeConfig.worldW * _k;
    final h = PlanetMergeConfig.worldH * _k;
    const top = -30.0; // duvarlar kabinin cok ustune kadar uzansin
    final wallBody = _phys.createBody(BodyDef(type: BodyType.static));
    void edge(double x1, double y1, double x2, double y2) {
      final shape = EdgeShape()..set(Vector2(x1, y1), Vector2(x2, y2));
      wallBody.createFixture(
        FixtureDef(shape, friction: PlanetMergeConfig.friction),
      );
    }

    edge(0, h, w, h); // zemin
    edge(0, top, 0, h); // sol duvar
    edge(w, top, w, h); // sag duvar
  }

  /// [b] icin forge2d govdesi olusturur ve listeye ekler.
  void _attach(MergeBody b) {
    final body = _phys.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: Vector2(b.x * _k, b.y * _k),
      ),
    );
    final shape = CircleShape()..radius = b.r * _k;
    body.createFixture(
      FixtureDef(
        shape,
        density: 1.0,
        friction: PlanetMergeConfig.friction,
        restitution: restitution,
      ),
    );
    body.linearVelocity = Vector2(b.vx * _k, b.vy * _k);
    b.phys = body;
    bodies.add(b);
  }

  MergeBody drop(int tier, double x, {int ice = 0}) {
    final r = PlanetMergeConfig.radiusOf(tier);
    final cx = x.clamp(r, PlanetMergeConfig.worldW - r).toDouble();
    final b = MergeBody(
      id: _nextId++,
      tier: tier,
      x: cx,
      y: dangerY - r - 2,
      vy: 20,
    )..ice = ice;
    _attach(b);
    if (tier > bestTier) bestTier = tier;
    return b;
  }

  /// [dt] saniye ilerletir (UI her frame cagirir; sabit adimlara boler).
  void step(double dt) {
    if (gameOver) return;
    if (dt > 0.05) dt = 0.05; // uzun frame'de patlamayi onle
    _acc += dt;
    var n = 0;
    while (_acc >= PlanetMergeConfig.fixedDt && n < 8) {
      _phys.stepDt(PlanetMergeConfig.fixedDt);
      _acc -= PlanetMergeConfig.fixedDt;
      n++;
    }
    if (n >= 8) _acc = 0;

    // Fizik sonuclarini UI'in okudugu alanlara kopyala (oyun birimine geri).
    for (final b in bodies) {
      final p = b.phys!;
      final pos = p.position;
      final v = p.linearVelocity;
      b.x = pos.x / _k;
      b.y = pos.y / _k;
      b.vx = v.x / _k;
      b.vy = v.y / _k;
      b.age += dt;
      if (b.pop > 0) b.pop = math.max(0.0, b.pop - dt * 4);
      if (b.joy > 0) b.joy = math.max(0.0, b.joy - dt);
      if (b.surprise > 0) b.surprise = math.max(0.0, b.surprise - dt);
      if (!b.locked &&
          (b.age < 0.35 ||
              b.vy > 28 ||
              (b.vx * b.vx + b.vy * b.vy) > 2500)) {
        b.surprise = 0.25;
      }
      b.worried = !b.locked &&
          b.age > 1.2 &&
          (b.y - b.r) < dangerY + (b.worried ? 26 : 12);
    }
    _processMerges();
    _stepWells(dt);
    _checkDanger(dt);
  }

  void _processMerges() {
    // Ayni frame'de bir gezegen sadece bir birlesmeye girer.
    final used = <int>{};
    final mergePts = <List<double>>[];
    final spawns = <MergeBody>[];
    final n = bodies.length;
    for (var i = 0; i < n; i++) {
      final a = bodies[i];
      if (used.contains(a.id) || a.locked || a.ice > 0) continue;
      for (var j = i + 1; j < n; j++) {
        final b = bodies[j];
        if (used.contains(b.id) || a.tier != b.tier) continue;
        if (b.locked || b.ice > 0) continue;
        final dx = b.x - a.x, dy = b.y - a.y;
        final lim = a.r + b.r + 0.35;
        if (dx * dx + dy * dy > lim * lim) continue;
        used.add(a.id);
        used.add(b.id);
        // Kutle ~ r^2 (esit yogunluk) -> agirlikli merkez.
        final ma = a.r * a.r, mb = b.r * b.r;
        final mx = (a.x * ma + b.x * mb) / (ma + mb);
        final my = (a.y * ma + b.y * mb) / (ma + mb);
        mergePts.add([mx, my]);
        if (a.tier >= PlanetMergeConfig.tierCount - 1) {
          // Iki Karanlik Kutle: yok olur, buyuk bonus.
          const pts = PlanetMergeConfig.sunVanishBonus;
          score += pts;
          pendingEvents.add(MergeEvent(-1, mx, my, pts));
        } else {
          final tier = a.tier + 1;
          final pts = PlanetMergeConfig.pointsForTier(tier);
          score += pts;
          if (tier > bestTier) bestTier = tier;
          spawns.add(MergeBody(
            id: _nextId++,
            tier: tier,
            x: mx,
            y: my,
            vx: (a.vx + b.vx) / 2,
            vy: (a.vy + b.vy) / 2,
          )
            ..pop = 1
            ..joy = 1.3
            ..age = 10); // yeni olusan "yeni birakilmis" sayilmaz
          pendingEvents.add(MergeEvent(tier, mx, my, pts));
        }
        break;
      }
    }
    if (used.isEmpty) return;
    for (final b in bodies) {
      if (used.contains(b.id)) _phys.destroyBody(b.phys!);
    }
    bodies.removeWhere((b) => used.contains(b.id));
    for (final s in spawns) {
      _attach(s);
    }
    if (powers) {
      for (final s in spawns) {
        _triggerPower(s);
      }
    }
    _afterMerges(mergePts);
  }

  // ---------------------------------------------------------------------
  // Bolum Modu engelleri (buz / kilit)
  // ---------------------------------------------------------------------

  /// Bolum baslarken kabine buzlu ve kilitli gezegenleri yerlestirir.
  void setupLevel(LevelDef lv) {
    for (final l in lv.locks) {
      final r = PlanetMergeConfig.radiusOf(l.tier);
      final b = MergeBody(id: _nextId++, tier: l.tier, x: l.x, y: l.y)
        ..locked = true
        ..lockLeft = l.count
        ..age = 10;
      final body = _phys.createBody(
        BodyDef(type: BodyType.static, position: Vector2(b.x * _k, b.y * _k)),
      );
      body.createFixture(
        FixtureDef(
          CircleShape()..radius = r * _k,
          friction: PlanetMergeConfig.friction,
        ),
      );
      b.phys = body;
      bodies.add(b);
    }
    for (final i in lv.startIce) {
      final r = PlanetMergeConfig.radiusOf(i.tier);
      final b = MergeBody(
        id: _nextId++,
        tier: i.tier,
        x: i.x.clamp(r, PlanetMergeConfig.worldW - r).toDouble(),
        y: dangerY + 22,
      )..ice = lv.iceHp;
      _attach(b);
    }
  }

  /// Bu karedeki birlesmelerden sonra: yakindaki buzlari catlat, kilitlerin
  /// sayacini azalt.
  void _afterMerges(List<List<double>> pts) {
    if (pts.isEmpty) return;
    var any = false;
    for (final b in bodies) {
      if (b.ice > 0 || b.locked) {
        any = true;
        break;
      }
    }
    if (!any) return;
    for (final p in pts) {
      for (final b in bodies) {
        if (b.ice <= 0) continue;
        final dx = b.x - p[0], dy = b.y - p[1];
        final lim = b.r + _iceBreakReach;
        if (dx * dx + dy * dy > lim * lim) continue;
        b.ice -= 1;
        pendingObstacleEvents.add(ObstacleEvent(
          b.ice > 0 ? ObstacleKind.iceCrack : ObstacleKind.iceBreak,
          b.x,
          b.y,
          b.tier,
        ));
      }
    }
    final toUnlock = <MergeBody>[];
    for (final b in bodies) {
      if (!b.locked) continue;
      b.lockLeft -= pts.length;
      if (b.lockLeft <= 0) toUnlock.add(b);
    }
    for (final b in toUnlock) {
      _unlock(b);
    }
  }

  /// Kilitli (sabit) gezegeni normal, yercekimine uyan gezegene cevirir.
  void _unlock(MergeBody b) {
    final ph = b.phys;
    if (ph != null) _phys.destroyBody(ph);
    bodies.remove(b);
    final nb = MergeBody(id: _nextId++, tier: b.tier, x: b.x, y: b.y)
      ..pop = 1
      ..joy = 1.6
      ..age = 10;
    _attach(nb);
    pendingObstacleEvents
        .add(ObstacleEvent(ObstacleKind.unlock, b.x, b.y, b.tier));
  }

  List<ObstacleEvent> takeObstacleEvents() {
    final e = List<ObstacleEvent>.from(pendingObstacleEvents);
    pendingObstacleEvents.clear();
    return e;
  }

  // ---------------------------------------------------------------------
  // Gezegen guclari
  // ---------------------------------------------------------------------
  void _triggerPower(MergeBody s) {
    final power = CosmicPowers.forTier(s.tier);
    if (power == null) return;
    switch (power) {
      case CosmicPower.ringPulse:
        _ringPulse(s);
        break;
      case CosmicPower.solarFlare:
        _solarFlare(s);
        break;
      case CosmicPower.singularity:
        _singularity(s);
        break;
    }
  }

  /// Saturn: halkasi komsulari disa iter (yukari itme yarim guc). Itilenler
  /// tehlike cizgisi icin kisa sure korunur.
  void _ringPulse(MergeBody s) {
    final reach = s.r + CosmicPowers.ringPulseReach;
    for (final b in bodies) {
      if (b.id == s.id) continue;
      final dx = b.x - s.x, dy = b.y - s.y;
      final d = math.sqrt(dx * dx + dy * dy);
      final maxD = reach + b.r;
      if (d > maxD || d < 0.001) continue;
      final f = 1.0 - d / maxD;
      final sp = CosmicPowers.ringPulseSpeed * (0.35 + 0.65 * f);
      final ph = b.phys;
      if (ph == null) continue;
      final v = ph.linearVelocity;
      final ux = dx / d, uy = dy / d;
      ph.linearVelocity = Vector2(
        v.x + ux * sp * _k,
        v.y + uy * sp * (uy < 0 ? 0.5 : 1.0) * _k,
      );
      b.age = 0;
    }
    dangerTimer = 0;
    pendingPowerEvents
        .add(PowerEvent(CosmicPower.ringPulse, s.x, s.y, reach, const [], 0));
  }

  /// Gunes: yakindaki kucuk gezegenleri yakar, her biri icin bonus puan.
  void _solarFlare(MergeBody s) {
    final reach = s.r + CosmicPowers.flareReach;
    final hits = <PowerHit>[];
    final doomed = <int>{};
    var total = 0;
    for (final b in bodies) {
      if (b.id == s.id || b.tier > CosmicPowers.flareMaxTier) continue;
      final dx = b.x - s.x, dy = b.y - s.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > reach + b.r) continue;
      final pts =
          PlanetMergeConfig.pointsForTier(b.tier) * CosmicPowers.flarePointsMult;
      hits.add(PowerHit(b.x, b.y, b.tier, pts));
      doomed.add(b.id);
      total += pts;
    }
    for (final b in bodies) {
      if (doomed.contains(b.id)) _phys.destroyBody(b.phys!);
    }
    bodies.removeWhere((b) => doomed.contains(b.id));
    score += total;
    pendingPowerEvents
        .add(PowerEvent(CosmicPower.solarFlare, s.x, s.y, reach, hits, total));
  }

  /// Karanlik Kutle: [CosmicPowers.singularityDuration] sn komsulari ceker.
  void _singularity(MergeBody s) {
    wells.removeWhere((w) => w.bodyId == s.id);
    wells.add(GravityWell(
      s.id,
      CosmicPowers.singularityDuration,
      CosmicPowers.singularityReach,
    ));
    pendingPowerEvents.add(PowerEvent(CosmicPower.singularity, s.x, s.y,
        s.r + CosmicPowers.singularityReach, const [], 0));
  }

  void _stepWells(double dt) {
    if (wells.isEmpty) return;
    for (final w in wells) {
      w.remaining -= dt;
      MergeBody? c;
      for (final b in bodies) {
        if (b.id == w.bodyId) {
          c = b;
          break;
        }
      }
      if (c == null) {
        w.remaining = 0; // merkez govde yok oldu (birlesti / silindi)
        continue;
      }
      for (final b in bodies) {
        if (b.id == c.id) continue;
        final dx = c.x - b.x, dy = c.y - b.y;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 0.001) continue;
        final gap = d - c.r - b.r;
        if (gap > w.reach) continue;
        final f = 1.0 - (gap < 0 ? 0.0 : gap) / w.reach;
        final a = CosmicPowers.singularityAccel * f * dt;
        final ax = dx / d * a;
        var ay = dy / d * a;
        if (ay < 0) ay *= 0.4; // yukari cekimi zayif tut (tehlike cizgisi)
        final ph = b.phys;
        if (ph == null) continue;
        final v = ph.linearVelocity;
        ph.linearVelocity = Vector2(v.x + ax * _k, v.y + ay * _k);
      }
    }
    wells.removeWhere((w) => w.remaining <= 0);
  }

  List<PowerEvent> takePowerEvents() {
    final e = List<PowerEvent>.from(pendingPowerEvents);
    pendingPowerEvents.clear();
    return e;
  }

  void _checkDanger(double dt) {
    var over = false;
    for (final b in bodies) {
      // Yeni birakilan gezegen (age<1.2sn) cizgiyi gecici asabilir.
      if (b.age < 1.2) continue;
      if (b.y - b.r < dangerY) {
        over = true;
        break;
      }
    }
    if (over) {
      dangerTimer += dt;
      if (dangerTimer >= PlanetMergeConfig.dangerSeconds) gameOver = true;
    } else {
      dangerTimer = math.max(0.0, dangerTimer - dt * 2);
    }
  }

  /// "Devam et" odulu: cizgiye en yakin (en ustteki) [count] gezegeni
  /// kaldirir ve game over'i geri alir.
  void rescue({int count = 6}) {
    final byTop = [...bodies]
      ..sort((a, b) => (a.y - a.r).compareTo(b.y - b.r));
    final remove = <int>{};
    for (final b in byTop) {
      if (remove.length >= count) break;
      if (b.locked) continue;
      remove.add(b.id);
    }
    for (final b in bodies) {
      if (remove.contains(b.id)) _phys.destroyBody(b.phys!);
    }
    bodies.removeWhere((b) => remove.contains(b.id));
    dangerTimer = 0;
    gameOver = false;
  }

  /// "Sil" guclendiricisi: (x, y) dunya koordinatindaki gezegeni kaldirir.
  /// Birden fazlasi ust uste ise merkeze en yakin olani secer. Hicbiri yoksa
  /// null doner.
  MergeBody? removeAt(double x, double y) {
    MergeBody? best;
    var bestD = double.infinity;
    for (final b in bodies) {
      if (b.locked) continue;
      final dx = b.x - x, dy = b.y - y;
      final d = math.sqrt(dx * dx + dy * dy);
      // Kucuk gezegenlere parmakla dokunmak zor: hit alanini biraz genislet.
      if (d <= b.r + 2.5 && d < bestD) {
        best = b;
        bestD = d;
      }
    }
    if (best == null) return null;
    final ph = best.phys;
    if (ph != null) _phys.destroyBody(ph);
    bodies.remove(best);
    dangerTimer = 0;
    return best;
  }

  /// "Salla" guclendiricisi: tum gezegenlere kucuk, rastgele bir itme verir
  /// (sikismis yiginlari gevsetir). Tehlike cizgisi icin yeni birakilmis gibi
  /// kisa sure korunurlar (age sifirlanir).
  void shake(math.Random rng) {
    for (final b in bodies) {
      final ph = b.phys;
      if (ph == null || b.locked) continue;
      final vx = (rng.nextDouble() - 0.5) * 80 * _k;
      final vy = -(25 + rng.nextDouble() * 35) * _k;
      final v = ph.linearVelocity;
      ph.linearVelocity = Vector2(v.x + vx, v.y + vy);
      b.age = 0;
    }
    dangerTimer = 0;
  }

  List<MergeEvent> takeEvents() {
    final e = List<MergeEvent>.from(pendingEvents);
    pendingEvents.clear();
    return e;
  }
}
