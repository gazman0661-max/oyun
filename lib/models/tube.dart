/// Tek bir "enerji tupu"nu (sort oyunundaki klasik "tube") temsil eder.
/// Renkler int index olarak tutulur (0,1,2,...), gercek Color eslemesi
/// UI katmaninda (theme/app_colors.dart) yapilir.
class Tube {
  final int capacity;
  final List<int> balls; // index 0 = en alt, son eleman = en ust (tepe)

  Tube(this.capacity, [List<int>? initial]) : balls = initial ?? <int>[];

  bool get isEmpty => balls.isEmpty;
  bool get isFull => balls.length >= capacity;
  int get freeSpace => capacity - balls.length;

  int? get topColor => balls.isEmpty ? null : balls.last;

  /// Tepeden asagi giderken ayni renkten kac tane ust uste oldugunu sayar.
  int get topRunLength {
    if (balls.isEmpty) return 0;
    final c = balls.last;
    var count = 0;
    for (var i = balls.length - 1; i >= 0; i--) {
      if (balls[i] == c) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// Tup "tamamlanmis" sayilir: bossa VEYA tamamen doluysa ve
  /// icindeki tum toplar ayni renkteyse.
  bool get isSolved {
    if (isEmpty) return true;
    if (balls.length != capacity) return false;
    final first = balls.first;
    return balls.every((b) => b == first);
  }

  Tube copy() => Tube(capacity, List<int>.from(balls));

  /// "Sifir yercekimi" yetenegi: tuptekilerin dizilisini ters cevirir.
  /// (En alttaki en uste, en usttteki en alta gecer.) Bos veya tek renkli
  /// tuplerde gorsel olarak fark etmez ama yine de gecerli bir islemdir.
  void reverse() {
    final reversed = balls.reversed.toList();
    balls
      ..clear()
      ..addAll(reversed);
  }

  @override
  String toString() => 'Tube(cap=$capacity, balls=$balls)';
}
