/// Bölüm 2: Müşteri siparişi. Belirli bir seviyedeki objeyi tahtadan
/// teslim edince coin ödülü kazandırır. Her an birkaç açık sipariş var,
/// biri tamamlanınca yerine yenisi gelir.
///
/// KURAL SIPARISI ([anyAbove] = true): "Lv N ve ustu herhangi bir obje".
/// Odul, teslim edilen objenin seviyesine gore verilir ([bonusPercent] ek).
class FoodOrder {
  final int id;
  final int level;
  final int reward;
  final bool anyAbove;

  const FoodOrder({
    required this.id,
    required this.level,
    required this.reward,
    this.anyAbove = false,
  });

  static const int bonusPercent = 25;

  bool accepts(int ballLevel) => anyAbove ? ballLevel >= level : ballLevel == level;
}
