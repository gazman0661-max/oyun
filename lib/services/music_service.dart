import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../models/game_progress.dart';

/// Arka plan muzigi: assets/music/loop.wav kesintisiz doner.
/// Ses ayari (GameProgress.soundEnabled) kapaliysa calmaz; ayar
/// degisince [sync] cagrilir. Uygulama arka plana gidince durur.
class MusicService {
  MusicService._();
  static final MusicService instance = MusicService._();

  static const double _volume = 0.22;

  AudioPlayer? _player;
  bool _started = false;
  bool _playing = false;
  bool _kicking = false;
  // Web'de tarayici, kullanici ekrana dokunmadan sesi calmaya izin
  // vermez (autoplay engeli). Ilk dokunusta muzigi zorla baslatiriz.
  bool _gestureDone = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final p = AudioPlayer();
    _player = p;
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_volume);
      await p.setSource(AssetSource('music/loop.wav'));
      await sync();
    } catch (e) {
      debugPrint('MusicService: baslatilamadi: $e');
    }
  }

  /// Ekrana HER dokunusta cagrilir (main.dart'taki Listener). Muzik henuz
  /// calmiyorsa (ozellikle web autoplay engeli yuzunden) baslatir.
  Future<void> kickstart() async {
    if (_kicking) return;
    if (!GameProgress.instance.musicEnabled) return;
    final p = _player;
    if (p == null) {
      await start();
      return;
    }
    final alreadyPlaying = p.state == PlayerState.playing;
    if (alreadyPlaying && (_gestureDone || !kIsWeb)) {
      _playing = true;
      return;
    }
    _kicking = true;
    try {
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource('music/loop.wav'), volume: _volume);
      _playing = true;
      _gestureDone = true;
    } catch (e) {
      debugPrint('MusicService: kickstart hatasi: $e');
    } finally {
      _kicking = false;
    }
  }

  /// Ses ayarina gore calar ya da durdurur.
  Future<void> sync() async {
    final p = _player;
    if (p == null) return;
    try {
      if (GameProgress.instance.musicEnabled) {
        if (!_playing) {
          await p.resume();
          _playing = true;
        }
      } else if (_playing) {
        _playing = false;
        await p.pause();
      }
    } catch (e) {
      debugPrint('MusicService: sync hatasi: $e');
    }
  }

  Future<void> onPaused() async {
    final p = _player;
    if (p == null || !_playing) return;
    _playing = false;
    try {
      await p.pause();
    } catch (_) {}
  }

  Future<void> onResumed() => sync();
}
