import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/player_progress.dart';
import '../widgets/backgrounds/meteor_shower_background.dart';
import '../widgets/backgrounds/solar_system_background.dart';
import '../widgets/backgrounds/spaceships_background.dart';
import '../widgets/backgrounds/ufos_background.dart';
import '../widgets/space_background.dart';

/// Tek bir "Kozmik Oda" arkaplan temasinin tanimi: kimligi, gosterilecek
/// ismi (lokalizasyon anahtari), fiyati ve gercek arkaplan widget'ini
/// (hem kucuk onizleme kartinda hem de tam ekranda AYNI widget'i, sadece
/// farkli boyutta) uretenfonksiyon.
class CosmicTheme {
  final String id;
  final String nameKey;
  final int price;
  final Widget Function({Key? key, Widget? child}) builder;

  const CosmicTheme({
    required this.id,
    required this.nameKey,
    required this.price,
    required this.builder,
  });

  bool get isFree => price == 0;
}

/// Tum Kozmik Oda temalarinin TEK kaynagi. Yeni bir arkaplan animasyonu
/// eklendiginde (yeni bir StatefulWidget dosyasi olarak) buraya tek bir
/// satir eklemek yeterlidir — Dukkan ve Kozmik Oda ekranlari bu listeyi
/// otomatik olarak kullanir.
///
/// NOT: 'default' (SpaceBackground) HER ZAMAN ucretsiz ve herkeste hazir
/// kalmali — bu, oyunun basindan beri standart olan ana ekran temasi.
class CosmicThemes {
  CosmicThemes._();

  static const List<CosmicTheme> all = [
    CosmicTheme(
      id: 'default',
      nameKey: 'theme_default',
      price: 0,
      builder: SpaceBackground.new,
    ),
    CosmicTheme(
      id: 'meteor_shower',
      nameKey: 'theme_meteorShower',
      price: EconomyConfig.cosmicThemePriceTier1,
      builder: MeteorShowerBackground.new,
    ),
    CosmicTheme(
      id: 'solar_system',
      nameKey: 'theme_solarSystem',
      price: EconomyConfig.cosmicThemePriceTier2,
      builder: SolarSystemBackground.new,
    ),
    CosmicTheme(
      id: 'spaceships',
      nameKey: 'theme_spaceships',
      price: EconomyConfig.cosmicThemePriceTier3,
      builder: SpaceshipsBackground.new,
    ),
    CosmicTheme(
      id: 'ufos',
      nameKey: 'theme_ufos',
      price: EconomyConfig.cosmicThemePriceTier4,
      builder: UfosBackground.new,
    ),
    // Buraya 6 yeni arkaplan daha eklenecek (kullanicidan gelen
    // animasyonlarla) — her biri sadece yeni bir CosmicTheme girisi ve
    // yeni bir arkaplan dosyasi/widget'i olarak.
  ];

  static CosmicTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);

  /// Su an aktif temanin (PlayerProgress.activeTheme) arkaplan widget'ini
  /// [child] icerigiyle sarmalayarak dondurur. Ana ekran / bolum secim
  /// ekranlari bunu SpaceBackground yerine dogrudan kullanir.
  static Widget buildActive(PlayerProgress progress, {Widget? child}) {
    return byId(progress.activeTheme).builder(child: child);
  }
}
