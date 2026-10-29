import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';
import 'player_progress.dart';

/// Adim adim ogreticinin kalici durumu.
///
/// Evreler (sirayla):
///   home1 -> karsilama, meteor rozeti, OYNA butonu
///   game  -> oyun ici etkilesimli ogretici (birak, birlestir, tehlike, guc)
///   home2 -> ana ekran turu (ikmal, gorevler, gunluk, kuyruklu yildiz...)
///   done  -> bitti
///
/// Oyuncu uygulamayi evre ortasinda kapatirsa kaldigi evreden devam eder.
/// Daha once oyun oynamis (eski) oyunculara ogretici zorla gosterilmez;
/// profilden "Ogreticiyi tekrar oyna" ile istenirse acilabilir.
enum TutorialPhase { home1, game, home2, done }

class TutorialService {
  TutorialService._();
  static final TutorialService instance = TutorialService._();

  static const _phaseKey = 'tut_phase_v11';
  static const _rewardKey = 'tut_reward_claimed_v11';

  /// Ana ekran turu, Gorevler ekranina girince mini tur gostersin diye.
  bool tasksTourPending = false;

  TutorialPhase _phase = TutorialPhase.done;
  bool _rewardClaimed = false;
  bool _loaded = false;

  TutorialPhase get phase => _phase;
  bool get isActive => _phase != TutorialPhase.done;
  bool get rewardClaimed => _rewardClaimed;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _rewardClaimed = prefs.getBool(_rewardKey) ?? false;
    final saved = prefs.getString(_phaseKey);
    if (saved == null) {
      // Ilk kez: yeni oyuncuysa ogretici baslar, eski oyuncuysa atlanir.
      final p = PlayerProgress.instance;
      final veteran = p.lifetimeDrops > 0 || p.mergeBestScore > 0;
      _phase = veteran ? TutorialPhase.done : TutorialPhase.home1;
      await prefs.setString(_phaseKey, _phase.name);
    } else {
      _phase = TutorialPhase.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => TutorialPhase.done,
      );
    }
    _loaded = true;
  }

  Future<void> setPhase(TutorialPhase p) async {
    _phase = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phaseKey, p.name);
    unawaited(AnalyticsService.instance.log('tutorial_phase', {'phase': p.name}));
    AnalyticsService.instance.setUserProp('tutorial_state', p.name);
  }

  /// Profilden "tekrar oyna". Odul ikinci kez verilmez.
  Future<void> restart() => setPhase(TutorialPhase.home1);

  Future<void> skip() async {
    await setPhase(TutorialPhase.done);
    AnalyticsService.instance.setUserProp('tutorial_state', 'skipped');
  }

  Future<void> markRewardClaimed() async {
    _rewardClaimed = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rewardKey, true);
  }
}
