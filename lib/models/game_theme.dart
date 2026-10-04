import 'package:flutter/material.dart';
import 'food_item.dart';
import 'cafe_item.dart';
import 'magic_item.dart';
import 'pirate_item.dart';
import 'ice_item.dart';
import 'space_item.dart';

enum ChapterKind { normal, easy, boss }

/// TÜM objelerin (fizik, çizim, nişan) boyut çarpanı - tek merkezi ayar.
///
/// Referans videoda (Mystery Town) bir obje, masa genişliğinin yalnızca
/// ~%6-9'u kadar; masanın uzak ucuna yan yana ~12-17 obje sığıyor ve yığın
/// bu yüzden masanın tüm genişliğine YAYILIP uzak duvarın dibinde
/// (masa boyunun ~%25'i kadar derinlikte) toplanıyor. Eski boyutlarda
/// (yarıçap 20..69 dp, çap masa uzak genişliğinin %17..%58'i) aynı masaya
/// 3-5 obje sığıyordu: yığın uzak duvara yaslanmak yerine masanın ortasına
/// (~%50'sine) kadar uzuyordu. 0.62 ile Python simülasyonunda yığın
/// derinliği referansla aynı (~%26) çıkıyor; 0.78 ile ~%33 (v66: bir tık daha büyük; 0.70 ~%30, hâlâ videoya yakın). Objeler çok küçük gelirse
/// 0.70-0.75'e çıkar, tam eski boyut için 1.0 yap.
const double kBallSizeScale = 0.78;

/// GameBoard'un hangi temayı kullanacağını tanımlayan soyut arayüz.
/// FoodTiers, CafeTiers, MagicTiers, PirateTiers, IceTiers ve SpaceTiers bu
/// arayüzü sağlayan wrapper'larla sarılır, GameBoard kodu değişmeden tüm
/// temaları çalıştırabilir.
abstract class GameTheme {
  int get maxLevel;
  String get tableImagePath;
  double get imageWidth;   // masa PNG/JPG'nin gerçek pixel genişliği
  double get imageHeight;  // masa PNG/JPG'nin gerçek pixel yüksekliği
  String get themeName;    // "Kafe & Pastane" gibi görünen isim (TR sabit - eski cagrilar icin)
  String get themeNameKey; // AppStrings.t() ile cevrilecek anahtar

  TierInfo byLevel(int level);
}

/// Tek bir obje seviyesinin veri paketi - GameBoard bu yapıyla çalışır.
class TierInfo {
  final int level;
  final String name;
  final String emoji;
  final Color color;
  final int coinReward;
  final String imagePath;
  final double radius;

  const TierInfo({
    required this.level,
    required this.name,
    required this.emoji,
    required this.color,
    required this.coinReward,
    required this.imagePath,
    required this.radius,
  });
}

// ──────────────────────────────────────────────────────
// Tema 1: Fast Food Dükkanı
// ──────────────────────────────────────────────────────
class FastFoodTheme implements GameTheme {
  const FastFoodTheme();
  @override int get maxLevel => FoodTiers.maxLevel;
  @override String get tableImagePath => 'assets/images/table_background.jpg';
  @override double get imageWidth => 768;
  @override double get imageHeight => 1376;
  @override String get themeName => 'Fast Food Dükkanı';
  @override String get themeNameKey => 'theme_fastfood';
  @override TierInfo byLevel(int level) {
    final t = FoodTiers.byLevel(level);
    return TierInfo(level: t.level, name: t.name, emoji: t.emoji, color: t.color,
        coinReward: t.coinReward, imagePath: t.imagePath, radius: t.radius * kBallSizeScale);
  }
}

// ──────────────────────────────────────────────────────
// Tema 2: Kafe & Pastane
// ──────────────────────────────────────────────────────
class CafeTheme implements GameTheme {
  const CafeTheme();
  @override int get maxLevel => CafeTiers.maxLevel;
  @override String get tableImagePath => CafeTiers.tableImagePath;
  @override double get imageWidth => 768;
  @override double get imageHeight => 1376;
  @override String get themeName => 'Kafe & Pastane';
  @override String get themeNameKey => 'theme_cafe';
  @override TierInfo byLevel(int level) {
    final t = CafeTiers.byLevel(level);
    return TierInfo(level: t.level, name: t.name, emoji: t.emoji, color: t.color,
        coinReward: t.coinReward, imagePath: t.imagePath, radius: t.radius * kBallSizeScale);
  }
}

