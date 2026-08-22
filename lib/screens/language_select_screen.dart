import 'package:flutter/material.dart';

import '../services/localization.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';

/// Uygulama ilk kez acildiginda, Splash ekraninden hemen sonra gosterilen
/// tek seferlik dil secim ekrani. Bir dil secilip "Devam Et" ile
/// onaylandiginda AppLocale'e kaydedilir ve bir daha gosterilmez (bkz.
/// AppLocale.hasChosenLanguage / setInitialLanguage).
class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});

  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  AppLanguage _selected = AppLocale.instance.language;

  void _confirm() {
    AppLocale.instance.setInitialLanguage(_selected);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.spaceTop,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🚀', style: TextStyle(fontSize: 44)),
                  const SizedBox(height: 18),
                  Text(
                    AppLocale.instance.t('langSelect_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocale.instance.t('langSelect_subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _langOption(AppLanguage.tr, '🇹🇷', 'Türkçe'),
                  const SizedBox(height: 12),
                  _langOption(AppLanguage.en, '🇬🇧', 'English'),
                  const SizedBox(height: 12),
                  _langOption(AppLanguage.ru, '🇷🇺', 'Русский'),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        AppLocale.instance.t('langSelect_continue'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _langOption(AppLanguage lang, String flag, String label) {
    final active = _selected == lang;
    return GestureDetector(
      onTap: () => setState(() => _selected = lang),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.18) : AppColors.tubeGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? AppColors.accent : AppColors.tubeGlassBorder,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (active)
              const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
