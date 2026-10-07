import 'dart:async';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';
import 'push_service.dart';

/// Ilk acilista Kullanim Sartlari + Gizlilik Politikasi (+ AB/AEA/UK icin GDPR)
/// onayi. Onay verilmeden oyun acilmaz; reklam SDK'si ve push (Firebase)
/// onaydan ONCE baslatilmaz.
///
/// Metinler degisip yeniden onay gerekirse [_kVersion] sayisini artir.
class LegalConsentService {
  LegalConsentService._();
  static final LegalConsentService instance = LegalConsentService._();

  static const int _kVersion = 1;
  static const String _kKey = 'legal_consent_version_v1';
  static const String _kTimeKey = 'legal_consent_time_v1';

  bool _accepted = false;
  bool get accepted => _accepted;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _accepted = (p.getInt(_kKey) ?? 0) >= _kVersion;
    } catch (_) {
      _accepted = false;
    }
  }

  /// Kullanici onayladi: kaydet, sonra onay gerektiren servisleri baslat.
  Future<void> accept({required bool gdprConsent}) async {
    _accepted = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kKey, _kVersion);
      await p.setString(_kTimeKey, DateTime.now().toUtc().toIso8601String());
      await p.setBool('legal_gdpr_consent_v1', gdprConsent);
    } catch (_) {}
    startConsentGatedServices();
  }

  bool _started = false;

  /// Reklam SDK'si (Google UMP/Appodeal rıza formu dahil) ve push: yalnizca onay sonrasi.
  void startConsentGatedServices() {
    if (_started || !_accepted) return;
    _started = true;
    unawaited(PushService.instance.init());
    unawaited(AdService.instance.initializeSdk().timeout(const Duration(seconds: 8), onTimeout: () {}));
  }

  static const Set<String> _gdprRegions = {
    // AB uyeleri
    'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE',
    'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
    // AEA + Birlesik Krallik + Isvicre
    'IS', 'LI', 'NO', 'GB', 'UK', 'CH',
  };

  /// Cihaz bolgesi AB/AEA/UK/Isvicre ise (ya da bolge bilinmiyorsa, temkinli
  /// olarak) acik GDPR onay kutusu gosterilir. Reklam icin asil bolge tespitini
  /// zaten Google UMP formu yapar.
  bool get showGdpr {
    final cc = ui.PlatformDispatcher.instance.locale.countryCode;
    if (cc == null || cc.isEmpty) return true;
    return _gdprRegions.contains(cc.toUpperCase());
  }
}
