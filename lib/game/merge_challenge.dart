import 'dart:math';

import '../services/localization.dart';
import '../services/player_progress.dart';
import 'economy_config.dart';
import 'level_mode.dart';

/// Gezegen Birlestir meydan okumalari: GUNLUK SERI ve KUYRUKLU YILDIZ
/// etkinligi bu sinifla tanimlanir. Sonsuz moddan farki: belirli bir
/// HEDEF gezegene, sinirli sayida birakista ulasmak gerekir; ayrica her
/// meydan okumanin kendine ozel kurali vardir (dar kabin, agir baslangic,
/// kit kaynak ...).
///
/// Herkese ayni gun ayni meydan okuma gelir: tohum (seed) gunun
/// numarasindan uretilir, birakilan gezegen DIZISI her oyuncuda ve her
/// denemede ayni olur. Boylece denemeler adildir, skorlar paylasilabilir.
///
/// Sayilar (hedef kademe, birakis siniri, tehlike cizgisi) TAHMINIDIR —
/// oyun testinde zor/kolay bulunursa sadece bu dosyadaki tabloyu
/// degistirmek yeter.
enum MergeChallengeKind { daily, comet, level }

class MergeChallenge {
  final MergeChallengeKind kind;

  /// Yerellestirme anahtari (baslik) ve kural aciklamasi anahtari.
  final String titleKey;
  final String ruleKey;

  /// Birakilan gezegen dizisini belirleyen tohum.
  final int seed;

  /// Ulasilacak hedef kademe (0..12). 7 = Neptun, 9 = Saturn.
  final int targetTier;

  /// En fazla kac gezegen birakilabilir.
  final int maxDrops;

  /// Tehlike cizgisinin y konumu (varsayilan 24; buyudukce kabin daralir).
  final double dangerY;

  /// Birakilacak kademelerin agirliklari (index = kademe).
  final List<int> dropWeights;

  /// Gunluk seriye bagli zorluk seviyesi (0 = taban). Bkz.
  /// EconomyConfig.streakDifficultyLevel.
  final int difficultyLevel;

  /// Bolum Modu: bolum numarasi (0 = bolum degil) ve engelli bolum tanimi.
  final int levelNumber;
  final LevelDef? level;

  const MergeChallenge({
    required this.kind,
    required this.titleKey,
    required this.ruleKey,
    required this.seed,
    required this.targetTier,
    required this.maxDrops,
    required this.dangerY,
    required this.dropWeights,
    this.difficultyLevel = 0,
    this.levelNumber = 0,
    this.level,
  });

  /// Ekranda gosterilen baslik (bolumlerde "Bolum N").
  String get title =>
      levelNumber > 0 ? t('lv_title', {'n': '$levelNumber'}) : t(titleKey);

  /// Bolum Modu meydan okumasi.
  static MergeChallenge forLevel(LevelDef lv) => MergeChallenge(
        kind: MergeChallengeKind.level,
        titleKey: 'lv_title',
        ruleKey: lv.ruleKey,
        seed: lv.seed,
        targetTier: lv.targetTier,
        maxDrops: lv.maxDrops,
        dangerY: lv.dangerY,
        dropWeights: lv.dropWeights,
        levelNumber: lv.number,
        level: lv,
      );

  /// 3 yildiz icin "par" birakis sayisi (maxDrops'un %55'i).
  int get parDrops => level?.parDrops ?? (maxDrops * 0.55).ceil();

  /// Tohumlu rastgele sayi ureteci — her deneme basinda YENIDEN
  /// olusturulur, boylece ayni dizi tekrar gelir.
  Random newRng() => Random(seed);

  /// Agirliklara gore bir kademe secer.
  int pickTier(Random rng) {
    final total = dropWeights.fold<int>(0, (a, b) => a + b);
    var roll = rng.nextInt(total);
    for (var i = 0; i < dropWeights.length; i++) {
      if (roll < dropWeights[i]) return i;
      roll -= dropWeights[i];
    }
    return 0;
  }

