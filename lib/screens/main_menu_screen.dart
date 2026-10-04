import 'dart:async';
import 'package:flutter/material.dart';
import '../models/game_progress.dart';
import '../models/game_theme.dart';
import '../localization/app_strings.dart';
import '../services/ad_service.dart';
import '../services/game_fx.dart';
import '../utils/duration_format.dart';
import 'level_map_screen.dart';
import 'missions_screen.dart';
import 'album_screen.dart';
import 'town_screen.dart';
import 'wheel_screen.dart';
import 'season_screen.dart';
import 'piggy_screen.dart';
import 'event_screen.dart';
import '../models/engage.dart';
import '../models/weekly_event.dart';
import '../models/piggy.dart';
import '../services/notification_service.dart';
import '../models/season.dart';
import '../models/town.dart';
import 'gem_shop_screen.dart';
import 'settings_screen.dart';
import 'upgrades_screen.dart';
import '../widgets/menu_fx.dart';
import '../widgets/ui_kit.dart';

/// ANA SAYFA: ustte coin / enerji / elmas ikonlari, yanlarda ikon seklinde
/// kisayollar (kumbara, kasaba, cark, sezon, etkinlik), altta ikon cubugu
/// (albüm, gorevler, HARITA, dukkan, menu). Gunluk odul acilista popup olarak
/// cikar. "Oyna" butonu yok: oyuna HARITA ikonundan girilir.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  // Enerji/reklam-kota geri sayimlarinin canli gorunmesi icin periyodik setState.
  Timer? _tickTimer;

  /// Gunluk odul popup'i oturum basina (uygulama acilisinda) bir kez; gun
  /// degisirse (gece yarisi) tekrar cikar.
  bool _dailyDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // Ilk bolum bitince (menuye donuldugunde) bildirim izni bir kez istenir.
    if (GameProgress.instance.maxUnlockedChapter >= 2) {
      Future.delayed(const Duration(seconds: 2), NotificationService.instance.requestPermissionOnce);
    }
    GameProgress.instance.refreshMissions();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeShowPopups();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPopups());
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  /// Acilis popup'lari: once hos geldin / geri donus hediyesi, sonra gunluk
  /// odul. Her biri kendi "acik mi" bayragini kontrol ettigi icin periyodik
  /// cagrilarda ust uste binmez.
  Future<void> _maybeShowPopups() async {
    await _maybeShowGift();
    await _maybeShowDaily();
  }

  bool _giftDialogOpen = false;

  /// Hos geldin / geri donus hediyesi bekliyorsa (menu ustte iken) gosterir.
  Future<void> _maybeShowGift() async {
    if (_giftDialogOpen || _dailyDialogOpen || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final eg = EngageService.instance;
    final bool welcome = eg.welcomePending;
    final int days = eg.pendingAwayDays;
    if (!welcome && days <= 0) return;
    _giftDialogOpen = true;
    final s = AppStrings.instance;
    final r = welcome ? EngageService.welcomeReward : EngageService.comebackReward(days);
    final parts = <String>[];
    if (r.coins > 0) parts.add('🪙 ${r.coins}');
    if (r.gems > 0) parts.add('💎 ${r.gems}');
    if (r.energy) parts.add('⚡ ${s.t('gift_energy')}');
    if (r.booster != null) parts.add('🎁 1');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GameAlertDialog(
        title: Text(s.t(welcome ? 'welcome_title' : 'back_title'), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t(welcome ? 'welcome_body' : 'back_body'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            for (final p in parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(p, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
          ],
        ),
        actions: [
          CandyButton(
            height: 52,
            fontSize: 18,
            label: s.t('gift_claim'),
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
    if (welcome) {
      eg.claimWelcome();
    } else {
      eg.claimComeback();
    }
    GameFx.instance.reward();
    _giftDialogOpen = false;
    if (mounted) setState(() {});
  }

  /// GUNLUK ODUL popup'i: 7 gunluk seri + buyuk hediye + "AL" butonu.
  /// Yalnizca butonla kapanir (disari dokunarak gecilemez).
  Future<void> _maybeShowDaily() async {
    if (_dailyDialogOpen || _giftDialogOpen || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final gp = GameProgress.instance;
    if (!gp.canClaimDailyReward) return;
    final eg = EngageService.instance;
    if (eg.welcomePending || eg.pendingAwayDays > 0) return;
    _dailyDialogOpen = true;
    final tr = AppStrings.instance.language == AppLanguage.tr;
    final streak = gp.dailyStreak % GameProgress.dailyRewardCoins.length;
    final amount = gp.nextDailyRewardAmount;
    final gemBonus = gp.nextDailyRewardGems;
    GameFx.instance.reward();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PanelFrame(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr ? 'Günlük Ödül' : 'Daily Reward',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF5D2E00)),
                ),
                Text(
                  tr ? 'Seri: ${streak + 1}/7. gün' : 'Streak: day ${streak + 1}/7',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF8A5A2B)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < GameProgress.dailyRewardCoins.length; i++)
                      Expanded(child: _DayChip(index: i, streak: streak)),
                  ],
                ),
                const SizedBox(height: 14),
                Bobbing(
                  amplitude: 6,
                  child: Image.asset('assets/images/ui/gift.webp', width: 110, height: 110),
                ),
                const SizedBox(height: 6),
                Text(
                  '+$amount 🪙${gemBonus > 0 ? '   +$gemBonus 💎' : ''}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF5D2E00)),
                ),
                const SizedBox(height: 16),
                CandyButton(
                  height: 60,
                  fontSize: 22,
                  pulse: true,
                  label: tr ? 'AL' : 'CLAIM',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _claimDailyReward();
    _dailyDialogOpen = false;
  }

  void _claimDailyReward() {
    final amount = GameProgress.instance.claimDailyReward();
    if (amount <= 0) return;
    GameFx.instance.reward();
    if (mounted) setState(() {});
  }

  Future<void> _push(Widget page) async {
    GameFx.instance.uiTap();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Future<void> _openMap() => _push(const LevelMapScreen());
  Future<void> _openMissions() => _push(const MissionsScreen());
  Future<void> _openAlbum() => _push(const AlbumScreen());
  Future<void> _openPiggy() => _push(const PiggyScreen());
  Future<void> _openSeason() => _push(const SeasonScreen());
  Future<void> _openWheel() => _push(const WheelScreen());
  Future<void> _openTown() => _push(const TownScreen());
  void _showLevelInfo() {
    GameFx.instance.uiTap();
    final gp = GameProgress.instance;
    final need = GameProgress.xpNeededForLevel(gp.playerLevel);
    final tr = AppStrings.instance.language == AppLanguage.tr;
    showDialog(
      context: context,
      builder: (ctx) => GameAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr ? 'Seviye ${gp.playerLevel}' : 'Level ${gp.playerLevel}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: gp.levelProgress, minHeight: 12),
            ),
            const SizedBox(height: 6),
            Text('${gp.playerXp} / $need XP', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              tr ? 'Bölümleri tamamlayarak XP kazan.' : 'Earn XP by completing chapters.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGemShop() => _push(const GemShopScreen());
  Future<void> _openUpgrades() => _push(const UpgradesScreen());
  Future<void> _openEvent() => _push(const EventScreen());
  Future<void> _openSettings() => _push(const SettingsScreen());

  /// Sol sutundaki "Bedava elmas" ikonu: rewarded reklam izle -> gunluk hakki varsa elmas ver.
  Future<void> _watchGemAd() async {
    final gp = GameProgress.instance;
    if (gp.adGemsRemaining <= 0) {
      GameFx.instance.uiTap();
      return;
    }
    GameFx.instance.uiTap();
    final watched = await watchRewardedAd(context);
    if (!watched || !mounted) return;
    final got = gp.claimAdGems();
    if (got > 0) {
      GameFx.instance.reward();
      setState(() {});
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('+$got 💎', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          duration: const Duration(milliseconds: 1600),
        ));
    }
  }

  Future<void> _watchEnergyAd() async {
    if (!GameProgress.instance.canWatchEnergyAd) return;
    final watched = await watchRewardedAd(context);
    if (!watched) return;
    GameProgress.instance.claimEnergyAdReward();
    GameFx.instance.reward();
    if (mounted) setState(() {});
  }

  /// Enerjiyi mucevherle doldur; mucevher yetmezse magazayi ac.
  Future<void> _gemRefillEnergy() async {
    final gp = GameProgress.instance;
    if (gp.energy >= GameProgress.maxEnergy) return;
    if (gp.refillEnergyWithGems()) {
      GameFx.instance.reward();
      if (mounted) setState(() {});
    } else {
      await _openGemShop();
    }
  }

  /// Enerji ikonuna dokununca: durum + reklamla / elmasla doldurma.
  void _openEnergyDialog() {
    GameFx.instance.uiTap();
    final gp = GameProgress.instance;
    final s = AppStrings.instance;
    final tr = s.language == AppLanguage.tr;
    final full = gp.energy >= GameProgress.maxEnergy;
    final next = gp.timeUntilNextEnergy;
    final cooldown = gp.energyAdCooldownRemaining;
    final canWatch = gp.canWatchEnergyAd;
    String adLabel;
    if (!full && canWatch) {
      adLabel = '${tr ? 'Reklam İzle' : 'Watch Ad'}  (${gp.energyAdWatchesRemaining}/${GameProgress.maxEnergyAdWatches})';
    } else if (!full && cooldown != null) {
      adLabel = formatCountdown(cooldown);
    } else {
      adLabel = tr ? 'Reklam İzle' : 'Watch Ad';
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        title: Text(tr ? 'Enerji' : 'Energy', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < GameProgress.maxEnergy; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Opacity(
                      opacity: i < gp.energy ? 1.0 : 0.3,
                      child: Image.asset('assets/images/ui/bolt.webp', width: 34, height: 34),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              full
                  ? s.t('energy_full')
                  : (next != null ? '${formatCountdown(next)} • +1' : s.t('energy_full')),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          if (!full)
            CandyButton(
              height: 50,
              fontSize: 16,
              style: CandyStyle.orange,
              label: adLabel,
              onTap: canWatch
                  ? () {
                      Navigator.of(ctx).pop();
                      _watchEnergyAd();
                    }
                  : null,
            ),
          if (!full)
            CandyButton(
              height: 50,
              fontSize: 16,
              style: CandyStyle.blue,
              label: '💎 ${GameProgress.energyRefillGemCost}  ${tr ? 'ile Doldur' : 'Refill'}',
              onTap: () {
                Navigator.of(ctx).pop();
                _gemRefillEnergy();
              },
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr ? 'Kapat' : 'Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = GameProgress.instance;
    progress.tickTownUpgrades(); // biten kasaba insaatlarini uygula
    final s = AppStrings.instance;
    final tr = s.language == AppLanguage.tr;
    final world = TownCatalog.worldOfChapter(progress.maxUnlockedChapter);
    final activeTheme = ChapterConfig.themeFor(progress.maxUnlockedChapter);
    final heroTier = activeTheme.byLevel(activeTheme.maxLevel);
    final townLevel = progress.townLevel(world);
    final townStage = townLevel <= 3 ? 1 : (townLevel <= 7 ? 2 : 3);
    final townImage = townLevel == 0 ? 'assets/images/town/ruin.webp' : 'assets/images/town/b${world}_s$townStage.webp';
    final energyFull = progress.energy >= GameProgress.maxEnergy;
    final nextEnergyIn = progress.timeUntilNextEnergy;
    final piggy = PiggyService.instance;
    final adLeft = progress.adGemsRemaining;
    final adCd = progress.adGemsCooldownRemaining;
    final adLabel = adLeft > 0
        ? (tr ? 'Bedava 💎 $adLeft/${GameProgress.adGemsPerWindow}' : 'Free 💎 $adLeft/${GameProgress.adGemsPerWindow}')
        : (adCd != null ? formatCountdown(adCd) : (tr ? 'Bedava 💎' : 'Free 💎'));

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: MenuBackground(world: world)),
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Ortada: ilerlenen dunyanin kahraman objesi (dokununca harita) ──
                Positioned.fill(
                  child: Align(
                    alignment: const Alignment(0, -0.12),
                    child: GestureDetector(
                      onTap: _openMap,
                      child: SizedBox(
                        width: 250,
                        height: 250,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(opacity: 0.45, child: const SunburstRays(size: 250)),
                            Positioned(
                              bottom: 30,
                              child: Container(
                                width: 110,
                                height: 16,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(60),
                                  color: Colors.black.withOpacity(0.22),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 14)],
                                ),
                              ),
                            ),
                            Bobbing(
                              amplitude: 8,
                              child: Image.asset(heroTier.imagePath, width: 150, height: 150),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Ust cubuk: COIN | ENERJI | ELMAS ──
                Positioned(
                  top: 8,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      // Sol ust: OYUNCU SEVIYESI (XP halkali rozet)
                      GestureDetector(
                        onTap: _showLevelInfo,
                        child: _LevelBadge(
                          level: progress.playerLevel,
                          progress: progress.levelProgress,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: _openUpgrades,
                          child: _TopPill(
                            icon: Image.asset('assets/images/coin_icon.webp', width: 24, height: 24),
                            value: '${progress.coins}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: _openEnergyDialog,
                          child: _TopPill(
                            icon: Image.asset('assets/images/ui/bolt.webp', width: 24, height: 24),
                            value: '${progress.energy}/${GameProgress.maxEnergy}',
                            sub: (!energyFull && nextEnergyIn != null) ? formatCountdown(nextEnergyIn) : null,
                            plus: !energyFull,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: _openGemShop,
                          child: _TopPill(
                            icon: Image.asset('assets/images/ui/gem.webp', width: 24, height: 24),
                            value: '${progress.gems}',
                            plus: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Sol sutun: Reklam izle (bedava elmas), Magaza, Ejderha kumbarasi, Kasaba ──
                Positioned(
                  left: 10,
                  top: 78,
                  child: Column(
                    children: [
                      _SideIcon(
                        image: 'assets/images/ui/gem.webp',
                        label: adLabel,
                        badge: adLeft > 0,
                        dim: adLeft <= 0,
                        corner: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3DBE4E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, size: 17, color: Colors.white),
                        ),
                        onTap: _watchGemAd,
                      ),
                      const SizedBox(height: 14),
                      _SideIcon(
                        image: 'assets/images/ui/nav_shop.webp',
                        label: tr ? 'Mağaza' : 'Store',
                        onTap: _openGemShop,
                      ),
                      const SizedBox(height: 14),
                      _SideIcon(
                        image: 'assets/images/ui/dragon_1.webp',
                        label: s.t('piggy_title'),
                        badge: piggy.canBreak,
                        onTap: _openPiggy,
                      ),
                      const SizedBox(height: 14),
                      _SideIcon(
                        image: townImage,
                        label: tr ? 'Kasaba' : 'Town',
                        badge: progress.hasTownUpgradeAvailable || progress.hasTownCollectable,
                        onTap: _openTown,
                      ),
                    ],
                  ),
                ),
                // ── Sag sutun: Cark, Sezon, Etkinlik ──
                Positioned(
                  right: 10,
                  top: 78,
                  child: Column(
                    children: [
                      _SideIcon(
                        image: 'assets/images/ui/wheel.webp',
                        label: s.t('wheel_title'),
                        badge: progress.hasWheelReady,
                        onTap: _openWheel,
                      ),
                      const SizedBox(height: 14),
                      _SideIcon(
                        image: 'assets/images/ui/ticket.webp',
                        label: s.t('season_title'),
                        badge: SeasonService.instance.hasClaimable,
                        onTap: _openSeason,
                      ),
                      const SizedBox(height: 14),
                      _SideIcon(
                        image: 'assets/images/ui/trophy.webp',
                        label: tr ? 'Etkinlik' : 'Event',
                        badge: WeeklyEvent.instance.hasClaimable,
                        onTap: _openEvent,
                      ),
                    ],
                  ),
                ),
                // ── Alt ikon cubugu ──
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: _BottomDock(
                    items: [
                      _DockItem(
                        image: 'assets/images/ui/nav_album.webp',
                        label: s.t('album_title'),
                        badge: progress.hasAlbumClaimable,
                        onTap: _openAlbum,
                      ),
                      _DockItem(
                        image: 'assets/images/ui/nav_missions.webp',
                        label: s.t('missions_title'),
                        onTap: _openMissions,
                      ),
                      _DockItem(
                        image: 'assets/images/ui/nav_map.webp',
                        label: tr ? 'Harita' : 'Map',
                        big: true,
                        onTap: _openMap,
                      ),
                      _DockItem(
                        image: 'assets/images/ui/nav_shop.webp',
                        label: tr ? 'Dükkan' : 'Shop',
                        onTap: _openUpgrades,
                      ),
                      _DockItem(
                        image: 'assets/images/ui/nav_settings.webp',
                        label: tr ? 'Menü' : 'Menu',
                        onTap: _openSettings,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sol ustteki oyuncu seviyesi rozeti: altin cerceveli mor rozet gorseli + XP ilerleme halkasi + seviye sayisi.
class _LevelBadge extends StatelessWidget {
  final int level;
  final double progress; // 0..1
  const _LevelBadge({required this.level, required this.progress});

  static const double _size = 60;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset('assets/images/ui/level_badge.webp', width: _size, height: _size, fit: BoxFit.contain),
          // XP halkasi: morun icinde, altin cerceveye degmeden
          SizedBox(
            width: _size * 0.66,
            height: _size * 0.66,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF9CF25B)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('LV',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFFFFE082), height: 1.0)),
                Text('$level',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))],
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ust cubuktaki ikonlu rozet (coin / enerji / elmas): kahverengi-altin zemin.
class _TopPill extends StatelessWidget {
  final Widget icon;
  final String value;
  final String? sub;
  final bool plus;
  const _TopPill({required this.icon, required this.value, this.sub, this.plus = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: SlicedBar(base: 'assets/images/ui/pill', capRatio: 0.65)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 5),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white, height: 1.0)),
                      if (sub != null)
                        Text(sub!,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: Color(0xFFFFE082), height: 1.1)),
                    ],
                  ),
                  if (plus) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.add_circle, size: 18, color: Color(0xFF9CF25B)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yan kisayol ikonu: resim + altinda konturlu yazi + bildirim noktasi.
class _SideIcon extends StatelessWidget {
  final String image;
  final String label;
  final bool badge;
  final VoidCallback onTap;
  final Widget? corner; // ikonun sag alt kosesinde kucuk rozet (ornegin reklam "oynat" isareti)
  final bool dim; // true: soluk (kullanilamaz) gorunum
  const _SideIcon({
    required this.image,
    required this.label,
    required this.onTap,
    this.badge = false,
    this.corner,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.25),
                    border: Border.all(color: Colors.white.withOpacity(0.55), width: 2),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Opacity(opacity: dim ? 0.45 : 1.0, child: Image.asset(image, fit: BoxFit.contain)),
                ),
                if (corner != null) Positioned(right: -3, bottom: -3, child: corner!),
                if (badge)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94F4F),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Text('!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, height: 1.0)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
                    Shadow(color: Colors.black, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gunluk odul popup'indaki tek gun kutusu.
class _DayChip extends StatelessWidget {
  final int index;
  final int streak;
  const _DayChip({required this.index, required this.streak});

  @override
  Widget build(BuildContext context) {
    final today = index == streak;
    final past = index < streak;
    final coins = GameProgress.dailyRewardCoins[index];
    final gems = GameProgress.dailyGemsForIndex(index);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: today ? Colors.amber.shade200 : (past ? Colors.green.shade100 : Colors.white.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: today ? Colors.amber.shade700 : Colors.brown.shade200, width: today ? 2.5 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF8A5A2B), height: 1.0)),
          const SizedBox(height: 3),
          past
              ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF2E9E2E))
              : Image.asset('assets/images/coin_icon.webp', width: 18, height: 18),
          const SizedBox(height: 2),
          Text('$coins', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF5D2E00), height: 1.0)),
          if (gems > 0)
            Text('+$gems', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.purple.shade600, height: 1.2)),
        ],
      ),
    );
  }
}

/// Alttaki etiketli ikon cubugu.
class _BottomDock extends StatelessWidget {
  final List<_DockItem> items;
  const _BottomDock({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.38),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.4),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [for (final it in items) Expanded(child: it)],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final String image;
  final String label;
  final VoidCallback onTap;
  final bool badge;
  final bool big;
  const _DockItem({
    required this.image,
    required this.label,
    required this.onTap,
    this.badge = false,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = big ? 78.0 : 54.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Harita (buyuk): arkasinda yesil isik halkasi
              if (big)
                Container(
                  width: size + 8,
                  height: size + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [const Color(0xFF9CF25B).withOpacity(0.55), const Color(0xFF9CF25B).withOpacity(0.0)],
                    ),
                  ),
                ),
              SizedBox(width: size, height: size, child: Image.asset(image, fit: BoxFit.contain)),
              if (badge)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1.0,
                shadows: [Shadow(color: Colors.black.withOpacity(0.7), blurRadius: 3)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
