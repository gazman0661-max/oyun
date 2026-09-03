import 'dart:math';

import 'package:flutter/foundation.dart';

import 'orbit_level_generator.dart';
import 'orbit_models.dart';

enum OrbitStatus { playing, won, jammed }

/// Bir gezegenin halkanin kapisindan CIKTIGI anı temsil eder. UI (OrbitBoard)
/// bunu dinleyerek gezegenin kapidan hedefine (teslim edildiyse yukari,
/// rihtima gittiyse asagi) SUZULEREK gitmesini saglayan kisa bir animasyon
/// baslatir; ayni zamanda uygun ses efektini calmak icin de kullanilir.
/// [id] her cikista bir artar, boylece ayni renk/halka tekrar etse bile
/// UI yeni bir olay oldugunu ayirt edebilir.
class OrbitExitEvent {
  final int id;
  final int ringIndex;
  final int colorIndex;
  final bool matched;

  const OrbitExitEvent({
    required this.id,
    required this.ringIndex,
    required this.colorIndex,
    required this.matched,
  });
}

/// Orbit Jam'in tum canli oyun durumunu tutan ve UI'a bildiren controller.
///
/// Akis:
/// 1. Oyuncu bir halkayi saga/sola dondurur (1 hamle).
/// 2. Halkanin kapi hucresine (index 0) gelen nesne varsa disari cikar:
///    - Rengi o anki hedefle (targetQueue'nun basi) eslesiyorsa DOGRUDAN
///      teslim edilir, hedef kuyrugu ilerler ve rihtimdeki bekleyenler
///      arasinda yeni hedefle eslesen olursa zincirleme teslim olur.
///    - Eslesmiyorsa rihtime (dock) konur; rihtim doluysa o donus GERI
///      alinir (blokaj) — oyuncu baska bir halka denemek zorunda kalir.
/// 3. Tum nesneler teslim edilince kazanilir. Hicbir yasal donus rihtimi
///    bosaltamiyorsa ve tahta hala doluysa "sikisma" (jam) ile kaybedilir.
class OrbitController extends ChangeNotifier {
  OrbitLevel level;
  final List<int?> dock;
  int targetCursor = 0;
  int rotations = 0;
  OrbitStatus status = OrbitStatus.playing;

  /// Kombo/skor sistemi (10. bölümden itibaren aktif — bkz.
  /// [OrbitLevel.comboEnabled]). Art arda DOĞRUDAN teslimat (rıhtıma
  /// hiç uğramadan) kombo sayacını artırır, her artan kombo bir öncekine
  /// göre daha fazla puan katar; rıhtıma giden (eşleşmeyen) bir nesne
  /// komboyu sıfırlar.
  int score = 0;
  int combo = 0;
  int bestCombo = 0;

  /// Son kilidi açılan halkanın index'i — UI'da kısa bir "açıldı"
  /// bildirimi/animasyonu tetiklemek icin (bkz. [OrbitExitEvent] ile
  /// ayni fikir). null ise henuz/az once bir acilma olmadi.
  int? lastUnlockedRing;

  /// Son kilitli halkaya dokunulup bloke edilen deneme — UI'da "hala
  /// kilitli" sarsilma/uyari geri bildirimi icin.
  int? lastLockedRingAttempt;

  /// Son basarisiz (bloke edilen) donus denemesinin halka indeksi — UI'da
  /// kisa bir "sarsilma" animasyonu tetiklemek icin kullanilabilir.
  int? lastBlockedRing;

  /// Son kapidan cikan nesne hakkinda bilgi — UI'da "suzulme" (glide)
  /// animasyonu ve ses efekti tetiklemek icin kullanilir. bkz. [OrbitExitEvent].
  OrbitExitEvent? lastExit;
  int _exitEventCounter = 0;

  /// Son hamleden ONCEKI tam durumun anlik goruntusu — "hamleyi geri al"
  /// icin. Tek seviyeli (sadece SON hamle geri alinabilir, daha eskisi
  /// degil); her yeni basarili donusde bir onceki snapshot'in uzerine
  /// yazilir. bkz. [undoLastMove]/[canUndo].
  _OrbitSnapshot? _undoSnapshot;

  /// Su an geri alinabilecek bir hamle var mi (ve oyun bitmemis mi).
  bool get canUndo => _undoSnapshot != null && status != OrbitStatus.won;

  OrbitController(this.level)
      : dock = List<int?>.filled(level.dockCapacity, null, growable: true);