  // ---- Gunluk seri: 4 gunluk dongu, gun numarasina gore ----
  static const List<_Variant> _dailyVariants = [
    // 0) Neptun'e ulas — standart kurallar, genis birakis siniri.
    _Variant('mc_daily_target', 'mc_rule_target', 7, 80, 24,
        [40, 28, 18, 10, 4]),
    // 1) Dar kabin — tehlike cizgisi asagida, daha az yer.
    _Variant('mc_daily_narrow', 'mc_rule_narrow', 6, 60, 44,
        [40, 28, 18, 10, 4]),
    // 2) Agir baslangic — baslangictan buyuk gezegenler gelir.
    _Variant('mc_daily_heavy', 'mc_rule_heavy', 8, 70, 24,
        [0, 30, 30, 22, 12, 6]),
    // 3) Kit kaynak — az birakis, hatasiz birlestirme.
    _Variant('mc_daily_scarce', 'mc_rule_scarce', 6, 34, 24,
        [40, 28, 18, 10, 4]),
  ];

  /// Birakilan gezegenlerin ortalama "degeri" (kademe t = 2^t birim).
  static double _avgDropValue(List<int> weights) {
    var total = 0;
    var sum = 0.0;
    for (var i = 0; i < weights.length; i++) {
      total += weights[i];
      sum += weights[i] * pow(2, i).toDouble();
    }
    return sum / total;
  }

  /// Bugunun gunluk meydan okumasi (UTC gun numarasina gore). [streak]
  /// oyuncunun AKTIF gunluk serisidir: seri uzadikca ayni gunun meydan
  /// okumasi (ayni tohum, ayni gezegen dizisi) daha sert parametrelerle
  /// gelir — daha az birakis hakki, daha dar kabin, 14. gunden sonra bir
  /// kademe buyuk hedef. Taban (seviye 0) eski tabloyla birebir aynidir.
  static MergeChallenge daily([DateTime? now, int streak = 0]) {
    final n = PlayerProgress.dailyNumber(now);
    final v = _dailyVariants[n % _dailyVariants.length];
    final lvl = EconomyConfig.streakDifficultyLevel(streak);
    var target = v.target;
    var drops = v.maxDrops;
    var danger = v.dangerY;
    if (lvl > 0) {
      final avg = _avgDropValue(v.weights);
      final baseEff = pow(2, v.target).toDouble() / (avg * v.maxDrops);
      final eff = min(EconomyConfig.streakDiffMaxEfficiency,
          baseEff + EconomyConfig.streakDiffEfficiencyAdd[lvl]);
      target = min(EconomyConfig.streakDiffMaxTarget,
          v.target + EconomyConfig.streakDiffTargetBonus[lvl]);
      drops = (pow(2, target).toDouble() / (avg * eff)).ceil();
      danger = min(EconomyConfig.streakDiffMaxDangerY,
          v.dangerY + EconomyConfig.streakDiffDangerAdd[lvl]);
      if (danger < v.dangerY) danger = v.dangerY;
    }
    return MergeChallenge(
      kind: MergeChallengeKind.daily,
      titleKey: v.titleKey,
      ruleKey: v.ruleKey,
      seed: PlayerProgress.dailySeed(now),
      targetTier: target,
      maxDrops: drops,
      dangerY: danger,
      dropWeights: v.weights,
      difficultyLevel: lvl,
    );
  }

  // ---- Kuyruklu yildiz: daha uzun ve zor, 3 farkli varyant ----
  static const List<_Variant> _cometVariants = [
    _Variant('mc_comet_a', 'mc_rule_comet_a', 8, 130, 24,
        [40, 28, 18, 10, 4]),
    _Variant('mc_comet_b', 'mc_rule_comet_b', 8, 110, 38,
        [40, 28, 18, 10, 4]),
    _Variant('mc_comet_c', 'mc_rule_comet_c', 9, 110, 24,
        [0, 30, 30, 22, 12, 6]),
  ];

  /// Su anki kuyruklu yildiz penceresinin meydan okumasi (event
  /// numarasina gore sabit — pencere boyunca herkese ayni).
  static MergeChallenge comet([DateTime? now]) {
    final n = PlayerProgress.cometEventNumber(now);
    final v = _cometVariants[n % _cometVariants.length];
    return MergeChallenge(
      kind: MergeChallengeKind.comet,
      titleKey: v.titleKey,
      ruleKey: v.ruleKey,
      seed: 700000 + n,
      targetTier: v.target,
      maxDrops: v.maxDrops,
      dangerY: v.dangerY,
      dropWeights: v.weights,
    );
  }
}

class _Variant {
  final String titleKey;
  final String ruleKey;
  final int target;
  final int maxDrops;
  final double dangerY;
  final List<int> weights;
  const _Variant(this.titleKey, this.ruleKey, this.target, this.maxDrops,
      this.dangerY, this.weights);
}
