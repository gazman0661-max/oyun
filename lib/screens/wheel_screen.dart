import '../widgets/ui_kit.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../models/lucky_wheel.dart';
import '../services/game_fx.dart';
import '../services/ad_service.dart';

/// SANS CARKI ekrani: gunde 1 bedava + 3 reklamli cevirme, 7 gun serisi.
class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key});

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen> with SingleTickerProviderStateMixin {
  static const int _n = 8;
  static const double _w = 2 * pi / _n;

  late final AnimationController _ctrl;
  final Random _rng = Random();
  double _from = 0; // animasyon basindaki aci
  double _delta = 0; // toplam donus
  double _angle = 0; // gosterilen aci
  int _lastTick = 0;
  bool _spinning = false;

  bool get _tr => AppStrings.instance.language == AppLanguage.tr;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800))
      ..addListener(() {
        final t = Curves.easeOutQuart.transform(_ctrl.value);
        final a = _from + _delta * t;
        final tick = ((a + _w / 2) / _w).floor();
        if (tick != _lastTick) {
          _lastTick = tick;
          GameFx.instance.uiTap(); // dilim gecerken "tik"
        }
        setState(() => _angle = a);
      });
  }

  @override
  void dispose() {
    // Cark donerken ekrandan cikilirsa odul kaybolmasin.
    GameProgress.instance.claimWheelPrize();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onSpin() async {
    if (_spinning) return;
    final gp = GameProgress.instance;
    var viaAd = false;
    if (!gp.canSpinWheelFree) {
      if (gp.wheelAdSpinsRemaining <= 0) {
        GameFx.instance.denied();
        return;
      }
      GameFx.instance.uiTap();
      final watched = await watchRewardedAd(context);
      if (!watched || !mounted) return;
      viaAd = true;
    }
    final result = gp.spinWheel(viaAd: viaAd);
    if (result == null) return;
    setState(() => _spinning = true);

    // Hedef: secilen dilimin merkezi yukaridaki isaretcinin altina gelsin.
    final jitter = (_rng.nextDouble() - 0.5) * _w * 0.6;
    final targetMod = _mod(-result.sliceIndex * _w + jitter, 2 * pi);
    final turns = 5 + _rng.nextInt(2); // 5-6 tam tur
    final delta = turns * 2 * pi + _mod(targetMod - _angle, 2 * pi);
    _from = _angle;
    _delta = delta;
    _lastTick = ((_angle + _w / 2) / _w).floor();
    await _ctrl.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _angle = _from + _delta;
    });
    gp.claimWheelPrize(); // odul ancak cark durunca bakiyeye eklenir
    final big = LuckyWheel.slices[result.sliceIndex].rare;
    if (big) {
      GameFx.instance.chapterComplete();
    } else {
      GameFx.instance.reward();
    }
    await _showResult(result);
    if (mounted) setState(() {});
  }

  static double _mod(double a, double b) => ((a % b) + b) % b;

  String _boosterName(BoosterType t) {
    switch (t) {
      case BoosterType.aimGuide:
        return _tr ? 'Nişan Rehberi' : 'Aim Guide';
      case BoosterType.joker:
        return 'Joker';
      case BoosterType.revive:
        return _tr ? 'Can Yenileme' : 'Revive';
    }
  }

  (String, String) _label(int i) {
    final s = LuckyWheel.slices[i];
    switch (s.kind) {
      case WheelKind.coins:
        return (s.rare ? '👑' : '🪙', '${s.amount}');
      case WheelKind.gems:
        return ('💎', '${s.amount}');
      case WheelKind.energy:
        return ('⚡', _tr ? 'Dolum' : 'Refill');
      case WheelKind.booster:
        return ('🎁', 'Booster');
    }
  }

  Future<void> _showResult(WheelResult r) async {
    final s = AppStrings.instance;
    final (emoji, _) = _label(r.sliceIndex);
    String prize;
    if (r.coins > 0) {
      prize = '🪙 ${r.coins}';
    } else if (r.gems > 0) {
      prize = '💎 ${r.gems}';
    } else if (r.energyFilled) {
      prize = _tr ? '⚡ Enerji tamamen doldu!' : '⚡ Energy fully refilled!';
    } else {
      prize = '🎁 ${_boosterName(r.booster!)}';
    }
    final rare = LuckyWheel.slices[r.sliceIndex].rare;
    await showDialog<void>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          rare ? s.t('wheel_big_win') : s.t('wheel_you_won'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 6),
            Text(prize, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            if (r.guaranteed) ...[
              const SizedBox(height: 8),
              Text(s.t('wheel_streak_bonus'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final gp = GameProgress.instance;
    final free = gp.canSpinWheelFree;
    final adLeft = gp.wheelAdSpinsRemaining;
    final size = min(MediaQuery.of(context).size.width - 40, 340.0);
    final streak = gp.currentWheelStreak;

    String btnText;
    Color btnColor;
    bool enabled = !_spinning;
    if (_spinning) {
      btnText = s.t('wheel_spinning');
      btnColor = Colors.grey.shade600;
    } else if (free) {
      btnText = '🎁 ${s.t('wheel_free_spin')}';
      btnColor = Colors.green.shade600;
    } else if (adLeft > 0) {
      btnText = '🎬 ${s.t('wheel_ad_spin')} ($adLeft/${GameProgress.wheelAdSpinsPerDay})';
      btnColor = Colors.orange.shade700;
    } else {
      btnText = '🌙 ${s.t('wheel_come_back')}';
      btnColor = Colors.grey.shade600;
      enabled = false;
    }

    return GameScaffold(
      title: s.t('wheel_title'),
      bodyColor: const Color(0xFF2B1B4D),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Center(
            child: SizedBox(
              width: size,
              height: size + 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 24,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.amber.shade700,
                        boxShadow: [
                          BoxShadow(color: Colors.amber.withOpacity(0.45), blurRadius: 24, spreadRadius: 2),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 24 + 9,
                    child: Transform.rotate(
                      angle: _angle,
                      child: CustomPaint(
                        size: Size(size - 18, size - 18),
                        painter: _WheelPainter(
                          colors: [for (final sl in LuckyWheel.slices) Color(sl.color)],
                          emojis: [for (var i = 0; i < _n; i++) _label(i).$1],
                          texts: [for (var i = 0; i < _n; i++) _label(i).$2],
                        ),
                      ),
                    ),
                  ),
                  // Merkez tusu
                  Positioned(
                    top: 24 + size / 2 - 34,
                    child: GestureDetector(
                      onTap: enabled ? _onSpin : null,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.amber.shade200],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.amber.shade800, width: 4),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
                        ),
                        alignment: Alignment.center,
                        child: const Text('🎡', style: TextStyle(fontSize: 30)),
                      ),
                    ),
                  ),
                  // Isaretci (ustte, asagi bakan ucgen)
                  Positioned(
                    top: 0,
                    child: CustomPaint(size: const Size(38, 46), painter: _PointerPainter()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          CandyButton(
            height: 60,
            fontSize: 18,
            style: btnColor == Colors.orange.shade700 ? CandyStyle.orange : CandyStyle.green,
            label: btnText,
            onTap: enabled ? _onSpin : null,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.t('wheel_streak')}: $streak/${GameProgress.wheelStreakTarget}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 1; i <= GameProgress.wheelStreakTarget; i++)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= streak ? Colors.amber.shade600 : Colors.white24,
                          border: i == GameProgress.wheelStreakTarget
                              ? Border.all(color: Colors.amberAccent, width: 2)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          i == GameProgress.wheelStreakTarget ? '🎁' : '$i',
                          style: TextStyle(
                            color: i <= streak ? Colors.brown.shade900 : Colors.white70,
                            fontWeight: FontWeight.w900,
                            fontSize: i == GameProgress.wheelStreakTarget ? 16 : 14,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(s.t('wheel_streak_info'), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ExpansionTile(
                iconColor: Colors.white,
                collapsedIconColor: Colors.white,
                title: Text(s.t('wheel_odds'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (var i = 0; i < _n; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Color(LuckyWheel.slices[i].color)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${_label(i).$1} ${_label(i).$2}',
                                style: const TextStyle(color: Colors.white)),
                          ),
                          Text('%${LuckyWheel.percentOf(i).toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (GameProgress.instance.townLevel(3) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(s.t('wheel_pirate_bonus'),
                          style: TextStyle(color: Colors.amber.shade200, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<Color> colors;
  final List<String> emojis;
  final List<String> texts;
  _WheelPainter({required this.colors, required this.emojis, required this.texts});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final n = colors.length;
    final w = 2 * pi / n;
    final rect = Rect.fromCircle(center: c, radius: r);

    for (var i = 0; i < n; i++) {
      final center = -pi / 2 + i * w;
      final paint = Paint()..color = colors[i];
      canvas.drawArc(rect, center - w / 2, w, true, paint);
      final edge = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawArc(rect, center - w / 2, w, true, edge);
    }

    for (var i = 0; i < n; i++) {
      final center = -pi / 2 + i * w;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(center + pi / 2);
      canvas.translate(0, -r * 0.66);
      final tp = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        text: TextSpan(
          children: [
            TextSpan(text: '${emojis[i]}\n', style: const TextStyle(fontSize: 26)),
            TextSpan(
              text: texts[i],
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))],
              ),
            ),
          ],
        ),
      )..layout(maxWidth: r * 0.6);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Ic halka (merkez tusa gecis)
    canvas.drawCircle(c, r * 0.20, Paint()..color = Colors.white.withOpacity(0.25));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => false;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 4)
      ..quadraticBezierTo(size.width / 2, -6, size.width, 4)
      ..close();
    canvas.drawShadow(path, Colors.black, 4, true);
    canvas.drawPath(path, Paint()..color = Colors.red.shade600);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => false;
}
