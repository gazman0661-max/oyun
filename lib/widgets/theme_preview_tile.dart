import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';

/// Dükkan ve Kozmik Oda ekranlarının ortak kartı: gerçek arkaplan
/// widget'ının küçük, canlı (animasyonlu) bir önizlemesi + tema adı +
/// altında değişken bir "footer" (fiyat/satın al butonu ya da
/// aktif/etkinleştir butonu — ekrana göre değişir).
class ThemePreviewTile extends StatelessWidget {
  final CosmicTheme theme;
  final Widget footer;
  final bool highlight;

  const ThemePreviewTile({
    super.key,
    required this.theme,
    required this.footer,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? AppColors.accent : AppColors.tubeGlassBorder,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gercek arkaplan widget'inin KENDISI, kucuk boyutta canli
          // onizleme olarak — ayri bir "screenshot" veya statik gorsel
          // uretmeye gerek yok, ayni CustomPainter'lar zaten oranli
          // (relative) boyutlandirma kullaniyor.
          AspectRatio(
            aspectRatio: 16 / 11,
            child: IgnorePointer(child: theme.builder()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(theme.nameKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                footer,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