  factory OrbitController.forStage(int stage, {Random? random}) {
    return OrbitController(OrbitLevelGenerator.generate(stage, random: random));
  }

  /// Gunluk gorev icin: herkese ayni gun ayni bulmacayi vermek uzere sabit
  /// bir tohum (seed) ile uretilir. Zorluk, gunden gune hafifce degissin
  /// diye gunluk numaraya gore 4-7 bolum araliginda bir "sanal bolum"
  /// kullanilir (ama ilerlemeyi etkilemez, sadece zorluk parametresidir).
  factory OrbitController.daily({required int dailyNumber, required int seed}) {
    final virtualStage = 4 + (dailyNumber % 4);
    return OrbitController(
      OrbitLevelGenerator.generate(virtualStage, random: Random(seed)),
    );
  }

  /// Kuyruklu Yıldız (Comet Event) icin: herkese ayni pencerede ayni ozel
  /// tahtayi vermek uzere event numarasina sabit bir tohumla uretilir
  /// (bkz. PlayerProgress.cometEventNumber). Normal gunluk bulmacadan
  /// daha zorlu hissettirmesi icin daha yuksek bir "sanal bolum" araligi
  /// kullanilir (12-17: kombo/skor her zaman acik, bazen kilitli halka
  /// da var) — "event" ozel hissi icin.
  factory OrbitController.cometEvent(int eventNumber) {
    final virtualStage = 12 + (eventNumber % 6);
    return OrbitController(
      OrbitLevelGenerator.generate(
        virtualStage,
        random: Random(900000 + eventNumber),
      ),
    );
  }

  /// Odullu reklam sonrasi cagrilir: rihtime +1 bos yuva ekler. Oyun
  /// sikismis (jammed) haldeyse, yeni yer acildigi icin oyuna kaldigi
  /// yerden devam edilebilir hale getirir.
  void expandDock() {
    dock.add(null);
    if (status == OrbitStatus.jammed) {
      status = OrbitStatus.playing;
    }
    notifyListeners();
  }

  int? get currentTarget =>
      targetCursor < level.targetQueue.length ? level.targetQueue[targetCursor] : null;

  /// Sonraki birkac hedefi HUD'da onizleme olarak gostermek icin.
  List<int> upcomingTargets(int count) {
    final end = min(targetCursor + count, level.targetQueue.length);
    return level.targetQueue.sublist(targetCursor, end);
  }

  /// [ringIndex] halkasi icin [clockwise] yonde art arda yapilacak
  /// donuslerin kapiya SIRAYLA getirecegi degerleri, halkayi fiilen
  /// dondurmeden onizler (bkz. [OrbitRing.peekAhead]). [depth]
  /// belirtilmezse seviyenin kendi "peek derinligi" kullanilir
  /// (bkz. [OrbitLevel.peekDepth]) — ileri bolumlerde bu deger otomatik
  /// artar, boylece oyuncu 6 halka + genis renk paletiyle bogusurken
  /// artik sadece bir sonraki degil, birkac adim ileriyi gorebilir.
  List<int?> previewRing(int ringIndex, {required bool clockwise, int? depth}) {
    final ring = level.rings[ringIndex];
    return ring.peekAhead(depth ?? level.peekDepth, clockwise: clockwise);
  }

  bool get isFinished => status != OrbitStatus.playing;

  int get deliveredCount => targetCursor;

  int get totalCount => level.targetQueue.length;

  int get dockUsed => dock.where((d) => d != null).length;

  /// [ringIndex] halkasini dondurmeyi dener. Basariliysa true doner.
  bool rotateRing(int ringIndex, {required bool clockwise}) {
    if (status != OrbitStatus.playing) return false;
    final ring = level.rings[ringIndex];
    if (ring.isEmpty) return false;
    if (ring.locked) {
      lastLockedRingAttempt = ringIndex;
      notifyListeners();
      return false;
    }

    // Onceden simule et: bu donus kapiya YENI bir nesne getirecek mi ve
    // o nesne rihtime sigmayacak mi? Sigmiyorsa donusu hic uygulama.
    final incoming = _peekIncoming(ring, clockwise: clockwise);
    if (incoming != null && !_canAccept(incoming)) {
      lastBlockedRing = ringIndex;
      notifyListeners();
      return false;
    }

    // Fiilen uygulanacak bir hamle: geri-al icin bu andaki tam durumu
    // sakla (onceki snapshot varsa uzerine yazilir - tek seviyeli undo).
    _undoSnapshot = _OrbitSnapshot.capture(this);

    ring.rotate(clockwise: clockwise);
    rotations++;
    lastBlockedRing = null;

    final exiting = ring.gateValue;
    if (exiting != null) {
      ring.cells[0] = null; // nesne halkadan ayrildi
      final matched = exiting == currentTarget;
      lastExit = OrbitExitEvent(
        id: _exitEventCounter++,
        ringIndex: ringIndex,
        colorIndex: exiting,
        matched: matched,
      );
      _receive(exiting);
    }

    _checkJam();
    notifyListeners();
    return true;
  }

