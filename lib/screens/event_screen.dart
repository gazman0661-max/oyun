import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/season.dart';
import '../models/weekly_event.dart';
import '../services/game_fx.dart';

/// HAFTALIK ETKINLIK ekrani.
class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  final WeeklyEvent _ev = WeeklyEvent.instance;

  String _left(Duration d) {
    final tr = AppStrings.instance.language == AppLanguage.tr;
    return tr ? '${d.inDays}g ${d.inHours % 24}s' : '${d.inDays}d ${d.inHours % 24}h';
  }

  String _rewardText(SeasonReward r) {
    final p = <String>[];
    if (r.coins > 0) p.add('🪙${r.coins}');
    if (r.gems > 0) p.add('💎${r.gems}');
    if (r.booster != null) p.add('🎁×${r.boosterCount}');
    return p.join('  ');
  }

  void _claim(int i) {
    if (_ev.claim(i) != null) GameFx.instance.reward();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final k = _ev.kind.name;
    final targets = _ev.targets;
    return GameScaffold(
      title: s.t('event_title'),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.deepOrange.shade400, Colors.red.shade400]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('event_${k}_name'),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(s.t('event_${k}_desc'), style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('${_ev.points}', style: const TextStyle(color: Colors.amberAccent, fontSize: 30, fontWeight: FontWeight.w900)),
                    Text(' / ${targets.last}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    const Spacer(),
                    const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text(_left(_ev.timeLeft), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_ev.isWeekend) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(10)),
                    child: Text('⚡ ${s.t('event_weekend')}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < targets.length; i++) _milestone(i, targets[i]),
        ],
      ),
    );
  }

  Widget _milestone(int i, int target) {
    final s = AppStrings.instance;
    final claimed = _ev.isClaimed(i);
    final can = _ev.canClaim(i);
    final p = (_ev.points / target).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: claimed ? Colors.grey.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: can ? Colors.green : Colors.orange.shade200, width: can ? 3 : 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${s.t('event_goal')}: $target', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(_rewardText(WeeklyEvent.rewards[i]), style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: p,
                    backgroundColor: Colors.orange.shade100,
                    valueColor: AlwaysStoppedAnimation(claimed ? Colors.grey : Colors.deepOrange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (claimed)
            const Icon(Icons.check_circle, color: Colors.green, size: 32)
          else
            CandyButton(
              width: 96,
              height: 42,
              fontSize: 13,
              label: s.t('mission_claim'),
              onTap: can ? () => _claim(i) : null,
            ),
        ],
      ),
    );
  }
}
