import 'dart:math';

/// Bolum Modu: sabit, siralı bolumler. Her bolumun hedef gezegeni, birakis
/// siniri ve ENGELLERI vardir:
///
/// - BUZLU gezegen: birlesemez. Yakininda bir birlesme olunca catlar,
///   ikinci birlesmede kirilip normal gezegene doner.
/// - KILITLI gezegen: kabinde sabit durur (duvar gibi). Belirli sayida
///   birlesme yapilinca kilit acilir ve gezegen yercekimine uyar.
///
/// Tum sayilar (hedef, birakis siniri, engel yerleri) TAHMINIDIR; denge icin
/// sadece [LevelCatalog.levels] tablosunu degistirmek yeter.
class IceSpawn {
  final int tier;
  final double x;
  const IceSpawn(this.tier, this.x);
}

class LockSpawn {
  final int tier;
  final double x, y;

  /// Kilidin acilmasi icin gereken birlesme sayisi.
  final int count;
  const LockSpawn(this.tier, this.x, this.y, this.count);
}

enum ObstacleKind { iceCrack, iceBreak, unlock }

/// Dunya -> UI: bir engel degisti (ses/parcacik/yazi icin).
class ObstacleEvent {
  final ObstacleKind kind;
  final double x, y;
  final int tier;
  const ObstacleEvent(this.kind, this.x, this.y, this.tier);
}

class LevelDef {
  final int number;
  final int targetTier;
  final int maxDrops;
  final double dangerY;
  final List<int> dropWeights;

  /// 0 = birakilan gezegenler buzlu olmaz. Aksi halde [iceFrom]. birakistan
  /// baslayarak her [iceEvery] birakista bir gezegen buzlu gelir.
  final int iceEvery;
  final int iceFrom;

  /// Buzun dayanikliligi: kac birlesmede kirilir.
  final int iceHp;

  /// Bolum baslarken kabine konan buzlu gezegenler.
  final List<IceSpawn> startIce;

  /// Bolum baslarken kabine konan kilitli (sabit) gezegenler.
  final List<LockSpawn> locks;

  const LevelDef(
    this.number,
    this.targetTier,
    this.maxDrops, {
    this.dangerY = 24,
    this.dropWeights = LevelCatalog.baseWeights,
    this.iceEvery = 0,
    this.iceFrom = 4,
    this.iceHp = 2,
    this.startIce = const [],
    this.locks = const [],
  });

  int get seed => 900000 + number;

  bool get hasIce => iceEvery > 0 || startIce.isNotEmpty;
  bool get hasLocks => locks.isNotEmpty;

  /// Bolum girisinde gosterilen kural metni (yerellestirme anahtari).
  String get ruleKey {
    if (hasIce && hasLocks) return 'lv_rule_both';
    if (hasIce) return 'lv_rule_ice';
    if (hasLocks) return 'lv_rule_lock';
    return 'lv_rule_plain';
  }

  /// [dropNumber] (1'den baslar) numarali birakilan gezegen buzlu mu?
  bool isIceDrop(int dropNumber) =>
      iceEvery > 0 &&
      dropNumber >= iceFrom &&
      (dropNumber - iceFrom) % iceEvery == 0;

  /// 3 yildiz icin "par" birakis sayisi (limitin %75'i).
  int get parDrops => (maxDrops * 0.75).ceil();
}

class _Slot {
  final double x;

  /// null = kabin tabani (govde zemine oturur), aksi halde havada sabit y.
  final double? y;
  const _Slot(this.x, this.y);
}

class LevelCatalog {
  LevelCatalog._();

  static const List<int> baseWeights = [40, 28, 18, 10, 4];

  /// Elle tasarlanan bolum sayisi ([levels] tablosu).
  static int get handmade => levels.length;

  /// Bu bolumden itibaren zorluk SABIT kalir (sonsuz bolumler hep ayni
  /// zorlukta, sadece yerlesimler farkli).
  static const int rampEnd = 100;

  static final Map<int, LevelDef> _cache = {};

  /// Bolum [n]: ilk [handmade] tanesi tablodan, sonrasi n'ye gore
  /// DETERMINISTIK uretilir (herkeste ayni bolum ayni gelir).
  static LevelDef level(int n) {
    final no = n < 1 ? 1 : n;
    if (no <= levels.length) return levels[no - 1];
    return _cache.putIfAbsent(no, () => _generate(no));
  }

  /// 0 (elle yapilan son bolum) .. 1 ([rampEnd] ve sonrasi), yumusak gecis.
  static double difficulty(int n) {
    final t = ((n - levels.length) / (rampEnd - levels.length))
        .clamp(0.0, 1.0)
        .toDouble();
    return t * t * (3 - 2 * t);
  }

  static double _avgValue(List<int> w) {
    var total = 0;
    var sum = 0.0;
    for (var i = 0; i < w.length; i++) {
      total += w[i];
      sum += w[i] * pow(2, i).toDouble();
    }
    return sum / total;
  }

  static const List<_Slot> _slots = [
    _Slot(24, null),
    _Slot(76, null),
    _Slot(50, 104),
    _Slot(28, 100),
    _Slot(72, 100),
  ];

