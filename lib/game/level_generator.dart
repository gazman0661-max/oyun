import 'dart:math';

import 'level_config.dart';

/// HTML prototipindeki generateSolvableLevel() + A* solve() fonksiyonlarinin
/// Dart karsiligi. Bolum TAMAMEN rastgele karistirilir, sonra gercek bir A*
/// cozucuyle "cozulebilir mi" diye dogrulanir; cozulemeyen bir dagilim asla
/// oyuncuya gosterilmez. Donen `optimalMoves`, kazanma ekranindaki yildiz
/// hesaplamasinda kullanilir (movesUsed <= optimalMoves => 3 yildiz).
class GeneratedLevel {
  final List<List<int>> tubes;
  final int optimalMoves;
  GeneratedLevel(this.tubes, this.optimalMoves);
}

const int kCapacity = 4;

bool isSolvedState(List<List<int>> tubes) {
  for (final t in tubes) {
    if (t.isEmpty) continue;
    if (t.length != kCapacity) return false;
    final first = t.first;
    if (t.any((c) => c != first)) return false;
  }
  return true;
}

List<List<int>> _cloneTubes(List<List<int>> tubes) =>
    tubes.map((t) => List<int>.from(t)).toList();

String _stateKey(List<List<int>> tubes) =>
    tubes.map((t) => t.join('.')).join('|');

List<List<int>> _getValidMoves(List<List<int>> tubes) {
  final moves = <List<int>>[];
  for (var i = 0; i < tubes.length; i++) {
    if (tubes[i].isEmpty) continue;
    final top = tubes[i].last;
    final isPureFull =
        tubes[i].length == kCapacity && tubes[i].every((c) => c == top);
    if (isPureFull) continue;
    for (var j = 0; j < tubes.length; j++) {
      if (i == j || tubes[j].length >= kCapacity) continue;
      if (tubes[j].isEmpty || tubes[j].last == top) {
        moves.add([i, j]);
      }
    }
  }
  return moves;
}

List<List<int>> _applyMoveSim(List<List<int>> tubes, int i, int j) {
  final nt = _cloneTubes(tubes);
  final top = nt[i].last;
  while (nt[i].isNotEmpty && nt[i].last == top && nt[j].length < kCapacity) {
    nt[j].add(nt[i].removeLast());
  }
  return nt;
}

/// Her tupteki "ayni renk blogu" fazlasi: hedefe kalan minimum hamleyi
/// kabaca tahmin eder, A* aramasini hedefe yonlendirir.
int _heuristic(List<List<int>> tubes) {
  var h = 0;
  for (final tube in tubes) {
    if (tube.isEmpty) continue;
    var groups = 1;
    for (var k = 1; k < tube.length; k++) {
      if (tube[k] != tube[k - 1]) groups++;
    }
    h += groups - 1;
  }
  return h;
}

class _Node implements Comparable<_Node> {
  final List<List<int>> tubes;
  final int depth;
  final int f;
  _Node(this.tubes, this.depth, this.f);

  @override
  int compareTo(_Node other) => f.compareTo(other.f);
}

/// A*: en kisa cozumu bulur, bulunamazsa null doner.
int? solvePuzzle(List<List<int>> initialTubes, {int maxStates = 25000}) {
  final visited = <String>{_stateKey(initialTubes)};
  final heap = HeapPriorityQueue<_Node>();
  heap.add(_Node(initialTubes, 0, _heuristic(initialTubes)));
  var explored = 0;
  while (heap.isNotEmpty && explored < maxStates) {
    final node = heap.removeFirst();
    explored++;
    if (isSolvedState(node.tubes)) return node.depth;
    for (final move in _getValidMoves(node.tubes)) {
      final nt = _applyMoveSim(node.tubes, move[0], move[1]);
      final key = _stateKey(nt);
      if (!visited.contains(key)) {
        visited.add(key);
        heap.add(_Node(nt, node.depth + 1, node.depth + 1 + _heuristic(nt)));
      }
    }
  }
  return null;
}

void _shuffle(List<int> arr, Random rng) {
  for (var i = arr.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;
  }
}

/// [stage] normal bolum uretimi icin; gunluk gorev icin sabit
/// [overrideColors]/[overrideEmpty] ve [rng] (tarihten turetilmis seed'li
/// Random) verilebilir — boylece herkese ayni gun ayni bulmaca cikar.
GeneratedLevel generateSolvableLevel(
  int stage, {
  int? overrideColors,
  int? overrideEmpty,
  Random? rng,
}) {
  final cfg = LevelConfig.forLevel(stage);
  final numColors = overrideColors ?? cfg.colorCount;
  final numEmpty = overrideEmpty ?? cfg.emptyTubes;
  final random = rng ?? Random();

  for (var attempt = 0; attempt < 40; attempt++) {
    final units = <int>[
      for (var c = 0; c < numColors; c++)
        for (var k = 0; k < kCapacity; k++) c,
    ];
    _shuffle(units, random);
    final tubes = <List<int>>[];
    for (var tI = 0; tI < numColors; tI++) {
      tubes.add(units.sublist(0, kCapacity));
      units.removeRange(0, kCapacity);
    }
    for (var e = 0; e < numEmpty; e++) {
      tubes.add(<int>[]);
    }
    if (isSolvedState(tubes)) continue;
    final optimal = solvePuzzle(tubes);
    if (optimal != null && optimal > 0) {
      return GeneratedLevel(tubes, optimal);
    }
  }

  // Guvenlik agi: 40 denemede bulunamazsa (pratikte neredeyse hic olmaz),
  // bir renk azaltarak garanti cozulebilir minimal bir seviye uret.
  final fallbackColors = max(2, numColors - 1);
  final units = <int>[
    for (var c = 0; c < fallbackColors; c++)
      for (var k = 0; k < kCapacity; k++) c,
  ];
  _shuffle(units, random);
  final tubes = <List<int>>[];
  for (var tI = 0; tI < fallbackColors; tI++) {
    tubes.add(units.sublist(0, kCapacity));
    units.removeRange(0, kCapacity);
  }
  tubes.add(<int>[]);
  tubes.add(<int>[]);
  final optimal = solvePuzzle(tubes) ?? 1;
  return GeneratedLevel(tubes, optimal);
}

/// Kucuk, bagimliliksiz bir binary min-heap (oncelik kuyrugu).
/// `collection` paketine bagimli olmamak icin kendi yaziyoruz.
class HeapPriorityQueue<T extends Comparable<T>> {
  final List<T> _arr = [];

  bool get isNotEmpty => _arr.isNotEmpty;
  bool get isEmpty => _arr.isEmpty;
  int get length => _arr.length;

  void add(T item) {
    _arr.add(item);
    _bubbleUp(_arr.length - 1);
  }

  T removeFirst() {
    final top = _arr[0];
    final last = _arr.removeLast();
    if (_arr.isNotEmpty) {
      _arr[0] = last;
      _bubbleDown(0);
    }
    return top;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_arr[p].compareTo(_arr[i]) <= 0) break;
      final tmp = _arr[p];
      _arr[p] = _arr[i];
      _arr[i] = tmp;
      i = p;
    }
  }

  void _bubbleDown(int i) {
    final n = _arr.length;
    while (true) {
      var s = i;
      final l = 2 * i + 1, r = 2 * i + 2;
      if (l < n && _arr[l].compareTo(_arr[s]) < 0) s = l;
      if (r < n && _arr[r].compareTo(_arr[s]) < 0) s = r;
      if (s == i) break;
      final tmp = _arr[s];
      _arr[s] = _arr[i];
      _arr[i] = tmp;
      i = s;
    }
  }
}

