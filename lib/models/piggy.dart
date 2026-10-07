import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'game_progress.dart';

/// KUMBARA: oynadikca dolan mucevher havuzu. Oyuncu belli bir miktara
/// ulasinca tek seferlik odemeyle kirar ve icindeki tum mucevheri alir.
///
/// Sabitler asagida; urun ID'si [productId]; fiyat Play Billing'den gelir
/// (services/billing_service.dart). Icerik oyuncuya acikca gosterilir.
/// Kaydi kendi anahtariyla ('piggy_v1') tutar.
class PiggyService {
  PiggyService._();
  static final PiggyService instance = PiggyService._();

  static const String productId = 'piggy_bank';
  static const int capacity = 500; // en fazla bu kadar birikir
  static const int minToBreak = 250; // kirilabilmesi icin gereken en az miktar
  static const int perOrder = 1;
  static const int perChapter = 5;
  static const int perMerge = 0;

  static const String _key = 'piggy_v1';
  int gems = 0;

  bool get isFull => gems >= capacity;
  bool get canBreak => gems >= minToBreak;

  void add(int amount) {
    if (amount <= 0 || gems >= capacity || !GameProgress.instance.piggyUnlocked) return;
    gems = (gems + amount).clamp(0, capacity).toInt();
    save();
  }

  /// Odeme basariliysa cagrilir: icindekini oyuncuya verir, kumbarayi bosaltir.
  int breakOpen() {
    if (!canBreak) return 0;
    final n = gems;
    gems = 0;
    GameProgress.instance.addGems(n);
    save();
    return n;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        gems = (j['gems'] as int? ?? 0).clamp(0, capacity).toInt();
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode({'gems': gems}));
    } catch (_) {}
  }
}
