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
  final int peekDepth;

  OrbitLevelConfig({
    required this.stage,
    required this.ringCount,
    required this.cellsPerRing,
    required this.colorCount,
    required this.dockCapacity,
    required this.comboEnabled,
    required this.lockedRingEnabled,
    required this.secondLockedRingEnabled,
    required this.peekDepth,
  });

  factory OrbitLevelConfig.forStage(int stage) {
    final safeStage = stage < 1 ? 1 : stage;

    // Halka sayisi: 3'ten baslar, her 3 bolumde bir +1, 6'da tavanlanir.
    // ONBOARDING DUZELTMESI: 1. ve 2. bolum ozel olarak 1 ve 2 halkaya
    // INDIRILDI (once formul hep 3'ten basliyordu — piyasada hic
    // benzeri olmayan bu mekanigi ilk acilista 3 donen halka + kapi +
    // rihtim kuyrugu ile birden karsilastirmak, "first_open var ama
    // level_start yok" seklindeki erken birakma riskini artiriyordu).
    // 3. bolumden itibaren eski egriye (3 halka) sorunsuz baglaniyor,
    // sonraki hicbir esik/zorluk hesaplamasi etkilenmiyor.
    int ringCount;
    if (safeStage == 1) {
      ringCount = 1;
    } else if (safeStage == 2) {
      ringCount = 2;
    } else {
      ringCount = 3 + ((safeStage - 1) ~/ 3);
      if (ringCount > 6) ringCount = 6;
    }

    // Renk/gezegen sayisi: 3'ten baslar, her 7 bolumde +1 (ONCEDEN 5'ti).
    // SIMULASYON BULGUSU: gercek uretici+controller mantigi Python'a
    // tasinip "iyi oynayan" bir bot ile yuzlerce tahta denendi. 5'lik adimda
    // renk sayisi rihtim kapasitesinden BAGIMSIZ, sadece zamana gore artan
    // dock ile cakisip stage ~14-20 arasinda kazanma oranini pratikte SIFIRA
    // dusuruyordu (best-of-5 deneme bile stage 16'da %0-4). 7'lik adimla
    // tavan (16) daha gec (~92. bolum) gelse de, asil onemlisi asagidaki
    // dockCapacity artik renk sayisiyla BIRLIKTE olculuyor.
    var colorCount = _colorCountForStage(safeStage);
    if (colorCount > 16) colorCount = 16;

    // Ic halkalar kucuk (az hucre), dis halkalar buyuk — gercek bir
    // gunes sistemi gibi hissettirir.
    final cellsPerRing = List<int>.generate(
      ringCount,
      (i) => 4 + i + min(safeStage ~/ 6, 3),
    );

    // Rihtim (dock) kapasitesi: ONCEDEN SADECE renk sayisina gore
    // olceklendiriliyordu (colorCount - 1), halka sayisindan tamamen
    // BAGIMSIZDI. SIMULASYON BULGUSU (guncel, kilit-bug duzeltmesinden
    // SONRA tekrar kosuldu): asil darbogaz hic kilit degilmis — 6 halka
    // ayni anda donerken (stage ~16'dan itibaren tavan) oyuncu her
    // halkada sadece TEK adim ileri gorebiliyor (_peekIncoming), yani
    // her donusun buyuk kismi rihtime gidiyor. Dock sadece renge gore
    // buyuyunce, halka sayisi 6'ya tavanlanir tavanlanmaz dock rolatif
    // olarak KUCULMUS oluyordu — best-of-5 kazanma orani stage 7-8
    // civarinda cokup stage 12+'de %0'a kilitleniyordu (kilit mekanigi
    // 15'e kadar hic devrede degilken bile). Simdi dock, HEM halka
    // sayisina HEM renk sayisina gore birlikte olceklendiriliyor (ikisi
    // de zorlugu ayni anda artiran faktorler). Ayni simulasyonda bu
    // degisiklik stage 3-25 araligindaki best-of-5 kazanma oranini
    // belirgin sekilde yukselti (orn. stage 10: ~%4 -> ~%80, stage 20:
    // ~%0 -> ~%43). Cok ileri bolumlerde (40+) simulasyon bulgulari
    // bot kalitesi sinirlamasi yuzunden kesin degil (bkz. proje notlari,
    // ayri bir "peek derinligi" iyilestirmesiyle ele alinmasi planlaniyor)
    // ama en kritik erken/orta oyun penceresinde net bir iyilesme var.
    var dockCapacity = (ringCount * 0.7 + colorCount * 0.9).round() + 2;
    if (dockCapacity < 3) dockCapacity = 3;

    // 10. bolumden itibaren kombo/skor sistemi acik.
    final comboEnabled = safeStage >= 10;
    // 15. bolumden itibaren kilitli halka mekanigi acik.
    final lockedRingEnabled = safeStage >= 15;
    // 40. bolumden itibaren 2. bir halka da kilitli baslar.
    final secondLockedRingEnabled = safeStage >= 40;

    // Peek derinligi: kac halka + kac renk varken oyuncu hala sadece
    // TEK adim ileri gorebiliyordu (bkz. OrbitRing.peekAhead). Halka
    // sayisi stage ~16'da 6'ya tavanlanip renk cesitliligi (16'ya kadar)
    // artmaya devam ederken bu "korluk" giderek daha cezalandirici hale
    // geliyordu (bkz. dockCapacity notundaki simulasyon bulgusu — stage
    // 30+'ta hala zorlu kalan kisim). Peek derinligini kademeli artirarak
    // oyuncuya birden fazla adim ileriyi (bkz. previewRing) gosterip daha
    // bilgili/planli hamleler yapmasini sagliyoruz.
    final peekDepth = _peekDepthForStage(safeStage);

    return OrbitLevelConfig(
      stage: safeStage,
      ringCount: ringCount,
      cellsPerRing: cellsPerRing,
      colorCount: colorCount,
      dockCapacity: dockCapacity,
      comboEnabled: comboEnabled,
      lockedRingEnabled: lockedRingEnabled,
      secondLockedRingEnabled: secondLockedRingEnabled,
      peekDepth: peekDepth,
    );
  }

  static int _peekDepthForStage(int stage) {
    // 1-14: halka sayisi hala kucuk (<=5), tek adimlik gorus yeterince
    //       oynanabilir (bkz. simulasyon: bu araliktaki dusus dock
    //       kapasitesi kaynakliydi, dockCapacity fix'iyle zaten cozuldu).
    // 15-39: halka sayisi 6'ya tavanlanmis, kilitli halka mekanigi de
    //        devrede — 2 adim ileri gorus.
    // 40+: renk cesitliligi (16'ya kadar) ve ikinci kilitli halka da
    //      eklenince en zor pencere — 3 adim ileri gorus.
    if (stage < 15) return 1;
    if (stage < 40) return 2;
    return 3;
  }

  static int _colorCountForStage(int stage) {
    // 3'ten baslar, her 7 bolumde +1 renk (bkz. forStage() ustundeki not;
    // ONCEDEN 5'ti, simulasyon bulgusuyla 7'ye cekildi).
    const step = 7;
    return 3 + ((stage - 1) ~/ step);
  }
}