  /// Kaydedilmis son-hamle-oncesi durumu geri yukler (bkz. [_undoSnapshot]).
  /// Ekonomi/hak kontrolu (ucretsiz hak / meteor) burada YAPILMAZ - cagiran
  /// taraf (UI) once PlayerProgress.useUndo() ile hakki dusurup basarili
  /// donerse bu metodu cagirmali. [canUndo] false iken cagirmak no-op'tur.
  void undoLastMove() {
    final snap = _undoSnapshot;
    if (snap == null) return;
    for (var i = 0; i < level.rings.length; i++) {
      level.rings[i].cells
        ..clear()
        ..addAll(snap.ringCells[i]);
      level.rings[i].locked = snap.ringLocked[i];
    }
    dock
      ..clear()
      ..addAll(snap.dock);
    targetCursor = snap.targetCursor;
    rotations = snap.rotations;
    status = snap.status;
    score = snap.score;
    combo = snap.combo;
    bestCombo = snap.bestCombo;
    lastUnlockedRing = snap.lastUnlockedRing;
    lastExit = null;
    lastBlockedRing = null;
    lastLockedRingAttempt = null;
    _undoSnapshot = null; // tek seviyeli - kullanilinca tukenir
    notifyListeners();
  }

  /// Donus sonrasi kapiya hangi degerin gelecegini, halkayi degistirmeden
  /// hesaplar (salt-okunur onizleme).
  int? _peekIncoming(OrbitRing ring, {required bool clockwise}) {
    if (ring.cellCount <= 1) return ring.gateValue;
    return clockwise ? ring.cells.last : ring.cells[1 % ring.cellCount];
  }

  bool _canAccept(int colorIndex) {
    if (colorIndex == currentTarget) return true;
    return dockUsed < dock.length;
  }

  void _receive(int colorIndex) {
    if (colorIndex == currentTarget) {
      targetCursor++;
      _registerMatch();
      _drainDockCascade();
      _checkRingUnlocks();
    } else {
      final freeSlot = dock.indexWhere((d) => d == null);
      // _canAccept zaten kontrol ettigi icin normalde her zaman bulunur.
      if (freeSlot != -1) dock[freeSlot] = colorIndex;
      _registerMiss();
    }
    _checkWin();
  }

  /// Kombo/skor guncellemesi: sadece [OrbitLevel.comboEnabled] iken
  /// calisir (10. bolum oncesinde sessizce no-op).
  void _registerMatch() {
    if (!level.comboEnabled) return;
    combo++;
    if (combo > bestCombo) bestCombo = combo;
    // Her ardisik dogrudan teslimat bir onceki komboya gore daha fazla
    // puan katar (10, 20, 30, ... — basit ama hissedilir bir carpan).
    score += 10 * combo;
  }

  void _registerMiss() {
    if (!level.comboEnabled) return;
    combo = 0;
  }

  /// Kilitli halka(lar) yeterli teslimat sayisina ulasildiginda acilir.
  void _checkRingUnlocks() {
    for (var i = 0; i < level.rings.length; i++) {
      final ring = level.rings[i];
      if (ring.locked && targetCursor >= ring.unlockAt) {
        ring.locked = false;
        lastUnlockedRing = i;
      }
    }
  }

  /// Yeni hedefle rihtimde bekleyen bir nesne eslesiyorsa zincirleme
  /// teslim et (Pixel Flow tarzi "auto-resolve").
  void _drainDockCascade() {
    while (true) {
      final target = currentTarget;
      if (target == null) return;
      final idx = dock.indexOf(target);
      if (idx == -1) return;
      dock[idx] = null;
      targetCursor++;
      _registerMatch();
    }
  }

  void _checkWin() {
    if (targetCursor >= level.targetQueue.length &&
        level.rings.every((r) => r.isEmpty) &&
        dock.every((d) => d == null)) {
      status = OrbitStatus.won;
    }
  }

