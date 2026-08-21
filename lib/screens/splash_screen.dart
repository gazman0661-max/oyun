import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/cloud_progress_sync.dart';
import '../services/gdpr_service.dart';
import '../services/localization.dart';
import '../services/network_time_service.dart';
import '../services/notification_service.dart';
import '../services/planet_images.dart';
import '../services/play_games_service.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'language_select_screen.dart';

/// HTML prototipindeki #splash-screen ile ayni fikir: roket + baslik +
/// slogan + ilerleme cubugu. Yukleme (PlayerProgress.load()) bitince VEYA
/// ~2 saniye sonra (hangisi once gelirse) ana ekrana geciyor; ekrana
/// dokununca da hemen atlanabiliyor.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flameController;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    )..repeat(reverse: true);
    // DUZELTME (v10): Ses/reklam SDK'si kurulumu ARTIK ana gecis akisini
    // (_boot -> _goHome) hicbir sekilde BEKLEMIYOR / BLOKLAMIYOR. Ikisi de
    // bagimsiz olarak, paralel calisiyor. Boylece reklam SDK'si yavas/
    // sorunlu olsa bile oyuncu splash'te fazladan beklemez, direkt ana
    // menuye gecer; reklamlar arka planda kendi hazirlanir.
    unawaited(_bootAudioAndAds());
    _boot();
  }

  /// Ses sistemini kurar ve (varsa) reklam SDK'sini baslatir. Bu islemler
  /// navigasyonu ETKILEMEZ — main.dart artik runApp()'i hicbir sey
  /// beklemeden en basta cagiriyor (native acilis ikonu aninda kayboluyor),
  /// bu metod ise Flutter arayuzu ZATEN EKRANDAYKEN arka planda calisir.
  Future<void> _bootAudioAndAds() async {
    try {
      await SoundService.instance.init().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
    } catch (_) {
      // Ses sistemi kurulamasa bile oyun etkilenmesin.
    }
    // Yerel bildirim sistemi (Kozmik Ikmal hazir / gunluk seri
    // hatirlatmasi) de navigasyonu bloklamayan arka plan kurulumlarindan
    // biri. Basarisiz olursa oyun bildirimsiz calismaya devam eder.
    try {
      await NotificationService.instance.init().timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
    } catch (_) {}
    // Appodeal Mobile Ads SDK sadece Android/iOS icindir. Web'de (orn.
    // FlutLab "preview" veya "flutter run -d chrome") native eklenti
    // bulunamadigi icin bu cagri hata firlatir; try/catch ile sarmalaniyor.
    if (!kIsWeb) {
      try {
        // AdService.initializeSdk(): Appodeal SDK'sini kurar VE (AB/AEA/
        // Isvicre/UK/CCPA bolgesindeyse) Appodeal'in KENDI resmi/otomatik
        // onay ekranini (Google UMP tabanli Stack Consent Manager)
        // tetikler — bkz. ad_service.dart.
        await AdService.instance.initializeSdk().timeout(
              const Duration(seconds: 8),
              onTimeout: () {},
            );
        // Kullanim Sartlari onayi / bolge tespiti (Appodeal'den bagimsiz,
        // kendi yerel Terms/Privacy akisimiz icin) — GDPR popup'i ana
        // ekranda (henuz onaylanmadiysa) ayrica gosterilir.
        await GdprService.instance.load().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
        // Ilk odullu + ilk gecis (interstitial) reklam isteginin
        // beklemeden gosterilebilmesi icin arka planda onceden yuklemeyi
        // baslat (hata olursa sessizce yutulur; AdService.preload() /
        // preloadInterstitial() zaten kendi icinde tekrar deniyor).
        unawaited(AdService.instance.preload());
        unawaited(AdService.instance.preloadInterstitial());
      } catch (_) {
        // Reklam SDK'si baslatilamasa bile oyun asla etkilenmesin.
      }
      // Firebase Analytics — Appodeal panelinde gorunmeyen yeni/eski
      // kullanici ve reklam izleme detaylarini Firebase Console'a
      // gonderir. Diger tum kurulumlar gibi navigasyonu BLOKLAMAZ ve
      // google-services.json eksikse (henuz eklenmediyse) sessizce
      // atlanir, oyun Analytics olmadan normal calismaya devam eder.
      try {
        await AnalyticsService.instance.init().timeout(
              const Duration(seconds: 5),
              onTimeout: () {},
            );
      } catch (_) {}
    }
  }

  Future<void> _boot() async {
    final loadFuture = PlayerProgress.instance.load();
    final localeFuture = AppLocale.instance.load();
    final planetsFuture = PlanetImages.preload();
    // Haftalik gorev sinirlarinin (bkz. NetworkTimeService) diskteki en
    // son bilinen offset ile hazir olmasi icin — gercek NTP sorgusu
    // kendi icinde arka planda devam eder, burasi BEKLEMEZ/BLOKLAMAZ.
    final ntpFuture = NetworkTimeService.instance.init();
    await Future.wait([
      loadFuture,
      localeFuture,
      planetsFuture,
      ntpFuture,
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    // Yerel ilerleme yuklendikten SONRA Play Games'e sessizce baglanmayi
    // dene; basariliysa buluttaki (varsa) daha ileri kaydi uygula.
    await PlayGamesService.instance.signInSilently();
    if (PlayGamesService.instance.isSignedIn) {
      await CloudProgressSync.instance.syncAfterSignIn();
    }
    // Gunluk seri hatirlatmasini, ilerleme yuklendikten hemen sonra
    // (bugun oynanip oynanmadigi artik bilindigi icin) yeniden kur.
    // NotificationService kendi init'ini gerekirse burada tamamlar,
    // navigasyonu (_goHome) BEKLEMEDEN arka planda calisir.
    unawaited(NotificationService.instance.refreshDailyStreakReminder(
      playedToday: PlayerProgress.instance.dailyCompletedToday,
    ));
    // Uygulama acildi: "3 gundur ugramadin" geri cagirma bildirimini de
    // simdiden 3 gun ileriye ertele.
    unawaited(NotificationService.instance.refreshComebackReminder());
    // Kuyruklu Yıldız / haftalık / aylık görev bildirimlerini de acilista
    // guncel ilerlemeyle kur (bkz. PlayerProgress.
    // refreshPeriodicEventNotifications).
    unawaited(PlayerProgress.instance.refreshPeriodicEventNotifications());
    _goHome();
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final needsLanguage = !AppLocale.instance.hasChosenLanguage;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => needsLanguage
            ? const LanguageSelectScreen()
            : const HomeScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _flameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.spaceTop,
      body: GestureDetector(
        onTap: _goHome,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _flameController,
                  builder: (context, _) {
                    final flicker = 0.85 + _flameController.value * 0.3;
                    return CustomPaint(
                      size: const Size(76, 114),
                      painter: _RocketPainter(flameScale: flicker),
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  '🚀 AstroFelyx',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('splashTagline'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: const LinearProgressIndicator(
                      backgroundColor: AppColors.surfaceBorder,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// HTML splash'indeki roket SVG'siyle ayni siluet: 4 renkli bolme + alev.
class _RocketPainter extends CustomPainter {
  final double flameScale;
  _RocketPainter({required this.flameScale});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sx = w / 80.0, sy = h / 120.0;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final hull = Path()
      ..moveTo(p(40, 6).dx, p(40, 6).dy)
      ..cubicTo(p(54, 20).dx, p(54, 20).dy, p(58, 42).dx, p(58, 42).dy,
          p(58, 66).dx, p(58, 66).dy)
      ..lineTo(p(58, 86).dx, p(58, 86).dy)
      ..cubicTo(p(58, 90).dx, p(58, 90).dy, p(54, 92).dx, p(54, 92).dy,
          p(50, 92).dx, p(50, 92).dy)
      ..lineTo(p(30, 92).dx, p(30, 92).dy)
      ..cubicTo(p(26, 92).dx, p(26, 92).dy, p(22, 90).dx, p(22, 90).dy,
          p(22, 86).dx, p(22, 86).dy)
      ..lineTo(p(22, 66).dx, p(22, 66).dy)
      ..cubicTo(p(22, 42).dx, p(22, 42).dy, p(26, 20).dx, p(26, 20).dy,
          p(40, 6).dx, p(40, 6).dy)
      ..close();

    canvas.drawPath(
      hull,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_shade(0x2A3560, 20), const Color(0xFF151C36)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      hull,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFCBD5E1),
    );

    void band(double y1, double y2, Color color) {
      final rect = Rect.fromLTRB(p(26, y1).dx, p(26, y1).dy, p(54, y2).dx, p(54, y2).dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(4 * sx)),
        Paint()..color = color,
      );
    }

    band(70, 88, AppColors.accent);
    band(52, 68, AppColors.accentSoft);
    band(34, 50, AppColors.warning);

    canvas.drawCircle(p(40, 24), 9 * sx, Paint()..color = const Color(0xFF0A0E1F));
    canvas.drawCircle(p(40, 24), 4 * sx, Paint()..color = AppColors.accentSoft.withValues(alpha: 0.9));

    final finPaint = Paint()..color = AppColors.danger;
    canvas.drawPath(
      Path()
        ..moveTo(p(22, 66).dx, p(22, 66).dy)
        ..lineTo(p(8, 90).dx, p(8, 90).dy)
        ..lineTo(p(22, 84).dx, p(22, 84).dy)
        ..close(),
      finPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(58, 66).dx, p(58, 66).dy)
        ..lineTo(p(72, 90).dx, p(72, 90).dy)
        ..lineTo(p(58, 84).dx, p(58, 84).dy)
        ..close(),
      finPaint,
    );

    // Alev (flicker animasyonlu): roketin altindaki sabit noktadan
    // (40, 92) asagi dogru dikey olarek olceklenir.
    final flameAnchor = p(40, 92);
    canvas.save();
    canvas.translate(flameAnchor.dx, flameAnchor.dy);
    canvas.scale(1, flameScale);
    canvas.translate(-flameAnchor.dx, -flameAnchor.dy);
    canvas.drawPath(
      Path()
        ..moveTo(p(30, 92).dx, p(30, 92).dy)
        ..lineTo(p(40, 118).dx, p(40, 118).dy)
        ..lineTo(p(50, 92).dx, p(50, 92).dy)
        ..close(),
      Paint()..color = AppColors.warning.withValues(alpha: 0.9),
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(34, 92).dx, p(34, 92).dy)
        ..lineTo(p(40, 108).dx, p(40, 108).dy)
        ..lineTo(p(46, 92).dx, p(46, 92).dy)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  Color _shade(int hex, int amt) {
    final c = Color(0xFF000000 | hex);
    int ch(int v) => (v + amt).clamp(0, 255).toInt();
    return Color.fromARGB(
      255,
      ch((c.r * 255.0).round().clamp(0, 255)),
      ch((c.g * 255.0).round().clamp(0, 255)),
      ch((c.b * 255.0).round().clamp(0, 255)),
    );
  }

  @override
  bool shouldRepaint(covariant _RocketPainter oldDelegate) =>
      oldDelegate.flameScale != flameScale;
}
