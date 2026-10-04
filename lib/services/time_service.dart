import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Oyunun "su an saat kac" sorusunun TEK kaynagi.
///
/// NEDEN: Enerji dolumu, reklam-izle kotasi, gunluk odul ve gorev
/// sifirlamalari eskiden cihaz saatine (DateTime.now()) bakiyordu.
/// Oyuncu telefonun saatini ileri alarak enerjiyi/kotayi/gunluk odulu
/// bedavaya doldurabiliyordu. Artik saat bir internet sunucusundan
/// (HTTP "Date" basligi) alinir.
///
/// NASIL CALISIR:
///  1. Acilista ve uygulama arka plandan donunce sunucu saati alinir
///     (gidis-donus gecikmesinin yarisi eklenerek).
///  2. Senkrondan sonra gecen sure, cihazin DUVAR saati yerine
///     Stopwatch (monotonik saat) ile olculur. Oyuncu saati elle
///     degistirse bile now() etkilenmez.
///  3. Internet yoksa (hic senkron olunamadiysa) cihaz saati kullanilir
///     ama en son gorulen sunucu saatinin GERISINE dusmesine izin
///     verilmez (saati geri alma hilesi calismaz).
///
/// SINIR (durust not): Internet tamamen yokken cihaz saatini ILERI almak
/// hala ise yarar - ta ki oyun bir sonraki sefer sunucuyla senkron
/// olana kadar. Senkron olunca gelecege tasmis kayitli zamanlar
/// GameProgress icinde temizlenir.
class TimeService {
  TimeService._();
  static final TimeService instance = TimeService._();

  static const String _prefsKey = 'time_service_last_server_ms_v1';

  /// HTTPS uclari (ikisi de "Date" basligi doner). Sirayla denenir.
  static const List<String> _endpoints = [
    'https://www.google.com/generate_204',
    'https://www.cloudflare.com/cdn-cgi/trace',
  ];
  static const Duration _requestTimeout = Duration(seconds: 4);

  /// Acilista senkron icin beklenecek EN FAZLA sure. Bu sure asilirsa
  /// oyun beklemeden acilir, istek arka planda devam eder.
  static const Duration _initWait = Duration(seconds: 3);

  DateTime? _anchorServerUtc; // senkron anindaki sunucu saati
  DateTime? _anchorDeviceUtc; // ayni anda cihazin duvar saati
  final Stopwatch _sw = Stopwatch(); // senkrondan beri gecen (monotonik) sure
  DateTime? _lastServerUtc; // diske yazilan son guvenilir sunucu saati
  bool _fresh = false; // senkron oldu ve o zamandan beri arka plana gitmedi
  bool _syncing = false;

  /// Bu oturumda en az bir kez sunucuyla senkron olundu mu?
  bool get isSynced => _anchorServerUtc != null;

  /// main() icinde, GameProgress.load()'dan ONCE await edilir.
  Future<void> init() async {
    await _loadLast();
    try {
      await syncWithServer().timeout(_initWait, onTimeout: () => false);
    } catch (_) {
      // Senkron basarisiz - cihaz saatiyle (korumali) devam.
    }
  }

  /// Oyun ici tum "simdi" sorgulari BURADAN gecmeli. Yerel saat doner
  /// (gun/hafta/ay sinirlari oyuncunun kendi saat dilimine gore).
  DateTime now() => _nowUtc().toLocal();

  DateTime _nowUtc() {
    final devNow = DateTime.now().toUtc();
    final anchorServer = _anchorServerUtc;
    final anchorDevice = _anchorDeviceUtc;

    // Bu oturumda hic senkron olunamadi: cihaz saati, ama son gorulen
    // sunucu saatinden geri gitmesin.
    if (anchorServer == null || anchorDevice == null) {
      final last = _lastServerUtc;
      if (last != null && devNow.isBefore(last)) return last;
      return devNow;
    }

    final mono = anchorServer.add(_sw.elapsed);
    // Taze senkronda monotonik saate tam guven (cihaz saati oynansa bile).
    if (_fresh) return mono;

    // Arka plandan donduk ama henuz yeniden senkron olamadik: telefon
    // uykudayken Stopwatch durmus olabilir, bu yuzden cihaz saatinden
    // hesaplanan degerle monotonik degerin buyugunu al.
    final wall = anchorServer.add(devNow.difference(anchorDevice));
    return wall.isAfter(mono) ? wall : mono;
  }

  /// Sunucuyla senkron olur. Basariliysa true doner. Ayni anda tek
  /// istek calisir. Uygulama arka plandan donunce cagrilir.
  Future<bool> syncWithServer() async {
    if (_syncing) return false;
    _syncing = true;
    try {
      for (final url in _endpoints) {
        final t = await _fetchServerUtc(url);
        if (t == null) continue;
        _anchorServerUtc = t;
        _anchorDeviceUtc = DateTime.now().toUtc();
        _sw
          ..reset()
          ..start();
        _fresh = true;
        _lastServerUtc = t;
        unawaited(_saveLast());
        return true;
      }
      return false;
    } finally {
      _syncing = false;
    }
  }

  /// Uygulama arka plana alinirken cagrilir: taze ise son guvenilir
  /// sunucu saatini diske yazar ve "taze" bayragini dusurur (uykuda
  /// Stopwatch'a guvenilmez, donuste yeniden senkron olunacak).
  void onPaused() {
    if (_fresh) {
      _lastServerUtc = _nowUtc();
      unawaited(_saveLast());
    }
    _fresh = false;
  }

  Future<DateTime?> _fetchServerUtc(String url) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse(url)).timeout(_requestTimeout);
      final resp = await req.close().timeout(_requestTimeout);
      sw.stop();
      await resp.drain<void>().timeout(_requestTimeout);
      final date = resp.headers.date;
      if (date == null) return null;
      final utc = date.toUtc();
      if (utc.year < 2024) return null; // saçma/bozuk yanit
      // Yanit, sunucu saatini okuduktan yaklasik gecikmenin yarisi kadar
      // sonra bize ulasti.
      return utc.add(Duration(milliseconds: sw.elapsedMilliseconds ~/ 2));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadLast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefsKey);
      if (ms != null) {
        _lastServerUtc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
    } catch (_) {}
  }

  Future<void> _saveLast() async {
    try {
      final last = _lastServerUtc;
      if (last == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, last.millisecondsSinceEpoch);
    } catch (_) {}
  }
}
