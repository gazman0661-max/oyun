/// Hafif, paket gerektirmeyen dil sistemi.
///
/// Neden `intl`/ARB dosyaları yerine bu basit yapı: proje şu an sadece
/// birkaç düzine UI metni içeriyor - tam bir yerelleştirme paketinin
/// (ayrı .arb dosyaları, kod üretimi, build_runner adımı) getirdiği
/// karmaşıklık bu ölçekte gereksiz. Aşağıdaki yapı %100 elle
/// okunabilir Dart kodu: yeni bir dil eklemek = Map'e yeni bir
/// AppLanguage değeri + her satıra bir çeviri eklemek kadar basit.
///
/// Proje büyüyüp onlarca ekrana/yüzlerce metne çıkarsa `intl` paketine
/// geçmek mantıklı olur - o zaman burada kullanılan `t('key')` çağrı
/// noktaları neredeyse hiç değişmeden ARB tabanlı bir sisteme taşınabilir.
import '../models/town.dart' show localChapterNumber;
enum AppLanguage { tr, en }

class AppStrings {
  AppStrings._internal();
  static final AppStrings instance = AppStrings._internal();

  /// Uygulama genelinde aktif dil. Şu an sadece BELLEKTE tutuluyor -
  /// GameProgress'teki coin/ilerleme gibi, gerçek kalıcılık
  /// (shared_preferences) henüz eklenmedi; bu da aynı "sıradaki adım"
  /// listesine giriyor.
  AppLanguage language = AppLanguage.tr;

  void toggle() {
    language = language == AppLanguage.tr ? AppLanguage.en : AppLanguage.tr;
  }

  /// Basit sabit metinler icin anahtar bazli sozluk.
  String t(String key) {
    final entry = _values[key];
    if (entry == null) return key; // ceviri unutulduysa sessizce patlamasin
    return entry[language] ?? entry[AppLanguage.tr] ?? key;
  }

  // ── Parametreli / kalıp cümleler (map ile ifade etmesi zor olanlar) ──

  // Arayuzde bolge ici numara (1-8) gosterilir; 9. bolum = 2. bolgenin 1. bolumu.
  String chapterLabel(int chapterNumber) {
    final n = localChapterNumber(chapterNumber);
    return language == AppLanguage.tr ? 'Bölüm $n' : 'Chapter $n';
  }

  String chapterGoalLabel(int goal) =>
      language == AppLanguage.tr ? '$goal sipariş' : '$goal orders';

  String chapterCompleteTitle(int chapterNumber) {
    final n = localChapterNumber(chapterNumber);
    return language == AppLanguage.tr ? '🎉 Bölüm $n Tamamlandı!' : '🎉 Chapter $n Complete!';
  }

  String chapterCompleteSubtitle(int goal, int coins) => language == AppLanguage.tr
      ? '$goal siparişi başarıyla teslim ettin.\nToplam kazanç: $coins coin'
      : 'You successfully delivered $goal orders.\nTotal earnings: $coins coins';

  String tableFullSubtitle(int completed, int goal, int coins) => language == AppLanguage.tr
      ? 'Sipariş: $completed/$goal  •  Coin: $coins'
      : 'Orders: $completed/$goal  •  Coins: $coins';

  /// "12/15 sipariş teslim et" gibi ilerleme cumlecikleri icin.
  String missionProgressLabel(int progress, int target, String suffixKey) =>
      '${progress.clamp(0, target)}/$target ${t(suffixKey)}';

