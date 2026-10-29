/// Yerel basarimlar (Play Games'ten bagimsiz, oyun icinde gorunur) ve
/// gezegen koleksiyonu kilometre taslari.
enum AchMetric {
  runs, // biten oyun sayisi
  merges, // toplam birlestirme
  bestScore, // tek oyunda en yuksek skor
  bestCombo, // en yuksek combo
  planets, // kesfedilen gezegen sayisi (0..13)
  streak, // en uzun gunluk seri
  powerUses, // kullanilan guclendirici
}

class LocalAchievement {
  final String id;
  final String icon;

  /// Baslik anahtari; aciklama anahtari 'ach_d_<metric.name>' ({n} = hedef).
  final String nameKey;
  final AchMetric metric;
  final int target;
  final int rewardMeteors;
  const LocalAchievement(
    this.id,
    this.icon,
    this.nameKey,
    this.metric,
    this.target,
    this.rewardMeteors,
  );
}

class Milestones {
  static const List<LocalAchievement> achievements = [
    LocalAchievement('a_runs1', '🚀', 'ach_runs1', AchMetric.runs, 1, 5),
    LocalAchievement('a_runs25', '🛰️', 'ach_runs25', AchMetric.runs, 25, 10),
    LocalAchievement('a_runs100', '🌠', 'ach_runs100', AchMetric.runs, 100, 25),
    LocalAchievement('a_merge500', '✨', 'ach_merge500', AchMetric.merges, 500, 10),
    LocalAchievement('a_merge5000', '🌌', 'ach_merge5000', AchMetric.merges, 5000, 30),
    LocalAchievement('a_score1000', '⭐', 'ach_score1000', AchMetric.bestScore, 1000, 10),
    LocalAchievement('a_score3000', '🏅', 'ach_score3000', AchMetric.bestScore, 3000, 20),
    LocalAchievement('a_score8000', '🏆', 'ach_score8000', AchMetric.bestScore, 8000, 40),
    LocalAchievement('a_combo5', '⚡', 'ach_combo5', AchMetric.bestCombo, 5, 10),
    LocalAchievement('a_combo8', '🔥', 'ach_combo8', AchMetric.bestCombo, 8, 25),
    LocalAchievement('a_planets12', '🪐', 'ach_planets12', AchMetric.planets, 12, 40),
    LocalAchievement('a_planets13', '🌑', 'ach_planets13', AchMetric.planets, 13, 60),
    LocalAchievement('a_streak7', '📅', 'ach_streak7', AchMetric.streak, 7, 20),
    LocalAchievement('a_streak30', '🛡️', 'ach_streak30', AchMetric.streak, 30, 60),
    LocalAchievement('a_power20', '💥', 'ach_power20', AchMetric.powerUses, 20, 15),
  ];

  /// Koleksiyon kilometre taslari: kesfedilen gezegen sayisi -> meteor odulu.
  static const Map<int, int> collectionRewards = {4: 10, 8: 20, 12: 50, 13: 60};
}
