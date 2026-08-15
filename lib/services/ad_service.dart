import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_toast.dart';
import 'analytics_service.dart';
import 'localization.dart';
import 'sound_service.dart';

/// Odullu (rewarded) reklam akisini yoneten servis — Appodeal Mobile Ads
/// Flutter SDK (stack_appodeal_flutter) ile gercek entegrasyon. Appodeal
/// tek bir global mediation SDK'si oldugu icin (Yandex'teki gibi "her
/// istekte yeni bir Ad nesnesi" degil) reklam durumu ve callback'ler
/// SDK genelinde tek noktadan (bu sinif icinde) yonetilir.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Appodeal panelinden alinan App Key.
  static const String appodealAppKey =
      '4f369a001101f693fcca813d3d21108905a17d9e833852de';

  /// TEST MODU — Appodeal'in kendi test/demo reklamlarini gostermesini
  /// saglar (gercek doluluk/odeme UZERINDE ETKISI YOKTUR, sadece test
  /// reklami gelir). !!! YAYINA CIKMADAN ONCE "false" YAP !!! Aksi halde
  /// gercek reklamlar yerine surekli test reklami gosterilir ve GERCEK
  /// PARA KAZANILMAZ.
  static const bool testingMode = false;

  bool _sdkInitialized = false;
  bool get sdkInitialized => _sdkInitialized;

  Completer<bool>? _pendingCompleter;
  bool _adStartedShowing = false;
  bool _rewardGranted = false;
  Timer? _notShownWatchdog;
  // Su an devam eden odullu reklam akisinin hangi yerlesime (hint, undo,
  // resupply, vb.) ait oldugunu tutar — Firebase event'lerinde placement
  // bazinda funnel analizi yapabilmek icin. Tek seferde tek bir rewarded
  // akisi olabildigi icin (_pendingCompleter gibi) paylasilan tek bir
  // alan yeterli.
  String _currentPlacementId = 'unknown';

  // --- Interstitial (gecis reklami) durumu ---
  // Rewarded'dan farkli olarak interstitial'da "odul" yok, bu yuzden
  // basit bir completer yeterli: gosterim bitince (basarili/basarisiz
  // fark etmeksizin) tamamlanir ki cagiran taraf bir sonraki bolume
  // GECIS REKLAMI KAPANDIKTAN SONRA gecebilsin.
  Completer<void>? _pendingInterstitialCompleter;

  // "Toplamda 2 bolumde 1 gecis reklami" sayaci — Orbit VE Tup modlari
  // ORTAK kullanir (biri 1, digeri 1 oynasa bile toplam 2 sayilir).
  // AdService uygulama omru boyunca yasayan bir singleton oldugu icin bu
  // sayac, kullanici ana menuye donup tekrar bir bolume girse bile
  // SIFIRLANMAZ; SADECE uygulama tamamen kapatilip yeniden acildiginda
  // (yeni process = yeni AdService ornegi) sifirdan baslar.
  int _stagesCompletedSinceInterstitial = 0;

  /// Uygulama acilisinda (SplashScreen._bootAudioAndAds) BIR KERE
  /// cagrilir: Appodeal SDK'sini kurar, odullu + gecis reklami
  /// callback'lerini baglar. Appodeal SDK 3.0+'dan itibaren, kullanici
  /// AB/AEA/Isvicre/UK/CCPA bolgesindeyse KENDI resmi onay ekranini
  /// (Google UMP tabanli Stack Consent Manager) ILK BASLATMADA OTOMATIK
  /// gosterir — bunun icin ekstra kod GEREKMEZ. Ayrica burada acikca da
  /// tetikliyoruz (zaten gerekli degilse/onaylanmissa hicbir sey
  /// yapmaz, sadece garanti altina alir).
  Future<void> initializeSdk() async {
    if (_sdkInitialized) return;

    Appodeal.setTesting(testingMode);
    Appodeal.setLogLevel(
      testingMode ? Appodeal.LogLevelVerbose : Appodeal.LogLevelNone,
    );
    _bindRewardedCallbacks();
    _bindInterstitialCallbacks();

    await Appodeal.initialize(
      appKey: appodealAppKey,
      adTypes: [AppodealAdType.RewardedVideo, AppodealAdType.Interstitial],
    );
    _sdkInitialized = true;

    try {
      // NOT: Appodeal.ConsentForm.loadAndShowIfRequired 'void' donuyor
      // (Future degil), bu yuzden 'await' KULLANILAMAZ — derleme hatasi
      // ("This expression has type 'void' and can't be used") buradan
      // kaynaklaniyordu. Sonuc zaten kendi callback'i
      // (onConsentFormDismissed) uzerinden asenkron olarak geliyor.
      Appodeal.ConsentForm.loadAndShowIfRequired(
        appKey: appodealAppKey,
        onConsentFormDismissed: (error) {
          // Kullanici resmi riza formunu (varsa) kapatti; onbellekteki
          // reklami yeni rizaya gore tazele.
          unawaited(preload());
          unawaited(preloadInterstitial());
        },
      );
    } catch (_) {
      // Onay formu yuklenemezse (ör. internet yok) reklamlar yine de
      // bolgeye gore varsayilan davranisla calismaya devam eder.
    }
  }

  void _bindRewardedCallbacks() {
    Appodeal.setRewardedVideoCallbacks(
      onRewardedVideoLoaded: (isPrecache) {},
      onRewardedVideoFailedToLoad: () {},
      onRewardedVideoShown: () {
        _adStartedShowing = true;
        _notShownWatchdog?.cancel();
      },
      onRewardedVideoShowFailed: () {
        // Gosterim teknik bir sebeple hic baslayamadi — bos donus
        // sayilir, odul verilir (kullanicinin magdur olmamasi icin).
        _finish(true);
        unawaited(preload());
      },
      onRewardedVideoFinished: (amount, reward) {
        _rewardGranted = true;
        _finish(true);
      },
      onRewardedVideoClosed: (isFinished) {
        // Reklam fiilen gosterildi. Odul, sadece gercekten
        // tamamlandiysa (onRewardedVideoFinished tetiklendiyse) verilir;
        // yarida kapatildiysa odul yok.
        if (_adStartedShowing) {
          // Sadece reklam GERCEKTEN ekranda gosterildiyse logla — bos
          // donus/basarisiz yukleme durumlarinda (onRewardedVideoShowFailed)
          // burasi zaten tetiklenmiyor, o yuzden ekstra kontrole gerek yok
          // ama acikca belirtmek icin birakildi.
          unawaited(AnalyticsService.instance.logRewardedAdShown(
            rewardGranted: _rewardGranted,
            placementId: _currentPlacementId,
          ));
        }
        _finish(_rewardGranted);
        unawaited(preload());
      },
      onRewardedVideoExpired: () {},
      onRewardedVideoClicked: () {},
    );
  }

  void _finish(bool result) {
    _notShownWatchdog?.cancel();
    final completer = _pendingCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _bindInterstitialCallbacks() {
    Appodeal.setInterstitialCallbacks(
      onInterstitialLoaded: (isPrecache) {},
      onInterstitialFailedToLoad: () {},
      onInterstitialShown: () {
        unawaited(AnalyticsService.instance.logInterstitialShown());
      },
      onInterstitialShowFailed: () {
        _finishInterstitial();
        unawaited(preloadInterstitial());
      },
      onInterstitialClosed: () {
        _finishInterstitial();
        // Bir sonraki "2 bolumde 1" gecis reklami icin onbellegi hemen
        // tazele — kullanici oyuna donerken reklam zaten hazir olsun.
        unawaited(preloadInterstitial());
      },
      onInterstitialClicked: () {},
      onInterstitialExpired: () {
        unawaited(preloadInterstitial());
      },
    );
  }

  void _finishInterstitial() {
    final completer = _pendingInterstitialCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Bir sonraki gosterim icin Appodeal'in onceden reklam onbelleklemesini
  /// (auto-cache varsayilan olarak zaten ACIK) tetikler/garanti eder.
  /// Basarisiz olursa sessizce yutulur; Appodeal kendi ic mekanizmasiyla
  /// zaten arka planda tekrar tekrar dener.
  Future<void> preload() async {
    if (!_sdkInitialized) return;
    try {
      final loaded = await Appodeal.isLoaded(AppodealAdType.RewardedVideo);
      if (!loaded) {
        Appodeal.cache(AppodealAdType.RewardedVideo);
      }
    } catch (_) {}
  }

  /// Gecis (interstitial) reklamini onceden onbellege alir — aynen
  /// rewarded'daki [preload] gibi calisir.
  Future<void> preloadInterstitial() async {
    if (!_sdkInitialized) return;
    try {
      final loaded = await Appodeal.isLoaded(AppodealAdType.Interstitial);
      if (!loaded) {
        Appodeal.cache(AppodealAdType.Interstitial);
      }
    } catch (_) {}
  }

  /// Orbit VEYA Tup modunda bir bolum basariyla tamamlandiginda cagirilir
  /// (bkz. GameScreen/OrbitGameScreen > onNext). Ortak sayaci 1 artirir;
  /// toplam (iki mod BIRLIKTE sayilarak) 2'ye ulastiginda sayaci
  /// sifirlar ve (hazirsa) gecis reklamini gosterip kapanana kadar
  /// bekler. Cagiran taraf bunu `await` ederek reklam kapandiktan SONRA
  /// bir sonraki bolume gecmelidir.
  Future<void> notifyStageCompleted() async {
    _stagesCompletedSinceInterstitial++;
    if (_stagesCompletedSinceInterstitial >= 2) {
      // DUZELTME: sayac ARTIK burada degil, sadece reklam GERCEKTEN
      // gosterildiyse sifirlaniyor (bkz. showInterstitialIfReady).
      // Onceki halinde doluluk yoksa (loaded == false) bile sayac
      // sifirlaniyordu; bu da o an gosterilmesi gereken interstitial'in
      // sessizce "kaybolmasina" ve bir sonraki firsatin gerekenden 2
      // bolum daha gec gelmesine sebep oluyordu (sistematik gelir kaybi).
      await showInterstitialIfReady();
    }
  }

  /// "2 bolumde 1 gecis reklami" akisi icin cagrilir: eger o an
  /// onbellekte hazir bir interstitial varsa gosterir ve kapanana kadar
  /// (Future) bekletir; hazir degilse (doluluk yok / henuz yuklenmedi)
  /// SESSIZCE hicbir sey yapmadan hemen doner — kullaniciyi bos yere
  /// bekletmeyiz, oyun akisi kesintisiz devam eder.
  ///
  /// DUZELTME: sayac (_stagesCompletedSinceInterstitial) SADECE reklam
  /// gercekten gosterilebildiyse (loaded == true, show() cagrildi)
  /// sifirlanir. Doluluk yoksa sayac KORUNUR, boylece bir sonraki bolum
  /// tamamlaninca tekrar denenir — o "2 bolumde 1" firsati kaybolmaz,
  /// sadece reklam hazir olana kadar ertelenir.
  Future<void> showInterstitialIfReady() async {
    if (!_sdkInitialized) return;
    try {
      final loaded = await Appodeal.isLoaded(AppodealAdType.Interstitial);
      if (!loaded) {
        unawaited(preloadInterstitial());
        return;
      }
      _stagesCompletedSinceInterstitial = 0;
      final completer = Completer<void>();
      _pendingInterstitialCompleter = completer;
      Appodeal.show(AppodealAdType.Interstitial);
      // Guvenlik agi: native tarafta hicbir callback tetiklenmezse (cok
      // nadir) sonsuza kadar takili kalmayalim.
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    } catch (_) {
      // Gosterim basarisiz olursa oyun akisini engellemeyelim.
    }
  }

  /// GDPR/riza tercihi SONRADAN degistiginde (bkz. GdprService.
  /// openAdConsentForm) cagrilir: onbellekteki reklamin yeni rizaya gore
  /// tazelenmesini saglar.
  void refreshForConsentChange() {
    unawaited(preload());
  }

  /// Cihazin GERCEKTEN internete cikip cikamadigini kontrol eder (sadece
  /// "wifi/mobil veri simgesi acik mi" degil). Kullanicilarin ucus modu/
  /// internet kapatip reklami BILEREK bos donduruerek odulu bedavaya
  /// almasini onlemek icin: bos donus/basarisiz yukleme durumunda odul
  /// SADECE cihaz gercekten cevrimdeysa (reklam sunucusuna GERCEKTEN
  /// ulasilamadiysa, orn. doluluk yoksa) verilir; internet tamamen
  /// kapaliysa odul verilmez.
  ///
  /// `InternetAddress.lookup` kucuk bir DNS sorgusu yapar; sadece cihazin
  /// bir aga bagli GORUNMESINE degil, o agin fiilen calisip calismadigina
  /// bakar (ucus modunda/interneti kapatildiginda bu sorgu basarisiz olur).
  ///
  /// DUZELTME: tek bir domain'e (ör. sadece "pub.dev") guvenmek riskliydi
  /// — bazi ulkelerde/kurumsal aglarda/DNS saglayicilarinda bu tek domain
  /// engellenmis veya erisilemez olabilir, boylece cihaz GERCEKTEN
  /// cevrimici olsa bile yanlislikla "cevrimdisi" sayilip odul haksiz
  /// yere reddedilebilirdi (false negative). Bunun yerine birkac cok
  /// yaygin/genel-erisilebilir domain sirayla denenir; HERHANGI biri
  /// basarili olursa cihaz cevrimici kabul edilir.
  Future<bool> _hasRealInternetConnection() async {
    const candidates = ['google.com', 'cloudflare.com', 'pub.dev'];
    for (final host in candidates) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 4));
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        // Bu domain basarisiz oldu, siradakini dene.
      } on TimeoutException {
        // Bu domain zaman asimina ugradi, siradakini dene.
      } catch (_) {
        // Beklenmeyen bir hata, siradakini dene.
      }
    }
    return false;
  }

  /// Kullaniciya "Reklam Izle" onay diyalogunu gosterir, onaylanirsa
  /// gercek odullu reklami yukleyip gosterir ve odulun verilip
  /// verilmeyecegini (true/false) dondurur. Kullanici iptal ederse null
  /// doner.
  Future<bool?> showRewardedAdFlow(
    BuildContext context, {
    required String icon,
    required String title,
    required String placementId,
    String? subtitle,
  }) async {
    _currentPlacementId = placementId;
    // Teklif (onay diyalogu) acildi — kullanici henuz "izle" ya da
    // "vazgec" demedi. Bu, o rescue/bonus ozelligine GERCEKTEN
    // ihtiyac duyuldugu/istendigi anin kaydidir (bkz.
    // AnalyticsService.logAdOfferShown dokumantasyonu).
    unawaited(AnalyticsService.instance.logAdOfferShown(placementId));
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _AdConfirmDialog(
        icon: icon,
        title: title,
        subtitle: subtitle ?? t('ad_defaultSubtitle'),
      ),
    );
    if (confirmed != true) {
      unawaited(AnalyticsService.instance.logAdOfferDeclined(placementId));
      return null;
    }
    if (!context.mounted) return false;

    // Odul verilmeden ONCE cihazin gercekten internete cikip cikamadigini
    // dogrula. Bu kontrol olmadan, kullanici interneti kapatip butona
    // basarsa reklam hicbir zaman yuklenemez ve asagidaki "bos donus =
    // odul ver" kurali (doluluk sorunlarinda kullanicinin magdur olmamasi
    // icin var) istismar edilerek bedava odul alinabilirdi.
    final online = await _hasRealInternetConnection();
    if (!online) {
      if (context.mounted) {
        CustomToast.show(
          context,
          t('ad_noInternet'),
          icon: '📡',
          accentColor: AppColors.warning,
        );
      }
      return false;
    }

    // "Yukleniyor" gostergesi + reklamin gercekten yuklenip gosterilmesi.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AdLoadingDialog(),
    ));
    final granted = await _loadAndShow();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return granted;
  }

  Future<bool> _loadAndShow() async {
    if (!_sdkInitialized) {
      // SDK henuz hazir degilse kullanicinin kusuru degil, magdur etme.
      return true;
    }

    final loaded = await Appodeal.isLoaded(AppodealAdType.RewardedVideo);
    if (!loaded) {
      // Reklam yuklenemedi / bos dondu (doluluk sorunu — internet yok,
      // envanter yok vb.). Bu kullanicinin kusuru degil, "Reklam Izle"yi
      // onaylamisti; odul yine de verilir ki kullanici kizip oyunu
      // birakmasin.
      unawaited(preload());
      return true;
    }

    _rewardGranted = false;
    _adStartedShowing = false;
    final completer = Completer<bool>();
    _pendingCompleter = completer;

    // DUZELTME (v2 - "bazen odul vermiyor" KOKTEN COZUM): reklam GERCEKTEN
    // ekranda gosterilmeye basladiysa (onRewardedVideoShown tetiklendiyse),
    // asagidaki zaman asimi guvenlik agi iptal edilir ve artik SADECE
    // gercek Appodeal olaylari (onRewardedVideoFinished /
    // onRewardedVideoClosed / onRewardedVideoShowFailed) sonucu belirler —
    // reklam ister 20 saniye ister 90 saniye sursun, kullanici onu
    // izledigi surece odul kaybolmaz.
    try {
      Appodeal.show(AppodealAdType.RewardedVideo);
    } catch (_) {
      // Gosterim hic baslatilamadi — bos donus sayilir, odul verilir.
      _finish(true);
    }

    // Guvenlik agi: `show()` cagrildiktan sonra 15 saniye icinde
    // `onRewardedVideoShown` HIC tetiklenmezse (native tarafta tamamen
    // takildiysa), kullaniciyi sonsuza kadar bekletmemek icin odul
    // verilerek tamamlanir. Reklam bir kez gosterilmeye basladiysa
    // (_adStartedShowing == true) bu zamanlayici zaten iptal edilmis
    // olur ve artik hicbir zaman asimi devreye girmez.
    _notShownWatchdog = Timer(const Duration(seconds: 15), () {
      if (!_adStartedShowing) _finish(true);
    });
    return completer.future;
  }
}

class _AdConfirmDialog extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  const _AdConfirmDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  SoundService.instance.buttonTap();
                  Navigator.of(context).pop(true);
                },
                child: Text(t('ad_watch'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.surfaceBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t('ad_cancel'),
                    style: const TextStyle(color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdLoadingDialog extends StatelessWidget {
  const _AdLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accentSoft),
            const SizedBox(height: 16),
            Text(t('ad_loading'),
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
