import 'dart:math' as math;

/// Meteor (elmas) ekonomisinin TEK kaynağı. Fiyatlar ve olasılıklar
/// burada toplanır ki dengeleme yapılacaksa tek dosyaya bakmak yetsin.
///
/// Ana oyun: Gezegen Birleştir (Suika tarzı). Görevler, takımyıldız,
/// kuyruklu yıldız ve günlük seri hep bu oyunun sonuçlarına bağlıdır.
class EconomyConfig {
  EconomyConfig._();

  // ---- Kurtarma hakkı ("Kabini hafiflet": oyun bitince en üstteki 6 ----
  // gezegeni kaldırıp devam et). Reklam izleyerek ya da burada stoklanan
  // haktan reklamsız kullanılır. Malzeme Mağazası'ndan meteorla alınır.
  static const int rescueShopPrice = 40;

  // ---- Guclendiriciler (sadece Sonsuz Mod) ----
  static const int powerBombPrice = 25; // "Sil"
  static const int powerSwapPrice = 15; // "Degistir"
  static const int powerShakePrice = 20; // "Salla"

  /// Yeni oyuncuya (ve eski kayitlara) her guclendiriciden hediye adedi.
  static const int powerStarterGift = 1;

  // ---- Elde tutma ----
  /// Kopmak uzere olan gunluk seriyi meteorla kurtarma bedeli.
  static const int streakRescueCost = 60;

  /// Seri koruyucu: en fazla kac adet tutulur / kac gunde bir kazanilir.
  static const int streakShieldMax = 2;
  static const int streakShieldEvery = 7;

  /// Donus hediyesi: en az kac gun uzak kalinca, son hediyeden kac gun sonra.
  static const int comebackGiftMinDays = 3;
  static const int comebackGiftCooldownDays = 14;

  // ---- Combo ----
  /// Iki birlesme arasi bu sureden kisa ise combo devam eder.
  static const double comboWindowSeconds = 1.6;

  /// Combo bonusu: birlesme puaninin (combo-1) * bu oran kadari eklenir.
  static const double comboBonusPerStep = 0.25;

  /// Bonus carpaninin ust siniri (ornek: 4 adim * 0.25 = en fazla +%100).
  static const int comboMaxSteps = 4;

  // ---- Gezegen Birleştir: görev ve ödül eşikleri ----
  /// Bir oyunun "bitirilmiş" sayılması için en az bırakış sayısı (hiç
  /// oynamadan çıkıp görev şişirmeyi engeller).
  static const int mergeMinDropsForRun = 15;

  /// "cleanStages" görevi: "devam et" kullanmadan bu kademeye (5 = Dünya)
  /// ulaşılan oyun sayılır.
  static const int mergeCleanTier = 5;

  /// "perfectStars" görevi: bu kademeye (7 = Neptün) ulaşılan oyun.
  static const int mergePerfectTier = 7;

  /// Bir oyunda ulaşılan en yüksek kademeden takımyıldız puanı:
  /// Mars (4) = 1 ... en çok 6 puan.
  static int mergeConstellationPoints(int bestTier) =>
      math.min(6, math.max(0, bestTier - 3));

  /// İlk kez ulaşılan rekor kademe için tek seferlik meteor: Dünya (5)
  /// ve üstü, kademe-3 meteor (5->2, 6->3, ... 11->8).
  static int mergeMeteorsForNewTier(int tier) => tier < 5 ? 0 : tier - 3;

  /// Bir oyundan kazanılan XP: skor/8, en çok 300.
  static const int mergeXpMax = 300;
  static const int mergeXpScoreDivisor = 8;

  // ---- Kozmik İkmal ödül olasılık tablosu (toplam %100) ----
  // EKONOMI v2: reklam artik XP VERMEZ, sadece meteor verir (%50'lik eski
  // XP dilimi 1 meteora cevrildi). Bonus meteor kaldirildi.
  static const double pMeteor10 = 0.05;
  static const double pMeteor5 = 0.10;
  static const double pMeteor3 = 0.15;
  static const double pMeteor2 = 0.20;
  static const double pMeteor1 = 0.50;

  static const int xpRewardAmount = 100;

  // ---- Küçük, sabit meteor gelir kanalları (tamamen RNG'ye bağlı
  // kalmaması için) ----
  // DUZELTME (ekonomi dengeleme, IAP oncesi): eskiden HER bolumde garanti
  // 1 meteor veriliyordu - organik kazanc cok yuksekti (haftada ~120-160
  // meteor), bu da temalari/gelecekteki IAP'yi anlamsizlastiriyordu.
  // Artik garanti degil, %30 ihtimalle 1 meteor (bkz. PlayerProgress'te
  // bu olasiliga gore cagrilan yer).
  static const double meteorPerLevelCompleteChance = 0.30;
  static const int meteorPerLevelComplete = 1;
  static const int meteorDailyStreakBonus = 2;

