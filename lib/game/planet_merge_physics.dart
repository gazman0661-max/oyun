import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

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

  /// 0..1 arasi "pop" animasyonu (merge ile olusunca 1'den 0'a iner).
  double pop = 0;

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

  MergeBody drop(int tier, double x) {
    final r = PlanetMergeConfig.radiusOf(tier);
    final cx = x.clamp(r, PlanetMergeConfig.worldW - r).toDouble();
    final b = MergeBody(
      id: _nextId++,
      tier: tier,
      x: cx,
      y: dangerY - r - 2,
      vy: 20,
    );
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
    }
    _processMerges();
    _checkDanger(dt);
  }

  void _processMerges() {
    // Ayni frame'de bir gezegen sadece bir birlesmeye girer.
    final used = <int>{};
    final spawns = <MergeBody>[];
    final n = bodies.length;
    for (var i = 0; i < n; i++) {
      final a = bodies[i];
      if (used.contains(a.id)) continue;
      for (var j = i + 1; j < n; j++) {
        final b = bodies[j];
        if (used.contains(b.id) || a.tier != b.tier) continue;
        final dx = b.x - a.x, dy = b.y - a.y;
        final lim = a.r + b.r + 0.35;
        if (dx * dx + dy * dy > lim * lim) continue;
        used.add(a.id);
        used.add(b.id);
        // Kutle ~ r^2 (esit yogunluk) -> agirlikli merkez.
        final ma = a.r * a.r, mb = b.r * b.r;
        final mx = (a.x * ma + b.x * mb) / (ma + mb);
        final my = (a.y * ma + b.y * mb) / (ma + mb);
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
      if (ph == null) continue;
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
