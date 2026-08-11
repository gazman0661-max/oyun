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

  const OrbitLevel({
    required this.stage,
    required this.rings,
    required this.targetQueue,
    required this.dockCapacity,
    required this.parRotations,
    this.comboEnabled = false,
  });

  int get totalObjects => targetQueue.length;
}
