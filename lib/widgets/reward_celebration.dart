import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/haptic_service.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';

/// Oyun sonu / odul ekranlari icin gorsel sov parcalari.
///
/// Hicbir ek paket gerektirmez (confetti / lottie yok): havai fisek ve
/// konfeti tamamen CustomPainter + Ticker ile cizilir. Parcacik sayisi
/// sinirli oldugu icin dusuk seviyeli cihazlarda da akici calisir.
/// Tum parcalar, ekrandan cikinca controller/ticker'larini kendisi
/// serbest birakir.

// -----------------------------------------------------------------------
// 1) Havai fisek + konfeti
// -----------------------------------------------------------------------

enum CelebrationLevel {
  /// Hicbir sey cizilmez.
  none,

  /// Sadece hafif altin konfeti (rekor olmayan, odullu oyun sonu).
  soft,

  /// Havai fisek patlamalari + yogun konfeti (rekor / galibiyet).
  full,
}

class _Particle {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  final double size;
  double rot;
  final double vrot;
  final double swayPhase;
  final Color color;
  final bool confetti;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.maxLife,
    required this.size,
    required this.rot,
    required this.vrot,
    required this.swayPhase,
    required this.color,
    required this.confetti,
  }) : life = maxLife;
}

class CelebrationFx extends StatefulWidget {
  final CelebrationLevel level;

  /// Her havai fisek patlamasinda "pop" sesi calinsin mi.
  final bool sound;

  /// Efekt kac saniye boyunca yeni parcacik uretsin.
  final double spawnSeconds;

  const CelebrationFx({
    super.key,
    this.level = CelebrationLevel.full,
    this.sound = true,
    this.spawnSeconds = 3.2,
  });

  @override
  State<CelebrationFx> createState() => _CelebrationFxState();
}

