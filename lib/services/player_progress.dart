import '../game/planet_merge_physics.dart' show PlanetMergeConfig;
import '../game/planet_skins.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/daily_missions.dart';
import '../game/economy_config.dart';
import '../game/milestones.dart';
import '../game/ranks.dart';
import '../game/weekly_rules.dart';
import 'analytics_service.dart';
import 'cloud_progress_sync.dart';
import 'network_time_service.dart';
import 'notification_service.dart';
import 'play_games_service.dart';
import 'sound_service.dart';

/// Gunluk bulmaca bitince verilen SERI odullerinin ozeti (sonuc diyalogu
/// icin; kaydedilmez).
class StreakRewardResult {
  final int streak;
  final int dailyMeteors;
  final StreakMilestone? milestone;
  final int weekendBonus;
  final int difficultyLevel;
  const StreakRewardResult({
    required this.streak,
    required this.dailyMeteors,
    this.milestone,
    this.weekendBonus = 0,
    this.difficultyLevel = 0,
  });
}

/// Gunluk gorevin son sonucu (paylasim ekrani + 2x XP butonu icin).
class DailyResult {
  final int dailyNum;

  /// Kullanilan birakis (drop) sayisi.
  final int moves;

  /// 3 yildiz icin "par" birakis sayisi.
  final int optimal;
  final int stars;
  final int timeSeconds;
  final int xp;

  /// Meydan okumanin son skoru ve ulasilan en yuksek gezegen kademesi.
  final int score;
  final int bestTier;
  bool doubled;
  DailyResult({
    required this.dailyNum,
    required this.moves,
    required this.optimal,
    required this.stars,
    required this.timeSeconds,
    required this.xp,
    this.score = 0,
    this.bestTier = 0,
    this.doubled = false,
  });

  Map<String, dynamic> toJson() => {
        'dailyNum': dailyNum,
        'moves': moves,
        'optimal': optimal,
        'stars': stars,
        'timeSeconds': timeSeconds,
        'xp': xp,
        'score': score,
        'bestTier': bestTier,
        'doubled': doubled,
      };

  factory DailyResult.fromJson(Map<String, dynamic> j) => DailyResult(
        dailyNum: j['dailyNum'] ?? 1,
        moves: j['moves'] ?? 0,
        optimal: j['optimal'] ?? 1,
        stars: j['stars'] ?? 1,
        timeSeconds: j['timeSeconds'] ?? 0,
        xp: j['xp'] ?? 0,
        score: j['score'] ?? 0,
        bestTier: j['bestTier'] ?? 0,
        doubled: j['doubled'] ?? false,
      );
}

class LevelInfo {
  final int level;
  final int xpIntoLevel;
  final int xpForNext;
  final double progress;
  const LevelInfo(this.level, this.xpIntoLevel, this.xpForNext, this.progress);
}

/// "Kozmik Ikmal" odul turleri (resupply reklam odulleri).
enum ResupplyRewardKind {
  xp,
  meteor,
}

class ResupplyReward {
  final ResupplyRewardKind kind;
  final int amount;
  /// Ana ödülün TÜRÜ ne olursa olsun (XP/meteor dilimi), HER
  /// Kozmik İkmal izlemesinde üstüne eklenen rastgele (1-5) ekstra
  /// meteor miktarı. kind == meteor ise ekranda toplam olarak
  /// (amount + bonusMeteors) gösterilir; diğer türlerde ayrıca
  /// "+N meteor" şeklinde belirtilir.
  final int bonusMeteors;
  const ResupplyReward(this.kind, this.amount, {this.bonusMeteors = 0});
}

/// Oyuncunun tum kalici ilerlemesini tutan ve SharedPreferences'a
/// kaydeden/yukleyen ChangeNotifier. HTML prototipindeki `playerData` +
/// ilgili tum fonksiyonlarin (saveLocal/loadLocal, resupply, daily,
/// level/xp sistemi) Dart karsiligi.
/// Haftalık Ödül Takvimi'nde tek bir günün UI durumu (7 kutulu şeritte
/// her kutu için).
enum WeeklyRewardDayState {
  /// Geçmiş gün, hiç açılmadan kaçırılmış — kutu artık kilitli/gri.
  missed,

  /// Geçmiş gün, ödülü alınmış — kutu işaretli/dolu.
  claimed,

  /// Bugün, henüz alınmamış — kutu vurgulu, dokunulabilir.
  claimableToday,

  /// Henüz gelmemiş gelecek gün — kutu kilitli, sadece önizleme.
  future,
}

/// Bir "Haftalık Ödül" talebinin (claim) sonucu — UI'da gösterilecek
/// meteor miktarını ve Pazar bonusu tetiklenip tetiklenmediğini taşır.
class WeeklyRewardClaimResult {
  final int baseMeteor;
  final int bonusMeteor;
  final bool isSundayBonus;
  const WeeklyRewardClaimResult({
    required this.baseMeteor,
    required this.bonusMeteor,
    required this.isSundayBonus,
  });
  int get totalMeteor => baseMeteor + bonusMeteor;
}


class PlayerProgress extends ChangeNotifier {
  // Ekonomideki sansa-bagli odemeler (orn. meteorPerLevelCompleteChance)
  // icin tek, paylasilan bir rastgele sayi ureteci.
  final Random _rng = Random();
  static final PlayerProgress instance = PlayerProgress._();
  PlayerProgress._();

  static const _prefsKey = 'cs_data_v1';

  int xp = 0;

  /// Tum oyunlarin (Gezegen Birlestir) toplam skoru — liderlik tablosu.
  int totalScore = 0;

  // Gezegen Birlestir (ana oyun) istatistikleri.
  int mergeRunsPlayed = 0;
  int mergeBestScore = 0;

  // Gunluk / haftalik (haftalik kural periyodu) rekor.
  String mergeBestTodayKey = '';
  int mergeBestToday = 0;
  int mergeBestWeekNum = -1;
  int mergeBestWeek = 0;

  /// Ulasilmis en yuksek gezegen kademesi (0..12); -1 = hic oynanmadi.
  int mergeBestTier = -1;

  int dailyStreak = 0;
  String dailyLastCompletedDate = '';
  DailyResult? dailyLastResult;

  // Haftalık ödül takvimi (Empires & Puzzles tarzı): Pazartesi-Pazar sabit
  // TAKVİM haftası (rolling 7 gün DEĞİL — hafta UTC Pazartesi 00:00'da
  // sıfırlanır, bkz. _currentWeekKey/weeklyEpochUtc). Her gün SADECE o gün
  // alınabilir bir ödül var; bir gün kaçırılırsa o günün ödülü tamamen
  // kaybedilir ama sonraki günler etkilenmez. Pazar ekstra (bonus) ödülü
  // İSE sadece o hafta Pazartesi'den Cumartesi'ye kadar 6 günün HEPSİ
  // alınmışsa verilir — yani "kusursuz hafta" ödülü.
  String weeklyRewardWeekKey = '';
  List<bool> weeklyRewardClaimedDays = List<bool>.filled(7, false);

  // Haftalık hedef: "bu hafta N bölüm bitir -> meteor ödülü". weeklyKey
  // hangi haftaya ait olduğumuzu tutar (bkz. _currentWeekKey); hafta
  // değişince sayaç ve "alındı" bayrağı otomatik sıfırlanır.
  int weeklyStagesCompleted = 0;
  String weeklyKey = '';
  bool weeklyRewardClaimed = false;

  // Dönüşümlü haftalık görev tiplerinin kendi sayaçları — hangisinin
  // okunacağı EconomyConfig.weeklyQuestRotation'daki aktif göreve göre
  // weeklyQuestProgress getter'ında seçilir. Hepsi _ensureCurrentWeek()
  // içinde hafta değişince sıfırlanır.
  int weeklyCleanStages = 0;
  int weeklyPerfectStages = 0;
  int weeklyMeteorsSpent = 0;
  final Set<String> weeklyPlayDates = <String>{};

  // Aylık hedef: haftalık ile BİREBİR AYNI mantık, sadece periyot bir
  // takvim ayı (UTC) ve hedefler/ödüller EconomyConfig.monthlyQuestByMonth
  // içinde daha büyük. monthlyKey hangi aya ait olduğumuzu tutar (bkz.
  // _currentMonthKey); ay değişince sayaç ve "alındı" bayrağı otomatik
  // sıfırlanır.
  int monthlyStagesCompleted = 0;
  String monthlyKey = '';
  bool monthlyRewardClaimed = false;
  int monthlyCleanStages = 0;
  int monthlyPerfectStages = 0;
  int monthlyMeteorsSpent = 0;
  final Set<String> monthlyPlayDates = <String>{};

  // Takımyıldız (Constellation): weeklyKey ile AYNI periyotta sıfırlanır
  // (bkz. _ensureCurrentWeek), ama weeklyQuest'ten bağımsız kendi
  // dönüşümü ve ödülü var. Gezegen Birleştir'de ulaşılan gezegen kademesinden gelen puanları
  // sayar (bkz. recordMergeRun -> _addConstellationStars).
  int weeklyConstellationStars = 0;
  bool weeklyConstellationClaimed = false;

  // Bir takımyıldız TAMAMEN tamamlandığında (bkz. claimConstellationReward)
  // kalıcı olarak eklenir; ConstellationDef.id değerlerini tutar (ör.
  // 'orion'). Haftalık sıfırlanmaz, HARCANMAZ — meteor havuzundan bilerek
  // ayrı, biriktirilip Kozmik Oda'da gösterilen bir rozet koleksiyonu.
  final Set<String> unlockedConstellationBadges = <String>{};

  bool hasConstellationBadge(String id) =>
      unlockedConstellationBadges.contains(id);

  // Kuyruklu Yıldız (Comet Event): son ödül verilen event numarası — aynı
  // event penceresinde ikinci kez ödül verilmesini engeller (bkz.
  // EconomyConfig.cometCycleDays/cometActiveDays ve recordCometEventComplete).
  int cometLastCompletedEvent = -1;

  // Meteor: tek, evrensel para birimi. Kozmik Ikmal'in %50'si + bolum
  // tamamlama/gunluk seri gibi kucuk sabit kanallardan biriktirilir;
  // magazadan rihtim hakki almak icin harcanir.
  int meteors = 0;
  bool meteorStarterGiftGranted = false;

  /// "Kozmik Oda" arkaplan temalari: 'default' (ucretsiz, herkeste hazir)
  /// disinda sahip olunan tema ID'leri. Dukkandan meteorla satin alinir.
  final Set<String> ownedThemes = <String>{'default'};

  /// Su an aktif (ana ekranda gosterilen) tema ID'si.
  String activeTheme = 'default';

