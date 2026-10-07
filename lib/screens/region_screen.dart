import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../models/game_theme.dart';
import '../models/town.dart';
import '../services/game_fx.dart';
import '../utils/duration_format.dart';
import '../widgets/game_board.dart';
import '../widgets/gem_dialogs.dart';
import '../widgets/menu_fx.dart';
import '../widgets/ui_kit.dart';

/// Bir bolume giris: yetki + enerji kontrolu, sonra oyun sahnesi.
Future<void> openChapterFlow(BuildContext context, int chapter) async {
  final gp = GameProgress.instance;
  if (chapter > gp.maxUnlockedChapter) {
    GameFx.instance.denied();
    return;
  }
  GameFx.instance.uiTap();
  if (!gp.hasEnergy) {
    showNoEnergyDialog(context, onChanged: () {});
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GameBoard(
        theme: ChapterConfig.themeFor(chapter),
        chapterNumber: chapter,
        chapterGoal: ChapterConfig.goalFor(chapter),
      ),
    ),
  );
}

/// Bolge basina bolum sayisi (dunya blogu = 8 bolum).
int get kChaptersPerRegion => TownCatalog.chaptersPerWorldBlock;

int regionOfChapter(int chapter) => (chapter - 1) ~/ kChaptersPerRegion + 1;
int firstChapterOfRegion(int region) => (region - 1) * kChaptersPerRegion + 1;

/// Ust cubukta enerji rozeti: "3/5" + dolu degilse geri sayim.
/// Kendi 1 sn'lik zamanlayicisiyla yenilenir: eskiden `const EnergyPill()` olarak kullanildigi icin
/// ust ekran yeniden cizilse bile rozet ESKI degerde takili kaliyordu (haritada 5/5, ana menude 4/5).
class EnergyPill extends StatefulWidget {
  const EnergyPill({super.key});

  @override
  State<EnergyPill> createState() => _EnergyPillState();
}

