import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/planet_images.dart';

/// Gezegen gorsellerinin ustune cizilen sevimli yuzler.
///
/// Yuz, PNG'nin icine gomulu degil, kodla cizilir: boylece her gezegende
/// ayni stil, gozler kirpar (blink) ve ayarlamak icin
/// sadece asagidaki [_specs] tablosu degistirilir.
///
/// Geometri, 512x512 gezegen PNG'sinin YARI boyutuna (half) gore verilir:
/// [dx]/[dy] govde merkezinin goruntu merkezine uzakligi, [r] govde
/// yaricapi (halo / halka haric), [scale] yuz buyuklugu carpani.
class _FaceSpec {
  final double dx, dy, r, scale;

  /// true: kapali, mutlu gozler (^ ^). false: parlak acik gozler.
  final bool happyEyes;

  /// 0 gulumseme, 1 acik gulumseme, 2 kedi agzi (w), 3 kucuk "o".
  final int mouth;

  /// Koyu gezegenlerde agiz acik renkle cizilir.
  final bool lightInk;

  const _FaceSpec(
    this.dx,
    this.dy,
    this.r,
    this.scale,
    this.happyEyes,
    this.mouth,
    this.lightInk,
  );
}

// Sira = PlanetImages.assetPaths sirasi.
const List<_FaceSpec> _specs = [
  _FaceSpec(0, 0, .66, 1, true, 1, false), // 0 gunes
  _FaceSpec(0, 0, .64, 1, false, 0, false), // 1 dunya
  _FaceSpec(0, 0, .94, 1, false, 2, false), // 2 gaia
  _FaceSpec(.01, -.01, .49, 1, false, 0, false), // 3 saturn
  _FaceSpec(.02, 0, .49, 1, false, 2, true), // 4 mor halkali
  _FaceSpec(0, 0, .93, 1, false, 1, false), // 5 mars
  _FaceSpec(0, -.1, .53, .8, false, 0, false), // 6 uranus (halka alttan gecer)
  _FaceSpec(0, 0, .93, 1, false, 2, false), // 7 pembe gaz devi
  _FaceSpec(0, 0, .94, 1, false, 3, true), // 8 merkur
  _FaceSpec(0, 0, .93, 1, false, 0, false), // 9 neptun
  _FaceSpec(0, 0, .70, 1, false, 1, true), // 10 indigo
  _FaceSpec(0, 0, .81, 1, false, 2, true), // 11 kizil cuce
  _FaceSpec(0, 0, .74, 1, false, 1, true), // 12 toksik dunya
  _FaceSpec(0, 0, .77, 1, false, 0, false), // 13 buz ay
  _FaceSpec(0, 0, .81, 1, false, 2, true), // 14 bakir asteroit
  _FaceSpec(0, 0, .70, 1, false, 0, true), // 15 karanlik kutle
];

const Color _ink = Color(0xFF2B1B3A);
const Color _lightInk = Color(0xFFFFEEF2);

/// Yuz ifadesi. [idle] bosta: goz kirpma + ara sira dil cikarma / goz
/// kirpma / kocaman gulus. Digerleri oyun durumundan gelir.
enum FaceMood { idle, surprised, happy, worried }

// Her yuz icin Paint nesnesi yeniden olusturulmasin diye paylasilan boyalar
// (canvas cizim cagrisi aninda kopyalar; her kullanimdan hemen once ayarlanir).
final Paint _fillPaint = Paint();
final Paint _linePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round;

double _smooth(double x) {
  final c = x.clamp(0.0, 1.0).toDouble();
  return c * c * (3 - 2 * c);
}

