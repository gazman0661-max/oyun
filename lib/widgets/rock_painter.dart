import 'dart:math';

import 'package:flutter/material.dart';

import '../services/planet_images.dart';
import '../theme/app_colors.dart';

/// [rect] icine, [colorIndex]'e karsilik gelen GERCEK gezegen fotografini
/// (kullanicinin sagladigi, assets/planets/ altinda projeye gomulu PNG)
/// oranini BOZMADAN (contain-fit) ortalayarak cizer. Gorsel PlanetImages
/// tarafindan uygulama acilirken (splash ekraninda) onceden yuklenip
/// senkron erisilebilir sekilde onbelleklenir; henuz yuklenmemisse (cok
/// nadir/beklenmedik durum) basit bir renkli daireye geri duser.
void paintRock(Canvas canvas, Rect rect, int colorIndex) {
  final img = PlanetImages.forIndex(colorIndex);
  if (img == null) {
    _paintFallback(canvas, rect, colorIndex);
    return;
  }

  final srcW = img.width.toDouble();
  final srcH = img.height.toDouble();
  final srcRect = Rect.fromLTWH(0, 0, srcW, srcH);

  // contain-fit: gorseli oranini bozmadan rect icine ortala.
  final scale = min(rect.width / srcW, rect.height / srcH);
  final dstW = srcW * scale;
  final dstH = srcH * scale;
  final dstRect = Rect.fromCenter(center: rect.center, width: dstW, height: dstH);

  // Zemine oturmus hissi versin diye hafif, yumusak bir golge.
  final shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.32)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(rect.center.dx, rect.center.dy + dstH * 0.36),
      width: dstW * 0.68,
      height: dstH * 0.16,
    ),
    shadowPaint,
  );

  // Kaynak PNG'lerin kenarinda, gorselin kendi icine gomulu, hafif
  // saydam KOYU/siyahimsi bir "hale" bulunuyor (fotograflarin arka
  // plani tam seffaf degil, kenara dogru koyulasan bir gecis birakmis —
  // ozellikle Dunya, Gunes, Merkur, Mars, Neptun ve pembe/gaia
  // gezegenlerinde belirgin). Bunu gostermemek icin, gezegeni
  // cizecegimiz dairenin, gorselin kendi disk sinirindan biraz iceriden
  // bir daireyle KIRPIYORUZ. Satürn/Uranüs/Violet gorselleri ise
  // halkalariyla birlikte gelip yuvarlak degil eni-genis bir sekle sahip
  // oldugu icin (halkalar govdeden daha genise tasiyor), onlara SIKI bir
  // daire kirpmasi uygulanirsa halkanin uclari kesilir — bu yuzden o
  // gezegenler icin kirpma neredeyse devre disi birakiliyor.
  final clipFactor = _haloClipFactor(colorIndex);
  final clipRadius = min(dstW, dstH) / 2 * clipFactor;
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: rect.center, radius: clipRadius)));
  canvas.drawImageRect(
    img,
    srcRect,
    dstRect,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();
}

/// Her gezegen PNG'sinin kendi sanat stiline gore ne kadar sikica
/// kirpilmasi gerektigini soyler (1.0 = kirpma yok). assets/planets
/// klasorundeki gercek dosyalar incelenerek belirlendi:
/// - index 3 (Saturn), 4 (Violet), 6 (Uranus): govdeden daha genis
///   halkalari oldugu icin dairesel kirpma onlarin ucunu keser -> kirpma
///   neredeyse kapali birakildi.
/// - digerleri: kenarda koyu/siyahimsi bir hale var -> sikica kirpiliyor.
double _haloClipFactor(int colorIndex) {
  switch (colorIndex % 10) {
    case 3:
    case 4:
    case 6:
      return 0.99;
    default:
      return 0.80;
  }
}

/// Gorsel(ler) henuz yuklenmemisse kullanilan cok basit yedek gorunum.
void _paintFallback(Canvas canvas, Rect rect, int colorIndex) {
  final c = AppColors.colorFor(colorIndex);
  final center = rect.center;
  final radius = min(rect.width, rect.height) / 2 * 0.9;
  final paint = Paint()
    ..shader = RadialGradient(
      colors: [Color.lerp(c, Colors.white, 0.45)!, c],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  canvas.drawCircle(center, radius, paint);
}
