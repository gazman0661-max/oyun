import 'dart:math' show Random;

/// SANS CARKI katalogu. Denge icin sadece bu dosyadaki sayilara bak.
///
/// Gunde 1 bedava + en fazla 3 reklamli cevirme. Ust uste 7 gun bedava
/// cevirene 7. gun NADIR dilimlerden biri garanti (rare = true).
/// Mucevher odulleri bilerek dusuk: beklenen deger ~0.5 gem / cevirme.
enum WheelKind { coins, gems, energy, booster }

class WheelSlice {
  final WheelKind kind;
  final int amount; // coins/gems icin miktar
  final int weight; // toplam 100
  final bool rare;
  final int color; // 0xAARRGGBB
  const WheelSlice(this.kind, this.amount, this.weight, this.color, {this.rare = false});
}

class LuckyWheel {
  LuckyWheel._();

  static const List<WheelSlice> slices = [
    WheelSlice(WheelKind.coins, 100, 24, 0xFF66BB6A),
    WheelSlice(WheelKind.gems, 2, 12, 0xFF42A5F5),
    WheelSlice(WheelKind.coins, 250, 18, 0xFFFFA726),
    WheelSlice(WheelKind.booster, 1, 14, 0xFFAB47BC),
    WheelSlice(WheelKind.coins, 500, 10, 0xFFEF5350),
    WheelSlice(WheelKind.energy, 1, 12, 0xFF26C6DA),
    WheelSlice(WheelKind.gems, 5, 6, 0xFF5C6BC0, rare: true),
    WheelSlice(WheelKind.coins, 1500, 4, 0xFFFFCA28, rare: true), // JACKPOT
  ];

  static int get totalWeight => slices.fold(0, (a, s) => a + s.weight);

  /// Agirliklara gore dilim secer. [rareOnly] = 7. gun garantisi.
  static int pickIndex(Random rng, {bool rareOnly = false}) {
    var total = 0;
    for (final s in slices) {
      if (!rareOnly || s.rare) total += s.weight;
    }
    var roll = rng.nextInt(total);
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      if (rareOnly && !s.rare) continue;
      if (roll < s.weight) return i;
      roll -= s.weight;
    }
    return 0;
  }

  static double percentOf(int index) => slices[index].weight * 100 / totalWeight;
}