  // ---- Haftalık Ödül Takvimi (Pazartesi=index 0 ... Pazar=index 6) ----
  // DUZELTME (ekonomi dengeleme): toplam haftalik taban 27 -> 13'e,
  // Pazar ekstra bonusu 20 -> 10'a dusuruldu. Mantik/sira ayni kaldi,
  // sadece rakamlar kisildi.
  static const List<int> weeklyRewardMeteor = [1, 1, 2, 2, 2, 2, 3];
  static const int weeklyRewardSundayBonus = 10;
  static const int meteorStarterGift = 30;

  // ---- Kazanma diyalogu "2x XP" reklam ödülü: XP'nin yanında sabit ----
  // meteor bonusu da verir (reklam izleyince +N meteor).
  static const int winDoubleXpMeteorBonus = 3;

  // ---- Kozmik Oda / Dükkan: arkaplan teması fiyatı ----
  // Su an TUM temalar ayni fiyatta (500); ileride tema basina farkli
  // fiyat gerekirse bunu bir Map<String,int>'e cevirmek yeterli olur.
  // Kozmik Oda arkaplan temaları — kademeli fiyatlandırma (eskiden hepsi
  // tek bir cosmicThemePrice=500 idi). Sıra CosmicThemes.all listesindeki
  // sırayla eşleşiyor: meteor_shower en ucuz (giriş seviyesi), ufos en
  // pahalı (en son/en gösterişli tema).
  static const int cosmicThemePriceTier1 = 600; // meteor_shower
  static const int cosmicThemePriceTier2 = 1000; // solar_system
  static const int cosmicThemePriceTier3 = 1600; // spaceships
  static const int cosmicThemePriceTier4 = 2500; // ufos

  // ---- ESKİ sabit haftalık hedef — artık home_screen'den çağrılmıyor,
  // yerini aşağıdaki dönüşümlü weeklyQuestRotation aldı. Geriye dönük
  // uyumluluk / referans için silinmedi.
  static const int weeklyGoalTarget = 15;
  static const int weeklyGoalReward = 20;

  // ---------------------------------------------------------------------
  // Haftalık Görev Rotasyonu: her hafta farklı bir görev tipi aktif olur.
  // Hangi görevin aktif olduğu PlayerProgress._currentWeekKey() (cihaz
  // yerel, 7 günde bir artan bir sayaç) ile bu listenin indeksine mod
  // alınarak belirlenir -> sunucu gerekmez, ama her oyuncuda aynı hafta
  // aynı görev görünür ve hafta bitince otomatik değişir.
  //
  // Zorluk arttıkça ödül de artar (temel = 15 bölüm / 20 meteor'un
  // "adil değeri" referans alınarak dengelenmiştir):
  //   - stagesCleared : en kolay — N oyun bitir (en az mergeMinDropsForRun bırakış)
  //   - playDays      : kolay ama alışkanlık kurmayı hedefler (D7 icin)
  //   - cleanStages   : orta — "devam et" kullanmadan Dünya'ya (mergeCleanTier) ulaş
  //   - perfectStars  : zor — Neptün'e (mergePerfectTier) ulaşan oyunlar
  //   - spendMeteors  : zor — ekonomiyi döndürür, mağazayı kullandırır
  // ---------------------------------------------------------------------
  static const List<WeeklyQuestDef> weeklyQuestRotation = [
    WeeklyQuestDef(
      type: WeeklyQuestType.stagesCleared,
      target: 15,
      reward: 20,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.cleanStages,
      target: 6,
      reward: 30,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.playDays,
      target: 4,
      reward: 18,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.perfectStars,
      target: 4,
      reward: 28,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.stagesCleared,
      target: 22,
      reward: 26,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.spendMeteors,
      target: 60,
      reward: 25,
    ),
  ];

