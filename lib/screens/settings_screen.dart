import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../services/game_fx.dart';
import '../services/cloud_save_service.dart';
import '../services/ad_service.dart';
import '../widgets/ui_kit.dart';
import 'legal_screen.dart';

/// SECENEKLER: muzik, ses efektleri, titresim, dil, kullanim sartlari ve
/// gizlilik politikasi.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool get _tr => AppStrings.instance.language == AppLanguage.tr;

  final CloudSaveService _cloud = CloudSaveService.instance;

  @override
  void initState() {
    super.initState();
    _cloud.addListener(_onCloud);
  }

  @override
  void dispose() {
    _cloud.removeListener(_onCloud);
    super.dispose();
  }

  void _onCloud() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  Future<void> _cloudSignIn() async {
    GameFx.instance.uiTap();
    final ok = await _cloud.signIn();
    if (!mounted) return;
    _snack(ok
        ? (_tr ? 'Google Play Games\'e giriş yapıldı' : 'Signed in to Google Play Games')
        : (_tr ? 'Giriş yapılamadı' : 'Sign-in failed'));
  }

  void _toggleMusic() {
    final p = GameProgress.instance;
    p.setMusicEnabled(!p.musicEnabled);
    setState(() {});
  }

  void _toggleSfx() {
    final p = GameProgress.instance;
    p.setSoundEnabled(!p.soundEnabled);
    setState(() {});
    if (p.soundEnabled) GameFx.instance.uiTap(); // acilirken ornek "tik"
  }

  void _toggleHaptics() {
    final p = GameProgress.instance;
    p.setHapticsEnabled(!p.hapticsEnabled);
    setState(() {});
    if (p.hapticsEnabled) GameFx.instance.uiTap(); // acilirken hissettir
  }

  void _toggleLanguage() {
    GameFx.instance.uiTap();
    setState(() => AppStrings.instance.toggle());
  }

  void _open(LegalKind k) {
    GameFx.instance.uiTap();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LegalScreen(kind: k)));
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF8A5A2B), letterSpacing: 1),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = GameProgress.instance;
    final tr = _tr;
    return GameScaffold(
      title: tr ? 'Seçenekler' : 'Settings',
      showCurrency: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(26, 4, 26, 40),
        children: [
          _section(tr ? 'Ses' : 'Sound'),
          _SettingToggle(label: tr ? 'Müzik' : 'Music', value: p.musicEnabled, onTap: _toggleMusic),
          const SizedBox(height: 10),
          _SettingToggle(label: tr ? 'Ses Efektleri' : 'Sound Effects', value: p.soundEnabled, onTap: _toggleSfx),
          _section(tr ? 'Cihaz' : 'Device'),
          _SettingToggle(label: tr ? 'Titreşim' : 'Vibration', value: p.hapticsEnabled, onTap: _toggleHaptics),
          _section(tr ? 'Oyun Hesabı' : 'Game Account'),
          if (!_cloud.signedIn)
            CandyButton(
              label: _cloud.busy ? (tr ? 'Bağlanıyor…' : 'Connecting…') : (tr ? 'Google Play Games ile Giriş' : 'Sign in with Google Play Games'),
              icon: Icons.sports_esports,
              style: CandyStyle.green,
              height: 54,
              fontSize: 16,
              onTap: _cloud.busy ? () {} : _cloudSignIn,
            )
          else ...[
            Center(
              child: Text(
                tr ? '✔ Google Play Games bağlı – ilerleme otomatik kaydediliyor' : '✔ Google Play Games connected – progress saves automatically',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32)),
              ),
            ),
          ],
          _section(tr ? 'Dil' : 'Language'),
          CandyButton(
            label: tr ? 'TÜRKÇE' : 'ENGLISH',
            icon: Icons.language,
            style: CandyStyle.blue,
            height: 54,
            fontSize: 18,
            onTap: _toggleLanguage,
          ),
          _section(tr ? 'Gizlilik' : 'Privacy'),
          CandyButton(
            label: tr ? 'Reklam Rızasını Yönet' : 'Manage Ad Consent',
            icon: Icons.privacy_tip_outlined,
            style: CandyStyle.blue,
            height: 54,
            fontSize: 16,
            onTap: () {
              GameFx.instance.uiTap();
              AdService.instance.openAdConsentForm();
            },
          ),
          _section(tr ? 'Hakkında' : 'About'),
          CandyButton(
            label: tr ? 'Kullanım Şartları' : 'Terms of Use',
            style: CandyStyle.blue,
            height: 54,
            fontSize: 17,
            onTap: () => _open(LegalKind.terms),
          ),
          const SizedBox(height: 10),
          CandyButton(
            label: tr ? 'Gizlilik Politikası' : 'Privacy Policy',
            style: CandyStyle.blue,
            height: 54,
            fontSize: 17,
            onTap: () => _open(LegalKind.privacy),
          ),
          const SizedBox(height: 22),
          const Center(
            child: Text('Merge Worlds  •  v1.0.0',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF8A5A2B))),
          ),
        ],
      ),
    );
  }
}

/// Isaret kutulu mavi ayar butonu: acikken kutuda tik, kapaliyken buton grilesir.
class _SettingToggle extends StatelessWidget {
  final String label;
  final bool value;
  final VoidCallback onTap;
  const _SettingToggle({required this.label, required this.value, required this.onTap});

  static const ColorFilter _grey = ColorFilter.matrix(<double>[
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0,
    0.33, 0.33, 0.33, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Positioned.fill(child: SlicedBar(base: 'assets/images/ui/btn_blue', filter: value ? null : _grey)),
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 22, bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFF184C9A), width: 2),
                    ),
                    child: value
                        ? const Icon(Icons.check_rounded, size: 22, color: Color(0xFF2E9E2E))
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Color(0xFF184C9A), offset: Offset(0, 2), blurRadius: 3)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
