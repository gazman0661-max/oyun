import 'dart:async';

import 'package:flutter/services.dart';

import '../models/game_progress.dart';

/// Dusuk seviyeli titresim motoru (Flutter'in hazir HapticFeedback'ini
/// kullanir: ekstra paket ya da izin GEREKMEZ). Oyun kodu bunu dogrudan
/// cagirmaz - "hangi anda ne titresecek" kararlari `game_fx.dart` icinde.
///
/// Siddet kademeleri: tick < light < medium < heavy.
/// Not: cihaza gore farklar kucuk olabilir (bazi telefonlarda light ile
/// medium neredeyse ayni hissedilir) - bu yuzden onemli anlarda tek
/// darbe yerine KISA DESEN (arka arkaya birkac darbe) kullaniyoruz.
class HapticService {
  HapticService._();
  static final HapticService instance = HapticService._();

  static const int tick = 0;
  static const int light = 1;
  static const int medium = 2;
  static const int heavy = 3;

  final Stopwatch _clock = Stopwatch()..start();
  int _lastMs = -100000;

  bool get _enabled => GameProgress.instance.hapticsEnabled;

  void _fire(int strength) {
    switch (strength) {
      case tick:
        unawaited(HapticFeedback.selectionClick());
        break;
      case light:
        unawaited(HapticFeedback.lightImpact());
        break;
      case medium:
        unawaited(HapticFeedback.mediumImpact());
        break;
      default:
        unawaited(HapticFeedback.heavyImpact());
    }
  }

  /// Tek darbe. [minGapMs]: bir onceki (HERHANGI bir) titresimden bu
  /// kadar ms gecmeden calismaz - carpisma/atis gibi sik olaylarin
  /// sürekli "vızıltı"ya donusmesini engeller.
  void pulse(int strength, {int minGapMs = 0}) {
    if (!_enabled) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastMs < minGapMs) return;
    _lastMs = now;
    _fire(strength);
  }

  /// Zamanlanmis desen: her adim [gecikmeMs, siddet]. Ornek:
  /// `[[0, heavy], [120, medium]]` = hemen agir darbe, 120 ms sonra orta darbe.
  void pattern(List<List<int>> steps) {
    if (!_enabled) return;
    _lastMs = _clock.elapsedMilliseconds;
    for (final step in steps) {
      final delay = step[0];
      final strength = step[1];
      if (delay <= 0) {
        _fire(strength);
      } else {
        Timer(Duration(milliseconds: delay), () {
          // Desen ortasinda kullanici titresimi kapattiysa devam etme.
          if (_enabled) _fire(strength);
        });
      }
    }
  }
}
