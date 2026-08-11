import 'dart:math';

import 'package:flutter/material.dart';

import '../game/orbit_controller.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'rock_painter.dart';

/// Ic ice gecmis donen yorunge halkalarini gosteren, dokunmayla kontrol
/// edilen oyun tahtasi widget'i.
///
/// Etkilesim: bir halkanin cizildigi yaricap bandina dokunulunca, dokunulan
/// nokta merkezin SOLUNDAYSA halka saat yonunun TERSINE, SAGINDAYSA saat
/// yonunde bir adim doner. Ustteki "toplama hunisi" (gate) her zaman sabit
/// kalir; nesneler halkalar donerken oraya dogru kayar.
///
/// GORSEL IPUCU: bu kural ekranda hicbir yerde yazmadigi icin, tahtanin
/// tam ortasindan gecen kesikli bir dikey cizgi ve onun iki yaninda sabit
/// "‹ ters yon" / "saat yonu ›" etiketleri ciziliyor; ayrica her halkanin
/// sol yarisi soguk (mavi), sag yarisi sicak (turuncu) renkte ince bir
/// cizgiyle vurgulanip yon farkini surekli hatirlatiyor. Bir donus rihtim
/// doluluğu yuzunden reddedilirse, o halka kisa sureligine kirmizi yanip
/// soner (blokaj geri bildirimi).
///
/// GEZEGEN CIKIS ANIMASYONU: kapiya gelen bir gezegen halkadan ayrildiginda
/// (teslim edildi ya da rihtima kondu) artik aniden kaybolmuyor; kapi
/// noktasindan hedefine dogru kisa bir "suzulme" (glide) animasyonuyla
/// ucuyor — teslim edilenler yukari/disari, rihtima gidenler asagiya
/// (Kargo Rihtimi kutusuna dogru) suzulur. bkz. [OrbitController.lastExit].
class OrbitBoard extends StatefulWidget {
  final OrbitController controller;
  final void Function(int ringIndex) onBlockedTap;

  const OrbitBoard({
    super.key,
    required this.controller,
    required this.onBlockedTap,
  });

  @override
  State<OrbitBoard> createState() => _OrbitBoardState();
}

class _FlightItem {
  final int id;
  final int colorIndex;
  final Offset start;
  final Offset end;
  final bool matched;
  final AnimationController anim;

  _FlightItem({
    required this.id,
    required this.colorIndex,
    required this.start,
    required this.end,
    required this.matched,
    required this.anim,
  });
}

class _OrbitBoardState extends State<OrbitBoard> with TickerProviderStateMixin {
  int? _flashRing;
  int? _lastHandledExitId;
  final List<_FlightItem> _flights = [];

