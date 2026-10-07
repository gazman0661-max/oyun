import 'dart:math';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../services/game_fx.dart';
import 'ui_kit.dart';

/// BOLUM SONU + SEVIYE ATLAMA "SOV" EKRANLARI
///
///  * [ChapterCompleteCelebration]: karartma, donen isin demeti, konfeti,
///    sirayla "pop" ile acilan 1-3 yildiz, sayarak artan oduller, XP cubugu.
///  * [showLevelUpCelebration]: madalyon icinde yeni seviye + oduller + "Al".
///
/// Hissi ayarlamak icin dosyanin basindaki sabitlere bak.
const Color _kGoldLight = Color(0xFFFFE27A);
const Color _kGoldDark = Color(0xFFB8741A);
const Color _kOutline = Color(0xFF6B2E0B);
const int _kConfettiCount = 90;

// ── Ortak parcalar ──────────────────────────────────────────────

/// Kalin kahverengi konturlu, altin renkli baslik yazisi.
class _StrokedText extends StatelessWidget {
  final String text;
  final double size;
  final Color fill;
  const _StrokedText(this.text, {required this.size, this.fill = _kGoldLight});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: size, fontWeight: FontWeight.w900, height: 1.05);
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.16
              ..strokeJoin = StrokeJoin.round
              ..color = _kOutline,
          ),
        ),
        Text(text, textAlign: TextAlign.center, style: base.copyWith(color: fill)),
      ],
    );
  }
}

/// Merkezden acilan, yavasca donen isin demeti.
class _SunburstPainter extends CustomPainter {
  final double angle;
  final double opacity;
  _SunburstPainter(this.angle, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.longestSide;
    const rays = 14;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF3B0).withOpacity(0.55 * opacity),
          const Color(0xFFFFD54F).withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.7));
    for (int i = 0; i < rays; i++) {
      final a0 = angle + i * 2 * pi / rays;
      final a1 = a0 + pi / rays;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a0) * r, c.dy + sin(a0) * r)
        ..lineTo(c.dx + cos(a1) * r, c.dy + sin(a1) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SunburstPainter old) => old.angle != angle || old.opacity != opacity;
}

class _ConfettiPiece {
  final double vx, vy, size, spin, phase;
  final Color color;
  final bool round;
  _ConfettiPiece(this.vx, this.vy, this.size, this.spin, this.phase, this.color, this.round);
}

/// Ust-ortadan patlayip asagi dusen konfeti (tek seferlik).
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double seconds; // baslangictan beri gecen sure
  final Offset origin;
  _ConfettiPainter(this.pieces, this.seconds, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    const gravity = 900.0;
    const life = 3.2;
    if (seconds > life) return;
    for (final p in pieces) {
      final x = origin.dx + p.vx * seconds;
      final y = origin.dy + p.vy * seconds + 0.5 * gravity * seconds * seconds;
      if (y > size.height + 20) continue;
      final fade = seconds < life - 0.8 ? 1.0 : ((life - seconds) / 0.8).clamp(0.0, 1.0).toDouble();
      final paint = Paint()..color = p.color.withOpacity(fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.phase + p.spin * seconds);
      // "sallanma" etkisi: genislik cosinus ile daralip genisler
      final w = p.size * (0.35 + 0.65 * cos(seconds * 9 + p.phase).abs());
      if (p.round) {
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w, height: p.size), paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: p.size * 1.6), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.seconds != seconds;
}

List<_ConfettiPiece> _makeConfetti(int seed) {
  final rnd = Random(seed);
  const colors = [
    Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF69F0AE),
    Color(0xFF40C4FF), Color(0xFFE040FB), Color(0xFFFFFFFF),
  ];
  return List.generate(_kConfettiCount, (_) {
    final ang = -pi / 2 + (rnd.nextDouble() - 0.5) * 2.4; // yukari yelpaze
    final speed = 350 + rnd.nextDouble() * 650;
    return _ConfettiPiece(
      cos(ang) * speed,
      sin(ang) * speed,
      6 + rnd.nextDouble() * 7,
      (rnd.nextDouble() - 0.5) * 12,
      rnd.nextDouble() * pi * 2,
      colors[rnd.nextInt(colors.length)],
      rnd.nextBool(),
    );
  });
}

