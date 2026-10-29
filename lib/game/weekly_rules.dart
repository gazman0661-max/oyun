import '../services/network_time_service.dart';

/// Haftalik kural (Sonsuz Mod): her hafta (Pazartesi 00:00 UTC) tek bir
/// degisken oyunu farkli hissettirir. 6 kural sirayla doner; tum oyuncularda
/// ayni hafta ayni kural gecerlidir. Haftanin rekoru da bu kurala gore tutulur.
///
/// Alanlarin hepsi opsiyoneldir; verilmeyen deger oyunun varsayilanini kullanir.
class WeeklyRule {
  final String icon;
  final String titleKey;
  final String descKey;

  /// Yercekimi (varsayilan 15) / ziplama (varsayilan 0.05) /
  /// tehlike cizgisi y (varsayilan 24; buyudukce kabin daralir).
  final double? gravity;
  final double? restitution;
  final double? dangerY;

  /// Zorluk egrisini (0..1) bu araliga sikistirir. giants: 0.65'ten baslar,
  /// relax: en fazla 0.4'e cikar.
  final double difficultyMin;
  final double difficultyMax;

  /// Combo bonusu carpani ve combo penceresi (sn).
  final double comboBonusMult;
  final double? comboWindow;

  const WeeklyRule({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    this.gravity,
    this.restitution,
    this.dangerY,
    this.difficultyMin = 0.0,
    this.difficultyMax = 1.0,
    this.comboBonusMult = 1.0,
    this.comboWindow,
  });
}

class WeeklyRules {
  static const List<WeeklyRule> all = [
    WeeklyRule(
      icon: '🌙',
      titleKey: 'rule_lowGravity',
      descKey: 'rule_lowGravity_desc',
      gravity: 8,
    ),
    WeeklyRule(
      icon: '📏',
      titleKey: 'rule_narrow',
      descKey: 'rule_narrow_desc',
      dangerY: 44,
    ),
    WeeklyRule(
      icon: '🪐',
      titleKey: 'rule_giants',
      descKey: 'rule_giants_desc',
      difficultyMin: 0.65,
    ),
    WeeklyRule(
      icon: '🏀',
      titleKey: 'rule_bouncy',
      descKey: 'rule_bouncy_desc',
      restitution: 0.3,
    ),
    WeeklyRule(
      icon: '⚡',
      titleKey: 'rule_combo',
      descKey: 'rule_combo_desc',
      comboBonusMult: 2.0,
      comboWindow: 2.6,
    ),
    WeeklyRule(
      icon: '🍃',
      titleKey: 'rule_relax',
      descKey: 'rule_relax_desc',
      difficultyMax: 0.4,
    ),
  ];

  /// 2024-01-01 bir Pazartesi: hafta numarasi Pazartesi'den baslar.
  static int weekNumber(DateTime utc) =>
      utc.difference(DateTime.utc(2024, 1, 1)).inDays ~/ 7;

  static WeeklyRule forWeek(int week) => all[week.abs() % all.length];

  static WeeklyRule current() =>
      forWeek(weekNumber(NetworkTimeService.instance.nowUtc()));
}