class _CelebrationFxState extends State<CelebrationFx>
    with SingleTickerProviderStateMixin {
  static const _palette = <Color>[
    Color(0xFFFFD54F), // altin
    Color(0xFFFFB020), // meteor turuncusu
    Color(0xFFFF5CC8), // nebula pembesi
    Color(0xFF5CC8FF), // aksan mavisi
    Color(0xFF8CFFEA), // turkuaz
    Color(0xFFB388FF), // mor
  ];
  static const int _maxParticles = 240;

  late final Ticker _ticker;
  final Random _rng = Random();
  final List<_Particle> _parts = <_Particle>[];
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Duration _last = Duration.zero;
  double _t = 0;
  double _nextBurst = 0.3;
  double _confettiCarry = 0;
  int _bursts = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.level != CelebrationLevel.none) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  Color _pick() => _palette[_rng.nextInt(_palette.length)];

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    _t += dt;

    final w = _size.width;
    final h = _size.height;
    final spawning = _t < widget.spawnSeconds && w > 0 && h > 0;

    if (spawning) {
      final full = widget.level == CelebrationLevel.full;
      // Havai fisek patlamalari
      if (full && _t >= _nextBurst && _bursts < 7) {
        _spawnFirework(w, h);
        _bursts++;
        _nextBurst = _t + 0.35 + _rng.nextDouble() * 0.35;
      }
      // Konfeti yagmuru
      final rate = full ? 38.0 : 12.0;
      _confettiCarry += rate * dt;
      while (_confettiCarry >= 1) {
        _confettiCarry -= 1;
        if (_parts.length < _maxParticles) _spawnConfetti(w);
      }
    }

    final drag = exp(-1.5 * dt);
    for (final p in _parts) {
      p.life -= dt;
      if (p.confetti) {
        p.x += (p.vx + sin(_t * 3 + p.swayPhase) * 28) * dt;
        p.y += p.vy * dt;
        p.rot += p.vrot * dt;
      } else {
        p.vx *= drag;
        p.vy = p.vy * drag + 150 * dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
      }
    }
    _parts.removeWhere((p) => p.life <= 0 || p.y > h + 30);

    _repaint.value++;

    if (_t >= widget.spawnSeconds && _parts.isEmpty) {
      _ticker.stop();
    }
  }

  void _spawnFirework(double w, double h) {
    final cx = w * (0.15 + _rng.nextDouble() * 0.7);
    final cy = h * (0.10 + _rng.nextDouble() * 0.38);
    final base = _pick();
    final alt = _pick();
    const count = 26;
    for (var i = 0; i < count; i++) {
      final a = (i / count) * pi * 2 + _rng.nextDouble() * 0.2;
      final sp = 110 + _rng.nextDouble() * 190;
      if (_parts.length >= _maxParticles) break;
      _parts.add(_Particle(
        x: cx,
        y: cy,
        vx: cos(a) * sp,
        vy: sin(a) * sp,
        maxLife: 0.9 + _rng.nextDouble() * 0.7,
        size: 2.0 + _rng.nextDouble() * 1.4,
        rot: 0,
        vrot: 0,
        swayPhase: 0,
        color: i.isEven ? base : alt,
        confetti: false,
      ));
    }
    if (widget.sound) SoundService.instance.fireworkPop();
  }

  void _spawnConfetti(double w) {
    final life = 4.0 + _rng.nextDouble() * 2.0;
    _parts.add(_Particle(
      x: _rng.nextDouble() * w,
      y: -12,
      vx: (_rng.nextDouble() - 0.5) * 50,
      vy: 90 + _rng.nextDouble() * 120,
      maxLife: life,
      size: 5 + _rng.nextDouble() * 5,
      rot: _rng.nextDouble() * pi,
      vrot: (_rng.nextDouble() - 0.5) * 9,
      swayPhase: _rng.nextDouble() * pi * 2,
      color: _pick(),
      confetti: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.level == CelebrationLevel.none) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          _size = Size(c.maxWidth, c.maxHeight);
          return RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _FxPainter(_parts, _repaint),
            ),
          );
        },
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  final List<_Particle> parts;
  _FxPainter(this.parts, Listenable repaint) : super(repaint: repaint);

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      final f = (p.life / p.maxLife).clamp(0.0, 1.0);
      if (p.confetti) {
        // Ust ve alt kenarda yumusak solma.
        final a = (f < 0.15 ? f / 0.15 : 1.0);
        _paint
          ..style = PaintingStyle.fill
          ..color = p.color.withValues(alpha: a);
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.rot);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 1.7),
            const Radius.circular(1.5),
          ),
          _paint,
        );
        canvas.restore();
      } else {
        final a = f;
        // Parlama
        _paint
          ..style = PaintingStyle.fill
          ..color = p.color.withValues(alpha: a * 0.25);
        canvas.drawCircle(Offset(p.x, p.y), p.size * 2.2, _paint);
        // Iz (kisa cizgi)
        _paint
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = p.size
          ..color = p.color.withValues(alpha: a);
        canvas.drawLine(
          Offset(p.x, p.y),
          Offset(p.x - p.vx * 0.035, p.y - p.vy * 0.035),
          _paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) => false;
}

// -----------------------------------------------------------------------
// 2) Sayarak artan sayi
// -----------------------------------------------------------------------

/// 0'dan (veya onceki degerden) [value]'ya hizla sayan, sayarken hafifce
/// "nabiz atan" yazi. [value] sonradan degisirse (ornegin XP x2) kaldigi
/// yerden yeni degere sayar.
class AnimatedCount extends StatefulWidget {
  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final Duration duration;
  final Duration delay;
  final VoidCallback? onDone;

  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 1200),
    this.delay = Duration.zero,
    this.onDone,
  });

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _from = 0;
  double _to = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });
    _to = widget.value.toDouble();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      _started = true;
      _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedCount old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _started) {
      _from = _current();
      _to = widget.value.toDouble();
      _c.forward(from: 0);
    } else if (old.value != widget.value) {
      _to = widget.value.toDouble();
    }
  }

  double _current() {
    final t = Curves.easeOutCubic.transform(_c.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final shown = _started ? _current().round() : _from.round();
        final pulse = 1 + 0.08 * sin(pi * _c.value);
        return Transform.scale(
          scale: pulse,
          child: Text(
            '${widget.prefix}$shown${widget.suffix}',
            style: widget.style,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------
// 3) Gecikmeli "pat" diye beliren animasyon
// -----------------------------------------------------------------------

class PopIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final VoidCallback? onShown;

  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.onShown,
  });

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      widget.onShown?.call();
      _c.forward();
    });
  }

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
        final s = Curves.elasticOut.transform(_c.value);
        final o = Curves.easeOut.transform((_c.value * 2.5).clamp(0.0, 1.0));
        return Opacity(
          opacity: o,
          child: Transform.scale(scale: s, child: child),
        );
      },
      child: widget.child,
    );
  }
}