/// Parlak yesil, kabarik "cartoon" buton.
class _GlossyButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final double width;
  final Color top;
  final Color bottom;
  const _GlossyButton({
    required this.label,
    required this.onPressed,
    this.width = 240,
    this.top = const Color(0xFFB6F542),
    this.bottom = const Color(0xFF3FAE1B),
  });

  @override
  Widget build(BuildContext context) {
    // Mavi ton verilmisse (Tekrar Oyna) mavi buton, aksi halde yesil.
    final blue = top.value == 0xFF7FC8FF;
    return SizedBox(
      width: width,
      child: CandyButton(
        label: label,
        height: 58,
        fontSize: 21,
        style: blue ? CandyStyle.blue : CandyStyle.green,
        onTap: onPressed,
      ),
    );
  }
}

/// Oduller icin kucuk "hap" seklinde satir (ikon + sayilan deger).
class _RewardChip extends StatelessWidget {
  final Widget icon;
  final String text;
  const _RewardChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: icon)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

Widget _coinIcon() => Image.asset('assets/images/coin_icon.webp', width: 24, height: 24);
Widget _gemIcon() => const Text('💎', style: TextStyle(fontSize: 20));

// ── BOLUM TAMAMLANDI ────────────────────────────────────────────

class ChapterCompleteCelebration extends StatefulWidget {
  final String title;
  final String chapterLabel;
  final int stars; // 1-3
  final int coins;
  final int gems;
  final int xpGained;
  final int level;
  final double barFrom;
  final double barTo;
  final bool buttonsEnabled; // seviye atlama kutlamasi bitene kadar false
  final VoidCallback? onNextPressed;
  final String? nextLabel; // null = varsayilan "Sonraki Bolum"
  final VoidCallback onReplayPressed;
  final VoidCallback onMapPressed;
  // Reklamla x2 coin: doubleBonus > 0 ve onDoublePressed != null ise buton gorunur.
  final int doubleBonus;
  final bool doubleBusy;
  final VoidCallback? onDoublePressed;

  const ChapterCompleteCelebration({
    super.key,
    required this.title,
    required this.chapterLabel,
    required this.stars,
    required this.coins,
    required this.gems,
    required this.xpGained,
    required this.level,
    required this.barFrom,
    required this.barTo,
    this.buttonsEnabled = true,
    required this.onReplayPressed,
    required this.onMapPressed,
    this.onNextPressed,
    this.nextLabel,
    this.doubleBonus = 0,
    this.doubleBusy = false,
    this.onDoublePressed,
  });

  @override
  State<ChapterCompleteCelebration> createState() => _ChapterCompleteCelebrationState();
}

class _ChapterCompleteCelebrationState extends State<ChapterCompleteCelebration> with TickerProviderStateMixin {
  static const double _total = 3.4; // saniye - tum giris animasyonu
  late final AnimationController _intro;
  late final AnimationController _spin;
  late final List<_ConfettiPiece> _confetti;
  final Set<int> _starSounded = {};

  @override
  void initState() {
    super.initState();
    _confetti = _makeConfetti(widget.stars * 97 + widget.level);
    _intro = AnimationController(vsync: this, duration: Duration(milliseconds: (_total * 1000).round()))
      ..addListener(_onIntroTick)
      ..forward();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  }

  // Her yildiz acildigi anda yukselen tonda "tik" + titresim.
  void _onIntroTick() {
    final t = _intro.value * _total;
    for (int i = 0; i < widget.stars; i++) {
      if (t >= _starStart(i) && _starSounded.add(i)) {
        GameFx.instance.merge(3 + i * 2);
      }
    }
  }

