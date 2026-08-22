import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// HTML'deki playRocketLaunch(): 3 yildizla bitirince ~1.2sn suren kisa bir
/// "roket kalkisi" kutlamasi oynatir, sonra otomatik kapanir.
Future<void> playRocketLaunch(BuildContext context) async {
  await showGeneralDialog(
    context: context,
    barrierColor: Colors.black87,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, anim1, anim2) => const _RocketLaunchView(),
    transitionBuilder: (ctx, anim, secAnim, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _RocketLaunchView extends StatefulWidget {
  const _RocketLaunchView();

  @override
  State<_RocketLaunchView> createState() => _RocketLaunchViewState();
}

class _RocketLaunchViewState extends State<_RocketLaunchView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();
    Future.delayed(const Duration(milliseconds: 1750), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0.65),
                  radius: 1.1,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.35),
                    AppColors.spaceTop.withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              // 0->0.3: hafif sallanma, 0.3->1: yukari firlama + kucultme
              final riseT = Curves.easeIn.transform(
                  ((t - 0.15) / 0.85).clamp(0.0, 1.0).toDouble());
              final dy = -riseT * size.height * 1.25;
              final scale = 1 - riseT * 0.55;
              return Transform.translate(
                offset: Offset(0, dy + size.height * 0.06),
                child: Transform.scale(
                  scale: scale.clamp(0.4, 1.0).toDouble(),
                  child: child,
                ),
              );
            },
            child: Transform.rotate(
              // 🚀 emoji varsayilan olarak yaklasik 45° capraz duruyor;
              // burada dondurerek dikey (yukari) baksin diye duzeltiyoruz.
              angle: -math.pi / 4,
              child: const Text('🚀', style: TextStyle(fontSize: 64)),
            ),
          ),
          FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _controller,
                curve: const Interval(0.05, 0.35, curve: Curves.easeOut),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 0),
              child: Align(
                alignment: Alignment(0, -0.55),
                child: Text('⭐⭐⭐', style: TextStyle(fontSize: 32)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