/// [imageIndex] gorseline ait yuzu, gorselin merkezi [c] ve yari boyutu
/// [half] (piksel) olacak sekilde cizer.
///
/// - [timeSec] verilirse goz kirpar (~2.2-3.3 sn'de bir) ve bostayken ara
///   sira (~6.5-10 sn'de bir, 1.4 sn) komik bir ifade yapar; ifadeye girip
///   cikis ~0.18 sn'de yumusatilir.
/// - [mood]: dusen gezegen sasirir, yeni birlesen sevinir, tehlike cizgisine
///   yakin olan endiselenir.
/// - [lookX]/[lookY] (-1..1): gozbebekleri hareket yonune bakar.
/// - [seed] gezegenlerin ayni anda ayni seyi yapmamasi icin faz kaydirir.
void drawPlanetFace(
  Canvas canvas,
  int imageIndex,
  Offset c,
  double half, {
  double opacity = 1,
  int seed = 0,
  double? timeSec,
  FaceMood mood = FaceMood.idle,
  double lookX = 0,
  double lookY = 0,
}) {
  final spec = _specs[imageIndex % _specs.length];
  final u = half * spec.r * spec.scale; // yuz birimi
  if (u < 8) return; // cok kucukse yuz cizme
  final a = (255 * opacity).round().clamp(0, 255).toInt();
  if (a == 0) return;
  final center = Offset(c.dx + spec.dx * half, c.dy + spec.dy * half);
  final sd = seed.abs();

  // ---- Ifade secimi ----
  var happyEyes = spec.happyEyes;
  var idleHappy = false; // bosta "kocaman gulus" (gozler yumusakca kapanir)
  var winkRight = false;
  var wide = false; // sasirmis / endiseli buyuk gozler
  var tongue = false;
  var mouth = spec.mouth;
  var idleMouth = spec.mouth; // bosta ifadenin agzi (gecisin ortasinda gecer)
  var brows = 0; // 1 yukari (sasirma), 2 endiseli
  var exprK = 0.0; // bosta ifade gecis agirligi 0..1 (yumusak)
  switch (mood) {
    case FaceMood.surprised:
      wide = true;
      mouth = 4;
      brows = 1;
      break;
    case FaceMood.happy:
      happyEyes = true;
      mouth = 1;
      break;
    case FaceMood.worried:
      wide = true;
      mouth = 5;
      brows = 2;
      break;
    case FaceMood.idle:
      if (timeSec != null) {
        final period = 6.5 + (sd % 5) * 0.9;
        final t0 = timeSec + (sd % 11) * 1.7;
        final cycle = (t0 / period).floor();
        final t = t0 - cycle * period;
        if (t < 1.4) {
          exprK = _smooth(min(t, 1.4 - t) / 0.18);
          switch ((cycle + sd) % 3) {
            case 0: // goz kirp + dil cikar
              winkRight = true;
              tongue = true;
              idleMouth = 0;
              break;
            case 1: // dil cikar (iki goz acik)
              tongue = true;
              idleMouth = 0;
              break;
            default: // kocaman gulus
              idleHappy = true;
              idleMouth = 1;
          }
          if (exprK >= 0.5) mouth = idleMouth;
        }
      }
      break;
  }

  // Goz kirpma: ~2.2-3.3 sn'de bir, 0.16 sn surer.
  var open = 1.0;
  if (timeSec != null && mood != FaceMood.happy) {
    final period = 2.2 + (sd % 7) * 0.18;
    final t = (timeSec + (sd % 13) * 0.77) % period;
    if (t < 0.16) {
      open = (1 - sin(t / 0.16 * pi)).clamp(0.08, 1.0).toDouble();
    }
  }

  Color withA(Color col, [double f = 1]) =>
      col.withAlpha((a * f).round().clamp(0, 255).toInt());
  Paint fill(Color col) => _fillPaint..color = col;
  Paint line(Color col, double w) => _linePaint
    ..color = col
    ..strokeWidth = w;

  final ink = withA(_ink);
  final browInk = withA(spec.lightInk ? _lightInk : _ink);
  final mouthInk = browInk;
  final eyeX = 0.36 * u;
  final eyeY = -0.02 * u;
  final er = 0.20 * u * (wide ? 1.16 : 1.0);
  final lx = lookX.clamp(-1.0, 1.0).toDouble();
  final ly = lookY.clamp(-1.0, 1.0).toDouble();
  final cheekA = mood == FaceMood.happy ? 0.8 : 0.55 + 0.25 * exprK;

  for (final s in const [-1.0, 1.0]) {
    final ex = center.dx + s * eyeX;
    final ey = center.dy + eyeY;
    // Bosta ifadede kapanan goz: kirpma gibi yumusakca kisilir.
    final eff = open * ((idleHappy || (winkRight && s > 0)) ? 1 - exprK : 1.0);
    final closed = happyEyes || eff < 0.2;

    if (closed) {
      canvas.drawArc(
        Rect.fromLTRB(ex - er, ey - er * 0.9, ex + er, ey + er * 1.1),
        pi * 1.1,
        pi * 0.8,
        false,
        line(ink, max(1.5, 0.075 * u)),
      );
    } else {
      final ry = er * 1.1 * eff;
      final eye = Rect.fromLTRB(ex - er, ey - ry, ex + er, ey + ry);
      canvas.drawOval(eye, fill(withA(Colors.white)));
      canvas.drawOval(eye, line(ink, max(1.0, 0.05 * u)));
      // Gozbebegi hareket yonune kayar; sasirinca kucuk, normalde buyuk.
      final pr = er * (wide ? 0.46 : 0.68);
      final room = er - pr - 0.04 * u;
      final pcx = ex + lx * room * 0.85;
      final pcy = ey + er * 0.1 + ly * room * 0.7;
      canvas.drawOval(
        Rect.fromLTRB(pcx - pr, pcy - pr * eff, pcx + pr, pcy + pr * eff),
        fill(ink),
      );
      if (eff > 0.6) {
        final h = er * 0.28;
        canvas.drawCircle(
          Offset(pcx - pr * 0.1, pcy - pr * 0.55 - er * 0.1),
          h,
          fill(withA(Colors.white)),
        );
        canvas.drawCircle(
          Offset(pcx + pr * 0.35, pcy + pr * 0.4 - er * 0.1),
          er * 0.14,
          fill(withA(Colors.white, 0.9)),
        );
      }
    }

    // Kaslar.
    if (brows != 0) {
      final bw = max(1.4, 0.06 * u);
      if (brows == 1) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(ex, ey - er * 1.7),
            width: er * 1.7,
            height: er * 0.9,
          ),
          pi * 1.15,
          pi * 0.7,
          false,
          line(browInk, bw),
        );
      } else {
        // Endiseli: ic uclar yukarida, dis uclar asagida.
        canvas.drawLine(
          Offset(ex + s * er, ey - er * 1.3),
          Offset(ex - s * er, ey - er * 1.9),
          line(browInk, bw),
        );
      }
    }

    // Yanak.
    final br = 0.13 * u;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + s * 0.64 * u, center.dy + 0.34 * u),
        width: br * 2.4,
        height: br * 1.6,
      ),
      fill(withA(const Color(0xFFFF6E96), cheekA)),
    );
  }

  // Agiz.
  final mc = Offset(center.dx, center.dy + 0.36 * u);
  final mw = max(1.5, 0.07 * u);

  // Dil (agzin altindan sarkar; once cizilir, gulus cizgisi ustune biner).
  // Yumusak gecis: [exprK] ile agizdan asagi dogru uzar / geri cekilir.
  if (tongue && exprK > 0.03) {
    final tw = 0.17 * u;
    final th = 0.22 * u * exprK;
    final top = mc.dy + 0.07 * u;
    final tr = RRect.fromRectAndRadius(
      Rect.fromLTWH(mc.dx + 0.02 * u - tw / 2, top, tw, th),
      Radius.circular(min(tw, th) / 2),
    );
    canvas.drawRRect(tr, fill(withA(const Color(0xFFFF7890))));
    canvas.drawLine(
      Offset(mc.dx + 0.02 * u, top + 0.05 * u * exprK),
      Offset(mc.dx + 0.02 * u, top + 0.15 * u * exprK),
      line(withA(const Color(0xFFD94F6B)), max(1.0, 0.025 * u)),
    );
  }

  switch (mouth) {
    case 0: // gulumseme
      canvas.drawArc(
        Rect.fromLTRB(mc.dx - 0.2 * u, mc.dy - 0.2 * u, mc.dx + 0.2 * u,
            mc.dy + 0.12 * u),
        pi * 0.1,
        pi * 0.8,
        false,
        line(mouthInk, mw),
      );
      break;
    case 1:
      {
        // acik gulumseme
        final m = 0.2 * u;
        final rect = Rect.fromLTRB(
            mc.dx - m, mc.dy - m * 0.9, mc.dx + m, mc.dy + m * 1.1);
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(
            mc.dx - m * 1.2, mc.dy, mc.dx + m * 1.2, mc.dy + m * 1.4));
        canvas.drawOval(rect, fill(withA(const Color(0xFF3A1428))));
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(mc.dx, mc.dy + m * 0.85),
              width: m * 1.0,
              height: m * 0.7),
          fill(withA(const Color(0xFFFF7890))),
        );
        canvas.restore();
        break;
      }
    case 2:
      {
        // kedi agzi (w)
        final m = 0.11 * u;
        for (final s in const [-1.0, 1.0]) {
          canvas.drawArc(
            Rect.fromLTRB(mc.dx + s * m - m, mc.dy - m * 0.9, mc.dx + s * m + m,
                mc.dy + m * 0.9),
            pi * 0.1,
            pi * 0.8,
            false,
            line(mouthInk, mw),
          );
        }
        break;
      }
    case 4:
      {
        // sasirma: acik "o"
        final m = 0.11 * u;
        final rect = Rect.fromCenter(
            center: Offset(mc.dx, mc.dy + 0.1 * u),
            width: m * 1.6,
            height: m * 2.4);
        canvas.drawOval(rect, fill(withA(const Color(0xFF3A1428))));
        canvas.drawOval(rect, line(mouthInk, max(1.0, 0.04 * u)));
        break;
      }
    case 5:
      {
        // endise: dalgali cizgi
        final w = 0.2 * u;
        final path = Path()
          ..moveTo(mc.dx - w, mc.dy + 0.08 * u)
          ..quadraticBezierTo(
              mc.dx - w / 2, mc.dy - 0.04 * u, mc.dx, mc.dy + 0.08 * u)
          ..quadraticBezierTo(
              mc.dx + w / 2, mc.dy + 0.2 * u, mc.dx + w, mc.dy + 0.08 * u);
        canvas.drawPath(path, line(mouthInk, mw));
        break;
      }
    default:
      {
        // kucuk "o" (utangac)
        final m = 0.09 * u;
        canvas.drawOval(
          Rect.fromLTRB(
              mc.dx - m, mc.dy - m * 0.2, mc.dx + m, mc.dy + m * 1.5),
          fill(mouthInk),
        );
      }
  }
}

