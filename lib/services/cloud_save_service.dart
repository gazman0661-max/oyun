import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/engage.dart';
import '../models/game_progress.dart';
import '../models/piggy.dart';
import '../models/season.dart';
import '../models/weekly_event.dart';
import 'inbox_service.dart';
import 'save_merge.dart';

/// Google Play Games girisi + OTOMATIK bulut kaydi (Kayitli Oyunlar).
///
/// IKI CIHAZ NASIL STABIL CALISIR?
///  Eski surum her seferinde TEK PARCA kaydi ustune yaziyordu ve acilistan
///  sonra bulutu bir daha okumuyordu. Yeni surum:
///   1) Her esitleme "oku -> birlestir -> yaz -> dogrula"dir (blind-write yok).
///   2) Birlestirme 3'lu (base/local/cloud): mucevher/coin harcama-kazanma
///      DELTA olarak eklenir, satin alinanlar/seviyeler asla geri gitmez
///      (bkz. save_merge.dart).
///   3) Arka plandan donuste ve on planda 60 sn'de bir bulut okunur; diger
///      cihazdaki degisiklik kisa surede bu cihaza gelir.
///   4) Yazdiktan sonra geri okuyup kendi yazimimizin kalip kalmadigina
///      bakilir; iki cihaz ayni anda yazdiysa kaybeden taraf tekrar birlestirir.
///   5) Cihaz kimligi + revizyon ("seen") ile ayni degisiklik iki kez
///      sayilmaz (uygulama yazma sirasinda kapansa bile).
///
/// SINIR: Play Games Kayitli Oyunlar sunucu tarafi islem (transaction)
/// sunmaz. Cok nadir bir yaris (iki cihaz ayni saniyede yazarsa) dogrulama +
/// yeniden birlestirme ile cozulur ama %100 atomik degildir. Gercek "sunucu
/// otoriteli" sistem icin bkz. oyun backend'i (Cloudflare Worker + D1).
class CloudSaveService {
  CloudSaveService._();
  static final CloudSaveService instance = CloudSaveService._();

  static const String _slot = 'progress';
  static const String _backupKey = 'cloud_pre_restore_backup_v1';
  static const String _kDevice = 'cloud_device_id_v1';
  static const String _kBase = 'cloud_base_v1';
  static const String _kPending = 'cloud_pending_v1';

  bool signedIn = false;
  bool busy = false;
  String? lastError;

  bool _syncing = false;
  bool _again = false;
  bool _foreground = true;
  Timer? _uploadTimer;
  Timer? _pollTimer;

  final List<void Function()> _listeners = [];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  // ---------------------------------------------------------------- oturum

  /// Uygulama acilisinda cagrilir; BEKLENMEZ, hata firlatmaz.
  Future<void> init() async {
    try {
      signedIn = await GamesServices.isSignedIn;
    } catch (e) {
      lastError = '$e';
    }
    _startPolling();
    await syncNow();
    _notify();
  }

  /// Otomatik giris olmadiysa ayarlardaki tek dugmeyle elle giris.
  Future<bool> signIn() async {
    busy = true;
    lastError = null;
    _notify();
    try {
      await GamesServices.signIn();
      signedIn = await GamesServices.isSignedIn;
    } catch (e) {
      lastError = '$e';
      signedIn = false;
    }
    await syncNow();
    busy = false;
    _notify();
    return signedIn;
  }

  // ------------------------------------------------------ yasam dongusu

  void onResumed() {
    _foreground = true;
    _startPolling();
    syncNow();
  }

