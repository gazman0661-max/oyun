import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../theme/app_colors.dart';

/// Tek bir "coach mark" adimi: ekranda gercek bir widget'i (GlobalKey ile)
/// isaret edip, yaninda kisa bir aciklama balonu gosterir. `targetKey` null
/// birakilirsa (ornegin hedef widget henuz olusmadiysa) tum ekranin
/// ortasinda, spot isigi olmadan sadece aciklama balonu gosterilir.
class CoachStep {
  final GlobalKey? targetKey;
  final String title;
  final String body;
  /// Spot isigi sekli: true=daire (yuvarlak butonlar/alanlar icin),
  /// false=yuvarlatilmis dikdortgen (satir/kutu gibi genis alanlar icin).
  final bool circleShape;
  /// Hedefin etrafinda birakilacak ekstra bosluk (px).
  final double padding;
  /// DUZELTME: true ise bu adim METIN OKUYARAK degil, OYUNCUNUN GERCEKTEN
  /// BIR HAMLE YAPMASIYLA ilerler. Bu adimdayken overlay tum ekrani
  /// bloke etmeyi birakir (IgnorePointer) — spot isigi altindaki gercek
  /// oyun tahtasina dokunulabilir. "Ileri" butonu yerine bir bekleme
  /// ipucu gosterilir; oyuncu gercek bir hamle yapinca (bkz.
  /// [CoachOverlay.actionValue]) otomatik bir sonraki adima gecilir.
  /// Boylece "hangi yon" gibi soyut/metinle anlatilmasi zor kurallar,
  /// deneyerek (learning-by-doing) ogretilir — okuyup gecmek yerine.
  final bool waitForAction;

  const CoachStep({
    required this.title,
    required this.body,
    this.targetKey,
    this.circleShape = false,
    this.padding = 10,
    this.waitForAction = false,
  });
}

