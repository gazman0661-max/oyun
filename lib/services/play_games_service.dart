import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Google Play Games girisini, "Saved Games" (Snapshot) bulut kaydini ve
/// skor tablosunu (leaderboard) yoneten ince bir sarmalayici.
///
/// Bu servis, Android tarafinda yazilan kucuk bir native (Kotlin) koprusu
/// uzerinden calisir (bkz. android/.../MainActivity.kt), cunku Saved
/// Games API'si (SnapshotsClient) su an icin hicbir hafif Flutter
/// paketi tarafindan guvenilir sekilde saglanmiyor; doğrudan Google Play
/// Games Services v2 SDK'siyla native olarak konusmak gerekiyor.
///
/// ÖNEMLİ — bunun gercekten calismasi icin yapman gereken kurulum
/// adimlari icin projedeki README_PLAY_GAMES.md dosyasina bak (App ID,
/// gercek applicationId, SHA-1 parmak izi, ve skor tablosu ID'si).
class PlayGamesService {
  PlayGamesService._();
  static final PlayGamesService instance = PlayGamesService._();

  static const _channel = MethodChannel('space_sort/play_games');

  bool _signedIn = false;
  bool get isSignedIn => _signedIn;

  /// Uygulama acilirken, kullaniciya hicbir sey gostermeden sessizce
  /// giris denemesi yapar (daha once bu cihazda/hesapla giris yapildiysa
  /// basarili olur). Basarisiz olursa sessizce yutar.
  Future<void> signInSilently() async {
    try {
      final ok = await _channel.invokeMethod<bool>('signInSilently');
      _signedIn = ok ?? false;
    } catch (e) {
      _signedIn = false;
      debugPrint('Play Games sessiz giris basarisiz: $e');
    }
  }

  /// Profildeki "Play Games'e Bağlan" butonundan cagrilir; gerekirse
  /// Google'in kendi giris ekranini gosterir.
  Future<bool> signIn() async {
    try {
      final ok = await _channel.invokeMethod<bool>('signIn');
      _signedIn = ok ?? false;
      return _signedIn;
    } catch (e) {
      _signedIn = false;
      debugPrint('Play Games giris basarisiz: $e');
      return false;
    }
  }

  /// Verilen JSON metnini (oyuncunun tum ilerlemesi) Play Games "Saved
  /// Games" bulut kaydina yazar. Giris yapilmamissa hicbir sey yapmaz.
  Future<bool> saveProgress(String json) async {
    if (!_signedIn) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('saveProgress', {'data': json});
      return ok ?? false;
    } catch (e) {
      debugPrint('Bulut kaydi yazilamadi: $e');
      return false;
    }
  }

  /// Buluttaki kayitli oyunu (varsa) JSON metni olarak okur; hic kayit
  /// yoksa veya giris yapilmamissa null doner.
  Future<String?> loadProgress() async {
    if (!_signedIn) return null;
    try {
      return await _channel.invokeMethod<String>('loadProgress');
    } catch (e) {
      debugPrint('Bulut kaydi okunamadi: $e');
      return null;
    }
  }

  /// Kumulatif toplam skoru (PlayerProgress.totalScore) skor tablosuna
  /// gonderir. Play Games SDK'si bunu GUNLUK + HAFTALIK + TUM-ZAMANLAR
  /// varyantlarinin ucune de otomatik isler (ayri ayri gondermeye gerek
  /// yok). Giris yapilmamissa sessizce hicbir sey yapmaz.
  Future<void> submitScore(int totalScore) async {
    if (!_signedIn) return;
    try {
      await _channel.invokeMethod<bool>('submitScore', {'score': totalScore});
    } catch (e) {
      debugPrint('Skor gonderilemedi: $e');
    }
  }

  /// Google'in kendi skor tablosu ekranini (Gunluk / Haftalik / Tum-
  /// zamanlar sekmeleriyle) oyunun uzerine acar. Giris yapilmamissa
  /// once sessiz-olmayan girisi dener.
  Future<void> showLeaderboard() async {
    if (!_signedIn) {
      final ok = await signIn();
      if (!ok) return;
    }
    try {
      await _channel.invokeMethod<bool>('showLeaderboard');
    } catch (e) {
      debugPrint('Skor tablosu acilamadi: $e');
    }
  }

  /// Verilen Play Console basarim ID'sini kilidini acar (idempotent —
  /// zaten acilmissa Google tarafinda hicbir sey degismez, tekrar tekrar
  /// cagirmak guvenlidir). Giris yapilmamissa SESSIZCE hicbir sey yapmaz
  /// (kullaniciya "giris yap" diye zorlamiyoruz, basarim sadece bagliysa
  /// bir bonus).
  Future<void> unlockAchievement(String achievementId) async {
    if (!_signedIn) return;
    try {
      await _channel.invokeMethod<bool>(
        'unlockAchievement',
        {'achievementId': achievementId},
      );
    } catch (e) {
      debugPrint('Basarim acilamadi ($achievementId): $e');
    }
  }

  /// Artimli (incremental) basarim ilerlemesini bildirir (orn. "50 bolum
  /// bitir" gibi Play Console'da "kademeli" olarak tanimlanmis
  /// basarimlar icin). [steps], bu cagriyla eklenecek adim sayisidir
  /// (toplam degil — Google tarafinda kumulatif olarak tutulur).
  Future<void> incrementAchievement(String achievementId, int steps) async {
    if (!_signedIn) return;
    try {
      await _channel.invokeMethod<bool>(
        'incrementAchievement',
        {'achievementId': achievementId, 'steps': steps},
      );
    } catch (e) {
      debugPrint('Basarim ilerlemesi gonderilemedi ($achievementId): $e');
    }
  }
}
