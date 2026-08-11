import 'dart:async';

import 'package:ntp/ntp.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihaz saatinden BAGIMSIZ, internet (NTP) tabanli "dogru simdi" saglar.
///
/// NEDEN: Haftalik gorevin (bkz. PlayerProgress._currentWeekKey) TUM
/// oyuncularda ayni anda baslayip bitmesi gerekiyor. Sadece cihazin
/// kendi saatine (DateTime.now()) guvenilirse iki sorun cikar:
///  1) Farkli oyuncularin cihaz saati/saat dilimi yanlis ayarli olabilir
///     -> hafta sinirlari kisiden kisiye kayar, "herkeste ayni anda"
///     saglanamaz.
///  2) Kullanici cihaz saatini ILERI alip haftayi erken bitirip odulu
///     tekrar tekrar alabilir (ya da GERI alip suresiz erteleyebilir).
///
/// COZUM: Uygulama acilisinda bir NTP sunucusundan gercek UTC zamanini
/// sorup, cihaz saatiyle arasindaki farki ("offset") diske kaydediyoruz.
/// Sonrasinda `nowUtc()` HER ZAMAN bu offset'i cihaz saatine ekleyerek
/// senkron/hizli calisir — network beklemez. Internet yoksa (ilk acilis
/// haric) en son bilinen offset kullanilir; o da yoksa cihaz saatine
/// (offset 0) sessizce duser, oyun ASLA bloklanmaz/cokmez.
class NetworkTimeService {
  NetworkTimeService._();
  static final NetworkTimeService instance = NetworkTimeService._();

  static const _prefsOffsetMsKey = 'ntp_offset_ms_v1';
  static const _prefsSyncedAtMsKey = 'ntp_synced_at_ms_v1';

  /// Son basarili NTP senkronizasyonundan bu kadar sure sonra, bir
  /// sonraki `nowUtc()`/`init()` cagrisinda arka planda sessizce tekrar
  /// senkronize edilir (offset zamanla cihaz saatinden kaymasin diye).
  static const Duration _resyncAfter = Duration(hours: 6);

  int _offsetMs = 0;
  DateTime? _syncedAt;
  bool _loadedFromPrefs = false;
  Completer<void>? _syncing;

  /// Uygulama aciliginda (splash boot) bir kez cagrilir. Diskteki en son
  /// bilinen offset'i HIZLICA yukler (sadece SharedPreferences okur,
  /// network BEKLEMEZ) ve gercek NTP sorgusunu arka planda baslatir.
  Future<void> init() async {
    if (!_loadedFromPrefs) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _offsetMs = prefs.getInt(_prefsOffsetMsKey) ?? 0;
        final syncedAtMs = prefs.getInt(_prefsSyncedAtMsKey);
        _syncedAt = syncedAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(syncedAtMs)
            : null;
      } catch (_) {
        // Diskten okunamazsa offset 0 (cihaz saati) ile devam.
      }
      _loadedFromPrefs = true;
    }
    unawaited(_syncIfNeeded());
  }

  Future<void> _syncIfNeeded() {
    if (_syncing != null) return _syncing!.future;
    if (_syncedAt != null &&
        DateTime.now().difference(_syncedAt!) < _resyncAfter) {
      return Future.value();
    }
    final completer = Completer<void>();
    _syncing = completer;
    () async {
      try {
        final offsetMs = await NTP
            .getNtpOffset(localTime: DateTime.now())
            .timeout(const Duration(seconds: 5));
        _offsetMs = offsetMs;
        _syncedAt = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefsOffsetMsKey, _offsetMs);
        await prefs.setInt(
            _prefsSyncedAtMsKey, _syncedAt!.millisecondsSinceEpoch);
      } catch (_) {
        // Internet yok / NTP portu (UDP 123) engellendi: elde ne varsa
        // (onceki basarili offset ya da 0) onunla devam edilir.
      } finally {
        completer.complete();
        _syncing = null;
      }
    }();
    return completer.future;
  }

  /// NTP ile duzeltilmis, cihaz saatinden bagimsiz UTC "simdi". Ayrica
  /// gerekiyorsa arka planda yeniden senkronizasyonu tetikler (sonucunu
  /// BEKLEMEDEN, mevcut offset ile aninda deger doner).
  DateTime nowUtc() {
    unawaited(_syncIfNeeded());
    return DateTime.now().toUtc().add(Duration(milliseconds: _offsetMs));
  }
}