  double _starStart(int i) => 0.55 + i * 0.32;

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  /// [start, start+dur] araligindaki 0..1 ilerleme.
  double _seg(double t, double start, double dur) => ((t - start) / dur).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _spin]),
      builder: (context, _) {
        final t = _intro.value * _total;
        final scrim = _seg(t, 0, 0.3);
        final titleP = Curves.elasticOut.transform(_seg(t, 0.1, 0.7));
        final rewardP = Curves.easeOut.transform(_seg(t, 1.8, 0.5));
        final btnP = Curves.easeOutBack.transform(_seg(t, 2.5, 0.5));
        final verdictKey = 'stars_verdict_${widget.stars}';

        return LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: Colors.black.withOpacity(0.74 * scrim))),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _SunburstPainter(_spin.value * 2 * pi, scrim)),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ConfettiPainter(_confetti, max(0.0, t - 0.15), Offset(size.width / 2, size.height * 0.38)),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                  width: min(size.width - 32, 420.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: titleP,
                        child: Opacity(
                          opacity: titleP.clamp(0.0, 1.0).toDouble(),
                          child: Column(
                            children: [
                              _StrokedText(widget.title, size: 34),
                              const SizedBox(height: 2),
                              Text(widget.chapterLabel,
                                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildStars(t),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: _seg(t, _starStart(widget.stars - 1) + 0.25, 0.3),
                        child: _StrokedText(s.t(verdictKey), size: 26),
                      ),
                      const SizedBox(height: 16),
                      Opacity(
                        opacity: rewardP,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - rewardP)),
                          child: _buildRewards(t),
                        ),
                      ),
                      const SizedBox(height: 22),
                      IgnorePointer(
                        ignoring: !widget.buttonsEnabled,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: widget.buttonsEnabled ? btnP.clamp(0.0, 1.0).toDouble() : 0.0,
                          child: Transform.scale(scale: 0.85 + 0.15 * btnP, child: _buildButtons()),
                        ),
                      ),
                    ],
                  ),
                    ),
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }

  // Ortadaki yildiz daha buyuk ve yukarida (yay seklinde dizilim).
  Widget _buildStars(double t) {
    const sizes = [78.0, 104.0, 78.0];
    const tilt = [-0.18, 0.0, 0.18];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(3, (i) {
        final earned = i < widget.stars;
        final p = earned ? _seg(t, _starStart(i), 0.45) : _seg(t, 0.45, 0.4);
        // 0 -> 1.35 -> 1 : "pop"
        final scale = earned ? Curves.easeOutBack.transform(p) : Curves.easeOut.transform(p);
        final glow = earned ? (1 - _seg(t, _starStart(i) + 0.2, 0.6)) : 0.0;
        return Padding(
          padding: EdgeInsets.only(left: 3, right: 3, top: i == 1 ? 0 : 24),
          child: Transform.rotate(
            angle: tilt[i] * (earned ? (1 - p) * 2 + 1 : 1),
            child: Transform.scale(
              scale: scale.clamp(0.0, 1.5).toDouble(),
              child: Container(
                width: sizes[i],
                height: sizes[i],
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: earned && glow > 0
                      ? [BoxShadow(color: const Color(0xFFFFE27A).withOpacity(0.8 * glow), blurRadius: 40 * glow, spreadRadius: 6 * glow)]
                      : null,
                ),
                child: Image.asset(
                  earned ? 'assets/images/ui/star_full.webp' : 'assets/images/ui/star_empty.webp',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildRewards(double t) {
    final count = Curves.easeOut.transform(_seg(t, 1.9, 1.0));
    final chips = <Widget>[
      _RewardChip(icon: _coinIcon(), text: '+${(widget.coins * count).round()}'),
      if (widget.gems > 0) _RewardChip(icon: _gemIcon(), text: '+${(widget.gems * count).ceil()}'),
      _RewardChip(
        icon: const Icon(Icons.auto_awesome, color: Color(0xFF7CF3FF), size: 20),
        text: '+${(widget.xpGained * count).round()} XP',
      ),
    ];
    final bar = Curves.easeInOut.transform(_seg(t, 2.1, 1.1));
    final barValue = widget.barFrom + (widget.barTo - widget.barFrom) * bar;
    return Column(
      children: [
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: chips),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: Row(
            children: [
              Text('${AppStrings.instance.t('level_short')} ${widget.level}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: barValue.clamp(0.0, 1.0).toDouble(),
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF7CF3FF)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    final s = AppStrings.instance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onDoublePressed != null && widget.doubleBonus > 0) ...[
          IgnorePointer(
            ignoring: widget.doubleBusy,
            child: Opacity(
              opacity: widget.doubleBusy ? 0.6 : 1.0,
              child: SizedBox(
                width: 240,
                child: CandyButton(
                  label: '🎬 ${s.t('double_coins_btn')}  +${widget.doubleBonus}',
                  height: 58,
                  fontSize: 21,
                  style: CandyStyle.orange,
                  onTap: widget.onDoublePressed!,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.onNextPressed != null)
          _GlossyButton(label: widget.nextLabel ?? s.t('next_chapter'), onPressed: widget.onNextPressed!),
        if (widget.onNextPressed != null) const SizedBox(height: 10),
        _GlossyButton(
          label: s.t('play_again'),
          onPressed: widget.onReplayPressed,
          width: widget.onNextPressed != null ? 200 : 240,
          top: widget.onNextPressed != null ? const Color(0xFF7FC8FF) : const Color(0xFFB6F542),
          bottom: widget.onNextPressed != null ? const Color(0xFF2B7FD6) : const Color(0xFF3FAE1B),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: widget.onMapPressed,
          child: Text(s.t('return_to_map'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }
}

// ── SEVIYE ATLAMA ───────────────────────────────────────────────

/// [rewards] listesindeki her seviye icin sirayla kutlama ekrani acar.
Future<void> showLevelUpCelebrations(BuildContext context, List<LevelUpReward> rewards) async {
  for (final r in rewards) {
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => _LevelUpScreen(reward: r),
    );
  }
}

class _LevelUpScreen extends StatefulWidget {
  final LevelUpReward reward;
  const _LevelUpScreen({required this.reward});

  @override
  State<_LevelUpScreen> createState() => _LevelUpScreenState();
}

class _LevelUpScreenState extends State<_LevelUpScreen> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _spin;
  late final List<_ConfettiPiece> _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = _makeConfetti(widget.reward.level * 31);
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    GameFx.instance.chapterComplete(); // fanfar + titresim
  }

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  double _seg(double t, double start, double dur) => ((t - start) / dur).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final r = widget.reward;
    const total = 2.6;
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _spin]),
        builder: (context, _) {
          final t = _intro.value * total;
          final scrim = _seg(t, 0, 0.25);
          final titleP = Curves.elasticOut.transform(_seg(t, 0.05, 0.7));
          final badgeP = Curves.elasticOut.transform(_seg(t, 0.3, 0.9));
          final rewardP = Curves.easeOut.transform(_seg(t, 1.0, 0.5));
          final btnP = Curves.easeOutBack.transform(_seg(t, 1.6, 0.5));
          return LayoutBuilder(builder: (context, box) {
            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.black.withOpacity(0.82 * scrim))),
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _SunburstPainter(_spin.value * 2 * pi, scrim))),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConfettiPainter(_confetti, max(0.0, t - 0.2), Offset(box.maxWidth / 2, box.maxHeight * 0.36)),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(scale: titleP, child: _StrokedText(s.t('level_up_title'), size: 38)),
                      const SizedBox(height: 22),
                      Transform.scale(scale: badgeP, child: _LevelBadge(level: r.level)),
                      const SizedBox(height: 24),
                      Opacity(
                        opacity: rewardP,
                        child: Column(
                          children: [
                            _StrokedText(s.t('rewards_label'), size: 22, fill: const Color(0xFFFFC96B)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _RewardChip(icon: _coinIcon(), text: '+${r.coins}'),
                                if (r.gems > 0) _RewardChip(icon: _gemIcon(), text: '+${r.gems}'),
                                if (r.energyRefilled)
                                  const _RewardChip(icon: Icon(Icons.bolt, color: Color(0xFF3DD6FF), size: 24), text: 'MAX'),
                              ],
                            ),
                            if (r.energyRefilled) ...[
                              const SizedBox(height: 10),
                              Text(s.t('level_up_energy_full'),
                                  style: const TextStyle(color: Color(0xFFFFE9A8), fontWeight: FontWeight.w800, fontSize: 15)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      Opacity(
                        opacity: btnP.clamp(0.0, 1.0).toDouble(),
                        child: Transform.scale(
                          scale: 0.85 + 0.15 * btnP,
                          child: _GlossyButton(
                            label: s.t('claim_button'),
                            width: 220,
                            onPressed: () {
                              GameFx.instance.reward();
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          });
        },
      ),
    );
  }
}

/// Altin cerceveli madalyon + icinde seviye numarasi + altta yildiz.
class _LevelBadge extends StatelessWidget {
  final int level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kGoldLight, Color(0xFFFFB92E), _kGoldDark],
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFFD54F).withOpacity(0.7), blurRadius: 34, spreadRadius: 4),
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 6)),
              ],
            ),
          ),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Colors.white, Color(0xFFF6E7C4)]),
              border: Border.all(color: const Color(0xFFE2A93B), width: 5),
            ),
            alignment: Alignment.center,
            child: _StrokedText('$level', size: 76),
          ),
          Positioned(
            bottom: -14,
            child: Image.asset('assets/images/ui/star_full.webp', width: 64, height: 64),
          ),
        ],
      ),
    );
  }
}