class _EnergyPillState extends State<EnergyPill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = GameProgress.instance;
    final energy = progress.energy;
    final full = energy >= GameProgress.maxEnergy;
    final remaining = progress.timeUntilNextEnergy;
    return GlassPill(
      borderColor: Colors.amber.shade300,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/ui/bolt.webp', width: 18, height: 18),
          const SizedBox(width: 2),
          Text('$energy/${GameProgress.maxEnergy}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
          if (!full && remaining != null) ...[
            const SizedBox(width: 6),
            Text(formatCountdown(remaining), style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

/// BOLGE EKRANI: dunyanin arka plani uzerinde 8 bolum dugumu, yol boyunca.
class RegionScreen extends StatefulWidget {
  final int region;
  const RegionScreen({super.key, required this.region});

  @override
  State<RegionScreen> createState() => _RegionScreenState();
}

/// 8 dugumun ekran icindeki konumu (0..1, alttan uste yilanvari).
const List<Offset> _kNodePos = [
  Offset(0.30, 0.90),
  Offset(0.70, 0.79),
  Offset(0.32, 0.68),
  Offset(0.70, 0.57),
  Offset(0.30, 0.46),
  Offset(0.68, 0.35),
  Offset(0.34, 0.24),
  Offset(0.62, 0.12),
];

class _RegionScreenState extends State<RegionScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _play(int chapter) async {
    await openChapterFlow(context, chapter);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final gp = GameProgress.instance;
    final s = AppStrings.instance;
    final tr = s.language == AppLanguage.tr;
    final region = widget.region;
    final first = firstChapterOfRegion(region);
    final last = first + kChaptersPerRegion - 1;
    final world = TownCatalog.worldOfChapter(first);
    final theme = ChapterConfig.themeFor(first);
    final bg = kMenuBackgroundImages[world];
    final maxUnlocked = gp.maxUnlockedChapter;
    var stars = 0;
    for (var c = first; c <= last; c++) {
      stars += gp.starsFor(c);
    }
    final target = maxUnlocked.clamp(first, last).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF2A0F5C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (bg != null) Image.asset(bg, fit: BoxFit.cover, alignment: Alignment.center),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xAA000000), Color(0x33000000), Color(0x22000000), Color(0x99000000)],
                stops: [0.0, 0.3, 0.65, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  child: Row(
                    children: [
                      GlassCircleButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () {
                          GameFx.instance.uiTap();
                          Navigator.of(context).maybePop();
                        },
                      ),
                      Expanded(
                        child: Center(child: RibbonTitle(text: '${tr ? 'Bölge' : 'Region'} $region', height: 58)),
                      ),
                      const EnergyPill(),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFE082), Color(0xFFFFB300)]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.t(theme.themeNameKey),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF5D2E00)),
                      ),
                      const SizedBox(width: 10),
                      Image.asset('assets/images/ui/star_full.webp', width: 18, height: 18),
                      const SizedBox(width: 3),
                      Text('$stars/${kChaptersPerRegion * 3}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF5D2E00))),
                    ],
                  ),
                ),
                // Dugumler
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    final w = box.maxWidth;
                    final h = box.maxHeight - 84; // alttaki buton icin pay
                    final pts = [for (final p in _kNodePos) Offset(p.dx * w, 8 + p.dy * h)];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _RegionPathPainter(pts, first, maxUnlocked)),
                        ),
                        for (var i = 0; i < pts.length; i++)
                          Positioned(
                            left: pts[i].dx - 44,
                            top: pts[i].dy - 44,
                            width: 88,
                            height: 88,
                            child: _RegionNode(
                              chapter: first + i,
                              maxUnlocked: maxUnlocked,
                              stars: gp.starsFor(first + i),
                              onTap: () => _play(first + i),
                            ),
                          ),
                      ],
                    );
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 14),
                  child: CandyButton(
                    label: '${s.t('play')}  •  ${s.chapterLabel(target)}',
                    icon: Icons.play_arrow_rounded,
                    height: 58,
                    fontSize: 20,
                    pulse: true,
                    onTap: () => _play(target),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek bolum dugumu: yuvarlak, numarali, yildizli.
class _RegionNode extends StatelessWidget {
  final int chapter;
  final int maxUnlocked;
  final int stars;
  final VoidCallback onTap;
  const _RegionNode({required this.chapter, required this.maxUnlocked, required this.stars, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final locked = chapter > maxUnlocked;
    final completed = chapter < maxUnlocked;
    final current = chapter == maxUnlocked;
    final kind = ChapterConfig.kindFor(chapter);
    final List<Color> colors = locked
        ? const [Color(0xFFA9B3C6), Color(0xFF6A768F)]
        : completed
            ? const [Color(0xFFFFE082), Color(0xFFFF9800)]
            : const [Color(0xFF9CF25B), Color(0xFF3CC13A)];
    final Color edge = locked
        ? const Color(0xFF3E4860)
        : completed
            ? const Color(0xFF9A4A00)
            : const Color(0xFF1B7A2A);

    Widget circle = Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
        border: Border.all(color: Colors.white, width: 3.5),
        boxShadow: [
          BoxShadow(color: edge, offset: const Offset(0, 5)),
          if (current) BoxShadow(color: const Color(0xFF9CF25B).withOpacity(0.75), blurRadius: 20, spreadRadius: 3),
        ],
      ),
      alignment: Alignment.center,
      child: locked
          ? Image.asset('assets/images/ui/lock.webp', width: 30, height: 30)
          : Text(
              '${localChapterNumber(chapter)}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black38, offset: Offset(0, 2), blurRadius: 2)],
              ),
            ),
    );
    if (current) circle = Bobbing(amplitude: 3, duration: const Duration(milliseconds: 1300), child: circle);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          circle,
          if (kind == ChapterKind.boss) const Positioned(top: -6, child: Text('👑', style: TextStyle(fontSize: 22))),
          if (kind == ChapterKind.easy) const Positioned(top: 2, right: 2, child: Text('🌿', style: TextStyle(fontSize: 18))),
          if (!locked && stars > 0)
            Positioned(
              bottom: -8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (i) => Image.asset(
                    i < stars ? 'assets/images/ui/star_full.webp' : 'assets/images/ui/star_empty.webp',
                    width: 17,
                    height: 17,
                  ),
                ),
              ),
            ),
          if (current)
            Positioned(
              top: -16,
              child: Bobbing(
                amplitude: 4,
                duration: const Duration(milliseconds: 800),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
                  ),
                  child: Text(
                    s.t('play'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1B7A2A)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dugumleri baglayan kesikli yol: gidilen kisim altin, gidilmemis kisim soluk beyaz.
class _RegionPathPainter extends CustomPainter {
  final List<Offset> pts;
  final int firstChapter;
  final int maxUnlocked;
  const _RegionPathPainter(this.pts, this.firstChapter, this.maxUnlocked);

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, min(d + 10, m.length)), paint);
        d += 20;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    Paint mk(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w
      ..color = c;
    final shadow = mk(Colors.black.withOpacity(0.35), 12);
    final gold = mk(const Color(0xFFFFD54F), 7);
    final dim = mk(Colors.white.withOpacity(0.5), 7);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final mid = Offset((a.dx + b.dx) / 2 + (i.isEven ? -28 : 28), (a.dy + b.dy) / 2);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      final walked = (firstChapter + i + 1) <= maxUnlocked;
      _dashed(canvas, path, shadow);
      _dashed(canvas, path, walked ? gold : dim);
    }
  }

  @override
  bool shouldRepaint(covariant _RegionPathPainter old) => old.maxUnlocked != maxUnlocked || old.firstChapter != firstChapter;
}
