import 'package:flutter/material.dart';

/// Bölüm 1 - Fast Food Dükkanı için 8 seviyelik birleştirme (merge) zinciri.
/// Her seviye bir öncekinden hem görsel hem "hacim" olarak daha büyük
/// gösterilecek şekilde tasarlandı (Altın Kural 1: Ölçekleme).
class FoodTier {
  final int level; // 1..8
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath; // gercek illustrasyon asset yolu

  const FoodTier({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
  });

  /// Tahtadaki görsel boyut çarpanı. Seviye 1 küçük durur,
  /// Seviye 8 hücrenin neredeyse tamamını kaplar.
  double get scale => 0.55 + (level - 1) * 0.065;

  /// Fizik tahtasında bu objenin dairesel yarıçapı (px). Seviye arttıkça
  /// belirgin şekilde büyür (Altın Kural 1: Ölçekleme).
  double get radius => 20 + (level - 1) * 7;
}

class FoodTiers {
  FoodTiers._();

  static const int maxLevel = 8;

  /// Altın Kural 2 (Renk Kontrastı): art arda gelen seviyeler bilerek
  /// birbirinden tamamen farklı tonlarda seçildi, tahta 1 saniyede
  /// okunabilsin diye.
  static const List<FoodTier> all = [
    FoodTier(
      level: 1,
      name: 'Tekli Patates Kızartması',
      emoji: '🍟',
      color: Color(0xFFFFC107),
      coinReward: 1,
      imagePath: 'assets/images/tier_1.webp',
    ),
    FoodTier(
      level: 2,
      name: 'Kutu Patates',
      emoji: '🥡',
      color: Color(0xFFE53935),
      coinReward: 2,
      imagePath: 'assets/images/tier_2.webp',
    ),
    FoodTier(
      level: 3,
      name: 'Soğan Halkası Tabağı',
      emoji: '🧅',
      color: Color(0xFF43A047),
      coinReward: 3,
      imagePath: 'assets/images/tier_3.webp',
    ),
    FoodTier(
      level: 4,
      name: 'Tek Katlı Cheeseburger',
      emoji: '🍔',
      color: Color(0xFF5E35B1),
      coinReward: 5,
      imagePath: 'assets/images/tier_4.webp',
    ),
    FoodTier(
      level: 5,
      name: 'Çift Katlı Big Burger',
      emoji: '🍔',
      color: Color(0xFFFB8C00),
      coinReward: 8,
      imagePath: 'assets/images/tier_5.webp',
    ),
    FoodTier(
      level: 6,
      name: 'Pizza Dilimi',
      emoji: '🍕',
      color: Color(0xFF1E88E5),
      coinReward: 13,
      imagePath: 'assets/images/tier_6.webp',
    ),
    FoodTier(
      level: 7,
      name: 'Tam Boy Büyük Pizza',
      emoji: '🍕',
      color: Color(0xFFD81B60),
      coinReward: 21,
      imagePath: 'assets/images/tier_7.webp',
    ),
    FoodTier(
      level: 8,
      name: 'Dev Ziyafet Menüsü Tepsisi',
      emoji: '🍱',
      color: Color(0xFF00897B),
      coinReward: 34,
      imagePath: 'assets/images/tier_8.webp',
    ),
  ];

  static FoodTier byLevel(int level) => all[level - 1];
}
