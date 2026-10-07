import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/game_progress.dart';
import 'services/analytics_service.dart';
import 'models/season.dart';
import 'models/piggy.dart';
import 'models/engage.dart';
import 'models/weekly_event.dart';
import 'services/notification_service.dart';
import 'services/sfx_service.dart';
import 'services/music_service.dart';
import 'services/time_service.dart';
import 'services/cloud_save_service.dart';
import 'services/billing_service.dart';
import 'services/inbox_service.dart';
import 'services/legal_consent_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  // Kayitli ilerlemeyi (varsa) uygulama acilmadan once diskten okuyoruz -
  // boylece ana menu ilk karesinden itibaren dogru coin/enerji/gorev
  // durumunu gosterir.
  WidgetsFlutterBinding.ensureInitialized();
  // Oyun dikey (portrait) oynanir.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  // Internet saati: enerji/gorev/gunluk odul artik cihaz saatine degil
  // sunucu saatine bakar. En fazla ~3 sn bekler, sonra oyun acilir.
  await TimeService.instance.init();
  await LegalConsentService.instance.load();
  await GameProgress.instance.load();
  await AnalyticsService.instance.load(); // ogretici hunisi sayaclari
  await SeasonService.instance.load();
  await PiggyService.instance.load();
  await WeeklyEvent.instance.load();
  await EngageService.instance.load();
  await InboxService.instance.load(); // gelen kutusu / davet kimligi (ag istegi yok)
  EngageService.instance.skipWelcomeForExistingPlayer();
  EngageService.instance.onAppOpen();
  await NotificationService.instance.init();
  // Ses efektlerini arka planda yukle (BEKLEMEDEN) - oyun acilisini
  // geciktirmez; yukleme bitene kadar gelen sesler sessizce atlanir.
  SfxService.instance.init();
  MusicService.instance.start();
  // Play Games bulut yedegi: acilista sessiz oturum kontrolu (BEKLENMEZ),
  // yerel kayit yazildikca (45 sn'de bir) buluta yukle.
  GameProgress.onSaved = CloudSaveService.instance.scheduleUpload;
  // Davet edilen oyuncu hedef seviyeye (7) ulasinca sunucuya haber ver (baska seviye atlamada istek yok).
  GameProgress.onLevelUp = InboxService.instance.onPlayerLevelUp;
  CloudSaveService.instance.init();
  runApp(const FastFoodMergeApp());
  // Reklam SDK'si: arayuz ekrandayken, BEKLENMEDEN kurulur (SDK sorun cikarsa
  // oyun acilisi etkilenmesin). Anahtar girilene kadar reklamlar simule edilir.
  // Play Billing: urunleri/fiyatlari yukler, yarim kalan satin almalari teslim eder.
  unawaited(BillingService.instance.init());
  // Push bildirimi (gelen kutusu): Firebase bilgileri girilene kadar hicbir sey yapmaz.
  // Reklam SDK'si + push: SADECE kullanici ilk acilis onayini (Sartlar/Gizlilik/GDPR)
  // verdiyse burada baslar; ilk kez acan oyuncuda onaydan hemen sonra baslatilir.
  LegalConsentService.instance.startConsentGatedServices();
}

class FastFoodMergeApp extends StatefulWidget {
  const FastFoodMergeApp({super.key});

  @override
  State<FastFoodMergeApp> createState() => _FastFoodMergeAppState();
}

class _FastFoodMergeAppState extends State<FastFoodMergeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama arka plana alinirken ya da kapanirken bekleyen (debounce
    // edilmis) kayit varsa hemen diske yaz - son saniyedeki coin/enerji
    // degisikligi kaybolmasin.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      GameProgress.instance.flush();
      CloudSaveService.instance.flushUpload();
      MusicService.instance.onPaused();
      EngageService.instance.touch();
      if (state == AppLifecycleState.paused) NotificationService.instance.scheduleAll();
      TimeService.instance.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      // Arka plandan donunce sunucu saatiyle yeniden senkron ol.
      TimeService.instance.syncWithServer();
      CloudSaveService.instance.onResumed();
      BillingService.instance.onResumed();
      if (LegalConsentService.instance.accepted) InboxService.instance.maybeSync(); // onaydan once kimlik/istek yok
      MusicService.instance.onResumed();
      EngageService.instance.onAppOpen();
      NotificationService.instance.cancelAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Merge Dünyaları',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Baloo2',
        colorSchemeSeed: Colors.deepOrange,
        scaffoldBackgroundColor: Colors.orange.shade50,
      ),
      // Her dokunusta muzigi (gerekirse) baslat - web'de autoplay engelini asar.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => MusicService.instance.kickstart(),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const SplashScreen(),
    );
  }
}
