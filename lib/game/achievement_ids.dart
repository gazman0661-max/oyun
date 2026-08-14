/// Play Console basarim ID'lerinin TEK kaynagi. `leaderboardId`
/// (MainActivity.kt) ile ayni mantik: Play Console > "Play Games
/// Services" > "Başarımlar" bolumunden GERCEK ID'leri alip asagidaki
/// placeholder'larla DEGISTIRMEDEN basarimlar calismaz (sessizce
/// basarisiz olur, oyunun geri kalanini etkilemez).
///
/// Onerilen 3 basarim (Play Console'da su sekilde olusturulmali):
///  - PLANET_EXPLORER (standart/tek seferlik): "10 farkli gezegen kesfet"
///  - WEEK_STREAK (standart/tek seferlik): "7 gun ust uste oyna"
///  - ORBIT_50 (standart/tek seferlik): "Yorunge Vardiyasi'nda 50. bolume ulas"
class AchievementIds {
  AchievementIds._();

  // TODO: Play Console'da olusturduktan sonra bu 3 ID'yi degistir.
  static const String planetExplorer = 'CHANGE_ME_PLANET_EXPLORER';
  static const String weekStreak = 'CHANGE_ME_WEEK_STREAK';
  static const String orbit50 = 'CHANGE_ME_ORBIT_50';

  /// Kac farkli gezegen kesfedilince PLANET_EXPLORER acilsin.
  static const int planetExplorerThreshold = 10;

  /// Kac gunluk seri ile WEEK_STREAK acilsin.
  static const int weekStreakThreshold = 7;

  /// Orbit modunda hangi bolume ulasinca ORBIT_50 acilsin.
  static const int orbit50Threshold = 50;
}
