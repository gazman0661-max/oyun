import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';
import '../screens/legal_screen.dart';
import '../services/legal_consent_service.dart';
import 'ui_kit.dart';

/// Ilk acilis zorunlu onay penceresi. Kapatilamaz; ya onaylanir ya uygulamadan cikilir.
class LegalGateDialog extends StatefulWidget {
  const LegalGateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.78),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const LegalGateDialog(),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)), child: child),
      ),
    );
  }

  @override
  State<LegalGateDialog> createState() => _LegalGateDialogState();
}

class _LegalGateDialogState extends State<LegalGateDialog> {
  bool _terms = false;
  bool _privacy = false;
  bool _gdpr = false;
  final _termsTap = TapGestureRecognizer();
  final _privacyTap = TapGestureRecognizer();
  late final bool _showGdpr = LegalConsentService.instance.showGdpr;

  @override
  void initState() {
    super.initState();
    _termsTap.onTap = () => _open(LegalKind.terms);
    _privacyTap.onTap = () => _open(LegalKind.privacy);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _open(LegalKind k) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(kind: k)));
  }

  bool get _ready => _terms && _privacy && (!_showGdpr || _gdpr);

  Future<void> _accept() async {
    if (!_ready) return;
    await LegalConsentService.instance.accept(gdprConsent: _showGdpr && _gdpr);
    if (mounted) Navigator.of(context).pop();
  }

  void _decline() {
    SystemNavigator.pop();
  }

  Widget _check({required bool value, required ValueChanged<bool> onChanged, required InlineSpan label}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                activeColor: const Color(0xFF3CC13A),
                side: const BorderSide(color: Color(0xFF8A5A2B), width: 2),
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                label,
                style: const TextStyle(fontSize: 14, height: 1.25, color: Color(0xFF4A2C0A), fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _link(String text, TapGestureRecognizer r) => TextSpan(
        text: text,
        recognizer: r,
        style: const TextStyle(color: Color(0xFF1B6FD1), decoration: TextDecoration.underline, fontWeight: FontWeight.w900),
      );

  @override
  Widget build(BuildContext context) {
    final tr = AppStrings.instance.language == AppLanguage.tr;
    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFF4D6), Color(0xFFFFE0A3)],
                  ),
                  border: Border.all(color: const Color(0xFFFFB300), width: 4),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 8))],
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🛡️', style: TextStyle(fontSize: 38, height: 1.0)),
                      const SizedBox(height: 4),
                      Text(
                        tr ? 'Başlamadan Önce' : 'Before You Start',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF5D2E00), height: 1.1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr
                            ? 'Oyunu oynamak için Kullanım Şartları ve Gizlilik Politikası\'nı kabul etmen gerekiyor. Metinleri okumak için altı çizili yazılara dokun.'
                            : 'To play, you need to accept the Terms of Use and the Privacy Policy. Tap the underlined text to read them.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, height: 1.3, color: Color(0xFF6B4423), fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _check(
                        value: _terms,
                        onChanged: (v) => setState(() => _terms = v),
                        label: tr
                            ? TextSpan(children: [_link('Kullanım Şartları', _termsTap), const TextSpan(text: '\'nı okudum ve kabul ediyorum.')])
                            : TextSpan(children: [const TextSpan(text: 'I have read and accept the '), _link('Terms of Use', _termsTap), const TextSpan(text: '.')]),
                      ),
                      _check(
                        value: _privacy,
                        onChanged: (v) => setState(() => _privacy = v),
                        label: tr
                            ? TextSpan(children: [_link('Gizlilik Politikası', _privacyTap), const TextSpan(text: '\'nı okudum ve kabul ediyorum.')])
                            : TextSpan(children: [const TextSpan(text: 'I have read and accept the '), _link('Privacy Policy', _privacyTap), const TextSpan(text: '.')]),
                      ),
                      if (_showGdpr) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF1B6FD1).withOpacity(0.5), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr ? '🇪🇺 AB / AEA / Birleşik Krallık (GDPR)' : '🇪🇺 EU / EEA / UK (GDPR)',
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF14509A)),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tr
                                    ? 'Oyun ilerlemen cihazında saklanır. Reklam ve ölçümleme ortaklarımız (Appodeal vb.) reklam kimliği ve cihaz bilgisi gibi verileri işleyebilir. Reklam tercihlerini bir sonraki adımda Google\'ın resmi formundan seçersin; rızanı istediğin zaman Ayarlar > Reklam Rızasını Yönet\'ten geri alabilir, verilerine erişim/silme haklarını Gizlilik Politikası\'ndaki adrese yazarak kullanabilirsin.'
                                    : 'Your progress is stored on your device. Our ad and measurement partners (e.g. Appodeal) may process data such as the advertising ID and device info. You choose your ad preferences in the next step using Google\'s official form; you can withdraw consent any time in Settings > Manage Ad Consent, and exercise your data access/erasure rights via the address in the Privacy Policy.',
                                style: const TextStyle(fontSize: 12, height: 1.25, color: Color(0xFF4A2C0A), fontWeight: FontWeight.w600),
                              ),
                              _check(
                                value: _gdpr,
                                onChanged: (v) => setState(() => _gdpr = v),
                                label: TextSpan(
                                  text: tr
                                      ? 'Kişisel verilerimin yukarıda açıklanan şekilde işlenmesine açık rıza veriyorum.'
                                      : 'I explicitly consent to the processing of my personal data as described above.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      IgnorePointer(
                        ignoring: !_ready,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _ready ? 1.0 : 0.45,
                          child: CandyButton(
                            label: tr ? 'Kabul Et ve Devam' : 'Accept & Continue',
                            style: CandyStyle.green,
                            height: 58,
                            fontSize: 20,
                            pulse: _ready,
                            onTap: _accept,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _decline,
                        child: Text(
                          tr ? 'Kabul Etmiyorum (Çıkış)' : 'Decline (Exit)',
                          style: const TextStyle(color: Color(0xFF8A3B1B), fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
