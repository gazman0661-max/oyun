/// KASABA (meta ilerleme) katalogu.
///
/// 6 dunyanin her biri icin 1 bina var. Her bina 0 (harabe) -> 10 arasi
/// yukseltilir; her seviye KALICI bir oyun bonusu verir. Yukseltme:
///  * coin harcar (coin sink - ust seviyeler pahali),
///  * o DUNYADA yeterli yildiz ister (bolumleri tekrar oynatir).
/// Toplam kasaba seviyesi (0-60) kilometre taslarinda otomatik odul verir.
///
/// Denge ayarlari icin sadece bu dosyadaki sabitlere bak.
enum TownPerk { coinBonus, xpBonus, luck, dailyBonus, throwSpeed, gemBonus }

class TownMilestone {
  final int totalLevel;
  final int coins;
  final int gems;
  const TownMilestone(this.totalLevel, this.coins, this.gems);
}

class TownUpgradeResult {
  final int world;
  final int newLevel;
  final List<TownMilestone> milestones;
  const TownUpgradeResult(this.world, this.newLevel, this.milestones);
}

class TownCatalog {
  TownCatalog._();

  static const int worldCount = 6;
  static const int maxLevel = 10;
  static const int maxTotalLevel = worldCount * maxLevel; // 60
  static const int chaptersPerWorldBlock = 8; // ChapterConfig.chaptersPerThemeBlock ile ayni

  /// Seviye basina (0->1, 1->2, ... 9->10) temel coin maliyeti.
  /// Dunya indeksi arttikca %15 pahalilasir (bkz. costFor).
  static const List<int> baseCost = [450, 1050, 2000, 3600, 6000, 9600, 15000, 21000, 28500, 39000];

  /// Seviyeyi yukseltmek icin O DUNYADA gereken toplam yildiz
  /// (bir dunyada 8 bolum x 3 yildiz = 24 var; 10. seviye icin 22 yeter).
  static const List<int> starReq = [1, 2, 4, 6, 9, 12, 15, 18, 20, 22];

  /// Dunya sirasi = AlbumCatalog.themes sirasi.
  static const List<TownPerk> perks = [
    TownPerk.coinBonus, // Fast Food
    TownPerk.xpBonus, // Kafe
    TownPerk.luck, // Buyu & Simya
    TownPerk.dailyBonus, // Korsan
    TownPerk.throwSpeed, // Buz
    TownPerk.gemBonus, // Uzay
  ];

  // ── KAYNAK URETIMI (pasif coin) ─────────────────────────────────
  /// Bina seviyesine (0..10) gore SAATLIK coin uretimi. Seviye 0 (harabe)
  /// uretmez. Sonraki dunyalar bu degeri (100 + 25*dunya)% ile carpar.
  /// Denge icin sadece bu tabloya / storageHours'a bak.
  static const List<int> coinsPerHourBase = [0, 3, 5, 7, 10, 13, 17, 21, 26, 31, 37];

  /// Depo kapasitesi = saatlik uretim x bu saat. Dolunca uretim durur;
  /// oyuncu toplayinca yeniden baslar (geri donme sebebi).
  static const double storageHours = 8;

  // ── INSAAT SURELERI (Clash of Clans / Empires & Puzzles tarzi) ────
  /// Mevcut seviyeden (0..9) bir sonrakine yukseltmenin SURESI (dakika):
  /// 1 dk, 10 dk, 30 dk, 1.5 sa, 4 sa, 8 sa, 15 sa, 26 sa, 42 sa, 70 sa.
  /// Sonraki dunyalarda %10 daha uzun. Ilk yukseltmeler cok kisa (aninda
  /// tatmin), sonrakiler gunlere uzar -> geri donme sebebi.
  static const List<int> upgradeMinutesBase = [1, 10, 30, 90, 240, 480, 900, 1560, 2520, 4200];

  static int upgradeMinutes(int world, int currentLevel) =>
      (upgradeMinutesBase[currentLevel.clamp(0, maxLevel - 1).toInt()] * (100 + 10 * world) / 100).round();

  /// Kisa sureler: 2 dk ve alti 1 elmas, 3-5 dk arasi dakika kadar elmas (3 dk = 3, 4 dk = 4, 5 dk = 5);
  /// 6 dk'dan sonra asagidaki egri (6 dk = 6). Eskiden ucretsizdi. Tek istisna: ilk bina kurulumu,
  /// bkz. GameProgress.townSkipCost.
  static const int shortSkipMinutes = 5;
  static const int minSkipGemCost = 1;

  /// Insaatci sayisi 1'den baslar. 2. ve 3. insaatci elmasla alinir
  /// (index = mevcut insaatci sayisi).
  static const int maxBuilders = 3;
  static const List<int> builderGemCost = [0, 600, 1600];

