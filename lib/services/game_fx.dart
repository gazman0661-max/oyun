import 'dart:async';
import 'dart:math';

import 'haptic_service.dart';
import 'sfx_service.dart';

/// OYUNDAKI TUM SES + TITRESIM KARARLARI TEK YERDE.
///
/// game_board.dart ve menuler sadece "bu an oldu" der (throwBall, merge,
/// orderDelivered ...), hangi sesin/titresimin calacagini burasi belirler.
/// Hissi degistirmek istersen sadece bu dosyadaki sayilara bak.
///
/// GENEL KURALLAR (yorucu olmasin diye):
///  * Sik olan olaylar (atis, carpisma) KISA ve yumusak; nadir olaylar
///    (yeni seviye, bolum sonu) uzun ve gösterişli.
///  * Carpisma titresimi sadece belirli bir hizin ustunde ve en fazla
///    ~8 kez/sn; duvar carpmasi sadece ses (titresim yok).
///  * Merge sesi seviyeyle YUKSELIR, titresim de siddetlenir.
class GameFx {
  GameFx._();
  static final GameFx instance = GameFx._();

  final SfxService _sfx = SfxService.instance;
  final HapticService _hap = HapticService.instance;

  // ── Ayar sabitleri ──────────────────────────────────────────
  // Hizlar px/sn cinsinden "birbirine yaklasma hizi" (relVel).
  static const double _hitSoundMinSpeed = 45; // altindaki carpisma sessiz
  static const double _hitLightHapticSpeed = 150; // hafif titresim esigi
  static const double _hitMediumHapticSpeed = 260; // orta titresim esigi
  static const double _wallSoundMinSpeed = 80; // duvara carpma sesi esigi

  void _later(int ms, void Function() action) {
    if (ms <= 0) {
      action();
    } else {
      Timer(Duration(milliseconds: ms), action);
    }
  }

  // ── Arayuz ──────────────────────────────────────────────────
  /// Buton/menu dokunusu: minik "tik" + en hafif titresim.
  void uiTap() {
    _sfx.play('tap', volume: 0.6, minGapMs: 50);
    _hap.pulse(HapticService.tick, minGapMs: 50);
  }

  /// Odul alindi (gunluk odul, gorev, enerji reklami, dukkan alimi).
  void reward() {
    _sfx.play('reward', volume: 0.8);
    _hap.pattern([
      [0, HapticService.light],
      [70, HapticService.medium],
    ]);
  }

  /// Yetersiz coin vb. "olmaz" geri bildirimi: iki kisa tok darbe.
  void denied() {
    _sfx.play('denied', volume: 0.7);
    _hap.pattern([
      [0, HapticService.medium],
      [110, HapticService.medium],
    ]);
  }

  // ── Oyun ici ────────────────────────────────────────────────
  /// Obje firlatildi: yumusak "fiiit" + hafif titresim.
  void throwBall() {
    _sfx.play('throw', volume: 0.55, minGapMs: 60);
    _hap.pulse(HapticService.light, minGapMs: 80);
  }

  /// Iki FARKLI seviyeli obje carpisti. [speed] = yaklasma hizi.
  /// Buyuk objeler daha derin/tok ses cikarir (hit_1 ince tik ... hit_4 derin tok).
  void impact({required int levelA, required int levelB, required double speed}) {
    if (speed >= _hitSoundMinSpeed) {
      final big = max(levelA, levelB);
      final variant = ((big - 1) ~/ 2 + 1).clamp(1, 4); // 1-2->1, 3-4->2, 5-6->3, 7-8->4
      final volume = (0.25 + speed / 400).clamp(0.25, 0.9).toDouble();
      // group: 4 farkli hit sesi TEK bir kisitlama sayacini paylasir.
      _sfx.play('hit_$variant', volume: volume, minGapMs: 55, group: 'hit');
    }
    if (speed >= _hitMediumHapticSpeed) {
      _hap.pulse(HapticService.medium, minGapMs: 130);
    } else if (speed >= _hitLightHapticSpeed) {
      _hap.pulse(HapticService.light, minGapMs: 130);
    }
  }

  /// Obje masanin kenarina carpip durdu: yumusak "tok" (titresim YOK -
  /// her atista olacagi icin titresim yorucu olurdu).
  void wallHit(double speed) {
    if (speed < _wallSoundMinSpeed) return;
    final volume = (0.25 + speed / 500).clamp(0.25, 0.7).toDouble();
    _sfx.play('wall', volume: volume, minGapMs: 70, group: 'wall');
  }

  /// Iki obje birlesti ve [newLevel] seviyesi olustu.
  /// [isNewBest]: bu tur ilk kez bu kadar yuksek bir seviyeye ulasildi
  /// ("seviye atlama" hissi: ekstra parlak ses + guclu titresim).
  /// [delayMs]: ayni karede birden fazla merge olursa (zincirleme)
  /// birbirinin ustune binmesin diye kademeli geciktirilir.
  void merge(int newLevel, {bool isNewBest = false, int delayMs = 0}) {
    final lvl = newLevel.clamp(2, 8);
    _later(delayMs, () {
      _sfx.play('merge_$lvl', volume: (0.7 + 0.04 * (lvl - 2)).clamp(0.0, 0.95).toDouble());
      if (isNewBest) {
        _sfx.play('new_tier', volume: 0.7);
      }
      if (isNewBest) {
        // ta-DUM: yeni seviye
        _hap.pattern([
          [0, HapticService.heavy],
          [110, HapticService.medium],
        ]);
      } else if (lvl <= 3) {
        _hap.pulse(HapticService.light);
      } else if (lvl <= 5) {
        _hap.pulse(HapticService.medium);
      } else {
        _hap.pulse(HapticService.heavy);
      }
    });
  }

  /// EN ust seviye iki obje birlesip yok oldu (bonus coin patlamasi).
  void mergeMax({int delayMs = 0}) {
    _later(delayMs, () {
      _sfx.play('merge_max', volume: 1.0);
      _hap.pattern([
        [0, HapticService.heavy],
        [100, HapticService.medium],
        [200, HapticService.heavy],
      ]);
    });
  }

  /// Siparis teslim edildi: "ka-ching" + cift kisa tik.
  void orderDelivered() {
    _sfx.play('coin', volume: 0.8, minGapMs: 80);
    _hap.pattern([
      [0, HapticService.light],
      [75, HapticService.light],
    ]);
  }

  /// Bolum tamamlandi: fanfar + artan siddette titresim, sonda kivilcim tikleri.
  /// (Ses zamanlamasi: fanfar notalari 0/120/240 ms, akor 400 ms, kivilcimlar ~950 ms+)
  void chapterComplete() {
    _sfx.play('chapter_complete', volume: 1.0);
    _hap.pattern([
      [0, HapticService.light],
      [120, HapticService.medium],
      [240, HapticService.heavy],
      [400, HapticService.heavy],
      [950, HapticService.light],
      [1035, HapticService.light],
      [1120, HapticService.light],
    ]);
  }

  /// Masa doldu: yumusak alcalan "ahh" + iki agir darbe.
  void gameOver() {
    _sfx.play('game_over', volume: 0.9);
    _hap.pattern([
      [0, HapticService.heavy],
      [180, HapticService.heavy],
      [420, HapticService.medium],
    ]);
  }
}