/// Koleksiyon ekranindaki tum [PlanetFaced] widget'lari icin TEK ortak saat:
/// ~30 fps'te bir kez tetiklenir (kirpma/ifade icin yeterli), hic dinleyici
/// kalmayinca durur. Boylece her gezegen ayri 60 fps controller calistirmaz.
class _FaceClock extends ChangeNotifier {
  _FaceClock._();
  static final _FaceClock instance = _FaceClock._();

  Ticker? _ticker;
  int _refs = 0;
  int _lastMs = -1000;

  void attach() {
    _refs++;
    if (_refs == 1) {
      _lastMs = -1000;
      _ticker = Ticker(_onTick)..start();
    }
  }

  void detach() {
    _refs--;
    if (_refs <= 0) {
      _refs = 0;
      _ticker?.dispose();
      _ticker = null;
    }
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms - _lastMs >= 33) {
      _lastMs = ms;
      notifyListeners();
    }
  }
}

/// Gezegen gorselini yuzuyle birlikte gosteren widget (Koleksiyon vb.).
/// Gorsel ve yuz ayni kareye oturur; kutu kare degilse kisa kenar kullanilir.
/// Yuz canlidir: goz kirpar, ara sira dil cikarir / kirpistirir.
class PlanetFaced extends StatefulWidget {
  final int imageIndex;
  const PlanetFaced(this.imageIndex, {super.key});

  @override
  State<PlanetFaced> createState() => _PlanetFacedState();
}

class _PlanetFacedState extends State<PlanetFaced> {
  @override
  void initState() {
    super.initState();
    _FaceClock.instance.attach();
  }

  @override
  void dispose() {
    _FaceClock.instance.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(PlanetImages.assetPaths[widget.imageIndex],
            fit: BoxFit.contain),
        CustomPaint(
          painter: _FacePainter(widget.imageIndex, _FaceClock.instance),
        ),
      ],
    );
  }
}

class _FacePainter extends CustomPainter {
  final int imageIndex;
  _FacePainter(this.imageIndex, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    drawPlanetFace(
      canvas,
      imageIndex,
      Offset(size.width / 2, size.height / 2),
      min(size.width, size.height) / 2,
      seed: imageIndex * 7 + 3,
      timeSec: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) =>
      old.imageIndex != imageIndex;
}
