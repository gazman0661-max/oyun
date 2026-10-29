import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Her renk index'ine (0..9) karsilik gelen GERCEK gezegen fotografini
/// (assets/planets/ altinda gomulu PNG) tutar. CustomPainter.paint()
/// senkron calistigi icin gorseller uygulama acilirken (main() icinde,
/// runApp'tan once) bir kez onceden yuklenir ve burada ui.Image olarak
/// onbelleklenir — calisma zamaninda hicbir network/dosya-sistemi
/// gecikmesi olmadan dogrudan Canvas'a cizilebilir.
class PlanetImages {
  PlanetImages._();

  static const List<String> assetPaths = [
    'assets/planets/0_sun.png',
    'assets/planets/1_earth.png',
    'assets/planets/2_gaia.png',
    'assets/planets/3_saturn.png',
    'assets/planets/4_violet.png',
    'assets/planets/5_mars.png',
    'assets/planets/6_uranus.png',
    'assets/planets/7_pink.png',
    'assets/planets/8_mercury.png',
    'assets/planets/9_neptune.png',
    'assets/planets/10_indigo.png',
    'assets/planets/11_kizilcuce.png',
    'assets/planets/12_toksikdunya.png',
    'assets/planets/13_buzay.png',
    'assets/planets/14_bakirasteroit.png',
    'assets/planets/15_karanlikkutle.png',
  ];

  static final List<ui.Image?> _images = List<ui.Image?>.filled(assetPaths.length, null);
  static bool _loaded = false;

  static bool get isReady => _loaded;

  /// [colorIndex]'e karsilik gelen onceden yuklenmis gezegen gorseli.
  /// Henuz yuklenmediyse (preload() tamamlanmadan cizim istenirse) null
  /// doner; cagiran taraf bu durumda eski vektorel cizime geri duser.
  static ui.Image? forIndex(int colorIndex) => _images[colorIndex % _images.length];

  /// Tum gezegen PNG'lerini bir kez yukler. main() icinde, runApp'tan
  /// once await edilmelidir.
  static Future<void> preload() async {
    if (_loaded) return;
    for (var i = 0; i < assetPaths.length; i++) {
      final data = await rootBundle.load(assetPaths[i]);
      final image = await _decode(data);
      _images[i] = image;
    }
    _loaded = true;
  }

  static Future<ui.Image> _decode(ByteData data) async {
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