  // ---------------------------------------------------------------------
  // Aylık Görev Takvimi: dönüşümlü DEĞİL — her takvim ayının (Ocak..Aralık)
  // KENDİ SABİT görevi var (index 0 = Ocak, 11 = Aralık). Hangi görevin
  // aktif olduğu PlayerProgress.monthlyQuest içinde NetworkTimeService
  // (UTC) üzerinden okunan gerçek ay numarasıyla (1-12) doğrudan
  // seçilir — yıldan yıla AYNI ay AYNI görevi gösterir (ör. her Aralık
  // "temiz bitir" görevi olur).
  //
  // Hedefler o ayin gun sayisina (28-31) ve mevsimsel/etkinlik temasina
  // gore hafifce degisir; Aralik (yil sonu) ve Ocak (yeni yil) en yuksek
  // odullu aylardir.
  // ---------------------------------------------------------------------
  static const List<MonthlyQuestDef> monthlyQuestByMonth = [
    // 1) Ocak — Yeni Yil acilisi: en cok bolum bitiren kazanir.
    MonthlyQuestDef(type: MonthlyQuestType.stagesCleared, target: 65, reward: 100),
    // 2) Subat — en kisa ay: yardimsiz/temiz bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.cleanStages, target: 20, reward: 120),
    // 3) Mart — 3 yildizli mukemmel bitirmeler.
    MonthlyQuestDef(type: MonthlyQuestType.perfectStars, target: 12, reward: 115),
    // 4) Nisan — alligkanlik/D30: farkli gunlerde oyna.
    MonthlyQuestDef(type: MonthlyQuestType.playDays, target: 14, reward: 80),
    // 5) Mayis — magazayi kullandir.
    MonthlyQuestDef(type: MonthlyQuestType.spendMeteors, target: 220, reward: 95),
    // 6) Haziran — yaz baslangici: bolum bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.stagesCleared, target: 70, reward: 105),
    // 7) Temmuz — yaz ortasi: temiz bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.cleanStages, target: 24, reward: 135),
    // 8) Agustos — mukemmel bitirmeler.
    MonthlyQuestDef(type: MonthlyQuestType.perfectStars, target: 14, reward: 125),
    // 9) Eylul — okul/is donusu: alisilan oyun gunleri.
    MonthlyQuestDef(type: MonthlyQuestType.playDays, target: 16, reward: 90),
    // 10) Ekim — magazayi kullandir.
    MonthlyQuestDef(type: MonthlyQuestType.spendMeteors, target: 260, reward: 105),
    // 11) Kasim — bolum bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.stagesCleared, target: 75, reward: 110),
    // 12) Aralik — yil sonu: en zor + en yuksek odul, temiz bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.cleanStages, target: 26, reward: 150),
  ];

  // ---------------------------------------------------------------------
  // Takımyıldız (Constellation) — Gezegen Birleştir'de ulaşılan gezegen
  // kademesinden gelen puanlarla dolan, haftalık sıfırlanan ayrı bir
  // katman (bkz.
  // PlayerProgress.activeConstellation / weeklyConstellationStars).
  // weeklyQuestRotation'dan KASITLI olarak farklı uzunlukta bir liste —
  // aynı hafta aynı "fazda" olmadıkları için ikisi birden aynı anda
  // bitmiyor, daha çeşitli hissettiriyor.
  //
  // ÖDÜL BİLEREK meteor DEĞİL: PlayerProgress.unlockedConstellationBadges
  // içine kalıcı, harcanamaz bir rozet ekler (bkz. claimConstellationReward).
  // Meteor havuzu zaten bölüm bitirme/haftalık/aylık/Kuyruklu Yıldız gibi
  // pek çok kaynaktan doluyor; bu katman kasıtlı olarak O HAVUZDAN AYRI
  // tutulup "biriktirilecek, gösterilecek" bir koleksiyon ödülü sağlar —
  // oyuncunun geri dönmesi için meteordan farklı bir sebep.
  // ---------------------------------------------------------------------
  static const List<ConstellationDef> constellationRotation = [
    ConstellationDef(
      id: 'orion',
      nameKey: 'constellation_orion',
      pointCount: 12,
      badgeIcon: '🏹',
    ),
    ConstellationDef(
      id: 'ursa',
      nameKey: 'constellation_ursa',
      pointCount: 15,
      badgeIcon: '🐻',
    ),
    ConstellationDef(
      id: 'lyra',
      nameKey: 'constellation_lyra',
      pointCount: 10,
      badgeIcon: '🎻',
    ),
  ];

  // ---------------------------------------------------------------------
  // Kuyruklu Yıldız (Comet Event) — periyodik, zaman sınırlı özel bir
  // Meydan okuma. cometCycleDays günde bir döngü başlar, ilk
  // cometActiveDays günü boyunca AÇIK kalır (bkz. PlayerProgress.
  // cometEventActive/cometEventNumber — NetworkTimeService/UTC tabanlı,
  // cihaz saatinden bağımsız). Aynı event penceresinde herkese aynı
  // (event numarasına göre sabit tohumlu) meydan okuma gelir; bir kez
  // bitirilince o pencerede ödül tekrar verilmez.
  // ---------------------------------------------------------------------
  static const int cometCycleDays = 4;
  static const int cometActiveDays = 2;
  static const int cometMeteorReward = 12;
  static const int cometXpReward = 60;

