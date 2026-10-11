/// Gunluk gorevler ve "Galaksi Yolu" (aylik sezon gecisi) tanimlari.
///
/// Gunluk gorevler her gun (UTC) 3 adet, kolay/orta/zor havuzlarindan
/// gun numarasina gore DETERMINISTIK secilir (tum oyuncularda ayni gun ayni
/// gorevler). Gorev tamamlayinca "Yildiz puani" verir; puanlar Galaksi
/// Yolu seviyelerini acar, her seviyenin bir odulu vardir.
library;

/// Oyun icinde takip edilen olcutler.
enum MissionMetric {
  merges, // toplam birlestirme sayisi
  drops, // toplam atilan gezegen
  runs, // biten oyun sayisi
  bestTier, // ulasilan en yuksek gezegen kademesi (maksimum)
  bestCombo, // en yuksek combo (maksimum)
  runScore, // tek oyunda en yuksek skor (maksimum)
  powerUses, // kullanilan guclendirici sayisi
}

class DailyMissionDef {
  final String id;
  final String icon;

  /// Yerellestirme anahtari; metinde {n} hedefi (ya da gezegen adini) alir.
  final String titleKey;
  final MissionMetric metric;
  final int target;

  /// Tamamlayinca verilen Yildiz puani.
  final int points;

  const DailyMissionDef(
    this.id,
    this.icon,
    this.titleKey,
    this.metric,
    this.target,
    this.points,
  );

  /// true: deger "en yuksek" olarak tutulur; false: birikimli toplanir.
  bool get isMax =>
      metric == MissionMetric.bestTier ||
      metric == MissionMetric.bestCombo ||
      metric == MissionMetric.runScore;
}

class DailyMissions {
  static const List<DailyMissionDef> easy = [
    DailyMissionDef('m_merge25', '🪐', 'mission_merge', MissionMetric.merges, 25, 30),
    DailyMissionDef('m_drop40', '🚀', 'mission_drop', MissionMetric.drops, 40, 30),
    DailyMissionDef('m_run2', '🎮', 'mission_run', MissionMetric.runs, 2, 30),
  ];

  static const List<DailyMissionDef> medium = [
    DailyMissionDef('m_tier4', '🔴', 'mission_tier', MissionMetric.bestTier, 4, 40),
    DailyMissionDef('m_combo3', '⚡', 'mission_combo', MissionMetric.bestCombo, 3, 40),
    DailyMissionDef('m_merge60', '✨', 'mission_merge', MissionMetric.merges, 60, 40),
    DailyMissionDef('m_score800', '⭐', 'mission_score', MissionMetric.runScore, 800, 40),
    DailyMissionDef('m_run4', '🎯', 'mission_run', MissionMetric.runs, 4, 40),
  ];

  static const List<DailyMissionDef> hard = [
    DailyMissionDef('m_tier7', '🔵', 'mission_tier', MissionMetric.bestTier, 7, 60),
    DailyMissionDef('m_combo5', '🔥', 'mission_combo', MissionMetric.bestCombo, 5, 60),
    DailyMissionDef('m_score2000', '🏆', 'mission_score', MissionMetric.runScore, 2000, 60),
    DailyMissionDef('m_power2', '💥', 'mission_power', MissionMetric.powerUses, 2, 60),
    DailyMissionDef('m_merge120', '🌌', 'mission_merge', MissionMetric.merges, 120, 60),
  ];

  /// [dayNumber] (epoch'tan bu yana gun) icin o gunun 3 gorevi.
  static List<DailyMissionDef> forDay(int dayNumber) {
    final d = dayNumber < 0 ? -dayNumber : dayNumber;
    return [
      easy[d % easy.length],
      medium[(d * 2 + 1) % medium.length],
      hard[(d * 3 + 2) % hard.length],
    ];
  }
}

/// Galaksi Yolu seviye odulu.
class PassReward {
  final int meteors;
  final int xp;
  final int bomb;
  final int swap;
  final int shake;
  const PassReward({
    this.meteors = 0,
    this.xp = 0,
    this.bomb = 0,
    this.swap = 0,
    this.shake = 0,
  });
}

class PassConfig {
  /// Bir seviyeyi acmak icin gereken Yildiz puani.
  static const int pointsPerLevel = 300;

  /// 3 gunluk gorevin hepsi alininca verilen bonus puan.
  static const int dailyBonusPoints = 40;

  /// Haftalik / aylik gorev odulu alininca eklenen puan.
  static const int weeklyQuestPoints = 100;
  static const int monthlyQuestPoints = 200;

  /// Seviye odulleri (1. seviyeden baslar). Sezon = takvim ayi (UTC).
  static const List<PassReward> rewards = [
    PassReward(meteors: 5), // 1
    PassReward(xp: 40), // 2
    PassReward(xp: 50), // 3
    PassReward(meteors: 8), // 4
    PassReward(swap: 1, xp: 60), // 5
    PassReward(meteors: 10), // 6
    PassReward(meteors: 8), // 7
    PassReward(xp: 100), // 8
    PassReward(meteors: 12, bomb: 1), // 9
    PassReward(meteors: 10), // 10
    PassReward(meteors: 15), // 11
    PassReward(xp: 150), // 12
    PassReward(meteors: 15), // 13
    PassReward(meteors: 20), // 14
    PassReward(meteors: 40, xp: 200, bomb: 1, swap: 1, shake: 1), // 15
  ];

  static int get maxLevel => rewards.length;
}
