import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/album.dart';
import '../models/game_progress.dart';
import '../models/town.dart';
import '../services/game_fx.dart';
import '../utils/duration_format.dart';
import '../widgets/menu_fx.dart' show Bobbing;
import '../widgets/ui_kit.dart';

/// KASABA: 6 dunyanin binasini haritada goren, kaydirilip yakinlastirilan
/// bir ada. Her bina seviyesine gore pasif COIN URETIR (depoda birikir,
/// dokunarak toplanir) ve ayrica kalici bir bonus verir.

/// Ozel bina gorseli (assets/images/town/b{dunya}_s{1..3}.webp) HAZIR olan dunyalar.
/// Yeni dunya gorselleri eklenince sadece bu kumeye numarasini ekle; olmayan
/// dunyalar eski obje (tier) gorseliyle cizilmeye devam eder.
const Set<int> _kBuildingArtWorlds = {0, 1, 2, 3, 4, 5};

/// Seviye 1-3 -> s1, 4-7 -> s2, 8-10 -> s3 (seviye 0'da s1 silueti kullanilir).
String _buildingImage(int world, int level) {
  if (_kBuildingArtWorlds.contains(world)) {
    final stage = level <= 3 ? 1 : (level <= 7 ? 2 : 3);
    return 'assets/images/town/b${world}_s$stage.webp';
  }
  return AlbumCatalog.themes[world].byLevel(_TownScreenState._tierFor(level)).imagePath;
}

const double _kCanvasW = 400;
const double _kCanvasH = 860;

/// 6 dunya binasinin harita uzerindeki merkez noktalari (altta 0 -> ustte 5).
const List<Offset> _kPlots = [
  Offset(120, 740),
  Offset(280, 610),
  Offset(120, 480),
  Offset(280, 350),
  Offset(120, 220),
  Offset(280, 100),
];

class _Deco {
  final String emoji;
  final double x;
  final double y;
  final double size;
  final int minTotal; // 0 = hep gorunur; >0 = toplam kasaba seviyesi bu olunca acilir
  const _Deco(this.emoji, this.x, this.y, this.size, [this.minTotal = 0]);
}

const List<_Deco> _kDecos = [
  _Deco('🌳', 30, 820, 46),
  _Deco('🌲', 368, 842, 46),
  _Deco('🌴', 40, 545, 42),
  _Deco('🌳', 355, 520, 42),
  _Deco('🌲', 40, 420, 44),
  _Deco('🌳', 360, 440, 40),
  _Deco('🌲', 30, 245, 42),
  _Deco('🌳', 368, 262, 44),
  _Deco('🌲', 40, 120, 40),
  _Deco('🌳', 368, 40, 44),
  _Deco('🍄', 75, 640, 22),
  _Deco('🌾', 372, 600, 26),
  // Kasaba buyudukce acilan dekorlar (kilitliyken silik siluet gorunur).
  _Deco('🌷', 62, 590, 26, 3),
  _Deco('🌻', 338, 478, 28, 6),
  _Deco('⛲', 335, 790, 50, 12),
  _Deco('🎠', 335, 690, 48, 22),
  _Deco('🎡', 62, 675, 54, 30),
  _Deco('🏰', 335, 200, 52, 45),
  _Deco('🗽', 60, 325, 50, 55),
];

