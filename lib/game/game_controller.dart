import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/tube.dart';
import 'level_config.dart';
import 'level_generator.dart';

/// Oyunun tum durumunu (state) ve kurallarini yoneten sinif.
/// UI, bu sinifi dinleyerek (ChangeNotifier) kendini yeniden ciziyor.
class GameController extends ChangeNotifier {
  /// Normal bir bolum icin.
  GameController({required int startLevel})
      : level = startLevel < 1 ? 1 : startLevel,
        isDaily = false,
        dailyNumber = null {
    colorCount = LevelConfig.forLevel(level).colorCount;
    _generateAndLoad();
  }

  /// Gunluk gorev icin: [seed] ayni gun herkese ayni bulmacayi verir.
  GameController.daily({required this.dailyNumber, required int seed})
      : level = 0,
        isDaily = true {
    colorCount = 6;
    _generateAndLoad(overrideColors: 6, overrideEmpty: 1, seed: seed);
  }

  final bool isDaily;
  final int? dailyNumber;
  late int level;
  late int colorCount;
  late List<Tube> tubes;
  int? selectedIndex;
  int moveCount = 0;
  bool won = false;
  int optimalMoves = 1;
  int extraTubesUsed = 0;
  static const int maxExtraTubes = 2;
  int flipsUsed = 0;
  static const int maxFlips = 2;

  /// "Kara Delik" yetenegi: herhangi bir tupten TEK bir tasi cekip
  /// gecici olarak tutar, sonra renk kurali aranmadan HERHANGI bir
  /// tupe birakilabilir. Bolum 11'den itibaren acilir, bolum basina
  /// 1 kez kullanilabilir.
  int? blackHoleHeldColor;
  int? _blackHoleSource;
  int blackHoleUsed = 0;
  static const int maxBlackHole = 1;

  bool get blackHoleUnlocked => !isDaily && level >= 11;

  /// Bolumun ILK (uretildigi anki) dizilimi — "Yenile" butonu artik yeni
  /// bir bulmaca uretmiyor, sadece buna geri donuyor.
  List<List<int>> _initialArrangement = [];

  final List<List<Tube>> _history = [];

  bool get canUndo => _history.isNotEmpty;

  int get stars {
    if (moveCount <= optimalMoves) return 3;
    if (moveCount <= (optimalMoves * 1.5).ceil()) return 2;
    return 1;
  }

  void _generateAndLoad({int? overrideColors, int? overrideEmpty, int? seed}) {
    final rng = seed != null ? Random(seed) : null;
    final cfg = LevelConfig.forLevel(level);
    final generated = generateSolvableLevel(
      level,
      overrideColors: overrideColors ?? cfg.colorCount,
      overrideEmpty: overrideEmpty ?? cfg.emptyTubes,
      rng: rng,
    );
    optimalMoves = generated.optimalMoves;
    _initialArrangement =
        generated.tubes.map((t) => List<int>.from(t)).toList();
    tubes = generated.tubes
        .map((t) => Tube(kCapacity, List<int>.from(t)))
        .toList();
    selectedIndex = null;
    moveCount = 0;
    won = false;
    extraTubesUsed = 0;
    flipsUsed = 0;
    blackHoleHeldColor = null;
    _blackHoleSource = null;
    blackHoleUsed = 0;
    _history.clear();
  }

  void restartToInitial() {
    tubes = _initialArrangement
        .map((t) => Tube(kCapacity, List<int>.from(t)))
        .toList();
    selectedIndex = null;
    moveCount = 0;
    won = false;
    extraTubesUsed = 0;
    flipsUsed = 0;
    blackHoleHeldColor = null;
    _blackHoleSource = null;
    blackHoleUsed = 0;
    _history.clear();
    notifyListeners();
  }