  // =====================================================================
  // GUNLUK SERI v2: kademeli gunluk bonus, kilometre tasi odulleri, seri
  // kurtarma/koruyucu fiyatlari, hafta ici bonusu ve SERI ZORLUK EGRISI.
  // Hepsi tek yerde; denge icin sadece bu bolume bakmak yeter.
  // =====================================================================

  /// Gunluk bulmaca bitince verilen meteor, seri uzadikca artar.
  /// 1-6. gun: 2, 7-13: 3, 14-29: 4, 30+: 5.
  static int dailyStreakMeteor(int streak) {
    if (streak >= 30) return 5;
    if (streak >= 14) return 4;
    if (streak >= 7) return 3;
    return 2;
  }

  /// Seri kurtarma bedeli: seri ne kadar uzunsa kurtarmak o kadar pahali
  /// (ama kaybetmek daha da aci). 3-9: 40, 10-29: 60, 30-59: 90, 60+: 130.
  static int streakRescueCostFor(int streak) {
    if (streak >= 60) return 130;
    if (streak >= 30) return 90;
    if (streak >= 10) return 60;
    return 40;
  }

  /// Seri koruyucuyu meteorla satin alma bedeli (en fazla streakShieldMax).
  static const int streakShieldPrice = 100;

  /// Pzt-Cuma 5 gun ust uste (hafta icinde) gunluk bulmaca bitirilirse,
  /// Cumartesi ya da Pazar bulmacasini bitirince haftada bir verilir.
  static const int weekendStreakBonusMeteor = 15;

  /// Seri kilometre taslari: BIR KEZ verilir (omur boyu). 100. gunden
  /// sonra her 50 gunde bir tekrar eden buyuk odul ayrica verilir.
  static const List<StreakMilestone> streakMilestones = [
    StreakMilestone(day: 3, shake: 1),
    StreakMilestone(day: 7, meteors: 15, bomb: 1),
    StreakMilestone(day: 14, meteors: 30, swap: 1, shield: 1),
    StreakMilestone(day: 30, meteors: 80, bomb: 1, swap: 1, shake: 1),
    StreakMilestone(day: 60, meteors: 150, bomb: 1, swap: 1, shake: 1, shield: 1),
    StreakMilestone(day: 100, meteors: 300, bomb: 2, swap: 2, shake: 2, shield: 1),
  ];

  static StreakMilestone? streakMilestoneFor(int day) {
    for (final m in streakMilestones) {
      if (m.day == day) return m;
    }
    if (day > 100 && day % 50 == 0) {
      return StreakMilestone(day: day, meteors: 100, shield: 1);
    }
    return null;
  }

  /// Henuz alinmamis, [streak]'in ustundeki ilk kilometre tasi.
  static StreakMilestone? nextStreakMilestone(int streak, Set<int> claimed) {
    for (final m in streakMilestones) {
      if (m.day > streak && !claimed.contains(m.day)) return m;
    }
    var d = (math.max(streak, 100) ~/ 50 + 1) * 50;
    while (claimed.contains(d)) {
      d += 50;
    }
    return streakMilestoneFor(d);
  }

  /// [streak]'e kadar (dahil) ulasilmis son kilometre tasi gunu (yoksa 0).
  static int previousStreakMilestoneDay(int streak) {
    var best = 0;
    for (final m in streakMilestones) {
      if (m.day <= streak && m.day > best) best = m.day;
    }
    if (streak > 100) {
      final r = (streak ~/ 50) * 50;
      if (r > best) best = r;
    }
    return best;
  }

  // ---- Seri zorluk egrisi (gunluk meydan okuma seriye gore sertlesir) ----
  // Seviye: 0: 0-2 gun, 1: 3-6, 2: 7-13, 3: 14-29, 4: 30-59, 5: 60+.
  // Her seviyede (a) gereken "verimlilik" artar (ayni hedef icin daha az
  // birakis hakki), (b) tehlike cizgisi asagi iner (kabin daralir),
  // (c) 14. gunden itibaren hedef gezegen bir kademe buyur.
  static const int streakDifficultyMaxLevel = 5;

  static int streakDifficultyLevel(int streak) {
    if (streak >= 60) return 5;
    if (streak >= 30) return 4;
    if (streak >= 14) return 3;
    if (streak >= 7) return 2;
    if (streak >= 3) return 1;
    return 0;
  }

