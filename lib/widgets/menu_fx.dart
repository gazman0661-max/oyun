import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game_theme.dart';

/// Ana menu arkaplani. Oyuncunun ILERLEDIGI DUNYAYA gore degisir:
/// - O dunya icin tam ekran gorsel hazirsa ([kMenuBackgroundImages]) onu kullanir
///   (ustune okunurluk icin koyulastirma + hafif yildiz tozu / suzulen objeler).
/// - Degilse dunyanin renginde animasyonlu gradyan kullanir.
/// Tamamen dekoratif - dokunuslari yutmaz.
/// Yeni dunya arkaplani eklenince sadece [kMenuBackgroundImages]'a ekle.
const Map<int, String> kMenuBackgroundImages = {
  0: 'assets/images/menu_background.jpg', // Fast Food mutfagi
  1: 'assets/images/bg/menu_w1.jpg', // Kafe
  2: 'assets/images/bg/menu_w2.jpg', // Buyu
  3: 'assets/images/bg/menu_w3.jpg', // Korsan
  4: 'assets/images/bg/menu_w4.jpg', // Buz
  5: 'assets/images/bg/menu_w5.jpg', // Uzay
};

/// Gorseli olmayan dunyalar icin [ust, orta, alt] gradyan renkleri.
const List<List<Color>> _kMenuGradients = [
  [Color(0xFF5A1A10), Color(0xFFB93A2E), Color(0xFFFF9A5A)], // Fast Food
  [Color(0xFF3E2415), Color(0xFF8B5A3C), Color(0xFFD9A066)], // Kafe
  [Color(0xFF2A0F5C), Color(0xFF51299B), Color(0xFF16788A)], // Buyu
  [Color(0xFF062C43), Color(0xFF0D6E8A), Color(0xFF4DB6AC)], // Korsan
  [Color(0xFF16335F), Color(0xFF3F72AF), Color(0xFF9BD8F5)], // Buz
  [Color(0xFF050520), Color(0xFF2B1B6B), Color(0xFF5C46B5)], // Uzay
];

class MenuBackground extends StatefulWidget {
  /// 0..5: oyuncunun aktif dunyasi.
  final int world;

  /// false ise dunya gorseli yerine gradyan kullanilir (acilis ekrani icin).
  final bool useImage;
  const MenuBackground({super.key, this.world = 2, this.useImage = true});

  @override
  State<MenuBackground> createState() => _MenuBackgroundState();
}

class _Floater {
  final String image;
  final double x;
  final double size;
  final double phase;
  final int speed;
  final double sway;
  final double rot;
  const _Floater({
    required this.image,
    required this.x,
    required this.size,
    required this.phase,
    required this.speed,
    required this.sway,
    required this.rot,
  });
}

class _MenuBackgroundState extends State<MenuBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late List<_Floater> _floaters;

  static const List<GameTheme> _themes = <GameTheme>[
    FastFoodTheme(),
    CafeTheme(),
    MagicTheme(),
    PirateTheme(),
    IceTheme(),
    SpaceTheme(),
  ];

  /// Aktif dunyanin objelerinden suzulen ikonlar (4..8. seviye karisik).
  List<_Floater> _buildFloaters() {
    final th = _themes[widget.world.clamp(0, _themes.length - 1).toInt()];
    final rnd = Random(11 + widget.world);
    return List.generate(10, (i) {
      final lvl = min(3 + rnd.nextInt(6), th.maxLevel);
      return _Floater(
        image: th.byLevel(lvl).imagePath,
        x: rnd.nextDouble(),
        size: 44 + rnd.nextDouble() * 40,
        phase: rnd.nextDouble(),
        speed: 1 + rnd.nextInt(2),
        sway: 10 + rnd.nextDouble() * 16,
        rot: (rnd.nextDouble() - 0.5) * 0.7,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
    _floaters = _buildFloaters();
  }

  @override
  void didUpdateWidget(covariant MenuBackground old) {
    super.didUpdateWidget(old);
    if (old.world != widget.world) _floaters = _buildFloaters();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final world = widget.world.clamp(0, _kMenuGradients.length - 1).toInt();
    final imagePath = widget.useImage ? kMenuBackgroundImages[world] : null;
    final g = _kMenuGradients[world];
    final hasImage = imagePath != null;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Image.asset(imagePath, fit: BoxFit.cover, alignment: Alignment.bottomCenter)
          else ...[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: g,
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.1),
                  radius: 0.95,
                  colors: [Color(0x66FFB74D), Color(0x00FFB74D)],
                ),
              ),
            ),
          ],
          LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _SparklePainter(_c.value))),
                    for (final f in _floaters)
                      Builder(builder: (context) {
                        final p = (_c.value * f.speed + f.phase) % 1.0;
                        final top = h - p * (h + f.size);
                        final left = f.x * (w - f.size) + sin(p * 2 * pi * 2 + f.phase * 6) * f.sway;
                        return Positioned(
                          left: left,
                          top: top,
                          child: Transform.rotate(
                            angle: f.rot + sin(p * 2 * pi) * 0.15,
                            child: Opacity(
                              opacity: hasImage ? 0.2 : 0.26,
                              child: Image.asset(f.image, width: f.size, height: f.size, cacheWidth: 128),
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            );
          }),
          // Okunurluk: ustte baslik, altta dock butonlari icin koyulastirma.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: hasImage
                    ? const [Color(0xAA000000), Color(0x22000000), Color(0x11000000), Color(0x99000000)]
                    : const [Color(0x00000000), Color(0x00000000), Color(0x66000000)],
                stops: hasImage ? const [0.0, 0.3, 0.6, 1.0] : const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final double t;
  _SparklePainter(this.t);

  static final List<List<double>> _pts = () {
    final r = Random(5);
    return List.generate(38, (_) => [r.nextDouble(), r.nextDouble(), 1.0 + r.nextDouble() * 2.2, r.nextDouble() * 6.28]);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in _pts) {
      final tw = 0.5 + 0.5 * sin(t * 2 * pi * 6 + p[3]);
      paint.color = Colors.white.withOpacity(0.10 + 0.55 * tw);
      canvas.drawCircle(Offset(p[0] * size.width, p[1] * size.height), p[2] * (0.6 + 0.6 * tw), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.t != t;
}

/// Yavasca donen isin demeti (kahramanin arkasinda).
class SunburstRays extends StatefulWidget {
  final double size;
  const SunburstRays({super.key, this.size = 240});

  @override
  State<SunburstRays> createState() => _SunburstRaysState();
}

class _SunburstRaysState extends State<SunburstRays> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 28))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.rotate(angle: _c.value * 2 * pi, child: child),
      child: CustomPaint(size: Size.square(widget.size), painter: _RaysPainter()),
    );
  }
}

class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withOpacity(0.55), Colors.white.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a0 = i * 2 * pi / n;
      final a1 = a0 + pi / n * 0.8;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * cos(a0), c.dy + r * sin(a0))
        ..lineTo(c.dx + r * cos(a1), c.dy + r * sin(a1))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Cocugunu yavasca yukari-asagi salindiran (nefes alir gibi) sarmalayici.
class Bobbing extends StatefulWidget {
  final Widget child;
  final double amplitude;
  final Duration duration;
  const Bobbing({
    super.key,
    required this.child,
    this.amplitude = 6,
    this.duration = const Duration(milliseconds: 2200),
  });

  @override
  State<Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<Bobbing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -widget.amplitude * v),
          child: Transform.scale(scale: 1.0 + 0.02 * v, child: child),
        );
      },
      child: widget.child,
    );
  }
}
