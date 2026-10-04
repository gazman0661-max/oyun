import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/time_service.dart';
import 'game_progress.dart';
import 'weekly_event.dart';

/// SEZON YOLU: aylik, 30 kademelik, bedava + premium yollu ilerleme.
///
///  * Sezon puani (SP) mevcut sistemlerden akar: siparis teslimi, bolum
///    bitirme, gorev odulu alma, cark cevirme, gunluk odul.
///  * Her ayin 1'inde sezon sifirlanir (TimeService: saat hilesine karsi).
///  * Premium yol GERCEK PARA ile acilir -> [kSeasonPremiumEnabled] false
///    iken premium yol hic gorunmez (IAP baglanana kadar guvenli).
///  * Kaydi kendi anahtariyla ('season_v1') tutar; GameProgress'e ek alan
///    gerektirmez, eski kayitlar etkilenmez.
const bool kSeasonPremiumEnabled = true;

class SeasonReward {
  final int coins;
  final int gems;
  final bool energy;
  final BoosterType? booster;
  final int boosterCount;
  const SeasonReward({
    this.coins = 0,
    this.gems = 0,
    this.energy = false,
    this.booster,
    this.boosterCount = 1,
  });
}

class SeasonService {
  SeasonService._();
  static final SeasonService instance = SeasonService._();

  // ── Denge sabitleri ──
  static const int tierCount = 30;
  static const int spPerTier = 50;
  static const int spOrder = 2;
  static const int spChapter = 8;
  static const int spMission = 15;
  static const int spWheel = 10;
  static const int spDaily = 10;
  static const String premiumProductId = 'season_pass_premium';

  static const String _key = 'season_v1';

  int _seasonId = 0; // yil*100+ay
  int points = 0;
  bool premium = false;
  final Set<int> _claimedFree = {};
  final Set<int> _claimedPremium = {};

  // ── Odul tablolari ──
  static SeasonReward freeReward(int t) {
    if (t % 10 == 0) return const SeasonReward(gems: 8, coins: 500);
    if (t % 5 == 0) return SeasonReward(booster: BoosterType.values[(t ~/ 5) % 3]);
    if (t % 7 == 0) return const SeasonReward(energy: true);
    if (t % 3 == 0) return const SeasonReward(gems: 2);
    return SeasonReward(coins: 100 + t * 10);
  }

  static SeasonReward premiumReward(int t) {
    if (t == tierCount) return const SeasonReward(gems: 60, coins: 3000);
    if (t % 10 == 0) return const SeasonReward(gems: 25, coins: 1000);
    if (t % 5 == 0) return SeasonReward(booster: BoosterType.values[(t ~/ 5) % 3], boosterCount: 3);
    if (t % 7 == 0) return const SeasonReward(energy: true, gems: 3);
    if (t % 3 == 0) return const SeasonReward(gems: 6);
    return SeasonReward(coins: 300 + t * 30);
  }

  // ── Durum ──
  static int _currentSeasonId() {
    final n = TimeService.instance.now();
    return n.year * 100 + n.month;
  }

  /// Sezonun bitmesine kalan sure.
  Duration get timeLeft {
    _rollIfNewSeason();
    final n = TimeService.instance.now();
    final next = DateTime(n.year, n.month + 1, 1);
    return next.difference(n);
  }

  void _rollIfNewSeason() {
    final id = _currentSeasonId();
    if (_seasonId != id) {
      _seasonId = id;
      points = 0;
      premium = false;
      _claimedFree.clear();
      _claimedPremium.clear();
      save();
    }
  }

  int get tier {
    _rollIfNewSeason();
    return (points ~/ spPerTier).clamp(0, tierCount);
  }

  /// Mevcut kademe icindeki ilerleme (0..spPerTier-1); son kademede tam.
  int get pointsInTier => tier >= tierCount ? spPerTier : points % spPerTier;

  bool isClaimed(int t, {required bool premiumTrack}) =>
      (premiumTrack ? _claimedPremium : _claimedFree).contains(t);

  bool canClaim(int t, {required bool premiumTrack}) {
    _rollIfNewSeason();
    if (t < 1 || t > tierCount || t > tier) return false;
    if (premiumTrack && !premium) return false;
    return !isClaimed(t, premiumTrack: premiumTrack);
  }

  /// Alinmayi bekleyen odul var mi? (ana menu kirmizi noktasi)
  bool get hasClaimable {
    _rollIfNewSeason();
    for (var t = 1; t <= tier; t++) {
      if (canClaim(t, premiumTrack: false)) return true;
      if (kSeasonPremiumEnabled && canClaim(t, premiumTrack: true)) return true;
    }
    return false;
  }

  int get claimableCount {
    var n = 0;
    for (var t = 1; t <= tier; t++) {
      if (canClaim(t, premiumTrack: false)) n++;
      if (kSeasonPremiumEnabled && canClaim(t, premiumTrack: true)) n++;
    }
    return n;
  }

  void addPoints(int amount) {
    if (amount <= 0) return;
    _rollIfNewSeason();
    final max = tierCount * spPerTier;
    points = (points + amount * WeeklyEvent.instance.spMultiplier).clamp(0, max).toInt();
    save();
  }

  /// Bir kademenin odulunu verir. Basariliysa odulu doner, degilse null.
  SeasonReward? claim(int t, {required bool premiumTrack}) {
    if (!canClaim(t, premiumTrack: premiumTrack)) return null;
    final r = premiumTrack ? premiumReward(t) : freeReward(t);
    (premiumTrack ? _claimedPremium : _claimedFree).add(t);
    GameProgress.instance.grantReward(
      coins: r.coins,
      gems: r.gems,
      energy: r.energy,
      booster: r.booster,
      boosterAmount: r.boosterCount,
    );
    save();
    return r;
  }

  /// Alinabilen tum odulleri tek seferde verir; alinan adet doner.
  int claimAll() {
    var n = 0;
    for (var t = 1; t <= tier; t++) {
      if (claim(t, premiumTrack: false) != null) n++;
      if (kSeasonPremiumEnabled && claim(t, premiumTrack: true) != null) n++;
    }
    return n;
  }

  /// Premium yolu acar (Play Billing teslimatinda BillingService cagirir).
  void unlockPremium() {
    _rollIfNewSeason();
    premium = true;
    save();
  }

  // ── Kalicilik ──
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _seasonId = j['season'] as int? ?? 0;
        points = j['points'] as int? ?? 0;
        premium = j['premium'] as bool? ?? false;
        _claimedFree
          ..clear()
          ..addAll((j['free'] as List? ?? const []).whereType<int>());
        _claimedPremium
          ..clear()
          ..addAll((j['prem'] as List? ?? const []).whereType<int>());
      }
    } catch (_) {
      // bozuk kayit: varsayilanla devam
    }
    _rollIfNewSeason();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'season': _seasonId,
          'points': points,
          'premium': premium,
          'free': _claimedFree.toList(),
          'prem': _claimedPremium.toList(),
        }),
      );
    } catch (_) {}
  }
}