  /// Kalan sureyi elmasla hizlandirma bedeli (parcali dogrusal egri:
  /// 1 dk=2, 1 sa=45, 1 gun=600, 7 gun=2300 elmas). Son 5 dk: <=2 dk 1, sonra dakika kadar).
  static int skipGemCost(int remainingMinutes) {
    final m = remainingMinutes;
    if (m <= 2) return minSkipGemCost;
    if (m <= shortSkipMinutes) return m; // 3->3, 4->4, 5->5
    const pts = <List<double>>[
      [1, 2],
      [60, 45],
      [1440, 600],
      [10080, 2300],
    ];
    for (var i = 0; i < pts.length - 1; i++) {
      if (m <= pts[i + 1][0]) {
        final t = (m - pts[i][0]) / (pts[i + 1][0] - pts[i][0]);
        return (pts[i][1] + t * (pts[i + 1][1] - pts[i][1])).ceil();
      }
    }
    return (2300 + (m - 10080) * (1700 / 8640)).ceil();
  }

  static int coinsPerHour(int world, int level) {
    if (level <= 0) return 0;
    final base = coinsPerHourBase[level.clamp(0, maxLevel).toInt()];
    return base * (100 + 25 * world) ~/ 100;
  }

  static int capacity(int world, int level) => (coinsPerHour(world, level) * storageHours).round();

  /// Toplam kasaba seviyesine gore OTOMATIK verilen oduller (artan sirada).
  static const List<TownMilestone> milestones = [
    TownMilestone(3, 0, 3),
    TownMilestone(6, 500, 3),
    TownMilestone(10, 0, 8),
    TownMilestone(15, 1500, 5),
    TownMilestone(20, 0, 12),
    TownMilestone(25, 3000, 8),
    TownMilestone(30, 0, 20),
    TownMilestone(40, 6000, 25),
    TownMilestone(50, 0, 35),
    TownMilestone(60, 15000, 60),
  ];

  /// Bolum numarasindan dunya indeksi (ChapterConfig.themeFor ile ayni mantik).
  static int worldOfChapter(int chapterNumber) =>
      (((chapterNumber - 1) ~/ chaptersPerWorldBlock) % worldCount);

  static int costFor(int world, int currentLevel) {
    final base = baseCost[currentLevel];
    final scaled = base * (100 + 15 * world) ~/ 100;
    return (scaled ~/ 10) * 10;
  }

  /// Bonusun sayisal degeri: coin/xp/gunluk = oran, luck = oran,
  /// throwSpeed = ms, gemBonus = adet.
  static double perkValue(TownPerk perk, int level) {
    switch (perk) {
      case TownPerk.coinBonus:
        return level * 0.04;
      case TownPerk.xpBonus:
        return level * 0.05;
      case TownPerk.luck:
        return level * 0.005;
      case TownPerk.dailyBonus:
        return level * 0.10;
      case TownPerk.throwSpeed:
        return level * 4.0;
      case TownPerk.gemBonus:
        return (level ~/ 3).toDouble();
    }
  }

  static String perkText(TownPerk perk, int level, bool tr) {
    if (level <= 0) return tr ? 'Bonus yok' : 'No bonus';
    switch (perk) {
      case TownPerk.coinBonus:
        return tr ? '+%${level * 4} coin kazancı' : '+${level * 4}% coin earnings';
      case TownPerk.xpBonus:
        return tr ? '+%${level * 5} XP' : '+${level * 5}% XP';
      case TownPerk.luck:
        final v = (level * 0.5).toStringAsFixed(1);
        return tr ? '+%$v şanslı başlangıç' : '+$v% lucky start';
      case TownPerk.dailyBonus:
        return tr ? '+%${level * 10} günlük ödül coini' : '+${level * 10}% daily reward coins';
      case TownPerk.throwSpeed:
        return tr ? '-${level * 4} ms atış bekleme' : '-${level * 4} ms throw delay';
      case TownPerk.gemBonus:
        final g = level ~/ 3;
        if (g == 0) return tr ? '3. seviyede +1 💎 açılır' : 'Unlocks +1 💎 at level 3';
        return tr ? '+$g 💎 ilk bölüm geçişinde' : '+$g 💎 per first chapter clear';
    }
  }

  /// Toplam seviyeye gore unvan indeksi (0-5) -> 'town_rank_N' anahtari.
  static int rankIndex(int total) {
    if (total >= 60) return 5;
    if (total >= 50) return 4;
    if (total >= 35) return 3;
    if (total >= 20) return 2;
    if (total >= 10) return 1;
    return 0;
  }
}

/// Genel bolum numarasini (1,2,3...) bolge ici numaraya (1-8) cevirir:
/// 9. bolum -> 2. bolgenin 1. bolumu. Arayuzde HEP bu gosterilir; ilerleme
/// ve kayitlar genel numarayi kullanmaya devam eder.
int localChapterNumber(int chapter) => ((chapter - 1) % TownCatalog.chaptersPerWorldBlock) + 1;

/// Bu bolum bolgesinin son (8.) bolumu mu?
bool isLastChapterOfRegion(int chapter) => localChapterNumber(chapter) == TownCatalog.chaptersPerWorldBlock;
