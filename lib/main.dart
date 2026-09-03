import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/player_progress.dart';
import 'services/sound_service.dart';
import 'theme/app_colors.dart';

/// DUZELTME (v10): Onceki surumde (v7) main()'deki adimlara timeout
/// eklenmisti, ama YINE DE runApp() cagrilmadan ONCE calisiyorlardi — yani
/// native acilis ikonu, bu adimlar bitene (ya da timeout'a) kadar (en kotu
/// ihtimalle ~11 saniye) ekranda kaliyordu. Daha da onemlisi: eger reklam
/// SDK'si (Appodeal) kendi ACTIGI bir arka plan thread'inde (native tarafta)
/// bir hataya dusuyorsa, bu Dart'taki try/catch tarafindan YAKALANAMAZ —
/// butun uygulama sessizce cokup Android tarafindan yeniden baslatilir, bu
/// da kullaniciya "splash ekraninda sonsuza kadar takili kaliyor" gibi
/// gorunur (aslinda cok kisa surelerle cokup yeniden baslıyordur).
///
/// COZUM: runApp() ARTIK HICBIR SEYI BEKLEMEDEN, EN BASTA cagriliyor. Native
/// acilis ikonu bu sayede ANINDA kayboluyor ve kendi roketli splash
/// ekranimiz (lib/screens/splash_screen.dart) hemen goruluyor. Ses/reklam
/// SDK'si kurulumu ise Flutter arayuzu ZATEN EKRANDAYKEN, SplashScreen'in
/// kendi _boot() metodunda arka planda yapiliyor (bkz. splash_screen.dart).
/// Boylece:
///  1) Native ikon ASLA birkac yuz milisaniyeden fazla ekranda kalmaz.
///  2) Reklam SDK'si gercekten sorunluysa/cokuyorsa bile once oyunun kendi
///     arayuzu goruldugu icin sorun ac,kca "reklamlarda" olarak ayirt edilir.
///  3) runZonedGuarded, Dart tarafinda yakalanmamis (uncaught) herhangi bir
///     hatayi/Future rejection'ini yutup logluyor — boylece beklenmedik tek
///     bir hata butun uygulamayi asagi cekmiyor.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // DUZELTME (beyaz ekran/status-bar bugı): daha once hicbir yerde
    // sistem durum cubugu / navigasyon cubugu rengi sabitlenmiyordu. Tam
    // ekran bir overlay actiginda (orn. CoachOverlay ogretici balonu)
    // Android bazi cihazlarda/surumlerde sistem cubuklarini VARSAYILAN
    // (genelde ACIK/beyaza yakin) renge donduruyor, bu da oyuncuya "ekran
    // beyaz oldu" gibi gorunuyor. Burada uygulama boyunca sabit, koyu ve
    // seffaf bir stil zorlaniyor ki uzay temasiyla hicbir zaman celismesin.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.spaceTop,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
    runApp(const CosmicSortApp());
  }, (error, stack) {
    debugPrint('[main] Yakalanmamis hata: $error\n$stack');
  });
}

class CosmicSortApp extends StatefulWidget {
  const CosmicSortApp({super.key});

  @override
  State<CosmicSortApp> createState() => _CosmicSortAppState();
}

/// Uygulamanin acik/kapali (foreground/background) durumunu dinler:
/// ekran kapandiginda / baska bir uygulamaya gecildiginde arka plan
/// muzigini durdurur, geri donuldugunde kaldigi yerden devam ettirir.
class _CosmicSortAppState extends State<CosmicSortApp>
    with WidgetsBindingObserver {
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
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Ekran kapandi / uygulama arka plana atildi.
        SoundService.instance.pauseBgm();
        break;
      case AppLifecycleState.resumed:
        // Ekran tekrar acildi / uygulama on plana geldi.
        SoundService.instance.resumeBgm();
        // Uygulama arka planda kalirken saat 13:00 esigini gecmis olabilir
        // (ya da gunluk bulmaca baska bir cihazdan tamamlanmis olabilir);
        // hatirlatmayi guncel bilgiyle yeniden hesapla.
        unawaited(NotificationService.instance.refreshDailyStreakReminder(
          playedToday: PlayerProgress.instance.dailyCompletedToday,
        ));
        // Uygulama tekrar acildi: "3 gundur ugramadin" bildirimini
        // simdiden 3 gun ileriye ertele (oyuncu duzenli aciyorsa bu
        // bildirim boylece hicbir zaman tetiklenmez).
        unawaited(NotificationService.instance.refreshComebackReminder());
        // Kuyruklu Yıldız / haftalık / aylık görev bildirimlerini de
        // guncel ilerlemeyle yeniden hesapla (bkz. PlayerProgress.
        // refreshPeriodicEventNotifications) — hedef bu arada baska bir
        // cihazdan tutturulmus olabilir.
        unawaited(PlayerProgress.instance.refreshPeriodicEventNotifications());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.spaceTop,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: MaterialApp(
        title: 'AstroFelyx: Galaxy Puzzle',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.spaceTop,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.accent,
            brightness: Brightness.dark,
          ),
          fontFamily: 'Roboto',
        ),
        // ONEMLI: Flutter varsayilan olarak Text widget'larini kullanicinin
        // telefon/tablet ayarlarindaki "yazi tipi boyutu" (erisilebilirlik)
        // tercihine gore otomatik buyutup kucultur. HTML surumundeki gibi
        // TAMAMEN SABIT (px kilitli) bir gorunum istendigi icin, burada
        // sistem yazi olcegini "1.0"a (hicbir buyutme/kucultme yok) kilitliyoruz.
        // Boylece oyun, kullanicinin cihazindaki yazi tipi ayari ne olursa
        // olsun HER ZAMAN ayni gorsel boyutta, taşma riski olmadan calisir.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
