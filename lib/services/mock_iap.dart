import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';

/// GEÇİCİ / YER TUTUCU: Gerçek bir ödeme SDK'sı (in_app_purchase paketi +
/// Google Play Console'da tanımlı ürün ID'leri) henüz bağlı değil.
///
/// [kIapMockEnabled] true iken "satın alma" sadece bir TEST onay kutusu
/// gösterip mücevheri BEDAVA verir. Yayına çıkmadan önce:
///   1) `in_app_purchase` paketini ekle, ürün ID'lerini ([GemPack.id])
///      Play Console'da oluştur,
///   2) [mockPurchase] içini gerçek satın alma akışıyla değiştir
///      (ödeme başarılı olunca true dön),
///   3) [kIapMockEnabled] değerini false yap.
/// false iken mockPurchase hiçbir şey vermez (güvenli varsayılan).
///
/// ŞU AN: false -> satın almalar KİLİTLİ. Fiyat gösterilmez (kilit simgesi),
/// dokununca "yakında" mesajı çıkar, hiçbir ürün verilmez. Billing eklenince
/// fiyatlar [iapPrice] üzerinden Play Billing'den çekilecek.
const bool kIapMockEnabled = false;

/// Butonlarda gösterilecek fiyat metni. Billing yokken fiyat gizlenir.
/// TODO(billing): ProductDetails.price (Play'den gelen yerel fiyat) döndür.
String iapPrice(String fallbackLabel) => kIapMockEnabled ? fallbackLabel : '🔒';

class GemPack {
  final String id;
  final int gems;
  final String priceLabel;
  final bool best;
  const GemPack(this.id, this.gems, this.priceLabel, {this.best = false});
}

/// Başlangıç paketi: tek seferlik. İçeriği GameProgress.grantStarterPack.
const GemPack kStarterPack = GemPack('starter_pack', 150, '\$1.99');

const List<GemPack> kGemPacks = [
  GemPack('gems_80', 80, '\$0.99'),
  GemPack('gems_300', 300, '\$2.99'),
  GemPack('gems_550', 550, '\$4.99', best: true),
  GemPack('gems_1200', 1200, '\$9.99'),
  GemPack('gems_2600', 2600, '\$19.99'),
  GemPack('gems_7000', 7000, '\$49.99'),
];

/// Satın almayı dener; başarılıysa true döner.
Future<bool> mockPurchase(BuildContext context, GemPack pack) async {
  final s = AppStrings.instance;
  if (!kIapMockEnabled) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.t('iap_locked'))));
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => GameAlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(s.t('iap_test_title')),
      content: Text('${s.t('iap_test_body')}\n\n${pack.priceLabel}'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.t('iap_test_confirm'))),
      ],
    ),
  );
  return ok == true;
}
