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
  void _checkJam() {
    if (status != OrbitStatus.playing) return;
    final boardHasObjects = level.rings.any((r) => !r.isEmpty);
    if (!boardHasObjects) return;
    if (dockUsed < dock.length) return; // rihtimde hala yer var, sikisma yok

    final unlockedNonEmpty =
        level.rings.where((r) => !r.isEmpty && !r.locked).toList();
    if (unlockedNonEmpty.isEmpty) {
      // Geriye sadece hala KILITLI halka(lar) kaldi — normal esik hicbir
      // zaman tetiklenemeyecek demektir (baska teslimat gelmiyor). Sahte
      // bir sikismaya dusmemek icin kilidi burada zorla ac.
      for (final ring in level.rings) {
        if (ring.locked) {
          ring.locked = false;
          lastUnlockedRing = level.rings.indexOf(ring);
        }
      }
      return;
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
