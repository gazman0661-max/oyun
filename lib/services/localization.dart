import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { tr, en, ru }

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
    final code = switch (lang) {
      AppLanguage.tr => 'tr',
      AppLanguage.en => 'en',
      AppLanguage.ru => 'ru',
    };
    await prefs.setString(_prefsKey, code);
    await prefs.setBool(_chosenPrefsKey, true);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_lang == lang) return;
    _lang = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final code = switch (lang) {
      AppLanguage.tr => 'tr',
      AppLanguage.en => 'en',
      AppLanguage.ru => 'ru',
    };
    await prefs.setString(_prefsKey, code);
  }

  int get _i => switch (_lang) {
        AppLanguage.tr => 0,
        AppLanguage.en => 1,
        AppLanguage.ru => 2,
      };

  /// Bir anahtari mevcut dile cevirir. {ad} gibi yer tutuculari [args]
  /// ile degistirir (orn. t('win_missionCompleted', {'n': '7'})).
  String t(String key, [Map<String, String>? args]) {
    final list = _strings[key];
    var s = (list != null && _i < list.length) ? list[_i] : key;
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
      'Galaksiler Arası Renk Sıralama',
      'Intergalactic Color Sorting',
      'Межгалактическая сортировка цвета',
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
    'home_dailyTitle': ['Günlük Sinyal', 'Daily Signal', 'Ежедневный сигнал'],
    'home_dailyDoneTitle': [
      'Bugün Tamamlandı',
      'Completed Today',
      'Сегодня выполнено',
    ],
    'home_dailySubtitle': [
      'Herkese aynı sinyal, sadece bugün.',
      'Same signal for everyone, today only.',
      'Один сигнал для всех, только сегодня.',
    ],
    'home_dailyDoneSubtitle': [
      'Yarın tekrar gel.',
      'Come back tomorrow.',
      'Приходи завтра.',
    ],
    'home_chooseStage': ['Görev Seç', 'Choose Mission', 'Выбор задания'],
    'home_stageHint': [
      'Sırayla ilerle, her görev bir öncekinden biraz daha zor.',
      'Progress in order — each mission is a bit harder than the last.',
      'Проходи по порядку — каждое задание немного сложнее предыдущего.',
    ],
    'home_lockedStage': [
      '🔒 Bu görev henüz kilitli.',
      '🔒 This mission is still locked.',
      '🔒 Это задание пока заблокировано.',
    ],

    // ---- Profil ----
    'profile_totalStars': ['Toplam Yıldız', 'Total Stars', 'Всего звёзд'],
    'profile_stagesCleared': ['Tamamlanan', 'Cleared', 'Пройдено'],
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
      '{n} bölüm bitir, {r} meteor kazan',
      'Complete {n} stages, earn {r} meteors',
      'Пройдите {n} уровней и получите {r} метеоритов',
    ],
    'home_weeklyProgress': [
      '{done}/{total} bölüm',
      '{done}/{total} stages',
      '{done}/{total} уровней',
    ],
    // ---- Dönüşümlü haftalık görev tipleri (bkz. WeeklyQuestType) ----
    'home_weeklySubtitle_clean': [
      'İpucu/yardım kullanmadan {n} bölüm bitir, {r} meteor kazan',
      'Clear {n} stages without hints or assists, earn {r} meteors',
      'Пройдите {n} уровней без подсказок и получите {r} метеоритов',
    ],
    'home_weeklySubtitle_perfect': [
      '{n} bölümü 3 yıldızla bitir, {r} meteor kazan',
      'Finish {n} stages with 3 stars, earn {r} meteors',
      'Завершите {n} уровней на 3 звезды и получите {r} метеоритов',
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
      '{n} bölüm bitir, {r} meteor kazan',
      'Complete {n} stages, earn {r} meteors',
      'Пройдите {n} уровней и получите {r} метеоритов',
    ],
    'home_monthlySubtitle_clean': [
      'İpucu/yardım kullanmadan {n} bölüm bitir, {r} meteor kazan',
      'Clear {n} stages without hints or assists, earn {r} meteors',
      'Пройдите {n} уровней без подсказок и получите {r} метеоритов',
    ],
    'home_monthlySubtitle_perfect': [
      '{n} bölümü 3 yıldızla bitir, {r} meteor kazan',
      'Finish {n} stages with 3 stars, earn {r} meteors',
      'Завершите {n} уровней на 3 звезды и получите {r} метеоритов',
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
      '{done}/{total} yıldız — Orbit\'te kazan',
      '{done}/{total} stars — earn them in Orbit',
      '{done}/{total} звёзд — заработайте в Orbit',
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
      'Takımyıldızları haftalık olarak Orbit\'te tamamlayarak kazanılır.',
      'Earned by completing constellations in Orbit each week.',
      'Получаются за завершение созвездий в Orbit каждую неделю.',
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
      'Meteorla malzeme satın al, biriktir, oyunda reklam izlemeden kullan.',
      'Buy supplies with meteors, stock up, and use them in-game without watching an ad.',
      'Покупайте снаряжение за метеоры, копите и используйте в игре без рекламы.',
    ],
    'supplyShop_itemDockSlot': ['Rıhtım Yuvası', 'Dock Slot', 'Место в доке'],
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
    // DUZELTME: Dukkan'a yeni "Yardimcilar" (Meteor Magazasi) sekmesi
    // eklendi — hint/geri al/ters cevir/ekstra tank/orbit rihtim hakki
    // ARTIK ONCEDEN meteorla satin alinip stoklanabiliyor. Backend zaten
    // hazirdi (player_progress.dart _buyBankedItem'lar), sadece UI
    // eksikti.
    'shop_tabThemes': ['Temalar', 'Themes', 'Темы'],
    'shop_tabHelpers': ['Yardımcılar', 'Helpers', 'Помощники'],
    'shop_helpersSubtitle': [
      'Meteorla önceden satın al, bölüm içinde reklamsız kullan.',
      'Buy ahead with meteors, use them in-mission without an ad.',
      'Купите заранее за метеориты, используйте в задании без рекламы.',
    ],
    'shop_ownedCount': [
      '🎁 Bankada: {count}',
      '🎁 Banked: {count}',
      '🎁 В банке: {count}',
    ],
    'shop_dockSlot': ['Rıhtım Hakkı', 'Dock Slot', 'Место в доке'],
    'shop_dockSlotDesc': [
      'Yörünge modunda rıhtım dolduğunda +1 yuva açar.',
      'Opens +1 slot when the dock is full in Orbit mode.',
      'Открывает +1 место, когда док заполнен в режиме «Орбита».',
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
    'daily_moves': ['Hamle', 'Moves', 'Ходы'],
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
    'resupply_rewardOrbitDockSlot': [
      '+{n} ⚓ Rıhtım Yuvası',
      '+{n} ⚓ Dock Slot',
      '+{n} ⚓ Место в доке',
    ],
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

    // ---- Orbit: kombo/skor + kilitli halka + meteor ile rıhtım ----
    'orbit_comboLabel': ['Kombo', 'Combo', 'Комбо'],
    'orbit_scoreLabel': ['Puan', 'Score', 'Очки'],
    'orbit_lockedRingHint': [
      '🔒 Bu halka kilitli — açmak için {n} teslimat yap',
      '🔒 This ring is locked — deliver {n} more to unlock',
      '🔒 Это кольцо заблокировано — доставьте ещё {n}',
    ],
    'orbit_ringUnlocked': ['🔓 Halka açıldı!', '🔓 Ring unlocked!', '🔓 Кольцо разблокировано!'],
    'orbit_buyDockMeteor': [
      '☄️ {price} Meteor ile Genişlet',
      '☄️ Expand for {price} Meteor',
      '☄️ Расширить за {price} метеор(ов)',
    ],
    'orbit_notEnoughMeteor': [
      'Yeterli meteorun yok',
      'Not enough meteors',
      'Недостаточно метеоров',
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

    // ---- Ana ekran: Yörünge bölüm ızgarası eyebrow + Enerji Tüpleri karti ----
    'home_orbitSectionTitle': [
      'Yörünge Vardiyası',
      'Orbit Shift',
      'Орбитальная смена',
    ],

    // ---- Ana ekran: Harita ve Kozmik Oda kartları ----
    'home_mapCardTitle': ['Harita', 'Map', 'Карта'],
    'home_shopCardTitle': ['Mağaza', 'Shop', 'Магазин'],
    'home_mapCardSubtitle': [
      'Görevleri seç ve ilerle',
      'Pick a mission and progress',
      'Выбери задание и продолжай',
    ],
    'home_cosmicRoomCardSubtitle': [
      'Temanı özelleştir',
      'Customize your theme',
      'Настрой свою тему',
    ],

    // ---- Enerji Tüpleri bölüm secim ekrani ----

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

    // ---- Yörünge Vardiyası oyun ekrani ----
    'orbit_expandDockTitle': [
      'Rıhtımı Genişlet',
      'Expand the Dock',
      'Расширить причал',
    ],
    'orbit_expandDockSubtitle': [
      'Reklamı izle, bu bölüm için +1 kargo yuvası kazan.',
      'Watch an ad to earn +1 cargo slot for this stage.',
      'Посмотрите рекламу, чтобы получить +1 грузовой слот для этого уровня.',
    ],
    'orbit_dailyTitle': [
      'Günlük Yörünge Vardiyası',
      'Daily Orbit Shift',
      'Ежедневная орбитальная смена',
    ],
    'orbit_stageTitle': [
      'Yörünge Vardiyası · Bölüm {n}',
      'Orbit Shift · Stage {n}',
      'Орбитальная смена · Уровень {n}',
    ],
    'orbit_requestedOrder': ['İstenen sıra', 'Requested order', 'Нужный порядок'],
    'orbit_cargoDock': ['Kargo Rıhtımı', 'Cargo Dock', 'Грузовой причал'],
    'orbit_plusSlot': ['+1 Yuva', '+1 Slot', '+1 слот'],
    'orbit_rotationsTarget': [
      'Dönüş: {rotations}  ·  Hedef: {par}',
      'Rotations: {rotations}  ·  Target: {par}',
      'Повороты: {rotations}  ·  Цель: {par}',
    ],
    'orbit_tutorialTitle': [
      'Yörünge Vardiyası Nasıl Oynanır?',
      'How to Play Orbit Shift?',
      'Как играть в «Орбитальную смену»?',
    ],
    'orbit_rule1Title': ['1) Hangi halka?', '1) Which ring?', '1) Какое кольцо?'],
    'orbit_rule1Body': [
      'Merkeze olan uzaklığına göre tut. Parmağını hangi halkanın '
          'üzerine koyup sürüklersen o halka döner.',
      'Grab based on distance from the center. Whichever nested ring '
          'you press and drag is the one that rotates.',
      'Хватайте кольцо в зависимости от расстояния до центра. Какое '
          'кольцо потянете, то и повернётся.',
    ],
    'orbit_rule2Title': ['2) Nasıl döndürülür?', '2) How to rotate?', '2) Как повернуть?'],
    'orbit_rule2Body': [
      'Halkayı tut ve istediğin yöne (saat yönü ya da tersi, fark etmez) '
          'sürükle — halka parmağınla birlikte döner.',
      'Grab the ring and drag it either way — clockwise or counter-'
          'clockwise — the ring turns together with your finger.',
      'Возьмите кольцо и потяните в любую сторону — по часовой или '
          'против — кольцо повернётся вместе с пальцем.',
    ],
    // DUZELTME: Bu kural sadece okunarak degil, DENEYEREK ogretiliyor —
    // CoachOverlay bu adimda ekranin geri kalanini bloke etmiyor, oyuncu
    // gercekten bir halkayi surukleyene kadar bekliyor ve otomatik ilerliyor.
    // Bkz. orbit_game_screen.dart _showTutorialDialog() / coach_overlay.dart.
    'orbit_rule2TryBody': [
      'Halkayı tut ve istediğin yöne sürükle — parmağınla birlikte döner. '
          'Şimdi bir halkayı SÜRÜKLE ve dene — otomatik devam edeceğiz.',
      'Grab a ring and drag it either way — it turns with your finger. '
          'Now DRAG a ring and try it — we\'ll continue automatically.',
      'Возьмите кольцо и потяните в любую сторону — оно повернётся '
          'вместе с пальцем. Теперь ПОТЯНИТЕ кольцо и попробуйте — мы '
          'продолжим автоматически.',
    ],
    'orbit_rule3Title': [
      '3) Kapı ve rıhtım',
      '3) Gate and dock',
      '3) Ворота и причал',
    ],
    'orbit_rule3Body': [
      'Tepedeki kapıya gelen gezegen, sıradaki hedefle eşleşiyorsa '
          'teslim edilir; eşleşmiyorsa rıhtımda bekler. Rıhtım doluyken '
          'hedefe uymayan bir gezegeni kapıya getirecek dönüşler engellenir.',
      'A planet arriving at the top gate is delivered if it matches '
          'the next target; otherwise it waits at the dock. While the dock '
          'is full, rotations that would bring a non-matching planet to '
          'the gate are blocked.',
      'Планета, прибывшая к воротам, будет доставлена, если совпадает '
          'со следующей целью; иначе она ждёт у причала. Пока причал полон, '
          'повороты, которые привели бы к воротам несовпадающую планету, '
          'блокируются.',
    ],
    'orbit_gotIt': ['Anladım', 'Got it', 'Понятно'],
    'coach_next': ['İleri', 'Next', 'Далее'],
    'coach_gotIt': ['Anladım', 'Got it', 'Понятно'],
    // DUZELTME: interaktif (waitForAction) coach adimlarinda "Ileri"
    // butonu yerine gosterilen bekleme ipucu + acil durumda kacis (Atla).
    'coach_waitingHint': ['Dene bakalım 👆', 'Give it a try 👆', 'Попробуйте сами 👆'],
    'coach_skip': ['Atla', 'Skip', 'Пропустить'],
    'orbit_rule3TryTitle': [
      '3) Az önce ne oldu?',
      '3) What just happened?',
      '3) Что только что произошло?',
    ],
    'orbit_systemComplete': [
      'Sistem Tamamlandı!',
      'System Complete!',
      'Система завершена!',
    ],
    'orbit_dockJammed': ['Rıhtım Tıkandı', 'Dock Jammed', 'Причал заблокирован'],
    'orbit_jamDesc': [
      'Tüm rıhtım yuvaları doldu ve kapıya gelen kargo eşleşmedi.\n'
          'Farklı bir sırayla dene!',
      'All dock slots are full and the cargo reaching the gate '
          'didn\'t match.\nTry a different order!',
      'Все слоты причала заполнены, а груз у ворот не совпал.\n'
          'Попробуй другой порядок!',
    ],
    'orbit_useBankedSlot': [
      '⚓ Bankadan Yuva Kullan ({n} kalan)',
      '⚓ Use Banked Slot ({n} left)',
      '⚓ Использовать слот из банка (осталось {n})',
    ],
    'orbit_watchAdExpand': [
      'Reklam İzle · +1 Rıhtım Yuvası',
      'Watch Ad · +1 Dock Slot',
      'Смотреть рекламу · +1 слот причала',
    ],
    'orbit_buyDockMeteorFull': [
      '☄️ {price} Meteor ile Genişlet  ·  ({balance} elinde)',
      '☄️ Expand for {price} Meteor  ·  ({balance} on hand)',
      '☄️ Расширить за {price} метеор(ов)  ·  (у вас {balance})',
    ],
    'orbit_exit': ['Çıkış', 'Exit', 'Выход'],
    'orbit_nextStage': ['Sonraki Bölüm', 'Next Stage', 'Следующий уровень'],
    'orbit_tryAgain': ['Tekrar Dene', 'Try Again', 'Повторить'],
    'orbit_tapLeft': ['Sola dokun', 'Tap left', 'Нажми слева'],
    'orbit_tapRight': ['Sağa dokun', 'Tap right', 'Нажми справа'],
    'orbit_dragHint': [
      'Halkayı tut, istediğin yöne sürükle',
      'Grab a ring, drag it either way',
      'Возьми кольцо и потяни в любую сторону',
    ],
    'orbit_lockedRingToast': [
      '🔒 Bu halka hâlâ kilitli — birkaç teslimat daha yap',
      '🔒 This ring is still locked — make a few more deliveries',
      '🔒 Это кольцо всё ещё заблокировано — сделайте ещё пару доставок',
    ],
    'orbit_dockFullToast': [
      '🚧 Rıhtım dolu — önce oradaki yükü boşalt!',
      '🚧 Dock is full — clear the load there first!',
      '🚧 Причал заполнен — сначала разгрузите его!',
    ],
    'orbit_undoTooltip': [
      'Hamleyi geri al',
      'Undo move',
      'Отменить ход',
    ],
    'orbit_undoNoneAvailable': [
      '↩️ Bugünkü ücretsiz hakların bitti, yeterli meteorün de yok',
      '↩️ Out of free undos today, and not enough meteors',
      '↩️ Бесплатные отмены сегодня закончились, метеоритов не хватает',
    ],
    'orbit_undoUsedFree': [
      '↩️ Hamle geri alındı',
      '↩️ Move undone',
      '↩️ Ход отменён',
    ],
    'orbit_undoUsedMeteor': [
      '↩️ Hamle geri alındı (−{price} meteor)',
      '↩️ Move undone (−{price} meteor)',
      '↩️ Ход отменён (−{price} метеорит)',
    ],

    // ---- Günlük sonuç paylasim karti ----
    'daily_shareChallenge': [
      'Beni yenebilir misin? 👀',
      'Can you beat me? 👀',
      'Сможешь меня обыграть? 👀',
    ],
    'daily_shareCardTitle': [
      'Yörünge Vardiyası · Günlük #{n}',
      'Orbit Shift · Daily #{n}',
      'Орбитальная смена · Ежедневный #{n}',
    ],
    'daily_shareMoves': ['hamle', 'moves', 'ходов'],
    'daily_shareTime': ['süre', 'time', 'время'],
    'daily_shareStreak': ['seri', 'streak', 'серия'],
  };
}

/// Kisa yol: her yerde `t('key')` yazabilmek icin.
String t(String key, [Map<String, String>? args]) =>
    AppLocale.instance.t(key, args);
