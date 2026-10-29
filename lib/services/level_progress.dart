import 'package:shared_preferences/shared_preferences.dart';

/// Bolum Modu ilerlemesi: her bolum icin en iyi yildiz (0 = gecilmedi).
/// Bolum sayisi SONSUZ oldugu icin yildizlar "bolum:yildiz" ciftleri olarak
/// saklanir. Cihazda SharedPreferences'ta (bulut kaydina henuz bagli degil).
class LevelClearResult {
  final bool firstClear;

  /// Onceki en iyiye gore KAZANILAN yeni yildiz sayisi (ilk gecista = yildiz).
  final int newStars;
  const LevelClearResult(this.firstClear, this.newStars);
}

class LevelProgress {
  LevelProgress._();
  static final LevelProgress instance = LevelProgress._();

  static const _prefsKey = 'lv_stars_v2';
  static const _legacyKey = 'lv_stars_v1'; // "3,2,0,..." (sira = bolum-1)

  final Map<int, int> _stars = {};
  bool _loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _stars.clear();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      for (final part in raw.split(',')) {
        final kv = part.split(':');
        if (kv.length != 2) continue;
        final lv = int.tryParse(kv[0]);
        final st = int.tryParse(kv[1]);
        if (lv != null && st != null && lv >= 1 && st > 0) _stars[lv] = st;
      }
    } else {
      // Eski (20 bolumluk) kayit varsa tasi.
      final old = prefs.getString(_legacyKey) ?? '';
      if (old.isNotEmpty) {
        final parts = old.split(',');
        for (var i = 0; i < parts.length; i++) {
          final st = int.tryParse(parts[i]) ?? 0;
          if (st > 0) _stars[i + 1] = st;
        }
      }
    }
    _loaded = true;
  }

  bool get loaded => _loaded;

  int starsOf(int level) => _stars[level] ?? 0;

  int get totalStars => _stars.values.fold<int>(0, (a, b) => a + b);

  /// 1. bolum hep acik; sonrakiler bir onceki gecilince acilir.
  bool isUnlocked(int level) => level <= 1 || starsOf(level - 1) > 0;

  /// Oyuncunun siradaki oynayacagi bolum (ilk gecilmemis bolum).
  int get nextLevel {
    var n = 1;
    while (starsOf(n) > 0) {
      n++;
    }
    return n;
  }

  /// Birakis sayisina gore yildiz: par veya altinda 3, par ile limit
  /// arasinin yarisina kadar 2, aksi halde 1.
  static int starsFor({
    required int drops,
    required int par,
    required int max,
  }) {
    if (drops <= par) return 3;
    if (drops <= par + (max - par) / 2) return 2;
    return 1;
  }

  Future<LevelClearResult> recordClear(int level, int stars) async {
    if (!_loaded) await load();
    if (level < 1) return const LevelClearResult(false, 0);
    final prev = starsOf(level);
    final better = stars > prev;
    if (better) {
      _stars[level] = stars;
      final prefs = await SharedPreferences.getInstance();
      final keys = _stars.keys.toList()..sort();
      await prefs.setString(
          _prefsKey, keys.map((k) => '$k:${_stars[k]}').join(','));
    }
    return LevelClearResult(prev == 0, better ? stars - prev : 0);
  }
}
