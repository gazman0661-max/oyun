import 'package:flutter/material.dart';
import '../models/food_order.dart';
import '../models/game_theme.dart';

/// Referans videodaki "To-Go Order" fişine benzer, gerçek illüstrasyon
/// (kullanıcının ürettiği "clipboard" asset'i) kullanan sipariş kartı.
/// Ortasında istenen objenin gerçek görseli, altında seviye ve coin
/// ödülü var.
///
/// [theme] parametresi ile hangi temanın (Fast Food / Kafe) obje
/// görsellerinin kullanılacağı dışarıdan veriliyor - eskiden burada
/// hep FoodTiers (Fast Food) sabit kullanılıyordu, bu yüzden Kafe
/// bölümlerinde bile burger/patates görselleri çıkardı.
class OrderCardView extends StatelessWidget {
  final FoodOrder order;
  final GameTheme theme;
  final bool deliverable;

  const OrderCardView({
    super.key,
    required this.order,
    required this.theme,
    this.deliverable = false,
  });

  @override
  Widget build(BuildContext context) {
    final tier = theme.byLevel(order.level);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: deliverable
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.55),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Gercek "clipboard" fis gorseli - kullanicinin urettigi asset.
          Positioned.fill(
            child: Image.asset(
              'assets/images/order_card_frame.webp',
              fit: BoxFit.contain,
            ),
          ),
          // Klips alanini atlayip kagit yuzeyinde ortalanan icerik.
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(tier.imagePath, width: 42, height: 42),
                const SizedBox(height: 2),
                Text(
                  order.anyAbove ? 'Lv${tier.level}+' : 'Lv${tier.level}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: order.anyAbove ? Colors.deepPurple : Colors.black87,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${order.reward} ',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    Image.asset('assets/images/coin_icon.webp', width: 12, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