  void goToLevel(int lvl) {
    level = lvl < 1 ? 1 : lvl;
    colorCount = LevelConfig.forLevel(level).colorCount;
    _generateAndLoad();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Hamle kurallari
  // ---------------------------------------------------------------------

  void _pour(Tube from, Tube to) {
    final color = from.topColor;
    if (color == null) return;
    final run = from.topRunLength;
    final space = to.freeSpace;
    final moveN = min(run, space);
    for (var i = 0; i < moveN; i++) {
      to.balls.add(from.balls.removeLast());
    }
  }

  bool canPour(int a, int b) {
    if (a == b) return false;
    if (a < 0 || b < 0 || a >= tubes.length || b >= tubes.length) return false;
    final from = tubes[a];
    final to = tubes[b];
    if (from.isEmpty) return false;
    if (to.isFull) return false;
    if (to.isEmpty) return true;
    return to.topColor == from.topColor;
  }

  /// Gercek durumu DEGISTIRMEDEN, bir (from,to) hamlesinin gecerli olup
  /// olmadigini ve kac top akacagini hesaplar. UI katmani, animasyonu
  /// baslatmadan once bu bilgiye ihtiyac duyar (hangi renk, kac top).
  ({int color, int moveCount})? previewPour(int from, int to) {
    if (!canPour(from, to)) return null;
    final top = tubes[from].topColor;
    if (top == null) return null;
    final run = tubes[from].topRunLength;
    final space = tubes[to].freeSpace;
    return (color: top, moveCount: min(run, space));
  }

  /// Sadece secim durumunu degistirir (pour animasyonu oynatilirken UI
  /// katmani, gercek dokme islemini animasyon bitene kadar erteler).
  void setSelected(int? index) {
    selectedIndex = index;
    notifyListeners();
  }

  /// Animasyon bittikten SONRA cagrilir: gercek durum degisikligini uygular.
  void commitPour(int from, int to) {
    if (!canPour(from, to)) return;
    _pushHistory();
    _pour(tubes[from], tubes[to]);
    moveCount++;
    selectedIndex = null;
    _checkWin();
    notifyListeners();
  }

  void tapTube(int index) {
    if (won) return;
    if (index < 0 || index >= tubes.length) return;

    if (selectedIndex == null) {
      if (tubes[index].isEmpty) return;
      selectedIndex = index;
    } else if (selectedIndex == index) {
      selectedIndex = null;
    } else if (canPour(selectedIndex!, index)) {
      _pushHistory();
      _pour(tubes[selectedIndex!], tubes[index]);
      moveCount++;
      selectedIndex = null;
      _checkWin();
    } else {
      selectedIndex = tubes[index].isEmpty ? null : index;
    }
    notifyListeners();
  }

  void _pushHistory() {
    _history.add([for (final t in tubes) t.copy()]);
    if (_history.length > 60) _history.removeAt(0);
  }

  void undo() {
    if (_history.isEmpty) return;
    tubes = _history.removeLast();
    selectedIndex = null;
    won = false;
    blackHoleHeldColor = null;
    _blackHoleSource = null;
    if (moveCount > 0) moveCount--;
    notifyListeners();
  }

  void _checkWin() {
    won = tubes.every((t) => t.isSolved);
  }

  bool addExtraTube() {
    if (extraTubesUsed >= maxExtraTubes) return false;
    tubes.add(Tube(kCapacity));
    extraTubesUsed++;
    notifyListeners();
    return true;
  }

  /// "Sifir Yercekimi" yetenegi: secilen tupun icindekileri ters cevirir.
  /// Bir hamle sayilmaz (moveCount degismez) ama geri alinabilir
  /// (undo gecmisine eklenir) ve bolum basina sinirlidir.
  bool flipTube(int index) {
    if (index < 0 || index >= tubes.length) return false;
    if (tubes[index].isEmpty) return false;
    if (flipsUsed >= maxFlips) return false;
    _pushHistory();
    tubes[index].reverse();
    flipsUsed++;
    selectedIndex = null;
    _checkWin();
    notifyListeners();
    return true;
  }

  /// Oynanabilir herhangi bir (kaynak, hedef) cifti bulur. Bulunamazsa null.
  (int, int)? findHint() {
    for (var a = 0; a < tubes.length; a++) {
      if (tubes[a].isEmpty || (tubes[a].isSolved && tubes[a].isFull)) {
        continue;
      }
      for (var b = 0; b < tubes.length; b++) {
        if (canPour(a, b)) return (a, b);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Kara Delik yetenegi
  // ---------------------------------------------------------------------

  /// Herhangi bir tupun en ustundeki TEK tasi "kara delige" cekip gecici
  /// olarak oyundan cikarir (renk/hamle kurali aranmaz). Cagiran taraf,
  /// bunu takiben [releaseFromBlackHole] ile herhangi bir tupe birakabilir.
  bool pullIntoBlackHole(int index) {
    if (won) return false;
    if (blackHoleHeldColor != null) return false;
    if (blackHoleUsed >= maxBlackHole) return false;
    if (index < 0 || index >= tubes.length) return false;
    final tube = tubes[index];
    if (tube.isEmpty) return false;
    _pushHistory();
    blackHoleHeldColor = tube.balls.removeLast();
    _blackHoleSource = index;
    selectedIndex = null;
    notifyListeners();
    return true;
  }

  /// Kara delikte tutulan tasi [index]'teki tupe birakir. Tas, cekildigi
  /// tupun KENDISINE geri birakilirsa bu ucretsiz bir "iptal" sayilir
  /// (hamle sayilmaz, hak tuketmez); farkli bir tupe birakmak gercek bir
  /// hamledir ve bolum basina sinirli kara delik hakkini tuketir.
  bool releaseFromBlackHole(int index) {
    final held = blackHoleHeldColor;
    if (held == null) return false;
    if (index < 0 || index >= tubes.length) return false;
    final tube = tubes[index];
    if (tube.isFull) return false;
    final isCancel = index == _blackHoleSource;
    tube.balls.add(held);
    blackHoleHeldColor = null;
    _blackHoleSource = null;
    if (!isCancel) {
      moveCount++;
      blackHoleUsed++;
      _checkWin();
    }
    notifyListeners();
    return true;
  }
}
