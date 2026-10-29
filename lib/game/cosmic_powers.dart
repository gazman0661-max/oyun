import 'dart:ui' show Color;

/// Gezegen guclari: belirli bir kademe BIRLESMEYLE olustugunda tetiklenen
/// ozel etkiler. Cekirdek oyunu Suika'dan ayiran katman budur.
///
/// - Saturn (kademe 9)       -> Halka Dalgasi: komsulari iter, yigini gevsetir.
/// - Gunes (kademe 11)       -> Gunes Patlamasi: yakindaki kucukleri yakar, bonus puan.
/// - Karanlik Kutle (kademe 12) -> Kutlecekim: birkac sn komsulari kendine ceker.
///
/// Denge ayari: SADECE asagidaki sabitler. Fizik/gorsel kod bunlari okur.
enum CosmicPower { ringPulse, solarFlare, singularity }

class PowerInfo {
  final CosmicPower power;
  final String id;
  final String nameKey;
  final String descKey;
  final String icon;
  final Color color;
  const PowerInfo(
      this.power, this.id, this.nameKey, this.descKey, this.icon, this.color);
}

/// Bir gucun etkiledigi (yakilan) tek bir gezegen.
class PowerHit {
  final double x, y;
  final int tier;
  final int points;
  const PowerHit(this.x, this.y, this.tier, this.points);
}

/// Dunya -> UI: bir guc tetiklendi (ses/titresim/gorsel efekt icin).
class PowerEvent {
  final CosmicPower power;
  final double x, y;

  /// Etki yaricapi (dunya birimi).
  final double radius;
  final List<PowerHit> hits;
  final int points;
  const PowerEvent(
      this.power, this.x, this.y, this.radius, this.hits, this.points);
}

/// Kutlecekim alani: [bodyId] govdesi [remaining] sn boyunca komsulari ceker.
class GravityWell {
  final int bodyId;
  double remaining;
  final double total;

  /// Govde yuzeyinden itibaren etki mesafesi (dunya birimi).
  final double reach;
  GravityWell(this.bodyId, this.total, this.reach) : remaining = total;
}

class CosmicPowers {
  CosmicPowers._();

  static const int ringPulseTier = 9;
  static const int solarFlareTier = 11;
  static const int singularityTier = 12;

  // ---- Halka Dalgasi ----
  /// Govde yuzeyinden itibaren itme mesafesi.
  static const double ringPulseReach = 26;

  /// En yakin komsuya verilen hiz (birim/sn); uzaklastikca azalir.
  static const double ringPulseSpeed = 70;

  // ---- Gunes Patlamasi ----
  static const double flareReach = 34;

  /// Bu kademe ve altindaki gezegenler yanar.
  static const int flareMaxTier = 3;

  /// Yanan her gezegen icin normal birlesme puaninin kaci kati.
  static const int flarePointsMult = 3;

  // ---- Kutlecekim ----
  static const double singularityReach = 30;
  static const double singularityDuration = 4.0;

  /// Birim/sn^2 (yercekimi 150 birim/sn^2). Uzaklastikca azalir.
  static const double singularityAccel = 120;

  static const List<PowerInfo> all = [
    PowerInfo(CosmicPower.ringPulse, 'ring', 'pw_ring_name', 'pw_ring_desc',
        '🪐', Color(0xFFFFD27A)),
    PowerInfo(CosmicPower.solarFlare, 'flare', 'pw_flare_name',
        'pw_flare_desc', '☀️', Color(0xFFFF9A3C)),
    PowerInfo(CosmicPower.singularity, 'sing', 'pw_sing_name', 'pw_sing_desc',
        '🕳️', Color(0xFFB794FF)),
  ];

  static PowerInfo info(CosmicPower p) =>
      all.firstWhere((i) => i.power == p);

  /// [tier] kademesi olusunca tetiklenen guc (yoksa null).
  static CosmicPower? forTier(int tier) {
    if (tier == ringPulseTier) return CosmicPower.ringPulse;
    if (tier == solarFlareTier) return CosmicPower.solarFlare;
    if (tier == singularityTier) return CosmicPower.singularity;
    return null;
  }

  /// Koleksiyon ekrani icin: [tier] gezegeninin gucu (yoksa null).
  static PowerInfo? infoForTier(int tier) {
    final p = forTier(tier);
    return p == null ? null : info(p);
  }
}