// -----------------------------------------------------------------------
// 4) Donen isik huzmeleri (odulun arkasinda)
// -----------------------------------------------------------------------

class RewardRays extends StatefulWidget {
  final double size;
  final Color color;
  const RewardRays({
    super.key,
    this.size = 260,
    this.color = const Color(0xFFFFD54F),
  });

  @override
  State<RewardRays> createState() => _RewardRaysState();
}

class _RewardRaysState extends State<RewardRays>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _RaysPainter(_c.value * pi * 2, widget.color),
            ),
          ),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  final double angle;
  final Color color;
  _RaysPainter(this.angle, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: 0.38),
        color.withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCircle(center: c, radius: r));
    final paint = Paint()..shader = shader;
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = angle + i * (pi * 2 / rays);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a - 0.09) * r, c.dy + sin(a - 0.09) * r)
        ..lineTo(c.dx + cos(a + 0.09) * r, c.dy + sin(a + 0.09) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.angle != angle;
}

// -----------------------------------------------------------------------
// 5) Seviye ilerleme cubugu (XP)
// -----------------------------------------------------------------------

/// Konum = (seviye - 1) + seviye ici ilerleme. Ornegin 3.40 => Seviye 4'un
/// %40'i. [fromPos]'tan [toPos]'a animasyonla dolar; seviye atlanirsa cubuk
/// dolup basa sarar, "Seviye atladin!" yazisi ve ses/titresim tetiklenir.
/// [toPos] sonradan degisirse (XP x2) kaldigi yerden devam eder.
class XpLevelBar extends StatefulWidget {
  final double fromPos;
  final double toPos;
  final Duration delay;

  const XpLevelBar({
    super.key,
    required this.fromPos,
    required this.toPos,
    this.delay = Duration.zero,
  });

  @override
  State<XpLevelBar> createState() => _XpLevelBarState();
}

class _XpLevelBarState extends State<XpLevelBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late double _from;
  late double _to;
  late int _lastLevel;
  bool _started = false;
  bool _leveledUp = false;

  @override
  void initState() {
    super.initState();
    _from = widget.fromPos;
    _to = widget.toPos;
    _lastLevel = _from.floor();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..addListener(_onTick);
    Future<void>.delayed(widget.delay, () {
      if (!mounted) return;
      _started = true;
      _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant XpLevelBar old) {
    super.didUpdateWidget(old);
    if (old.toPos != widget.toPos) {
      if (_started) {
        _from = _pos();
        _to = widget.toPos;
        _c.forward(from: 0);
      } else {
        _to = widget.toPos;
      }
    }
  }

  double _pos() {
    if (!_started) return _from;
    final t = Curves.easeInOutCubic.transform(_c.value);
    return _from + (_to - _from) * t;
  }

  void _onTick() {
    final lv = _pos().floor();
    if (lv > _lastLevel) {
      _lastLevel = lv;
      _leveledUp = true;
      SoundService.instance.levelUp();
      HapticService.instance.heavy();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pos = _pos();
        final level = pos.floor() + 1;
        final frac = (pos - pos.floor()).clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  t('rc_level', {'n': '$level'}),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (_leveledUp)
                  const _LevelUpBadge()
                else
                  const SizedBox.shrink(),
                const Spacer(),
                Text(
                  t('rc_level', {'n': '${level + 1}'}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF241A5C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD54F), width: 1.6),
              ),
              clipBehavior: Clip.antiAlias,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: frac,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF8CFFEA)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LevelUpBadge extends StatelessWidget {
  const _LevelUpBadge();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Text(
        '⬆ ${t('rc_levelUp')}',
        style: const TextStyle(
          color: Color(0xFFFFD54F),
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}