  /// Uygulama arka plana alinirken: bekleyen her seyi hemen esitle.
  Future<void> flushUpload() async {
    _foreground = false;
    _uploadTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    await syncNow();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground) syncNow();
    });
  }

  /// Eski API: acilista/geri donuste esitleme.
  Future<void> syncIfNeeded() => syncNow();

  /// Yerel kayit her yazildiginda cagrilir; 45 sn'de bir tek esitleme yapar.
  void scheduleUpload() {
    if (!signedIn) return;
    if (_uploadTimer?.isActive ?? false) return;
    _uploadTimer = Timer(const Duration(seconds: 45), () {
      syncNow();
    });
  }

  /// Satin alma sonrasi vb. hemen esitle (oku-birlestir-yaz).
  Future<bool> uploadNow() => syncNow();

  // ----------------------------------------------------------- esitleme

  Future<bool> syncNow() async {
    if (_syncing) {
      _again = true; // calisan esitleme bitince bir tur daha doner
      return false;
    }
    if (!signedIn) {
      try {
        signedIn = await GamesServices.isSignedIn;
      } catch (_) {}
    }
    if (!signedIn) return false;
    _syncing = true;
    var ok = false;
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        _again = false;
        final r = await _syncOnce();
        ok = r;
        if (r && !_again) break;
        if (!r) await Future<void>.delayed(const Duration(milliseconds: 700)); // yaris: tekrar dene
      }
      if (ok) lastError = null;
    } catch (e) {
      lastError = '$e'; // internet yok vb.: sonra tekrar denenir
      ok = false;
    }
    _syncing = false;
    _notify();
    return ok;
  }

  Future<String> _deviceId(SharedPreferences prefs) async {
    var id = prefs.getString(_kDevice);
    if (id == null || id.isEmpty) {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 30).toRadixString(36)}';
      await prefs.setString(_kDevice, id);
    }
    return id;
  }

  Future<_Cloud?> _fetchCloud() async {
    final raw = await GamesServices.loadGame(name: _slot);
    if (raw == null || raw.isEmpty) return null;
    final j = jsonDecode(raw);
    if (j is! Map || j['data'] is! Map) return null;
    final data = <String, Map<String, dynamic>>{};
    (j['data'] as Map).forEach((k, v) {
      try {
        final d = v is String ? jsonDecode(v) : v;
        if (d is Map) data['$k'] = Map<String, dynamic>.from(d);
      } catch (_) {}
    });
    final seen = <String, int>{};
    final s = j['seen'];
    if (s is Map) {
      s.forEach((k, v) {
        if (v is num) seen['$k'] = v.toInt();
      });
    }
    return _Cloud((j['rev'] as num?)?.toInt() ?? 0, seen, data);
  }

  /// Yerel hal. Ilerleme bellekten (senkron) okunur; digerleri diske yazilip okunur.
  Future<Map<String, Map<String, dynamic>>> _snapshotLocal() async {
    final out = <String, Map<String, dynamic>>{};
    out[SaveMerge.kProgress] = _roundTrip(GameProgress.instance.toJson())..remove('wheelPending'); // yarim cark buluta gitmez
    await Future.wait([
      SeasonService.instance.save(),
      PiggyService.instance.save(),
      WeeklyEvent.instance.save(),
      EngageService.instance.save(),
      InboxService.instance.save(),
    ]);
    final prefs = await SharedPreferences.getInstance();
    for (final k in SaveMerge.otherKeys) {
      final raw = prefs.getString(k);
      if (raw == null || raw.isEmpty) continue;
      try {
        final d = jsonDecode(raw);
        if (d is Map) out[k] = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return out;
  }

  Map<String, dynamic> _roundTrip(Map<String, dynamic> m) => Map<String, dynamic>.from(jsonDecode(jsonEncode(m)) as Map);

  /// Hic oynanmamis (yeni kurulum) yerel kayit mi?
  bool _looksFresh(Map<String, dynamic>? p) {
    if (p == null) return true;
    final stars = p['chapterStars'];
    return ((p['maxUnlockedChapter'] as num?)?.toInt() ?? 1) <= 1 &&
        ((p['playerLevel'] as num?)?.toInt() ?? 1) <= 1 &&
        ((p['playerXp'] as num?)?.toInt() ?? 0) == 0 &&
        (stars is! Map || stars.isEmpty);
  }

  /// true = tamam, false = yaris (tekrar dene). Ag hatasinda istisna firlatir.
  Future<bool> _syncOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final me = await _deviceId(prefs);
    final cloud = await _fetchCloud(); // okunamazsa istisna: hicbir sey yazilmaz

    var base = SaveMerge.storesFrom(prefs.getString(_kBase));

    // Onceki turdan yarim kalan yazma var mi?
    final pendingRaw = prefs.getString(_kPending);
    if (pendingRaw != null) {
      try {
        final p = jsonDecode(pendingRaw) as Map;
        final pRev = (p['rev'] as num?)?.toInt() ?? 0;
        final landed = cloud != null && pRev > 0 && (cloud.seen[me] ?? 0) >= pRev;
        if (landed) {
          // Yazimimiz buluta ulasmis ama biz uygulayamadan kapanmisiz: simdi uygula.
          final m = SaveMerge.storesFrom(p['m']);
          final l1 = SaveMerge.storesFrom(p['l1']);
          if (m != null && l1 != null) {
            await _adopt(m, l1);
            base = m;
            await prefs.setString(_kBase, jsonEncode(m));
          }
        }
      } catch (_) {}
      await prefs.remove(_kPending);
    }

    final l1 = await _snapshotLocal();

    Stores merged;
    if (cloud == null) {
      merged = l1; // bulutta kayit yok: yerel ilk kayit olur
    } else if (base == null && _looksFresh(l1[SaveMerge.kProgress])) {
      merged = cloud.data; // yeni cihaz/yeniden kurulum: bulut aynen gelir
    } else {
      merged = SaveMerge.all(base, l1, cloud.data);
    }

    final needUpload = cloud == null || !SaveMerge.deepEq(merged, cloud.data);
    if (!needUpload) {
      await _adopt(merged, l1);
      base = merged;
      await prefs.setString(_kBase, jsonEncode(merged));
      return true;
    }

    final rev = (cloud?.rev ?? 0) + 1;
    final seen = <String, int>{...?cloud?.seen, me: rev};
    // Yazmadan ONCE niyeti kaydet: yazma sirasinda kapanirsak sonra anlariz.
    await prefs.setString(_kPending, jsonEncode({'rev': rev, 'm': merged, 'l1': l1}));
    final payload = {
      'v': 2,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'rev': rev,
      'deviceId': me,
      'seen': seen,
      'chapter': (merged[SaveMerge.kProgress]?['maxUnlockedChapter'] as num?)?.toInt() ?? 1,
      'data': merged.map((k, v) => MapEntry(k, jsonEncode(v))),
    };
    await GamesServices.saveGame(data: jsonEncode(payload), name: _slot);

    // Dogrula: yazimimiz hala orada mi (baska cihaz arada yazmis olabilir)?
    final check = await _fetchCloud();
    if (check == null || (check.seen[me] ?? 0) < rev) return false;

    await _adopt(merged, l1);
    await prefs.setString(_kBase, jsonEncode(merged));
    await prefs.remove(_kPending);
    return true;
  }

  /// Birlestirilmis hali yerel servislere uygular. Agi beklerken oyuncu bir
  /// sey harcadi/kazandiysa ([l1] ile simdiki hal farki) onu ustune ekler.
  Future<void> _adopt(Map<String, Map<String, dynamic>> m, Map<String, Map<String, dynamic>> l1) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Ilerleme: senkron bolum (arada oyuncu islemi araya giremez).
    final gp = GameProgress.instance;
    final mp = m[SaveMerge.kProgress];
    if (mp != null) {
      final l2 = _roundTrip(gp.toJson());
      final a = SaveMerge.rebase(SaveMerge.kProgress, mp, l1[SaveMerge.kProgress] ?? <String, dynamic>{}, l2);
      a.remove('wheelPending'); // yarim cark odulu tekrar verilmesin
      if (!SaveMerge.deepEq(_withoutWheel(a), _withoutWheel(l2))) {
        // Eski yerel hali yedekle (bir sorun cikarsa elde kalsin).
        // NOT: asagidaki iki cagri arasinda await YOK -> uygulama senkron kalir.
        prefs.setString(_backupKey, jsonEncode({'p': l2}));
        final f = gp.applyRemote(a);
        await f;
      }
    }

    // 2) Diger depolar.
    final changed = <String>[];
    await Future.wait([
      SeasonService.instance.save(),
      PiggyService.instance.save(),
      WeeklyEvent.instance.save(),
      EngageService.instance.save(),
      InboxService.instance.save(),
    ]);
    for (final k in SaveMerge.otherKeys) {
      final mk = m[k];
      if (mk == null) continue;
      Map<String, dynamic> l2 = <String, dynamic>{};
      final raw = prefs.getString(k);
      if (raw != null && raw.isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is Map) l2 = Map<String, dynamic>.from(d);
        } catch (_) {}
      }
      final a = SaveMerge.rebase(k, mk, l1[k] ?? <String, dynamic>{}, l2);
      if (!SaveMerge.deepEq(a, l2)) {
        await prefs.setString(k, jsonEncode(a));
        changed.add(k);
      }
    }
    if (changed.contains(SaveMerge.kSeason)) await SeasonService.instance.load();
    if (changed.contains(SaveMerge.kPiggy)) await PiggyService.instance.load();
    if (changed.contains(SaveMerge.kEvents)) await WeeklyEvent.instance.load();
    if (changed.contains(SaveMerge.kEngage)) await EngageService.instance.load();
    if (changed.contains(SaveMerge.kInvite)) await InboxService.instance.reloadAfterCloudRestore();
  }

  Map<String, dynamic> _withoutWheel(Map<String, dynamic> m) {
    final c = Map<String, dynamic>.of(m);
    c.remove('wheelPending');
    return c;
  }
}

class _Cloud {
  final int rev;
  final Map<String, int> seen;
  final Map<String, Map<String, dynamic>> data;
  _Cloud(this.rev, this.seen, this.data);
}
