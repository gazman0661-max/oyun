import 'package:flutter/material.dart';

/// Tema 5 — Buz Krallığı için 8 seviyelik birleştirme (merge) zinciri.
/// Aynı fizik/oynanış motoru, sadece görsel/isim/renk farklı (diğer
/// temalarla birebir aynı desen: FoodTier/CafeTier/MagicTier/PirateTier'e bakınız).
class IceTier {
  final int level;
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath;

  const IceTier({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
  });

  double get radius => 20 + (level - 1) * 7;
}

class IceTiers {
  IceTiers._();

  static const int maxLevel = 8;
  static const String tableImagePath = 'assets/images/ice/table_ice.jpg';

  static const List<IceTier> all = [
    IceTier(
      level: 1,
      name: 'Buz Küpü',
      emoji: '🧊',
      color: Color(0xFF4FC3F7),
      coinReward: 1,
      imagePath: 'assets/images/ice/ice_tier_1.webp',
    ),
    IceTier(
      level: 2,
      name: 'Kar Tanesi',
      emoji: '❄️',
      color: Color(0xFF29B6F6),
      coinReward: 2,
      imagePath: 'assets/images/ice/ice_tier_2.webp',
    ),
    IceTier(
      level: 3,
      name: 'Buz Kristali',
      emoji: '💎',
      color: Color(0xFF7C4DFF),
      coinReward: 3,
      imagePath: 'assets/images/ice/ice_tier_3.webp',
    ),
    IceTier(
      level: 4,
      name: 'Buz Çanı',
      emoji: '🔔',
      color: Color(0xFF00ACC1),
      coinReward: 5,
      imagePath: 'assets/images/ice/ice_tier_4.webp',
    ),
    IceTier(
      level: 5,
      name: 'Buz Ayısı',
      emoji: '🐻‍❄️',
      color: Color(0xFF0288D1),
      coinReward: 8,
      imagePath: 'assets/images/ice/ice_tier_5.webp',
    ),
    IceTier(
      level: 6,
      name: 'Buz Tahtı',
      emoji: '🪑',
      color: Color(0xFF039BE5),
      coinReward: 13,
      imagePath: 'assets/images/ice/ice_tier_6.webp',
    ),
    IceTier(
      level: 7,
      name: 'Buz Ejderhası',
      emoji: '🐉',
      color: Color(0xFF1565C0),
      coinReward: 21,
      imagePath: 'assets/images/ice/ice_tier_7.webp',
    ),
    IceTier(
      level: 8,
      name: 'Buz Kraliçesi Tacı',
      emoji: '👑',
      color: Color(0xFFB3E5FC),
      coinReward: 34,
      imagePath: 'assets/images/ice/ice_tier_8.webp',
    ),
  ];

  static IceTier byLevel(int level) => all[level - 1];
}
