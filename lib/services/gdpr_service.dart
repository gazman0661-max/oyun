import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import 'ad_service.dart';

/// Kullanım Şartları / Gizlilik Politikası onayını cihaz üzerinde kalıcı
/// olarak (SharedPreferences) saklayan basit bir ChangeNotifier singleton.
///
/// Reklam ağlarına iletilen ASIL (yasal olarak geçerli, IAB TCF uyumlu)
/// GDPR/AB rızası, kendi arayüzümüzde manuel olarak YÖNETİLMEZ — bunun
/// yerine tamamen Appodeal'in KENDİ resmi onay ekranı (Google UMP tabanlı
/// Stack Consent Manager) üzerinden otomatik alınır: SDK ilk kez
/// başlatıldığında AB/AEA/İsviçre/UK/CCPA bölgesindeki kullanıcılara
/// OTOMATİK olarak gösterilir (bkz. AdService.initializeSdk). Kullanıcı bu
/// rızasını istediği zaman [openAdConsentForm] ile (Profil ekranından)
/// yeniden açıp değiştirebilir. Bu sınıf o akışa hiç karışmaz; sadece
/// oyunun kendi Kullanım Şartları/Gizlilik Politikası onayını tutar.
class GdprService extends ChangeNotifier {
  GdprService._();
  static final GdprService instance = GdprService._();

  static const _kTermsAccepted = 'legal_terms_accepted_v1';

  bool _termsAccepted = false;
  bool _loaded = false;

  /// Kullanım Şartları & Gizlilik Politikası onaylandı mı?
  bool get termsAccepted => _termsAccepted;

  bool get loaded => _loaded;

  /// İlk açılıştaki sözleşme popup'ının gösterilmesi gerekiyor mu?
  bool get needsConsentPrompt => _loaded && !_termsAccepted;

  /// Uygulama en başlarken (main.dart içinde, runApp'ten önce) çağrılmalı.
  /// Kayıtlı tercihi okur. Reklam ağlarına iletilen asıl rıza Appodeal
  /// SDK'sının kendi resmi onay ekranı üzerinden ayrıca yönetilir (bkz.
  /// sınıf açıklaması / AdService.initializeSdk).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _termsAccepted = prefs.getBool(_kTermsAccepted) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// İlk açılış popup'ından çağrılır: sözleşmeyi onaylar. Reklam
  /// ağlarına iletilen ASIL rıza, Appodeal'in kendi resmi onay ekranı
  /// üzerinden ayrıca (SDK ilk başlatıldığında otomatik) alınır.
  Future<void> acceptTerms() async {
    _termsAccepted = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTermsAccepted, true);
  }

  /// Profil/Ayarlar ekranindaki "Reklam Rızasını Yönet" butonundan
  /// çağrılır: Appodeal'in KENDİ resmi onay ekranını (Google UMP tabanlı
  /// Stack Consent Manager) tekrar açar; kullanıcı IAB TCF rızasını
  /// istediği zaman buradan gerçekten değiştirebilir.
  Future<void> openAdConsentForm() async {
    try {
      // NOT: Appodeal.ConsentForm.load ve .show 'void' donuyor (Future
      // degil), bu yuzden 'await' KULLANILAMAZ — derleme hatasi
      // ("This expression has type 'void' and can't be used") buradan
      // kaynaklaniyordu. Sonuc, load'un kendi callback'leri
      // (onConsentFormLoadSuccess / onConsentFormLoadFailure) uzerinden
      // asenkron olarak geliyor zaten.
      Appodeal.ConsentForm.load(
        appKey: AdService.appodealAppKey,
        onConsentFormLoadSuccess: (status) {
          Appodeal.ConsentForm.show(
            onConsentFormDismissed: (error) {
              // Onbellekteki reklam eski rizayla alinmisti; yeni rizaya
              // gore atip yeniden yukle.
              AdService.instance.refreshForConsentChange();
            },
          );
        },
        onConsentFormLoadFailure: (error) {},
      );
    } catch (_) {
      // Form yuklenemezse (ör. internet yok) sessizce yut.
    }
  }
}
