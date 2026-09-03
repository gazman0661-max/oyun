import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/achievement_ids.dart';
import '../game/economy_config.dart';
import 'cloud_progress_sync.dart';
import 'network_time_service.dart';
import 'notification_service.dart';
import 'play_games_service.dart';
import 'sound_service.dart';

/// Tek bir bolumun en iyi sonucu.
class StageStat {
  final int stars;
  final int bestMoves;
  final int score;
  const StageStat({
    required this.stars,
    required this.bestMoves,
    required this.score,
  });

  Map<String, dynamic> toJson() =>
      {'stars': stars, 'bestMoves': bestMoves, 'score': score};

  factory StageStat.fromJson(Map<String, dynamic> j) => StageStat(
        stars: j['stars'] ?? 0,
        bestMoves: j['bestMoves'] ?? 0,
        score: j['score'] ?? 0,
      );
}

/// Gunluk gorevin son sonucu (paylasim ekrani + 2x XP butonu icin).
class DailyResult {
  final int dailyNum;
  final int moves;
  final int optimal;
  final int stars;
  final int timeSeconds;
  final int xp;
  bool doubled;
  DailyResult({
    required this.dailyNum,
    required this.moves,
    required this.optimal,
    required this.stars,
    required this.timeSeconds,
    required this.xp,
    this.doubled = false,
  });

  Map<String, dynamic> toJson() => {
        'dailyNum': dailyNum,
        'moves': moves,
        'optimal': optimal,
        'stars': stars,
        'timeSeconds': timeSeconds,
        'xp': xp,
        'doubled': doubled,
      };

  factory DailyResult.fromJson(Map<String, dynamic> j) => DailyResult(
        dailyNum: j['dailyNum'] ?? 1,
        moves: j['moves'] ?? 0,
        optimal: j['optimal'] ?? 1,
        stars: j['stars'] ?? 1,
        timeSeconds: j['timeSeconds'] ?? 0,
        xp: j['xp'] ?? 0,
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
  orbitDockSlot,
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
  int totalStars = 0;
  int totalScore = 0;

  // Orbit Jam (yorunge sikismasi) modunun bolum ilerlemesi — kilit ve
  // yildiz takibi burada tutulur.
  int orbitUnlockedStage = 1;
  final Map<int, StageStat> orbitStageStats = {};

  int dailyStreak = 0;
  String dailyLastCompletedDate = '';
  DailyResult? dailyLastResult;

  // Hamleyi Geri Al (Undo) — Orbit genelinde, bolum bazli DEGIL GUNLUK
  // (bkz. EconomyConfig.undoFreeDailyCount/undoMeteorPrice). Gun degisince
  // sayac otomatik sifirlanir (asagidaki undoFreeRemainingToday getter'i).
  int undoUsedToday = 0;
  String undoLastUsedDate = '';

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
  // dönüşümü ve ödülü var. SADECE Orbit modunda kazanılan yıldızları
  // sayar (bkz. recordOrbitStageResult -> _addConstellationStars).
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

  /// "Gunes Sistemi Koleksiyonu": bir bolum basariyla kazanildiginda
  /// kullanilan gezegen renk index'leri (0..9), ilk kesfedildiginde
  /// buraya eklenir ve kalici olarak saklanir.
  final Set<int> discoveredPlanets = <int>{};

  // Kozmik Ikmal bankasi: reklamla kazanilan, sonra reklamsiz
  // harcanabilen haklar. Yorunge Vardiyasi icin: reklamsiz kullanilabilen,
  // bir sonraki sikismada rihtima +1 yuva eklemek uzere biriktirilen hak.
  int bankedOrbitDockSlots = 0;
  int lastResupplyTime = 0;
  int resupplyAdsWatched = 0;

  int dailyResetsUsed = 0;
  String dailyResetsDate = '';

  static const int resupplyCooldownMs = 2 * 60 * 60 * 1000;
  static const int resupplyAdsRequired = 3;
  static const int dailyResetsFree = 3;
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
        'totalStars': totalStars,
        'totalScore': totalScore,
        'orbitUnlockedStage': orbitUnlockedStage,
        'orbitStageStats':
            orbitStageStats.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'dailyStreak': dailyStreak,
        'dailyLastCompletedDate': dailyLastCompletedDate,
        'dailyLastResult': dailyLastResult?.toJson(),
        'undoUsedToday': undoUsedToday,
        'undoLastUsedDate': undoLastUsedDate,
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
        'bankedOrbitDockSlots': bankedOrbitDockSlots,
        'lastResupplyTime': lastResupplyTime,
        'resupplyAdsWatched': resupplyAdsWatched,
        'dailyResetsUsed': dailyResetsUsed,
        'dailyResetsDate': dailyResetsDate,
      };

