import 'dart:ui' as ui;

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
/// Ozel skor tablosunun zaman dilimi (Play Games LeaderboardVariant
/// TIME_SPAN_* degerleriyle ayni sayilar).
enum LeaderboardSpan {
  daily(0),
  weekly(1),
  allTime(2);

  final int value;
  const LeaderboardSpan(this.value);
}

/// Skor tablosundaki tek bir satir.
class LeaderboardEntry {
  final int rank;
  final int score;
  final String name;

  /// Skor etiketinden (tag) okunan rutbe seviyesi; yoksa null.
  final int? level;
  const LeaderboardEntry({
    required this.rank,
    required this.score,
    required this.name,
    this.level,
  });

  factory LeaderboardEntry.fromMap(Map<dynamic, dynamic> m) {
    final tag = (m['tag'] as String?) ?? '';
    int? level;
    if (tag.length > 1 && tag.startsWith('l')) {
      level = int.tryParse(tag.substring(1));
    }
    return LeaderboardEntry(
      rank: (m['rank'] as num?)?.toInt() ?? 0,
      score: (m['score'] as num?)?.toInt() ?? 0,
      name: ((m['name'] as String?) ?? '').trim(),
      level: level,
    );
  }
}

class PlayGamesService {
  PlayGamesService._();
  static final PlayGamesService instance = PlayGamesService._();

  static const _channel = MethodChannel('space_sort/play_games');

  // ---- Ozel skor tablosu ("en iyi oyun skoru": gunluk/haftalik/tum zamanlar)
  // Play Console > Play Games Services > Skor Tablolari'nda iki tablo ac
  // (ikisi de "buyuk skor daha iyi", sayisal): 1) "Rekor Skor" (Dunya),
  // 2) "Rekor Skor - Turkiye". Olusan ID'leri (CgkI...) asagiya yapistir.
  // Bos birakilirsa uygulama eski Google skor ekranina duser.
  static const String bestBoardWorld = '';
  static const String bestBoardTr = '';

  static bool get leaderboardReady => bestBoardWorld.isNotEmpty;
  static bool get turkeyBoardReady => bestBoardTr.isNotEmpty;

  /// Cihaz bolgesi Turkiye ise skor Turkiye tablosuna da gonderilir.
  static bool get isTurkeyDevice =>
      ui.PlatformDispatcher.instance.locale.countryCode?.toUpperCase() ==
      'TR';

  String _boardId(bool turkey) => turkey ? bestBoardTr : bestBoardWorld;

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

  /// Bir oyunun skorunu "en iyi oyun skoru" tablolarina gonderir (Dunya,
  /// cihaz Turkiye ise Turkiye de). Tablo kendisi en yuksegi tutar; gunluk,
  /// haftalik ve tum zamanlar goruntuleri Google tarafindan uretilir.
  /// [rankLevel] oyuncunun seviyesidir; skor etiketine yazilir.
  Future<void> submitRunScore(int score, int rankLevel) async {
    if (!_signedIn || score <= 0 || !leaderboardReady) return;
    final tag = 'l$rankLevel';
    try {
      await _channel.invokeMethod<bool>('submitBoardScore',
          {'boardId': bestBoardWorld, 'score': score, 'tag': tag});
      if (turkeyBoardReady && isTurkeyDevice) {
        await _channel.invokeMethod<bool>('submitBoardScore',
            {'boardId': bestBoardTr, 'score': score, 'tag': tag});
      }
    } catch (e) {
      debugPrint('Oyun skoru gonderilemedi: $e');
    }
  }

  /// Herkese acik ilk 25 skor. Hata olursa null, bos tablo icin bos liste.
  Future<List<LeaderboardEntry>?> loadLeaderboard({
    required bool turkey,
    required LeaderboardSpan span,
  }) async {
    final id = _boardId(turkey);
    if (!_signedIn || id.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
          'loadLeaderboard', {'boardId': id, 'span': span.value});
      if (raw == null) return null;
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(LeaderboardEntry.fromMap)
          .toList();
    } catch (e) {
      debugPrint('Skor tablosu yuklenemedi: $e');
      return null;
    }
  }

  /// Oyuncunun kendi sirasi/skoru (bu donemde skoru yoksa null).
  Future<LeaderboardEntry?> loadMyLeaderboardEntry({
    required bool turkey,
    required LeaderboardSpan span,
  }) async {
    final id = _boardId(turkey);
    if (!_signedIn || id.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'loadMyLeaderboardScore', {'boardId': id, 'span': span.value});
      if (raw == null) return null;
      return LeaderboardEntry.fromMap(raw);
    } catch (e) {
      debugPrint('Kendi skorum yuklenemedi: $e');
      return null;
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
}
