import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase Analytics sarmalayicisi — Appodeal panelinin GOSTERMEDIGI
/// verileri (yeni/eski kullanici ayrimi, retention, kullanici basina
/// rewarded/interstitial izleme sayisi) Firebase Console'da gormek icin.
///
/// ONEMLI: Bu servis `firebase_options.dart` / `flutterfire configure`
/// CLI'sina IHTIYAC DUYMAZ. Bunun yerine klasik/native yontemi kullanir:
/// `Firebase.initializeApp()` parametresiz cagrildiginda, Android
/// tarafinda `android/app/google-services.json` dosyasini (Google
/// Services Gradle eklentisi araciligiyla derleme sirasinda islenmis
/// halini) otomatik okur. Bu sayede:
///  - Bilgisayarda `flutterfire configure` calistirmana GEREK KALMAZ.
///  - Tek yapman gereken: Firebase konsolundan indirdigin
///    `google-services.json` dosyasini `android/app/` klasorune
///    KENDIN eklemen (ya da GitHub Actions'ta bir secret'tan bu dosyayi
///    build oncesi yazdirman) — bkz. README_FIREBASE.md.
///
/// Bu dosya yoksa Gradle build'i "File google-services.json is missing"
/// hatasiyla BASARISIZ olur; bu KASITLI bir davranistir (Google'in kendi
/// eklentisinin varsayilani), boylece Firebase'siz yanlislikla yayina
/// cikilmaz. Dosyayi eklemeden test etmek istersen android/app/build.gradle
/// icindeki `id "com.google.gms.google-services"` satirini gecici olarak
/// yorum satirina alabilirsin.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  bool _initialized = false;
  FirebaseAnalytics? _analytics;

  /// SplashScreen._bootAudioAndAds icinde, digerleri gibi navigasyonu
  /// BLOKLAMADAN cagrilir. google-services.json henuz eklenmemisse veya
  /// web platformundaysa (Appodeal SDK'sinda oldugu gibi) sessizce hicbir
  /// sey yapmadan cikar — oyunun geri kalani asla etkilenmez.
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      // Firebase Analytics zaten OTOMATIK olarak "first_open" (ilk acilis
      // = yeni kullanici) ve "session_start" (her oturum) olaylarini
      // kendi kendine loglar — Firebase Console > Analytics > Realtime /
      // Retention ekraninda "Yeni Kullanicilar" ve "Geri Donen
      // Kullanicilar" (New vs Returning) otomatik olarak ayrisir, bunun
      // icin bizim ayrica kod yazmamiza gerek yok.
      _initialized = true;
    } catch (_) {
      // google-services.json eksik/gecersizse ya da baska bir kurulum
      // sorunu varsa, oyun Analytics OLMADAN normal calismaya devam eder.
      _initialized = false;
    }
  }

  /// Odullu reklam ONAY DIYALOGU acildiginda (kullanici henuz "izle" ya da
  /// "vazgec" demeden ONCE) cagrilir. Bu, oyuncunun o rescue/bonus
  /// mekanizmasina GERCEKTEN ihtiyac duydugu/istedigi anin kaydidir —
  /// "oyun cok kolay oldu, kimse sikismiyor" ile "sikisiyorlar ama
  /// reklami reddediyorlar" ihtimallerini birbirinden ayirmak icin bu
  /// event'i, asagidaki logRewardedAdShown (gercekten izlenen) ile
  /// KARSILASTIRMAN gerekiyor:
  ///  - offer_shown COK AZ ise -> oyuncular o ozelligi hic tetiklemiyor
  ///    (rescue mekanikleri icin: oyun muhtemelen fazla kolay).
  ///  - offer_shown COK ama rewarded_ad_shown AZ ise -> oyuncular teklifi
  ///    goruyor ama reddediyor (tesvik/UX sorunu, zorluk sorunu degil).
  Future<void> logAdOfferShown(String placementId) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'ad_offer_shown',
        parameters: {'placement': placementId},
      );
    } catch (_) {}
  }

  /// Odullu reklam onay diyalogu, kullanici "izle" demeden KAPANDIYSA
  /// (vazgecti / disariya dokundu) cagrilir. logAdOfferShown ile
  /// birlikte okununca "teklif goruldu ama reddedildi" oranini verir.
  Future<void> logAdOfferDeclined(String placementId) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'ad_offer_declined',
        parameters: {'placement': placementId},
      );
    } catch (_) {}
  }

  /// Orbit modunda "sikisma" (jam/deadlock) diyalogu goruldugunde cagrilir
  /// — bu, ad teklifinden BAGIMSIZ, saf bir "oyun bu noktada zorlasti mi"
  /// sinyalidir. Gun basina bu event'in sikligi, zorluk ayari icin en
  /// guvenilir gosterge.
  Future<void> logGameStuckShown(String context) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'game_stuck_shown',
        parameters: {'context': context},
      );
    } catch (_) {}
  }

  /// Kozmik Ikmal butonuna basildi ama cooldown DOLMAMISTI (odul
  /// verilmedi, sadece "bekle" toast'i gosterildi). Bu, kullanicilarin
  /// ozelligi fark edip denedigini ama zamanlama yuzunden
  /// kacirdigini gosterir — "hic fark edilmiyor" ihtimalinden ayirmak
  /// icin onemli.
  Future<void> logResupplyNotReady() async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(name: 'resupply_not_ready');
    } catch (_) {}
  }

  /// Odullu reklam GERCEKTEN goruntulendiginde (kullanici odulu aldi/
  /// almadi fark etmeksizin, reklam ekranda acildiginda) cagrilir.
  /// Firebase Console'da bunu kullanici basina, gun basina, cihaz/ulke
  /// kirilimina gore sayabilirsin — Appodeal panelinde olmayan detay bu.
  /// `placementId`, logAdOfferShown ile ayni degeri tasir; boylece
  /// Firebase'de placement bazinda "teklif goruldu -> gercekten
  /// izlendi" donusum oranini (funnel) karsilastirabilirsin.
  Future<void> logRewardedAdShown({
    required bool rewardGranted,
    required String placementId,
  }) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'rewarded_ad_shown',
        parameters: {
          'reward_granted': rewardGranted,
          'placement': placementId,
        },
      );
    } catch (_) {}
  }

  /// Gecis (interstitial) reklami GERCEKTEN goruntulendiginde cagrilir.
  Future<void> logInterstitialShown() async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(name: 'interstitial_ad_shown');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Bolum (level) hunisi — hangi bolumde kac oyuncunun basladigini,
  // bitirdigini ve sikistigini gormek icin. `mode` 'orbit' ya da 'tube'.
  // Firebase Console'da bu ucunu (start/complete/jam) ayni bolum
  // numarasina gore karsilastirarak "bolum X'te oyuncularin
  // %Y'si birakiyor" grafigini cikarabilirsin.
  // ---------------------------------------------------------------------
  Future<void> logLevelStart(String mode, int stage) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'level_start',
        parameters: {'mode': mode, 'stage': stage},
      );
    } catch (_) {}
  }

  Future<void> logLevelComplete(
    String mode,
    int stage, {
    required int stars,
    required int moves,
  }) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'level_complete',
        parameters: {
          'mode': mode,
          'stage': stage,
          'stars': stars,
          'moves': moves,
        },
      );
    } catch (_) {}
  }

  /// Sikisma (jam) diyalogunda oyuncunun ne yaptigini kaydeder:
  /// 'retry' (reklam/meteor/banka ile devam etti VEYA sifirdan tekrar
  /// denedi) ya da 'exit' (dogrudan ana menuye dondu — rage-quit
  /// sinyali). Bu, hangi bolumlerin oyuncuyu gercekten oyunu birakmaya
  /// ittigini gorebilmek icin logGameStuckShown'dan daha kesin bir
  /// sonuc metrigi.
  Future<void> logJamDialogOutcome(String mode, int stage, String outcome) async {
    if (!_initialized || _analytics == null) return;
    try {
      await _analytics!.logEvent(
        name: 'jam_dialog_outcome',
        parameters: {'mode': mode, 'stage': stage, 'outcome': outcome},
      );
    } catch (_) {}
  }
}
