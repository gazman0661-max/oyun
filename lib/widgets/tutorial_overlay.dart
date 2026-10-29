import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';

/// Bir ogretici adiminin nasil ilerledigi.
enum TutorialAdvance {
  /// Balonda "Devam" butonu var; hedef (varsa) parlar ama dokunulamaz.
  button,

  /// Oyuncu parlayan hedefe dokununca ilerler (dokunus hedefe de ulasir).
  targetTap,

  /// Disaridan [TutorialHandle.close] ile kapatilir (ornegin "ilk gezegeni
  /// birak" gibi oyun olaylarini beklerken). Hedefe dokunmak serbesttir.
  manual,
}

class TutorialStep {
  /// Parlatilacak widget (null ise sadece karartma + balon).
  final GlobalKey? target;

  /// Localization anahtari.
  final String textKey;
  final Map<String, String>? textArgs;
  final TutorialAdvance advance;

  /// Hedefin dikdortgenini degistirmek icin (ornegin tehlike cizgisi bandi).
  final Rect Function(Rect)? holeBuilder;
  final double holePadding;

  /// "3/12" gibi kucuk sayac.
  final String? counter;
  final bool showSkip;

  const TutorialStep({
    this.target,
    required this.textKey,
    this.textArgs,
    this.advance = TutorialAdvance.button,
    this.holeBuilder,
    this.holePadding = 8,
    this.counter,
    this.showSkip = true,
  });
}

/// Calisan bir adimi temsil eder. [done] adim bitince tamamlanir;
/// deger true ise oyuncu ogreticiyi ATLADI.
class TutorialHandle {
  final Completer<bool> _completer = Completer<bool>();
  OverlayEntry? _entry;

  Future<bool> get done => _completer.future;
  bool get isOpen => !_completer.isCompleted;

  void close({bool skipped = false}) {
    final e = _entry;
    _entry = null;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {}
    }
    if (!_completer.isCompleted) _completer.complete(skipped);
  }
}

class TutorialOverlay {
  TutorialOverlay._();

  /// Adimi root overlay'e ekler ve bir [TutorialHandle] doner.
  static TutorialHandle show(BuildContext context, TutorialStep step) {
    final handle = TutorialHandle();
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => _TutorialLayer(step: step, handle: handle),
    );
    handle._entry = entry;
    overlay.insert(entry);
    unawaited(AnalyticsService.instance.log('tutorial_step', {
      'step': step.textKey,
      'counter': step.counter,
    }));
    return handle;
  }
}

class _TutorialLayer extends StatefulWidget {
  final TutorialStep step;
  final TutorialHandle handle;
  const _TutorialLayer({required this.step, required this.handle});

  @override
  State<_TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends State<_TutorialLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  Rect? _holeRect() {
    final key = widget.step.target;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    var r = ro.localToGlobal(Offset.zero) & ro.size;
    final b = widget.step.holeBuilder;
    if (b != null) r = b(r);
    return r.inflate(widget.step.holePadding);
  }

