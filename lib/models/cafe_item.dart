import 'package:flutter/material.dart';

/// Tema 2 — Kafe & Pastane için 8 seviyelik birleştirme zinciri.
/// Aynı fizik/oynanış motoru, sadece görsel/isim/renk farklı.
class CafeTier {
  final int level;
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath;

  const CafeTier({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
  });

  double get radius => 20 + (level - 1) * 7;
}

class CafeTiers {
  CafeTiers._();

  static const int maxLevel = 8;
  static const String tableImagePath = 'assets/images/cafe/table_cafe.jpg';

  static const List<CafeTier> all = [
    CafeTier(
      level: 1,
      name: 'Kahve Çekirdeği',
      emoji: '☕',
      color: Color(0xFF6D4C41),
      coinReward: 1,
      imagePath: 'assets/images/cafe/cafe_tier_1.webp',
    ),
    CafeTier(
      level: 2,
      name: 'Espresso Fincanı',
      emoji: '☕',
      color: Color(0xFFE53935),
      coinReward: 2,
      imagePath: 'assets/images/cafe/cafe_tier_2.webp',
    ),
    CafeTier(
      level: 3,
      name: 'Köpüklü Cappuccino',
      emoji: '☕',
      color: Color(0xFFFFB74D),
      coinReward: 3,
      imagePath: 'assets/images/cafe/cafe_tier_3.webp',
    ),
    CafeTier(
      level: 4,
      name: 'Buzlu Latte',
      emoji: '🧊',
      color: Color(0xFF29B6F6),
      coinReward: 5,
      imagePath: 'assets/images/cafe/cafe_tier_4.webp',
    ),
    CafeTier(
      level: 5,
      name: 'Taze Kruvasan',
      emoji: '🥐',
      color: Color(0xFFFFA726),
      coinReward: 8,
      imagePath: 'assets/images/cafe/cafe_tier_5.webp',
    ),
    CafeTier(
      level: 6,
      name: 'Çilekli Dilim Pasta',
      emoji: '🍰',
      color: Color(0xFFEC407A),
      coinReward: 13,
      imagePath: 'assets/images/cafe/cafe_tier_6.webp',
    ),
    CafeTier(
      level: 7,
      name: 'Kremalı Dev Milkshake',
      emoji: '🥤',
      color: Color(0xFFAB47BC),
      coinReward: 21,
      imagePath: 'assets/images/cafe/cafe_tier_7.webp',
    ),
    CafeTier(
      level: 8,
      name: 'Çok Katlı Kutlama Pastası',
      emoji: '🎂',
      color: Color(0xFF26C6DA),
      coinReward: 34,
      imagePath: 'assets/images/cafe/cafe_tier_8.webp',
    ),
  ];

  static CafeTier byLevel(int level) => all[level - 1];
}
