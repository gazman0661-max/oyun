import 'milestones.dart' show AchMetric;

/// Gizli gezegenler (skin): zor hedeflerle acilan, oyundaki bir kademenin
/// GORUNUMUNU degistiren alternatif gezegen gorselleri. Fizik/boyut/puan
/// ayni kalir; sadece cizilen PNG (ve gorsele uygun cizim carpani) degisir.
///
/// Acilma kosulu [metric] >= [target] ile belirlenir (PlayerProgress.
/// achievementValue ile ayni sayaclar; kalicidir, dusmez). Acilan skin
/// Koleksiyon ekranindan secilip birakilir.
///
/// Zorluk ayari: sadece buradaki [target] sayilari.
class PlanetSkin {
  final String id;

  /// Hangi kademenin gorselinin yerine gecer (PlanetMergeConfig.tierImage sirasi).
  final int tier;

  /// assets/planets/ gorsel indeksi (PlanetImages.assetPaths).
  final int image;

  /// Gorselin collision dairesine oturmasi icin cizim carpani
  /// (halkali: ~1.55, parlamali kayalik: ~1.15).
  final double drawScale;

  /// Ad anahtari (ayni zamanda id).
  final String nameKey;

  final AchMetric metric;
  final int target;

  const PlanetSkin(
    this.id,
    this.tier,
    this.image,
    this.drawScale,
    this.nameKey,
    this.metric,
    this.target,
  );
}

class PlanetSkins {
  PlanetSkins._();

  static const List<PlanetSkin> all = [
    // Koleksiyon bonusu: 13 gezegenin hepsini kesfet -> Saturn'un yerine.
    PlanetSkin('skin_violet', 9, 4, 1.55, 'skin_violet', AchMetric.planets, 13),
    // 30 gunluk seri -> Dunya'nin yerine.
    PlanetSkin('skin_indigo', 5, 10, 1.15, 'skin_indigo', AchMetric.streak, 30),
    // Tek oyunda 15000 puan -> Gaia'nin yerine.
    PlanetSkin(
        'skin_toksik', 6, 12, 1.15, 'skin_toksik', AchMetric.bestScore, 15000),
  ];
}
