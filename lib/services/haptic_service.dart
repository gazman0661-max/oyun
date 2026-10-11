import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Titresim (haptic) geri bildirimi. Tercih kalici saklanir; profil
/// ekranindaki anahtardan kapatilabilir. Desteklemeyen platformlarda
/// (web onizleme vb.) sessizce hicbir sey yapmaz.
class HapticService extends ChangeNotifier {
  HapticService._();
  static final HapticService instance = HapticService._();

  static const _prefsKey = 'cs_haptics_enabled_v1';

  bool enabled = true;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefsKey) ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    if (value) light();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {}
  }

  void _run(Future<void> Function() f) {
    if (!enabled) return;
    try {
      f().catchError((_) {});
    } catch (_) {}
  }

  /// Hafif: gezegen birakma, kucuk birlesme.
  void light() => _run(HapticFeedback.lightImpact);

  /// Orta: orta boy birlesme, guclendirici kullanimi.
  void medium() => _run(HapticFeedback.mediumImpact);

  /// Guclu: buyuk gezegen, yuksek combo, oyun sonu.
  void heavy() => _run(HapticFeedback.heavyImpact);

  /// Cok hafif "tik": nisan/secim.
  void tick() => _run(HapticFeedback.selectionClick);
}
