import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'play_games_service.dart';
import 'player_progress.dart';

/// PlayerProgress'in yerel (cihaz-ici) kaydiyla, Play Games "Saved
/// Games" bulut kaydini senkronize eder.
///
/// Kural basit tutuldu: iki taraftan hangisi daha ileri durumdaysa
/// (totalScore daha yuksekse) o taraf "kazanir" ve digerine yazilir.
/// Boylece:
///  - Yeni bir cihazda giris yapinca, buluttaki daha ileri kayit
///    otomatik olarak indirilip bu cihaza uygulanir.
///  - Bu cihazdaki ilerleme bulutta olandan daha ileriyse, bulut bu
///    cihazdakiyle guncellenir (hicbir zaman veri kaybi olmaz).
class CloudProgressSync {
  CloudProgressSync._();
  static final CloudProgressSync instance = CloudProgressSync._();

  bool _busy = false;

  /// Play Games'e giris basarili olur olmaz (sessiz girişte veya
  /// profilden manuel baglanildiginda) cagrilir.
  Future<void> syncAfterSignIn() async {
    if (_busy || !PlayGamesService.instance.isSignedIn) return;
    _busy = true;
    try {
      final cloudJson = await PlayGamesService.instance.loadProgress();
      final progress = PlayerProgress.instance;

      if (cloudJson == null || cloudJson.isEmpty) {
        // Buluta hic kayit yok — bu ilk baglanma. Yerel ilerlemeyi
        // (varsa) buluta yukle.
        await _pushLocal();
        return;
      }

      Map<String, dynamic> cloud;
      try {
        cloud = jsonDecode(cloudJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Bulut kaydi okunamadi/bozuk, dokunulmadi: $e');
        return;
      }

      final cloudScore = (cloud['totalScore'] as num?)?.toInt() ?? 0;
      if (cloudScore > progress.totalScore) {
        // Bulut daha ileride (ör. baska bir cihazdan geliniyor):
        // yerel ilerlemeyi bulutla degistir.
        await progress.restoreFromJson(cloud);
      } else if (cloudScore < progress.totalScore) {
        // Bu cihaz daha ileride: buluta yaz.
        await _pushLocal();
      }
      // Esitse zaten senkron, hicbir sey yapmaya gerek yok.
    } finally {
      _busy = false;
    }
  }

  /// PlayerProgress.save() her cagrildiginda tetiklenir. Giris
  /// yapilmamissa sessizce hicbir sey yapmaz.
  Future<void> pushAfterLocalSave() async {
    if (!PlayGamesService.instance.isSignedIn) return;
    await _pushLocal();
  }

  Future<void> _pushLocal() async {
    final json = PlayerProgress.instance.exportJson();
    await PlayGamesService.instance.saveProgress(json);
  }
}