/// Adim adim ilerleyen, tam ekran kaplayan spot isigi ogretici overlay'i.
/// `Navigator.push` ile ayri bir route olarak degil, dogrudan `Overlay`
/// uzerinden gosterilir ki alttaki gercek oyun ekrani (ve GlobalKey'lerin
/// bagli oldugu widget agaci) canli/olculebilir kalsin.
///
/// Kullanim: `CoachOverlay.show(context, steps: [...])`. Kullanici "Ileri"ye
/// basarak ya da spot isiginin disina dokunarak ilerler; son adimda buton
/// "Anladim" yazisina doner ve overlay kapanir.
class CoachOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final VoidCallback? onFinished;
  /// DUZELTME: `waitForAction` adimlarinda dinlenecek gercek oyun sinyali
  /// (orn. OrbitController — zaten bir ChangeNotifier). Bu Listenable her
  /// tetiklendiginde [actionValue] tekrar okunur; adim baslarken alinan
  /// baseline'dan FARKLIYSA (yani oyuncu gercekten bir hamle yaptiysa)
  /// otomatik olarak bir sonraki adima gecilir.
  final Listenable? actionListenable;
  /// Su anki "ilerleme sayacini" dondurur (orn. `() => controller.rotations`).
  /// [actionListenable] ile birlikte kullanilir.
  final int Function()? actionValue;

  const CoachOverlay({
    super.key,
    required this.steps,
    this.onFinished,
    this.actionListenable,
    this.actionValue,
  });

  static OverlayEntry? _active;

  static void show(
    BuildContext context, {
    required List<CoachStep> steps,
    VoidCallback? onFinished,
    Listenable? actionListenable,
    int Function()? actionValue,
  }) {
    // Ayni anda tek bir coach overlay olabilir — cakismayi onler.
    _active?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => CoachOverlay(
        steps: steps,
        actionListenable: actionListenable,
        actionValue: actionValue,
        onFinished: () {
          entry.remove();
          _active = null;
          onFinished?.call();
        },
      ),
    );
    _active = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  @override
  State<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<CoachOverlay> {
  int _index = 0;
  int? _actionBaseline;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    widget.actionListenable?.addListener(_onAction);
    _captureBaselineIfNeeded();
  }

  @override
  void dispose() {
    widget.actionListenable?.removeListener(_onAction);
    super.dispose();
  }

  void _captureBaselineIfNeeded() {
    final step = widget.steps[_index];
    _actionBaseline = (step.waitForAction && widget.actionValue != null)
        ? widget.actionValue!()
        : null;
  }

  /// Gercek oyun durumu (orn. controller.rotations) her degistiginde
  /// cagrilir. Su anki adim bir hamle bekliyorsa VE deger baseline'dan
  /// farklilastiysa (oyuncu GERCEKTEN bir hamle yaptiysa), kisa bir
  /// gecikmeyle (hamlenin animasyonu/sonucu goruslsun diye) otomatik
  /// olarak sonraki adima gecer.
  void _onAction() {
    final step = widget.steps[_index];
    if (!step.waitForAction || widget.actionValue == null) return;
    if (_actionBaseline == null || _advancing) return;
    if (widget.actionValue!() == _actionBaseline) return;
    _advancing = true;
    Future.delayed(const Duration(milliseconds: 450), () {
      _advancing = false;
      _next();
    });
  }

  void _next() {
    if (!mounted) return;
    if (_index >= widget.steps.length - 1) {
      widget.onFinished?.call();
      return;
    }
    setState(() {
      _index++;
      _captureBaselineIfNeeded();
    });
  }

  Rect? _targetRect(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final rect = _targetRect(step.targetKey);
    final screen = MediaQuery.of(context).size;
    final isLast = _index == widget.steps.length - 1;
    // Sadece gercekten bir hamle bekleyen VE bunu dinleyebilecek bir
    // sinyali olan adimlarda "dokunmayi oyuna birak" moduna gecilir.
    final waiting = step.waitForAction && widget.actionValue != null;

    // Balon, spot isiginin altina mi ustune mi sigsin ona gore konumlanir.
    final bubbleBelow = rect == null || (rect.bottom + 160 < screen.height);
    final bubbleTop = rect == null
        ? screen.height / 2 - 80
        : (bubbleBelow ? rect.bottom + 16 : rect.top - 176);

    return Stack(
      children: [
        // DUZELTME: `waiting` true iken bu katman IgnorePointer ile
        // tamamen "seffaflastirilir" — dokunuslar overlay'in ALTINDAKI
        // gercek oyun tahtasina ulasir. Boylece oyuncu spot isigiyla
        // vurgulanan halkaya GERCEKTEN dokunup deneyebilir; okuyup
        // "Ileri"ye basmak yerine yaparak ogrenir.
        IgnorePointer(
          ignoring: waiting,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: waiting ? null : _next,
            child: Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  rect: rect == null ? null : rect.inflate(step.padding),
                  circleShape: step.circleShape,
                  pulse: waiting,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: bubbleTop.clamp(20, screen.height - 200),
          child: _Bubble(
            title: step.title,
            body: step.body,
            isLast: isLast,
            stepIndex: _index,
            stepCount: widget.steps.length,
            waiting: waiting,
            onNext: waiting ? null : _next,
            onSkip: waiting ? _next : null,
          ),
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? rect;
  final bool circleShape;
  /// DUZELTME: interaktif ("dene") adimlarda cerceveyi biraz daha
  /// kalin/parlak cizerek "burasi dokunulabilir" hissini guclendirir.
  final bool pulse;

  _SpotlightPainter({
    required this.rect,
    required this.circleShape,
    this.pulse = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final full = Path()..addRect(Offset.zero & size);
    if (rect == null) {
      canvas.drawPath(full, dim);
      return;
    }
    final hole = circleShape
        ? (Path()
          ..addOval(Rect.fromCircle(
              center: rect!.center, radius: rect!.longestSide / 2)))
        : (Path()
          ..addRRect(RRect.fromRectAndRadius(
              rect!, const Radius.circular(18))));
    final combined = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(combined, dim);
    // Spot isiginin kenarina ince, dikkat cekici bir cerceve. Interaktif
    // ("dene") adimlarda kalinlik ve parlaklik artirilir — "burasi
    // TIKLANABILIR/dokunulabilir" mesajini guclendirmek icin.
    final border = Paint()
      ..color = pulse ? AppColors.accent.withValues(alpha: 1.0) : AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = pulse ? 4 : 2.5;
    if (circleShape) {
      canvas.drawCircle(rect!.center, rect!.longestSide / 2, border);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect!, const Radius.circular(18)),
        border,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.circleShape != circleShape ||
      oldDelegate.pulse != pulse;
}

/// DUZELTME: interaktif coach adimlarinda gosterilen, surekli hafifce
/// nabiz gibi atan "dene" ipucu. Amaci: "buton degil, GERCEK oyun
/// tahtasi tiklanabilir" mesajini gorsel olarak da pekistirmek.
class _PulsingHintChip extends StatefulWidget {
  const _PulsingHintChip();

  @override
  State<_PulsingHintChip> createState() => _PulsingHintChipState();
}

class _PulsingHintChipState extends State<_PulsingHintChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = 0.55 + _controller.value * 0.45;
        return Opacity(opacity: v, child: child);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent),
        ),
        child: Text(
          t('coach_waitingHint'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String title;
  final String body;
  final bool isLast;
  final int stepIndex;
  final int stepCount;
  /// DUZELTME: `waiting` true iken asagida "Ileri" yerine bir bekleme
  /// ipucu gosterilir (bu adim gercek bir hamleyle otomatik ilerler).
  /// `onNext` null verilirse (waiting durumunda oldugu gibi) buton
  /// devre disi/gizli gorunur; `onSkip` verilirse kucuk bir "Atla"
  /// metni de eklenir — oyuncu kurali anlamis ve denemeden gecmek
  /// isterse takilip kalmasin diye bir kacis kapisi.
  final bool waiting;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;

  const _Bubble({
    required this.title,
    required this.body,
    required this.isLast,
    required this.stepIndex,
    required this.stepCount,
    this.onNext,
    this.onSkip,
    this.waiting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                ),
                Text(
                  '${stepIndex + 1}/$stepCount',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 14),
            if (waiting)
              // DUZELTME: Bu adimda "Ileri" butonu YOK — oyuncu gercek
              // oyun tahtasina dokunana kadar bekleniyor. Nabiz gibi
              // atan bir ipucu ile "buraya dokun" mesaji veriliyor,
              // takilirsa diye kucuk bir "Atla" kacis kapisi birakildi.
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _PulsingHintChip(),
                  if (onSkip != null) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding:
                            const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      ),
                      child: Text(
                        t('coach_skip'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onNext,
                  child: Text(
                    isLast ? t('coach_gotIt') : t('coach_next'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