  static const Map<String, Map<AppLanguage, String>> _values = {
    // ── Ana menü ──
    'game_title': {AppLanguage.tr: 'Merge Dünyaları', AppLanguage.en: 'Merge Worlds'},
    'game_tagline': {
      AppLanguage.tr: 'Dünyaları birleştir, maceraya atıl!',
      AppLanguage.en: 'Merge your way through every world!',
    },
    'shop_upgrades': {AppLanguage.tr: 'Dükkan - Yükseltmeler', AppLanguage.en: 'Shop - Upgrades'},
    'upgrade_throw_title': {AppLanguage.tr: 'Hızlı Atış', AppLanguage.en: 'Quick Throw'},
    'upgrade_throw_desc': {
      AppLanguage.tr: 'Fırlatışlar arası bekleme süresini kısaltır.',
      AppLanguage.en: 'Shortens the wait time between throws.',
    },
    'upgrade_luck_title': {AppLanguage.tr: 'Şanslı Başlangıç', AppLanguage.en: 'Lucky Start'},
    'upgrade_luck_desc': {
      AppLanguage.tr: 'Daha yüksek seviyeli objelerin gelme ihtimalini artırır.',
      AppLanguage.en: 'Increases the chance of higher-level items appearing.',
    },
    'level_of': {AppLanguage.tr: 'Seviye', AppLanguage.en: 'Level'},
    'max': {AppLanguage.tr: 'Max', AppLanguage.en: 'Max'},
    'insufficient_coins': {
      AppLanguage.tr: 'Yetersiz coin ya da zaten maksimum seviyede.',
      AppLanguage.en: 'Not enough coins, or already at max level.',
    },
    'upgrade_success_throw': {AppLanguage.tr: 'Hızlı Atış yükseltildi!', AppLanguage.en: 'Quick Throw upgraded!'},
    'upgrade_success_luck': {AppLanguage.tr: 'Şanslı Başlangıç yükseltildi!', AppLanguage.en: 'Lucky Start upgraded!'},

    // ── Enerji sistemi ──
    'energy_title': {AppLanguage.tr: 'Enerji', AppLanguage.en: 'Energy'},
    'energy_full': {AppLanguage.tr: 'Enerji dolu', AppLanguage.en: 'Energy full'},
    'energy_watch_ad': {AppLanguage.tr: 'Enerji Doldur', AppLanguage.en: 'Refill Energy'},
    'energy_watch_ad_hint': {
      AppLanguage.tr: 'Reklam izle, +1 enerji kazan',
      AppLanguage.en: 'Watch an ad, earn +1 energy',
    },
    'energy_ad_quota_locked': {
      AppLanguage.tr: 'Reklam hakkın bitti, sayaç dolunca yenilenir',
      AppLanguage.en: 'Out of ad refills, resets when the timer runs out',
    },
    'ad_loading': {AppLanguage.tr: 'Reklam yükleniyor...', AppLanguage.en: 'Loading ad...'},
    'ad_no_internet': {AppLanguage.tr: 'Reklam için internet bağlantısı gerekli', AppLanguage.en: 'An internet connection is needed to watch an ad'},
    'no_energy_title': {AppLanguage.tr: 'Enerjin Kalmadı', AppLanguage.en: 'Out of Energy'},
    'no_energy_body': {
      AppLanguage.tr: 'Bölüme başlamak için en az 1 enerjin olmalı. Mücevherle hemen doldurabilir, ana menüden reklam izleyebilir ya da zamanla dolmasını bekleyebilirsin.',
      AppLanguage.en: 'You need at least 1 energy to start a level. Refill instantly with gems, watch an ad on the main menu, or wait for it to regenerate.',
    },
    'ok': {AppLanguage.tr: 'Tamam', AppLanguage.en: 'OK'},
    'ad_retry_title': {AppLanguage.tr: 'Masa Doldu!', AppLanguage.en: 'Table Full!'},
    'ad_retry_watch': {
      AppLanguage.tr: 'Reklam İzle, Enerji Harcamadan Tekrar Dene',
      AppLanguage.en: 'Watch Ad, Retry Without Spending Energy',
    },
    'return_to_menu': {AppLanguage.tr: 'Ana Menüye Dön', AppLanguage.en: 'Return to Menu'},

    // ── Bölüm haritası ──
    'chapter_map_title': {AppLanguage.tr: 'Bölüm Haritası', AppLanguage.en: 'Chapter Map'},
    'locked': {AppLanguage.tr: 'Kilitli', AppLanguage.en: 'Locked'},
    'play': {AppLanguage.tr: 'Oyna', AppLanguage.en: 'Play'},
    'play_again': {AppLanguage.tr: 'Tekrar Oyna', AppLanguage.en: 'Play Again'},
    'level_up_title': {AppLanguage.tr: 'Seviye Atlama', AppLanguage.en: 'Level Up'},
    'rewards_label': {AppLanguage.tr: 'Ödüller', AppLanguage.en: 'Rewards'},
    'claim_button': {AppLanguage.tr: 'Al', AppLanguage.en: 'Claim'},
    'level_up_energy_full': {AppLanguage.tr: 'Enerjin tamamen doldu!', AppLanguage.en: 'Your energy is fully refilled!'},
    'stars_verdict_3': {AppLanguage.tr: 'Mükemmel!', AppLanguage.en: 'Perfect!'},
    'stars_verdict_2': {AppLanguage.tr: 'Harika!', AppLanguage.en: 'Great!'},
    'stars_verdict_1': {AppLanguage.tr: 'Güzel!', AppLanguage.en: 'Nice!'},
    'stars_hint_3': {AppLanguage.tr: 'Masayı tertemiz tuttun', AppLanguage.en: 'You kept the table spotless'},
    'stars_hint_other': {AppLanguage.tr: 'Masayı daha boş tutarsan daha çok yıldız kazanırsın', AppLanguage.en: 'Keep the table emptier to earn more stars'},
    'level_short': {AppLanguage.tr: 'Sv.', AppLanguage.en: 'Lv.'},
    'theme_fastfood': {AppLanguage.tr: 'Fast Food Dükkanı', AppLanguage.en: 'Fast Food Shop'},
    'theme_cafe': {AppLanguage.tr: 'Kafe & Pastane', AppLanguage.en: 'Cafe & Bakery'},
    'theme_magic': {AppLanguage.tr: 'Büyü & Simya', AppLanguage.en: 'Magic & Alchemy'},
    'theme_pirate': {AppLanguage.tr: 'Korsan Hazinesi', AppLanguage.en: 'Pirate Treasure'},
    'theme_ice': {AppLanguage.tr: 'Buz Krallığı', AppLanguage.en: 'Ice Kingdom'},
    'theme_space': {AppLanguage.tr: 'Uzay İstasyonu', AppLanguage.en: 'Space Station'},

    // ── Ayarlar (ana menu sag ust butonlari) ──
    'settings_sound': {AppLanguage.tr: 'Ses', AppLanguage.en: 'Sound'},
    'settings_haptics': {AppLanguage.tr: 'Titreşim', AppLanguage.en: 'Vibration'},

    // ── Oyun içi HUD / diyaloglar ──
    'hud_level': {AppLanguage.tr: 'Level', AppLanguage.en: 'Level'},
    'exit_chapter_title': {AppLanguage.tr: 'Bölümden çık', AppLanguage.en: 'Exit chapter'},
    'exit_chapter_body': {
      AppLanguage.tr: 'Bölüm haritasına dönmek istediğine emin misin? Kazandığın coinler kaydedildi.',
      AppLanguage.en: 'Are you sure you want to return to the chapter map? Your coins have been saved.',
    },
    'cancel': {AppLanguage.tr: 'Vazgeç', AppLanguage.en: 'Cancel'},
    'exit': {AppLanguage.tr: 'Çık', AppLanguage.en: 'Exit'},
    'table_full_title': {AppLanguage.tr: 'Masa Doldu!', AppLanguage.en: 'Table Full!'},
    'restart': {AppLanguage.tr: 'Yeniden Başla', AppLanguage.en: 'Restart'},
    'next_chapter': {AppLanguage.tr: 'Sonraki Bölüm →', AppLanguage.en: 'Next Chapter →'},
    'next_region': {AppLanguage.tr: 'Yeni Bölgeye Geç →', AppLanguage.en: 'Next Region →'},
    'return_to_map': {AppLanguage.tr: 'Bölüm Haritasına Dön', AppLanguage.en: 'Return to Chapter Map'},
    'aim_hint': {
      AppLanguage.tr: 'Sürükleyerek nişan al, bıraktığında obje karşıya kayar. Siparişle eşleşen obje durunca otomatik teslim edilir.',
      AppLanguage.en: 'Drag to aim, release to launch the item. It delivers automatically once it stops on a matching order.',
    },
    'next_label': {AppLanguage.tr: 'SONRAKİ', AppLanguage.en: 'NEXT'},

    // ── Ekstra Sipariş Slotu ──
    'upgrade_slot_title': {AppLanguage.tr: 'Ekstra Sipariş Slotu', AppLanguage.en: 'Extra Order Slot'},
    'upgrade_slot_desc': {
      AppLanguage.tr: 'Aynı anda bekleyen sipariş sayısını artırır.',
      AppLanguage.en: 'Increases the number of orders waiting at once.',
    },
    'upgrade_success_slot': {AppLanguage.tr: 'Ekstra Sipariş Slotu açıldı!', AppLanguage.en: 'Extra Order Slot unlocked!'},

    // ── Günlük ödül ──
    'daily_reward_title': {AppLanguage.tr: 'Günlük Ödül', AppLanguage.en: 'Daily Reward'},
    'daily_reward_available': {AppLanguage.tr: 'Bugünkü ödülün hazır!', AppLanguage.en: 'Today\'s reward is ready!'},
    'daily_reward_claimed_today': {AppLanguage.tr: 'Bugün zaten aldın, yarın tekrar gel!', AppLanguage.en: 'Already claimed today, come back tomorrow!'},
    'daily_reward_claim': {AppLanguage.tr: 'Ödülü Al', AppLanguage.en: 'Claim Reward'},
    'daily_reward_streak': {AppLanguage.tr: 'Seri', AppLanguage.en: 'Streak'},
    'daily_reward_claimed_toast': {AppLanguage.tr: 'Günlük ödül alındı!', AppLanguage.en: 'Daily reward claimed!'},

    // ── Görevler (Günlük / Haftalık / Aylık) ──
    'missions_title': {AppLanguage.tr: 'Görevler', AppLanguage.en: 'Missions'},
    'missions_tab_daily': {AppLanguage.tr: 'Günlük', AppLanguage.en: 'Daily'},
    'missions_tab_weekly': {AppLanguage.tr: 'Haftalık', AppLanguage.en: 'Weekly'},
    'missions_tab_monthly': {AppLanguage.tr: 'Aylık', AppLanguage.en: 'Monthly'},
    'mission_deliver': {AppLanguage.tr: 'sipariş teslim et', AppLanguage.en: 'orders delivered'},
    'mission_merge': {AppLanguage.tr: 'birleştirme yap', AppLanguage.en: 'merges made'},
    'mission_coins': {AppLanguage.tr: 'coin kazan', AppLanguage.en: 'coins earned'},
    'mission_claim': {AppLanguage.tr: 'Al', AppLanguage.en: 'Claim'},
    'mission_claimed': {AppLanguage.tr: 'Alındı', AppLanguage.en: 'Claimed'},

    // ── Sans carki ──
    'season_title': {AppLanguage.tr: 'Sezon Yolu', AppLanguage.en: 'Season Pass'},
    'season_tier': {AppLanguage.tr: 'Kademe', AppLanguage.en: 'Tier'},
    'season_free': {AppLanguage.tr: 'Bedava', AppLanguage.en: 'Free'},
    'season_premium': {AppLanguage.tr: 'Premium', AppLanguage.en: 'Premium'},
    'season_premium_buy': {AppLanguage.tr: 'Premium Yolu Aç', AppLanguage.en: 'Unlock Premium'},
    'season_premium_on': {AppLanguage.tr: 'Premium aktif', AppLanguage.en: 'Premium active'},
    'season_claim_all': {AppLanguage.tr: 'Hepsini Al', AppLanguage.en: 'Claim All'},
    'season_done': {AppLanguage.tr: 'Tüm kademeler tamam! 🎉', AppLanguage.en: 'All tiers complete! 🎉'},
    'season_sp_hint': {
      AppLanguage.tr: 'Sipariş, görev, çark ve bölümlerle SP kazan',
      AppLanguage.en: 'Earn SP from orders, missions, wheel and chapters'
    },
    'piggy_title': {AppLanguage.tr: 'Ejderha Kumbarası', AppLanguage.en: 'Dragon Hoard'},
    'piggy_how': {
      AppLanguage.tr: 'Sipariş teslim ettikçe ve bölüm geçtikçe bebek ejderhanın hazinesinde 💎 birikir. Yeterince dolunca hepsini alabilirsin.',
      AppLanguage.en: 'Gems build up in the baby dragon\'s hoard as you deliver orders and clear chapters. Claim it once it has enough.'
    },
    'piggy_break': {AppLanguage.tr: 'Hazineyi Al', AppLanguage.en: 'Claim the Hoard'},
    'piggy_need': {AppLanguage.tr: 'Almak için en az', AppLanguage.en: 'Needs at least'},
    'piggy_broken': {AppLanguage.tr: 'ejderhanın hazinesinden çıktı!', AppLanguage.en: 'from the dragon\'s hoard!'},
    'piggy_full': {AppLanguage.tr: 'Ejderha doldu, hazineyi alma zamanı!', AppLanguage.en: 'The dragon\'s hoard is full, time to claim it!'},
    'notif_energy_title': {AppLanguage.tr: 'Enerjin doldu ⚡', AppLanguage.en: 'Energy full ⚡'},
    'notif_energy_body': {AppLanguage.tr: 'Siparişler seni bekliyor, hadi oynayalım!', AppLanguage.en: 'Orders are waiting, let\'s play!'},
    'notif_daily_title': {AppLanguage.tr: 'Bedava ödüller hazır 🎁', AppLanguage.en: 'Free rewards ready 🎁'},
    'notif_daily_body': {AppLanguage.tr: 'Günlük ödül ve Şans Çarkı seni bekliyor.', AppLanguage.en: 'Your daily reward and Lucky Wheel are waiting.'},
    'notif_season_title': {AppLanguage.tr: 'Sezon bitmek üzere 🏆', AppLanguage.en: 'Season ending soon 🏆'},
    'notif_season_body': {AppLanguage.tr: 'Kaçırdığın Sezon Yolu ödüllerini almak için son 2 gün!', AppLanguage.en: 'Last 2 days to grab your Season Pass rewards!'},
    'notif_back_title': {AppLanguage.tr: 'Kasaba seni özledi 🏘️', AppLanguage.en: 'Your town misses you 🏘️'},
    'notif_back_body': {AppLanguage.tr: 'Geri dön, ödüllerin birikti.', AppLanguage.en: 'Come back, your rewards are piling up.'},
    'event_title': {AppLanguage.tr: 'Haftalık Etkinlik', AppLanguage.en: 'Weekly Event'},
    'event_goal': {AppLanguage.tr: 'Hedef', AppLanguage.en: 'Goal'},
    'event_weekend': {AppLanguage.tr: 'HAFTA SONU: puanlar 2 KAT!', AppLanguage.en: 'WEEKEND: points count DOUBLE!'},
    'event_orders_name': {AppLanguage.tr: 'Sipariş Fırtınası', AppLanguage.en: 'Order Storm'},
    'event_orders_desc': {AppLanguage.tr: 'Bu hafta en çok sipariş teslim et!', AppLanguage.en: 'Deliver as many orders as you can this week!'},
    'event_merges_name': {AppLanguage.tr: 'Birleştirme Şenliği', AppLanguage.en: 'Merge Fest'},
    'event_merges_desc': {AppLanguage.tr: 'Bu hafta her birleştirme puan!', AppLanguage.en: 'Every merge counts this week!'},
    'event_combos_name': {AppLanguage.tr: 'Kombo Ustası', AppLanguage.en: 'Combo Master'},
    'event_combos_desc': {AppLanguage.tr: 'Art arda 3+ birleştirme yap, zincirleri say!', AppLanguage.en: 'Chain 3+ merges in a row to score!'},
    'welcome_title': {AppLanguage.tr: 'Hoş geldin! 🎁', AppLanguage.en: 'Welcome! 🎁'},
    'welcome_body': {AppLanguage.tr: 'Yeni kasabana başlangıç hediyeni al:', AppLanguage.en: 'Grab your starter gift for your new town:'},
    'back_title': {AppLanguage.tr: 'Seni özledik! 🏘️', AppLanguage.en: 'We missed you! 🏘️'},
    'back_body': {AppLanguage.tr: 'Geri dönüş hediyen hazır:', AppLanguage.en: 'Your welcome-back gift is ready:'},
    'gift_claim': {AppLanguage.tr: 'Hediyeyi Al', AppLanguage.en: 'Claim Gift'},
    'gift_energy': {AppLanguage.tr: 'Tam enerji', AppLanguage.en: 'Full energy'},
    'kind_boss_toast': {AppLanguage.tr: '👑 BOSS BÖLÜM: zor siparişler, 2x ödül!', AppLanguage.en: '👑 BOSS CHAPTER: tough orders, 2x rewards!'},
    'kind_easy_toast': {AppLanguage.tr: '🌿 Rahat bölüm: nefes al!', AppLanguage.en: '🌿 Chill chapter: catch your breath!'},
    'wheel_title': {AppLanguage.tr: 'Şans Çarkı', AppLanguage.en: 'Lucky Wheel'},
    'wheel_free_spin': {AppLanguage.tr: 'BEDAVA ÇEVİR', AppLanguage.en: 'FREE SPIN'},
    'wheel_ad_spin': {AppLanguage.tr: 'Reklam İzle & Çevir', AppLanguage.en: 'Watch Ad & Spin'},
    'wheel_come_back': {AppLanguage.tr: 'Yarın tekrar gel', AppLanguage.en: 'Come back tomorrow'},
    'wheel_spinning': {AppLanguage.tr: 'Dönüyor...', AppLanguage.en: 'Spinning...'},
    'wheel_you_won': {AppLanguage.tr: 'Kazandın!', AppLanguage.en: 'You won!'},
    'wheel_big_win': {AppLanguage.tr: '🎉 BÜYÜK ÖDÜL! 🎉', AppLanguage.en: '🎉 BIG WIN! 🎉'},
    'wheel_streak': {AppLanguage.tr: 'Günlük seri', AppLanguage.en: 'Daily streak'},
    'wheel_streak_info': {
      AppLanguage.tr: 'Art arda 7 gün bedava çevir: 7. gün nadir ödül garanti!',
      AppLanguage.en: 'Spin free 7 days in a row: rare prize guaranteed on day 7!',
    },
    'wheel_streak_bonus': {AppLanguage.tr: '7 günlük seri ödülü! 🔥', AppLanguage.en: '7-day streak prize! 🔥'},
    'wheel_odds': {AppLanguage.tr: 'Düşme oranları', AppLanguage.en: 'Prize odds'},
    'wheel_pirate_bonus': {
      AppLanguage.tr: '🏴‍☠️ Korsan Limanı bonusu coin ödüllerine de uygulanır.',
      AppLanguage.en: '🏴‍☠️ Pirate Harbor bonus also applies to coin prizes.',
    },
    // ── Kasaba (meta ilerleme) ──
    'town_title': {AppLanguage.tr: 'Kasaba', AppLanguage.en: 'Town'},
    'town_level': {AppLanguage.tr: 'Kasaba Seviyesi', AppLanguage.en: 'Town Level'},
    'town_next_reward': {AppLanguage.tr: 'Sıradaki ödül', AppLanguage.en: 'Next reward'},
    'town_all_done': {AppLanguage.tr: 'Tüm ödüller alındı! 🎉', AppLanguage.en: 'All rewards claimed! 🎉'},
    'town_need_stars': {AppLanguage.tr: 'Bu dünyada daha fazla ⭐ topla', AppLanguage.en: 'Earn more ⭐ in this world'},
    'town_need_coins': {AppLanguage.tr: 'Yeterli coin yok', AppLanguage.en: 'Not enough coins'},
    'town_max': {AppLanguage.tr: 'MAKS', AppLanguage.en: 'MAX'},
    'town_upgraded': {AppLanguage.tr: 'Yükseltildi!', AppLanguage.en: 'Upgraded!'},
    'town_perk_now': {AppLanguage.tr: 'Şu an', AppLanguage.en: 'Now'},
    'town_perk_next': {AppLanguage.tr: 'Sonraki', AppLanguage.en: 'Next'},
    'town_milestone_reward': {AppLanguage.tr: 'Kilometre taşı ödülü!', AppLanguage.en: 'Milestone reward!'},
    'town_ok': {AppLanguage.tr: 'Harika!', AppLanguage.en: 'Awesome!'},
    'town_rank_0': {AppLanguage.tr: 'Küçük Köy', AppLanguage.en: 'Little Village'},
    'town_rank_1': {AppLanguage.tr: 'Şirin Kasaba', AppLanguage.en: 'Cozy Town'},
    'town_rank_2': {AppLanguage.tr: 'Parlayan Şehir', AppLanguage.en: 'Shining City'},
    'town_rank_3': {AppLanguage.tr: 'Büyük Metropol', AppLanguage.en: 'Grand Metropolis'},
    'town_rank_4': {AppLanguage.tr: 'Dünyaların Başkenti', AppLanguage.en: 'Capital of Worlds'},
    'town_rank_5': {AppLanguage.tr: 'Efsane Diyar', AppLanguage.en: 'Legendary Realm'},
    'town_b0': {AppLanguage.tr: 'Lezzet Durağı', AppLanguage.en: 'Flavor Plaza'},
    'town_b1': {AppLanguage.tr: 'Şirin Kafe', AppLanguage.en: 'Cozy Café'},
    'town_b2': {AppLanguage.tr: 'Simya Kulesi', AppLanguage.en: 'Alchemy Tower'},
    'town_b3': {AppLanguage.tr: 'Korsan Limanı', AppLanguage.en: 'Pirate Harbor'},
    'town_b4': {AppLanguage.tr: 'Buz Sarayı', AppLanguage.en: 'Ice Palace'},
    'town_b5': {AppLanguage.tr: 'Uzay İstasyonu', AppLanguage.en: 'Space Station'},
    // ── Koleksiyon albümü ──
    'album_title': {AppLanguage.tr: 'Koleksiyon', AppLanguage.en: 'Collection'},
    'album_total': {AppLanguage.tr: 'Toplam keşfedilen', AppLanguage.en: 'Total discovered'},
    'album_set_reward': {AppLanguage.tr: 'Set ödülü', AppLanguage.en: 'Set reward'},
    'album_all_reward': {AppLanguage.tr: 'Tüm albüm ödülü', AppLanguage.en: 'Full album reward'},
    'album_new_toast': {AppLanguage.tr: 'Yeni keşif:', AppLanguage.en: 'New discovery:'},
    'album_locked_hint': {AppLanguage.tr: 'Bu objeyi üretince açılır', AppLanguage.en: 'Unlocks when you make this item'},

    // ── Mücevher + güçlendiriciler ──
    'gem_shop_title': {AppLanguage.tr: 'Mağaza', AppLanguage.en: 'Shop'},
    'gem_shop_open': {AppLanguage.tr: 'Mağaza', AppLanguage.en: 'Shop'},
    'gem_shop_free': {AppLanguage.tr: 'Ücretsiz Mücevher', AppLanguage.en: 'Free Gems'},
    'gem_shop_watch_ad': {AppLanguage.tr: 'Reklam izle', AppLanguage.en: 'Watch ad'},
    'gem_shop_packs': {AppLanguage.tr: 'Mücevher Paketleri', AppLanguage.en: 'Gem Packs'},
    'gem_shop_energy': {AppLanguage.tr: 'Enerji', AppLanguage.en: 'Energy'},
    'gem_shop_boosters': {AppLanguage.tr: 'Güçlendiriciler', AppLanguage.en: 'Boosters'},
    'gem_shop_best': {AppLanguage.tr: 'EN İYİ', AppLanguage.en: 'BEST'},
    'energy_refill_gems': {AppLanguage.tr: 'ile doldur', AppLanguage.en: 'refill'},
    'not_enough_gems_title': {AppLanguage.tr: 'Yetersiz mücevher', AppLanguage.en: 'Not enough gems'},
    'not_enough_gems_body': {
      AppLanguage.tr: 'Bunun için yeterli mücevherin yok. Mağazadan mücevher alabilirsin.',
      AppLanguage.en: "You don't have enough gems for this. You can get more in the shop.",
    },
    'starter_pack_title': {AppLanguage.tr: 'Başlangıç Paketi', AppLanguage.en: 'Starter Pack'},
    'starter_pack_desc': {
      AppLanguage.tr: '150 💎 + her güçlendiriciden 3 adet (tek seferlik)',
      AppLanguage.en: '150 💎 + 3 of each booster (one-time)',
    },
    'iap_unavailable': {
      AppLanguage.tr: 'Satın alma şu an kullanılamıyor. Biraz sonra tekrar dene.',
      AppLanguage.en: 'Purchases are unavailable right now. Please try again later.',
    },
    'iap_pending': {
      AppLanguage.tr: 'Ödemen onay bekliyor. Onaylanınca ürün otomatik eklenecek.',
      AppLanguage.en: 'Your payment is pending. The item will be added automatically once approved.',
    },
    'booster_owned': {AppLanguage.tr: 'Elinde', AppLanguage.en: 'Owned'},
    'booster_aim_name': {AppLanguage.tr: 'Nişan Rehberi', AppLanguage.en: 'Aim Guide'},
    'booster_aim_desc': {
      AppLanguage.tr: 'Sonraki 5 atışta topun nereye çarpacağını gösterir',
      AppLanguage.en: 'Shows where the ball will hit for the next 5 shots',
    },
    'booster_joker_name': {AppLanguage.tr: 'Joker Top', AppLanguage.en: 'Joker Ball'},
    'booster_joker_desc': {
      AppLanguage.tr: 'Sıradaki topun seviyesini sen seç (1-5)',
      AppLanguage.en: 'Pick the level of your next ball (1-5)',
    },
    'booster_revive_name': {AppLanguage.tr: 'Devam Et', AppLanguage.en: 'Continue'},
    'booster_revive_desc': {
      AppLanguage.tr: 'Masa dolunca alt bölgeyi temizleyip kaldığın yerden devam et',
      AppLanguage.en: 'When the table is full, clear the bottom area and keep playing',
    },
    'booster_buy_title': {AppLanguage.tr: 'Satın al', AppLanguage.en: 'Buy'},
    'booster_aim_active': {AppLanguage.tr: 'Nişan rehberi açık', AppLanguage.en: 'Aim guide is on'},
    'booster_joker_pick': {AppLanguage.tr: 'Joker: seviye seç', AppLanguage.en: 'Joker: pick a level'},
    'booster_continue_btn': {AppLanguage.tr: 'Devam Et', AppLanguage.en: 'Continue'},
  };
}