  /// Sonsuz bolum ureteci. Her 10. bolum "usta bolumu" (agir gezegenler,
  /// bir kademe buyuk hedef, 3 canli buz). Denge ayarlari: asagidaki sayilar.
  static LevelDef _generate(int n) {
    final rng = Random(n * 7919 + 13);
    final d = difficulty(n);
    final boss = n % 10 == 0;
    final heavy = boss || rng.nextDouble() < 0.15;
    final weights = heavy ? const [0, 30, 30, 22, 12, 6] : baseWeights;

    // Hedef: 6 -> 8 (usta bolumunde +1, en fazla 9).
    var target = 6 + (d * 2).round();
    if (boss) target = min(9, target + 1);

    // Buz.
    final useIce = rng.nextDouble() < 0.45 + 0.4 * d;
    final iceEvery = useIce ? 9 - (4 * d).round() : 0; // 9 .. 5
    final iceFrom = 4 + rng.nextInt(3);
    final iceHp = (boss && d > 0.5) ? 3 : 2;
    final startIceN = rng.nextInt(2 + (2 * d).round()); // 0 .. 3
    final startIce = <IceSpawn>[];
    for (var k = 0; k < startIceN; k++) {
      final x = 18 + (64 / (startIceN + 1)) * (k + 1) + (rng.nextDouble() - 0.5) * 8;
      startIce.add(IceSpawn(1 + rng.nextInt(3), x));
    }

    // Kilitler.
    final wantLocks = rng.nextDouble() < 0.4 + 0.45 * d;
    final lockN =
        wantLocks ? min(3, 1 + rng.nextInt(2 + (2 * d).round())) : 0;
    final locks = <LockSpawn>[];
    final slots = List<_Slot>.from(_slots)..shuffle(rng);
    var air = 0;
    for (final sl in slots) {
      if (locks.length >= lockN) break;
      final yAir = sl.y;
      if (yAir != null) {
        if (air >= 2) continue;
        air++;
      }
      final tier = yAir == null ? 5 + rng.nextInt(3) : 5 + rng.nextInt(2);
      final r = 4.2 * pow(1.2, tier).toDouble();
      final y = yAir ?? (150 - r - 1.5);
      final count = 4 + rng.nextInt(2 + (3 * d).round());
      locks.add(LockSpawn(tier, sl.x, y, count));
    }

    // Tehlike cizgisi (kabin daralir).
    final danger = (d > 0.15 && rng.nextDouble() < 0.4)
        ? 24.0 + 6 * (1 + rng.nextInt(1 + (2 * d).round()))
        : 24.0;

    // Birakis sinirı: hedef degerini gereken verimliliğe bol; engel basina
    // biraz ek hak.
    final eff = 0.50 + 0.13 * d + (boss ? 0.03 : 0.0);
    var drops = (pow(2, target).toDouble() / (_avgValue(weights) * eff)).ceil();
    drops += lockN * 3 + startIceN * 2;
    drops = max(20, drops);

    return LevelDef(
      n,
      target,
      drops,
      dangerY: danger,
      dropWeights: weights,
      iceEvery: iceEvery,
      iceFrom: iceFrom,
      iceHp: iceHp,
      startIce: startIce,
      locks: locks,
    );
  }

  static const List<LevelDef> levels = [
    // 1-5: temel (engel yok), hedef giderek buyur.
    LevelDef(1, 4, 20),
    LevelDef(2, 4, 16),
    LevelDef(3, 5, 26),
    LevelDef(4, 5, 24),
    LevelDef(5, 6, 40),
    // 6-8: buz tanitimi.
    LevelDef(6, 5, 28, iceEvery: 7, iceFrom: 4),
    LevelDef(7, 6, 42, iceEvery: 6, iceFrom: 4),
    LevelDef(8, 6, 40,
        iceEvery: 8, iceFrom: 3, startIce: [IceSpawn(1, 28), IceSpawn(2, 72)]),
    // 9-11: kilit tanitimi ve ilk karisim.
    LevelDef(9, 5, 28, locks: [LockSpawn(5, 50, 100, 4)]),
    LevelDef(10, 6, 40, locks: [
      LockSpawn(6, 24, 136, 5),
      LockSpawn(6, 76, 136, 5),
    ]),
    LevelDef(11, 6, 42,
        iceEvery: 7, iceFrom: 4, locks: [LockSpawn(5, 50, 104, 6)]),
    // 12-16: zorlasan karisimlar.
    LevelDef(12, 7, 84, dangerY: 36),
    LevelDef(13, 6, 40, iceEvery: 5, iceFrom: 4),
    LevelDef(14, 7, 80,
        startIce: [IceSpawn(2, 30), IceSpawn(3, 70)],
        locks: [LockSpawn(6, 50, 110, 6)]),
    LevelDef(15, 6, 40, dangerY: 40, locks: [
      LockSpawn(5, 28, 100, 4),
      LockSpawn(5, 72, 100, 4),
    ]),
    LevelDef(16, 7, 78, dangerY: 30, iceEvery: 6, iceFrom: 5),
    // 17-20: usta bolumleri.
    LevelDef(17, 7, 78,
        iceEvery: 8, iceFrom: 5, locks: [LockSpawn(7, 50, 133, 7)]),
    LevelDef(18, 7, 76,
        startIce: [IceSpawn(1, 20), IceSpawn(2, 50), IceSpawn(3, 80)],
        locks: [LockSpawn(5, 30, 100, 5), LockSpawn(5, 70, 100, 5)]),
    LevelDef(19, 8, 140,
        iceEvery: 7, iceFrom: 5, locks: [LockSpawn(6, 50, 108, 8)]),
    LevelDef(20, 8, 130,
        dangerY: 30,
        iceEvery: 6,
        iceFrom: 5,
        startIce: [IceSpawn(2, 30), IceSpawn(2, 70)],
        locks: [LockSpawn(6, 26, 136, 6), LockSpawn(6, 74, 136, 6)]),
  ];
}
