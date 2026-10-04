import '../widgets/ui_kit.dart';
import '../widgets/menu_fx.dart' show Bobbing;
import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/piggy.dart';
import '../services/game_fx.dart';
import '../services/billing_service.dart';

/// KUMBARA ekrani.
class PiggyScreen extends StatefulWidget {
  const PiggyScreen({super.key});

  @override
  State<PiggyScreen> createState() => _PiggyScreenState();
}

class _PiggyScreenState extends State<PiggyScreen> {
  final PiggyService _piggy = PiggyService.instance;

  @override
  void initState() {
    super.initState();
    BillingService.instance.addListener(_onBilling);
  }

  void _onBilling() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BillingService.instance.removeListener(_onBilling);
    super.dispose();
  }

  Future<void> _break() async {
    GameFx.instance.uiTap();
    if (!_piggy.canBreak) {
      GameFx.instance.denied();
      return;
    }
    final n = _piggy.gems; // kirilmadan onceki miktar (mesaj icin)
    final ok = await BillingService.instance.buy(context, PiggyService.productId); // kirma + bulut yedegi serviste
    if (!ok) return;
    GameFx.instance.reward();
    if (!mounted) return;
    setState(() {});
    final s = AppStrings.instance;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('💎 +$n  ${s.t('piggy_broken')}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final g = _piggy.gems;
    return GameScaffold(
      title: s.t('piggy_title'),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.pink.shade50, Colors.orange.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 210,
              child: Bobbing(
                amplitude: 6,
                child: Image.asset(
                  // Bos: uykulu; biraz dolu: karni hazineli; DOLU: kahkaha atan parlak ejderha.
                  _piggy.isFull
                      ? 'assets/images/ui/dragon_2.webp'
                      : (g < PiggyService.minToBreak ? 'assets/images/ui/dragon_0.webp' : 'assets/images/ui/dragon_1.webp'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('💎 $g', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                minHeight: 16,
                value: g / PiggyService.capacity,
                backgroundColor: Colors.pink.shade100,
                valueColor: AlwaysStoppedAnimation(Colors.pink.shade400),
              ),
            ),
            const SizedBox(height: 6),
            Text('$g / ${PiggyService.capacity}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              s.t('piggy_how'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 22),
            CandyButton(
              height: 60,
              fontSize: 17,
              style: CandyStyle.orange,
              label: _piggy.canBreak
                  ? '${s.t('piggy_break')}  ${BillingService.instance.priceOf(PiggyService.productId)}'
                  : '${s.t('piggy_need')} ${PiggyService.minToBreak} 💎',
              onTap: _piggy.canBreak ? _break : null,
            ),
            if (_piggy.isFull) ...[
              const SizedBox(height: 10),
              Text(s.t('piggy_full'), style: TextStyle(color: Colors.pink.shade700, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}
