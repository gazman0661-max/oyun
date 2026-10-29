import 'dart:math';

/// YEDEK (kullanilmiyor): forge2d'ye gecmeden onceki, bagimliliksiz kendi
/// daire fizigimiz. forge2d ile sorun yasanirsa planet_merge_screen.dart
/// icindeki import'u bu dosyaya cevirmek yeterli (sinif adlari ayni).
///
/// Gezegen Birlestir (Suika tarzi) modunun saf-Dart 2D daire fizigi.
///
/// Harici fizik paketi (forge2d vb.) KULLANILMIYOR: sadece daire-daire ve
/// daire-duvar carpismasi gerektigi icin kucuk, bagimsiz ve deterministik
/// bir cozucu yeterli. Dunya birimleri: genislik [worldW], yukseklik
/// [worldH]; y asagi dogru artar (Flutter canvas gibi).
class MergeBody {
  final int id;
  int tier;
  double x, y, vx, vy;

  /// Olusturulduktan sonra gecen sure (sn) — game over kontrolunde
  /// "yeni birakilan" gezegeni saymamak ve merge pop animasyonu icin.
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
  double get mass => r * r;
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
    return base * pow(1.2, tier).toDouble();
  }

  /// Kademe t olusunca eklenen puan (1,3,6,10,...).
  static int pointsForTier(int tier) => (tier + 1) * (tier + 2) ~/ 2;

  /// Iki Gunes birlesince yok olur: buyuk bonus.
  static const int sunVanishBonus = 150;
}

class PlanetMergeWorld {
  /// Tehlike cizgisinin y konumu (meydan okuma modlarinda degisebilir).
  final double dangerY;

  // gravity/restitution: forge2d surumuyle ayni imza icin; burada kullanilmaz.
  PlanetMergeWorld({
    this.dangerY = PlanetMergeConfig.dangerY,
    double gravity = 0,
    double restitution = 0,
  });

  final List<MergeBody> bodies = [];
  final List<MergeEvent> pendingEvents = [];
  int _nextId = 1;

  int score = 0;
  int bestTier = 0;
  bool gameOver = false;

  /// Cizginin ustunde kesintisiz kalma suresi (en kotu gezegenin).
  double dangerTimer = 0;

