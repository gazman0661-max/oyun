import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/time_service.dart';
import 'game_progress.dart';

/// KARSILAMA: ilk acilista hos geldin hediyesi + uzun sure gelmeyen
/// oyuncuya "geri donus" odulu. Kendi anahtariyla ('engage_v1') saklanir.
class EngageReward {
  final int coins;
  final int gems;
  final bool energy;
  final BoosterType? booster;
  const EngageReward({this.coins = 0, this.gems = 0, this.energy = false, this.booster});
}

class EngageService {
  EngageService._();
  static final EngageService instance = EngageService._();

  static const String _key = 'engage_v1';
  static const int minAwayDays = 2;
  static const int maxRewardDays = 7;
  static const int coinsPerDay = 200;

  /// Hos geldin hediyesi (yalnizca yeni oyuncu).
  static const EngageReward welcomeReward =
      EngageReward(coins: 300, gems: 10, booster: BoosterType.joker);

  DateTime? _lastSeen;
  bool welcomeClaimed = false;
  int pendingAwayDays = 0;

  /// Yeni oyuncuya hos geldin hediyesi bekliyor mu?
  bool get welcomePending => !welcomeClaimed;

  static EngageReward comebackReward(int days) {
    final d = days.clamp(1, maxRewardDays).toInt();
    return EngageReward(
      coins: d * coinsPerDay,
      gems: d >= 5 ? 3 : 0,
      energy: true,
      booster: d >= maxRewardDays ? BoosterType.joker : null,
    );
  }

  DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Uygulama acilinca / arka plandan donunce cagrilir.
  void onAppOpen() {
    final now = TimeService.instance.now();
    final last = _lastSeen;
    if (last != null && pendingAwayDays == 0) {
      final days = _day(now).difference(_day(last)).inDays;
      if (days >= minAwayDays) pendingAwayDays = days;
    }
    _lastSeen = now;
    save();
  }

  /// Arka plana giderken cagrilir: "en son goruldu" simdi olsun.
  void touch() {
    _lastSeen = TimeService.instance.now();
    save();
  }

  /// Eski (zaten ilerlemis) oyuncuya hos geldin hediyesi gosterme.
  void skipWelcomeForExistingPlayer() {
    if (!welcomeClaimed && GameProgress.instance.maxUnlockedChapter > 1) {
      welcomeClaimed = true;
      save();
    }
  }

  void _give(EngageReward r) {
    GameProgress.instance.grantReward(
      coins: r.coins,
      gems: r.gems,
      energy: r.energy,
      booster: r.booster,
    );
  }

  void claimWelcome() {
    if (welcomeClaimed) return;
    welcomeClaimed = true;
    _give(welcomeReward);
    save();
  }

  void claimComeback() {
    if (pendingAwayDays <= 0) return;
    final r = comebackReward(pendingAwayDays);
    pendingAwayDays = 0;
    _give(r);
    save();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final ls = j['lastSeen'] as String?;
        _lastSeen = ls == null ? null : DateTime.tryParse(ls);
        welcomeClaimed = j['welcomeClaimed'] as bool? ?? false;
        pendingAwayDays = j['pendingAwayDays'] as int? ?? 0;
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'lastSeen': _lastSeen?.toIso8601String(),
          'welcomeClaimed': welcomeClaimed,
          'pendingAwayDays': pendingAwayDays,
        }),
      );
    } catch (_) {}
  }
}
