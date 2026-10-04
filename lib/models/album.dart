import 'game_theme.dart';

/// Koleksiyon albümünün katalogu: hangi temalar, hangi sırayla.
///
/// Albümdeki her kart = (tema, seviye) çifti. Oyuncu o objeyi tahtada
/// İLK KEZ ürettiğinde (atışla ya da birleştirmeyle) kart açılır
/// (bkz. GameProgress.discoverItem). Yeni tema eklenince sadece
/// aşağıdaki listeye eklemek ve GameProgress.albumThemeKeys'e anahtarını
/// yazmak yeterli.
class AlbumCatalog {
  AlbumCatalog._();

  static const List<GameTheme> themes = [
    FastFoodTheme(),
    CafeTheme(),
    MagicTheme(),
    PirateTheme(),
    IceTheme(),
    SpaceTheme(),
  ];
}