class OrbitLevelGenerator {
  /// Kilitli halka(lar)daki her rengin en az bir kopyasinin kilitsiz bir
  /// halkada da bulunmasini garanti eder. Boyle degilse, o rengi "tuzaga
  /// dusmus" kilitli hucreyle kilitsiz bir hucrenin DEGERLERINI takas eder
  /// (silmez/eklemez — toplam renk sayilari degismez, sadece hangi hucrede
  /// oldugu degisir).
  ///
  /// KOK NEDEN DUZELTMESI (v2 — onceki rastgele-swap yaklasiminin yerine):
  /// Eski versiyon donor hucreyi TAMAMEN RASTGELE seciyordu. Bu, tuzaga
  /// dusmus rengi (Y) kilitsiz tarafa tasirken, donor hucredeki rengin (X)
  /// kilitli tarafa gitmesine yol aciyordu — eger X'in kilitsiz taraftaki
  /// TEK kopyasi tam o donor hucreydiyse, X simdi YENI bir tuzak haline
  /// geliyordu. Rastgelelik yuzunden bu bazen ayni ciftin ileri-geri
  /// sallanmasina (ping-pong) yol acabiliyordu; maxPasses=200 sadece bir
  /// guvenlik tavaniydi, yakinsama MATEMATIKSEL olarak garanti degildi —
  /// bazi board'larda (ozellikle çok sayida "tekil" renk varken) 200
  /// pass icinde tam temizlenmeyebiliyordu, bu da runtime force-unlock
  /// guvenlik agini (bkz. OrbitController._checkJam) beklenenden sik
  /// tetikliyordu.
  ///
  /// Yeni yaklasim TEK GECISTE, RASTGELELIK OLMADAN biter: donor hucre
  /// HER ZAMAN kilitsiz tarafta rengi >=2 kopya bulunan bir hucreden
  /// secilir. Boylece donor rengi kilitli tarafa tasindiginda bile
  /// kilitsiz tarafta en az 1 kopyasi KALIR — yani takas asla yeni bir
  /// tuzak yaratmaz. Kanit: her adimda "kilitsiz tarafta >=1 kopyasi olan
  /// her renk erisilebilir kalir" degismezi (invariant) korunur; her
  /// locked hucre en fazla bir kez islenir, dolayisiyla toplam islem
  /// sayisi kilitli hucre sayisiyla sinirlidir (dongu/tekrar yok).
  ///
  /// Sadece asiri nadir bir durumda (kilitsiz taraftaki TUM renkler
  /// tekil — yani hicbir renk 2+ kopyaya sahip degil) guvenli bir donor
  /// bulunamaz; bu durumda eski davranisa (rastgele donor) geri duser.
  /// Bu son derece nadir kenar durum icin runtime force-unlock guvenlik
  /// agi zaten devrede kaliyor.
  static void _ensureLockedColorsReachable(List<OrbitRing> rings, Random rnd) {
    final lockedRings = rings.where((r) => r.locked).toList();
    if (lockedRings.isEmpty) return;
    final unlockedRings = rings.where((r) => !r.locked).toList();
    if (unlockedRings.isEmpty) return; // olmamali (rings.length>1 garantili) ama guvenlik icin

    // Kilitsiz taraftaki her rengin kac kopyasi oldugunu tut — donor
    // secerken ve degismezi korurken bu sayaci canli guncelleriz.
    final unlockedColorCounts = <int, int>{};
    for (final r in unlockedRings) {
      for (final c in r.cells) {
        if (c != null) {
          unlockedColorCounts[c] = (unlockedColorCounts[c] ?? 0) + 1;
        }
      }
    }

    for (final r in lockedRings) {
      for (var i = 0; i < r.cells.length; i++) {
        final trapped = r.cells[i];
        if (trapped == null) continue;
        if ((unlockedColorCounts[trapped] ?? 0) > 0) {
          continue; // bu renk zaten kilitsiz tarafta erisilebilir
        }

        // Guvenli donor ara: kilitsiz tarafta >=2 kopyasi olan bir renk
        // tutan hucre. Boyle bir hucreyi tuzaga dusmus renkle takas
        // etmek, donor rengini kilitsiz tarafta >=1 kopyayla birakir —
        // yani YENI bir tuzak yaratmaz.
        OrbitRing? donorRing;
        int? donorIndex;
        outer:
        for (final ur in unlockedRings) {
          for (var j = 0; j < ur.cells.length; j++) {
            final c = ur.cells[j];
            if (c != null && (unlockedColorCounts[c] ?? 0) >= 2) {
              donorRing = ur;
              donorIndex = j;
              break outer;
            }
          }
        }

        // Asiri nadir dusme durumu: kilitsiz tarafta hicbir renk 2+
        // kopyaya sahip degil (hepsi tekil). Bu durumda guvenli bir
        // donor yapisal olarak yok — eski (rastgele) davranisa don.
        // Runtime force-unlock guvenlik agi bu kenar durumu zaten kapsar.
        donorRing ??= unlockedRings[rnd.nextInt(unlockedRings.length)];
        donorIndex ??= rnd.nextInt(donorRing.cells.length);

        final donorColor = donorRing.cells[donorIndex];

        // Takas: tuzaga dusmus renk kilitsiz tarafa cikar, donor rengi
        // kilitli tarafa gider.
        donorRing.cells[donorIndex] = trapped;
        r.cells[i] = donorColor;

        // Sayaclari guncelle: trapped artik kilitsiz tarafta +1 oldu.
        unlockedColorCounts[trapped] = (unlockedColorCounts[trapped] ?? 0) + 1;
        if (donorColor != null) {
          final remaining = (unlockedColorCounts[donorColor] ?? 1) - 1;
          if (remaining <= 0) {
            unlockedColorCounts.remove(donorColor);
          } else {
            unlockedColorCounts[donorColor] = remaining;
          }
        }
      }
    }
  }

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
        // ONCEDEN 0.6 idi: iki halka cok uzun sure birlikte kilitli kaliyor,
        // dock'un hala dar oldugu bir donemle cakisiyordu. 0.45'e cekildi -
        // hala ilkinden (0.3) sonra aciliyor ("art arda", ayni anda degil)
        // ama toplam "iki kilit birden" penceresi kisaliyor.
        rings[secondLockIndex].unlockAt = (targetQueue.length * 0.45).ceil();
      }

      // BUG DUZELTMESI (kritik): kilitli halka(lar)a konan bir renk, o an
      // KILITSIZ hicbir halkada bulunmuyorsa, o rengin kalan kopyalari
      // erken oynanista tuketilir tuketilmez talep edilen renk artik
      // SADECE kilitli halkanin icinde kalir. targetCursor bu rengi
      // teslim edemedigi icin ilerlemez, kilit ACILMAZ, tahta matematiksel
      // olarak kazanilamaz hale gelir (simulasyonla dogrulandi). Duzeltme:
      // kilitler atandiktan hemen sonra, kilitli halka(lar)daki her rengin
      // en az bir kopyasinin kilitsiz bir halkada da bulunmasini garanti
      // altina al (toplam renk dagilimini bozmadan, sadece hucre DEGERLERI
      // takas edilerek).
      _ensureLockedColorsReachable(rings, rnd);
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
      peekDepth: cfg.peekDepth,
    );
  }
}
