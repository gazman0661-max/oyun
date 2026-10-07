import 'package:flutter/material.dart';

/// Tema 4 — Korsan Hazinesi için 8 seviyelik birleştirme (merge) zinciri.
/// Aynı fizik/oynanış motoru, sadece görsel/isim/renk farklı (diğer
/// temalarla birebir aynı desen: FoodTier/CafeTier/MagicTier'e bakınız).
class PirateTier {
  final int level;
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath;

  const PirateTier({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
  });

  double get radius => 20 + (level - 1) * 7;
}

class PirateTiers {
  PirateTiers._();

  static const int maxLevel = 8;
  static const String tableImagePath = 'assets/images/pirate/table_pirate.jpg';

  static const List<PirateTier> all = [
    PirateTier(
      level: 1,
      name: 'Altın Dublon',
      emoji: '🪙',
      color: Color(0xFFFFB300),
      coinReward: 1,
      imagePath: 'assets/images/pirate/pirate_tier_1.webp',
    ),
    PirateTier(
      level: 2,
      name: 'Kaptan Pusulası',
      emoji: '🧭',
      color: Color(0xFF00897B),
      coinReward: 2,
      imagePath: 'assets/images/pirate/pirate_tier_2.webp',
    ),
    PirateTier(
      level: 3,
      name: 'Define Haritası',
      emoji: '🗺️',
      color: Color(0xFF6D4C41),
      coinReward: 3,
      imagePath: 'assets/images/pirate/pirate_tier_3.webp',
    ),
    PirateTier(
      level: 4,
      name: 'Mücevherli Korsan Kılıcı',
      emoji: '🗡️',
      color: Color(0xFF1E88E5),
      coinReward: 5,
      imagePath: 'assets/images/pirate/pirate_tier_4.webp',
    ),
    PirateTier(
      level: 5,
      name: 'Konuşan Papağan',
      emoji: '🦜',
      color: Color(0xFFE53935),
      coinReward: 8,
      imagePath: 'assets/images/pirate/pirate_tier_5.webp',
    ),
    PirateTier(
      level: 6,
      name: 'Korsan Gemisi',
      emoji: '🚢',
      color: Color(0xFF3949AB),
      coinReward: 13,
      imagePath: 'assets/images/pirate/pirate_tier_6.webp',
    ),
    PirateTier(
      level: 7,
      name: 'Mücevher Dolu Define Sandığı',
      emoji: '💰',
      color: Color(0xFF8D6E63),
      coinReward: 21,
      imagePath: 'assets/images/pirate/pirate_tier_7.webp',
    ),
    PirateTier(
      level: 8,
      name: 'Derin Deniz Kralı Tacı',
      emoji: '👑',
      color: Color(0xFFFDD835),
      coinReward: 34,
      imagePath: 'assets/images/pirate/pirate_tier_8.webp',
    ),
  ];

  static PirateTier byLevel(int level) => all[level - 1];
}