  /// Tahtada hala nesne varken HICBIR halkanin yasal (rihtimi tasirmayan)
  /// bir donusu kalmadiysa oyun sikismis demektir.
  ///
  /// ONEMLI DUZELTME (kritik bug): "geriye sadece kilitli halka(lar) kaldi"
  /// kontrolu ONCEDEN "dock'ta hala yer var mi" kontrolunden SONRA
  /// yapiliyordu. Bu yuzden dock dolu DEGILKEN butun acik/kilitsiz halkalar
  /// bosalirsa (o an ihtiyac duyulan rengin tum kalan kopyalari kilitli
  /// halkanin icinde kalmissa bu kolayca olusabiliyor) fonksiyon en basta
  /// "rihtimde hala yer var, sikisma yok" diyerek erken donuyor, zorla-ac
  /// (force-unlock) dalina hic girmiyordu. Sonuc: targetCursor ilerleyemez
  /// (cunku baska teslimat gelecek yer yok), kilit hic acilmaz, oyuncunun
  /// dondurebilecegi HICBIR halka kalmaz (bos halkalar rotateRing'de
  /// isEmpty kontrolunde, kilitli halka da locked kontrolunde direkt
  /// reddedilir) — ama status hala "playing" kalir, jam ekrani da hic
  /// tetiklenmez. Yani tahta sessizce donar/kilitlenir (bkz. proje notlari).
  /// Duzeltme: "sadece kilitli halka(lar) kaldi mi" kontrolu artik dock
  /// durumundan BAGIMSIZ, en once yapiliyor — boylece bu durum dock dolu
  /// olsun ya da olmasin ayni sekilde (kilidi zorla acarak) guvenle
  /// cozuluyor ve hicbir tahta artik matematiksel olarak kazanilamaz hale
  /// gelemiyor.
  ///
  /// IKINCI DUZELTME (kritik bug, 2. tip sessiz kilitlenme — simulasyonla
  /// dogrulandi, ozellikle 40. bolumden itibaren iki kilitli halka
  /// varken sikca olusabiliyor): yukaridaki duzeltme sadece "acik
  /// halkalarin HEPSI BOSALDI" durumunu kapsar. Ama acik halkalar hala
  /// DOLUYKEN de (icinde hedefle eslesmeyen baska renkler kalmis olsa
  /// bile) ayni tuzak olusabiliyordu: dock tamamen doluyken, o an istenen
  /// renk SADECE kilitli bir halkanin icinde kalmissa, asagidaki "en az
  /// bir yasal hamle var mi" taramasi acik halkalardaki BOS (null)
  /// hucreleri "yasal hamle" sayip yanilticidir — bu donusler gorsel
  /// olarak hicbir sey yapmaz (kapidan hicbir nesne cikmaz) ve oyuncuyu
  /// hicbir zaman ilerletemez. Asagida bu durum ayrica, erkenden tespit
  /// edilip AYNI zorla-ac stratejisiyle cozuluyor (bkz. asagidaki
  /// `trappedRings` blogu).
  void _checkJam() {
    if (status != OrbitStatus.playing) return;
    final boardHasObjects = level.rings.any((r) => !r.isEmpty);
    if (!boardHasObjects) return;

    final unlockedNonEmpty =
        level.rings.where((r) => !r.isEmpty && !r.locked).toList();
    if (unlockedNonEmpty.isEmpty) {
      // Geriye sadece hala KILITLI halka(lar) kaldi — normal esik hicbir
      // zaman tetiklenemeyecek demektir (baska teslimat gelmiyor, dolayisiyla
      // targetCursor ilerlemeyecek). Sahte bir sikismaya ya da sessiz
      // donmaya dusmemek icin kilidi burada zorla ac. Dock'ta yer olup
      // olmamasindan bagimsiz calisir (bkz. yukaridaki not).
      for (final ring in level.rings) {
        if (ring.locked) {
          ring.locked = false;
          lastUnlockedRing = level.rings.indexOf(ring);
        }
      }
      return;
    }

    if (dockUsed < dock.length) return; // rihtimde hala yer var, sikisma yok

    // SESSIZ KILITLENME DUZELTMESI (kritik bug — simulasyonla dogrulandi,
    // bkz. proje notlari): rihtim tamamen DOLUYKEN, o an istenen renk
    // (currentTarget) hicbir ACIK halkada bulunmuyorsa (kalan tum kopyalari
    // hala KILITLI bir halkanin icinde kaldiysa), asagidaki "en az bir
    // yasal hamle var mi" taramasi YANILTICI sonuc verebiliyordu: acik
    // halkalardaki BOS (null) hucreleri kapiya getiren donusler teknik
    // olarak "yasal" sayiliyordu (hicbir renk kabul etmesi gerekmedigi
    // icin _canAccept hic devreye girmiyor), ama bu donusler gorsel olarak
    // HICBIR SEY yapmiyor — kapidan hicbir nesne cikmiyor (OrbitExitEvent
    // hic tetiklenmiyor) — ve oyuncuyu asla ilerletemiyor, cunku ihtiyaci
    // olan renge zaten hicbir acik halkadan erisilemiyor. Sonuc: status
    // hala "playing" kalirdi, jam ekrani hic tetiklenmezdi, oyuncu
    // sessizce (hicbir geri bildirim almadan) sonsuza dek halka
    // cevirebilirdi — bu, acik bir jam'den bile daha kotu bir deneyim
    // (en azindan jam'de "tekrar dene" ekrani gelir).
    //
    // Duzeltme: bu spesifik durumu (dock dolu + hedef SADECE kilitli
    // halka(lar)da) burada erkenden tespit edip, dosyanin ustundeki "tum
    // acik halkalar bosaldi" senaryosuyla AYNI "zorla-ac" (force-unlock)
    // stratejisini uyguluyoruz — sikisma ilan etmek yerine hedefi tasiyan
    // kilitli halka(lar)i acarak oyunun devam etmesini sagliyoruz. targetQueue
    // her zaman tahtaya konan gercek renklerden turetildigi icin (bkz.
    // OrbitLevelGenerator.generate), henuz teslim edilmemis bir hedefin
    // dock'ta OLMAMASI (drainDockCascade zaten oradaki eslesmeleri hemen
    // tuketir) ve acik hicbir halkada da bulunmamasi, matematiksel olarak
    // sadece kilitli bir halkada kalmis olabilecegi anlamina gelir — yani
    // bu dal guvenle "kilidi ac" diyebilir, sahte bir acilmaya yol acmaz.
    final target = currentTarget;
    if (target != null &&
        unlockedNonEmpty.every((r) => !r.cells.contains(target))) {
      final trappedRings =
          level.rings.where((r) => r.locked && r.cells.contains(target));
      if (trappedRings.isNotEmpty) {
        for (final ring in trappedRings) {
          ring.locked = false;
          lastUnlockedRing = level.rings.indexOf(ring);
        }
        return; // kilit(ler) acildi — sikisma degil, oyun devam ediyor
      }
    }

    for (final ring in unlockedNonEmpty) {
      for (final cw in [true, false]) {
        final incoming = _peekIncoming(ring, clockwise: cw);
        if (incoming == null || _canAccept(incoming)) return; // en az bir yasal hamle var
      }
    }
    status = OrbitStatus.jammed;
  }

