import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Titresim (haptic) geri bildirimi. Tercih kalici saklanir; profil
/// ekranindaki anahtardan kapatilabilir. Desteklemeyen platformlarda
/// (web onizleme vb.) sessizce hicbir sey yapmaz.
class HapticService extends ChangeNotifier {
  HapticService._();
  static final HapticService instance = HapticService._();

  static const _prefsKey = 'cs_haptics_enabled_v1';

  bool enabled = true;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefsKey) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    if (value) light();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }

  void _run(Future<void> Function() f) {
    if (!enabled) return;
    try {
      f().catchError((_) {});
    } catch (_) {}
  }

  /// Hafif: gezegen birakma, kucuk birlesme.
  void light() => _run(HapticFeedback.lightImpact);

  /// Orta: orta boy birlesme, guclendirici kullanimi.
  void medium() => _run(HapticFeedback.mediumImpact);

  /// Guclu: buyuk gezegen, yuksek combo, oyun sonu.
  void heavy() => _run(HapticFeedback.heavyImpact);

  /// Cok hafif "tik": nisan/secim.
  void tick() => _run(HapticFeedback.selectionClick);

  /// Desen yuklu titresim: her adim [gecikmeMs, siddet] (0 hafif, 1 orta, 2 guclu).
  /// Ornek: cift guclu = [[0, 2], [90, 2]].
  void pattern(List<List<int>> steps) {
    if (!enabled) return;
    for (final st in steps) {
      final ms = st[0];
      final kind = st[1];
      void fire() {
        switch (kind) {
          case 2:
            heavy();
          case 1:
            medium();
          default:
            light();
        }
      }

      if (ms <= 0) {
        fire();
      } else {
        Timer(Duration(milliseconds: ms), fire);
      }
    }
  }

  final Stopwatch _tensionClock = Stopwatch()..start();
  int _lastTensionMs = -1000;

  /// Yigin tehlike cizgisine yaklasinca: ~0.4 sn'den sik olmayan hafif "kalp atisi".
  void tension() {
    if (!enabled) return;
    final now = _tensionClock.elapsedMilliseconds;
    if (now - _lastTensionMs < 400) return;
    _lastTensionMs = now;
    light();
  }
}
