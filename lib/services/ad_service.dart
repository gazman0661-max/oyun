import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import '../localization/app_strings.dart';
import '../widgets/ui_kit.dart';

/// Odullu (rewarded) + gecis (interstitial) reklam servisi - Appodeal Mobile
/// Ads Flutter SDK (stack_appodeal_flutter). Eski oyundaki (AstroFelyx)
/// calisan yapidan tasindi; Merge Dunyalari'na uyarlandi.
///
/// KULLANIM:
///  - main(): [initializeSdk] (BEKLENMEZ, hata firlatmaz).
///  - Odullu: `final ok = await watchRewardedAd(context);` (true = odul ver).
///  - Gecis: bolum bitip oyuncu sonraki ekrana gecerken
///    `await AdService.instance.notifyChapterCompleted();`
///  - GDPR / AB rizasi: Appodeal'in KENDI resmi formu (Google UMP tabanli)
///    SDK baslayinca bolgeye gore OTOMATIK gosterilir; ayarlardaki buton
///    [openAdConsentForm] ile yeniden acar.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Appodeal panelindeki App Key. Anahtar paket adina bagli: bu oyun artik
  /// AstroFelyx ile AYNI paket adini (com.astrofelyx.pro) kullandigi icin
  /// ayni uygulamanin anahtari burada gecerlidir.
  static const String appodealAppKey = '4f369a001101f693fcca813d3d21108905a17d9e833852de';

  /// TEST MODU: true iken Appodeal'in test reklamlari gelir (para kazanilmaz
  /// ama hesap da riske girmez). Play kapali testi sirasinda TEST kullanicilari
  /// gercek reklama tiklarsa "gecersiz trafik" sayilabilir -> test boyunca
  /// true kalsin. !!! CANLIYA CIKMADAN ONCE false YAP !!!
  static const bool testingMode = true;

  /// Reklam yuklenemediginde (doluluk yok) ama cihaz internetteyse odul
  /// verilsin mi? Eski oyundaki kural: kullanici "izle"ye bastiysa magdur
  /// olmasin. Elmas ekonomisini korumak istersen false yap.
  static const bool rewardOnNoFill = true;

  /// Ilk N bolum boyunca gecis reklami GOSTERILMEZ (yeni oyuncu ilk
  /// oturumda reklamla karsilasip kacmasin - eski oyundaki D1 duzeltmesi).
  static const int interstitialGraceChapters = 6;

  /// Grace bittikten sonra kac bolumde bir gecis reklami.
  static const int chaptersPerInterstitial = 3;

  static const String _kLifetimeChapters = 'ad_lifetime_chapters_completed_v1';

  static bool get _configured => appodealAppKey.isNotEmpty && !kIsWeb;

  bool _sdkInitialized = false;
  bool get sdkInitialized => _sdkInitialized;

  Completer<bool>? _pendingCompleter;
  Completer<void>? _pendingInterstitialCompleter;
  bool _adStartedShowing = false;
  bool _rewardGranted = false;
  Timer? _notShownWatchdog;
  int _chaptersSinceInterstitial = 0;
  int? _lifetimeCache;

  // ------------------------------------------------------------ baslatma

  /// Appodeal'i kurar, callback'leri baglar ve (AB/AEA/UK/CCPA ise) resmi
  /// riza formunu tetikler. BEKLENMEZ; hata olursa oyun etkilenmez.
  Future<void> initializeSdk() async {
    if (_sdkInitialized || !_configured) return;
    try {
      Appodeal.setTesting(testingMode);
      Appodeal.setLogLevel(testingMode ? Appodeal.LogLevelVerbose : Appodeal.LogLevelNone);
      _bindRewardedCallbacks();
      _bindInterstitialCallbacks();
      await Appodeal.initialize(
        appKey: appodealAppKey,
        adTypes: [AppodealAdType.RewardedVideo, AppodealAdType.Interstitial],
      );
      _sdkInitialized = true;
      try {
        // NOT: 'void' doner (Future degil) -> await YOK; sonuc callback'te.
        Appodeal.ConsentForm.loadAndShowIfRequired(
          appKey: appodealAppKey,
          onConsentFormDismissed: (error) {
            unawaited(preload());
            unawaited(preloadInterstitial());
          },
        );
      } catch (_) {}
      unawaited(preload());
      unawaited(preloadInterstitial());
    } catch (_) {
      // SDK baslamazsa oyun reklamsiz/simule calismaya devam eder.
    }
  }

  /// Ayarlardaki "Reklam Rizasi" butonu: resmi formu tekrar acar.
  Future<void> openAdConsentForm() async {
    if (!_configured) return;
    try {
      Appodeal.ConsentForm.load(
        appKey: appodealAppKey,
        onConsentFormLoadSuccess: (status) {
          Appodeal.ConsentForm.show(
            onConsentFormDismissed: (error) {
              // Onbellekteki reklam eski rizayla alinmisti; yenile.
              unawaited(preload());
              unawaited(preloadInterstitial());
            },
          );
        },
        onConsentFormLoadFailure: (error) {},
      );
    } catch (_) {}
  }

  // ------------------------------------------------------------ callback'ler

  void _bindRewardedCallbacks() {
    Appodeal.setRewardedVideoCallbacks(
      onRewardedVideoLoaded: (isPrecache) {},
      onRewardedVideoFailedToLoad: () {},
      onRewardedVideoShown: () {
        _adStartedShowing = true;
        _notShownWatchdog?.cancel();
      },
      onRewardedVideoShowFailed: () {
        // Gosterim hic baslayamadi: kullanici magdur olmasin.
        _finish(rewardOnNoFill);
        unawaited(preload());
      },
      onRewardedVideoFinished: (amount, reward) {
        _rewardGranted = true;
        _finish(true);
      },
      onRewardedVideoClosed: (isFinished) {
        // Odul sadece reklam gercekten bittiyse verilir.
        _finish(_rewardGranted);
        unawaited(preload());
      },
      onRewardedVideoExpired: () {},
      onRewardedVideoClicked: () {},
    );
  }

  void _bindInterstitialCallbacks() {
    Appodeal.setInterstitialCallbacks(
      onInterstitialLoaded: (isPrecache) {},
      onInterstitialFailedToLoad: () {},
      onInterstitialShown: () {},
      onInterstitialShowFailed: () {
        _finishInterstitial();
        unawaited(preloadInterstitial());
      },
      onInterstitialClosed: () {
        _finishInterstitial();
        unawaited(preloadInterstitial());
      },
      onInterstitialClicked: () {},
      onInterstitialExpired: () {
        unawaited(preloadInterstitial());
      },
    );
  }

  void _finish(bool result) {
    _notShownWatchdog?.cancel();
    final c = _pendingCompleter;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  void _finishInterstitial() {
    final c = _pendingInterstitialCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  // ------------------------------------------------------------ onbellek

  Future<void> preload() async {
    if (!_sdkInitialized) return;
    try {
      if (!await Appodeal.isLoaded(AppodealAdType.RewardedVideo)) {
        Appodeal.cache(AppodealAdType.RewardedVideo);
      }
    } catch (_) {}
  }

  Future<void> preloadInterstitial() async {
    if (!_sdkInitialized) return;
    try {
      if (!await Appodeal.isLoaded(AppodealAdType.Interstitial)) {
        Appodeal.cache(AppodealAdType.Interstitial);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------ gecis reklami

  Future<int> _lifetimeChapters() async {
    if (_lifetimeCache != null) return _lifetimeCache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _lifetimeCache = prefs.getInt(_kLifetimeChapters) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _bumpLifetimeChapters() async {
    final updated = (await _lifetimeChapters()) + 1;
    _lifetimeCache = updated;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLifetimeChapters, updated);
    } catch (_) {}
  }

  /// Oyuncu bolumu bitirip sonraki ekrana gecerken cagrilir. Grace bitince
  /// "N bolumde 1" gecis reklami gosterir ve KAPANANA kadar bekler (cagiran
  /// `await` etmeli). Reklam hazir degilse sessizce doner, sayac korunur.
  Future<void> notifyChapterCompleted() async {
    if (!_configured) return;
    await _bumpLifetimeChapters();
    if ((await _lifetimeChapters()) <= interstitialGraceChapters) return;
    _chaptersSinceInterstitial++;
    if (_chaptersSinceInterstitial >= chaptersPerInterstitial) {
      await showInterstitialIfReady();
    }
  }

  Future<void> showInterstitialIfReady() async {
    if (!_sdkInitialized) return;
    try {
      if (!await Appodeal.isLoaded(AppodealAdType.Interstitial)) {
        unawaited(preloadInterstitial());
        return; // sayac KORUNUR: hazir olunca sonraki firsatta gosterilir
      }
      _chaptersSinceInterstitial = 0;
      final c = Completer<void>();
      _pendingInterstitialCompleter = c;
      Appodeal.show(AppodealAdType.Interstitial);
      await c.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    } catch (_) {}
  }

  // ------------------------------------------------------------ odullu reklam

  /// Cihaz GERCEKTEN internete cikabiliyor mu? (ucak modu ile bos donusten
  /// bedava odul almayi onlemek icin). Birkac domain denenir.
  Future<bool> _hasRealInternet() async {
    for (final host in const ['google.com', 'cloudflare.com', 'pub.dev']) {
      try {
        final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
        if (r.isNotEmpty && r.first.rawAddress.isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Reklami yukler/gosterir. true = odul verilmeli.
  Future<bool> showRewarded(BuildContext context) async {
    if (!_configured) return _simulate(context);

    if (!await _hasRealInternet()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AppStrings.instance.t('ad_no_internet'))));
      }
      return false;
    }
    if (!context.mounted) return false;

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
    if (!_sdkInitialized) return rewardOnNoFill; // SDK hazir degil: kullanici magdur olmasin
    if (!await Appodeal.isLoaded(AppodealAdType.RewardedVideo)) {
      unawaited(preload());
      return rewardOnNoFill; // doluluk yok
    }
    _rewardGranted = false;
    _adStartedShowing = false;
    final completer = Completer<bool>();
    _pendingCompleter = completer;
    try {
      Appodeal.show(AppodealAdType.RewardedVideo);
    } catch (_) {
      _finish(rewardOnNoFill);
    }
    // Guvenlik agi: 15 sn icinde "gosterildi" gelmezse takili kalma.
    // Reklam bir kez basladiysa bu zamanlayici iptal olur.
    _notShownWatchdog = Timer(const Duration(seconds: 15), () {
      if (!_adStartedShowing) _finish(rewardOnNoFill);
    });
    return completer.future;
  }

  /// Appodeal anahtari girilene kadar eski test davranisi.
  Future<bool> _simulate(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AdLoadingDialog(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!context.mounted) return false;
    Navigator.of(context, rootNavigator: true).pop();
    return true;
  }
}

/// Tum cagri noktalarinin kullandigi tek fonksiyon (eski watchMockRewardedAd'in yerine).
Future<bool> watchRewardedAd(BuildContext context) => AdService.instance.showRewarded(context);

class _AdLoadingDialog extends StatelessWidget {
  const _AdLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text(AppStrings.instance.t('ad_loading'))),
          ],
        ),
      ),
    );
  }
}
