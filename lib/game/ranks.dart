/// Oyuncu rutbesi: XP seviyesinden turetilir (bkz. PlayerProgress.levelInfo).
/// Yeni bir rutbeye ulasinca bir kereye mahsus meteor odulu verilir.
class PlayerRank {
  final int minLevel;
  final String icon;
  final String nameKey;
  final int rewardMeteors;
  const PlayerRank(this.minLevel, this.icon, this.nameKey, this.rewardMeteors);
}

class Ranks {
  /// 15 rutbe. Seviyeler PlayerProgress'teki XP egrisine (taban 100 XP,
  /// seviye basina %20 buyume) gore, gunde ~1500 XP kazanan yogun bir
  /// oyuncu icin su sure hedefiyle secildi (rutbeler arasi sure ~x1.45
  /// artar, buyuk ziplama yok):
  /// Asteğmen ~3 gun, Teğmen ~2 hafta, Üsteğmen ~3 hafta, Pilot ~1 ay,
  /// Kaptan ~1.5 ay, Binbaşı ~2 ay, Yarbay ~3 ay, Albay ~4.5 ay,
  /// Komutan ~6.5 ay, Tuğamiral ~9.5 ay, Koramiral ~1.1 yil, Amiral ~1.6 yil,
  /// Büyük Amiral ~2.3 yil, Galaksi Efendisi ~3.3 yil.
  /// Casual oyuncu (gunde ~300 XP) icin sureler yaklasik 5 kat uzar.
  /// Rutbe degistirmek/eklemek icin: yeni PlayerRank ekle (minLevel artan
  /// sirada olmali) ve localization.dart'a rank_<indeks> anahtarini ekle.
  static const List<PlayerRank> all = [
    PlayerRank(1, '🚀', 'rank_0', 0), // Kadet
    PlayerRank(14, '🔰', 'rank_1', 5), // Asteğmen
    PlayerRank(22, '🎖️', 'rank_2', 10), // Teğmen
    PlayerRank(24, '🏅', 'rank_3', 15), // Üsteğmen
    PlayerRank(26, '🛰️', 'rank_4', 20), // Pilot
    PlayerRank(28, '🌠', 'rank_5', 25), // Kaptan
    PlayerRank(30, '⭐', 'rank_6', 30), // Binbaşı
    PlayerRank(32, '🌟', 'rank_7', 40), // Yarbay
    PlayerRank(34, '💫', 'rank_8', 50), // Albay
    PlayerRank(36, '☄️', 'rank_9', 60), // Komutan
    PlayerRank(38, '🪐', 'rank_10', 80), // Tuğamiral
    PlayerRank(40, '🔭', 'rank_11', 100), // Koramiral
    PlayerRank(42, '👑', 'rank_12', 125), // Amiral
    PlayerRank(44, '💎', 'rank_13', 150), // Büyük Amiral
    PlayerRank(46, '🌌', 'rank_14', 250), // Galaksi Efendisi
  ];

  /// [level] icin rutbe indeksi.
  static int indexForLevel(int level) {
    var idx = 0;
    for (var i = 0; i < all.length; i++) {
      if (level >= all[i].minLevel) idx = i;
    }
    return idx;
  }

  static PlayerRank forLevel(int level) => all[indexForLevel(level)];
}