  void _targetTapped() {
    if (widget.step.advance != TutorialAdvance.targetTap) return;
    // Alttaki dugmenin kendi onTap'i de calissin diye bir sonraki kareye birak.
    scheduleMicrotask(() => widget.handle.close());
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, _) {
        final size = MediaQuery.of(context).size;
        final pad = MediaQuery.of(context).padding;
        final hole = _holeRect();
        final blockHole = step.advance == TutorialAdvance.button;
        final children = <Widget>[];

        // 1) Karartma (dokunus almaz, sadece boyar).
        children.add(Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DimPainter(hole, dimmed: step.advance != TutorialAdvance.manual),
            ),
          ),
        ));

        // 2) Dokunus engelleyiciler: delik haric her yer.
        Widget blocker(Rect r) => Positioned.fromRect(
              rect: r,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                onPanStart: (_) {},
                child: const SizedBox.expand(),
              ),
            );
        if (hole == null) {
          children.add(Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onPanStart: (_) {},
            ),
          ));
        } else {
          final h = Rect.fromLTRB(
            hole.left.clamp(0.0, size.width),
            hole.top.clamp(0.0, size.height),
            hole.right.clamp(0.0, size.width),
            hole.bottom.clamp(0.0, size.height),
          );
          children.addAll([
            blocker(Rect.fromLTRB(0, 0, size.width, h.top)),
            blocker(Rect.fromLTRB(0, h.bottom, size.width, size.height)),
            blocker(Rect.fromLTRB(0, h.top, h.left, h.bottom)),
            blocker(Rect.fromLTRB(h.right, h.top, size.width, h.bottom)),
          ]);
          if (blockHole) {
            children.add(blocker(h));
          } else {
            children.add(Positioned.fromRect(
              rect: h,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerUp: (_) => _targetTapped(),
                child: const SizedBox.expand(),
              ),
            ));
          }
        }

        // 3) Ok + balon.
        final wave = math.sin(_bounce.value * math.pi) * 10;
        final bubbleW = math.min(size.width - 32, 380.0);
        final left = (size.width - bubbleW) / 2;
        const arrowH = 78.0;
        const arrowW = 58.0;
        const bubbleMin = 150.0;

        if (hole == null) {
          children.add(Positioned(
            left: left,
            width: bubbleW,
            top: 0,
            bottom: 0,
            child: Center(child: _bubble(step, withButton: true)),
          ));
        } else {
          final spaceAbove = hole.top - pad.top;
          final spaceBelow = size.height - pad.bottom - hole.bottom;
          final fits = math.max(spaceAbove, spaceBelow) >= bubbleMin + arrowH;
          if (step.advance == TutorialAdvance.manual) {
            // Oyuncu oynarken: tahta acik kalir, balon en alta oturur.
            children.add(Positioned(
              left: left,
              width: bubbleW,
              bottom: pad.bottom + 8,
              child: _bubble(step, withButton: false),
            ));
          } else if (!fits) {
            // Hedef cok buyuk (ornegin oyun tahtasi): balon deligin ortasina
            // yakin oturur (ustte atis alani, altta gezegenler gorunur kalsin).
            children.add(Positioned(
              left: left,
              width: bubbleW,
              top: math.max(pad.top + 8, hole.top + hole.height * 0.32),
              child: _bubble(step, withButton: _showButton(step)),
            ));
          } else {
            final above = spaceAbove >= spaceBelow;
            final cx = hole.center.dx.clamp(arrowW, size.width - arrowW);
            if (above) {
              final arrowTop = hole.top - arrowH - 2 + wave;
              children.add(Positioned(
                left: cx - arrowW / 2,
                top: arrowTop,
                width: arrowW,
                height: arrowH,
                child: IgnorePointer(
                  child: CustomPaint(painter: _ArrowPainter(pointDown: true)),
                ),
              ));
              children.add(Positioned(
                left: left,
                width: bubbleW,
                bottom: size.height - (hole.top - arrowH - 6),
                child: _bubble(step, withButton: _showButton(step)),
              ));
            } else {
              final arrowTop = hole.bottom + 2 - wave;
              children.add(Positioned(
                left: cx - arrowW / 2,
                top: arrowTop,
                width: arrowW,
                height: arrowH,
                child: IgnorePointer(
                  child: CustomPaint(painter: _ArrowPainter(pointDown: false)),
                ),
              ));
              children.add(Positioned(
                left: left,
                width: bubbleW,
                top: hole.bottom + arrowH + 6,
                child: _bubble(step, withButton: _showButton(step)),
              ));
            }
          }
        }

        // 4) Atla butonu.
        if (step.showSkip) {
          children.add(Positioned(
            right: 10,
            top: pad.top + 6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                SoundService.instance.buttonTap();
                unawaited(AnalyticsService.instance
                    .log('tutorial_skip', {'step': step.textKey}));
                widget.handle.close(skipped: true);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  t('tut_skip'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ));
        }

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          builder: (context, v, child) => Opacity(opacity: v, child: child),
          child: Stack(children: children),
        );
      },
    );
  }

  bool _showButton(TutorialStep s) => s.advance == TutorialAdvance.button;

  Widget _bubble(TutorialStep step, {required bool withButton}) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 22, left: 6),
            padding: const EdgeInsets.fromLTRB(60, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF6EA),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF3B2F5C), width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(step.textKey, step.textArgs),
                  style: const TextStyle(
                    color: Color(0xFF241947),
                    fontSize: 15.5,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (withButton) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        SoundService.instance.buttonTap();
                        widget.handle.close();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF97316), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          t('tut_continue'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Rehber karakter (profil gorseli).
          Positioned(
            left: -4,
            top: 0,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/icon/profile_icon.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: AppColors.accent,
                    child: Center(
                      child: Text('🐱', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (step.counter != null)
            Positioned(
              right: 14,
              top: 28,
              child: Text(
                step.counter!,
                style: const TextStyle(
                  color: Color(0x99241947),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect? hole;

  /// false: karartma yok, sadece ince cerceve (oyuncu oynarken ekran net gorunsun).
  final bool dimmed;
  _DimPainter(this.hole, {this.dimmed = true});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final h = hole;
    if (h == null) {
      if (dimmed) canvas.drawPath(full, dim);
      return;
    }
    if (!dimmed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(18)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFFC857).withValues(alpha: 0.9),
      );
      return;
    }
    final rr = RRect.fromRectAndRadius(h, const Radius.circular(18));
    final cut = Path.combine(
      PathOperation.difference,
      full,
      Path()..addRRect(rr),
    );
    canvas.drawPath(cut, dim);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFFFFC857).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _DimPainter old) =>
      old.hole != hole || old.dimmed != dimmed;
}

/// Referanstaki gibi turuncu, beyaz kenarli blok ok.
class _ArrowPainter extends CustomPainter {
  final bool pointDown;
  _ArrowPainter({required this.pointDown});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Asagi bakan ok yolu.
    final p = Path()
      ..moveTo(w * 0.27, 0)
      ..lineTo(w * 0.73, 0)
      ..lineTo(w * 0.73, h * 0.5)
      ..lineTo(w, h * 0.5)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.5)
      ..lineTo(w * 0.27, h * 0.5)
      ..close();
    canvas.save();
    if (!pointDown) {
      canvas.translate(0, h);
      canvas.scale(1, -1);
    }
    canvas.drawShadow(p, Colors.black, 6, true);
    canvas.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFC107), Color(0xFFFF6D00)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) =>
      old.pointDown != pointDown;
}