  void _applyJson(Map<String, dynamic> j) {
    xp = j['xp'] ?? 0;
    totalStars = j['totalStars'] ?? 0;
    totalScore = j['totalScore'] ?? 0;
    orbitUnlockedStage = j['orbitUnlockedStage'] ?? 1;
    orbitStageStats.clear();
    final orbitStats = (j['orbitStageStats'] as Map?) ?? {};
    orbitStats.forEach((k, v) {
      orbitStageStats[int.parse(k)] =
          StageStat.fromJson(Map<String, dynamic>.from(v));
    });
    dailyStreak = j['dailyStreak'] ?? 0;
    dailyLastCompletedDate = j['dailyLastCompletedDate'] ?? '';
    dailyLastResult = j['dailyLastResult'] != null
        ? DailyResult.fromJson(Map<String, dynamic>.from(j['dailyLastResult']))
        : null;
    undoUsedToday = j['undoUsedToday'] ?? 0;
    undoLastUsedDate = j['undoLastUsedDate'] ?? '';
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
    bankedOrbitDockSlots = j['bankedOrbitDockSlots'] ?? 0;
    lastResupplyTime = j['lastResupplyTime'] ?? 0;
    resupplyAdsWatched = j['resupplyAdsWatched'] ?? 0;
    dailyResetsUsed = j['dailyResetsUsed'] ?? 0;
    dailyResetsDate = j['dailyResetsDate'] ?? '';
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
  LevelInfo levelInfo() {
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

  Future<void> addXp(int amount) async {
    final levelBefore = levelInfo().level;
    xp += amount;
    if (levelInfo().level > levelBefore) SoundService.instance.levelUp();
    notifyListeners();
    await save();
  }

  /// "2x XP" reklam ödülü: XP'nin yanında sabit meteor bonusu da ekler.
  /// (bkz. EconomyConfig.winDoubleXpMeteorBonus, orbit_game_screen.dart)
  Future<void> addXpAndMeteors(int xpAmount, int meteorAmount) async {
    final levelBefore = levelInfo().level;
    xp += xpAmount;
    meteors += meteorAmount;
    if (levelInfo().level > levelBefore) SoundService.instance.levelUp();
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
  /// OrbitController.cometEvent), böylece o pencerede herkese aynı tahta
  /// gelir.
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

  /// Orbit modunda bir bölüm kazanıldığında (bkz. recordOrbitStageResult)
  /// çağrılır; [starDelta] o denemede YENİ kazanılan yıldız sayısıdır
  /// (0-3, zaten sahip olunan yıldızlar tekrar sayılmaz).
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
    final levelBefore = levelInfo().level;
    xp += EconomyConfig.cometXpReward;
    if (levelInfo().level > levelBefore) SoundService.instance.levelUp();
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

  /// Bir bölüm (Orbit) kazanıldığında çağrılır. [usedAssist] o denemede
  /// rıhtım-kurtarması kullanıldıysa true olmalı — "cleanStages" görevi
  /// SADECE yardımsız bitirilen bölümleri sayar. [stars] 3 ise "perfectStars" görevine de sayılır.
  /// Haftalık VE aylık görev sayaçlarını BİRLİKTE günceller (birbirinden
  /// bağımsız periyotlar, ama tek bölüm sonucu ikisine de sayılır).
  void _recordWeeklyStageProgress({required int stars, bool usedAssist = false}) {
    _ensureCurrentWeek();
    if (!weeklyRewardClaimed) {
      weeklyStagesCompleted += 1;
      if (!usedAssist) weeklyCleanStages += 1;
      if (stars >= 3) weeklyPerfectStages += 1;
      weeklyPlayDates.add(todayStr());
    }
    _ensureCurrentMonth();
    if (!monthlyRewardClaimed) {
      monthlyStagesCompleted += 1;
      if (!usedAssist) monthlyCleanStages += 1;
      if (stars >= 3) monthlyPerfectStages += 1;
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
    weeklyRewardClaimed = true;
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
    monthlyRewardClaimed = true;
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
  // Bolum sonucu kaydi
  // ---------------------------------------------------------------------
  /// Orbit Jam'de bir bolum kazanildiginda cagrilir; XP/yildiz/skor
  /// gunceller, orbitUnlockedStage/orbitStageStats'a yazar. [moves]
  /// burada "donus sayisi" (rotations) anlamina gelir.
  Future<(int, bool)> recordOrbitStageResult({
    required int stage,
    required int stars,
    required int moves,
    required int optimalMoves,
    bool usedAssist = false,
  }) async {
    final score = max(50, 500 - (moves - optimalMoves) * 10);
    final prev = orbitStageStats[stage];
    final isNew = prev == null;
    final starDelta = isNew ? stars : max(0, stars - prev.stars);
    final scoreDelta = isNew ? score : max(0, score - prev.score);

    orbitStageStats[stage] = StageStat(
      stars: max(stars, prev?.stars ?? 0),
      bestMoves: prev == null ? moves : min(moves, prev.bestMoves),
      score: max(score, prev?.score ?? 0),
    );
    totalStars += starDelta;
    totalScore += scoreDelta;
    if (stage + 1 > orbitUnlockedStage) {
      orbitUnlockedStage = stage + 1;
      if (orbitUnlockedStage >= AchievementIds.orbit50Threshold) {
        unawaited(
            PlayGamesService.instance.unlockAchievement(AchievementIds.orbit50));
      }
    }
    // DUZELTME (ekonomi dengeleme): eskiden HER bolumde garanti meteor
    // veriliyordu; artik EconomyConfig.meteorPerLevelCompleteChance
    // olasilikla veriliyor (organik meteor arzini dusurup IAP/temalar
    // icin gercek bir bosluk birakmak amaciyla).
    if (_rng.nextDouble() < EconomyConfig.meteorPerLevelCompleteChance) {
      meteors += EconomyConfig.meteorPerLevelComplete;
    }
    _recordWeeklyStageProgress(stars: stars, usedAssist: usedAssist);
    _addConstellationStars(starDelta);

    final levelBefore = levelInfo().level;
    final gainedXp = 15 + stars * 10;
    xp += gainedXp;
    final levelAfter = levelInfo().level;
    if (levelAfter > levelBefore) SoundService.instance.levelUp();

    notifyListeners();
    await save();
    unawaited(PlayGamesService.instance.submitScore(totalScore));
    unawaited(refreshPeriodicEventNotifications());
    return (gainedXp, levelAfter > levelBefore);
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

    notifyListeners();
    await save();

    return WeeklyRewardClaimResult(
      baseMeteor: base,
      bonusMeteor: bonus,
      isSundayBonus: bonusEligible,
    );
  }


  /// Bugun icin, gunun ilk `EconomyConfig.undoFreeDailyCount` hakki hala
  /// kullanilmamissa kalan ucretsiz geri-al sayisi (gun degisince otomatik
  /// olarak tekrar tam dolar - ayri bir "reset" cagrisi gerekmez, sadece
  /// tarih karsilastirmasi yeterli).
  int get undoFreeRemainingToday {
    final today = todayStr();
    final usedToday = undoLastUsedDate == today ? undoUsedToday : 0;
    return max(0, EconomyConfig.undoFreeDailyCount - usedToday);
  }

  /// Bir "hamleyi geri al" kullanimini kaydeder: once ucretsiz hakki
  /// dener, yoksa (ve [allowMeteorSpend] ise) EconomyConfig.undoMeteorPrice
  /// kadar meteor duser. Basarisizsa (ne ucretsiz hak ne yeterli meteor)
  /// false doner ve HICBIR SEY degismez - cagiran taraf gercek oyun
  /// tahtasi geri almasini SADECE true donerse uygulamali.
  Future<bool> useUndo({bool allowMeteorSpend = true}) async {
    final today = todayStr();
    if (undoLastUsedDate != today) {
      undoUsedToday = 0;
      undoLastUsedDate = today;
    }
    final freeLeft = EconomyConfig.undoFreeDailyCount - undoUsedToday;
    if (freeLeft > 0) {
      undoUsedToday += 1;
      notifyListeners();
      await save();
      return true;
    }
    if (allowMeteorSpend && meteors >= EconomyConfig.undoMeteorPrice) {
      meteors -= EconomyConfig.undoMeteorPrice;
      undoUsedToday += 1;
      notifyListeners();
      await save();
      return true;
    }
    return false;
  }

  Future<void> recordDailyResult({
    required int moves,
    required int optimal,
    required int timeSeconds,
  }) async {
    final today = todayStr();
    if (dailyLastCompletedDate == yesterdayStr()) {
      dailyStreak += 1;
    } else if (dailyLastCompletedDate != today) {
      dailyStreak = 1;
    }
    dailyLastCompletedDate = today;
    meteors += EconomyConfig.meteorDailyStreakBonus;
    if (dailyStreak >= AchievementIds.weekStreakThreshold) {
      unawaited(
          PlayGamesService.instance.unlockAchievement(AchievementIds.weekStreak));
    }
    final stars =
        moves <= optimal ? 3 : (moves <= (optimal * 1.5).ceil() ? 2 : 1);
    final gainedXp = 30 + stars * 10;
    final levelBeforeDaily = levelInfo().level;
    xp += gainedXp;
    if (levelInfo().level > levelBeforeDaily) SoundService.instance.levelUp();
    dailyLastResult = DailyResult(
      dailyNum: dailyNumber(),
      moves: moves,
      optimal: optimal,
      stars: stars,
      timeSeconds: timeSeconds,
      xp: gainedXp,
    );
    notifyListeners();
    await save();
    // Bugunku gunluk bulmaca tamamlandi: hatirlatma bildirimini hemen
    // YARINA ertele, boylece bugun icin gereksiz bir hatirlatma kalmaz.
    unawaited(NotificationService.instance
        .refreshDailyStreakReminder(playedToday: true));
  }

  // ---------------------------------------------------------------------
  // Gunes Sistemi Koleksiyonu: bir bolum kazanildiginda, o bolumde
  // kullanilan gezegen renklerinden (0..colorCount-1) daha once hic
  // kesfedilmemis olanlari kalici listeye ekler. Yeni kesfedilenlerin
  // index listesini dondurur (UI, bunun uzerine bir "yeni gezegen
  // kesfedildi" animasyonu/diyalogu gosterebilir; bos liste -> yeni yok).
  Future<List<int>> markPlanetsDiscovered(int colorCount) async {
    final fresh = <int>[];
    for (var i = 0; i < colorCount && i < 10; i++) {
      if (discoveredPlanets.add(i)) fresh.add(i);
    }
    if (fresh.isNotEmpty) {
      if (discoveredPlanets.length >= AchievementIds.planetExplorerThreshold) {
        unawaited(PlayGamesService.instance
            .unlockAchievement(AchievementIds.planetExplorer));
      }
      notifyListeners();
      await save();
    }
    return fresh;
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
  ///   %50 -> XP (rihtim hakki artik SADECE meteor magazasindan
  ///   alinabiliyor, RNG'den cikarildi).
  /// 3. reklamdan sonra 2 saatlik bekleme baslatir.
  Future<ResupplyReward> grantResupplyReward(Random rng) async {
    final roll = rng.nextDouble();
    ResupplyReward reward;
    double cursor = 0;

    // Her izlemede, ana ödülden BAĞIMSIZ olarak 1-5 arası rastgele bir
    // ek meteor bonusu verilir (bkz. EconomyConfig.resupplyBonusMeteorMin/
    // Max) — "1 meteor + sinyal", "5 meteor + 2 meteor" gibi. Ana ödül
    // havuzu/olasılıkları DEĞİŞMEDİ, sadece üstüne bu ekleniyor.
    final bonusMeteors = EconomyConfig.resupplyBonusMeteorMin +
        rng.nextInt(EconomyConfig.resupplyBonusMeteorMax -
                EconomyConfig.resupplyBonusMeteorMin +
                1);
    meteors += bonusMeteors;

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
      final levelBeforeResupply = levelInfo().level;
      xp += EconomyConfig.xpRewardAmount;
      if (levelInfo().level > levelBeforeResupply) {
        SoundService.instance.levelUp();
      }
      reward = ResupplyReward(
          ResupplyRewardKind.xp, EconomyConfig.xpRewardAmount,
          bonusMeteors: bonusMeteors);
    }
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
  // Gunluk ucretsiz "yeniden baslat" haklari (hesap bazinda, bolum
  // bazinda degil).
  // ---------------------------------------------------------------------
  int getResetsLeftToday() {
    if (dailyResetsDate != todayStr()) {
      dailyResetsDate = todayStr();
      dailyResetsUsed = 0;
    }
    return max(0, dailyResetsFree - dailyResetsUsed);
  }

  Future<void> useFreeReset() async {
    dailyResetsUsed += 1;
    notifyListeners();
    await save();
  }

  Future<void> spendBankedOrbitDockSlot() async {
    bankedOrbitDockSlots = max(0, bankedOrbitDockSlots - 1);
    notifyListeners();
    await save();
  }

  // ---------------------------------------------------------------------
  // Meteor Mağazası: rıhtım hakkı artık SADECE buradan (meteor karşılığı)
  // alınabiliyor. Fiyat tek kaynak olan EconomyConfig'ten okunur.
  // ---------------------------------------------------------------------
  /// Orbit rihtim hakki artik SADECE sinirsiz odullu reklamla degil,
  /// istenirse onceden meteorla da stoklanabiliyor (bankedOrbitDockSlots
  /// havuzuna ekler, ayni Kozmik Ikmal'den kazanilanla ayni havuz).
  bool get canAffordDockSlot => meteors >= EconomyConfig.dockSlotShopPrice;

  Future<bool> buyDockSlotWithMeteors() => _buyBankedItem(
      EconomyConfig.dockSlotShopPrice, () => bankedOrbitDockSlots += 1);

  Future<bool> _buyBankedItem(int price, void Function() grantItem) async {
    if (meteors < price) return false;
    meteors -= price;
    _recordWeeklyMeteorSpend(price);
    grantItem();
    notifyListeners();
    await save();
    return true;
  }

  /// Orbit sıkışmasında 1. hak (reklam) kullanıldıktan sonraki her ek
  /// rıhtım genişletme hakkı için meteor harcar. [paidAttemptIndex] 0
  /// tabanlı (0 = 2. hak, 1 = 3. hak, ...) — fiyat kademeli artar.
  Future<bool> spendMeteorsForOrbitDock(int paidAttemptIndex) async {
    final price = EconomyConfig.orbitDockPriceFor(paidAttemptIndex);
    if (meteors < price) return false;
    meteors -= price;
    _recordWeeklyMeteorSpend(price);
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
    ownedThemes.add(themeId);
    notifyListeners();
    await save();
    return true;
  }

  /// Kozmik Oda > Malzemeler'de sahip olunan bir temayı aktif (ana
  /// ekranda gösterilen) tema yapar. Sahip olunmayan bir tema asla
  /// etkinleştirilemez.
  Future<void> setActiveTheme(String themeId) async {
    if (!ownsTheme(themeId)) return;
    if (activeTheme == themeId) return;
    activeTheme = themeId;
    notifyListeners();
    await save();
  }
}
