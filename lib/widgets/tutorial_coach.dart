import 'dart:math';
import 'package:flutter/material.dart';

/// OGRETICI PARCALARI (hepsi kozmetik, oyun fizigine/mantigina dokunmaz).
///
/// Ilkeler (piyasa arastirmasindan): okutma, yaptir. Her adimda EN FAZLA
/// 4-5 kelime. Parlayan nesne + hareket eden el hedefi gosterir. Yalnizca
/// DOGRU hareket bir sonraki adima gecirir (karar game_board.dart'ta).
///
///  * [PulseGlow]     : herhangi bir widget'in etrafinda nabiz gibi parlama
///  * [CoachBubble]   : kisa metinli, hafif zipliyan balon (+ ok)
///  * [PulseRing]     : tahtadaki bir objenin etrafinda buyuyup sonen halka
///  * [CoachHand]     : el parmak animasyonu (A noktasindan B noktasina surukle + birak)
///  * [SpotlightHint] : menu ikonu vurgusu (parlama + yan etiket)

const Color kCoachOrange = Color(0xFFFF9A1F);
const Color kCoachGlow = Color(0xFFFFE27A);

/// [child]'in etrafinda yumusak, nabiz gibi atan bir parlama.
class PulseGlow extends StatefulWidget {
  final bool active;
  final Widget child;
  final bool circle;
  final double radius;
  final Color color;

  const PulseGlow({
    super.key,
    required this.active,
    required this.child,
    this.circle = false,
    this.radius = 14,
    this.color = kCoachGlow,
  });

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulseGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle ? null : BorderRadius.circular(widget.radius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.35 + 0.45 * t),
                blurRadius: 10 + 14 * t,
                spreadRadius: 1 + 4 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Yonu belirtilen ok isareti ([CoachBubble] ile birlikte kullanilir).
enum CoachArrow { none, up, down, left, right }

/// Kisa metin balonu. Hafifce yukari-asagi (ya da ok yonune dogru) ziplar.
/// [text] degisince "pop" animasyonuyla yeniden belirir.
class CoachBubble extends StatefulWidget {
  final String text;
  final CoachArrow arrow;
  final double fontSize;
  final double maxWidth;

  const CoachBubble({
    super.key,
    required this.text,
    this.arrow = CoachArrow.none,
    this.fontSize = 20,
    this.maxWidth = 280,
  });

  @override
  State<CoachBubble> createState() => _CoachBubbleState();
}

class _CoachBubbleState extends State<CoachBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 720))..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  Offset _bobOffset(double t) {
    final d = 5 * Curves.easeInOut.transform(t);
    switch (widget.arrow) {
      case CoachArrow.up:
        return Offset(0, -d);
      case CoachArrow.down:
        return Offset(0, d);
      case CoachArrow.left:
        return Offset(-d, 0);
      case CoachArrow.right:
        return Offset(d, 0);
      case CoachArrow.none:
        return Offset(0, -d * 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB444), Color(0xFFFF8A1F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Text(
        widget.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w900,
          height: 1.1,
          shadows: const [Shadow(color: Color(0xAA7A3A00), blurRadius: 2, offset: Offset(0, 1.5))],
        ),
      ),
    );

    const arrowColor = Colors.white;
    Widget body;
    switch (widget.arrow) {
      case CoachArrow.up:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.arrow_drop_up, size: 40, color: arrowColor, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
          Transform.translate(offset: const Offset(0, -10), child: pill),
        ]);
        break;
      case CoachArrow.down:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          pill,
          Transform.translate(
            offset: const Offset(0, -10),
            child: const Icon(Icons.arrow_drop_down, size: 40, color: arrowColor, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
          ),
        ]);
        break;
      case CoachArrow.left:
        body = Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.arrow_left, size: 40, color: arrowColor, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
          Transform.translate(offset: const Offset(-10, 0), child: pill),
        ]);
        break;
      case CoachArrow.right:
        body = Row(mainAxisSize: MainAxisSize.min, children: [
          Transform.translate(offset: const Offset(10, 0), child: pill),
          const Icon(Icons.arrow_right, size: 40, color: arrowColor, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
        ]);
        break;
      case CoachArrow.none:
        body = pill;
        break;
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.text),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: AnimatedBuilder(
        animation: _bob,
        child: body,
        builder: (context, child) => Transform.translate(offset: _bobOffset(_bob.value), child: child),
      ),
    );
  }
}

/// Tahtadaki bir objenin (merkez [center], capi [diameter]) etrafinda
/// buyuyup sonen halka + hafif parlama. Koordinatlar ust widget'in
/// (Stack) koordinatlaridir.
class PulseRing extends StatefulWidget {
  final Offset center;
  final double diameter;
  final Color color;

