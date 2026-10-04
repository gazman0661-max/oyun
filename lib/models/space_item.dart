import 'package:flutter/material.dart';

/// Tema 6 — Uzay İstasyonu için 8 seviyelik birleştirme (merge) zinciri.
/// Aynı fizik/oynanış motoru, sadece görsel/isim/renk farklı (diğer
/// temalarla birebir aynı desen: FoodTier/CafeTier/MagicTier/PirateTier/
/// IceTier'a bakınız).
class SpaceTier {
  final int level;
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath;

  const SpaceTier({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
  });

  double get radius => 20 + (level - 1) * 7;
}

class SpaceTiers {
  SpaceTiers._();

  static const int maxLevel = 8;
  static const String tableImagePath = 'assets/images/space/table_space.jpg';

  static const List<SpaceTier> all = [
    SpaceTier(
      level: 1,
      name: 'Uzay Cıvatası',
      emoji: '🔩',
      color: Color(0xFF29B6F6),
      coinReward: 1,
      imagePath: 'assets/images/space/space_tier_1.webp',
    ),
    SpaceTier(
      level: 2,
      name: 'Devre Kartı',
      emoji: '💾',
      color: Color(0xFF00E676),
      coinReward: 2,
      imagePath: 'assets/images/space/space_tier_2.webp',
    ),
    SpaceTier(
      level: 3,
      name: 'Enerji Kristali',
      emoji: '💠',
      color: Color(0xFF00E5FF),
      coinReward: 3,
      imagePath: 'assets/images/space/space_tier_3.webp',
    ),
    SpaceTier(
      level: 4,
      name: 'Keşif Drone\'u',
      emoji: '🚁',
      color: Color(0xFF2979FF),
      coinReward: 5,
      imagePath: 'assets/images/space/space_tier_4.webp',
    ),
    SpaceTier(
      level: 5,
      name: 'Astro Robot',
      emoji: '🤖',
      color: Color(0xFF1E88E5),
      coinReward: 8,
      imagePath: 'assets/images/space/space_tier_5.webp',
    ),
    SpaceTier(
      level: 6,
      name: 'Siber Kask',
      emoji: '🪖',
      color: Color(0xFF76FF03),
      coinReward: 13,
      imagePath: 'assets/images/space/space_tier_6.webp',
    ),
    SpaceTier(
      level: 7,
      name: 'Kozmik Muhafız',
      emoji: '🛡️',
      color: Color(0xFF00C853),
      coinReward: 21,
      imagePath: 'assets/images/space/space_tier_7.webp',
    ),
    SpaceTier(
      level: 8,
      name: 'Yıldız Gemisi',
      emoji: '🛸',
      color: Color(0xFF00BFA5),
      coinReward: 34,
      imagePath: 'assets/images/space/space_tier_8.webp',
    ),
  ];

  static SpaceTier byLevel(int level) => all[level - 1];
}
