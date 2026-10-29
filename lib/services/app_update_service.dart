import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// ZORUNLU GUNCELLEME (Google Play In-App Updates).
///
/// Oyun acilirken Play'de yeni surum varsa Google'in tam ekran "Guncelle"
/// penceresi cikar; oyuncu guncelleyince oyun kendini yeniden acar.
///  - Sadece Play'den kurulu surumde calisir. Debug/APK (adb, manuel) ile
///    kurulu surumde sessizce atlanir.
///  - Yeni surum Play'de "yayinda" olmali; yuklenip yayina girmesi saatler
///    surebilir.
///  - Hicbir hata oyunu engellemez (her sey try/catch icinde).
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// true: tam ekran, zorunlu (immediate). false: arka planda indirir,
  /// hazir olunca kurar (flexible).
  static const bool forceImmediate = true;

  /// Yayinlanmasindan beri bu kadar gun gecmeden zorlama yapma (0 = hemen).
  /// Ornek: 2 yaparsan yeni surum cikinca oyunculara 2 gun sure taninir.
  static const int minStalenessDays = 0;

  bool _checked = false;

  Future<void> check() async {
    if (_checked || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _checked = true;
    try {
      // Arayuz/Activity hazir olsun.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final info =
          await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 8));
      debugPrint(
          'AppUpdate: availability=${info.updateAvailability} immediate=${info.immediateUpdateAllowed}');
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      final stale = info.clientVersionStalenessDays ?? 0;
      if (stale < minStalenessDays) return;
      if (forceImmediate && info.immediateUpdateAllowed) {
        final r = await InAppUpdate.performImmediateUpdate();
        debugPrint('AppUpdate: immediate sonuc: ${r.name}');
      } else if (info.flexibleUpdateAllowed) {
        final r = await InAppUpdate.startFlexibleUpdate();
        debugPrint('AppUpdate: flexible sonuc: ${r.name}');
        if (r == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (err) {
      // Play'den kurulu degil / Play Hizmetleri yok / zaman asimi:
      // oyun normal acilir.
      debugPrint('AppUpdate: yutulan hata: $err');
    }
  }
}
