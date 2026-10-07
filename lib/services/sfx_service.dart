import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/game_progress.dart';

/// Dusuk seviyeli ses motoru. Oyun kodu bunu DOGRUDAN cagirmaz -
/// hangi anda hangi ses/titresim calacagi `game_fx.dart` icinde.
///
/// Nasil calisiyor:
///  * assets/sfx/ altindaki kisa .wav dosyalari acilista onceden yuklenir
///    (ilk calmada gecikme olmasin diye).
///  * 8 adet AudioPlayer "havuzu" (lowLatency modu) sirayla kullanilir;
///    boylece ust uste binen sesler (zincirleme merge gibi) birbirini
///    kesmez.
///  * Ayni ses cok sik tetiklenirse (orn. carpisma) `minGapMs` ile
///    kisitlanir - kulak yorulmasin, cihaz kasmasin.
///  * Ses baska uygulamalarin muzigini DURDURMAZ (mixWithOthers).
///  * Ayarlardan ses kapatildiysa (GameProgress.soundEnabled) hicbir sey
///    calmaz.
class SfxService {
  SfxService._();
  static final SfxService instance = SfxService._();

  /// assets/sfx/ altindaki tum sesler (uzantisiz). pubspec.yaml'daki
  /// asset listesiyle AYNI olmali.
  static const List<String> names = [
    'throw',
    'hit_1',
    'hit_2',
    'hit_3',
    'hit_4',
    'wall',
    'merge_2',
    'merge_3',
    'merge_4',
    'merge_5',
    'merge_6',
    'merge_7',
    'merge_8',
    'merge_max',
    'new_tier',
    'coin',
    'reward',
    'denied',
    'tap',
    'chapter_complete',
    'game_over',
  ];

  // Her ses icin AYRI bir AudioPool: kaynak BIR KEZ yuklenir, calarken
  // tekrar setSource yapilmaz (eski havuzda her play() kaynagi yeniden
  // yukluyordu -> gecikme, "bazen calmama" ve donma anlarinda sesin
  // geriden gelmesi). Sik tetiklenen sesler 3, nadir olanlar 1 oyuncu.
  static const Set<String> _frequent = {
    'throw', 'hit_1', 'hit_2', 'hit_3', 'hit_4', 'wall', 'tap', 'coin',
    'merge_2', 'merge_3', 'merge_4', 'merge_5',
  };

  final Map<String, AudioPool> _pools = {};
  bool _ready = false;
  bool _initStarted = false;
  final Map<String, int> _lastPlayMs = {};
  final Stopwatch _clock = Stopwatch()..start();

  static String _path(String name) => 'sfx/$name.wav'; // AudioCache "assets/" onekini kendisi ekler

  /// main() icinde BEKLETMEDEN cagrilir. Yukleme bitene kadar gelen
  /// play() cagrilari sessizce yok sayilir.
  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      // Oyun sesleri baska uygulamalarin (Spotify vb.) muzigini kesmesin.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (e) {
      debugPrint('SfxService: audio context ayarlanamadi: $e');
    }
    for (final n in names) {
      try {
        _pools[n] = await AudioPool.createFromAsset(
          path: _path(n),
          maxPlayers: _frequent.contains(n) ? 3 : 1,
        );
      } catch (e) {
        debugPrint('SfxService: "$n" yuklenemedi: $e');
      }
    }
    _ready = _pools.isNotEmpty;
  }

  /// [name] sesini calar. [volume] 0..1. [minGapMs]: ayni [group]
  /// (verilmezse ses adi) icin iki calma arasi en az bu kadar ms olmali.
  void play(String name, {double volume = 1.0, int minGapMs = 0, String? group}) {
    if (!_ready) return;
    if (!GameProgress.instance.soundEnabled) return;

    final key = group ?? name;
    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayMs[key];
    if (last != null && now - last < minGapMs) return;
    _lastPlayMs[key] = now;

    final pool = _pools[name];
    if (pool == null) return;
    final v = volume.clamp(0.0, 1.0).toDouble();
    unawaited(
      pool.start(volume: v).then<void>((_) {}).catchError((Object e) {
        debugPrint('SfxService: "$name" calinamadi: $e');
      }),
    );
  }
}