  const PulseRing({super.key, required this.center, required this.diameter, this.color = kCoachGlow});

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _RingPainter(
              t: _c.value,
              center: widget.center,
              diameter: widget.diameter,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  final Offset center;
  final double diameter;
  final Color color;

  _RingPainter({required this.t, required this.center, required this.diameter, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final base = diameter / 2;
    // Sabit yumusak parlama
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.55), color.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: base * 1.5));
    canvas.drawCircle(center, base * 1.5, glow);
    // Buyuyup sonen iki halka (yarim faz farkli)
    for (final phase in const [0.0, 0.5]) {
      final p = (t + phase) % 1.0;
      final r = base * (0.95 + 0.65 * p);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - p) + 1
        ..color = Colors.white.withOpacity(0.9 * (1 - p));
      canvas.drawCircle(center, r, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.t != t || old.center != center || old.diameter != diameter || old.color != color;
}

/// El/parmak: [from] noktasindan [to] noktasina SURUKLER, orada "birakma"
/// halkasi gosterir, solar ve basa doner. Sadece gorsel; IgnorePointer ile
/// sarili oldugu icin gercek dokunusu asla engellemez.
class CoachHand extends StatefulWidget {
  final Offset from;
  final Offset to;
  final bool visible;

  const CoachHand({super.key, required this.from, required this.to, this.visible = true});

  @override
  State<CoachHand> createState() => _CoachHandState();
}

class _CoachHandState extends State<CoachHand> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _ease(double x) => x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2).toDouble() / 2;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: widget.visible ? 1 : 0,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              // 0.00-0.12 belir | 0.12-0.62 surukle | 0.62-0.80 birak (halka) | 0.80-0.92 sol | 0.92-1 bekle
              double opacity;
              double move;
              double press = 0;
              if (t < 0.12) {
                opacity = t / 0.12;
                move = 0;
              } else if (t < 0.62) {
                opacity = 1;
                move = _ease((t - 0.12) / 0.50);
              } else if (t < 0.80) {
                opacity = 1;
                move = 1;
                press = (t - 0.62) / 0.18;
              } else if (t < 0.92) {
                opacity = 1 - (t - 0.80) / 0.12;
                move = 1;
                press = 1;
              } else {
                opacity = 0;
                move = 0;
              }
              final pos = Offset.lerp(widget.from, widget.to, move)!;
              final scale = 1.0 - (press > 0 && press < 0.5 ? press * 0.28 : 0.0);
              return Stack(
                children: [
                  if (press > 0 && press < 1)
                    Positioned(
                      left: pos.dx - (18 + press * 30),
                      top: pos.dy - (18 + press * 30),
                      child: Container(
                        width: 2 * (18 + press * 30),
                        height: 2 * (18 + press * 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity((1 - press) * 0.95), width: 3),
                        ),
                      ),
                    ),
                  Positioned(
                    left: pos.dx - 28,
                    top: pos.dy - 28,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0).toDouble(),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF140E08).withOpacity(0.55),
                            border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
                          ),
                          child: const Icon(Icons.touch_app, color: Colors.white, size: 34),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Menu ikonu vurgusu: [active] iken ikonun etrafi parlar ve yanina kisa bir
/// etiket cikar. Dokunulunca vurgunun kapanmasi cagiran tarafin isi
/// (tutSeen isaretlenir). Etiket dokunusu ENGELLEMEZ.
enum HintSide { left, right, top }

class SpotlightHint extends StatelessWidget {
  final bool active;
  final String label;
  final HintSide side;
  final Widget child;

  /// right/left: ikonun kenarindan yatay uzaklik; top: ikonun ustunden dikey uzaklik.
  final double offset;

  const SpotlightHint({
    super.key,
    required this.active,
    required this.label,
    required this.child,
    this.side = HintSide.right,
    this.offset = 70,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final Widget bubble;
    final Widget positioned;
    switch (side) {
      case HintSide.right:
        bubble = CoachBubble(text: label, arrow: CoachArrow.left, fontSize: 15, maxWidth: 150);
        positioned = Positioned(left: offset, top: 6, child: IgnorePointer(child: bubble));
        break;
      case HintSide.left:
        bubble = CoachBubble(text: label, arrow: CoachArrow.right, fontSize: 15, maxWidth: 150);
        positioned = Positioned(right: offset, top: 6, child: IgnorePointer(child: bubble));
        break;
      case HintSide.top:
        bubble = CoachBubble(text: label, arrow: CoachArrow.down, fontSize: 14, maxWidth: 150);
        positioned = Positioned(
          bottom: offset,
          left: -50,
          right: -50,
          child: IgnorePointer(child: Center(child: bubble)),
        );
        break;
    }
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        PulseGlow(active: true, circle: true, child: child),
        positioned,
      ],
    );
  }
}
