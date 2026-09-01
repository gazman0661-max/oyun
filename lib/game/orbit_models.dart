/// Orbit Jam oyun modu icin temel veri modelleri.
///
/// Tasarim ozeti: klasik duz "grid" yerine ic ice gecmis, MERKEZ etrafinda
/// donen dairesel yorunge halkalari var. Her halka kendi ekseninde
/// (saat yonu / tersi) bagimsiz dondurulebilir. Her halkanin sabit bir
/// "kapi" (gate) hucresi vardir (index 0) — bir gok cismi donerek o hucreye
/// geldiginde halkadan disari cikar ve ya dogrudan teslim edilir ya da
/// sinirli kapasiteli "kargo rihtimi" (dock) beklemeye alinir.
library orbit_models;

/// Tek bir yorunge halkasi. [cells] uzunlugu [cellCount] kadardir; her
/// hucre ya bos (null) ya da bir renk indeksi (RockColor paletindeki index)
/// tutar. index 0 her zaman o halkanin "kapi" hucresidir.
class OrbitRing {
  final int cellCount;
  final List<int?> cells;

  /// 15. bölümden itibaren bazı halkalar kilitli başlar: oyuncu yeterli
  /// sayıda doğru teslimat yapana kadar bu halka döndürülemez.
  bool locked;

  /// [locked] true iken, toplam teslimat sayısı (targetCursor) bu değere
  /// ulaşınca halka otomatik olarak açılır.
  int unlockAt;

  OrbitRing({
    required this.cellCount,
    required List<int?> cells,
    this.locked = false,
    this.unlockAt = 0,
  }) : cells = List<int?>.from(cells);

  int? get gateValue => cells.isEmpty ? null : cells[0];

  bool get isEmpty => cells.every((c) => c == null);

  /// Halkayi FIILEN dondurmeden, [clockwise] yonde art arda yapilacak
  /// [depth] adet donusun kapiya SIRAYLA hangi degerleri getirecegini
  /// hesaplar (salt okunur onizleme — "peek derinligi"). depth=1 ile
  /// eski tek-adimlik onizlemeyle (bkz. OrbitController._peekIncoming)
  /// ayni sonucu verir; UI'da oyuncuya birden fazla adim ileriyi
  /// gosterebilmek icin genisletildi.
  ///
  /// k'inci (1-indeksli) donus sonrasi kapiya gelecek deger, listeyi
  /// fiilen kaydirmadan indeks aritmetigiyle hesaplaniyor:
  /// - saat yonu (cw): her donus son elemani basa tasir, yani k donus
  ///   sonrasi kapi = cells[(n - k) % n]
  /// - saat yonu tersi (ccw): her donus ilk elemani sona tasir, yani k
  ///   donus sonrasi kapi = cells[k % n]
  List<int?> peekAhead(int depth, {required bool clockwise}) {
    if (cells.isEmpty || depth <= 0) return const [];
    final n = cells.length;
    if (n <= 1) return List<int?>.filled(depth, cells[0]);
    return List<int?>.generate(depth, (i) {
      final k = i + 1;
      final idx = clockwise ? (n - k) % n : k % n;
      return cells[idx];
    });
  }

  /// Halkayi bir hucre miktari dondurur. [clockwise] true ise elemanlar
  /// index buyuklestirme yonunde kayar (yani eski index0 -> index1'e gider,
  /// eski son eleman -> index0'a / kapiya gelir).
  void rotate({required bool clockwise}) {
    if (cells.length <= 1) return;
    if (clockwise) {
      final last = cells.removeLast();
      cells.insert(0, last);
    } else {
      final first = cells.removeAt(0);
      cells.add(first);
    }
  }

  OrbitRing copy() => OrbitRing(
        cellCount: cellCount,
        cells: cells,
        locked: locked,
        unlockAt: unlockAt,
      );
}

/// Bir Orbit Jam bolumunun tam tanimi: kac halka, halka basina kac hucre,
/// hangi renkler nerede baslar, teslimat sirasi (hedef kuyrugu) ve
/// rihtim (dock) kapasitesi.
class OrbitLevel {
  final int stage;
  final List<OrbitRing> rings;
  final List<int> targetQueue; // teslim edilecek renk sirasi
  final int dockCapacity;
  final int parRotations; // 3 yildiz icin referans hamle sayisi
  final bool comboEnabled;

  /// Oyuncunun bir halkayi dondurmeden once kapiya SIRAYLA gelecek kac
  /// adet degeri onceden gorebilecegi ("peek derinligi"). 1 = eski
  /// davranis (sadece bir sonraki donus). Bkz. OrbitController.previewRing
  /// ve OrbitLevelGenerator._peekDepthForStage.
  final int peekDepth;

  const OrbitLevel({
    required this.stage,
    required this.rings,
    required this.targetQueue,
    required this.dockCapacity,
    required this.parRotations,
    this.comboEnabled = false,
    this.peekDepth = 1,
  });

  int get totalObjects => targetQueue.length;
}