// ──────────────────────────────────────────────────────
// Tema 3: Büyü & Simya
// ──────────────────────────────────────────────────────
class MagicTheme implements GameTheme {
  const MagicTheme();
  @override int get maxLevel => MagicTiers.maxLevel;
  @override String get tableImagePath => MagicTiers.tableImagePath;
  @override double get imageWidth => 768;
  @override double get imageHeight => 1376;
  @override String get themeName => 'Büyü & Simya';
  @override String get themeNameKey => 'theme_magic';
  @override TierInfo byLevel(int level) {
    final t = MagicTiers.byLevel(level);
    return TierInfo(level: t.level, name: t.name, emoji: t.emoji, color: t.color,
        coinReward: t.coinReward, imagePath: t.imagePath, radius: t.radius * kBallSizeScale);
  }
}

// ──────────────────────────────────────────────────────
// Tema 4: Korsan Hazinesi
// ──────────────────────────────────────────────────────
class PirateTheme implements GameTheme {
  const PirateTheme();
  @override int get maxLevel => PirateTiers.maxLevel;
  @override String get tableImagePath => PirateTiers.tableImagePath;
  @override double get imageWidth => 768;
  @override double get imageHeight => 1376;
  @override String get themeName => 'Korsan Hazinesi';
  @override String get themeNameKey => 'theme_pirate';
  @override TierInfo byLevel(int level) {
    final t = PirateTiers.byLevel(level);
    return TierInfo(level: t.level, name: t.name, emoji: t.emoji, color: t.color,
        coinReward: t.coinReward, imagePath: t.imagePath, radius: t.radius * kBallSizeScale);
  }
}

// ──────────────────────────────────────────────────────
// Tema 5: Buz Krallığı
// ──────────────────────────────────────────────────────
class IceTheme implements GameTheme {
  const IceTheme();
  @override int get maxLevel => IceTiers.maxLevel;
  @override String get tableImagePath => IceTiers.tableImagePath;
  @override double get imageWidth => 768;
  @override double get imageHeight => 1376;
  @override String get themeName => 'Buz Krallığı';
  @override String get themeNameKey => 'theme_ice';
  @override TierInfo byLevel(int level) {
    final t = IceTiers.byLevel(level);
    return TierInfo(level: t.level, name: t.name, emoji: t.emoji, color: t.color,
        coinReward: t.coinReward, imagePath: t.imagePath, radius: t.radius * kBallSizeScale);
  }
}

// ──────────────────────────────────────────────────────
// Tema 6: Uzay İstasyonu
// ──────────────────────────────────────────────────────
class SpaceTheme implements GameTheme {
  const SpaceTheme();
  @override int get maxLevel => SpaceTiers.maxLevel;
  @override String get tableImagePath => SpaceTiers.tableImagePath;
  @override double get imageWidth => 768;
  @override double get imageHeight => 1376;
  @override String get themeName => 'Uzay İstasyonu';
  @override String get themeNameKey => 'theme_space';
  @override TierInfo byLevel(int level) {
    final t = SpaceTiers.byLevel(level);
    return TierInfo(level: t.level, name: t.name, emoji: t.emoji, color: t.color,
        coinReward: t.coinReward, imagePath: t.imagePath, radius: t.radius * kBallSizeScale);
  }
}

// ──────────────────────────────────────────────────────
// Bolum yapilandirmasi: SINIRSIZ ilerleme.
//
// Sabit bir "son bolum" YOK. Oyuncu ne kadar ilerleyebilirse o kadar
// bolum acilir. Elimizdeki 6 tema, 8'er bolumluk bloklar halinde
// sirayla DONER (1-8 Fast Food, 9-16 Kafe, 17-24 Büyü&Simya, 25-32
// Korsan Hazinesi, 33-40 Buz Krallığı, 41-48 Uzay İstasyonu, 49-56
// tekrar Fast Food, ...) -
// yeni bir tema eklendiginde tek yapilacak sey asagidaki themeFor()
// fonksiyonuna bir dal daha eklemek.
//
// Zorluk egrisi de bloklar arasinda SIFIRLANMIYOR: her tam blok
// (8 bolum) tamamlandiginda taban hedef biraz daha yukseliyor, yani
// oyuncu 50. bolume geldiginde 1. bolumdekinden gercekten daha zor
// bir mucadeleyle karsilasiyor.
// ──────────────────────────────────────────────────────
class ChapterConfig {
  ChapterConfig._();

