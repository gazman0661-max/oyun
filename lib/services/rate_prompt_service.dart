import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oyuncuyu Play Store / App Store puanlamaya en uygun anda yönlendiren
/// servis.
///
/// ÖNEMLİ (Play Store politikası): Google, in-app review API'sinin
/// SADECE "mutlu" görünen kullanıcılara gösterilmesini (ör. önce
/// "Oyunu beğendin mi? Evet/Hayır" diye sorup Hayır diyenleri mağazaya
/// göndermemeyi) YASAKLAR — API her koşulda tutarlı davranmalı. Bu
/// yüzden burada duygu durumuna göre bir "ön kapı" filtresi YOK; bunun
/// yerine sadece BAĞLAM sinyalleri kullanılıyor (temiz kazanım, yeterli
/// ilerleme, soğuma süresi, oturum/toplam gösterim limiti). Bu hem
/// politika ile uyumlu hem de veride kanıtlanmış en etkili yöntem:
/// oyuncu az önce bir şeyi BAŞARDIĞI an, sinirli/takılı olduğu an değil.
class RatePromptService {
  RatePromptService._();
  static final RatePromptService instance = RatePromptService._();

  static const _prefsShownCountKey = 'rp_shown_count_v1';
  static const _prefsLastShownMsKey = 'rp_last_shown_ms_v1';

  /// Puan istemeden önce en az bu kadar bölüm bitirilmiş olmalı — ilk
  /// izlenimde (henüz oyunu sevip sevmediğine karar vermeden) sormak,
  /// düşük puan riskini artırır.
  static const int minStagesBeforePrompt = 6;

  /// Cihaz ömrü boyunca en fazla bu kadar kez gösterilir (native API
  /// zaten OS seviyesinde de kendi frekans sınırını uygular, ama kendi
  /// tarafımızda da tutmak davranışı öngörülebilir kılar).
  static const int maxPromptsTotal = 3;

  /// İki gösterim arası minimum gün.
  static const int cooldownDays = 21;

  bool _shownThisSession = false;

  /// Bir bölüm/level SONUCU üretildiğinde çağrılır. Sadece [cleanWin]
  /// true ise (ör. ilk denemede, yardım/ipucu/reklam-kurtarması
  /// kullanılmadan, en iyi sonuçla bitirilmiş) ve diğer tüm koşullar
  /// (yeterli ilerleme + soğuma süresi + toplam limit + oturum başına 1
  /// kez) sağlanıyorsa native puanlama diyaloğunu tetikler.
  Future<void> maybePromptAfterCleanWin({
    required int totalStagesCleared,
    required bool cleanWin,
  }) async {
    if (!cleanWin) return;
    if (_shownThisSession) return;
    if (totalStagesCleared < minStagesBeforePrompt) return;

    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt(_prefsShownCountKey) ?? 0;
    if (shownCount >= maxPromptsTotal) return;

    final lastShownMs = prefs.getInt(_prefsLastShownMsKey) ?? 0;
    if (lastShownMs != 0) {
      final daysSince = (DateTime.now().millisecondsSinceEpoch - lastShownMs) /
          (1000 * 60 * 60 * 24);
      if (daysSince < cooldownDays) return;
    }

    final inAppReview = InAppReview.instance;
    if (!await inAppReview.isAvailable()) return;

    // İşaretlemeyi (session/limit/cooldown) çağrıdan ÖNCE yapıyoruz;
    // requestReview() OS tarafında sessizce reddedilse bile (ör. OS'nin
    // kendi günlük/aylık limiti dolmuşsa) bizim tarafımızdaki sayaç
    // tutarlı ilerler, art arda her bölüm sonunda tekrar denemeyiz.
    _shownThisSession = true;
    await prefs.setInt(_prefsShownCountKey, shownCount + 1);
    await prefs.setInt(
        _prefsLastShownMsKey, DateTime.now().millisecondsSinceEpoch);

    await inAppReview.requestReview();
  }
}
