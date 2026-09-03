/// Meteor (elmas) ekonomisinin TEK kaynağı. Fiyatlar ve olasılıklar
/// burada toplanır ki dengeleme yapılacaksa tek dosyaya bakmak yetsin.
///
/// Sohbette üzerinde uzlaşılan mantık:
/// - Orbit'te 1. rıhtım genişletme hakkı hâlâ ücretsiz (reklam), ama
///   aynı denemede 2.+ hak artık meteorla, kademeli artan fiyatla
///   satın alınıyor (sınırsız "pay-to-skip" döngüsünü engellemek için).
class EconomyConfig {
  EconomyConfig._();

  // ---- Orbit rıhtım genişletme mağaza fiyatı (SABİT — artık kademeli ----
  // artmıyor, sınırsız reklam yolu var, bu sadece "önceden stoklama"
  // için düz fiyatlı bir alternatif). Eski kademeli liste
  // (orbitDockMeteorPrices/orbitDockPriceFor) artık oyun ekranından
  // çağrılmıyor ama geriye dönük uyumluluk için silinmedi.
  static const int dockSlotShopPrice = 18; // eski: 6 (x3)

  // ---- Orbit rıhtım genişletme: 1. hak ücretsiz (reklam), sonrası ----
  // meteor ile ve kademeli artan fiyatla. index 0 = 2. hak fiyatı.
  static const List<int> orbitDockMeteorPrices = [18, 30, 45, 60]; // eski: [6, 10, 15, 20] (x3)

  static int orbitDockPriceFor(int paidAttemptIndex) {
    if (paidAttemptIndex < orbitDockMeteorPrices.length) {
      return orbitDockMeteorPrices[paidAttemptIndex];
    }
    // Tablo biterse son fiyattan +15 katlanarak devam eder (pratikte tavan).
    // (eski: +5 idi, 3x orantı ile 15 oldu)
    final overflow = paidAttemptIndex - orbitDockMeteorPrices.length + 1;
    return orbitDockMeteorPrices.last + overflow * 15;
  }

  // ---- Kozmik İkmal ödül olasılık tablosu (toplam %100) ----
  // Meteor dilimi %50, XP %50.
  static const double pMeteor10 = 0.05;
  static const double pMeteor5 = 0.10;
  static const double pMeteor3 = 0.15;
  static const double pMeteor2 = 0.20;
  static const double pXp = 0.50;

  static const int xpRewardAmount = 100;

  // ---- Kozmik İkmal "her izlemede ekstra meteor" bonusu ----
  // Ödül türü ne olursa olsun (XP/meteor dilimi fark etmez), HER
  // reklam izlemede bu aralıkta rastgele bir ek meteor de verilir —
  // "1 meteor + XP", "5 meteor + 2 meteor" gibi. Amaç: mevcut
  // ödül çeşitliliğini (sürpriz/variable-reward hissini) bozmadan
  // meteor ekonomisini her izlemede besleyip mağaza kullanımını artırmak.
  static const int resupplyBonusMeteorMin = 1;
  static const int resupplyBonusMeteorMax = 5;

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
  static const int meteorStarterGift = 12;

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
  static const int cosmicThemePriceTier1 = 150; // meteor_shower
  static const int cosmicThemePriceTier2 = 250; // solar_system
  static const int cosmicThemePriceTier3 = 350; // spaceships
  static const int cosmicThemePriceTier4 = 500; // ufos

  // ---- ESKİ sabit haftalık hedef — artık home_screen'den çağrılmıyor,
  // yerini aşağıdaki dönüşümlü weeklyQuestRotation aldı. Geriye dönük
  // uyumluluk / referans için silinmedi (bkz. dockSlotShopPrice notu).
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
  //   - stagesCleared : en kolay, en cok tekrar eder (haftada 1-2 kez)
  //   - playDays      : kolay ama alışkanlık kurmayı hedefler (D7 icin)
  //   - cleanStages   : orta zor — yardım/ipucu/reklam kurtarması YOK
  //   - perfectStars  : orta zor — 3 yıldızla (en iyi performans) bitir
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
      target: 8,
      reward: 30,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.playDays,
      target: 4,
      reward: 18,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.perfectStars,
      target: 6,
      reward: 28,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.stagesCleared,
      target: 22,
      reward: 26,
    ),
    WeeklyQuestDef(
      type: WeeklyQuestType.spendMeteors,
      target: 30,
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
    MonthlyQuestDef(type: MonthlyQuestType.cleanStages, target: 28, reward: 120),
    // 3) Mart — 3 yildizli mukemmel bitirmeler.
    MonthlyQuestDef(type: MonthlyQuestType.perfectStars, target: 22, reward: 115),
    // 4) Nisan — alligkanlik/D30: farkli gunlerde oyna.
    MonthlyQuestDef(type: MonthlyQuestType.playDays, target: 14, reward: 80),
    // 5) Mayis — magazayi kullandir.
    MonthlyQuestDef(type: MonthlyQuestType.spendMeteors, target: 110, reward: 95),
    // 6) Haziran — yaz baslangici: bolum bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.stagesCleared, target: 70, reward: 105),
    // 7) Temmuz — yaz ortasi: temiz bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.cleanStages, target: 34, reward: 135),
    // 8) Agustos — mukemmel bitirmeler.
    MonthlyQuestDef(type: MonthlyQuestType.perfectStars, target: 26, reward: 125),
    // 9) Eylul — okul/is donusu: alisilan oyun gunleri.
    MonthlyQuestDef(type: MonthlyQuestType.playDays, target: 16, reward: 90),
    // 10) Ekim — magazayi kullandir.
    MonthlyQuestDef(type: MonthlyQuestType.spendMeteors, target: 130, reward: 105),
    // 11) Kasim — bolum bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.stagesCleared, target: 75, reward: 110),
    // 12) Aralik — yil sonu: en zor + en yuksek odul, temiz bitirme.
    MonthlyQuestDef(type: MonthlyQuestType.cleanStages, target: 36, reward: 150),
  ];

  // ---------------------------------------------------------------------
  // Takımyıldız (Constellation) — SADECE Orbit modunda kazanılan
  // yıldızlarla dolan, haftalık sıfırlanan ayrı bir katman (bkz.
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
  // Orbit tahtası. cometCycleDays günde bir döngü başlar, ilk
  // cometActiveDays günü boyunca AÇIK kalır (bkz. PlayerProgress.
  // cometEventActive/cometEventNumber — NetworkTimeService/UTC tabanlı,
  // cihaz saatinden bağımsız). Aynı event penceresinde herkese aynı
  // (event numarasına göre sabit tohumlu) tahta gelir; bir kez
  // bitirilince o pencerede ödül tekrar verilmez.
  // ---------------------------------------------------------------------
  static const int cometCycleDays = 4;
  static const int cometActiveDays = 2;
  static const int cometMeteorReward = 12;
  static const int cometXpReward = 60;

  // ---------------------------------------------------------------------
  // Hamleyi Geri Al (Undo) — Orbit genelinde, bolum bazli DEGIL, GUNLUK
  // (tum oyun boyunca gunde N hak). Ilk `undoFreeDailyCount` kullanim
  // ucretsiz; sonrasi sabit `undoMeteorPrice` meteor karsiliginda.
  // ---------------------------------------------------------------------
  static const int undoFreeDailyCount = 3;
  static const int undoMeteorPrice = 5;
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