/// Kalan insaat suresi: "2g 5sa", "3sa 12dk" veya "07:42".
String _fmtRemain(Duration d, bool tr) {
  final total = d.inSeconds.clamp(0, 1 << 30).toInt();
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final mins = (total % 3600) ~/ 60;
  final secs = total % 60;
  if (days > 0) return tr ? '${days}g ${hours}sa' : '${days}d ${hours}h';
  if (hours > 0) return tr ? '${hours}sa ${mins}dk' : '${hours}h ${mins}m';
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

class _Pop {
  final int id;
  final int world;
  final int amount;
  const _Pop(this.id, this.world, this.amount);
}

class TownScreen extends StatefulWidget {
  const TownScreen({super.key});

  @override
  State<TownScreen> createState() => _TownScreenState();
}

class _TownScreenState extends State<TownScreen> {
  bool get _tr => AppStrings.instance.language == AppLanguage.tr;

  Timer? _timer;
  final TransformationController _tc = TransformationController();
  bool _viewInit = false;
  final List<_Pop> _pops = [];
  int _popId = 0;

  @override
  void initState() {
    super.initState();
    // Biriken coin sayaclari canli aksin diye saniyede bir yenile.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      GameProgress.instance.tickTownUpgrades();
      if (GameProgress.instance.pendingTownResults.isNotEmpty) _drainResults();
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GameProgress.instance.tickTownUpgrades();
      if (GameProgress.instance.pendingTownResults.isNotEmpty) _drainResults();
    });
  }

  bool _showingResult = false;

  /// Biten insaatlarin sonuc (kutlama) diyaloglarini sirayla gosterir.
  Future<void> _drainResults() async {
    if (_showingResult) return;
    _showingResult = true;
    final gp = GameProgress.instance;
    while (mounted && gp.pendingTownResults.isNotEmpty) {
      final r = gp.pendingTownResults.removeAt(0);
      GameFx.instance.reward();
      await _showUpgradeDialog(r);
    }
    _showingResult = false;
    if (mounted) setState(() {});
  }

  static String _fmtMin(int m, bool tr) {
    if (m < 60) return tr ? '$m dk' : '$m min';
    if (m < 1440) {
      final h = m / 60;
      final hs = m % 60 == 0 ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
      return tr ? '$hs sa' : '$hs h';
    }
    final d = m ~/ 1440;
    final h = (m % 1440) ~/ 60;
    return tr ? '$d g${h > 0 ? ' $h sa' : ''}' : '$d d${h > 0 ? ' $h h' : ''}';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _showBuilderDialog() {
    GameFx.instance.uiTap();
    final gp = GameProgress.instance;
    final maxed = gp.builderCount >= TownCatalog.maxBuilders;
    showDialog<void>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(_tr ? '🔨 İnşaatçılar' : '🔨 Builders',
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(
          (_tr
                  ? 'İnşaatçı sayısı kadar bina aynı anda yükseltilebilir.\nŞu an: ${gp.townBusyBuilders}/${gp.builderCount} meşgul.'
                  : 'You can upgrade as many buildings at once as you have builders.\nRight now: ${gp.townBusyBuilders}/${gp.builderCount} busy.') +
              (maxed ? (_tr ? '\n\nEn fazla inşaatçıya ulaştın!' : '\n\nYou have the maximum builders!') : ''),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (!maxed)
            FilledButton(
              onPressed: gp.gems >= gp.nextBuilderGemCost
                  ? () {
                      if (GameProgress.instance.buyBuilder()) {
                        GameFx.instance.reward();
                        Navigator.of(ctx).pop();
                        setState(() {});
                        _snack(_tr ? 'Yeni inşaatçı işe başladı!' : 'New builder hired!');
                      }
                    }
                  : null,
              child: Text(_tr
                  ? 'İnşaatçı #${gp.builderCount + 1}  💎 ${gp.nextBuilderGemCost}'
                  : 'Builder #${gp.builderCount + 1}  💎 ${gp.nextBuilderGemCost}'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(_tr ? 'Kapat' : 'Close')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tc.dispose();
    super.dispose();
  }

  /// Harita ilk acilista genislige sigar ve ALT kismi (ilk bina) gosterir.
  void _initView(double w, double h) {
    if (_viewInit) return;
    _viewInit = true;
    final scale = (w / _kCanvasW).clamp(0.5, 2.0).toDouble();
    final ty = min(0.0, h - _kCanvasH * scale);
    _tc.value = Matrix4.diagonal3Values(scale, scale, 1.0)..setTranslationRaw(0.0, ty, 0.0);
  }

  void _addPop(int world, int amount) {
    final id = _popId++;
    _pops.add(_Pop(id, world, amount));
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      setState(() => _pops.removeWhere((p) => p.id == id));
    });
  }

  void _collect(int world) {
    final amt = GameProgress.instance.collectTown(world);
    if (amt <= 0) return;
    GameFx.instance.reward();
    _addPop(world, amt);
    setState(() {});
  }

  void _collectAll() {
    final gp = GameProgress.instance;
    var total = 0;
    for (var w = 0; w < TownCatalog.worldCount; w++) {
      final amt = gp.collectTown(w);
      if (amt > 0) {
        total += amt;
        _addPop(w, amt);
      }
    }
    if (total > 0) {
      GameFx.instance.reward();
    } else {
      GameFx.instance.denied();
    }
    setState(() {});
  }

  void _openBuilding(int w) {
    GameFx.instance.uiTap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final gp = GameProgress.instance;
        final pending = gp.townPending(w);
        final cap = gp.townCapacity(w);
        final rate = gp.townCoinsPerHour(w);
        return PanelFrame(
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(3)),
                  ),
                  if (rate > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade400, width: 2),
                      ),
                      child: Row(
                        children: [
                          const Text('📦', style: TextStyle(fontSize: 30)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (_tr ? 'Depo' : 'Storage') + ': $pending / $cap',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: cap <= 0 ? 0.0 : (pending / cap).clamp(0.0, 1.0).toDouble(),
                                    minHeight: 10,
                                    backgroundColor: Colors.amber.shade100,
                                    valueColor: AlwaysStoppedAnimation(
                                        pending >= cap ? Colors.deepOrange : Colors.amber.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: pending > 0
                                ? () {
                                    Navigator.of(ctx).pop();
                                    _collect(w);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(_tr ? 'Topla' : 'Collect',
                                style: const TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    ),
                  if (gp.townIsUpgrading(w))
                    _BuildStatus(
                      world: w,
                      tr: _tr,
                      onSkipped: () {
                        Navigator.of(ctx).pop();
                        _drainResults();
                      },
                    ),
                  _BuildingCard(
                    world: w,
                    tr: _tr,
                    onUpgrade: () {
                      Navigator.of(ctx).pop();
                      _upgrade(w);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _upgrade(int world) async {
    final gp = GameProgress.instance;
    if (gp.townIsMax(world)) return;
    if (!gp.townWorldUnlocked(world)) {
      GameFx.instance.denied();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(_tr
              ? 'Bu bina, dünyaya ulaşınca (Bölüm ${gp.townUnlockChapter(world)}) açılır'
              : 'Unlocks when you reach this world (Chapter ${gp.townUnlockChapter(world)})'),
          duration: const Duration(seconds: 2),
        ));
      return;
    }
    if (gp.townIsUpgrading(world)) return;
    if (!gp.townHasFreeBuilder) {
      GameFx.instance.denied();
      _snack(_tr
          ? 'Tüm inşaatçılar meşgul! Bir inşaatı bitir veya yeni inşaatçı al.'
          : 'All builders are busy! Finish a build or hire a builder.');
      return;
    }
    if (!gp.startTownUpgrade(world)) {
      GameFx.instance.denied();
      final s = AppStrings.instance;
      _snack(!gp.townStarsOk(world) ? s.t('town_need_stars') : s.t('town_need_coins'));
      return;
    }
    GameFx.instance.reward();
    setState(() {});
    _snack(_tr
        ? '🏗️ İnşaat başladı! Süre: ${_fmtMin(gp.townUpgradeMinutes(world), true)}'
        : '🏗️ Construction started! Time: ${_fmtMin(gp.townUpgradeMinutes(world), false)}');
  }

  Future<void> _showUpgradeDialog(TownUpgradeResult r) async {
    final s = AppStrings.instance;
    final theme = AlbumCatalog.themes[r.world];
    final tier = _tierFor(r.newLevel);
    final perk = TownCatalog.perks[r.world];
    await showDialog<void>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          '${s.t('town_b${r.world}')} • ${s.t('level_of')} ${r.newLevel}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(_buildingImage(r.world, r.newLevel), width: 120, height: 120),
            const SizedBox(height: 8),
            Text(s.t('town_upgraded'),
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(TownCatalog.perkText(perk, r.newLevel, _tr),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 6),
            Text(
                _tr
                    ? 'Üretim: 🪙 ${TownCatalog.coinsPerHour(r.world, r.newLevel)}/sa'
                    : 'Output: 🪙 ${TownCatalog.coinsPerHour(r.world, r.newLevel)}/h',
                style: TextStyle(fontWeight: FontWeight.w800, color: Colors.amber.shade800, fontSize: 15)),
            for (final m in r.milestones) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade600, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏆 ${s.t('town_milestone_reward')} (${m.totalLevel})',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text([
                      if (m.coins > 0) '🪙 ${m.coins}',
                      if (m.gems > 0) '💎 ${m.gems}',
                    ].join('   '), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () {
              GameFx.instance.uiTap();
              Navigator.of(ctx).pop();
            },
            child: Text(s.t('town_ok')),
          ),
        ],
      ),
    );
  }

  /// Bina seviyesine gore gosterilen obje kademesi (1-8): bina buyudukce
  /// dunyanin daha ust seviye objesi sergilenir.
  static int _tierFor(int level) {
    if (level <= 0) return 1;
    return ((level * 8 + TownCatalog.maxLevel - 1) ~/ TownCatalog.maxLevel).clamp(1, 8).toInt();
  }

  Widget _buildCanvas(int total) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(child: CustomPaint(painter: _TerrainPainter())),
        for (final d in _kDecos)
          Positioned(
            left: d.x - d.size / 2 - 8,
            top: d.y - d.size / 2 - 8,
            child: _DecoView(deco: d, unlocked: total >= d.minTotal),
          ),
        for (var w = 0; w < TownCatalog.worldCount; w++)
          _MapBuilding(
            world: w,
            tr: _tr,
            onTap: () => _openBuilding(w),
            onCollect: () => _collect(w),
          ),
        for (final p in _pops)
          Positioned(
            key: ValueKey('pop_${p.id}'),
            left: _kPlots[p.world].dx - 60,
            top: _kPlots[p.world].dy - 150,
            width: 120,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1200),
                builder: (context, v, child) => Opacity(
                  opacity: v < 0.6 ? 1.0 : (1.0 - (v - 0.6) / 0.4).clamp(0.0, 1.0).toDouble(),
                  child: Transform.translate(offset: Offset(0, -60 * v), child: child),
                ),
                child: Text(
                  '+${p.amount} 🪙',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [Shadow(color: Color(0xFF7A4A00), blurRadius: 4, offset: Offset(0, 2))],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final gp = GameProgress.instance;
    final total = gp.totalTownLevel;
    final nextIdx = gp.townMilestoneIdx;
    final hasNext = nextIdx < TownCatalog.milestones.length;
    final next = hasNext ? TownCatalog.milestones[nextIdx] : null;
    final prevTotal = nextIdx == 0 ? 0 : TownCatalog.milestones[nextIdx - 1].totalLevel;
    final pendingTotal = gp.townPendingTotal;
    final perHour = gp.townCoinsPerHourTotal;

    return Scaffold(
      backgroundColor: const Color(0xFF56B85C),
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(builder: (context, box) {
              _initView(box.maxWidth, box.maxHeight);
              return InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                minScale: 0.5,
                maxScale: 2.5,
                boundaryMargin: const EdgeInsets.all(60),
                child: SizedBox(width: _kCanvasW, height: _kCanvasH, child: _buildCanvas(total)),
              );
            }),
          ),
          // ── Ust: geri + unvan/ilerleme + coin/mucevher ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            GameFx.instance.uiTap();
                            Navigator.of(context).maybePop();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.4),
                            ),
                            child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.t('town_rank_${TownCatalog.rankIndex(total)}'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    Text('$total/${TownCatalog.maxTotalLevel}',
                                        style: const TextStyle(
                                            color: Colors.amberAccent, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: next == null
                                        ? 1.0
                                        : ((total - prevTotal) / (next.totalLevel - prevTotal))
                                            .clamp(0.0, 1.0)
                                            .toDouble(),
                                    minHeight: 8,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  next == null
                                      ? s.t('town_all_done')
                                      : '${s.t('town_next_reward')} (${next.totalLevel}): '
                                          '${next.coins > 0 ? '🪙 ${next.coins}  ' : ''}${next.gems > 0 ? '💎 ${next.gems}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: _showBuilderDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: gp.townHasFreeBuilder ? Colors.lightGreenAccent : Colors.white54, width: 1.4),
                              ),
                              child: Text('🔨 ${gp.townBusyBuilders}/${gp.builderCount}  +',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.amber.shade300, width: 1.4),
                            ),
                            child: Text('🪙 ${gp.coins}    💎 ${gp.gems}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Alt: saatlik gelir + HEPSINI TOPLA ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.42),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        perHour > 0
                            ? (_tr ? '⏱ Toplam üretim: 🪙 $perHour/saat' : '⏱ Total output: 🪙 $perHour/hour')
                            : (_tr
                                ? 'Bir bina yükselt, coin üretmeye başlasın!'
                                : 'Upgrade a building to start producing coins!'),
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CandyButton(
                      label: pendingTotal > 0
                          ? (_tr ? 'Hepsini Topla  🪙 +$pendingTotal' : 'Collect All  🪙 +$pendingTotal')
                          : (_tr ? 'Depolar boş' : 'Storage empty'),
                      height: 58,
                      fontSize: 19,
                      pulse: pendingTotal > 0,
                      onTap: pendingTotal > 0 ? _collectAll : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zemin: cimen gradyani, hafif lekeler ve binalari birbirine baglayan toprak yol.
class _TerrainPainter extends CustomPainter {
  const _TerrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FE07A), Color(0xFF56B85C)],
        ).createShader(rect),
    );
    final rnd = Random(3);
    final patch = Paint();
    for (var i = 0; i < 38; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 26 + rnd.nextDouble() * 40;
      patch.color = (i.isEven ? Colors.white : Colors.green.shade900).withOpacity(0.05 + rnd.nextDouble() * 0.05);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 1.2), patch);
    }
    final pts = <Offset>[Offset(size.width / 2, size.height), ..._kPlots];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final my = (a.dy + b.dy) / 2;
      path.cubicTo(a.dx, my, b.dx, my, b.dx, b.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 56
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFC79A5B),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 46
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFE9CD94),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DecoView extends StatelessWidget {
  final _Deco deco;
  final bool unlocked;
  const _DecoView({required this.deco, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      deco.emoji,
      style: TextStyle(
        fontSize: deco.size,
        shadows: [Shadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 3))],
      ),
    );
    if (unlocked) return text;
    // Kilitli dekor: hedef gostermek icin silik siluet.
    return Opacity(
      opacity: 0.18,
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
        child: text,
      ),
    );
  }
}

