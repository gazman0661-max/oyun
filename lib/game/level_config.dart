import 'dart:math';

/// Bolum (level) numarasina gore zorluk parametrelerini hesaplar.
/// Amac: her bolumde biraz daha zor ama oyuncuyu yormayacak sekilde
/// kademeli bir artis saglamak.
class LevelConfig {
  final int level;
  final int colorCount;
  final int emptyTubes;
  final int capacity;
  final int shuffleMoves;

  LevelConfig({
    required this.level,
    required this.colorCount,
    required this.emptyTubes,
    required this.capacity,
    required this.shuffleMoves,
  });

  factory LevelConfig.forLevel(int level) {
    final safeLevel = level < 1 ? 1 : level;

    // Kademeli zorluk eğrisi (üzerinde uzlaşılan plan):
    //   1-9. bölüm  -> her 5 bölümde 1 renk/gezegen
    //   10-14. bölüm -> her 4 bölümde 1 renk/gezegen
    //   15+. bölüm  -> her 3 bölümde 1 renk/gezegen
    // Böylece zorluk artışı büyük, anlaşılır "aşamalar" halinde gelir;
    // her aşama geçişinde oyuncu net bir "artık daha zor" hissi alır.
    var colorCount = _colorCountForLevel(safeLevel);
    if (colorCount > 7) colorCount = 7;

    // Ilk 4 bolum 2 bos tuple (yumusak giris), sonrasinda 1 bos tup
    // (daha az manevra alani = belirgin sekilde daha zor).
    final emptyTubes = safeLevel <= 4 ? 2 : 1;

    const capacity = 4;

    // Artik kullanilmiyor (uretim tam rastgele + A* ile dogrulaniyor),
    // geriye donuk uyumluluk icin birakildi.
    const shuffleMoves = 0;

    return LevelConfig(
      level: safeLevel,
      colorCount: colorCount,
      emptyTubes: emptyTubes,
      capacity: capacity,
      shuffleMoves: shuffleMoves,
    );
  }

  /// Bölüm 1'de 3 renkle başlar; her aşamada farklı bir hızda +1 renk
  /// ekler (bkz. [forLevel] üstündeki not).
  static int _colorCountForLevel(int level) {
    var count = 3;
    var remaining = level - 1;

    // 1-9 arası: her 5 bölümde +1 (bu aralıkta en fazla 1 artış olur).
    const phase1Levels = 9, phase1Step = 5;
    const phase2Levels = 5, phase2Step = 4; // 10-14

    final phase1 = min(remaining, phase1Levels);
    count += phase1 ~/ phase1Step;
    remaining -= phase1;
    if (remaining <= 0) return count;

    final phase2 = min(remaining, phase2Levels);
    count += phase2 ~/ phase2Step;
    remaining -= phase2;
    if (remaining <= 0) return count;

    // 15+ : her 3 bölümde +1
    count += remaining ~/ 3;
    return count;
  }
}
