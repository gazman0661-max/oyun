import 'dart:math';

import 'orbit_models.dart';

/// Bolum numarasina gore Orbit Jam parametrelerini hesaplar ve rastgele
/// (ama her zaman "cozulebilir" — cunku her nesne kendi halkasinda sonsuz
/// donerek er ya da gec kapiya ulasabilir) bir dizilim uretir. Asil zorluk
/// kaynagi cozulup cozulemeyecegi degil, HAMLE/RIHTIM butcesini asmadan
/// cozebilmek.
class OrbitLevelConfig {
  final int stage;
  final int ringCount;
  final List<int> cellsPerRing;
  final int colorCount;
  final int dockCapacity;
  final bool comboEnabled;
  final bool lockedRingEnabled;
  final bool secondLockedRingEnabled;

  OrbitLevelConfig({
    required this.stage,
    required this.ringCount,
    required this.cellsPerRing,
    required this.colorCount,
    required this.dockCapacity,
    required this.comboEnabled,
    required this.lockedRingEnabled,
    required this.secondLockedRingEnabled,
  });

  factory OrbitLevelConfig.forStage(int stage) {
    final safeStage = stage < 1 ? 1 : stage;

    // Halka sayisi: 3'ten baslar, her 3 bolumde bir +1, 6'da tavanlanir.
    var ringCount = 3 + ((safeStage - 1) ~/ 3);
    if (ringCount > 6) ringCount = 6;

    // Renk/gezegen sayisi: 3'ten baslar, her 5 bolumde +1 (NOT: "4 mi 5 mi"
    // tartismasinda 5 seçildi — degistirmek istersen asagidaki "5" sayisini
    // guncelle), tavan 16 (yeni 6 gezegenle birlikte). Bu hiz ile 16'ya
    // ~66. bolumde ulasilir, 25. bolum civarindaki eski "duzlesme" sorununu
    // cozer.
    var colorCount = _colorCountForStage(safeStage);
    if (colorCount > 16) colorCount = 16;

    // Ic halkalar kucuk (az hucre), dis halkalar buyuk — gercek bir
    // gunes sistemi gibi hissettirir.
    final cellsPerRing = List<int>.generate(
      ringCount,
      (i) => 4 + i + min(safeStage ~/ 6, 3),
    );

    // Rihtim (dock) kapasitesi: 3 (1-9) -> 2 (10-49) -> 1 (50+).
    // DUZELTME: eskiden 30. bolumde 1'e dusuyordu; oyuncu geri bildirimine
    // gore rihtimin 1 hucreye inmesi ("tek hata = tikanma") en sert zorluk
    // sicramasiydi ve orta seviyede birakma oranini yukseltiyordu. Simdi
    // 1'e dusus 50'ye ertelendi, boylece oyuncu once 2. kilitli halkaya
    // (40) 2 rihtim hucresiyle alisiyor, "tum zorluklar ayni anda" yigilmasi
    // olmuyor ve toplam ogrenme suresi ~20 bolum uzuyor.
    final dockCapacity = safeStage <= 9 ? 3 : (safeStage <= 49 ? 2 : 1);

    // 10. bolumden itibaren kombo/skor sistemi acik.
    final comboEnabled = safeStage >= 10;
    // 15. bolumden itibaren kilitli halka mekanigi acik.
    final lockedRingEnabled = safeStage >= 15;
    // 40. bolumden itibaren 2. bir halka da kilitli baslar.
    final secondLockedRingEnabled = safeStage >= 40;

    return OrbitLevelConfig(
      stage: safeStage,
      ringCount: ringCount,
      cellsPerRing: cellsPerRing,
      colorCount: colorCount,
      dockCapacity: dockCapacity,
      comboEnabled: comboEnabled,
      lockedRingEnabled: lockedRingEnabled,
      secondLockedRingEnabled: secondLockedRingEnabled,
    );
  }

  static int _colorCountForStage(int stage) {
    // 3'ten baslar, her 5 bolumde +1 renk (bkz. forStage() ustundeki not).
    const step = 5;
    return 3 + ((stage - 1) ~/ step);
  }
}

class OrbitLevelGenerator {
  static OrbitLevel generate(int stage, {Random? random}) {
    final rnd = random ?? Random();
    final cfg = OrbitLevelConfig.forStage(stage);

    // 1) Her halka icin hucreleri rastgele renklerle doldur (bos hucre
    //    birakmiyoruz ki halka "dolu" hissettirsin; bos hucre olmadan da
    //    dondurme her zaman mumkun cunku halka dairesel/kapali bir dongu).
    final rings = <OrbitRing>[];
    final allColors = <int>[];
    for (final cellCount in cfg.cellsPerRing) {
      final cells = List<int>.generate(
        cellCount,
        (_) => rnd.nextInt(cfg.colorCount),
      );
      allColors.addAll(cells);
      rings.add(OrbitRing(cellCount: cellCount, cells: List<int?>.from(cells)));
    }

    // 2) Baslangicta her halkayi rastgele bir miktar "on-donus" ile
    //    karistir (kapida hangi rengin bekledigi de rastgele olsun).
    for (final ring in rings) {
      final spins = rnd.nextInt(ring.cellCount);
      for (var i = 0; i < spins; i++) {
        ring.rotate(clockwise: rnd.nextBool());
      }
    }

    // 3) Hedef kuyrugu: tum nesnelerin rengini karistir. Toplam talep,
    //    toplam arzla birebir esit oldugu icin (ayni renk havuzundan
    //    geliyor) her zaman cozulebilir.
    final targetQueue = List<int>.from(allColors)..shuffle(rnd);

    // 3.5) Kilitli halka (15. bolumden itibaren): rastgele bir halka
    //    (ilk halka haric, boylece oyuncunun elinde her zaman en az bir
    //    acik/kucuk halka kalir) kilitlenir. targetQueue'nun ilk ucte
    //    biri teslim edilene kadar bu halka dondurulemez.
    //    40. bolumden itibaren farkli bir halka daha (ilkinden FARKLI bir
    //    index) ikinci kez kilitlenir; bu ikincisi daha GEC acilir (%60)
    //    ki iki kilit ayni anda acilip bir "rahatlama" hissi yaratmasin.
    if (cfg.lockedRingEnabled && rings.length > 1) {
      final lockIndex = 1 + rnd.nextInt(rings.length - 1);
      rings[lockIndex].locked = true;
      rings[lockIndex].unlockAt = (targetQueue.length * 0.3).ceil();

      if (cfg.secondLockedRingEnabled && rings.length > 2) {
        int secondLockIndex;
        do {
          secondLockIndex = 1 + rnd.nextInt(rings.length - 1);
        } while (secondLockIndex == lockIndex);
        rings[secondLockIndex].locked = true;
        rings[secondLockIndex].unlockAt = (targetQueue.length * 0.6).ceil();
      }
    }

    // 4) Par (referans) hamle sayisi: her nesnenin ortalama olarak kendi
    //    halkasinin yarisi kadar donmesi gerektigini varsayan kaba bir
    //    tahmin, + rihtim yonetimi icin kucuk bir tampon.
    var par = 0;
    for (final ring in rings) {
      par += (ring.cellCount * ring.cellCount / 2).ceil();
    }
    par += (targetQueue.length * 0.5).ceil();

    return OrbitLevel(
      stage: cfg.stage,
      rings: rings,
      targetQueue: targetQueue,
      dockCapacity: cfg.dockCapacity,
      parRotations: par,
      comboEnabled: cfg.comboEnabled,
    );
  }
}
