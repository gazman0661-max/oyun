import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'localization.dart';

/// Sunucusuz (backend'siz) yerel bildirim sistemi. Su turleri yonetir:
///
/// 1) "Kozmik Ikmal hazir" — oyuncu odulu topladiginda baslayan 2 saatlik
///    bekleme suresi dolunca tetiklenir (bkz. PlayerProgress.
///    grantResupplyReward).
/// 2) "Gunluk seri hatirlatmasi" — oyuncu o gun henuz oynamadiysa, GECE
///    RAHATSIZ ETMEMEK icin sabit bir ogle-sonrasi saatinde (13:00,
///    cihazin kendi saat dilimine gore) günde en fazla 1 kez gonderilir.
/// 3) "Geri cagirma" — oyuncu 3 gundur uygulamayi hic acmadiysa.
/// 4) "Kuyruklu Yildiz acildi" — periyodik event penceresi TAM olarak
///    acildigi anda (deterministik, herkeste ayni an) tetiklenir (bkz.
///    PlayerProgress.nextCometWindowOpen).
/// 5) "Haftalik/aylik gorev hatirlatmasi" — donem bitmeden (haftalikta
///    2, aylikta 3 gun once) hedef henuz tutturulmadiysa bir kez
///    hatirlatir; hedef tutturulup odul alinirsa hemen iptal edilir
///    (bkz. PlayerProgress.refreshPeriodicEventNotifications).
///
/// Tum bildirimler sabit bir ID kullanir (cancel + yeniden schedule),
/// boylece ayni bildirimden asla birden fazla kuyrukta kalmaz.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _resupplyNotificationId = 1001;
  static const _streakNotificationId = 2001;
  static const _comebackNotificationId = 3001;
  static const _cometNotificationId = 4001;
  static const _weeklyQuestNotificationId = 5001;
  static const _monthlyQuestNotificationId = 6001;

  /// Gunluk seri hatirlatmasinin gonderilecegi saat (24 saat formati,
  /// cihazin YEREL saat dilimine gore). Gece rahatsiz etmemek icin
  /// bilerek ogleden sonraya (13:00) sabitlendi.
  static const _streakReminderHour = 13;

  /// Haftalik/aylik gorev hatirlatmalarinin gonderilecegi saat — streak
  /// hatirlatmasindan (13:00) kasitli olarak farkli bir ogleden-sonra
  /// saati, ayni gun ikisi ust uste gelmesin diye.
  static const _questReminderHour = 18;

  /// "Geri cagirma" bildirimi, oyuncu uygulamayi acmadan bu kadar sure
  /// gecince gonderilir. Her acilista/resumed'de yeniden 3 gune
  /// ertelenir (bkz. refreshComebackReminder) — yani sadece GERCEKTEN
  /// 3 gundur hic acilmadiysa tetiklenir.
  static const _comebackAfter = Duration(days: 3);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _initFuture;

  /// main() / splash_screen.dart boot akisinda, diger arka plan
  /// kurulumlarinin (ses, reklam SDK'si) yaninda cagirilir. Web'de ya da
  /// herhangi bir hata durumunda sessizce devre disi kalir — bildirimler
  /// olmadan da oyun tamamen calisir durumda kalmali. Ayni anda birden
  /// fazla yerden cagirilirsa (orn. resupply odulu + streak hatirlatmasi
  /// ayni anda tetiklenirse) tek bir init calismasini paylasir.
  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    if (kIsWeb) return;
    try {
      tz_data.initializeTimeZones();
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (_) {
      // Cihaz saat dilimi alinamazsa UTC'ye duser; bildirim yine de
      // gonderilir, sadece saat hesaplamasi cihaz yerelinden sapabilir.
    }

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      // NOT: DarwinInitializationSettings/DarwinNotificationDetails iOS ve
      // macOS icin ortak ayar siniflaridir, ancak resolvePlatformSpecific
      // Implementation icin hala platforma ozel sinif kullanilir: iOS icin
      // IOSFlutterLocalNotificationsPlugin (macOS icin ayrica
      // MacOSFlutterLocalNotificationsPlugin var).
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

      _ready = true;
    } catch (e) {
      debugPrint('[NotificationService] init basarisiz: $e');
    }
  }

  /// "Kozmik Ikmal" odulu toplandiginda cagirilir. [readyAt] tam olarak
  /// bekleme suresinin (2 saat) bitecegi zaman damgasidir.
  Future<void> scheduleResupplyReady(DateTime readyAt) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _resupplyNotificationId);
      await _plugin.zonedSchedule(
        id: _resupplyNotificationId,
        title: t('notif_resupplyTitle'),
        body: t('notif_resupplyBody'),
        scheduledDate: tz.TZDateTime.from(readyAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'resupply_channel',
            'Kozmik İkmal',
            channelDescription: 'Kozmik İkmal ödülleri hazır olduğunda bildirir.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] resupply schedule basarisiz: $e');
    }
  }

  /// Oyuncu Kozmik Ikmal odulunu bildirim gelmeden ONCE, uygulama
  /// icindeyken zaten aldiysa (normal akis) bekleyen bildirimi iptal eder.
  Future<void> cancelResupplyReady() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _resupplyNotificationId);
  }

  /// Gunluk seri hatirlatmasini yeniden hesaplar/kurar. Su noktalarda
  /// cagirilmali: uygulama acilista (splash bitince), uygulama on plana
  /// donduğünde (resumed) ve gunluk bulmaca tamamlandiginda.
  ///
  /// [playedToday] true ise (bugunku gunluk bulmaca zaten tamamlandiysa)
  /// hatirlatma YARINKI 13:00'e ertelenir. False ise ve saat henuz
  /// 13:00'i gecmediyse BUGUN 13:00'e, gectiyse yine YARINA kurulur.
  Future<void> refreshDailyStreakReminder({required bool playedToday}) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _streakNotificationId);

      final now = tz.TZDateTime.now(tz.local);
      var target = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        _streakReminderHour,
      );
      final todayWindowPassed = now.isAfter(target);
      if (playedToday || todayWindowPassed) {
        target = target.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        id: _streakNotificationId,
        title: t('notif_streakTitle'),
        body: t('notif_streakBody'),
        scheduledDate: target,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_streak_channel',
            'Günlük Seri Hatırlatması',
            channelDescription:
                'Günlük bulmacayı oynamadıysan günde bir kez (öğleden sonra) hatırlatır.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] streak reminder basarisiz: $e');
    }
  }

  /// Geri cagirma bildirimini yeniden 3 gune erteler. Splash acilista
  /// VE uygulama on plana her donduğünde (didChangeAppLifecycleState ->
  /// resumed) cagrilmali — boylece oyuncu duzenli aciyorsa bildirim
  /// HICBIR ZAMAN tetiklenmez, sadece gercekten 3 gundur hic acmadiysa
  /// ("uzun sureli sessiz kullanici") gonderilir. Gunluk seri
  /// hatirlatmasindan (13:00, ayni gun icin) farkli olarak burada saat
  /// onemli degil, sadece "3 gun gecti mi" onemli.
  Future<void> refreshComebackReminder() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _comebackNotificationId);
      final target =
          tz.TZDateTime.now(tz.local).add(_comebackAfter);
      await _plugin.zonedSchedule(
        id: _comebackNotificationId,
        title: t('notif_comebackTitle'),
        body: t('notif_comebackBody'),
        scheduledDate: target,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'comeback_channel',
            'Geri Çağırma Hatırlatması',
            channelDescription:
                'Uzun süredir oyuna girmeyen oyunculara birkaç günde bir hatırlatma gönderir.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] comeback reminder basarisiz: $e');
    }
  }

  /// [dateUtc]'nin sadece YIL/AY/GUN kismini alip cihazin YEREL saat
  /// diliminde _questReminderHour'a oturtur. Bu an zaten gecmisse (ör.
  /// uygulama o gun/o an gec acildiysa, ya da donem bitmesine 2-3 gunden
  /// az kalmisken ilk kez kuruluyorsa) hatirlatma sessizce kaybolmasin
  /// diye "simdi + birkac dakika"ya kaydirilir.
  tz.TZDateTime _resolveReminderTime(DateTime dateUtc) {
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(
      tz.local,
      dateUtc.year,
      dateUtc.month,
      dateUtc.day,
      _questReminderHour,
    );
    if (target.isBefore(now)) {
      target = now.add(const Duration(minutes: 5));
    }
    return target;
  }

  /// Kuyruklu Yıldız penceresi bir sonraki sefer TAM olarak [opensAt]
  /// aninda acilacak (bkz. PlayerProgress.nextCometWindowOpen) — herkeste
  /// ayni deterministik an oldugu icin resupply bildirimi gibi kesin bir
  /// zamanda (zonedSchedule) planlanir; ogleden-sonra kisitlamasi yok,
  /// cunku aciliş saati zaten gunun her saatine denk gelebilir ve
  /// oyuncunun tam o an haberdar olmasi degerli.
  Future<void> scheduleCometWindowOpen(DateTime opensAt) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _cometNotificationId);
      await _plugin.zonedSchedule(
        id: _cometNotificationId,
        title: t('notif_cometTitle'),
        body: t('notif_cometBody'),
        scheduledDate: tz.TZDateTime.from(opensAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'comet_channel',
            'Kuyruklu Yıldız',
            channelDescription:
                'Kuyruklu Yıldız etkinliği açıldığında bildirir.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] comet schedule basarisiz: $e');
    }
  }

  /// Kuyruklu Yıldız penceresi zaten acikken (ör. oyuncu event acilir
  /// acilmaz oynadiysa) bekleyen "acildi" bildirimini iptal eder.
  Future<void> cancelCometWindowOpen() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _cometNotificationId);
  }

  /// Haftalık görev bu hafta içinde HENÜZ tamamlanmadıysa, hafta bitmeden
  /// [remindOnUtc] gününde (saat _questReminderHour, cihaz yereli) bir kez
  /// hatırlatır. Hedef tutturulup ödül alınırsa (bkz. PlayerProgress.
  /// refreshPeriodicEventNotifications) cancelWeeklyQuestReminder ile
  /// hemen iptal edilir.
  Future<void> scheduleWeeklyQuestReminder(DateTime remindOnUtc) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _weeklyQuestNotificationId);
      await _plugin.zonedSchedule(
        id: _weeklyQuestNotificationId,
        title: t('notif_weeklyQuestTitle'),
        body: t('notif_weeklyQuestBody'),
        scheduledDate: _resolveReminderTime(remindOnUtc),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'weekly_quest_channel',
            'Haftalık Görev Hatırlatması',
            channelDescription:
                'Haftalık görev bitmeden önce, tamamlanmadıysa hatırlatır.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] weekly quest reminder basarisiz: $e');
    }
  }

  Future<void> cancelWeeklyQuestReminder() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _weeklyQuestNotificationId);
  }

  /// scheduleWeeklyQuestReminder ile birebir ayni mantik, sadece aylik
  /// donem/kanal/metin uzerinden.
  Future<void> scheduleMonthlyQuestReminder(DateTime remindOnUtc) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _monthlyQuestNotificationId);
      await _plugin.zonedSchedule(
        id: _monthlyQuestNotificationId,
        title: t('notif_monthlyQuestTitle'),
        body: t('notif_monthlyQuestBody'),
        scheduledDate: _resolveReminderTime(remindOnUtc),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'monthly_quest_channel',
            'Aylık Görev Hatırlatması',
            channelDescription:
                'Aylık görev bitmeden önce, tamamlanmadıysa hatırlatır.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint(
          '[NotificationService] monthly quest reminder basarisiz: $e');
    }
  }

  Future<void> cancelMonthlyQuestReminder() async {
    await init();
    if (!_ready) return;
    await _plugin.cancel(id: _monthlyQuestNotificationId);
  }
}