  /// Acik ise her yeni oyunda, TUM temalar arasindan (sahiplik sarti yok)
  /// rastgele bir arkaplan secilir (oyun ekraninda). Kapaliysa aktif tema.
  bool randomThemePerGame = true;

  /// "Gunes Sistemi Koleksiyonu": bir bolum basariyla kazanildiginda
  /// kullanilan gezegen renk index'leri (0..9), ilk kesfedildiginde
  /// buraya eklenir ve kalici olarak saklanir.
  final Set<int> discoveredPlanets = <int>{};

  // Kozmik Ikmal bankasi: reklamla kazanilan, sonra reklamsiz
  // harcanabilen haklar. Yorunge Vardiyasi icin: reklamsiz kullanilabilen,
  // bir sonraki sikismada rihtima +1 yuva eklemek uzere biriktirilen hak.
  int bankedRescues = 0;

  // Guclendirici envanteri (Sonsuz Mod): sil / degistir / salla.
  int powerBombs = EconomyConfig.powerStarterGift;
  int powerSwaps = EconomyConfig.powerStarterGift;
  int powerShakes = EconomyConfig.powerStarterGift;

  // ---- Gunluk gorevler + Galaksi Yolu (aylik sezon gecisi) ----
  String missionDayKey = '';
  Map<String, int> missionProgress = <String, int>{};
  Set<String> missionClaimed = <String>{};
  bool missionBonusClaimed = false;
  String passSeasonKey = '';
  int passPoints = 0;
  Set<int> passClaimedLevels = <int>{};

  // ---- Elde tutma: seri koruyucu, donus hediyesi, rutbe, koleksiyon, basarim ----
  int streakShields = 0;
  int bestDailyStreak = 0;
  // Seri v2: bir kez verilen kilometre tasi odulleri + hafta ici bonusu.
  Set<int> streakMilestonesClaimed = <int>{};
  int dailyWeekStart = -1; // haftanin Pazartesi'sinin gun numarasi
  int dailyWeekMask = 0; // bit0 = Pzt ... bit6 = Paz (o hafta bitirilen gunler)
  int weekendBonusWeek = -1; // hafta ici bonusu en son hangi haftada alindi
  StreakRewardResult? lastStreakReward; // son gunluk bitiste verilenler
  String streakRescueOfferedDay = '';
  int lastSeenDayNum = -1;
  int lastComebackGiftDayNum = -100000;
  int comebackGiftPending = 0; // 0 yok, 1 kisa uzaklik, 2 uzun uzaklik
  int rankClaimed = 0;
  Set<int> collectionClaimed = <int>{};
  Set<String> achClaimed = <String>{};
  Set<String> equippedSkins = <String>{}; // takili gizli gezegen (skin) id'leri
  Set<String> skinsSeen = <String>{}; // acildigi gorulen skin'ler (kirmizi nokta icin)
  int lifetimeMerges = 0;
  int lifetimeDrops = 0;
  int bestComboEver = 0;
  int lifetimePowerUses = 0;
  bool _shieldJustUsed = false; // gecici (kaydedilmez)
  int lastResupplyTime = 0;
  int resupplyAdsWatched = 0;