  static const int chaptersPerThemeBlock = 8;

  /// Bolum numarasina gore hangi temanin oynanacagini dondurur.
  /// Su an elde 6 tema var; bloklar bu alti arasinda sonsuza kadar
  /// donuyor. Yeni tema eklenince buraya % 7, % 8 vb. eklenebilir.
  static GameTheme themeFor(int chapterNumber) {
    final block = (chapterNumber - 1) ~/ chaptersPerThemeBlock;
    switch (block % 6) {
      case 0:
        return const FastFoodTheme();
      case 1:
        return const CafeTheme();
      case 2:
        return const MagicTheme();
      case 3:
        return const PirateTheme();
      case 4:
        return const IceTheme();
      default:
        return const SpaceTheme();
    }
  }

  /// Bolum derinligine gore coin carpani: her 8 bolumluk dongude +%1,
  /// en fazla x1.5 (simulatorle dogrulandi; eskisi +%3/x3 geliri ucuruyordu). Gelir derinlestikce buyur, pahali yukseltmeler yetisilebilir kalir.
  static double coinMultiplier(int chapterNumber) =>
      (1 + 0.01 * ((chapterNumber - 1) ~/ chaptersPerThemeBlock)).clamp(1.0, 1.5).toDouble();

  /// Bolum hedefi (kac siparis teslim edilince bolum biter).
  /// Blok icinde 15'ten 50'ye kadar kademeli artar, her yeni blokta
  /// (yeni tema donguye girdiginde) taban +20 yukselir - boylece
  /// egri hicbir zaman duzlesmiyor/sifirlanmiyor.
  static int goalFor(int chapterNumber) {
    final raw = _rawGoalFor(chapterNumber);
    switch (kindFor(chapterNumber)) {
      case ChapterKind.easy:
        return (raw * 0.7).round().clamp(5, 1000).toInt();
      case ChapterKind.boss:
        return (raw * 0.5).round().clamp(5, 1000).toInt();
      case ChapterKind.normal:
        return raw;
    }
  }

  /// ZORLUK DALGASI: her 5. bolum RAHAT (%70 hedef, kolay siparisler),
  /// her 10. bolum BOSS (yarim hedef ama sadece yuksek seviye siparis,
  /// siparis odulu 2 kat + ilk gecise ekstra odul).
  static ChapterKind kindFor(int chapterNumber) {
    if (chapterNumber >= 5 && chapterNumber % 10 == 0) return ChapterKind.boss;
    if (chapterNumber >= 5 && chapterNumber % 5 == 0) return ChapterKind.easy;
    return ChapterKind.normal;
  }

  static int _rawGoalFor(int chapterNumber) {
    final posInBlock = ((chapterNumber - 1) % chaptersPerThemeBlock) + 1; // 1-8
    final cycleIndex = (chapterNumber - 1) ~/ chaptersPerThemeBlock; // 0,1,2,...
    // Ilk dongu (yeni oyuncu) daha yumusak: ilk bolumler cabuk biter,
    // hizli ilk galibiyet ve ilk odul. Sonraki dongulerde eski egri.
    if (cycleIndex == 0) return const [5, 7, 9, 11, 13, 15, 17, 20][posInBlock - 1];
    // TAVAN 20: eskiden her dongude +20 siparis ekleniyordu (ch41 ~29 dk, ch161 ~104 dk)
    // ve oyuncu bolumun ortasinda birakip gidiyordu. Piyasada bolum suresi
    // SABIT ve KISADIR (2-5 dk); zorluk sure uzatilarak degil siparis
    // SEVIYELERINDEN (difficultyT) gelir. Normal ~4-5 dk, boss ~4 dk, rahat ~3 dk.
    final base = 10 + posInBlock * 5;
    final cycleBonus = cycleIndex * 20;
    return (base + cycleBonus).clamp(0, 20).toInt();
  }

  /// 0.0 (en kolay) - 1.0 (en zor, plato) arasi normalize edilmis zorluk.
  /// GameBoard bunu siparis agirliklarini yuksek seviyelere kaydirmak
  /// icin kullanir. 40. bolum civarinda platoya oturur (sonsuza kadar
  /// gittikce imkansizlasmasin diye).
  static double difficultyT(int chapterNumber) {
    final t = ((chapterNumber - 1) / 40).clamp(0.0, 1.0).toDouble();
    return kindFor(chapterNumber) == ChapterKind.easy ? t * 0.4 : t;
  }
}