  static const double _gravity = 150; // birim/sn^2
  static const int _subSteps = 4;
  static const int _iterations = 3;
  static const double _restitution = 0.05;
  static const double _wallFriction = 0.985;
  static const double _damping = 0.9995;

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
    bodies.add(b);
    if (tier > bestTier) bestTier = tier;
    return b;
  }

  /// [dt] saniye ilerletir (UI her frame cagirir; icerde alt-adimlara boler).
  void step(double dt) {
    if (gameOver) return;
    if (dt > 0.05) dt = 0.05; // uzun frame'de patlamayi onle
    final h = dt / _subSteps;
    for (var s = 0; s < _subSteps; s++) {
      for (final b in bodies) {
        b.vy += _gravity * h;
        b.vx *= _damping;
        b.vy *= _damping;
        b.x += b.vx * h;
        b.y += b.vy * h;
      }
      for (var it = 0; it < _iterations; it++) {
        _resolveWalls();
        _resolveCircles();
      }
    }
    for (final b in bodies) {
      b.age += dt;
      if (b.pop > 0) b.pop = max(0.0, b.pop - dt * 4);
    }
    _processMerges();
    _checkDanger(dt);
  }

  void _resolveWalls() {
    const w = PlanetMergeConfig.worldW;
    const hgt = PlanetMergeConfig.worldH;
    for (final b in bodies) {
      final r = b.r;
      if (b.x < r) {
        b.x = r;
        if (b.vx < 0) b.vx = -b.vx * _restitution;
        b.vy *= _wallFriction;
      } else if (b.x > w - r) {
        b.x = w - r;
        if (b.vx > 0) b.vx = -b.vx * _restitution;
        b.vy *= _wallFriction;
      }
      if (b.y > hgt - r) {
        b.y = hgt - r;
        if (b.vy > 0) b.vy = -b.vy * _restitution;
        b.vx *= _wallFriction;
      }
    }
  }

  void _resolveCircles() {
    final n = bodies.length;
    for (var i = 0; i < n; i++) {
      final a = bodies[i];
      for (var j = i + 1; j < n; j++) {
        final b = bodies[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final minD = a.r + b.r;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minD * minD) continue;
        var d = sqrt(d2);
        double nx, ny;
        if (d < 1e-6) {
          nx = 0;
          ny = -1;
          d = 0;
        } else {
          nx = dx / d;
          ny = dy / d;
        }
        final overlap = minD - d;
        final ma = a.mass, mb = b.mass;
        final inv = 1 / (ma + mb);
        // Konum duzeltmesi: hafif olan daha cok kayar.
        a.x -= nx * overlap * (mb * inv);
        a.y -= ny * overlap * (mb * inv);
        b.x += nx * overlap * (ma * inv);
        b.y += ny * overlap * (ma * inv);
        // Hiz duzeltmesi (normal bilesen).
        final rvx = b.vx - a.vx;
        final rvy = b.vy - a.vy;
        final vn = rvx * nx + rvy * ny;
        if (vn < 0) {
          final jImp = -(1 + _restitution) * vn / (1 / ma + 1 / mb);
          a.vx -= jImp * nx / ma;
          a.vy -= jImp * ny / ma;
          b.vx += jImp * nx / mb;
          b.vy += jImp * ny / mb;
        }
      }
    }
  }

  void _processMerges() {
    // Ayni frame'de bir gezegen sadece bir birlesmeye girer.
    final used = <int>{};
    final toRemove = <MergeBody>[];
    final toAdd = <MergeBody>[];
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
        toRemove..add(a)..add(b);
        final mx = (a.x * a.mass + b.x * b.mass) / (a.mass + b.mass);
        final my = (a.y * a.mass + b.y * b.mass) / (a.mass + b.mass);
        if (a.tier >= PlanetMergeConfig.tierCount - 1) {
          // Iki Karanlik Kutle: yok olur, buyuk bonus.
          const pts = PlanetMergeConfig.sunVanishBonus;
          score += pts;
          pendingEvents.add(MergeEvent(-1, mx, my, pts));
        } else {
          final t = a.tier + 1;
          final pts = PlanetMergeConfig.pointsForTier(t);
          score += pts;
          if (t > bestTier) bestTier = t;
          toAdd.add(MergeBody(
            id: _nextId++,
            tier: t,
            x: mx,
            y: my,
            vx: (a.vx + b.vx) / 2,
            vy: (a.vy + b.vy) / 2,
          )
            ..pop = 1
            ..age = 10); // yeni olusan "yeni birakilmis" sayilmaz
          pendingEvents.add(MergeEvent(t, mx, my, pts));
        }
        break;
      }
    }
    if (toRemove.isNotEmpty) {
      bodies.removeWhere((b) => used.contains(b.id));
      bodies.addAll(toAdd);
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
      dangerTimer = max(0.0, dangerTimer - dt * 2);
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
    bodies.removeWhere((b) => remove.contains(b.id));
    dangerTimer = 0;
    gameOver = false;
  }

  /// "Sil" guclendiricisi (bkz. planet_merge_physics.dart).
  MergeBody? removeAt(double x, double y) {
    MergeBody? best;
    var bestD = double.infinity;
    for (final b in bodies) {
      final dx = b.x - x, dy = b.y - y;
      final d = sqrt(dx * dx + dy * dy);
      if (d <= b.r + 2.5 && d < bestD) {
        best = b;
        bestD = d;
      }
    }
    if (best == null) return null;
    bodies.remove(best);
    dangerTimer = 0;
    return best;
  }

  /// "Salla" guclendiricisi (bkz. planet_merge_physics.dart).
  void shake(Random rng) {
    for (final b in bodies) {
      b.vx += (rng.nextDouble() - 0.5) * 80;
      b.vy += -(25 + rng.nextDouble() * 35);
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