  static const int resupplyCooldownMs = 2 * 60 * 60 * 1000;
  static const int resupplyAdsRequired = 3;
  static const int _levelBaseXp = 100;
  static const double _levelGrowth = 1.2;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        _applyJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Bozuk kayit: varsayilanlarla devam et.
      }
    }
    if (!meteorStarterGiftGranted) {
      meteors += EconomyConfig.meteorStarterGift;
      _earn('starter_gift', EconomyConfig.meteorStarterGift);
      meteorStarterGiftGranted = true;
    }
    _loaded = true;
    notifyListeners();
    await save();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_toJson()));
    // Play Games'e baglaniysa ilerlemeyi buluta da yazar (sessizce;
    // baglanti yoksa hicbir sey yapmaz).
    unawaited(CloudProgressSync.instance.pushAfterLocalSave());
  }

  /// Bulut senkronizasyonu (Play Games Saved Games) icin: tum ilerlemeyi
  /// tek bir JSON metni olarak disari verir.
  String exportJson() => jsonEncode(_toJson());

  /// Bulut senkronizasyonu icin: verilen JSON'u uygulayip yerel olarak
  /// da kaydeder (SharedPreferences).
  Future<void> restoreFromJson(Map<String, dynamic> json) async {
    _applyJson(json);
    notifyListeners();
    await save();
  }

  Map<String, dynamic> _toJson() => {
        'xp': xp,
        'totalScore': totalScore,
        'mergeRunsPlayed': mergeRunsPlayed,
        'mergeBestScore': mergeBestScore,
        'mergeBestTodayKey': mergeBestTodayKey,
        'mergeBestToday': mergeBestToday,
        'mergeBestWeekNum': mergeBestWeekNum,
        'mergeBestWeek': mergeBestWeek,
        'mergeBestTier': mergeBestTier,
        'dailyStreak': dailyStreak,
        'dailyLastCompletedDate': dailyLastCompletedDate,
        'dailyLastResult': dailyLastResult?.toJson(),
        'weeklyRewardWeekKey': weeklyRewardWeekKey,
        'weeklyRewardClaimedDays': weeklyRewardClaimedDays,
        'weeklyStagesCompleted': weeklyStagesCompleted,
        'weeklyKey': weeklyKey,
        'weeklyRewardClaimed': weeklyRewardClaimed,
        'weeklyCleanStages': weeklyCleanStages,
        'weeklyPerfectStages': weeklyPerfectStages,
        'weeklyMeteorsSpent': weeklyMeteorsSpent,
        'weeklyPlayDates': weeklyPlayDates.toList(),
        'monthlyStagesCompleted': monthlyStagesCompleted,
        'monthlyKey': monthlyKey,
        'monthlyRewardClaimed': monthlyRewardClaimed,
        'monthlyCleanStages': monthlyCleanStages,
        'monthlyPerfectStages': monthlyPerfectStages,
        'monthlyMeteorsSpent': monthlyMeteorsSpent,
        'monthlyPlayDates': monthlyPlayDates.toList(),
        'weeklyConstellationStars': weeklyConstellationStars,
        'weeklyConstellationClaimed': weeklyConstellationClaimed,
        'unlockedConstellationBadges': unlockedConstellationBadges.toList(),
        'cometLastCompletedEvent': cometLastCompletedEvent,
        'discoveredPlanets': discoveredPlanets.toList(),
        'meteors': meteors,
        'meteorStarterGiftGranted': meteorStarterGiftGranted,
        'ownedThemes': ownedThemes.toList(),
        'activeTheme': activeTheme,
        'randomThemePerGame': randomThemePerGame,
        'bankedRescues': bankedRescues,
        'powerBombs': powerBombs,
        'powerSwaps': powerSwaps,
        'powerShakes': powerShakes,
        'missionDayKey': missionDayKey,
        'missionProgress': missionProgress,
        'missionClaimed': missionClaimed.toList(),
        'missionBonusClaimed': missionBonusClaimed,
        'passSeasonKey': passSeasonKey,
        'passPoints': passPoints,
        'passClaimedLevels': passClaimedLevels.toList(),
        'streakShields': streakShields,
        'bestDailyStreak': bestDailyStreak,
        'streakMilestonesClaimed': streakMilestonesClaimed.toList(),
        'dailyWeekStart': dailyWeekStart,
        'dailyWeekMask': dailyWeekMask,
        'weekendBonusWeek': weekendBonusWeek,
        'streakRescueOfferedDay': streakRescueOfferedDay,
        'lastSeenDayNum': lastSeenDayNum,
        'lastComebackGiftDayNum': lastComebackGiftDayNum,
        'comebackGiftPending': comebackGiftPending,
        'rankClaimed': rankClaimed,
        'collectionClaimed': collectionClaimed.toList(),
        'achClaimed': achClaimed.toList(),
        'equippedSkins': equippedSkins.toList(),
        'skinsSeen': skinsSeen.toList(),
        'lifetimeMerges': lifetimeMerges,
        'lifetimeDrops': lifetimeDrops,
        'bestComboEver': bestComboEver,
        'lifetimePowerUses': lifetimePowerUses,
        'lastResupplyTime': lastResupplyTime,
        'resupplyAdsWatched': resupplyAdsWatched,
      };

  void _applyJson(Map<String, dynamic> j) {
    xp = j['xp'] ?? 0;
    totalScore = j['totalScore'] ?? 0;
    mergeRunsPlayed = j['mergeRunsPlayed'] ?? 0;
    mergeBestScore = j['mergeBestScore'] ?? 0;
    mergeBestTodayKey = j['mergeBestTodayKey'] ?? '';
    mergeBestToday = j['mergeBestToday'] ?? 0;
    mergeBestWeekNum = j['mergeBestWeekNum'] ?? -1;
    mergeBestWeek = j['mergeBestWeek'] ?? 0;
    mergeBestTier = j['mergeBestTier'] ?? -1;
    dailyStreak = j['dailyStreak'] ?? 0;
    dailyLastCompletedDate = j['dailyLastCompletedDate'] ?? '';
    dailyLastResult = j['dailyLastResult'] != null
        ? DailyResult.fromJson(Map<String, dynamic>.from(j['dailyLastResult']))
        : null;
    weeklyRewardWeekKey = j['weeklyRewardWeekKey'] ?? '';
    final claimedDaysRaw = (j['weeklyRewardClaimedDays'] as List?) ?? const [];
    weeklyRewardClaimedDays = List<bool>.generate(
      7,
      (i) => i < claimedDaysRaw.length ? (claimedDaysRaw[i] == true) : false,
    );
    discoveredPlanets
      ..clear()
      ..addAll(
        ((j['discoveredPlanets'] as List?) ?? const [])
            .map((e) => e as int),
      );
    meteors = j['meteors'] ?? 0;
    meteorStarterGiftGranted = j['meteorStarterGiftGranted'] ?? false;
    ownedThemes
      ..clear()
      ..add('default')
      ..addAll(
        ((j['ownedThemes'] as List?) ?? const []).map((e) => e as String),
      );
    activeTheme = j['activeTheme'] ?? 'default';
    randomThemePerGame = j['randomThemePerGame'] ?? true;
    bankedRescues = j['bankedRescues'] ?? j['bankedOrbitDockSlots'] ?? 0;
    powerBombs = j['powerBombs'] ?? EconomyConfig.powerStarterGift;
    powerSwaps = j['powerSwaps'] ?? EconomyConfig.powerStarterGift;
    powerShakes = j['powerShakes'] ?? EconomyConfig.powerStarterGift;
    missionDayKey = j['missionDayKey'] ?? '';
    missionProgress = {
      for (final e in ((j['missionProgress'] as Map?) ?? const {}).entries)
        e.key.toString(): (e.value as num).toInt(),
    };
    missionClaimed = ((j['missionClaimed'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    missionBonusClaimed = j['missionBonusClaimed'] ?? false;
    passSeasonKey = j['passSeasonKey'] ?? '';
    passPoints = j['passPoints'] ?? 0;
    passClaimedLevels = ((j['passClaimedLevels'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toSet();
    streakShields = j['streakShields'] ?? 0;
    bestDailyStreak = (j['bestDailyStreak'] as num?)?.toInt() ?? 0;
    if (dailyStreak > bestDailyStreak) bestDailyStreak = dailyStreak;
    streakMilestonesClaimed = ((j['streakMilestonesClaimed'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toSet();
    dailyWeekStart = (j['dailyWeekStart'] as num?)?.toInt() ?? -1;
    dailyWeekMask = (j['dailyWeekMask'] as num?)?.toInt() ?? 0;
    weekendBonusWeek = (j['weekendBonusWeek'] as num?)?.toInt() ?? -1;
    streakRescueOfferedDay = j['streakRescueOfferedDay'] ?? '';
    lastSeenDayNum = j['lastSeenDayNum'] ?? -1;
    lastComebackGiftDayNum = j['lastComebackGiftDayNum'] ?? -100000;
    comebackGiftPending = j['comebackGiftPending'] ?? 0;
    rankClaimed = j['rankClaimed'] ?? 0;
    collectionClaimed = ((j['collectionClaimed'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toSet();
    achClaimed = ((j['achClaimed'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    equippedSkins = ((j['equippedSkins'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    skinsSeen = ((j['skinsSeen'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    lifetimeMerges = j['lifetimeMerges'] ?? 0;
    lifetimeDrops = j['lifetimeDrops'] ?? 0;
    bestComboEver = j['bestComboEver'] ?? 0;
    lifetimePowerUses = j['lifetimePowerUses'] ?? 0;
    lastResupplyTime = j['lastResupplyTime'] ?? 0;
    resupplyAdsWatched = j['resupplyAdsWatched'] ?? 0;
    weeklyStagesCompleted = j['weeklyStagesCompleted'] ?? 0;
    weeklyKey = j['weeklyKey'] ?? '';
    weeklyRewardClaimed = j['weeklyRewardClaimed'] ?? false;
    weeklyCleanStages = j['weeklyCleanStages'] ?? 0;
    weeklyPerfectStages = j['weeklyPerfectStages'] ?? 0;
    weeklyMeteorsSpent = j['weeklyMeteorsSpent'] ?? 0;
    weeklyPlayDates
      ..clear()
      ..addAll(
        ((j['weeklyPlayDates'] as List?) ?? const []).map((e) => e as String),
      );
    monthlyStagesCompleted = j['monthlyStagesCompleted'] ?? 0;
    monthlyKey = j['monthlyKey'] ?? '';
    monthlyRewardClaimed = j['monthlyRewardClaimed'] ?? false;
    monthlyCleanStages = j['monthlyCleanStages'] ?? 0;
    monthlyPerfectStages = j['monthlyPerfectStages'] ?? 0;
    monthlyMeteorsSpent = j['monthlyMeteorsSpent'] ?? 0;
    monthlyPlayDates
      ..clear()
      ..addAll(
        ((j['monthlyPlayDates'] as List?) ?? const [])
            .map((e) => e as String),
      );
    weeklyConstellationStars = j['weeklyConstellationStars'] ?? 0;
    weeklyConstellationClaimed = j['weeklyConstellationClaimed'] ?? false;
    unlockedConstellationBadges
      ..clear()
      ..addAll(((j['unlockedConstellationBadges'] as List?) ?? const [])
          .map((e) => e as String));
    cometLastCompletedEvent = j['cometLastCompletedEvent'] ?? -1;
    _ensureCurrentWeek();
    _ensureCurrentMonth();
  }

  // ---------------------------------------------------------------------
  // XP / seviye sistemi (bolum ilerlemesinden bagimsiz, meta ilerleme)
  // ---------------------------------------------------------------------
  LevelInfo levelInfo() => levelInfoForXp(xp);

  /// Verilen toplam XP icin seviye bilgisi (oyun sonu animasyonunda
  /// "onceki / sonraki" konumu hesaplamak icin).
  static LevelInfo levelInfoForXp(int xp) {
    var level = 1;
    var xpFloor = 0;
    var xpForNext = _levelBaseXp;
    while (xp >= xpFloor + xpForNext) {
      xpFloor += xpForNext;
      level++;
      xpForNext = (xpForNext * _levelGrowth).round();
    }
    final xpIntoLevel = xp - xpFloor;
    final progress = (xpIntoLevel / xpForNext).clamp(0.0, 1.0).toDouble();
    return LevelInfo(level, xpIntoLevel, xpForNext, progress);
  }

  // ---------------------------------------------------------------------
  // Analitik yardimcilari (v10_22)
  // ---------------------------------------------------------------------
  void _earn(String source, int amount) {
    if (amount <= 0) return;
    unawaited(AnalyticsService.instance.logEarn(source, amount, meteors));
  }

  void _logEvent(String name, [Map<String, Object?> params = const {}]) {
    unawaited(AnalyticsService.instance.log(name, params));
  }

  void _logLevelUp() => _logEvent('level_up', {'level': levelInfo().level});

  /// Segmentleme icin kullanici ozellikleri (uygulama acilisinda ve her
  /// oyun sonunda tazelenir).
  void _syncAnalyticsProps() {
    final a = AnalyticsService.instance;
    final lv = levelInfo().level;
    a.setUserProp('player_level', '$lv');
    a.setUserProp('rank_idx', '${Ranks.indexForLevel(lv)}');
    a.setUserProp('runs_bucket',
        AnalyticsService.bucket(mergeRunsPlayed, const [1, 6, 21, 101]));
    a.setUserProp('best_tier', '$mergeBestTier');
    a.setUserProp('streak_bucket',
        AnalyticsService.bucket(bestDailyStreak, const [1, 3, 7, 14, 30]));
    a.setUserProp('meteor_bucket',
        AnalyticsService.bucket(meteors, const [1, 50, 200, 500, 1500]));
    a.setUserProp('themes_owned', '${ownedThemes.length}');
  }

  Future<void> addXp(int amount) async {
    final levelBefore = levelInfo().level;
    xp += amount;
    if (levelInfo().level > levelBefore) {
      SoundService.instance.levelUp();
      _logLevelUp();
    }
    notifyListeners();
    await save();
  }

  /// "2x XP" reklam ödülü: XP'nin yanında sabit meteor bonusu da ekler.
  /// (bkz. EconomyConfig.winDoubleXpMeteorBonus, planet_merge_screen.dart)
  Future<void> addXpAndMeteors(int xpAmount, int meteorAmount,
      {String source = 'xp_bonus'}) async {
    final levelBefore = levelInfo().level;
    xp += xpAmount;
    meteors += meteorAmount;
    _earn(source, meteorAmount);
    if (levelInfo().level > levelBefore) {
      SoundService.instance.levelUp();
      _logLevelUp();
    }
    notifyListeners();
    await save();
  }

  // ---------------------------------------------------------------------
  // Tarih yardimcilari
  // ---------------------------------------------------------------------
  /// DUZELTME: Artik cihaz saatine DEGIL, NetworkTimeService (internet/
  /// NTP tabanli, UTC) zamanina dayanir — gun degisimi (gunluk bulmaca,
  /// seri/streak, gunluk sifirlanan haklar) TUM oyuncularda AYNI ANDA
  /// (UTC gece yarisi) olur ve cihaz saati degistirilerek manipule
  /// edilemez. [now] parametresi sadece test/ozel cagrilar icindir.
  static String todayStr([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String yesterdayStr([DateTime? now]) {
    final d =
        (now ?? NetworkTimeService.instance.nowUtc()).subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// UTC gece yarisina sabitlenmis referans nokta — weeklyEpochUtc ile
  /// ayni gun, ayni mantik (bkz. asagisi).
  static final DateTime dailyEpoch = DateTime.utc(2026, 7, 13);

  static int dailyNumber([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(dailyEpoch).inDays;
    return max(1, diff + 1);
  }

  /// Gunluk gorevin seed'i: ayni gun (UTC) herkese ayni sayi, boylece
  /// herkes ayni bulmacayi cozer.
  static int dailySeed([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    return d.year * 10000 + d.month * 100 + d.day;
  }

  /// Kuyruklu Yıldız (Comet Event) referans noktası — weeklyEpochUtc ile
  /// aynı gün. EconomyConfig.cometCycleDays günde bir döngü başlar, ilk
  /// EconomyConfig.cometActiveDays günü boyunca event AÇIK kalır, kalan
  /// günlerde kapalıdır. NetworkTimeService (UTC) kullanır — tüm
  /// oyuncularda cihaz saatinden bağımsız aynı anda başlar/biter.
  static final DateTime cometEpochUtc = DateTime.utc(2026, 7, 13);

  /// Şu anki (veya verilen) zamanın hangi kuyruklu yıldız döngüsüne denk
  /// geldiği — event tahtasının seed'i olarak kullanılır (bkz.
  /// MergeChallenge.comet), böylece o pencerede herkese aynı meydan
  /// okuma gelir.
  static int cometEventNumber([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(cometEpochUtc).inDays;
    if (diff < 0) return 0;
    return diff ~/ EconomyConfig.cometCycleDays;
  }

  /// Şu an bir kuyruklu yıldız penceresi açık mı (oynanabilir mi)?
  static bool cometEventActive([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(cometEpochUtc).inDays;
    if (diff < 0) return false;
    return (diff % EconomyConfig.cometCycleDays) < EconomyConfig.cometActiveDays;
  }

  /// Aktif pencerenin kapanmasına (veya kapalıysa bir sonraki açılışa)
  /// kalan süre — HUD'da geri sayım göstermek için.
  static Duration cometTimeRemaining([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(cometEpochUtc).inDays;
    final phase =
        diff < 0 ? 0 : diff % EconomyConfig.cometCycleDays;
    final daysUntilPhaseEnd = phase < EconomyConfig.cometActiveDays
        ? EconomyConfig.cometActiveDays - phase
        : EconomyConfig.cometCycleDays - phase;
    final phaseEndDay0 = today0.add(Duration(days: daysUntilPhaseEnd));
    return phaseEndDay0.difference(d);
  }

  /// Bir sonraki Kuyruklu Yıldız penceresinin AÇILACAĞI tam an (UTC gece
  /// yarısı). Pencere şu an zaten açıksa null döner — o durumda
  /// bildirime gerek yok, kapanınca bir sonraki döngü için tekrar
  /// hesaplanır (bkz. refreshPeriodicEventNotifications). cometEventActive
  /// ile birebir aynı faz mantığını kullanır, sadece "ne zaman" sorusuna
  /// cevap verir.
  static DateTime? nextCometWindowOpen([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(cometEpochUtc).inDays;
    if (diff < 0) return cometEpochUtc;
    final phase = diff % EconomyConfig.cometCycleDays;
    if (phase < EconomyConfig.cometActiveDays) return null;
    return today0.add(Duration(days: EconomyConfig.cometCycleDays - phase));
  }

  /// Haftalık hedefin ait olduğu "hafta anahtarı". UTC Pazartesi 00:00'a
  /// sabitlenmiş bir referans noktasindan (weeklyEpochUtc) itibaren 7
  /// gunluk bloklar halinde ilerler ve NetworkTimeService (cihaz saatine
  /// DEGIL, internetten alinan gercek zamana) dayanir — boylece TUM
  /// oyuncularda hafta AYNI ANDA (UTC Pazartesi 00:00) baslar/biter ve
  /// kullanicinin cihaz saatini degistirmesiyle manipule edilemez.
  static final DateTime weeklyEpochUtc = DateTime.utc(2026, 7, 13); // Pazartesi

  static String _currentWeekKey([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(weeklyEpochUtc).inDays;
    return (diff ~/ 7).toString();
  }

  /// Haftalık ödül takvimindeki bugünün indexi: 0=Pazartesi ... 6=Pazar.
  /// weeklyEpochUtc zaten bir Pazartesi olduğu için (diff % 7) direkt bu
  /// indexi verir — _currentWeekKey ile aynı referans noktasını kullanır,
  /// yani "hangi hafta" ve "haftanın hangi günü" hep tutarlı kalır.
  static int _currentWeekdayIndex([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final today0 = DateTime.utc(d.year, d.month, d.day);
    final diff = today0.difference(weeklyEpochUtc).inDays;
    return diff % 7;
  }

  /// Aylık hedefin ait olduğu "ay anahtarı" — weeklyEpochUtc'nin ait
  /// olduğu aydan (Temmuz 2026) itibaren gecen takvim ayi sayisi (0, 1,
  /// 2, ...). NetworkTimeService (UTC) kullanir, boylece TUM oyuncularda
  /// ay AYNI ANDA (UTC ayin 1'i, gece yarisi) baslar/biter; weeklyKey ile
  /// ayni "artan tam sayi" mantigi (rotasyon indexi icin).
  static String _currentMonthKey([DateTime? now]) {
    final d = now ?? NetworkTimeService.instance.nowUtc();
    final diff = (d.year - weeklyEpochUtc.year) * 12 +
        (d.month - weeklyEpochUtc.month);
    return diff.toString();
  }

  /// Hafta değiştiyse (weeklyKey güncel değilse) sayaç ve "ödül alındı"
  /// bayrağını sıfırlar. Her ilerleme kaydından ve yüklemeden önce
  /// çağrılır ki oyuncu hangi haftada olduğu bilgisini asla kaçırmasın.
  void _ensureCurrentWeek() {
    final key = _currentWeekKey();
    if (weeklyKey != key) {
      weeklyKey = key;
      weeklyStagesCompleted = 0;
      weeklyRewardClaimed = false;
      weeklyCleanStages = 0;
      weeklyPerfectStages = 0;
      weeklyMeteorsSpent = 0;
      weeklyPlayDates.clear();
      weeklyConstellationStars = 0;
      weeklyConstellationClaimed = false;
    }
  }

  /// Bu haftanın aktif görevi. weeklyKey (7 günde bir artan yerel sayaç)
  /// EconomyConfig.weeklyQuestRotation listesine mod alınarak dönüşümlü
  /// seçilir — sunucu şart değil, ama hafta değişince görev de değişir.
  WeeklyQuestDef get weeklyQuest {
    _ensureCurrentWeek();
    final list = EconomyConfig.weeklyQuestRotation;
    final idx = int.tryParse(weeklyKey) ?? 0;
    return list[idx % list.length];
  }

  /// Aktif görevin tipine göre doğru sayacı okur.
  int get weeklyQuestProgress {
    _ensureCurrentWeek();
    switch (weeklyQuest.type) {
      case WeeklyQuestType.stagesCleared:
        return weeklyStagesCompleted;
      case WeeklyQuestType.cleanStages:
        return weeklyCleanStages;
      case WeeklyQuestType.perfectStars:
        return weeklyPerfectStages;
      case WeeklyQuestType.playDays:
        return weeklyPlayDates.length;
      case WeeklyQuestType.spendMeteors:
        return min(weeklyMeteorsSpent, weeklyQuest.target);
    }
  }

  bool get weeklyGoalReady {
    _ensureCurrentWeek();
    return !weeklyRewardClaimed && weeklyQuestProgress >= weeklyQuest.target;
  }

  int get weeklyGoalRemaining {
    _ensureCurrentWeek();
    return max(0, weeklyQuest.target - weeklyQuestProgress);
  }

  /// Bu haftanın aktif takımyıldızı — constellationRotation'dan weeklyKey'e
  /// göre dönüşümlü seçilir (weeklyQuest ile aynı index mantığı, ama farklı
  /// liste uzunluğu sayesinde aynı hafta aynı fazda olmazlar).
  ConstellationDef get activeConstellation {
    _ensureCurrentWeek();
    final list = EconomyConfig.constellationRotation;
    final idx = int.tryParse(weeklyKey) ?? 0;
    return list[idx % list.length];
  }

  int get constellationProgress {
    _ensureCurrentWeek();
    return min(weeklyConstellationStars, activeConstellation.pointCount);
  }

  bool get constellationGoalReady {
    _ensureCurrentWeek();
    return !weeklyConstellationClaimed &&
        weeklyConstellationStars >= activeConstellation.pointCount;
  }

  /// Bir Gezegen Birleştir oyunu bittiğinde (bkz. recordMergeRun)
  /// çağrılır; [starDelta] o oyunda ulaşılan gezegen kademesinden
  /// hesaplanan puandır (bkz. EconomyConfig.mergeConstellationPoints).
  void _addConstellationStars(int starDelta) {
    if (starDelta <= 0) return;
    _ensureCurrentWeek();
    if (weeklyConstellationClaimed) return;
    weeklyConstellationStars += starDelta;
  }

  /// Takımyıldız tamamlanınca ödülünü verir. claimWeeklyReward ile aynı
  /// "hedef dolmadıysa/zaten alındıysa false dön" akışını izler, ama
  /// ödül BİLEREK meteor DEĞİL: activeConstellation.id kalıcı rozet
  /// koleksiyonuna eklenir (bkz. unlockedConstellationBadges) — meteor
  /// havuzundan ayrı, harcanamayan bir koleksiyon ödülü.
  Future<bool> claimConstellationReward() async {
    if (!constellationGoalReady) return false;
    unlockedConstellationBadges.add(activeConstellation.id);
    _logEvent('constellation_complete', {'id': activeConstellation.id});
    weeklyConstellationClaimed = true;
    notifyListeners();
    await save();
    unawaited(refreshPeriodicEventNotifications());
    return true;
  }

  /// Kuyruklu Yıldız tahtası kazanıldığında çağrılır. Event penceresi
  /// kapalıysa veya bu event zaten tamamlandıysa hiçbir şey değiştirmez
  /// ve false döner (ödül yalnızca aktif pencerede, bölüm başına bir kez).
  Future<bool> recordCometEventComplete() async {
    final eventNum = cometEventNumber();
    if (!cometEventActive() || cometLastCompletedEvent == eventNum) {
      return false;
    }
    cometLastCompletedEvent = eventNum;
    meteors += EconomyConfig.cometMeteorReward;
    _earn('comet', EconomyConfig.cometMeteorReward);
    _logEvent('comet_complete', {'event_no': eventNum});
    final levelBefore = levelInfo().level;
    xp += EconomyConfig.cometXpReward;
    if (levelInfo().level > levelBefore) {
      SoundService.instance.levelUp();
      _logLevelUp();
    }
    notifyListeners();
    await save();
    return true;
  }

  /// Bu event penceresi zaten tamamlandı mı (kart/HUD'da "✓ bitirildi"
  /// göstermek için).
  bool get cometCompletedThisEvent =>
      cometLastCompletedEvent == cometEventNumber();

  /// Ay değiştiyse (monthlyKey güncel değilse) sayaç ve "ödül alındı"
  /// bayrağını sıfırlar. _ensureCurrentWeek ile birebir aynı mantık,
  /// sadece periyot bir takvim ayı.
  void _ensureCurrentMonth() {
    final key = _currentMonthKey();
    if (monthlyKey != key) {
      monthlyKey = key;
      monthlyStagesCompleted = 0;
      monthlyRewardClaimed = false;
      monthlyCleanStages = 0;
      monthlyPerfectStages = 0;
      monthlyMeteorsSpent = 0;
      monthlyPlayDates.clear();
    }
  }

  /// Bu ayın aktif görevi — EconomyConfig.monthlyQuestByMonth SABİT bir
  /// takvim: dönüşümlü DEĞİL, gerçek ay numarasına (NetworkTimeService
  /// UTC üzerinden 1=Ocak..12=Aralık) doğrudan karşılık gelir. Böylece
  /// her yıl aynı ay aynı görevi gösterir (ör. her Aralık aynı görev).
  MonthlyQuestDef get monthlyQuest {
    _ensureCurrentMonth();
    final month = NetworkTimeService.instance.nowUtc().month; // 1..12
    return EconomyConfig.monthlyQuestByMonth[month - 1];
  }

  /// Aktif aylık görevin tipine göre doğru sayacı okur.
  int get monthlyQuestProgress {
    _ensureCurrentMonth();
    switch (monthlyQuest.type) {
      case MonthlyQuestType.stagesCleared:
        return monthlyStagesCompleted;
      case MonthlyQuestType.cleanStages:
        return monthlyCleanStages;
      case MonthlyQuestType.perfectStars:
        return monthlyPerfectStages;
      case MonthlyQuestType.playDays:
        return monthlyPlayDates.length;
      case MonthlyQuestType.spendMeteors:
        return min(monthlyMeteorsSpent, monthlyQuest.target);
    }
  }

  bool get monthlyGoalReady {
    _ensureCurrentMonth();
    return !monthlyRewardClaimed &&
        monthlyQuestProgress >= monthlyQuest.target;
  }

  int get monthlyGoalRemaining {
    _ensureCurrentMonth();
    return max(0, monthlyQuest.target - monthlyQuestProgress);
  }

  /// Bir Gezegen Birleştir oyunu bittiğinde çağrılır (bkz. recordMergeRun).
  /// [clean] o oyunda "devam et" kullanılmadan yeterince yüksek gezegene
  /// ulaşıldıysa true olmalı — "cleanStages" görevi SADECE bunları sayar.
  /// [perfect] en üst başarı eşiğine (EconomyConfig.mergePerfectTier)
  /// ulaşıldıysa true — "perfectStars" görevine sayılır.
  /// Haftalık VE aylık görev sayaçlarını BİRLİKTE günceller (birbirinden
  /// bağımsız periyotlar, ama tek oyun sonucu ikisine de sayılır).
  void _recordWeeklyRunProgress({required bool clean, required bool perfect}) {
    _ensureCurrentWeek();
    if (!weeklyRewardClaimed) {
      weeklyStagesCompleted += 1;
      if (clean) weeklyCleanStages += 1;
      if (perfect) weeklyPerfectStages += 1;
      weeklyPlayDates.add(todayStr());
    }
    _ensureCurrentMonth();
    if (!monthlyRewardClaimed) {
      monthlyStagesCompleted += 1;
      if (clean) monthlyCleanStages += 1;
      if (perfect) monthlyPerfectStages += 1;
      monthlyPlayDates.add(todayStr());
    }
  }

  /// Meteor harcanan HER yerden çağrılır (mağaza satın alımı, rıhtım
  /// hakkı, tema); "spendMeteors" görevi için (haftalık VE aylık) birikir.
  void _recordWeeklyMeteorSpend(int amount) {
    _ensureCurrentWeek();
    if (!weeklyRewardClaimed) weeklyMeteorsSpent += amount;
    _ensureCurrentMonth();
    if (!monthlyRewardClaimed) monthlyMeteorsSpent += amount;
  }

  /// Haftalık görev tamamlanınca aktif görevin ödülünü verir. Hedef
  /// henüz dolmadıysa veya bu hafta zaten alındıysa false döner, hiçbir
  /// şeyi değiştirmez.
  Future<bool> claimWeeklyReward() async {
    if (!weeklyGoalReady) return false;
    meteors += weeklyQuest.reward;
    _earn('weekly_quest', weeklyQuest.reward);
    _logEvent('quest_claim', {'type': 'weekly', 'reward': weeklyQuest.reward});
    weeklyRewardClaimed = true;
    _addPassPoints(PassConfig.weeklyQuestPoints);
    notifyListeners();
    await save();
    unawaited(refreshPeriodicEventNotifications());
    return true;
  }

  /// Aylık görev tamamlanınca aktif görevin ödülünü verir — claimWeeklyReward
  /// ile birebir aynı mantık, sadece aylık sayaç/bayrak üzerinden.
  Future<bool> claimMonthlyReward() async {
    if (!monthlyGoalReady) return false;
    meteors += monthlyQuest.reward;
    _earn('monthly_quest', monthlyQuest.reward);
    _logEvent('quest_claim', {'type': 'monthly', 'reward': monthlyQuest.reward});
    monthlyRewardClaimed = true;
    _addPassPoints(PassConfig.monthlyQuestPoints);
    notifyListeners();
    await save();
    unawaited(refreshPeriodicEventNotifications());
    return true;
  }

  /// Bu haftanın bittiği (bir sonraki haftanın 7 günlük bloğunun
  /// başladığı) UTC an — weeklyKey'den ("epoch'tan bu yana kaçıncı
  /// hafta") geri hesaplanır.
  DateTime get _weeklyPeriodEndUtc {
    _ensureCurrentWeek();
    final weekIndex = int.tryParse(weeklyKey) ?? 0;
    return weeklyEpochUtc.add(Duration(days: (weekIndex + 1) * 7));
  }

  /// Bu ayın bittiği (bir sonraki takvim ayının başladığı) UTC an.
  DateTime get _monthlyPeriodEndUtc {
    _ensureCurrentMonth();
    final now = NetworkTimeService.instance.nowUtc();
    return now.month == 12
        ? DateTime.utc(now.year + 1, 1, 1)
        : DateTime.utc(now.year, now.month + 1, 1);
  }

  /// Kuyruklu Yıldız açılışı / haftalık görev / aylık görev bildirimlerini
  /// tek yerden günceller. Uygulama açılışında, on plana her dönüşte
  /// (streak/comeback hatırlatmalarıyla aynı noktalarda) VE ilgili
  /// ilerleme kaydedildiğinde (bölüm bitirme, ödül alma) çağrılır.
  /// Hedef zaten tutturulmuş/alınmışsa ilgili bildirim hemen iptal edilir
  /// — streak/comeback ile aynı "oyuncu zaten düzenli oynuyorsa bildirim
  /// asla tetiklenmez" felsefesi.
  Future<void> refreshPeriodicEventNotifications() async {
    final opensAt = nextCometWindowOpen();
    if (opensAt != null) {
      unawaited(NotificationService.instance.scheduleCometWindowOpen(opensAt));
    } else {
      unawaited(NotificationService.instance.cancelCometWindowOpen());
    }

    _ensureCurrentWeek();
    if (weeklyRewardClaimed || weeklyGoalReady) {
      unawaited(NotificationService.instance.cancelWeeklyQuestReminder());
    } else {
      final remindOn = _weeklyPeriodEndUtc.subtract(const Duration(days: 2));
      unawaited(
          NotificationService.instance.scheduleWeeklyQuestReminder(remindOn));
    }

    _ensureCurrentMonth();
    if (monthlyRewardClaimed || monthlyGoalReady) {
      unawaited(NotificationService.instance.cancelMonthlyQuestReminder());
    } else {
      final remindOn = _monthlyPeriodEndUtc.subtract(const Duration(days: 3));
      unawaited(
          NotificationService.instance.scheduleMonthlyQuestReminder(remindOn));
    }
  }

  // ---------------------------------------------------------------------
  // Gezegen Birlestir (ana oyun) sonuc kaydi
  // ---------------------------------------------------------------------
  /// Sonsuz modda oyun bittiginde (ve "devam et" sonrasi tekrar
  /// bittiginde) cagrilir. IDEMPOTENT: rekorlari (en iyi skor / en yuksek
  /// gezegen) gunceller, ilk kez ulasilan gezegenleri koleksiyona ekler
  /// ve YENI rekor kademeleri icin tek seferlik meteor tutarini dondurur
  /// (cagiran taraf bunu addXpAndMeteors ile oyuncuya yazar).
  Future<int> settleMergeRecords({
    required int score,
    required int bestTier,
  }) async {
    var meteorsEarned = 0;
    for (var tr = max(mergeBestTier + 1, 0); tr <= bestTier; tr++) {
      meteorsEarned += EconomyConfig.mergeMeteorsForNewTier(tr);
    }
    var changed = false;
    var newPlanets = false;
    for (var tr = 0; tr <= bestTier && tr < PlanetMergeConfig.tierCount; tr++) {
      if (discoveredPlanets.add(tr)) {
        newPlanets = true;
        _logEvent('planet_discovered',
            {'tier': tr, 'total': discoveredPlanets.length});
      }
    }
    if (newPlanets) {
      changed = true;
    }
    _syncRecordPeriods();
    if (score > mergeBestToday) {
      mergeBestToday = score;
      changed = true;
    }
    if (score > mergeBestWeek) {
      mergeBestWeek = score;
      changed = true;
    }
    if (score > mergeBestScore) {
      mergeBestScore = score;
      changed = true;
    }
    if (bestTier > mergeBestTier) {
      mergeBestTier = bestTier;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      await save();
    }
    return meteorsEarned;
  }

  /// Bir oyun (sonsuz mod ya da gunluk/kuyruklu yildiz meydan okumasi
  /// denemesi) KESIN bittiginde (tekrar oyna / cik) bir kez cagrilir:
  /// toplam skor, oynanan oyun sayisi, haftalik/aylik gorev sayaclari ve
  /// takimyildiz puani burada islenir. Cok kisa oyunlar (hic
  /// birlestirmeden birakilanlar) sayilmaz.
  Future<void> recordMergeRun({
    required int score,
    required int bestTier,
    required int drops,
    required bool usedContinue,
  }) async {
    if (drops < EconomyConfig.mergeMinDropsForRun) return;
    mergeRunsPlayed += 1;
    recordMission(MissionMetric.runs, 1);
    recordMission(MissionMetric.runScore, score);
    totalScore += score;
    _recordWeeklyRunProgress(
      clean: bestTier >= EconomyConfig.mergeCleanTier && !usedContinue,
      perfect: bestTier >= EconomyConfig.mergePerfectTier,
    );
    _addConstellationStars(EconomyConfig.mergeConstellationPoints(bestTier));
    _syncAnalyticsProps();
    notifyListeners();
    await save();
    unawaited(PlayGamesService.instance.submitScore(totalScore));
    unawaited(PlayGamesService.instance.submitRunScore(score, levelInfo().level));
    unawaited(refreshPeriodicEventNotifications());
  }

  // ---------------------------------------------------------------------
  // Haftalık Ödül Takvimi (Pazartesi-Pazar, Empires & Puzzles tarzı)
  // ---------------------------------------------------------------------

  /// weeklyRewardWeekKey ile şu anki takvim haftası uyuşmuyorsa (yeni bir
  /// Pazartesi başlamışsa) 7 kutuyu da sıfırlar. Her okuma/claim'den önce
  /// çağrılır — kullanıcı arayüzü ile arka uç hep aynı haftayı görür.
  void _syncWeeklyRewardWeek([DateTime? now]) {
    final key = _currentWeekKey(now);
    if (weeklyRewardWeekKey != key) {
      weeklyRewardWeekKey = key;
      weeklyRewardClaimedDays = List<bool>.filled(7, false);
    }
  }

  /// Haftalık takvimdeki bugünün indexi (0=Pazartesi...6=Pazar).
  int weeklyRewardTodayIndex([DateTime? now]) => _currentWeekdayIndex(now);

  /// UI'nin 7 kutuyu çizerken her biri için kullanacağı durum.
  WeeklyRewardDayState weeklyRewardDayState(int dayIndex, [DateTime? now]) {
    _syncWeeklyRewardWeek(now);
    final todayIndex = _currentWeekdayIndex(now);
    if (dayIndex == todayIndex) {
      return weeklyRewardClaimedDays[dayIndex]
          ? WeeklyRewardDayState.claimed
          : WeeklyRewardDayState.claimableToday;
    }
    if (dayIndex < todayIndex) {
      return weeklyRewardClaimedDays[dayIndex]
          ? WeeklyRewardDayState.claimed
          : WeeklyRewardDayState.missed;
    }
    return WeeklyRewardDayState.future;
  }

  /// Bugünün ödülü daha önce alınmış mı (buton "alındı" mı göstermeli).
  bool weeklyRewardIsTodayClaimed([DateTime? now]) {
    _syncWeeklyRewardWeek(now);
    return weeklyRewardClaimedDays[_currentWeekdayIndex(now)];
  }

  /// Pazar bonusunun bu hafta hâlâ mümkün olup olmadığı (Pzt-Cmt'nin
  /// hepsi alınmışsa true) — takvimde Pazar kutusunun üstünde "🎁 Bonus"
  /// rozetini göstermek/gizlemek için kullanılır.
  bool weeklyRewardSundayBonusEligible([DateTime? now]) {
    _syncWeeklyRewardWeek(now);
    for (var i = 0; i < 6; i++) {
      if (!weeklyRewardClaimedDays[i]) return false;
    }
    return true;
  }

  /// Bugünün ödülünü talep eder. Zaten alınmışsa null döner (UI hata
  /// göstermemeli, buton zaten pasif olmalı). Bugün Pazar (index 6) ve
  /// Pzt-Cmt'nin hepsi alınmışsa, taban ödülün üstüne
  /// EconomyConfig.weeklyRewardSundayBonus da otomatik eklenir.
  Future<WeeklyRewardClaimResult?> claimWeeklyLoginReward([DateTime? now]) async {
    _syncWeeklyRewardWeek(now);
    final todayIndex = _currentWeekdayIndex(now);
    if (weeklyRewardClaimedDays[todayIndex]) return null;

    final isSunday = todayIndex == 6;
    final bonusEligible = isSunday && weeklyRewardSundayBonusEligible(now);

    final base = EconomyConfig.weeklyRewardMeteor[todayIndex];
    final bonus = bonusEligible ? EconomyConfig.weeklyRewardSundayBonus : 0;

    weeklyRewardClaimedDays[todayIndex] = true;
    meteors += base + bonus;
    _earn('weekly_login', base + bonus);
    _logEvent('weekly_login_claim',
        {'day_index': todayIndex, 'bonus': bonus > 0 ? 1 : 0});

    notifyListeners();
    await save();

    return WeeklyRewardClaimResult(
      baseMeteor: base,
      bonusMeteor: bonus,
      isSundayBonus: bonusEligible,
    );
  }


  Future<void> recordDailyResult({
    required int moves,
    required int optimal,
    required int timeSeconds,
    int score = 0,
    int bestTier = 0,
  }) async {
    final today = todayStr();
    var streakAdvanced = false;
    if (dailyLastCompletedDate == yesterdayStr()) {
      dailyStreak += 1;
      streakAdvanced = true;
    } else if (dailyLastCompletedDate != today) {
      if (streakProtectedByShield) {
        // Tam 1 gun kacirildi ve koruyucu var: seri kopmadan devam eder.
        streakShields -= 1;
        dailyStreak += 1;
        _shieldJustUsed = true;
        _logEvent('streak_shield_used', {'streak': dailyStreak});
      } else {
        if (dailyStreak > 1) {
          _logEvent('streak_lost', {'previous': dailyStreak});
        }
        dailyStreak = 1;
      }
      streakAdvanced = true;
    }
    dailyLastCompletedDate = today;
    if (streakAdvanced) {
      if (dailyStreak > bestDailyStreak) bestDailyStreak = dailyStreak;
      if (dailyStreak % EconomyConfig.streakShieldEvery == 0 &&
          streakShields < EconomyConfig.streakShieldMax) {
        streakShields += 1;
      }
    }
    // ---- Seri v2: kademeli gunluk bonus + kilometre tasi + hafta ici ----
    final dayMeteors = EconomyConfig.dailyStreakMeteor(dailyStreak);
    meteors += dayMeteors;
    _earn('daily_streak', dayMeteors);
    StreakMilestone? hitMilestone;
    if (streakAdvanced) {
      final m = EconomyConfig.streakMilestoneFor(dailyStreak);
      if (m != null && !streakMilestonesClaimed.contains(m.day)) {
        streakMilestonesClaimed.add(m.day);
        meteors += m.meteors;
        _earn('streak_milestone', m.meteors);
        _logEvent('streak_milestone', {'day': m.day});
        if (m.bomb > 0) _addPower('bomb', m.bomb);
        if (m.swap > 0) _addPower('swap', m.swap);
        if (m.shake > 0) _addPower('shake', m.shake);
        if (m.shield > 0) {
          streakShields =
              min(EconomyConfig.streakShieldMax, streakShields + m.shield);
        }
        hitMilestone = m;
      }
    }
    final wd = NetworkTimeService.instance.nowUtc().weekday; // 1=Pzt..7=Paz
    final weekStart = dailyNumber() - (wd - 1);
    if (weekStart != dailyWeekStart) {
      dailyWeekStart = weekStart;
      dailyWeekMask = 0;
    }
    dailyWeekMask |= 1 << (wd - 1);
    var weekendBonus = 0;
    if (wd >= 6 &&
        (dailyWeekMask & 0x1F) == 0x1F &&
        weekendBonusWeek != weekStart) {
      weekendBonus = EconomyConfig.weekendStreakBonusMeteor;
      weekendBonusWeek = weekStart;
      meteors += weekendBonus;
      _earn('weekend_bonus', weekendBonus);
    }
    _logEvent('daily_complete', {
      'streak': dailyStreak,
      'score': score,
      'best_tier': bestTier,
      'time_s': timeSeconds,
      'moves': moves,
      'advanced': streakAdvanced ? 1 : 0,
    });
    lastStreakReward = StreakRewardResult(
      streak: dailyStreak,
      dailyMeteors: dayMeteors,
      milestone: hitMilestone,
      weekendBonus: weekendBonus,
      difficultyLevel: EconomyConfig.streakDifficultyLevel(dailyStreak),
    );
    final stars =
        moves <= optimal ? 3 : (moves <= (optimal * 1.5).ceil() ? 2 : 1);
    final gainedXp = 30 + stars * 10;
    final levelBeforeDaily = levelInfo().level;
    xp += gainedXp;
    if (levelInfo().level > levelBeforeDaily) {
      SoundService.instance.levelUp();
      _logLevelUp();
    }
    dailyLastResult = DailyResult(
      dailyNum: dailyNumber(),
      moves: moves,
      optimal: optimal,
      stars: stars,
      timeSeconds: timeSeconds,
      xp: gainedXp,
      score: score,
      bestTier: bestTier,
    );
    notifyListeners();
    await save();
    // Bugunku gunluk bulmaca tamamlandi: hatirlatma bildirimini hemen
    // YARINA ertele, boylece bugun icin gereksiz bir hatirlatma kalmaz.
    unawaited(NotificationService.instance
        .refreshDailyStreakReminder(playedToday: true));
  }

  Future<void> claimDailyDouble() async {
    final r = dailyLastResult;
    if (r == null || r.doubled) return;
    xp += r.xp;
    r.doubled = true;
    notifyListeners();
    await save();
  }

  bool get dailyCompletedToday => dailyLastCompletedDate == todayStr();

  // ---------------------------------------------------------------------
  // Kozmik Ikmal (resupply): 2 saatte bir acilan, art arda 3 reklam
  // izlenebilen odul bankasi.
  // ---------------------------------------------------------------------
  bool get isResupplyReady =>
      lastResupplyTime == 0 ||
      (DateTime.now().millisecondsSinceEpoch - lastResupplyTime) >=
          resupplyCooldownMs;

  String resupplyCountdownText() {
    final remainMs = resupplyCooldownMs -
        (DateTime.now().millisecondsSinceEpoch - lastResupplyTime);
    final remainMin = max(0, (remainMs / 60000).ceil());
    final h = remainMin ~/ 60;
    final m = remainMin % 60;
    return h > 0 ? '${h}s ${m}dk' : '${m}dk';
  }

  /// Bir Kozmik Ikmal reklami izlendikten sonra cagrilir. Olasilik
  /// tablosu (EconomyConfig'te tek yerden kontrol edilir):
  ///   %5 -> 10 meteor, %10 -> 5 meteor, %15 -> 3 meteor, %20 -> 2 meteor
  ///   (meteor dilimi toplam %50)
  ///   %50 -> 1 meteor (reklam artik XP vermez, bonus meteor yok).
  /// 3. reklamdan sonra 2 saatlik bekleme baslatir.
  Future<ResupplyReward> grantResupplyReward(Random rng) async {
    final roll = rng.nextDouble();
    ResupplyReward reward;
    double cursor = 0;

    // Ekonomi dengeleme: eski "her izlemede 1-5 bonus meteor" kaldırıldı.
    const bonusMeteors = 0;

    cursor += EconomyConfig.pMeteor10;
    if (roll < cursor) {
      meteors += 10;
      reward = ResupplyReward(ResupplyRewardKind.meteor, 10,
          bonusMeteors: bonusMeteors);
    } else if (roll < (cursor += EconomyConfig.pMeteor5)) {
      meteors += 5;
      reward = ResupplyReward(ResupplyRewardKind.meteor, 5,
          bonusMeteors: bonusMeteors);
    } else if (roll < (cursor += EconomyConfig.pMeteor3)) {
      meteors += 3;
      reward = ResupplyReward(ResupplyRewardKind.meteor, 3,
          bonusMeteors: bonusMeteors);
    } else if (roll < (cursor += EconomyConfig.pMeteor2)) {
      meteors += 2;
      reward = ResupplyReward(ResupplyRewardKind.meteor, 2,
          bonusMeteors: bonusMeteors);
    } else {
      // Eski XP dilimi: artik reklam XP vermiyor, 1 meteor veriyor.
      meteors += 1;
      reward = ResupplyReward(ResupplyRewardKind.meteor, 1,
          bonusMeteors: bonusMeteors);
    }
    _earn('resupply', bonusMeteors + reward.amount);
    _logEvent('resupply_claim', {
      'main': reward.amount,
      'bonus': bonusMeteors,
      'ad_index': resupplyAdsWatched + 1,
    });
    resupplyAdsWatched += 1;
    if (resupplyAdsWatched >= resupplyAdsRequired) {
      resupplyAdsWatched = 0;
      lastResupplyTime = DateTime.now().millisecondsSinceEpoch;
      // 2 saatlik bekleme suresi tam bittigi anda "Kozmik Ikmalde
      // Odullerin Hazir!" bildirimi gonderilsin diye zamanla. Uygulama
      // o an kapali/arka planda olsa bile bildirim gelir (OS tarafinda
      // zamanlanmis alarm).
      unawaited(NotificationService.instance.scheduleResupplyReady(
        DateTime.fromMillisecondsSinceEpoch(
            lastResupplyTime + resupplyCooldownMs),
      ));
    }
    notifyListeners();
    await save();
    return reward;
  }

  // ---------------------------------------------------------------------
  // Kurtarma hakki ("Kabini hafiflet"): oyun bitince reklam izlemeden
  // devam etmeyi saglar. Meteorla onceden stoklanir (Malzeme Magazasi).
  // ---------------------------------------------------------------------
  Future<void> spendBankedRescue() async {
    bankedRescues = max(0, bankedRescues - 1);
    notifyListeners();
    await save();
  }

  // ---------------------------------------------------------------------
  // Elde tutma: seri koruyucu / kurtarma, donus hediyesi, rutbe,
  // koleksiyon, yerel basarimlar
  // ---------------------------------------------------------------------
  static int _epochDay() => NetworkTimeService.instance
      .nowUtc()
      .difference(DateTime.utc(2024, 1, 1))
      .inDays;

  /// Son tamamlanan gunluk sinyalden bu yana kac gun gecti (0 bugun).
  int _daysSinceDaily() {
    final p = dailyLastCompletedDate.split('-');
    if (p.length != 3) return 9999;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return 9999;
    final now = NetworkTimeService.instance.nowUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.difference(DateTime.utc(y, m, d)).inDays;
  }

  /// Tam 1 gun kacirildi ve koruyucu var: seri korunuyor sayilir.
  bool get streakProtectedByShield =>
      dailyStreak > 0 && streakShields > 0 && _daysSinceDaily() == 2;

  /// Ekranda gosterilecek seri (kopmus seri 0 gorunur).
  int get activeDailyStreak {
    if (_daysSinceDaily() <= 1 || streakProtectedByShield) return dailyStreak;
    return 0;
  }

  /// En az 3 gunluk seri 1-3 gun once koptuysa ve bugun teklif edilmediyse.
  bool get streakRescueAvailable {
    final d = _daysSinceDaily();
    return dailyStreak >= 3 &&
        d >= 2 &&
        d <= 4 &&
        !streakProtectedByShield &&
        streakRescueOfferedDay != todayStr();
  }

  Future<void> markStreakRescueOffered() async {
    streakRescueOfferedDay = todayStr();
    await save();
  }

  void _applyStreakRescue() {
    dailyLastCompletedDate = yesterdayStr();
    streakRescueOfferedDay = todayStr();
  }

  Future<bool> rescueStreakWithMeteors() =>
      _buyBankedItem(streakRescueCurrentCost, _applyStreakRescue, 'streak_rescue');

  /// Seri kurtarmanin su anki bedeli (seri uzadikca artar).
  int get streakRescueCurrentCost =>
      EconomyConfig.streakRescueCostFor(dailyStreak);

  /// Oyuncunun su anki serisine gore gunluk meydan okuma zorluk seviyesi.
  int get streakDifficultyLevel =>
      EconomyConfig.streakDifficultyLevel(activeDailyStreak);

  /// Siradaki (alinmamis) seri kilometre tasi.
  StreakMilestone? get nextStreakMilestone => EconomyConfig.nextStreakMilestone(
      activeDailyStreak, streakMilestonesClaimed);

  /// Kalici seri unvani (en uzun seriye gore), yoksa null.
  String? get streakTitleKey => EconomyConfig.streakTitleKey(
      max(bestDailyStreak, dailyStreak));

  /// Seri koruyucuyu meteorla satin alir. Depo doluysa ya da meteor
  /// yetmezse false.
  Future<bool> buyStreakShield() {
    if (streakShields >= EconomyConfig.streakShieldMax) {
      return Future<bool>.value(false);
    }
    return _buyBankedItem(EconomyConfig.streakShieldPrice,
        () => streakShields += 1, 'streak_shield');
  }

  Future<void> rescueStreakFree() async {
    _logEvent('streak_rescue_free', {'streak': dailyStreak});
    _applyStreakRescue();
    notifyListeners();
    await save();
  }

  /// Koruyucu serisi kurtardiysa bir kez true doner (toast icin).
  bool consumeShieldNotice() {
    final v = _shieldJustUsed;
    _shieldJustUsed = false;
    return v;
  }

  /// Uygulama acilisinda (ana ekran ilk acilista) cagrilir: uzun suredir
  /// gelmeyen oyuncu icin "donus hediyesi" hazirlar.
  Future<void> noteAppOpen() async {
    final today = _epochDay();
    final away = lastSeenDayNum < 0 ? 0 : today - lastSeenDayNum;
    lastSeenDayNum = today;
    _logEvent('app_open_state', {'days_away': away, 'runs': mergeRunsPlayed});
    _syncAnalyticsProps();
    if (comebackGiftPending == 0 &&
        away >= EconomyConfig.comebackGiftMinDays &&
        today - lastComebackGiftDayNum >=
            EconomyConfig.comebackGiftCooldownDays) {
      comebackGiftPending = away >= 7 ? 2 : 1;
    }
    await save();
  }

  /// Bekleyen donus hediyesini verir (null: yok).
  Future<PassReward?> claimComebackGift() async {
    if (comebackGiftPending == 0) return null;
    final long = comebackGiftPending == 2;
    final r = long
        ? const PassReward(meteors: 30, bomb: 1, swap: 1, shake: 1)
        : const PassReward(meteors: 15, shake: 1);
    meteors += r.meteors;
    _earn('comeback_gift', r.meteors);
    _logEvent('comeback_gift', {'long_away': long ? 1 : 0});
    if (r.bomb > 0) _addPower('bomb', r.bomb);
    if (r.swap > 0) _addPower('swap', r.swap);
    if (r.shake > 0) _addPower('shake', r.shake);
    lastComebackGiftDayNum = _epochDay();
    comebackGiftPending = 0;
    notifyListeners();
    await save();
    return r;
  }

  // ---- Rutbe ----
  int get rankIndex => Ranks.indexForLevel(levelInfo().level);
  bool get rankRewardPending => rankIndex > rankClaimed;

  /// Yeni rutbelerin odullerini verir; verilen toplam meteoru dondurur.
  Future<int> claimRankRewards() async {
    final idx = rankIndex;
    if (idx <= rankClaimed) return 0;
    var sum = 0;
    for (var i = rankClaimed + 1; i <= idx; i++) {
      sum += Ranks.all[i].rewardMeteors;
    }
    meteors += sum;
    _earn('rank', sum);
    _logEvent('rank_up', {'rank_idx': idx, 'level': levelInfo().level});
    rankClaimed = idx;
    notifyListeners();
    await save();
    return sum;
  }

  // ---- Gezegen koleksiyonu ----
  bool collectionClaimable(int threshold) =>
      discoveredPlanets.length >= threshold &&
      !collectionClaimed.contains(threshold);

  int get collectionClaimableCount =>
      Milestones.collectionRewards.keys
          .where((k) => collectionClaimable(k))
          .length +
      unseenSkinCount;

  Future<int> claimCollection(int threshold) async {
    if (!collectionClaimable(threshold)) return 0;
    final reward = Milestones.collectionRewards[threshold] ?? 0;
    collectionClaimed.add(threshold);
    meteors += reward;
    _earn('collection', reward);
    _logEvent('collection_claim', {'threshold': threshold});
    notifyListeners();
    await save();
    return reward;
  }

  // ---- Gizli gezegenler (skin) ----
  int skinProgressValue(PlanetSkin s) => achievementValue(s.metric);

  bool skinUnlocked(PlanetSkin s) => skinProgressValue(s) >= s.target;

  bool skinEquipped(PlanetSkin s) =>
      equippedSkins.contains(s.id) && skinUnlocked(s);

  /// [tier] icin takili (ve acik) skin; yoksa null.
  PlanetSkin? activeSkinFor(int tier) {
    for (final s in PlanetSkins.all) {
      if (s.tier == tier && skinEquipped(s)) return s;
    }
    return null;
  }

  /// Oyunda [tier] icin cizilecek gorsel indeksi (skin varsa onun, yoksa varsayilan).
  int activeImage(int tier) =>
      activeSkinFor(tier)?.image ?? PlanetMergeConfig.tierImage[tier];

  double activeDrawScale(int tier) =>
      activeSkinFor(tier)?.drawScale ?? PlanetMergeConfig.tierDrawScale[tier];

  /// Acilmis ama Koleksiyon ekraninda henuz gorulmemis skin sayisi.
  int get unseenSkinCount => PlanetSkins.all
      .where((s) => skinUnlocked(s) && !skinsSeen.contains(s.id))
      .length;

  Future<void> markSkinsSeen() async {
    var changed = false;
    for (final s in PlanetSkins.all) {
      if (skinUnlocked(s) && skinsSeen.add(s.id)) changed = true;
    }
    if (changed) {
      notifyListeners();
      await save();
    }
  }

  Future<void> toggleSkin(PlanetSkin s) async {
    if (!skinUnlocked(s)) return;
    if (!equippedSkins.add(s.id)) equippedSkins.remove(s.id);
    notifyListeners();
    await save();
  }

  // ---- Yerel basarimlar ----
  int achievementValue(AchMetric m) => switch (m) {
        AchMetric.runs => mergeRunsPlayed,
        AchMetric.merges => lifetimeMerges,
        AchMetric.bestScore => mergeBestScore,
        AchMetric.bestCombo => bestComboEver,
        AchMetric.planets => discoveredPlanets.length,
        AchMetric.streak => max(bestDailyStreak, dailyStreak),
        AchMetric.powerUses => lifetimePowerUses,
      };

  bool achievementDone(LocalAchievement a) =>
      achievementValue(a.metric) >= a.target;

  bool achievementClaimable(LocalAchievement a) =>
      achievementDone(a) && !achClaimed.contains(a.id);

  int get achievementClaimableCount =>
      Milestones.achievements.where(achievementClaimable).length;

  Future<int> claimAchievement(LocalAchievement a) async {
    if (!achievementClaimable(a)) return 0;
    achClaimed.add(a.id);
    meteors += a.rewardMeteors;
    _earn('achievement', a.rewardMeteors);
    _logEvent('unlock_achievement', {'achievement_id': a.id});
    notifyListeners();
    await save();
    return a.rewardMeteors;
  }

  /// Koleksiyon ekranina bakilacak bir sey var mi (rozet noktasi icin).
  int get collectionBadgeCount =>
      collectionClaimableCount +
      achievementClaimableCount +
      (rankRewardPending ? 1 : 0);

  // ---------------------------------------------------------------------
  // Gunluk / haftalik rekorlar
  // ---------------------------------------------------------------------
  void _syncRecordPeriods() {
    final day = todayStr();
    if (mergeBestTodayKey != day) {
      mergeBestTodayKey = day;
      mergeBestToday = 0;
    }
    final week = WeeklyRules.weekNumber(NetworkTimeService.instance.nowUtc());
    if (mergeBestWeekNum != week) {
      mergeBestWeekNum = week;
      mergeBestWeek = 0;
    }
  }

  /// Bugunun en yuksek Sonsuz Mod skoru.
  int get bestToday {
    _syncRecordPeriods();
    return mergeBestToday;
  }

  /// Bu haftanin (haftalik kural periyodunun) en yuksek skoru.
  int get bestWeek {
    _syncRecordPeriods();
    return mergeBestWeek;
  }

  // ---------------------------------------------------------------------
  // Gunluk gorevler + Galaksi Yolu
  // ---------------------------------------------------------------------
  static int _missionDayNumber() => NetworkTimeService.instance
      .nowUtc()
      .difference(DateTime.utc(2024, 1, 1))
      .inDays;

  void _syncMissionDay() {
    final key = todayStr();
    if (missionDayKey != key) {
      missionDayKey = key;
      missionProgress = <String, int>{};
      missionClaimed = <String>{};
      missionBonusClaimed = false;
    }
  }

  void _syncPassSeason() {
    final key = _currentMonthKey();
    if (passSeasonKey != key) {
      passSeasonKey = key;
      passPoints = 0;
      passClaimedLevels = <int>{};
    }
  }

  /// Bugunun 3 gunluk gorevi.
  List<DailyMissionDef> get todaysMissions {
    _syncMissionDay();
    return DailyMissions.forDay(_missionDayNumber());
  }

  /// Gorev ilerlemesi (hedefi asmaz).
  int missionValue(DailyMissionDef d) {
    _syncMissionDay();
    return min(missionProgress[d.id] ?? 0, d.target);
  }

  bool missionDone(DailyMissionDef d) => missionValue(d) >= d.target;
  bool missionIsClaimed(DailyMissionDef d) {
    _syncMissionDay();
    return missionClaimed.contains(d.id);
  }

  /// Oyun icinden cagrilir; kaydi (save) bir sonraki oyun bitisinde yapilir,
  /// bu yuzden her birlestirmede disk yazimi/bildirim yok.
  void recordMission(MissionMetric metric, int value) {
    switch (metric) {
      case MissionMetric.merges:
        lifetimeMerges += value;
      case MissionMetric.drops:
        lifetimeDrops += value;
      case MissionMetric.bestCombo:
        if (value > bestComboEver) bestComboEver = value;
      case MissionMetric.powerUses:
        lifetimePowerUses += value;
      default:
        break;
    }
    _syncMissionDay();
    for (final d in DailyMissions.forDay(_missionDayNumber())) {
      if (d.metric != metric) continue;
      final cur = missionProgress[d.id] ?? 0;
      missionProgress[d.id] = d.isMax ? max(cur, value) : cur + value;
    }
  }

  /// Gorev puanini alir; verilen Yildiz puanini dondurur (0: alinamadi).
  Future<int> claimMission(DailyMissionDef d) async {
    _syncMissionDay();
    if (!missionDone(d) || missionClaimed.contains(d.id)) return 0;
    missionClaimed.add(d.id);
    _logEvent('mission_claim', {'id': d.id, 'points': d.points});
    _addPassPoints(d.points);
    notifyListeners();
    await save();
    return d.points;
  }

  bool get missionBonusReady {
    _syncMissionDay();
    if (missionBonusClaimed) return false;
    return todaysMissions.every((d) => missionClaimed.contains(d.id));
  }

  Future<int> claimMissionBonus() async {
    if (!missionBonusReady) return 0;
    missionBonusClaimed = true;
    _logEvent('mission_bonus_claim');
    _addPassPoints(PassConfig.dailyBonusPoints);
    notifyListeners();
    await save();
    return PassConfig.dailyBonusPoints;
  }

  /// Alinabilir (tamamlanmis ama alinmamis) gunluk gorev sayisi (+ bonus).
  int get missionClaimableCount {
    var n = 0;
    for (final d in todaysMissions) {
      if (missionDone(d) && !missionClaimed.contains(d.id)) n++;
    }
    if (missionBonusReady) n++;
    return n;
  }

  void _addPassPoints(int n) {
    _syncPassSeason();
    passPoints += n;
  }

  int get passLevel {
    _syncPassSeason();
    return min(passPoints ~/ PassConfig.pointsPerLevel, PassConfig.maxLevel);
  }

  /// Mevcut seviye icinde biriken puan (son seviyede tam dolu).
  int get passPointsInLevel {
    _syncPassSeason();
    if (passLevel >= PassConfig.maxLevel) return PassConfig.pointsPerLevel;
    return passPoints % PassConfig.pointsPerLevel;
  }

  bool passLevelClaimable(int level) {
    _syncPassSeason();
    return level >= 1 &&
        level <= passLevel &&
        !passClaimedLevels.contains(level);
  }

  int get passClaimableCount {
    var n = 0;
    for (var l = 1; l <= passLevel; l++) {
      if (!passClaimedLevels.contains(l)) n++;
    }
    return n;
  }

  /// Sezonun bitimine (ay sonu, UTC) kalan sure.
  Duration get passTimeRemaining {
    final d = _monthlyPeriodEndUtc.difference(NetworkTimeService.instance.nowUtc());
    return d.isNegative ? Duration.zero : d;
  }

  /// Gunluk gorevlerin yenilenmesine (UTC gece yarisi) kalan sure.
  Duration get missionResetIn {
    final now = NetworkTimeService.instance.nowUtc();
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    return next.difference(now);
  }

  /// Seviye odulunu verir; null: alinamadi.
  Future<PassReward?> claimPassLevel(int level) async {
    if (!passLevelClaimable(level)) return null;
    final r = PassConfig.rewards[level - 1];
    passClaimedLevels.add(level);
    meteors += r.meteors;
    _earn('galaxy_pass', r.meteors);
    _logEvent('pass_level_claim', {'level': level});
    xp += r.xp;
    if (r.bomb > 0) _addPower('bomb', r.bomb);
    if (r.swap > 0) _addPower('swap', r.swap);
    if (r.shake > 0) _addPower('shake', r.shake);
    notifyListeners();
    await save();
    return r;
  }

  // ---------------------------------------------------------------------
  // Guclendiriciler ('bomb' = sil, 'swap' = degistir, 'shake' = salla)
  // ---------------------------------------------------------------------
  int powerCount(String kind) => switch (kind) {
        'bomb' => powerBombs,
        'swap' => powerSwaps,
        _ => powerShakes,
      };

  static int powerPrice(String kind) => switch (kind) {
        'bomb' => EconomyConfig.powerBombPrice,
        'swap' => EconomyConfig.powerSwapPrice,
        _ => EconomyConfig.powerShakePrice,
      };

  void _addPower(String kind, int n) {
    switch (kind) {
      case 'bomb':
        powerBombs += n;
      case 'swap':
        powerSwaps += n;
      default:
        powerShakes += n;
    }
  }

  /// Envanterden 1 adet harcar. Yoksa false doner.
  Future<bool> usePower(String kind) async {
    if (powerCount(kind) <= 0) return false;
    _addPower(kind, -1);
    recordMission(MissionMetric.powerUses, 1);
    notifyListeners();
    await save();
    return true;
  }

  /// Reklam / ozel odul ile 1 (veya [n]) adet verir.
  Future<void> grantPower(String kind, [int n = 1, String source = 'other']) async {
    _addPower(kind, n);
    _logEvent('power_grant', {'kind': kind, 'n': n, 'source': source});
    notifyListeners();
    await save();
  }

  /// Meteorla satin alir (envantere +1). Meteor yetmezse false.
  Future<bool> buyPowerWithMeteors(String kind) => _buyBankedItem(
      powerPrice(kind), () => _addPower(kind, 1), 'power_$kind');

  Future<bool> buyRescueWithMeteors() => _buyBankedItem(
      EconomyConfig.rescueShopPrice, () => bankedRescues += 1, 'rescue_banked');

  Future<bool> _buyBankedItem(
      int price, void Function() grantItem, String item) async {
    if (meteors < price) return false;
    meteors -= price;
    _recordWeeklyMeteorSpend(price);
    unawaited(AnalyticsService.instance.logSpend(item, price, meteors));
    grantItem();
    notifyListeners();
    await save();
    return true;
  }

  // ---------------------------------------------------------------------
  // Kozmik Oda: arkaplan temaları (Dükkan'dan satın alma + etkinleştirme)
  // ---------------------------------------------------------------------
  bool ownsTheme(String themeId) =>
      themeId == 'default' || ownedThemes.contains(themeId);

  /// Artık tema başına farklı fiyat var (bkz. EconomyConfig
  /// cosmicThemePriceTier1..4), o yüzden tek bir sabit yerine ilgili
  /// temanın kendi fiyatı parametre olarak veriliyor (bkz.
  /// ThemeShopScreen, CosmicTheme.price).
  bool canAffordThemePrice(int price) => meteors >= price;

  /// Dükkandan bir temayı meteorla satın alır. Zaten sahipse veya
  /// meteor yetmiyorsa false döner, hiçbir şeyi değiştirmez. [price]
  /// çağıran taraftan (CosmicTheme.price) geliyor çünkü artık her
  /// temanın kendi fiyatı var.
  Future<bool> purchaseTheme(String themeId, int price) async {
    if (ownsTheme(themeId)) return false;
    if (meteors < price) return false;
    meteors -= price;
    _recordWeeklyMeteorSpend(price);
    unawaited(AnalyticsService.instance.logSpend('theme_$themeId', price, meteors));
    ownedThemes.add(themeId);
    notifyListeners();
    await save();
    return true;
  }

  /// Kozmik Oda > Malzemeler'de sahip olunan bir temayı aktif (ana
  /// ekranda gösterilen) tema yapar. Sahip olunmayan bir tema asla
  /// etkinleştirilemez.
  Future<void> setRandomThemePerGame(bool value) async {
    if (randomThemePerGame == value) return;
    randomThemePerGame = value;
    notifyListeners();
    await save();
  }

  Future<void> setActiveTheme(String themeId) async {
    if (!ownsTheme(themeId)) return;
    if (activeTheme == themeId) return;
    activeTheme = themeId;
    notifyListeners();
    await save();
  }
}