/// Haritadaki tek bir bina: platform + bina gorseli + isim/seviye + coin balonu.
class _MapBuilding extends StatelessWidget {
  final int world;
  final bool tr;
  final VoidCallback onTap;
  final VoidCallback onCollect;
  const _MapBuilding({required this.world, required this.tr, required this.onTap, required this.onCollect});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final gp = GameProgress.instance;
    final level = gp.townLevel(world);
    final unlocked = gp.townWorldUnlocked(world);
    final pending = gp.townPending(world);
    final full = gp.townStorageFull(world);
    final canUp = gp.canUpgradeTown(world);
    final upgrading = gp.townIsUpgrading(world);
    final remaining = gp.townUpgradeRemaining(world);
    final theme = AlbumCatalog.themes[world];
    final imagePath = _buildingImage(world, level);
    final pos = _kPlots[world];

    // Seviye 0 (henuz kurulmamis): siluet yerine INSAAT ALANI gorseli.
    Widget image = Image.asset(level == 0 ? 'assets/images/town/ruin.webp' : imagePath, fit: BoxFit.contain);

    return Positioned(
      left: pos.dx - 72,
      top: pos.dy - 118,
      width: 144,
      height: 178,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: unlocked ? 1.0 : 0.62,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Platform (arsa)
              Positioned(
                left: 14,
                right: 14,
                bottom: 40,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFE0D2AE), Color(0xFFA88B5B)]),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white.withOpacity(0.75), width: 2.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                ),
              ),
              // Bina
              Positioned(
                left: 20,
                right: 20,
                top: 36,
                height: 104,
                child: Bobbing(
                  amplitude: 3,
                  duration: Duration(milliseconds: 1800 + world * 230),
                  child: image,
                ),
              ),
              if (upgrading && level > 0)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 64,
                  child: Center(child: Text('🏗️', style: TextStyle(fontSize: 34))),
                ),
              if (!unlocked)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 60,
                  child: Center(child: Image.asset('assets/images/ui/lock.webp', width: 36, height: 36)),
                ),
              // Isim + seviye
              Positioned(
                left: 4,
                right: 4,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.teal.shade300, width: 1.6),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.t('town_b$world'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF4A2C0A)),
                      ),
                      Text(
                        upgrading
                            ? '⏳ ${_fmtRemain(remaining, tr)}'
                            : (level >= TownCatalog.maxLevel ? s.t('town_max') : 'Lv $level/${TownCatalog.maxLevel}'),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.teal.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              // Coin balonu (dokun -> topla)
              if (pending > 0)
                Positioned(
                  top: 0,
                  left: 8,
                  right: 8,
                  height: 36,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onCollect,
                      child: Bobbing(
                        amplitude: 4,
                        duration: const Duration(milliseconds: 900),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFFFE082), Color(0xFFFFB300)]),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: full ? Colors.deepOrange : Colors.white, width: 2.2),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 2))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset('assets/images/coin_icon.webp', width: 16, height: 16),
                              const SizedBox(width: 4),
                              Text(
                                full ? '$pending  MAX' : '$pending',
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF5D2E00)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Yukseltme yapilabilir oku
              if (canUp)
                Positioned(
                  right: 4,
                  top: 46,
                  child: Bobbing(
                    amplitude: 5,
                    duration: const Duration(milliseconds: 800),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.green.shade500,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final int world;
  final bool tr;
  final VoidCallback onUpgrade;

  const _BuildingCard({required this.world, required this.tr, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final gp = GameProgress.instance;
    final level = gp.townLevel(world);
    final isMax = gp.townIsMax(world);
    final perk = TownCatalog.perks[world];
    final theme = AlbumCatalog.themes[world];
    final imagePath = _buildingImage(world, level);
    final unlocked = gp.townWorldUnlocked(world);
    final starsOk = gp.townStarsOk(world);
    final coinsOk = gp.coins >= gp.townUpgradeCost(world);

    // Harabe: insaat alani gorseli (siluet degil)
    final Widget image = Image.asset(level == 0 ? 'assets/images/town/ruin.webp' : imagePath, width: 84, height: 84, fit: BoxFit.contain);

    final rateNow = TownCatalog.coinsPerHour(world, level);
    final rateNext = TownCatalog.coinsPerHour(world, level + 1);
    final prodText = (tr ? 'Üretim' : 'Output') +
        ': 🪙 $rateNow/' +
        (tr ? 'sa' : 'h') +
        (isMax ? '' : '  →  $rateNext');

    final upgrading = gp.townIsUpgrading(world);
    String buttonLabel;
    bool enabled = true;
    CandyStyle bStyle = CandyStyle.green;
    if (!unlocked) {
      final ch = gp.townUnlockChapter(world);
      buttonLabel = tr ? '🔒 Bölüm $ch\'de açılır' : '🔒 Unlocks at Chapter $ch';
      enabled = false;
    } else if (isMax) {
      buttonLabel = s.t('town_max');
      enabled = false;
    } else if (upgrading) {
      buttonLabel = tr ? '⏳ İnşaat sürüyor' : '⏳ Under construction';
      enabled = false;
    } else if (!starsOk) {
      buttonLabel = '🔒 ⭐ ${gp.worldStars(world)}/${gp.townStarsNeeded(world)}';
      enabled = false;
    } else {
      buttonLabel = '🪙 ${gp.townUpgradeCost(world)}';
      bStyle = coinsOk ? CandyStyle.green : CandyStyle.orange;
    }

    return Opacity(
      opacity: unlocked ? 1.0 : 0.6,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked ? Colors.white : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: level == 0 ? Colors.grey.shade300 : Colors.teal.shade200, width: 2),
      ),
      child: Row(
        children: [
          SizedBox(width: 84, height: 84, child: image),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('town_b$world'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(s.t(theme.themeNameKey),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (var i = 1; i <= TownCatalog.maxLevel; i++)
                      Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= level ? Colors.teal.shade500 : Colors.grey.shade300,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${s.t('town_perk_now')}: ${TownCatalog.perkText(perk, level, tr)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (!isMax && unlocked)
                  Text('${s.t('town_perk_next')}: ${TownCatalog.perkText(perk, level + 1, tr)}',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                const SizedBox(height: 2),
                Text(prodText,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.amber.shade800)),
                if (!isMax && unlocked && !upgrading) ...[
                  const SizedBox(height: 2),
                  Text(
                    '⏱ ${tr ? 'Süre' : 'Time'}: ${_TownScreenState._fmtMin(gp.townUpgradeMinutes(world), tr)}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.blueGrey.shade600),
                  ),
                ],
                const SizedBox(height: 8),
                CandyButton(
                  height: 46,
                  fontSize: 15,
                  style: bStyle,
                  label: buttonLabel,
                  onTap: enabled ? onUpgrade : null,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

/// Bottom sheet icinde: devam eden insaatin geri sayimi + "Hizlandir" butonu.
class _BuildStatus extends StatefulWidget {
  final int world;
  final bool tr;
  final VoidCallback onSkipped;
  const _BuildStatus({required this.world, required this.tr, required this.onSkipped});

  @override
  State<_BuildStatus> createState() => _BuildStatusState();
}

class _BuildStatusState extends State<_BuildStatus> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = GameProgress.instance;
    final w = widget.world;
    final tr = widget.tr;
    if (!gp.townIsUpgrading(w)) return const SizedBox.shrink();
    final rem = gp.townUpgradeRemaining(w);
    final totalSec = max(1, gp.townUpgradeMinutes(w) * 60);
    final progress = (1 - rem.inSeconds / totalSec).clamp(0.0, 1.0).toDouble();
    final cost = gp.townSkipCost(w);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade300, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('🏗️', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr ? 'İnşaat sürüyor' : 'Under construction',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              Text(_fmtRemain(rem, tr),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.blue.shade800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.blue.shade100,
              valueColor: AlwaysStoppedAnimation(Colors.blue.shade600),
            ),
          ),
          const SizedBox(height: 10),
          CandyButton(
            height: 46,
            fontSize: 16,
            style: CandyStyle.blue,
            label: cost == 0
                ? (tr ? 'Hemen Bitir (ücretsiz)' : 'Finish now (free)')
                : (tr ? 'Hızlandır  💎 $cost' : 'Speed up  💎 $cost'),
            onTap: gp.gems >= cost
                ? () {
                    if (GameProgress.instance.skipTownUpgrade(w)) {
                      GameFx.instance.reward();
                      widget.onSkipped();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