  void _flash(int ringIndex) {
    setState(() => _flashRing = ringIndex);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted && _flashRing == ringIndex) {
        setState(() => _flashRing = null);
      }
    });
  }

  /// Yeni bir [OrbitController.lastExit] olayi tespit edilince cagrilir:
  /// kapi konumundan hedefine giden yeni bir "ucus" (flight) baslatir ve
  /// uygun ses efektini calar. Ayni build gecisinde birden fazla setState
  /// tetiklememek icin bir sonraki frame'e ertelenir.
  void _maybeSpawnFlight(Size size, double step) {
    final exit = widget.controller.lastExit;
    if (exit == null || exit.id == _lastHandledExitId) return;
    _lastHandledExitId = exit.id;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = step * (exit.ringIndex + 1.4);
    final start = center + const Offset(0, 0) + Offset(0, -radius);
    // Teslim edilen (matched) gezegen kapidan yukari/disari suzulerek
    // "gonderilir"; eslesmeyen gezegen ise asagidaki Kargo Rihtimi
    // kutusuna dogru suzulur.
    final end = exit.matched
        ? Offset(size.width / 2, -step * 0.8)
        : Offset(size.width / 2, size.height + step * 0.8);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      );
      final item = _FlightItem(
        id: exit.id,
        colorIndex: exit.colorIndex,
        start: start,
        end: end,
        matched: exit.matched,
        anim: animController,
      );
      setState(() => _flights.add(item));
      if (exit.matched) {
        SoundService.instance.orbitDeliver();
      } else {
        SoundService.instance.orbitDock();
      }
      animController.forward();
      animController.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _flights.remove(item));
          animController.dispose();
        }
      });
    });
  }

  @override
  void dispose() {
    for (final item in _flights) {
      item.anim.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DirectionLegend(),
        const SizedBox(height: 6),
        Expanded(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  final shortest = min(size.width, size.height);
                  final ringCount = widget.controller.level.rings.length;
                  final step = shortest / 2 / (ringCount + 1.4);

                  _maybeSpawnFlight(size, step);

                  return GestureDetector(
                    onTapUp: (details) {
                      final box = context.findRenderObject() as RenderBox;
                      final local = box.globalToLocal(details.globalPosition);
                      final center = Offset(size.width / 2, size.height / 2);
                      final dx = local.dx - center.dx;
                      final dy = local.dy - center.dy;
                      final radius = sqrt(dx * dx + dy * dy);
                      if (radius < step * 0.5) return; // merkeze / hunuye dokunuldu

                      final ringIndex = ((radius - step * 0.5) / step)
                          .floor()
                          .clamp(0, ringCount - 1)
                          .toInt();
                      final clockwise = dx >= 0;
                      final ok = widget.controller
                          .rotateRing(ringIndex, clockwise: clockwise);
                      if (ok) {
                        SoundService.instance.orbitRotate();
                      } else {
                        SoundService.instance.invalid();
                        _flash(ringIndex);
                        widget.onBlockedTap(ringIndex);
                      }
                    },
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: size,
                          painter: _OrbitPainter(
                            controller: widget.controller,
                            step: step,
                            flashRing: _flashRing,
                          ),
                        ),
                        for (final flight in _flights)
                          _FlightWidget(key: ValueKey(flight.id), item: flight),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Kapidan cikan tek bir gezegenin suzulme animasyonunu ciziyor:
/// baslangictan (kapi) bitise (yukari/asagi) konum, kucculme ve solma
/// (fade-out) ile birlikte hareket eder.
class _FlightWidget extends AnimatedWidget {
  final _FlightItem item;

  _FlightWidget({super.key, required this.item}) : super(listenable: item.anim);

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeInCubic.transform(item.anim.value);
    final pos = Offset.lerp(item.start, item.end, t)!;
    final scale = 1.0 - (t * 0.45);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    const objectSize = 30.0;

    return Positioned(
      left: pos.dx - objectSize / 2,
      top: pos.dy - objectSize / 2,
      width: objectSize,
      height: objectSize,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: CustomPaint(
            painter: _FlightPlanetPainter(item.colorIndex),
          ),
        ),
      ),
    );
  }
}

class _FlightPlanetPainter extends CustomPainter {
  final int colorIndex;
  const _FlightPlanetPainter(this.colorIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = AppColors.colorFor(colorIndex).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * 0.62, glow);
    paintRock(canvas, Offset.zero & size, colorIndex);
  }

  @override
  bool shouldRepaint(covariant _FlightPlanetPainter oldDelegate) =>
      oldDelegate.colorIndex != colorIndex;
}

