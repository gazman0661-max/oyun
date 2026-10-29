import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_extra.dart';

enum AppLanguage { tr, en, ru, es, pt, ja }

/// Uygulama genelinde TR / EN / RU metinlerini yoneten, tercihi
/// SharedPreferences'a kaydeden basit bir ChangeNotifier singleton.
/// HTML prototipindeki t(key) fonksiyonunun Dart karsiligi.
class AppLocale extends ChangeNotifier {
  static final AppLocale instance = AppLocale._();
  AppLocale._();

  static const _prefsKey = 'cs_lang_v1';
  static const _chosenPrefsKey = 'cs_lang_chosen_v1';

  AppLanguage _lang = AppLanguage.tr;
  AppLanguage get language => _lang;

  bool _hasChosen = false;
  bool get hasChosenLanguage => _hasChosen;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    _hasChosen = prefs.getBool(_chosenPrefsKey) ?? false;
    _lang = switch (code) {
      'en' => AppLanguage.en,
      'ru' => AppLanguage.ru,
      'es' => AppLanguage.es,
      'pt' => AppLanguage.pt,
      'ja' => AppLanguage.ja,
      _ => AppLanguage.tr,
    };
    notifyListeners();
  }

  /// İlk açılıştaki dil seçim ekranından çağrılır: dili ayarlar VE bir
  /// daha o ekranın gösterilmemesi için "seçildi" bayrağını kaydeder.
  Future<void> setInitialLanguage(AppLanguage lang) async {
    _lang = lang;
    _hasChosen = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final code = _codeOf(lang);
    await prefs.setString(_prefsKey, code);
    await prefs.setBool(_chosenPrefsKey, true);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_lang == lang) return;
    _lang = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final code = _codeOf(lang);
    await prefs.setString(_prefsKey, code);
  }

  static String _codeOf(AppLanguage lang) => switch (lang) {
        AppLanguage.tr => 'tr',
        AppLanguage.en => 'en',
        AppLanguage.ru => 'ru',
        AppLanguage.es => 'es',
        AppLanguage.pt => 'pt',
        AppLanguage.ja => 'ja',
      };

  /// _strings listesindeki sira (TR/EN/RU). Yeni diller (es/pt/ja) ayri
  /// tablolardan okunur; eksik anahtar Ingilizceye duser.
  int get _i => switch (_lang) {
        AppLanguage.tr => 0,
        AppLanguage.ru => 2,
        _ => 1,
      };

  Map<String, String>? get _extra => switch (_lang) {
        AppLanguage.es => kStringsEs,
        AppLanguage.pt => kStringsPt,
        AppLanguage.ja => kStringsJa,
        _ => null,
      };

  /// Bir anahtari mevcut dile cevirir. {ad} gibi yer tutuculari [args]
  /// ile degistirir (orn. t('win_missionCompleted', {'n': '7'})).
  String t(String key, [Map<String, String>? args]) {
    final list = _strings[key];
    final extra = _extra;
    var s = extra != null
        ? (extra[key] ??
            ((list != null && list.length > 1) ? list[1] : key))
        : ((list != null && _i < list.length) ? list[_i] : key);
    if (args != null) {
      args.forEach((k, v) {
        s = s.replaceAll('{$k}', v);
      });
    }
    return s;
  }

  static final Map<String, List<String>> _strings = {
    // ---- Genel / marka ----
    'appName': ['AstroFelyx', 'AstroFelyx', 'AstroFelyx'],
    'langSelect_title': [
      'Bir dil seç',
      'Choose a language',
      'Выберите язык',
    ],
    'langSelect_subtitle': [
      'Bu, oyun içindeki tüm metinlerin dilini belirler. Daha sonra '
          'profil ekranından değiştirebilirsin.',
      'This sets the language for all text in the game. You can change '
          'it later from the profile screen.',
      'Это определяет язык всех текстов в игре. Позже вы сможете '
          'изменить его в профиле.',
    ],
    'langSelect_continue': ['Devam Et', 'Continue', 'Продолжить'],
    'splashTagline': [
      'Gezegen Birleştirme',
      'Planet Merge',
      'Слияние планет',
    ],

    // ---- Gizlilik / Kullanım Şartları / GDPR onay popup'ı ----
    'legal_privacyPolicy': [
      'Gizlilik Politikası',
      'Privacy Policy',
      'Политика конфиденциальности',
    ],
    'legal_terms': [
      'Kullanım Şartları',
      'Terms of Use',
      'Условия использования',
    ],
    'consent_title': [
      'Kullanım Şartları & Gizlilik Politikası',
      'Terms of Use & Privacy Policy',
      'Условия использования и конфиденциальность',
    ],
    'consent_desc': [
      'Oyuna devam edebilmek için lütfen Kullanım Şartlarını ve Gizlilik '
          'Politikasını okuyup onaylayın.',
      'Please read and accept the Terms of Use and Privacy Policy to '
          'continue playing.',
      'Чтобы продолжить игру, пожалуйста, ознакомьтесь и примите Условия '
          'использования и Политику конфиденциальности.',
    ],
    'consent_euText': [
      'Avrupa Birliği (AB) bölgesinde bulunduğunuz için reklam '
          'tercihlerinizi seçebilirsiniz. Bu seçimi istediğiniz zaman '
          'Profil ekranından değiştirebilirsiniz.',
      'Since you are in the European Union (EU) region, you can choose '
          'your advertising preference. You can change this choice anytime '
          'from the Profile screen.',
      'Поскольку вы находитесь в регионе Европейского союза (ЕС), вы '
          'можете выбрать свои рекламные предпочтения. Вы можете изменить '
          'этот выбор в любое время в экране профиля.',
    ],
    'consent_euAccept': [
      'Kişiselleştirilmiş Reklamları Kabul Et',
      'Accept Personalized Ads',
      'Принять персонализированную рекламу',
    ],
    'consent_euDecline': [
      'Kişiselleştirilmemiş Reklamları Kabul Et',
      'Accept Non-Personalized Ads',
      'Принять неперсонализированную рекламу',
    ],
    'consent_acceptContinue': [
      'Kabul Et ve Devam Et',
      'Accept and Continue',
      'Принять и продолжить',
    ],

    // ---- Ana ekran ----
    'home_resupplyTitle': [
      'Kozmik İkmal',
      'Cosmic Resupply',
      'Космическое пополнение',
    ],
    'home_resupplyReady': ['✅ Hazır!', '✅ Ready!', '✅ Готово!'],
    'home_dailyTitle': [
      'Günlük Meydan Okuma',
      'Daily Challenge',
      'Ежедневный вызов',
    ],
    'home_dailyDoneTitle': [
      'Bugün Tamamlandı',
      'Completed Today',
      'Сегодня выполнено',
    ],
    'home_dailySubtitle': [
      'Herkese aynı meydan okuma — seriyi koru!',
      'Same challenge for everyone — keep your streak!',
      'Одно испытание для всех — сохрани серию!',
    ],
    'home_dailyDoneSubtitle': [
      'Yarın tekrar gel.',
      'Come back tomorrow.',
      'Приходи завтра.',
    ],

    // ---- Profil ----
    'profile_totalStars': [
      'Keşfedilen Gezegen',
      'Planets Found',
      'Найдено планет',
    ],
    'profile_stagesCleared': [
      'Oynanan Oyun',
      'Games Played',
      'Сыграно игр',
    ],
    'profile_totalScore': ['Toplam Skor', 'Total Score', 'Общий счёт'],
    'profile_about': ['Hakkında', 'About', 'О игре'],
    'profile_aboutText': [
      'AstroFelyx, uzay temalı özgün bir bulmaca oyunudur; tüm görseller '
          'kod içinde çizilir, harici içerik veya üçüncü taraf marka '
          'kullanmaz.',
      'AstroFelyx is an original space-themed puzzle game; every visual '
          'is drawn in code, with no external content or third-party '
          'branding.',
      'AstroFelyx — оригинальная космическая головоломка; вся графика '
          'рисуется в коде, без внешнего контента и сторонних брендов.',
    ],
    'profile_language': ['Dil', 'Language', 'Язык'],
    'profile_soundSettings': ['Ses Ayarları', 'Sound Settings', 'Настройки звука'],
    'profile_musicLabel': ['Müzik', 'Music', 'Музыка'],
    'profile_sfxLabel': ['Ses Efektleri', 'Sound Effects', 'Звуковые эффекты'],
    'resupply_oddsTitle': [
      'Ödül İhtimalleri',
      'Reward Odds',
      'Шансы наград',
    ],
    'resupply_oddsHint': [
      'Reklamı izleyince aşağıdaki ihtimallerle bir ödül kazanırsın:',
      'Watching the ad grants one of these rewards with the odds below:',
      'Просмотр рекламы даёт одну из наград с указанными шансами:',
    ],
    'resupply_oddsPercent': [
      '%{p} ·',
      '{p}% ·',
      '{p}% ·',
    ],
    'resupply_oddsClose': ['Anladım', 'Got it', 'Понятно'],
    'notif_resupplyTitle': [
      'Kozmik İkmalde Ödüllerin Hazır! 🛰️',
      'Your Cosmic Resupply rewards are ready! 🛰️',
      'Награды Космического Снабжения готовы! 🛰️',
    ],
    'notif_resupplyBody': [
      'Yeni ödülünü almak için oyuna dön.',
      'Come back to claim your new reward.',
      'Вернитесь в игру, чтобы забрать награду.',
    ],
    'notif_streakTitle': [
      'Serini bozma! 🔥',
      'Don\'t break your streak! 🔥',
      'Не теряй свою серию! 🔥',
    ],
    'notif_streakBody': [
      'Bugün henüz oynamadın, günlük serini korumak için birkaç dakikanı ayır.',
      'You haven\'t played today yet — keep your daily streak alive.',
      'Вы ещё не играли сегодня — сохраните свою ежедневную серию.',
    ],
    'notif_comebackTitle': [
      'Gezegenlerin seni bekliyor 🪐',
      'Your planets are waiting 🪐',
      'Твои планеты ждут тебя 🪐',
    ],
    'notif_comebackBody': [
      'Birkaç gündür uğramadın — yörünge kaldığı yerde duruyor, devam etmeye ne dersin?',
      'It\'s been a few days — your orbit is right where you left it. Ready to continue?',
      'Тебя давно не было — орбита ждёт там же, где ты остановился. Продолжим?',
    ],
    'notif_cometTitle': [
      'Kuyruklu Yıldız açıldı! ☄️',
      'The Comet Event just opened! ☄️',
      'Событие «Комета» открыто! ☄️',
    ],
    'notif_cometBody': [
      'Sınırlı süreli özel tahta ve bonus ödül seni bekliyor.',
      'A limited-time special board and bonus reward are waiting.',
      'Тебя ждёт особая доска на ограниченное время и бонусная награда.',
    ],
    'notif_weeklyQuestTitle': [
      'Haftalık görevin yarım kaldı 📅',
      'Your weekly quest is unfinished 📅',
      'Твоё еженедельное задание не завершено 📅',
    ],
    'notif_weeklyQuestBody': [
      'Hafta bitmeden tamamla, ödülünü kaçırma.',
      'Finish it before the week ends so you don\'t miss the reward.',
      'Заверши его до конца недели, чтобы не упустить награду.',
    ],
    'notif_monthlyQuestTitle': [
      'Aylık görevin yarım kaldı 🗓️',
      'Your monthly quest is unfinished 🗓️',
      'Твоё ежемесячное задание не завершено 🗓️',
    ],
    'notif_monthlyQuestBody': [
      'Ay bitmeden tamamla, ödülünü kaçırma.',
      'Finish it before the month ends so you don\'t miss the reward.',
      'Заверши его до конца месяца, чтобы не упустить награду.',
    ],
    'home_tasksTitle': [
      'Görevler',
      'Tasks',
      'Задания',
    ],
    'home_tasksSubtitle_ready': [
      '{n} ödül almaya hazır! 🎁',
      '{n} reward ready to claim! 🎁',
      '{n} наград готовы к получению! 🎁',
    ],
    'home_tasksSubtitle_comet': [
      'Kuyruklu yıldız aktif — kaçırma!',
      'Comet event active — don\'t miss it!',
      'Событие с кометой активно — не пропусти!',
    ],
    'home_tasksSubtitle_default': [
      'Haftalık, aylık ve özel görevler',
      'Weekly, monthly and special quests',
      'Еженедельные, ежемесячные и особые задания',
    ],
    'home_weeklyTitle': [
      'Haftalık Görev',
      'Weekly Quest',
      'Еженедельное задание',
    ],
    'home_weeklySubtitle': [
      '{n} oyun bitir, {r} meteor kazan',
      'Finish {n} games, earn {r} meteors',
      'Завершите {n} игр и получите {r} метеоритов',
    ],
    'home_weeklyProgress': [
      '{done}/{total} oyun',
      '{done}/{total} games',
      '{done}/{total} игр',
    ],
    // ---- Dönüşümlü haftalık görev tipleri (bkz. WeeklyQuestType) ----
    'home_weeklySubtitle_clean': [
      '"Devam et" kullanmadan {n} oyunda Dünya\'ya ulaş, {r} meteor kazan',
      'Reach Earth in {n} games without continuing, earn {r} meteors',
      'Достигните Земли в {n} играх без продолжения и получите {r} метеоритов',
    ],
    'home_weeklySubtitle_perfect': [
      '{n} oyunda Neptün\'e ulaş, {r} meteor kazan',
      'Reach Neptune in {n} games, earn {r} meteors',
      'Достигните Нептуна в {n} играх и получите {r} метеоритов',
    ],
    'home_weeklySubtitle_playDays': [
      'Bu hafta {n} farklı gün oyna, {r} meteor kazan',
      'Play on {n} different days this week, earn {r} meteors',
      'Играйте в {n} разных дней на этой неделе и получите {r} метеоритов',
    ],
    'home_weeklySubtitle_spend': [
      'Bu hafta mağazadan {n} meteor harca, {r} meteor kazan',
      'Spend {n} meteors in the shop this week, earn {r} meteors',
      'Потратьте {n} метеоритов в магазине на этой неделе и получите {r} метеоритов',
    ],
    'home_weeklyProgress_days': [
      '{done}/{total} gün',
      '{done}/{total} days',
      '{done}/{total} дней',
    ],
    'home_weeklyProgress_meteors': [
      '{done}/{total} meteor',
      '{done}/{total} meteors',
      '{done}/{total} метеоритов',
    ],
    'home_weeklyClaim': ['Ödülü Al', 'Claim Reward', 'Забрать награду'],
    'home_weeklyClaimed': [
      'Bu hafta alındı ✓',
      'Claimed this week ✓',
      'Получено на этой неделе ✓',
    ],
    'home_monthlyTitle': [
      'Aylık Görev',
      'Monthly Quest',
      'Ежемесячное задание',
    ],
    'home_monthlySubtitle': [
      '{n} oyun bitir, {r} meteor kazan',
      'Finish {n} games, earn {r} meteors',
      'Завершите {n} игр и получите {r} метеоритов',
    ],
    'home_monthlySubtitle_clean': [
      '"Devam et" kullanmadan {n} oyunda Dünya\'ya ulaş, {r} meteor kazan',
      'Reach Earth in {n} games without continuing, earn {r} meteors',
      'Достигните Земли в {n} играх без продолжения и получите {r} метеоритов',
    ],
    'home_monthlySubtitle_perfect': [
      '{n} oyunda Neptün\'e ulaş, {r} meteor kazan',
      'Reach Neptune in {n} games, earn {r} meteors',
      'Достигните Нептуна в {n} играх и получите {r} метеоритов',
    ],
    'home_monthlySubtitle_playDays': [
      'Bu ay {n} farklı gün oyna, {r} meteor kazan',
      'Play on {n} different days this month, earn {r} meteors',
      'Играйте в {n} разных дней в этом месяце и получите {r} метеоритов',
    ],
    'home_monthlySubtitle_spend': [
      'Bu ay mağazadan {n} meteor harca, {r} meteor kazan',
      'Spend {n} meteors in the shop this month, earn {r} meteors',
      'Потратьте {n} метеоритов в магазине в этом месяце и получите {r} метеоритов',
    ],
    'home_monthlyClaimed': [
      'Bu ay alındı ✓',
      'Claimed this month ✓',
      'Получено в этом месяце ✓',
    ],
    // ---- Takımyıldız (Constellation) katmanı ----
    'constellation_title': [
      'Takımyıldız',
      'Constellation',
      'Созвездие',
    ],
    'constellation_orion': ['Orion', 'Orion', 'Орион'],
    'constellation_ursa': ['Büyük Ayı', 'Ursa Major', 'Большая Медведица'],
    'constellation_lyra': ['Lyra', 'Lyra', 'Лира'],
    'constellation_progress': [
      '{done}/{total} puan — Gezegen Birleştir\'de kazan',
      '{done}/{total} points — earn them in Planet Merge',
      '{done}/{total} очков — набирайте в «Слиянии планет»',
    ],
    'constellation_claimed': [
      'Bu hafta alındı ✓',
      'Claimed this week ✓',
      'Получено на этой неделе ✓',
    ],
    'constellation_badgeReward': [
      'Ödül: kalıcı rozet {icon}',
      'Reward: permanent badge {icon}',
      'Награда: постоянный значок {icon}',
    ],
    'constellation_rewardBadge': [
      '{name} rozetini kazandın!',
      'You earned the {name} badge!',
      'Вы получили значок «{name}»!',
    ],
    'badges_title': [
      'Rozetler',
      'Badges',
      'Значки',
    ],
    'badges_hint': [
      'Takımyıldızları haftalık olarak Gezegen Birleştir\'de tamamlayarak kazanılır.',
      'Earned by completing constellations in Planet Merge each week.',
      'Получаются за завершение созвездий в «Слиянии планет» каждую неделю.',
    ],
    'badges_locked': [
      'Kilitli',
      'Locked',
      'Заблокировано',
    ],
    // ---- Kuyruklu Yıldız (Comet Event) katmanı ----
    'comet_title': [
      'Kuyruklu Yıldız',
      'Comet Event',
      'Комета',
    ],
    'comet_subtitle': [
      'Zaman sınırlı özel tahta, {r} bonus meteor',
      'Limited-time special board, {r} bonus meteors',
      'Особая доска на ограниченное время, {r} бонусных метеоритов',
    ],
    'comet_play': ['Oyna', 'Play', 'Играть'],
    'comet_done': [
      'Bu etkinlik bitirildi ✓',
      'This event is done ✓',
      'Это событие завершено ✓',
    ],
    'comet_alreadyDone': [
      'Bu etkinliği zaten bitirdin — yeni bir tanesi yakında açılacak.',
      'You already finished this event — a new one opens soon.',
      'Вы уже завершили это событие — скоро откроется новое.',
    ],
    'comet_closesIn': [
      'Kapanmasına {time} kaldı',
      'Closes in {time}',
      'Закрывается через {time}',
    ],
    'comet_nextIn': [
      'Sıradaki etkinliğe {time}',
      'Next event in {time}',
      'Следующее событие через {time}',
    ],
    'comet_timeHm': ['{h}s {m}dk', '{h}h {m}m', '{h}ч {m}м'],
    'comet_timeM': ['{m}dk', '{m}m', '{m}м'],
    'profile_playGames': ['Play Games', 'Play Games', 'Play Games'],
    'profile_playGamesConnect': [
      '🎮 Play Games\'e Bağlan',
      '🎮 Connect to Play Games',
      '🎮 Подключиться к Play Games',
    ],
    'profile_playGamesConnected': [
      '✅ Play Games\'e bağlı',
      '✅ Connected to Play Games',
      '✅ Подключено к Play Games',
    ],
    'profile_playGamesFailed': [
      'Bağlanılamadı. Google hesabınla giriş yaptığından emin ol.',
      'Couldn\'t connect. Make sure you\'re signed in with a Google account.',
      'Не удалось подключиться. Убедитесь, что вы вошли в аккаунт Google.',
    ],
    'profile_leaderboard': [
      '🏆 Skor Tablosu (Günlük / Haftalık)',
      '🏆 Leaderboard (Daily / Weekly)',
      '🏆 Таблица лидеров (Ежедн. / Еженед.)',
    ],

    // --- Kozmik Oda / Dükkan (arkaplan temaları) ---
    'theme_default': ['Uzay (Standart)', 'Space (Default)', 'Космос (Стандарт)'],
    'theme_meteorShower': ['Meteor Yağmuru', 'Meteor Shower', 'Метеоритный дождь'],
    'theme_solarSystem': ['Güneş Sistemi', 'Solar System', 'Солнечная система'],
    'theme_spaceships': ['Uzay Gemileri', 'Spaceships', 'Космические корабли'],
    'theme_ufos': ['UFO\'lar', 'UFOs', 'НЛО'],
    'cosmicRoom_title': ['Kozmik Oda', 'Cosmic Room', 'Космическая комната'],
    'cosmicRoom_materialsHint': [
      'Sahip olduğun arkaplan temaları. Birini seç, ana ekranında etkinleşsin.',
      'Backgrounds you own. Pick one to activate it on your home screen.',
      'Ваши фоны. Выберите один, чтобы активировать его на главном экране.',
    ],
    'cosmicRoom_randomLabel': ['🎲 Her oyunda rastgele arkaplan', '🎲 Random background every game', '🎲 Случайный фон в каждой игре'],
    'cosmicRoom_randomHint': ['Tüm temalar arasından seçilir', 'Picked from all themes', 'Выбирается из всех тем'],
    'cosmicRoom_active': ['Aktif', 'Active', 'Активен'],
    'cosmicRoom_activate': ['Etkinleştir', 'Activate', 'Активировать'],
    'cosmicRoom_goToShop': ['🛍️ Dükkana Git', '🛍️ Go to Shop', '🛍️ Перейти в магазин'],
    'shop_title': ['Dükkan', 'Shop', 'Магазин'],
    'shop_subtitle': [
      'Arkaplan temalarını meteorla satın al, koleksiyonunu tamamla.',
      'Buy background themes with meteors and complete your collection.',
      'Покупайте фоны за метеоры и собирайте коллекцию.',
    ],
    'shop_owned': ['✅ Sahip Olundu', '✅ Owned', '✅ Куплено'],
    'shop_buyFor': ['{price} Satın Al', 'Buy for {price}', 'Купить за {price}'],
    'shop_notEnoughMeteors': [
      'Yeterli meteorun yok.',
      'Not enough meteors.',
      'Недостаточно метеоров.',
    ],
    'supplyShop_title': ['Malzeme Mağazası', 'Supply Shop', 'Магазин снаряжения'],
    'supplyShop_subtitle': [
      'Meteorla kurtarma hakkı al, biriktir; oyun bitince reklam izlemeden devam et.',
      'Buy rescue tokens with meteors and stock up; continue after game over without an ad.',
      'Покупайте жетоны спасения за метеориты и продолжайте после конца игры без рекламы.',
    ],
    'supplyShop_owned': ['Stokta: {n}', 'In stock: {n}', 'В наличии: {n}'],
    'supplyShop_buySuccess': [
      'Satın alındı ve stoklandı!',
      'Purchased and stocked!',
      'Куплено и добавлено на склад!',
    ],
    'weeklyReward_title': [
      'Haftalık Ödül Takvimi',
      'Weekly Reward Calendar',
      'Еженедельный календарь наград',
    ],
    'weeklyReward_mon': ['Pzt', 'Mon', 'Пн'],
    'weeklyReward_tue': ['Sal', 'Tue', 'Вт'],
    'weeklyReward_wed': ['Çar', 'Wed', 'Ср'],
    'weeklyReward_thu': ['Per', 'Thu', 'Чт'],
    'weeklyReward_fri': ['Cum', 'Fri', 'Пт'],
    'weeklyReward_sat': ['Cmt', 'Sat', 'Сб'],
    'weeklyReward_sun': ['Paz', 'Sun', 'Вс'],
    'weeklyReward_claimedTitle': [
      'Günlük Ödül Alındı!',
      'Daily Reward Claimed!',
      'Ежедневная награда получена!',
    ],
    'weeklyReward_perfectWeekBonus': [
      '🎁 Kusursuz hafta bonusu: +{n} Meteor',
      '🎁 Perfect week bonus: +{n} Meteor',
      '🎁 Бонус за идеальную неделю: +{n} Метеор',
    ],
    'shop_buyConfirmTitle': ['Satın Alınsın mı?', 'Buy this theme?', 'Купить эту тему?'],
    'shop_buyConfirmBody': [
      '{price} karşılığında bu temayı satın almak istiyor musun?',
      'Buy this theme for {price}?',
      'Купить эту тему за {price}?',
    ],
    'shop_buyConfirmYes': ['Satın Al', 'Buy', 'Купить'],
    'shop_buyConfirmCancel': ['Vazgeç', 'Cancel', 'Отмена'],
    'shop_buySuccess': [
      'Tema satın alındı! Kozmik Oda\'dan etkinleştirebilirsin.',
      'Theme purchased! You can activate it from the Cosmic Room.',
      'Тема куплена! Активируйте её в Космической комнате.',
    ],
    'shop_applyNowTitle': [
      'Şimdi Uygulansın mı?',
      'Apply Now?',
      'Применить сейчас?',
    ],
    'shop_applyNowBody': [
      'Bu temayı ana ekranına hemen uygulamak ister misin?',
      'Want to apply this theme to your home screen right now?',
      'Хотите применить эту тему на главном экране прямо сейчас?',
    ],
    'shop_applyNowYes': ['Şimdi Uygula', 'Apply Now', 'Применить сейчас'],
    'shop_applyNowLater': ['Sonra', 'Later', 'Позже'],
    'shop_applySuccess': [
      '✨ Tema uygulandı',
      '✨ Theme applied',
      '✨ Тема применена',
    ],
    'shop_tabThemes': ['Temalar', 'Themes', 'Темы'],
    'shop_tabHelpers': ['Yardımcılar', 'Helpers', 'Помощники'],
    'shop_helpersSubtitle': [
      'Meteorla önceden satın al, oyun bitince reklamsız kullan.',
      'Buy ahead with meteors, use it without an ad when a game ends.',
      'Купите заранее за метеориты и используйте без рекламы, когда игра закончится.',
    ],
    'shop_ownedCount': [
      '🎁 Bankada: {count}',
      '🎁 Banked: {count}',
      '🎁 В банке: {count}',
    ],
    'profile_close': ['Kapat', 'Close', 'Закрыть'],
    'profile_level': ['Seviye', 'Level', 'Уровень'],
    'profile_legal': [
      'Yasal Bilgiler',
      'Legal',
      'Правовая информация',
    ],
    'profile_gdprSettingLabel': [
      'Kişiselleştirilmiş Reklamlar (GDPR)',
      'Personalized Ads (GDPR)',
      'Персонализированная реклама (GDPR)',
    ],
    'profile_gdprSettingHint': [
      'AB bölgesindeki kullanıcılar için reklam rızası; istediğiniz '
          'zaman resmi onay ekranını yeniden açıp değiştirebilirsiniz.',
      'Ad consent for users in the EU region; you can reopen the '
          'official consent screen and change it anytime.',
      'Согласие на рекламу для пользователей из региона ЕС; вы можете '
          'снова открыть официальный экран согласия и изменить его в '
          'любое время.',
    ],
    'profile_gdprManageButton': [
      'Reklam Rızasını Yönet',
      'Manage Ad Consent',
      'Управление согласием на рекламу',
    ],

    // ---- Oyun ekrani / HUD ----

    // ---- Kazanma diyalogu ----
    'win_doubleXp': [
      '🎬 Reklamla 2x XP + {m} Meteor Al (+{n} XP)',
      '🎬 Watch Ad for 2x XP + {m} Meteors (+{n} XP)',
      '🎬 Смотреть рекламу за 2x XP + {m} метеорита (+{n} XP)',
    ],
    'win_doubleXpTitle': [
      'XP\'yi İkiye Katla + Meteor Kazan',
      'Double Your XP + Earn Meteors',
      'Удвоить опыт + получить метеориты',
    ],
    'win_doubleXpClaimed': [
      'XP ikiye katlandı, +{m} meteor eklendi',
      'XP doubled, +{m} meteors added',
      'Опыт удвоен, +{m} метеорита добавлено',
    ],

    // ---- Gunluk sonuc diyalogu ----
    'daily_signalNum': [
      'Günlük Sinyal #{n}',
      'Daily Signal #{n}',
      'Ежедневный сигнал #{n}',
    ],
    'daily_streak': ['Seri', 'Streak', 'Серия'],
    'daily_moves': [
      'Bırakış',
      'Drops',
      'Броски',
    ],
    'daily_time': ['Süre', 'Time', 'Время'],
    'daily_share': ['Paylaş', 'Share', 'Поделиться'],
    'daily_copied': [
      '📋 Panoya kopyalandı',
      '📋 Copied to clipboard',
      '📋 Скопировано в буфер',
    ],
    'daily_doubleXp': [
      '🎬 Reklamla 2x XP Al (+{n} XP)',
      '🎬 Watch Ad for 2x XP (+{n} XP)',
      '🎬 Смотреть рекламу за 2x XP (+{n} XP)',
    ],
    'daily_nextCountdown': [
      'Sonraki Günlük Sinyal: {h}s {m}dk',
      'Next Daily Signal: {h}h {m}m',
      'Следующий сигнал через: {h}ч {m}м',
    ],
    'daily_close': ['Kapat', 'Close', 'Закрыть'],
    'lb_title': ['Galaktik Sıralama', 'Galactic Ranking', 'Галактический рейтинг'],
    'lb_subtitle': ['En yüksek oyun skoru', 'Best single-run score', 'Лучший счёт за игру'],
    'lb_world': ['Dünya', 'World', 'Мир'],
    'lb_turkey': ['Türkiye', 'Türkiye', 'Турция'],
    'lb_daily': ['Bugün', 'Today', 'Сегодня'],
    'lb_weekly': ['Bu hafta', 'This week', 'Эта неделя'],
    'lb_allTime': ['Tüm zamanlar', 'All time', 'Всё время'],
    'lb_you': ['Sen', 'You', 'Вы'],
    'lb_noScore': [
      'Bu dönemde henüz skorun yok. Bir tur oyna!',
      'No score for this period yet. Play a round!',
      'В этом периоде у вас пока нет счёта. Сыграйте раунд!',
    ],
    'lb_empty': [
      'Henüz kimse listede yok. İlk sen ol!',
      'Nobody is on the board yet. Be the first!',
      'Пока в списке никого нет. Будьте первым!',
    ],
    'lb_retry': ['Tekrar dene', 'Try again', 'Повторить'],
    'lb_connect': ['Play Games\'e bağlan', 'Connect Play Games', 'Подключить Play Games'],
    'lb_needSignIn': [
      'Sıralamayı görmek için Google Play Games\'e bağlan.',
      'Connect to Google Play Games to see the ranking.',
      'Подключитесь к Google Play Games, чтобы увидеть рейтинг.',
    ],
    'lb_loadFail': [
      'Sıralama yüklenemedi. Bağlantını kontrol edip tekrar dene.',
      'Could not load the ranking. Check your connection and try again.',
      'Не удалось загрузить рейтинг. Проверьте соединение и повторите.',
    ],
    'lb_gap': [
      'Bir üst sıraya {n} puan',
      '{n} pts to the next rank',
      '{n} очк. до следующего места',
    ],
    'lb_leading': ['Zirvedesin! 👑', 'You are on top! 👑', 'Вы на вершине! 👑'],
    'lb_setup': [
      'Sıralama yakında açılıyor.',
      'The ranking is opening soon.',
      'Рейтинг скоро откроется.',
    ],
    'lb_sep': ['.', ',', ' '],
    'streak_rewardDaily': [
      '+{n} meteor',
      '+{n} meteors',
      '+{n} метеоров',
    ],
    'streak_rewardMilestone': [
      '🏆 {n}. gün ödülü!',
      '🏆 Day {n} reward!',
      '🏆 Награда за {n}-й день!',
    ],
    'streak_rewardWeekend': [
      '🎉 Hafta içi serisi bonusu: +{n} meteor',
      '🎉 Weekday streak bonus: +{n} meteors',
      '🎉 Бонус за будни дни: +{n} метеоров',
    ],
    'streak_diffTag': ['Sv.{n}', 'Lv.{n}', 'Ур.{n}'],
    'streak_diffLine': [
      '🔥 Seri zorluğu: Sv.{n} (daha az bırakış, daha dar kabin)',
      '🔥 Streak difficulty: Lv.{n} (fewer drops, tighter cabin)',
      '🔥 Сложность серии: ур.{n} (меньше бросков, теснее кабина)',
    ],
    'streak_diffNext': [
      '🔥 Seri zorluğu: Sv.{n} — seri uzadıkça günlük sertleşir',
      '🔥 Streak difficulty: Lv.{n} — the daily gets harder as your streak grows',
      '🔥 Сложность серии: ур.{n} — чем длиннее серия, тем сложнее день',
    ],
    'streak_nextLine': [
      '{d} gün sonra: {r}',
      'In {d} days: {r}',
      'Через {d} дн.: {r}',
    ],
    'streak_title_30': ['Yıldız Yolcusu', 'Star Traveler', 'Звёздный путник'],
    'streak_title_60': ['Galaksi Gezgini', 'Galaxy Wanderer', 'Странник галактик'],
    'streak_title_100': ['Evren Bekçisi', 'Universe Keeper', 'Хранитель вселенной'],
    'supplyShop_itemShield': ['Seri Koruyucu', 'Streak Shield', 'Щит серии'],
    'supplyShop_shieldMax': [
      'Koruyucu deposu dolu (en fazla {n}).',
      'Shield storage is full (max {n}).',
      'Хранилище щитов заполнено (макс. {n}).',
    ],
    'daily_streakLine': [
      '{n} gün seri',
      '{n} day streak',
      'серия {n} дн.',
    ],

    // ---- Reklam onay diyalogu ----
    'ad_watch': ['Reklam İzle', 'Watch Ad', 'Смотреть рекламу'],
    'ad_cancel': ['İptal', 'Cancel', 'Отмена'],
    'ad_defaultSubtitle': [
      'Ödülü almak için kısa bir reklam izle.',
      'Watch a short ad to get the reward.',
      'Посмотри короткую рекламу, чтобы получить награду.',
    ],
    'ad_loading': [
      'Reklam yükleniyor...',
      'Loading ad...',
      'Загрузка рекламы...',
    ],
    'ad_noInternet': [
      '📡 İnternet bağlantın yok. Ödül almak için reklamı gerçekten izlemen gerekiyor.',
      "📡 You're offline. You need to actually watch the ad to get the reward.",
      '📡 Нет подключения к интернету. Чтобы получить награду, нужно посмотреть рекламу.',
    ],

    // ---- Kozmik Ikmal odul popup'i ----
    'resupply_rewardTitle': [
      '🎁 Ödül Kazandın!',
      '🎁 You Got a Reward!',
      '🎁 Ты получил награду!',
    ],
    'resupply_rewardXp': ['+{n} XP', '+{n} XP', '+{n} XP'],
    'resupply_rewardMeteor': [
      '+{n} ☄️ Meteor',
      '+{n} ☄️ Meteor',
      '+{n} ☄️ Метеор',
    ],
    'resupply_bonusMeteor': [
      'Bonus: +{n} Meteor',
      'Bonus: +{n} Meteor',
      'Бонус: +{n} Метеор',
    ],
    'resupply_close': ['Harika!', 'Awesome!', 'Отлично!'],
    'resupply_waitingBody': [
      'Sonraki ikmale kalan süre:',
      'Time left until next resupply:',
      'Время до следующего пополнения:',
    ],

    // ---- Gunes Sistemi Koleksiyonu (ana ekran karti + kodeks) ----

    'planet_0_name': ['Güneş', 'Sun', 'Солнце'],
    'planet_0_fact': [
      'Sistemin kalbi; tüm enerji ondan yayılır.',
      'The heart of the system; all energy radiates from it.',
      'Сердце системы; вся энергия исходит от неё.',
    ],
    'planet_1_name': ['Dünya', 'Earth', 'Земля'],
    'planet_1_fact': [
      'Bilinen tek yaşayan gezegen.',
      'The only known living planet.',
      'Единственная известная обитаемая планета.',
    ],
    'planet_2_name': ['Gaia', 'Gaia', 'Гея'],
    'planet_2_fact': [
      'Efsanevi bir ikiz dünya, kâşiflerin hayali.',
      'A legendary twin world, every explorer\'s dream.',
      'Легендарный мир-близнец, мечта исследователей.',
    ],
    'planet_3_name': ['Satürn', 'Saturn', 'Сатурн'],
    'planet_3_fact': [
      'Muhteşem halkalarıyla tanınan dev gezegen.',
      'A giant known for its magnificent rings.',
      'Гигант, известный своими великолепными кольцами.',
    ],
    'planet_4_name': ['Viyole', 'Violet', 'Виолет'],
    'planet_4_fact': [
      'Mor atmosferiyle bilinen gizemli bir dünya.',
      'A mysterious world known for its violet atmosphere.',
      'Загадочный мир с фиолетовой атмосферой.',
    ],
    'planet_5_name': ['Mars', 'Mars', 'Марс'],
    'planet_5_fact': [
      'Kızıl gezegen, insanlığın bir sonraki durağı.',
      'The red planet, humanity\'s next stop.',
      'Красная планета, следующая остановка человечества.',
    ],
    'planet_6_name': ['Uranüs', 'Uranus', 'Уран'],
    'planet_6_fact': [
      'Yan yatmış ekseniyle bilinen bir buz devi.',
      'An ice giant known for its tilted axis.',
      'Ледяной гигант с наклонённой осью.',
    ],
    'planet_7_name': ['Pembe Nebula', 'Pink Nebula', 'Розовая туманность'],
    'planet_7_fact': [
      'Doğan yıldızların beşiği.',
      'A cradle of newborn stars.',
      'Колыбель новорождённых звёзд.',
    ],
    'planet_8_name': ['Merkür', 'Mercury', 'Меркурий'],
    'planet_8_fact': [
      'Güneşe en yakın ve en hızlı yörüngeli gezegen.',
      'The closest planet to the sun, with the fastest orbit.',
      'Ближайшая к Солнцу планета с самой быстрой орбитой.',
    ],
    'planet_9_name': ['Neptün', 'Neptune', 'Нептун'],
    'planet_9_fact': [
      'Sistemin en rüzgarlı ve en uzak devi.',
      'The system\'s windiest and most distant giant.',
      'Самый ветреный и далёкий гигант системы.',
    ],

    // ---- Ana ekran: Mağaza ve Kozmik Oda kartları ----
    'home_shopCardTitle': ['Mağaza', 'Shop', 'Магазин'],
    'home_cosmicRoomCardSubtitle': [
      'Temanı özelleştir',
      'Customize your theme',
      'Настрой свою тему',
    ],

    // ---- Yasal sayfa (in-app WebView) hata durumu ----
    'legal_loadFailed': [
      'Sayfa yüklenemedi. İnternet bağlantını kontrol '
          'edip tekrar dene.',
      'The page couldn\'t load. Check your internet '
          'connection and try again.',
      'Не удалось загрузить страницу. Проверьте подключение '
          'к интернету и попробуйте снова.',
    ],
    'legal_retry': ['Tekrar Dene', 'Try Again', 'Повторить'],


    // ---- Günlük sonuç paylasim karti ----
    'daily_shareChallenge': [
      'Beni yenebilir misin? 👀',
      'Can you beat me? 👀',
      'Сможешь меня обыграть? 👀',
    ],
    'daily_shareCardTitle': [
      'Gezegen Birleştir · Günlük #{n}',
      'Planet Merge · Daily #{n}',
      'Слияние планет · Ежедневный #{n}',
    ],
    'daily_shareMoves': [
      'bırakış',
      'drops',
      'бросков',
    ],
    'daily_shareTime': ['süre', 'time', 'время'],
    'daily_shareStreak': ['seri', 'streak', 'серия'],

    // ---- Gezegen Birlestir (Suika tarzi prototip mod) ----
    'home_mergeTitle': ['Gezegen Birleştir', 'Planet Merge', 'Слияние планет'],
    'pm_score': ['Puan', 'Score', 'Очки'],
    'pm_best': ['En iyi', 'Best', 'Рекорд'],
    // ---- Odul kutlama ekrani ----
    'rc_level': ['Seviye {n}', 'Level {n}', 'Уровень {n}'],
    'rc_levelUp': ['Seviye atladın!', 'Level up!', 'Новый уровень!'],
    'rc_score': ['PUAN', 'SCORE', 'ОЧКИ'],
    'rc_progress': ['Seviye ilerlemesi', 'Level progress', 'Прогресс уровня'],
    'rc_congrats': ['Tebrikler!', 'Congratulations!', 'Поздравляем!'],
    'pm_next': ['Sıradaki', 'Next', 'Далее'],
    'pm_hint': [
      'Kaydır ve bırak — aynı gezegenler birleşir!',
      'Slide and release — matching planets merge!',
      'Двигай и отпускай — одинаковые планеты сливаются!',
    ],
    'pm_newPlanet': [
      'Yeni gezegen: {name}!',
      'New planet: {name}!',
      'Новая планета: {name}!',
    ],
    'pm_gameOverTitle': ['Kabin doldu!', 'Container full!', 'Контейнер полон!'],
    'pm_continueTitle': [
      'Kabini hafiflet',
      'Clear some space',
      'Освободить место',
    ],
    'pm_continueSubtitle': [
      'En üstteki 6 gezegen kaldırılır ve oyun devam eder.',
      'The top 6 planets are removed and the game continues.',
      'Шесть верхних планет исчезнут, и игра продолжится.',
    ],
    'pass_title': ['GALAKSİ YOLU', 'GALAXY PASS', 'ГАЛАКТИЧЕСКИЙ ПУТЬ'],
    'pass_endsIn': ['Sezon bitimine: {t}', 'Season ends in: {t}', 'До конца сезона: {t}'],
    'pass_tabTasks': ['GÖREVLER', 'MISSIONS', 'ЗАДАНИЯ'],
    'pass_tabRewards': ['ÖDÜLLER', 'REWARDS', 'НАГРАДЫ'],
    'pass_dailyTitle': ['GÜNLÜK GÖREVLER', 'DAILY MISSIONS', 'ЕЖЕДНЕВНЫЕ ЗАДАНИЯ'],
    'pass_refreshIn': ['Yenilenmesine: {t}', 'Refreshes in: {t}', 'Обновление: {t}'],
    'pass_specialTitle': ['ÖZEL GÖREVLER', 'SPECIAL MISSIONS', 'ОСОБЫЕ ЗАДАНИЯ'],
    'pass_claim': ['AL', 'CLAIM', 'ЗАБРАТЬ'],
    'pass_claimed': ['ALINDI', 'CLAIMED', 'ПОЛУЧЕНО'],
    'pass_claimAll': ['HEPSİNİ AL', 'CLAIM ALL', 'ЗАБРАТЬ ВСЁ'],
    'pass_bonusTitle': ['Bugünkü 3 görevi de al', 'Claim all 3 missions today', 'Заберите все 3 задания сегодня'],
    'pass_level': ['Seviye {n}', 'Level {n}', 'Уровень {n}'],
    'pass_needPoints': ['{n} puan gerek', '{n} pts needed', 'Нужно {n} очк.'],
    'pass_pointsLabel': ['Yıldız puanı', 'Star points', 'Звёздные очки'],
    'pass_helpTitle': ['Galaksi Yolu nasıl işler?', 'How does the Galaxy Pass work?', 'Как работает Галактический путь?'],
    'pass_helpBody': [
      'Günlük görevleri tamamla, Yıldız puanı kazan. Puanlar yolun seviyelerini açar ve her seviyede bir ödül seni bekler. Haftalık ve aylık görevler de puan verir. Sezon her ay başı sıfırlanır.',
      'Complete daily missions to earn Star points. Points unlock the pass levels and every level has a reward waiting. Weekly and monthly missions give points too. The season resets each month.',
      'Выполняйте ежедневные задания и получайте звёздные очки. Очки открывают уровни, на каждом ждёт награда. Недельные и месячные задания тоже дают очки. Сезон обновляется каждый месяц.',
    ],
    'pass_unitD': ['g', 'd', 'д'],
    'pass_unitH': ['s', 'h', 'ч'],
    'pass_unitM': ['d', 'm', 'м'],
    'reward_ok': ['HARİKA', 'AWESOME', 'ОТЛИЧНО'],
    'reward_titleMission': ['Görev tamamlandı!', 'Mission complete!', 'Задание выполнено!'],
    'reward_titleLevel': ['Seviye {n} ödülü!', 'Level {n} reward!', 'Награда уровня {n}!'],
    'reward_titleQuest': ['Ödül kazandın!', 'You earned a reward!', 'Вы получили награду!'],
    'reward_meteor': ['Meteor', 'Meteors', 'Метеоры'],
    'mission_merge': ['{n} birleştirme yap', 'Make {n} merges', 'Сделайте слияний: {n}'],
    'mission_drop': ['{n} gezegen at', 'Drop {n} planets', 'Бросьте планет: {n}'],
    'mission_run': ['{n} oyun bitir', 'Finish {n} games', 'Завершите игр: {n}'],
    'mission_tier': ['Gezegene ulaş: {n}', 'Reach planet: {n}', 'Достигните: {n}'],
    'mission_combo': ['x{n} kombo yap', 'Hit a x{n} combo', 'Комбо x{n}'],
    'mission_score': ['Tek oyunda {n} puan yap', 'Score {n} in one game', 'Наберите {n} за игру'],
    'mission_power': ['{n} güçlendirici kullan', 'Use {n} power-ups', 'Усилителей: {n}'],
    'pm_newRecord': ['YENİ REKOR!', 'NEW RECORD!', 'НОВЫЙ РЕКОРД!'],
    'pm_newWeekRecord': ['Haftanın rekoru!', 'Best of the week!', 'Рекорд недели!'],
    'pm_newTodayRecord': ['Günün rekoru!', 'Best of today!', 'Рекорд дня!'],
    'pm_recToday': ['Günün rekoru', "Today's best", 'Рекорд дня'],
    'pm_recWeek': ['Haftanın rekoru', "Week's best", 'Рекорд недели'],
    'pm_recAll': ['Rekor', 'Record', 'Рекорд'],
    'pm_closeTo': ['{what}: {n} puan kaldı!', '{what}: {n} to go!', '{what}: осталось {n}!'],
    'pm_newRecordDelta': ['🏆 Yeni rekor! +{n} puan', '🏆 New record! +{n}', '🏆 Новый рекорд! +{n}'],
    'pm_nearMiss': ['🔥 Rekora {n} puan kaldı!', '🔥 Just {n} short of your record!', '🔥 До рекорда {n} очк.!'],
    'rule_lowGravity': ['Ay Haftası', 'Moon Week', 'Лунная неделя'],
    'rule_lowGravity_desc': ['Düşük yerçekimi: gezegenler yavaş düşer', 'Low gravity: planets fall slowly', 'Низкая гравитация: планеты падают медленно'],
    'rule_narrow': ['Dar Kabin Haftası', 'Tight Week', 'Неделя тесноты'],
    'rule_narrow_desc': ['Kabin daralır: tehlike çizgisi aşağıda', 'Less room: the danger line is lower', 'Меньше места: линия опасности ниже'],
    'rule_giants': ['Devler Haftası', 'Giants Week', 'Неделя гигантов'],
    'rule_giants_desc': ['Büyük gezegenler baştan yağar', 'Big planets rain from the start', 'Крупные планеты с самого начала'],
    'rule_bouncy': ['Zıplayan Hafta', 'Bouncy Week', 'Неделя прыжков'],
    'rule_bouncy_desc': ['Gezegenler zıplar, yığın sallanır', 'Planets bounce around', 'Планеты отскакивают'],
    'rule_combo': ['Kombo Haftası', 'Combo Week', 'Неделя комбо'],
    'rule_combo_desc': ['Kombo bonusu 2 kat, süre daha uzun', 'Double combo bonus, longer window', 'Двойной бонус комбо, больше времени'],
    'rule_relax': ['Rahat Hafta', 'Chill Week', 'Спокойная неделя'],
    'rule_relax_desc': ['Daha çok küçük gezegen gelir', 'More small planets', 'Больше маленьких планет'],
    'home_cometDock': ['Kuyruklu', 'Comet', 'Комета'],
    'pm_fact_0': ['Güneş\'e en yakın gezegen; bir yılı yalnızca 88 gün sürer.', 'The closest planet to the Sun; its year lasts only 88 days.', 'Ближайшая к Солнцу планета; год длится всего 88 дней.'],
    'pm_fact_1': ['Kızıl cüceler küçük ve soğuk yıldızlardır; evrendeki yıldızların çoğunu oluştururlar.', 'Red dwarfs are small, cool stars and the most common kind in the universe.', 'Красные карлики — маленькие холодные звёзды, самые распространённые во Вселенной.'],
    'pm_fact_2': ['Asteroitler, Güneş Sistemi\'nin 4,5 milyar yıllık yapı taşı artıklarıdır.', 'Asteroids are leftover building blocks of the Solar System, 4.5 billion years old.', 'Астероиды — остатки строительного материала Солнечной системы возрастом 4,5 млрд лет.'],
    'pm_fact_3': ['Satürn\'ün ayı Enceladus\'un buzlu kabuğunun altında bir okyanus saklıdır.', 'Saturn\'s moon Enceladus hides an ocean beneath its icy crust.', 'Под ледяной корой спутника Сатурна Энцелада скрыт океан.'],
    'pm_fact_4': ['Mars\'ta Güneş Sistemi\'nin en yüksek yanardağı Olympus Mons bulunur.', 'Mars is home to Olympus Mons, the tallest volcano in the Solar System.', 'На Марсе находится Олимп — самый высокий вулкан Солнечной системы.'],
    'pm_fact_5': ['Dünya yüzeyinin yaklaşık %71\'i suyla kaplıdır.', 'About 71% of Earth\'s surface is covered by water.', 'Около 71% поверхности Земли покрыто водой.'],
    'pm_fact_6': ['Gaia hipotezi, Dünya\'yı yaşamla birlikte kendini düzenleyen tek bir sistem olarak görür.', 'The Gaia hypothesis sees Earth and life as one self-regulating system.', 'Гипотеза Гайи рассматривает Землю и жизнь как единую саморегулирующуюся систему.'],
    'pm_fact_7': ['Neptün\'de rüzgârlar saatte 2000 km\'yi aşar; Güneş Sistemi\'nin en hızlısıdır.', 'Neptune\'s winds top 2,000 km/h, the fastest in the Solar System.', 'Ветры на Нептуне превышают 2000 км/ч — самые быстрые в Солнечной системе.'],
    'pm_fact_8': ['Uranüs neredeyse yan yatmış bir şekilde döner.', 'Uranus spins almost on its side.', 'Уран вращается почти лёжа на боку.'],
    'pm_fact_9': ['Satürn\'ün halkaları çoğunlukla buz parçalarından oluşur.', 'Saturn\'s rings are made mostly of chunks of ice.', 'Кольца Сатурна состоят в основном из кусков льда.'],
    'pm_fact_10': ['Gaz devlerinin katı bir yüzeyi yoktur; derinlere indikçe gaz yoğunlaşır.', 'Gas giants have no solid surface; the gas just gets denser with depth.', 'У газовых гигантов нет твёрдой поверхности: с глубиной газ становится плотнее.'],
    'pm_fact_11': ['Güneş, Güneş Sistemi\'nin kütlesinin yaklaşık %99,86\'sını oluşturur.', 'The Sun holds about 99.86% of the Solar System\'s mass.', 'На Солнце приходится около 99,86% массы Солнечной системы.'],
    'pm_fact_12': [
      'Evrenin kütle-enerjisinin yaklaşık %27\'si ışık yaymayan karanlık maddedir.',
      'About 27% of the universe\'s mass-energy is dark matter, which gives off no light.',
      'Около 27% массы-энергии Вселенной — тёмная материя, которая не излучает свет.',
    ],
    'rank_0': ['Kadet', 'Cadet', 'Курсант'],
    'rank_1': ['Asteğmen', 'Ensign', 'Энсин'],
    'rank_2': ['Teğmen', 'Lieutenant', 'Лейтенант'],
    'rank_3': ['Üsteğmen', 'First Lieutenant', 'Старший лейтенант'],
    'rank_4': ['Pilot', 'Pilot', 'Пилот'],
    'rank_5': ['Kaptan', 'Captain', 'Капитан'],
    'rank_6': ['Binbaşı', 'Major', 'Майор'],
    'rank_7': ['Yarbay', 'Lieutenant Colonel', 'Подполковник'],
    'rank_8': ['Albay', 'Colonel', 'Полковник'],
    'rank_9': ['Komutan', 'Commander', 'Командор'],
    'rank_10': ['Tuğamiral', 'Rear Admiral', 'Контр-адмирал'],
    'rank_11': ['Koramiral', 'Vice Admiral', 'Вице-адмирал'],
    'rank_12': ['Amiral', 'Admiral', 'Адмирал'],
    'rank_13': ['Büyük Amiral', 'Grand Admiral', 'Гранд-адмирал'],
    'rank_14': ['Galaksi Efendisi', 'Galaxy Master', 'Повелитель галактики'],
    'ach_runs1': ['İlk Uçuş', 'First Flight', 'Первый полёт'],
    'ach_runs25': ['Düzenli Pilot', 'Regular Pilot', 'Постоянный пилот'],
    'ach_runs100': ['Yıldız Gezgini', 'Star Traveler', 'Звёздный странник'],
    'ach_merge500': ['Birleştirici', 'Merger', 'Объединитель'],
    'ach_merge5000': ['Evren Mimarı', 'Universe Architect', 'Архитектор Вселенной'],
    'ach_score1000': ['Bin Puan', 'Thousand Club', 'Тысячник'],
    'ach_score3000': ['Yıldız Avcısı', 'Star Hunter', 'Охотник за звёздами'],
    'ach_score8000': ['Galaksi Rekortmeni', 'Galaxy Record Holder', 'Рекордсмен галактики'],
    'ach_combo5': ['Zincir Ustası', 'Chain Master', 'Мастер цепей'],
    'ach_combo8': ['Kombo Efsanesi', 'Combo Legend', 'Легенда комбо'],
    'ach_planets12': ['Gezegen Kaşifi', 'Planet Explorer', 'Исследователь планет'],
    'ach_planets13': ['Karanlığın Efendisi', 'Master of the Dark', 'Повелитель тьмы'],
    'skin_title': ['Gizli Gezegenler', 'Secret Planets', 'Секретные планеты'],
    'skin_subtitle': [
      'Zor hedeflerle açılır. Açtığın gezegen oyunda ilgili kademenin görünümünü değiştirir.',
      'Unlocked by hard goals. An unlocked planet changes how its tier looks in the game.',
      'Открываются за сложные цели. Открытая планета меняет вид своего уровня в игре.',
    ],
    'skin_violet': ['Mor Halka', 'Violet Ring', 'Фиолетовое кольцо'],
    'skin_indigo': ['İndigo Dünya', 'Indigo Earth', 'Индиго-Земля'],
    'skin_toksik': ['Toksik Gaia', 'Toxic Gaia', 'Токсичная Гея'],
    'skin_replaces': ['{name} yerine geçer', 'Replaces {name}', 'Заменяет: {name}'],
    'skin_req_planets': [
      'Koleksiyonu tamamla: {n} gezegen keşfet',
      'Complete the collection: discover {n} planets',
      'Соберите коллекцию: откройте {n} планет',
    ],
    'skin_req_streak': ['{n} günlük seri yap', 'Reach a {n}-day streak', 'Серия {n} дн.'],
    'skin_req_bestScore': [
      'Tek oyunda {n} puana ulaş',
      'Reach {n} points in one game',
      'Наберите {n} очков за игру',
    ],
    'skin_use': ['Kullan', 'Use', 'Использовать'],
    'skin_remove': ['Varsayılana dön', 'Use default', 'По умолчанию'],
    'ach_streak7': ['Haftalık Seri', 'Week Streak', 'Недельная серия'],
    'ach_streak30': ['Demir Seri', 'Iron Streak', 'Железная серия'],
    'ach_power20': ['Güç Ustası', 'Power Master', 'Мастер усилений'],
    'ach_d_runs': ['{n} oyun bitir', 'Finish {n} games', 'Завершите игр: {n}'],
    'ach_d_merges': ['Toplam {n} birleştirme yap', 'Make {n} merges in total', 'Сделайте слияний: {n}'],
    'ach_d_bestScore': ['Tek oyunda {n} puana ulaş', 'Reach {n} points in one game', 'Наберите {n} за игру'],
    'ach_d_bestCombo': ['x{n} kombo yap', 'Hit a x{n} combo', 'Комбо x{n}'],
    'ach_d_planets': ['{n} gezegen keşfet', 'Discover {n} planets', 'Откройте планет: {n}'],
    'ach_d_streak': ['{n} günlük seri yap', 'Reach a {n}-day streak', 'Серия {n} дн.'],
    'ach_d_powerUses': ['{n} güçlendirici kullan', 'Use {n} power-ups', 'Усилителей: {n}'],
    'col_title': ['KOLEKSİYON', 'COLLECTION', 'КОЛЛЕКЦИЯ'],
    'col_tabPlanets': ['GEZEGENLER', 'PLANETS', 'ПЛАНЕТЫ'],
    'col_tabAch': ['BAŞARIMLAR', 'ACHIEVEMENTS', 'ДОСТИЖЕНИЯ'],
    'col_nextRank': ['Sonraki rütbe: {rank} (Seviye {n})', 'Next rank: {rank} (Level {n})', 'Следующее звание: {rank} (ур. {n})'],
    'col_maxRank': ['En yüksek rütbedesin!', 'You are at the top rank!', 'Вы на высшем звании!'],
    'col_locked': ['Bu gezegeni birleştirerek keşfet', 'Discover it by merging planets', 'Откройте, объединяя планеты'],
    'col_progress': ['Keşfedilen: {a}/{b}', 'Discovered: {a}/{b}', 'Открыто: {a}/{b}'],
    'col_milestone': ['{n} gezegen', '{n} planets', '{n} планет'],
    'col_rankClaim': ['Rütbe ödülünü al', 'Claim rank reward', 'Забрать награду за звание'],
    'retention_welcomeBack': ['Tekrar hoş geldin!', 'Welcome back!', 'С возвращением!'],
    'retention_rankUp': ['Yeni rütbe: {rank}!', 'New rank: {rank}!', 'Новое звание: {rank}!'],
    'retention_rescueTitle': ['Serin kopmak üzere!', 'Your streak is about to end!', 'Серия вот-вот прервётся!'],
    'retention_rescueBody': ['🔥 {n} günlük serini kurtarabilirsin. Bugünkü günlük sinyali tamamlayınca seri devam eder.', '🔥 You can save your {n}-day streak. Finish today\'s daily signal and it continues.', '🔥 Можно спасти серию из {n} дн. Пройдите сегодняшний сигнал, и она продолжится.'],
    'retention_rescueAd': ['🎬 Reklam izle, seriyi kurtar', '🎬 Watch ad, save streak', '🎬 Реклама — спасти серию'],
    'retention_rescueMeteor': ['☄️ {n} ile kurtar', 'Save for ☄️ {n}', 'Спасти за ☄️ {n}'],
    'retention_rescueDecline': ['Vazgeç', 'No thanks', 'Отказаться'],
    'retention_rescued': ['Serin kurtarıldı! Günlük sinyali tamamla.', 'Streak saved! Finish the daily signal.', 'Серия спасена! Пройдите сигнал дня.'],
    'retention_shieldUsed': ['🛡️ Seri koruyucu seni kurtardı!', '🛡️ Streak shield saved you!', '🛡️ Щит спас вашу серию!'],
    'notif_weeklyRuleTitle': ['Yeni haftalık kural!', 'New weekly rule!', 'Новое правило недели!'],
    'notif_weeklyRuleBody': ['Bu hafta oyun farklı hissettirecek. Rekorunu tazelemeye ne dersin?', 'This week plays differently. Ready to beat your record?', 'Эта неделя играет иначе. Побьёте рекорд?'],
    'profile_hapticsLabel': ['Titreşim', 'Vibration', 'Вибрация'],
    'pm_combo': ['KOMBO x{n}', 'COMBO x{n}', 'КОМБО x{n}'],
    'pm_doubleTitle': ['XP ödülünü ikiye katla', 'Double your XP reward', 'Удвоить награду XP'],
    'pm_doubleButton': ['🎬 XP x2 (+{m} ☄️)', '🎬 XP x2 (+{m} ☄️)', '🎬 XP x2 (+{m} ☄️)'],
    'power_bomb': ['Sil', 'Remove', 'Убрать'],
    'power_swap': ['Değiştir', 'Swap', 'Сменить'],
    'power_shake': ['Salla', 'Shake', 'Встряхнуть'],
    'power_bombHint': ['Silmek istediğin gezegene dokun', 'Tap a planet to remove it', 'Коснитесь планеты, чтобы убрать её'],
    'power_cancel': ['İptal', 'Cancel', 'Отмена'],
    'power_buyTitle': ['{name} hakkın bitti', 'Out of {name}', 'Закончилось: {name}'],
    'power_buyMeteor': ['☄️ {n} ile satın al', 'Buy for ☄️ {n}', 'Купить за ☄️ {n}'],
    'power_buyAd': ['🎬 Reklam izle, +1 kazan', '🎬 Watch ad, get +1', '🎬 Смотреть рекламу, +1'],
    'power_noMeteor': ['Yeterli meteor yok', 'Not enough meteors', 'Недостаточно метеоров'],
    'pm_continueButton': ['Reklam izle, devam et', 'Watch ad, continue', 'Смотреть рекламу и продолжить'],
    'pm_retry': ['Tekrar oyna', 'Play again', 'Играть снова'],
    'pm_exit': ['Ana menü', 'Main menu', 'Главное меню'],
    // ---- Bolum Modu (bkz. lib/game/level_mode.dart) ----
    'home_levelsDock': ['Bölümler', 'Levels', 'Уровни'],
    'lv_select_title': ['Bölümler', 'Levels', 'Уровни'],
    'lv_title': ['Bölüm {n}', 'Level {n}', 'Уровень {n}'],
    'lv_winTitle': ['Bölüm {n} tamam!', 'Level {n} cleared!', 'Уровень {n} пройден!'],
    'lv_rewardLine': ['+{m} ☄️  +{x} XP', '+{m} ☄️  +{x} XP', '+{m} ☄️  +{x} XP'],
    'lv_next': ['Sonraki bölüm', 'Next level', 'Следующий уровень'],
    'lv_menu': ['Bölümler', 'Levels', 'Уровни'],
    'lv_crack': ['Çatladı!', 'Cracked!', 'Трещина!'],
    'lv_thaw': ['Buz kırıldı!', 'Ice broken!', 'Лёд разбит!'],
    'lv_unlock': ['Kilit açıldı!', 'Unlocked!', 'Открыто!'],
    'lv_rule_plain': [
      'Sınırlı bırakışta hedef gezegene ulaş.',
      'Reach the target planet within your drops.',
      'Достигните цели за ограниченное число бросков.',
    ],
    'lv_rule_ice': [
      '🧊 Buzlu gezegenler birleşemez. Yakınında bir birleşme olunca çatlar, ikincisinde kırılır.',
      '🧊 Frozen planets cannot merge. A nearby merge cracks the ice, a second one breaks it.',
      '🧊 Замёрзшие планеты не сливаются. Слияние рядом трескает лёд, второе разбивает его.',
    ],
    'lv_rule_lock': [
      '🔒 Kilitli gezegenler yerinde sabit durur. Sayaçtaki kadar birleşme yapınca kilit açılır.',
      '🔒 Locked planets stay fixed in place. Make as many merges as the counter shows to unlock them.',
      '🔒 Заблокированные планеты неподвижны. Сделайте столько слияний, сколько на счётчике, чтобы открыть.',
    ],
    'lv_rule_both': [
      '🧊 Buzlu gezegenler yakındaki birleşmelerle çatlar ve kırılır. 🔒 Kilitli gezegenler sayaç bitince serbest kalır.',
      '🧊 Nearby merges crack and break frozen planets. 🔒 Locked planets are freed when their counter runs out.',
      '🧊 Слияния рядом трескают и разбивают замёрзшие планеты. 🔒 Заблокированные освобождаются, когда счётчик обнулится.',
    ],
    // ---- Gezegen guclari (bkz. lib/game/cosmic_powers.dart) ----
    'pw_new': ['Yeni güç: {name}', 'New power: {name}', 'Новая сила: {name}'],
    'pw_title': ['Gezegen gücü', 'Planet power', 'Сила планеты'],
    'pw_ring_name': ['Halka Dalgası', 'Ring Pulse', 'Кольцевая волна'],
    'pw_ring_desc': [
      'Satürn oluşunca halkaları çevredeki gezegenleri iter ve sıkışan yığını gevşetir.',
      'When Saturn forms, its rings push nearby planets away and loosen a jammed stack.',
      'Когда появляется Сатурн, его кольца отталкивают соседние планеты и разрыхляют завал.',
    ],
    'pw_flare_name': ['Güneş Patlaması', 'Solar Flare', 'Солнечная вспышка'],
    'pw_flare_desc': [
      'Güneş oluşunca çevreyi ısıtır; yakındaki küçük gezegenleri yakıp bonus puan verir.',
      'When the Sun forms, it scorches small planets nearby for bonus points.',
      'Когда рождается Солнце, оно сжигает мелкие планеты рядом и даёт бонусные очки.',
    ],
    'pw_sing_name': [
      'Kara Delik Çekimi',
      'Black Hole Pull',
      'Притяжение чёрной дыры',
    ],
    'pw_sing_desc': [
      'Karanlık Kütle oluşunca birkaç saniye komşu gezegenleri kendine çeker; aynı gezegenler yan yana gelip birleşir.',
      'When the Dark Mass forms, it pulls neighbors in for a few seconds so matching planets cluster and merge.',
      'Когда появляется Тёмная масса, она на несколько секунд притягивает соседей, и одинаковые планеты сближаются и сливаются.',
    ],
    'pm_planet_0': ['Merkür', 'Mercury', 'Меркурий'],
    'pm_planet_1': ['Kızıl Cüce', 'Red Dwarf', 'Красный карлик'],
    'pm_planet_2': ['Bakır Asteroit', 'Copper Asteroid', 'Медный астероид'],
    'pm_planet_3': ['Buz Ay', 'Ice Moon', 'Ледяная луна'],
    'pm_planet_4': ['Mars', 'Mars', 'Марс'],
    'pm_planet_5': ['Dünya', 'Earth', 'Земля'],
    'pm_planet_6': ['Gaia', 'Gaia', 'Гайя'],
    'pm_planet_7': ['Neptün', 'Neptune', 'Нептун'],
    'pm_planet_8': ['Uranüs', 'Uranus', 'Уран'],
    'pm_planet_9': ['Satürn', 'Saturn', 'Сатурн'],
    'pm_planet_10': ['Gaz Devi', 'Gas Giant', 'Газовый гигант'],
    'pm_planet_11': ['Güneş', 'Sun', 'Солнце'],
    'pm_planet_12': ['Karanlık Kütle', 'Dark Mass', 'Тёмная масса'],
    'home_play': [
      'OYNA',
      'PLAY',
      'ИГРАТЬ',
    ],
    'supplyShop_itemRescue': [
      'Kurtarma Hakkı',
      'Rescue Token',
      'Жетон спасения',
    ],
    'daily_shareScore': [
      'skor',
      'score',
      'счёт',
    ],
    'pm_continueUseRescue': [
      'Kurtarma hakkı kullan ({n})',
      'Use rescue token ({n})',
      'Использовать жетон ({n})',
    ],
    'pm_gotIt': [
      'Anladım',
      'Got it',
      'Понятно',
    ],
    'pm_tutorialTitle': [
      'Nasıl Oynanır?',
      'How to Play',
      'Как играть',
    ],
    'pm_tutorialRule1': [
      'Parmağınla kaydır, bırakınca gezegen düşer.',
      'Slide your finger, release to drop the planet.',
      'Двигайте пальцем и отпустите, чтобы бросить планету.',
    ],
    'pm_tutorialRule2': [
      'Aynı iki gezegen çarpışınca bir üst gezegene dönüşür. Güneş\'e ulaşmaya çalış!',
      'Two identical planets that touch merge into the next one. Aim for the Sun!',
      'Две одинаковые планеты при касании сливаются в следующую. Цель — Солнце!',
    ],
    'pm_tutorialRule3': [
      'Gezegenler kesikli çizgiyi aşıp bir süre kalırsa oyun biter.',
      'If planets stay above the dashed line for a while, the game ends.',
      'Если планеты задержатся выше пунктирной линии, игра закончится.',
    ],
    'tut_skip': [
      'Öğreticiyi atla',
      'Skip tutorial',
      'Пропустить обучение',
    ],
    'tut_continue': [
      'Devam',
      'Next',
      'Далее',
    ],
    'tut_welcome': [
      'Hoş geldin, Komutan! Ben Felyx. Galaksiyi birlikte keşfedeceğiz; sana her şeyi adım adım göstereceğim.',
      'Welcome, Commander! I\'m Felyx. We\'ll explore the galaxy together, and I\'ll show you everything step by step.',
      'Добро пожаловать, командир! Я Феликс. Мы вместе исследуем галактику, и я покажу тебе всё шаг за шагом.',
    ],
    'tut_meteor': [
      'Bunlar meteorların. Oyunun para birimi: güçlendirici, mağaza ve özel ürünler için kullanırsın.',
      'These are your meteors, the game\'s currency. Use them for power-ups, the shop and special items.',
      'Это твои метеоры — валюта игры. Они нужны для усилений, магазина и особых предметов.',
    ],
    'tut_play': [
      'Önce küçük bir deneme turu atalım! OYNA\'ya dokun.',
      'Let\'s start with a quick practice round! Tap PLAY.',
      'Начнём с небольшой тренировки! Нажми ИГРАТЬ.',
    ],
    'tut_g_drop': [
      'Parmağını kaydırarak gezegeni istediğin yere getir, sonra bırak. Hadi ilk gezegeni bırak!',
      'Slide your finger to aim the planet, then release to drop it. Go on, drop the first one!',
      'Води пальцем, чтобы выбрать место, и отпусти, чтобы бросить планету. Брось первую!',
    ],
    'tut_g_next': [
      'Sıradaki gezegen burada görünür. Hamleni ona göre planla.',
      'The next planet shows up here. Plan your move around it.',
      'Следующая планета показана здесь. Планируй ход с учётом неё.',
    ],
    'tut_g_drop2': [
      'İyi! Şimdi AYNI iki gezegeni yan yana getir; çarpışınca birleşip büyürler. Bir tane daha bırak.',
      'Nice! Now put TWO IDENTICAL planets side by side; when they touch they merge and grow. Drop another one.',
      'Отлично! Теперь поставь ДВЕ ОДИНАКОВЫЕ планеты рядом: при касании они сольются и вырастут. Брось ещё одну.',
    ],
    'tut_g_merge': [
      'Süper! İki gezegen birleşip bir üst gezegene dönüştü. Her birleşme puan kazandırır.',
      'Awesome! Two planets merged into the next one up. Every merge earns points.',
      'Супер! Две планеты слились в следующую. За каждое слияние начисляются очки.',
    ],
    'tut_g_score': [
      'Burada skorun ve rekorun görünür. Rekoruna yaklaşınca sana haber veririm!',
      'Your score and record show up here. I\'ll let you know when you\'re close to a record!',
      'Здесь видны твой счёт и рекорд. Я скажу, когда ты будешь близко к рекорду!',
    ],
    'tut_g_danger': [
      'Dikkat! Gezegenler bu kesikli çizginin üstünde kısa süre bile kalırsa oyun biter. Tahtayı taşırma.',
      'Careful! If planets stay above this dashed line for even a short time, the game ends. Don\'t overfill the board.',
      'Осторожно! Если планеты задержатся выше этой пунктирной линии, игра закончится. Не переполняй поле.',
    ],
    'tut_g_power': [
      'Sıkışırsan güçlendirici kullan: 💥 Sil bir gezegeni yok eder, 🔄 Değiştir sıradakiyle yer değiştirir, 🌀 Salla her şeyi sarsar. Hepsinden 1 hediye!',
      'Stuck? Use a power-up: 💥 Delete removes a planet, 🔄 Swap trades with the next one, 🌀 Shake jostles everything. You get 1 of each as a gift!',
      'Застрял? Используй усиление: 💥 Удалить убирает планету, 🔄 Обмен меняет местами со следующей, 🌀 Встряска перемешивает всё. По одному — в подарок!',
    ],
    'tut_g_chain': [
      'Evrim zinciri: gezegenlerin sırası burada. Soluk olanlara bu oyunda henüz ulaşmadın.',
      'Evolution chain: the order of planets is here. Faded ones haven\'t been reached yet this game.',
      'Цепочка эволюции: порядок планет. Бледные в этой игре ещё не достигнуты.',
    ],
    'tut_g_combo': [
      'Ardışık birleşmeler KOMBO yapar ve bonus puan verir. Hedefin Güneş\'e ulaşmak, hatta ötesine geçmek!',
      'Back-to-back merges make a COMBO and give bonus points. Your goal: reach the Sun and beyond!',
      'Слияния подряд дают КОМБО и бонусные очки. Твоя цель — дойти до Солнца и дальше!',
    ],
    'tut_g_free': [
      'Şimdi sen devam et! İstediğin zaman geri çıkabilirsin; ben ana ekranda bekliyorum.',
      'Now it\'s your turn! You can leave whenever you like; I\'ll be waiting on the home screen.',
      'Теперь твоя очередь! Можешь выйти в любой момент — я буду ждать на главном экране.',
    ],
    'tut_h_back': [
      'Harika gidiyorsun, Komutan! Şimdi ana ekranı gezelim.',
      'You\'re doing great, Commander! Let\'s tour the home screen.',
      'Отлично, командир! Теперь осмотрим главный экран.',
    ],
    'tut_h_resupply': [
      'Kozmik İkmal: Hazır olduğunda dokun, reklam izleyerek ücretsiz meteor kazan. Uzun basarsan ihtimalleri görürsün.',
      'Cosmic Resupply: tap it when it\'s ready and watch an ad for free meteors. Long-press to see the odds.',
      'Космическое снабжение: когда оно готово, нажми и посмотри рекламу — получишь метеоры бесплатно. Долгое нажатие покажет шансы.',
    ],
    'tut_h_tasks': [
      'Görevler burada. Dokunup içeri girelim!',
      'Your missions live here. Tap to step inside!',
      'Здесь твои задания. Нажми, чтобы зайти!',
    ],
    'tut_h_tasks_in1': [
      'Günlük, haftalık ve aylık görevleri yaparak Yıldız puanı kazanırsın.',
      'Complete daily, weekly and monthly missions to earn Star points.',
      'Выполняй ежедневные, еженедельные и ежемесячные задания, чтобы получать звёздные очки.',
    ],
    'tut_h_tasks_in2': [
      'Yıldız puanları Galaksi Yolu\'nda seviye atlatır; her seviyede meteor, XP ve güçlendirici ödülü var. Geri dönmek için sol üstteki oka dokun.',
      'Star points level you up on the Galaxy Path, with meteors, XP and power-ups at every level. Tap the back arrow at the top left to return.',
      'Звёздные очки повышают уровень на Галактическом пути: на каждом уровне — метеоры, опыт и усиления. Чтобы вернуться, нажми стрелку слева вверху.',
    ],
    'tut_h_daily': [
      'Günlük Meydan Okuma: herkes için aynı gezegen dizisi, sınırlı bırakışla hedef gezegene ulaş. Her gün tamamla, serin 🔥 büyüsün.',
      'Daily Challenge: everyone gets the same planet sequence; reach the target planet with limited drops. Finish it every day to grow your 🔥 streak.',
      'Ежедневный вызов: у всех одинаковая последовательность планет — достигни цели за ограниченное число бросков. Проходи каждый день, чтобы росла серия 🔥.',
    ],
    'tut_h_comet': [
      'Kuyruklu Yıldız: zaman zaman açılan, daha zor özel etkinlik. Tamamlayınca büyük ödül verir.',
      'Comet: a harder special event that opens from time to time. Finish it for a big reward.',
      'Комета: более сложное особое событие, которое открывается время от времени. За прохождение — крупная награда.',
    ],
    'tut_h_shop': [
      'Mağaza: meteorla güçlendirici ve seri koruyucu alabilirsin.',
      'Shop: spend meteors on power-ups and streak shields.',
      'Магазин: покупай за метеоры усиления и защиту серии.',
    ],
    'tut_h_room': [
      'Kozmik Oda: arka plan temalarını burada seçer, her oyunda rastgele tema seçeneğini açıp kapatırsın.',
      'Cosmic Room: pick your background themes here and toggle a random theme every game.',
      'Космическая комната: здесь выбирают фоновые темы и включают случайную тему для каждой игры.',
    ],
    'tut_h_rank': [
      'Rütben ve keşfettiğin gezegenler: dokununca Koleksiyon açılır. Rütbe atladıkça meteor kazanır, gizli gezegenleri açarsın!',
      'Your rank and discovered planets: tap to open the Collection. Ranking up earns meteors and unlocks hidden planets!',
      'Твой ранг и открытые планеты: нажми, чтобы открыть Коллекцию. Повышая ранг, получаешь метеоры и открываешь скрытые планеты!',
    ],
    'tut_h_board': [
      'Galaktik Sıralama: diğer oyuncuların rekorlarını burada görürsün.',
      'Galactic Ranking: see other players\' records here.',
      'Галактический рейтинг: здесь видны рекорды других игроков.',
    ],
    'tut_h_done': [
      'Eğitimi tamamladın, Komutan! İşte hediyen. Bol şans!',
      'Training complete, Commander! Here\'s your gift. Good luck!',
      'Обучение пройдено, командир! Вот твой подарок. Удачи!',
    ],
    'tut_reward_title': [
      'Eğitim Ödülü',
      'Training Reward',
      'Награда за обучение',
    ],
    'tut_replay': [
      'Öğreticiyi tekrar oyna',
      'Replay tutorial',
      'Пройти обучение заново',
    ],
    'mc_start': [
      'Başla',
      'Start',
      'Начать',
    ],
    'mc_retry': [
      'Tekrar dene',
      'Try again',
      'Попробовать снова',
    ],
    'mc_failTitle': [
      'Olmadı, tekrar dene!',
      'Not this time — try again!',
      'Не вышло — попробуйте ещё раз!',
    ],
    'mc_failOutOfDrops': [
      'Bırakış hakkın bitti!',
      'You ran out of drops!',
      'Броски закончились!',
    ],
    'mc_winTitle': [
      'Meydan okuma tamam!',
      'Challenge complete!',
      'Вызов пройден!',
    ],
    'mc_cometReward': [
      '+{m} ☄️   +{x} XP',
      '+{m} ☄️   +{x} XP',
      '+{m} ☄️   +{x} XP',
    ],
    'mc_cometAlready': [
      'Bu etkinliğin ödülünü zaten aldın.',
      'You already claimed this event\'s reward.',
      'Награда за это событие уже получена.',
    ],
    'mc_goalLine': [
      'Hedef: {name}',
      'Goal: {name}',
      'Цель: {name}',
    ],
    'mc_dropsLine': [
      'En fazla {n} bırakışın var.',
      'You have at most {n} drops.',
      'Всего у вас {n} бросков.',
    ],
    'mc_dropsLeft': [
      '{n}/{max} bırakış',
      '{n}/{max} drops',
      '{n}/{max} бросков',
    ],
    'mc_daily_target': [
      'Günlük: Hedef Gezegen',
      'Daily: Target Planet',
      'Ежедневно: целевая планета',
    ],
    'mc_daily_narrow': [
      'Günlük: Dar Kabin',
      'Daily: Tight Cabin',
      'Ежедневно: тесная кабина',
    ],
    'mc_daily_heavy': [
      'Günlük: Ağır Başlangıç',
      'Daily: Heavy Start',
      'Ежедневно: тяжёлый старт',
    ],
    'mc_daily_scarce': [
      'Günlük: Kıt Kaynak',
      'Daily: Scarce Supplies',
      'Ежедневно: мало ресурсов',
    ],
    'mc_comet_a': [
      'Kuyruklu Yıldız: Uzun Yol',
      'Comet: Long Haul',
      'Комета: дальний путь',
    ],
    'mc_comet_b': [
      'Kuyruklu Yıldız: Dar Geçit',
      'Comet: Narrow Pass',
      'Комета: узкий проход',
    ],
    'mc_comet_c': [
      'Kuyruklu Yıldız: Dev Başlangıç',
      'Comet: Giant Start',
      'Комета: гигантский старт',
    ],
    'mc_rule_target': [
      'Standart kurallar. Sınırlı bırakışta hedef gezegene ulaş.',
      'Standard rules. Reach the target planet within your drops.',
      'Обычные правила. Достигните цели за ограниченное число бросков.',
    ],
    'mc_rule_narrow': [
      'Tehlike çizgisi aşağıda — kabin daha dar, dikkatli yerleştir!',
      'The danger line is lower — less room, place carefully!',
      'Опасная линия ниже — места меньше, бросайте аккуратно!',
    ],
    'mc_rule_heavy': [
      'Başlangıçtan itibaren büyük gezegenler geliyor, küçükler yok.',
      'Big planets from the start — no small ones.',
      'С самого начала приходят крупные планеты, мелких нет.',
    ],
    'mc_rule_scarce': [
      'Çok az bırakışın var — her birleşme sayılır!',
      'Very few drops — every merge counts!',
      'Бросков очень мало — важно каждое слияние!',
    ],
    'mc_rule_comet_a': [
      'Uzun bir etkinlik: yüksek hedef, bol bırakış.',
      'A long event: high goal, plenty of drops.',
      'Длинное событие: высокая цель и много бросков.',
    ],
    'mc_rule_comet_b': [
      'Etkinlik kabini dar: tehlike çizgisi aşağıda.',
      'The event cabin is tight: the danger line is lower.',
      'Кабина события тесная: опасная линия ниже.',
    ],
    'mc_rule_comet_c': [
      'Etkinlik boyunca büyük gezegenler gelir, hedef çok yüksek.',
      'Big planets all event long and a very high goal.',
      'Всё событие приходят крупные планеты, цель очень высокая.',
    ],
  };
}

/// Kisa yol: her yerde `t('key')` yazabilmek icin.
String t(String key, [Map<String, String>? args]) =>
    AppLocale.instance.t(key, args);