  /// Yildiz hesaplama: par'a gore basit bir esik — mevcut oyunun
  /// StageStat sistemiyle uyumlu (1-3 yildiz).
  int starsForResult() {
    if (status != OrbitStatus.won) return 0;
    if (rotations <= level.parRotations) return 3;
    if (rotations <= (level.parRotations * 1.4).ceil()) return 2;
    return 1;
  }
}

/// [OrbitController.undoLastMove] icin salt-veri anlik goruntu. Halka
/// hucrelerini/kilit durumlarini, rihtimi ve tum sayaclari tek bir hamle
/// oncesine dondurebilecek kadar bilgi tasir.
class _OrbitSnapshot {
  final List<List<int?>> ringCells;
  final List<bool> ringLocked;
  final List<int?> dock;
  final int targetCursor;
  final int rotations;
  final OrbitStatus status;
  final int score;
  final int combo;
  final int bestCombo;
  final int? lastUnlockedRing;

  _OrbitSnapshot._({
    required this.ringCells,
    required this.ringLocked,
    required this.dock,
    required this.targetCursor,
    required this.rotations,
    required this.status,
    required this.score,
    required this.combo,
    required this.bestCombo,
    required this.lastUnlockedRing,
  });

  factory _OrbitSnapshot.capture(OrbitController c) {
    return _OrbitSnapshot._(
      ringCells: [for (final r in c.level.rings) List<int?>.from(r.cells)],
      ringLocked: [for (final r in c.level.rings) r.locked],
      dock: List<int?>.from(c.dock),
      targetCursor: c.targetCursor,
      rotations: c.rotations,
      status: c.status,
      score: c.score,
      combo: c.combo,
      bestCombo: c.bestCombo,
      lastUnlockedRing: c.lastUnlockedRing,
    );
  }
}