/// Tahtanin uzerinde sabit duran, "hangi taraf hangi yone dondurur"
/// hatirlaticisi. Sadece bir kez okunmasi yeterli olacak sekilde kucuk ve
/// surekli gorunur tutuluyor.
class _DirectionLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.rotate_left_rounded, color: AppColors.accentSoft, size: 16),
        const SizedBox(width: 4),
        Text(t('orbit_tapLeft'),
            style: const TextStyle(
                color: AppColors.accentSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 14),
        Container(width: 1, height: 12, color: AppColors.surfaceBorder),
        const SizedBox(width: 14),
        Text(t('orbit_tapRight'),
            style: const TextStyle(
                color: AppColors.warning,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        const Icon(Icons.rotate_right_rounded, color: AppColors.warning, size: 16),
      ],
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final OrbitController controller;
  final double step;
  final int? flashRing;

  _OrbitPainter({required this.controller, required this.step, this.flashRing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rings = controller.level.rings;
    final maxRadius = step * (rings.length + 1.4) + step * 0.6;

    // Tum tahtayi ikiye bolen, "sol = ters yon / sag = saat yonu"
    // kuralini surekli hatirlatan kesikli dikey cizgi.
    _drawDashedVerticalLine(canvas, center, maxRadius);

    // Merkez gunes.
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.warning, AppColors.warning.withValues(alpha: 0.15)],
      ).createShader(Rect.fromCircle(center: center, radius: step * 0.55));
    canvas.drawCircle(center, step * 0.42, sunPaint);

    for (var i = 0; i < rings.length; i++) {
      final ring = rings[i];
      final radius = step * (i + 1.4);
      final isFlashing = flashRing == i;
      final isLocked = ring.locked;

      // Halkanin kendisi: sol yari mavi (ters yon), sag yari turuncu (saat
      // yonu) olacak sekilde iki ayri yay olarak ciziliyor, boylece her
      // halka kendi uzerinde yon ipucunu tasiyor. Kilitli halkalarda bu
      // renkler soluk griye doner ki "şu an dokunulamaz" hissi versin.
      final leftArcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFlashing ? 3.4 : 2.0
        ..color = isFlashing
            ? AppColors.danger
            : isLocked
                ? AppColors.textSecondary.withValues(alpha: 0.35)
                : AppColors.accentSoft.withValues(alpha: 0.55);
      final rightArcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFlashing ? 3.4 : 2.0
        ..color = isFlashing
            ? AppColors.danger
            : isLocked
                ? AppColors.textSecondary.withValues(alpha: 0.35)
                : AppColors.warning.withValues(alpha: 0.55);

      final ringRect = Rect.fromCircle(center: center, radius: radius);
      // Sag yari: -90° (tepe) -> +90° (dip), saat yonunde.
      canvas.drawArc(ringRect, -pi / 2, pi, false, rightArcPaint);
      // Sol yari: -90° (tepe) -> -270°/+90° (dip), saat yonunun tersine.
      canvas.drawArc(ringRect, -pi / 2, -pi, false, leftArcPaint);

      final n = ring.cellCount;
      final objectRadius = (step * 0.46).clamp(13.0, 30.0).toDouble();
      for (var c = 0; c < n; c++) {
        final angle = (-pi / 2) + (c * 2 * pi / n);
        final pos = center + Offset(cos(angle), sin(angle)) * radius;
        final value = ring.cells[c];
        if (value == null) {
          final emptyPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = AppColors.tubeGlassBorder.withValues(alpha: 0.5);
          canvas.drawCircle(pos, objectRadius * 0.7, emptyPaint);
        } else {
          final glow = Paint()
            ..color =
                AppColors.colorFor(value).withValues(alpha: isLocked ? 0.15 : 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
          canvas.drawCircle(pos, objectRadius * 1.15, glow);
          final rect = Rect.fromCenter(
            center: pos,
            width: objectRadius * 2,
            height: objectRadius * 2,
          );
          if (isLocked) {
            canvas.saveLayer(rect.inflate(6), Paint()..color = Colors.white.withValues(alpha: 0.55));
            paintRock(canvas, rect, value);
            canvas.restore();
          } else {
            paintRock(canvas, rect, value);
          }
        }
      }

      // Bu halkanin "kapi" isaretcisi (her zaman tepede, index 0).
      final gatePos = center + Offset(0, -radius);
      if (isLocked) {
        // Kilitli halkalarda kapi vurgusu yerine kucuk bir asma kilit
        // cizilir — oyuncu neden dokunamadigini gorsel olarak anlar.
        _drawLockGlyph(canvas, gatePos, objectRadius * 0.62);
      } else {
        final gateHighlight = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = AppColors.accentSoft.withValues(alpha: 0.8);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          (-pi / 2) - 0.18,
          0.36,
          false,
          gateHighlight,
        );
        canvas.drawCircle(gatePos, 2.4, Paint()..color = AppColors.accentSoft);
      }
    }
  }

  /// Kucuk, vektorel bir asma kilit sembolu (kavis + govde) — dis kaynak
  /// gerektirmez, projenin "her sey Canvas'la cizilir" ilkesine uyar.
  void _drawLockGlyph(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round
      ..color = AppColors.textSecondary;
    final shacklePath = Path()
      ..addArc(
        Rect.fromCenter(
            center: center + Offset(0, -r * 0.15), width: r * 1.1, height: r * 1.3),
        pi,
        pi,
      );
    canvas.drawPath(shacklePath, paint);
    final bodyPaint = Paint()..color = AppColors.textSecondary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, r * 0.35), width: r * 1.5, height: r * 1.15),
        Radius.circular(r * 0.25),
      ),
      bodyPaint,
    );
  }

  void _drawDashedVerticalLine(Canvas canvas, Offset center, double maxRadius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.surfaceBorder.withValues(alpha: 0.6);
    const dashLength = 5.0;
    const gapLength = 4.0;
    var y = center.dy - maxRadius;
    final endY = center.dy + maxRadius;
    while (y < endY) {
      final segmentEnd = min(y + dashLength, endY);
      canvas.drawLine(Offset(center.dx, y), Offset(center.dx, segmentEnd), paint);
      y = segmentEnd + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => true;
}
