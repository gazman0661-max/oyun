import 'package:flutter/material.dart';

/// Tema 3 — Büyü & Simya için 8 seviyelik birleştirme (merge) zinciri.
/// Aynı fizik/oynanış motoru, sadece görsel/isim/renk farklı (diğer
/// iki temayla birebir aynı desen: FoodTier/CafeTier'e bakınız).
class MagicTier {
  final int level;
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath;

  const MagicTier({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
  });

  double get radius => 20 + (level - 1) * 7;
}

class MagicTiers {
  MagicTiers._();

  static const int maxLevel = 8;
  static const String tableImagePath = 'assets/images/magic/table_magic.jpg';

  static const List<MagicTier> all = [
    MagicTier(
      level: 1,
      name: 'Büyülü Kristal',
      emoji: '🔷',
      color: Color(0xFF1E88E5),
      coinReward: 1,
      imagePath: 'assets/images/magic/magic_tier_1.webp',
    ),
    MagicTier(
      level: 2,
      name: 'İyileştirme İksiri',
      emoji: '🧪',
      color: Color(0xFFE53935),
      coinReward: 2,
      imagePath: 'assets/images/magic/magic_tier_2.webp',
    ),
    MagicTier(
      level: 3,
      name: 'Girdap İksiri',
      emoji: '🌀',
      color: Color(0xFF00ACC1),
      coinReward: 3,
      imagePath: 'assets/images/magic/magic_tier_3.webp',
    ),
    MagicTier(
      level: 4,
      name: 'Büyücü Şapkası',
      emoji: '🎩',
      color: Color(0xFF5E35B1),
      coinReward: 5,
      imagePath: 'assets/images/magic/magic_tier_4.webp',
    ),
    MagicTier(
      level: 5,
      name: 'Kadim Büyü Kitabı',
      emoji: '📖',
      color: Color(0xFFFFB300),
      coinReward: 8,
      imagePath: 'assets/images/magic/magic_tier_5.webp',
    ),
    MagicTier(
      level: 6,
      name: 'Ejderha Yumurtası',
      emoji: '🥚',
      color: Color(0xFFFB8C00),
      coinReward: 13,
      imagePath: 'assets/images/magic/magic_tier_6.webp',
    ),
    MagicTier(
      level: 7,
      name: 'Kehanet Küresi',
      emoji: '🔮',
      color: Color(0xFF8E24AA),
      coinReward: 21,
      imagePath: 'assets/images/magic/magic_tier_7.webp',
    ),
    MagicTier(
      level: 8,
      name: 'Kaynayan Simya Kazanı',
      emoji: '⚗️',
      color: Color(0xFF6D4C41),
      coinReward: 34,
      imagePath: 'assets/images/magic/magic_tier_8.webp',
    ),
  ];

  static MagicTier byLevel(int level) => all[level - 1];
}
