import 'dart:async';
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'analytics_service.dart';
import 'inbox_service.dart';

/// FIREBASE BASLATMA + PUSH BILDIRIMI (Firebase Cloud Messaging) - "Gelen kutunda mesajin var".
///
/// Ayni Firebase uygulamasi kullanim istatistigi (Firebase Analytics) icin de baslatilir.
///
/// - Bildirimi sistem gosterir (uygulama kapaliyken de); icerigi sabit metindir, mesajin kendisi
///   bildirimde gorunmez. Metinler: android/app/src/main/res/values*/strings.xml (inbox_push_*).
/// - Firebase bilgileri google-services.json OLMADAN buradan verilir. Doldurulana kadar
///   [isConfigured] false'tur ve servis hicbir sey yapmaz (oyun etkilenmez).
/// - Cihaz token'i InboxService.setPushToken ile worker'a gider (yalnizca degisince).
/// - Herkese giden mesajlar icin cihaz 'all' konusuna abone olur (abonelik Google'a gider,
///   worker'a istek olmaz).
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  // TODO: Firebase konsolu > Proje ayarlari > Uygulamalariniz > Android (com.astrofelyx.pro).
  // Ayni degerler indirilen google-services.json icinde de yazar:
  //   projectId        = project_info.project_id
  //   messagingSenderId= project_info.project_number
  //   appId            = client[0].client_info.mobilesdk_app_id
  //   apiKey           = client[0].api_key[0].current_key
  // (Bunlar gizli anahtar degildir; her APK'nin icinde zaten bulunur.)
  static const String projectId = 'BURAYA_PROJECT_ID';
  static const String messagingSenderId = 'BURAYA_SENDER_ID';
  static const String appId = 'BURAYA_APP_ID';
  static const String apiKey = 'BURAYA_API_KEY';

  static const String topicAll = 'all';

  static bool get isConfigured =>
      !projectId.startsWith('BURAYA') &&
      !messagingSenderId.startsWith('BURAYA') &&
      !appId.startsWith('BURAYA') &&
      !apiKey.startsWith('BURAYA');

  bool _started = false;
  final Random _rng = Random();

  /// Uygulama acilisinda, arayuz ekrandayken BEKLENMEDEN cagrilir.
  Future<void> init() async {
    if (_started || !isConfigured) return;
    _started = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
        ),
      ).timeout(const Duration(seconds: 10));
      // Kullanim istatistigi: Firebase hazir, ogretici hunisi olaylari artik Firebase'e de gider.
      // (Reklam/GDPR onayindan bagimsizdir; yalnizca Sartlar/Gizlilik onayindan sonra baslar.)
      AnalyticsService.instance.sink = (name, params) {
        unawaited(FirebaseAnalytics.instance.logEvent(name: name, parameters: params).catchError((_) {}));
      };
      final fm = FirebaseMessaging.instance;

      // Uygulama ONDEYKEN gelen push'u sistem gostermez: gelen kutusunu yenile. Herkese giden bir
      // mesajda binlerce cihaz ayni anda istek atmasin diye 0-30 sn rastgele gecikme.
      FirebaseMessaging.onMessage.listen((_) {
        Future<void>.delayed(Duration(seconds: _rng.nextInt(30)), () {
          unawaited(InboxService.instance.sync(force: true));
        });
      });
      // Arka plandaki uygulama bildirime dokunularak acildi: oyuncu bekliyor, hemen yenile.
      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        unawaited(InboxService.instance.sync(force: true));
      });
      // (Kapaliyken bildirimle acilis zaten acilis senkronuyla yenilenir.)

      fm.onTokenRefresh.listen((t) => unawaited(InboxService.instance.setPushToken(t)));
      unawaited(fm.subscribeToTopic(topicAll).catchError((_) {}));
      final t = await fm.getToken();
      if (t != null) await InboxService.instance.setPushToken(t);
    } catch (_) {
      // Firebase / Play Hizmetleri yoksa push sessizce devre disi kalir; oyun etkilenmez.
    }
  }
}
