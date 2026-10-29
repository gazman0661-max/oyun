import 'package:flutter/material.dart';

import '../screens/legal_webview_screen.dart';
import '../services/gdpr_service.dart';
import '../services/legal_links.dart';
import '../services/localization.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';

/// Ilk acilista (dil secimi hemen sonrasinda) gosterilen, kapatilamaz
/// (barrier dismiss / geri tusu ile kapanmaz) sozlesme onay popup'i.
///
/// NOT: Bu diyalog artik AB/GDPR reklam rizasi icin ayri bir secim
/// SUNMAZ (kisisellestirilmis/kisisellestirilmemis reklam butonlari
/// kaldirildi) — cunku reklam aglarina iletilen ASIL yasal rizayi zaten
/// Appodeal'in KENDI resmi onay ekrani (Google UMP tabanli Stack
/// Consent Manager) SDK ilk baslatildiginda otomatik olarak aliyor
/// (bkz. AdService.initializeSdk). Burasi sadece oyunun kendi Kullanim
/// Sartlari/Gizlilik Politikasi onayini alir.
class ConsentDialog extends StatelessWidget {
  const ConsentDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConsentDialog(),
    );
  }

  void _openPrivacy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalWebViewScreen(
          url: LegalLinks.privacyPolicyUrl,
          title: t('legal_privacyPolicy'),
        ),
      ),
    );
  }

  void _openTerms(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalWebViewScreen(
          url: LegalLinks.termsUrl,
          title: t('legal_terms'),
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context) async {
    SoundService.instance.buttonTap();
    await GdprService.instance.acceptTerms();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚀', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                t('consent_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t('consent_desc'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accentSoft),
                        foregroundColor: AppColors.accentSoft,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _openPrivacy(context),
                      child: Text(
                        t('legal_privacyPolicy'),
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accentSoft),
                        foregroundColor: AppColors.accentSoft,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _openTerms(context),
                      child: Text(
                        t('legal_terms'),
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _accept(context),
                  child: Text(
                    t('consent_acceptContinue'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