  /// Seviye basina eklenen verimlilik gereksinimi (0..1 orani).
  static const List<double> streakDiffEfficiencyAdd = [0, 0.04, 0.08, 0.10, 0.13, 0.16];

  /// Seviye basina hedef kademe artisi.
  static const List<int> streakDiffTargetBonus = [0, 0, 0, 1, 1, 1];

  /// Seviye basina tehlike cizgisi kaymasi (buyudukce kabin daralir).
  static const List<double> streakDiffDangerAdd = [0, 2, 4, 6, 8, 10];

  /// Ust sinirlar: imkansiz meydan okuma uretmesin.
  static const double streakDiffMaxEfficiency = 0.78;
  static const double streakDiffMaxDangerY = 52;
  static const int streakDiffMaxTarget = 10;

  /// Seri unvani (kalici; en uzun seriye gore). null: henuz yok.
  static String? streakTitleKey(int bestStreak) {
    if (bestStreak >= 100) return 'streak_title_100';
    if (bestStreak >= 60) return 'streak_title_60';
    if (bestStreak >= 30) return 'streak_title_30';
    return null;
  }

}

/// Tek bir takımyıldız tanımı: kalıcı kimliği ([id] — rozet koleksiyonunda
/// saklanır), gösterilecek isim anahtarı (bkz. Localization), tamamlamak
/// için gereken yıldız (nokta) sayısı ve tamamlanınca kazanılan kalıcı
/// rozetin ikonu ([badgeIcon] — meteor DEĞİL, bkz. PlayerProgress.
/// unlockedConstellationBadges).
class ConstellationDef {
  final String id;
  final String nameKey;
  final int pointCount;
  final String badgeIcon;
  const ConstellationDef({
    required this.id,
    required this.nameKey,
    required this.pointCount,
    required this.badgeIcon,
  });
}

/// Bir haftalık görevin tipi — hangi sayaç okunacağını belirler
/// (bkz. PlayerProgress.weeklyQuestProgress).
enum WeeklyQuestType {
  /// N bölüm bitir (eski/klasik görev).
  stagesCleared,

  /// Rıhtım-kurtarması KULLANMADAN N bölüm bitir.
  cleanStages,

  /// 3 yıldızla (en iyi sonuç) N bölüm bitir.
  perfectStars,

  /// Bu hafta N FARKLI günde oyna (alışkanlık/D7 odaklı).
  playDays,

  /// Bu hafta mağazadan toplam N meteor harca.
  spendMeteors,
}

/// Tek bir haftalık görev tanımı: tipi + hedefi + ödülü. Zorluk arttıkça
/// ödül de EconomyConfig.weeklyQuestRotation içinde kademeli artırılmıştır.
class WeeklyQuestDef {
  final WeeklyQuestType type;
  final int target;
  final int reward;
  const WeeklyQuestDef({
    required this.type,
    required this.target,
    required this.reward,
  });
}

/// Aylık görev tipi — WeeklyQuestType ile birebir aynı kategoriler,
/// sadece ayrı bir enum (aylık ilerleme sayaçları haftalıktan bağımsız
/// tutulduğu için PlayerProgress.monthlyQuestProgress bunu okur).
enum MonthlyQuestType {
  stagesCleared,
  cleanStages,
  perfectStars,
  playDays,
  spendMeteors,
}

/// Tek bir aylık görev tanımı — WeeklyQuestDef ile aynı şekil.
class MonthlyQuestDef {
  final MonthlyQuestType type;
  final int target;
  final int reward;
  const MonthlyQuestDef({
    required this.type,
    required this.target,
    required this.reward,
  });
}



/// Tek bir seri kilometre tasi odulu (bkz. EconomyConfig.streakMilestones).
class StreakMilestone {
  final int day;
  final int meteors;
  final int bomb;
  final int swap;
  final int shake;
  final int shield;
  const StreakMilestone({
    required this.day,
    this.meteors = 0,
    this.bomb = 0,
    this.swap = 0,
    this.shake = 0,
    this.shield = 0,
  });

  /// Dil bagimsiz kisa ozet (emoji): "☄️15 💥1 🛡️1".
  String get summary {
    final parts = <String>[];
    if (meteors > 0) parts.add('☄️$meteors');
    if (bomb > 0) parts.add('💥$bomb');
    if (swap > 0) parts.add('🔄$swap');
    if (shake > 0) parts.add('🌀$shake');
    if (shield > 0) parts.add('🛡️$shield');
    return parts.join(' ');
  }
}
