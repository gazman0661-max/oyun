import 'dart:math';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_theme.dart';
import '../widgets/menu_fx.dart';
import 'main_menu_screen.dart';
import '../services/legal_consent_service.dart';
import '../widgets/legal_gate_dialog.dart';

/// ACILIS (SPLASH) EKRANI: kumbara ejderha maskot + 6 dunyanin objesi ucusan bir
/// halka + "MERGE WORLDS" basligi + yukleme cubugu. ~3 sn sonra (ya da
/// dokununca) ana menuye yumusakca gecer. Oyun adi her dilde Ingilizce.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  bool _left = false;

  static const List<GameTheme> _themes = <GameTheme>[
    FastFoodTheme(),
    CafeTheme(),
    MagicTheme(),
    PirateTheme(),
    IceTheme(),
    SpaceTheme(),
  ];

  @override
  void initState() {
    super.initState();
    _intro.forward().whenComplete(_go);
  }

  @override
  void dispose() {
    _intro.dispose();
    _orbit.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_left || !mounted) return;
    _left = true;
    // Ilk acilis: Sartlar + Gizlilik (+ AB icin GDPR) onayi. Onay yoksa devam yok.
    if (!LegalConsentService.instance.accepted) {
      await LegalGateDialog.show(context);
      if (!mounted) return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const MainMenuScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  double _seg(double t, double from, double len) => ((t - from) / len).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final isTr = AppStrings.instance.language == AppLanguage.tr;
    return Scaffold(
      backgroundColor: const Color(0xFF2A0F5C),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_intro.value > 0.4) _go();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const MenuBackground(world: 2, useImage: false),
            LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              final h = box.maxHeight;
              final cx = w / 2;
              final cy = h * 0.37;
              final rx = min(w * 0.40, 170.0);
              final ry = rx * 0.34;
              return AnimatedBuilder(
                animation: Listenable.merge([_intro, _orbit]),
                builder: (context, _) {
                  final t = _intro.value;
                  final spin = _orbit.value * 2 * pi;
                  final dragonP = Curves.elasticOut.transform(_seg(t, 0.0, 0.3));
                  final titleP = _seg(t, 0.28, 0.3);
                  final titleScale = Curves.elasticOut.transform(titleP);
                  final barP = Curves.easeInOut.transform(_seg(t, 0.12, 0.84));

                  // 6 obje halkada; arkadakiler ejderhanin ARKASINDA, onde olanlar ONUNDE.
                  final back = <Widget>[];
                  final front = <Widget>[];
                  for (var i = 0; i < _themes.length; i++) {
                    final a = spin + i * 2 * pi / _themes.length;
                    final depth = sin(a); // -1 arka ... +1 on
                    final pop = Curves.elasticOut.transform(_seg(t, 0.06 + i * 0.045, 0.28));
                    final sz = (54 + 14 * depth) * pop;
                    final x = cx + rx * cos(a);
                    final y = cy + 40 + ry * depth;
                    final th = _themes[i];
                    final child = Positioned(
                      left: x - sz / 2,
                      top: y - sz / 2,
                      child: Opacity(
                        opacity: (0.65 + 0.35 * (depth + 1) / 2).clamp(0.0, 1.0).toDouble(),
                        child: Image.asset(th.byLevel(th.maxLevel).imagePath, width: max(0.0, sz), height: max(0.0, sz)),
                      ),
                    );
                    (depth < 0 ? back : front).add(child);
                  }

                  return Stack(
                    children: [
                      // Donen isin demeti
                      Positioned(
                        left: cx - 280,
                        top: cy - 280,
                        child: Opacity(opacity: 0.55 * dragonP.clamp(0.0, 1.0).toDouble(), child: const SunburstRays(size: 560)),
                      ),
                      ...back,
                      // Maskot
                      Positioned(
                        left: cx - 125,
                        top: cy - 125,
                        width: 250,
                        height: 250,
                        child: Transform.scale(
                          scale: dragonP,
                          child: Bobbing(
                            amplitude: 7,
                            duration: const Duration(milliseconds: 1900),
                            child: Image.asset('assets/images/ui/dragon_2.webp', fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      ...front,
                      // Baslik
                      Positioned(
                        left: 0,
                        right: 0,
                        top: h * 0.60,
                        child: Opacity(
                          opacity: titleP,
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * titleScale,
                            child: Column(
                              children: [
                                _OutlinedText('MERGE', 74),
                                Transform.translate(offset: const Offset(0, -14), child: _OutlinedText('WORLDS', 74)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Yukleme cubugu
                      Positioned(
                        left: 56,
                        right: 56,
                        bottom: 54 + MediaQuery.of(context).padding.bottom,
                        child: Column(
                          children: [
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                              ),
                              padding: const EdgeInsets.all(2),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: barP,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF9CF25B), Color(0xFF3CC13A)]),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isTr ? 'Yükleniyor...' : 'Loading...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.5,
                                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Altin-turuncu gradyan dolgulu, koyu konturlu ve golgeli buyuk baslik yazisi.
class _OutlinedText extends StatelessWidget {
  final String text;
  final double size;
  const _OutlinedText(this.text, this.size);

  @override
  Widget build(BuildContext context) {
    final stroke = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      height: 1.0,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.17
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF2B0E5E),
      shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 14, offset: const Offset(0, 8))],
    );
    final fill = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      height: 1.0,
      foreground: Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF59D), Color(0xFFFFB300), Color(0xFFFF7A00)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size * 5, size)),
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(text, style: stroke),
          Text(text, style: fill),
        ],
      ),
    );
  }
}
