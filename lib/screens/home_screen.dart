import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/economy_config.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/cloud_progress_sync.dart';
import '../services/gdpr_service.dart';
import '../services/legal_links.dart';
import '../services/localization.dart';
import '../services/play_games_service.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';
import '../widgets/consent_dialog.dart';
import '../widgets/custom_toast.dart';
import '../widgets/daily_result_dialog.dart';
import '../widgets/meteor_icon.dart';
import '../widgets/weekly_reward_strip.dart';
import 'cosmic_room_screen.dart';
import 'legal_webview_screen.dart';
import 'orbit_game_screen.dart';
import 'stages_map_screen.dart';
import 'supply_shop_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerProgress _progress = PlayerProgress.instance;
  final AppLocale _locale = AppLocale.instance;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgressChanged);
    _locale.addListener(_onProgressChanged);
    // Ikmal geri sayimini ve gunluk kartini canli tutmak icin periyodik
    // yenileme (yeni bir olay olmasa bile).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Dil secimi tamamlandiktan hemen sonra (veya bu ekrana her donuste,
    // henuz onaylanmadiysa) Kullanim Sartlari + GDPR onay popup'ini goster.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runLaunchPopups());
    // Ana ekran muzigi: basa sardirilarak sonsuz dongude calar.
    SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
  }

  /// Açılışta sırayla gösterilecek popup'ları yönetir: önce Kullanım
  /// Şartları/GDPR onayı (varsa), o kapandıktan SONRA — bugünün haftalık
  /// ödülü henüz alınmadıysa — haftalık ödül takvimi popup'ı. Bu metot
  /// sadece initState'ten (bir kere, uygulama açılışında) çağrılır; ekran
  /// içindeki başka bir yerden tekrar tetiklenmez.
  Future<void> _runLaunchPopups() async {
    await _maybeShowConsent();
    if (!mounted) return;
    if (!_progress.weeklyRewardIsTodayClaimed()) {
      await WeeklyRewardStrip.showPopup(context);
    }
  }

  Future<void> _maybeShowConsent() async {
    if (!mounted) return;
    if (!GdprService.instance.loaded) {
      await GdprService.instance.load();
    }
    if (!mounted) return;
    if (GdprService.instance.needsConsentPrompt) {
      await ConsentDialog.show(context);
    }
  }

  void _onProgressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _progress.removeListener(_onProgressChanged);
    _locale.removeListener(_onProgressChanged);
    SoundService.instance.stopBgm();
    super.dispose();
  }

  /// Bir bolum/gorev ekranindan (kinetic_overdrive calan) ana ekrana geri
  /// donulduginde menu muzigini yeniden baslatir (playBgm zaten ayni
  /// track'i tekrar tekrar baslatmaz, sadece degistiginde tepki verir).
  void _resumeMenuMusic() {
    SoundService.instance.playBgm('audio/where_the_gravity_bends.mp3');
  }

  Future<void> _openMap() async {
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StagesMapScreen()),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
    }
  }

  Future<void> _openCosmicRoom() async {
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CosmicRoomScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openShop() async {
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SupplyShopScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openDaily() async {
    SoundService.instance.buttonTap();
    if (_progress.dailyCompletedToday) {
      await showDialog(
        context: context,
        builder: (_) => const DailyResultDialog(isReplay: true),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrbitGameScreen(isDaily: true)),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
    }
  }

  Future<void> _claimResupply() async {
    if (!_progress.isResupplyReady) {
      unawaited(AnalyticsService.instance.logResupplyNotReady());
      CustomToast.show(
          context, '⏳ ${_progress.resupplyCountdownText()}',
          icon: '🛰️', accentColor: AppColors.accent);
      return;
    }
    SoundService.instance.buttonTap();
    final granted = await AdService.instance.showRewardedAdFlow(
      context,
      icon: '🎁',
      title: t('home_resupplyTitle'),
      subtitle: t('ad_defaultSubtitle'),
      placementId: 'resupply',
    );
    if (granted != true || !mounted) return;
    final reward = await _progress.grantResupplyReward(Random());
    if (!mounted) return;
    SoundService.instance.reward();
    final rewardText = switch (reward.kind) {
      ResupplyRewardKind.xp => t('resupply_rewardXp', {'n': '${reward.amount}'}),
      ResupplyRewardKind.orbitDockSlot =>
        t('resupply_rewardOrbitDockSlot', {'n': '${reward.amount}'}),
      // Meteor dilimi kazanıldığında taban miktar + bonus meteor tek
      // satırda toplu gösterilir (ör. "7 Meteor" = 5 taban + 2 bonus).
      ResupplyRewardKind.meteor => t('resupply_rewardMeteor',
          {'n': '${reward.amount + reward.bonusMeteors}'}),
    };
    // Meteor dışındaki her ödül türünde, üstüne eklenen rastgele bonus
    // meteor AYRI bir satırda gösterilir (ör. "100 XP" + "+3 Meteor").
    final showsSeparateBonus =
        reward.kind != ResupplyRewardKind.meteor && reward.bonusMeteors > 0;
    final rewardIcon = switch (reward.kind) {
      ResupplyRewardKind.xp => '✨',
      ResupplyRewardKind.orbitDockSlot => '⚓',
      ResupplyRewardKind.meteor => '☄️',
    };
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rewardIcon, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                t('resupply_rewardTitle'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.tubeGlass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.tubeGlassBorder),
                ),
                child: Text(
                  rewardText,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (showsSeparateBonus) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.35)),
                  ),
                  child: Text(
                    '☄️ ${t('resupply_bonusMeteor', {
                          'n': '${reward.bonusMeteors}'
                        })}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(t('resupply_close'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    showDialog(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: _locale,
        builder: (context, _) {
          final info = _progress.levelInfo();
          return Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.accent,
                backgroundImage: AssetImage('assets/icon/profile_icon.jpg'),
              ),
              const SizedBox(height: 14),
              // --- Seviye ilerleme cubugu (HTML'deki level-progress-track/fill) ---
              Row(
                children: [
                  Text('🎖️ ${t('profile_level')} ${info.level}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const Spacer(),
                  Text('${info.xpIntoLevel} / ${info.xpForNext} XP',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 10,
                  child: Stack(
                    children: [
                      Container(color: AppColors.surfaceBorder),
                      FractionallySizedBox(
                        widthFactor: info.progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.accentSoft,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tubeGlass,
                  border: Border.all(color: AppColors.tubeGlassBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _profileStat('⭐', '${_progress.totalStars}',
                        t('profile_totalStars')),
                    _profileStat('🏆', '${_progress.orbitStageStats.length}',
                        t('profile_stagesCleared')),
                    _profileStat('💯', '${_progress.totalScore}',
                        t('profile_totalScore')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // --- Dil secici (TR / EN / RU) ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_language'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _langButton(ctx, AppLanguage.tr, '🇹🇷 TR'),
                  const SizedBox(width: 8),
                  _langButton(ctx, AppLanguage.en, '🇬🇧 EN'),
                  const SizedBox(width: 8),
                  _langButton(ctx, AppLanguage.ru, '🇷🇺 RU'),
                ],
              ),
              const SizedBox(height: 16),
              // --- Ses ayarlari: muzik / efekt anahtarlari ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_soundSettings'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: SoundService.instance,
                builder: (context, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.tubeGlass,
                      border: Border.all(color: AppColors.tubeGlassBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('profile_musicLabel'),
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                            ),
                            Switch(
                              value: SoundService.instance.musicEnabled,
                              activeThumbColor: AppColors.success,
                              onChanged: (val) {
                                SoundService.instance.setMusicEnabled(val);
                              },
                            ),
                          ],
                        ),
                        const Divider(
                            height: 1, color: AppColors.tubeGlassBorder),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('profile_sfxLabel'),
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                            ),
                            Switch(
                              value: SoundService.instance.sfxEnabled,
                              activeThumbColor: AppColors.success,
                              onChanged: (val) {
                                SoundService.instance.setSfxEnabled(val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // --- Play Games baglantisi (sadece giris + ilerleme kaydi) ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_playGames'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              StatefulBuilder(
                builder: (ctx2, setDialogState) {
                  final connected = PlayGamesService.instance.isSignedIn;
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: connected
                          ? null
                          : () async {
                              final ok =
                                  await PlayGamesService.instance.signIn();
                              if (ok) {
                                await CloudProgressSync.instance
                                    .syncAfterSignIn();
                              }
                              setDialogState(() {});
                              if (!ok && ctx2.mounted) {
                                CustomToast.show(
                                    ctx2, t('profile_playGamesFailed'),
                                    icon: '⚠️', accentColor: AppColors.danger);
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            connected ? AppColors.success : AppColors.textPrimary,
                        side: BorderSide(
                          color: connected
                              ? AppColors.success
                              : AppColors.tubeGlassBorder,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        connected
                            ? t('profile_playGamesConnected')
                            : t('profile_playGamesConnect'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              // --- Skor tablosu (Play Games'in kendi Gunluk/Haftalik/
              //     Tum-zamanlar ekrani; ayrica bir custom UI gerektirmez) ---
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => PlayGamesService.instance.showLeaderboard(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.tubeGlassBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(t('profile_leaderboard')),
                ),
              ),
              const SizedBox(height: 16),
              // --- Gizlilik Politikasi & Kullanim Sartlari (in-app) ---
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('profile_legal'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.tubeGlassBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        SoundService.instance.buttonTap();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalWebViewScreen(
                              url: LegalLinks.privacyPolicyUrl,
                              title: t('legal_privacyPolicy'),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        t('legal_privacyPolicy'),
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.tubeGlassBorder),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        SoundService.instance.buttonTap();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalWebViewScreen(
                              url: LegalLinks.termsUrl,
                              title: t('legal_terms'),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        t('legal_terms'),
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              // --- Reklam rizasini yonetme (Appodeal'in KENDI resmi
              // Google UMP tabanli onay formunu tekrar acar) — artik AB
              // bolgesine gore manuel gizlenmiyor, herkese gosteriliyor;
              // Appodeal formu gerekli degilse zaten kendi icinde no-op
              // davranir. ---
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tubeGlass,
                  border: Border.all(color: AppColors.tubeGlassBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('profile_gdprSettingLabel'),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('profile_gdprSettingHint'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.accentSoft),
                          foregroundColor: AppColors.accentSoft,
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          SoundService.instance.buttonTap();
                          GdprService.instance.openAdConsentForm();
                        },
                        child: Text(
                          t('profile_gdprManageButton'),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t('profile_close'),
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ],
            ),
          ),
        ),
      );
        },
      ),
    );
  }

  Widget _langButton(BuildContext ctx, AppLanguage lang, String label) {
    final active = _locale.language == lang;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          SoundService.instance.buttonTap();
          _locale.setLanguage(lang);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.tubeGlass,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.tubeGlassBorder,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileStat(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
        Text(label,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _progress.levelInfo();

    return Scaffold(
      body: CosmicThemes.buildActive(
        _progress,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(info),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildResupplyDock(),
                          _buildTasksDock(),
                          _buildMapDock(),
                        ],
                      ),
                      const Expanded(
                        child: Center(child: _FloatingStation()),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildShopDock(),
                          _buildCosmicRoomDock(),
                          _buildDailyDock(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LevelInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          const Spacer(),
          MeteorBadge(amount: _progress.meteors),
          const SizedBox(width: 8),
          _headerBadge('🎖️ ${info.level}'),
          const SizedBox(width: 8),
          _headerBadge('⭐ ${_progress.totalStars}'),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              SoundService.instance.buttonTap();
              PlayGamesService.instance.showLeaderboard();
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.tubeGlassBorder),
              ),
              child: const Text('🏆', style: TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openProfile,
            child: const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.accent,
              child: Icon(Icons.person_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tubeGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.tubeGlassBorder),
      ),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }

  // =====================================================================
  // Ana ekran v3: eski dikdörtgen kartlar yerine, ekranın sol/sağ
  // kenarlarına dizilmiş küçük yuvarlak "dock" ikonları + ortada asılı
  // duran Kozmik İstasyon. Kartların altında duran ikon görselleri
  // (UFO/kargo gemisi) AYNEN korunuyor, sadece boyutu küçültülüp daire
  // içine alındı — durum metinleri (ör. "Hazır! (1/3)") kaldırıldı,
  // dokununca açılan ekranda/diyalogda zaten görünüyor. Merkezdeki
  // istasyon SABİT bir dekor; oyuncunun Kozmik Oda'dan seçtiği tema
  // (bkz. CosmicThemes.buildActive, tüm ekranı zaten sarıyor) arka
  // planda değişerek "dönüşüm" hissini veriyor — bunun için ayrıca bir
  // bağlama gerekmiyor.
  // =====================================================================

  Widget _buildResupplyDock() {
    final ready = _progress.isResupplyReady;
    return _DockIcon(
      icon: _ResupplyPulseIcon(ready: ready),
      label: t('home_resupplyTitle'),
      badge: ready ? _dotBadge() : null,
      onTap: _claimResupply,
      onLongPress: _showResupplyOdds,
    );
  }

  Widget _buildTasksDock() {
    final weeklyReady = _progress.weeklyGoalReady;
    final monthlyReady = _progress.monthlyGoalReady;
    final constellationReady = _progress.constellationGoalReady;
    final readyCount = [weeklyReady, monthlyReady, constellationReady]
        .where((r) => r)
        .length;

    return _DockIcon(
      icon: _imageCircleIcon(
        'assets/fx/tasks_ship_card.png',
        background: const LinearGradient(
          colors: [Color(0xFF241947), Color(0xFF0F3D2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      label: t('home_tasksTitle'),
      badge: readyCount > 0 ? _countBadge('$readyCount') : null,
      onTap: _openTasks,
    );
  }

  Future<void> _openTasks() async {
    SoundService.instance.buttonTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TasksScreen()),
    );
    if (mounted) {
      _resumeMenuMusic();
      setState(() {});
    }
  }

  /// Kozmik Ikmal karti sagustundeki "i" butonundan acilan, odul
  /// reklaminin hangi ihtimallerle hangi odulu verdigini gosteren ozel
  /// (custom) popup. Sistem uyarisi/AlertDialog gibi degil, uygulamanin
  /// kendi cam/gradyan temasiyla uyumlu bir Dialog kullanir. Artik "i"
  /// butonu yok - ayni diyalog, ikmal ikonuna UZUN BASINCA aciliyor.
  void _showResupplyOdds() {
    SoundService.instance.buttonTap();
    final rows = <(double, String, String)>[
      (EconomyConfig.pMeteor10, '', t('resupply_rewardMeteor', {'n': '10'})),
      (EconomyConfig.pMeteor5, '', t('resupply_rewardMeteor', {'n': '5'})),
      (EconomyConfig.pMeteor3, '', t('resupply_rewardMeteor', {'n': '3'})),
      (EconomyConfig.pMeteor2, '', t('resupply_rewardMeteor', {'n': '2'})),
      (
        EconomyConfig.pXp,
        '💯',
        t('resupply_rewardXp', {'n': '${EconomyConfig.xpRewardAmount}'})
      ),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.surfaceBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t('resupply_oddsTitle'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t('resupply_oddsHint'),
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4),
              ),
              const SizedBox(height: 14),
              ...rows.map((row) {
                final percentText = t('resupply_oddsPercent',
                    {'p': (row.$1 * 100).toStringAsFixed(0)});
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.tubeGlass,
                      border: Border.all(color: AppColors.tubeGlassBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (row.$2.isNotEmpty) ...[
                          Text(row.$2, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                        ],
                        Text(percentText,
                            style: const TextStyle(
                                color: AppColors.accentSoft,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(row.$3,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    SoundService.instance.buttonTap();
                    Navigator.of(ctx).pop();
                  },
                  child: Text(t('resupply_oddsClose'),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapDock() {
    return _DockIcon(
      icon: _emojiCircleIcon(
        '🗺️',
        background: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF9333EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      label: t('home_mapCardTitle'),
      badge: _countBadge('${_progress.orbitUnlockedStage}',
          background: AppColors.surface, textColor: AppColors.accentSoft),
      onTap: _openMap,
    );
  }

  Widget _buildShopDock() {
    return _DockIcon(
      icon: _emojiCircleIcon('🧰'),
      label: t('home_shopCardTitle'),
      onTap: _openShop,
    );
  }

  Widget _buildCosmicRoomDock() {
    return _DockIcon(
      icon: _emojiCircleIcon('🛋️'),
      label: t('cosmicRoom_title'),
      onTap: _openCosmicRoom,
    );
  }

  Widget _buildDailyDock() {
    final completed = _progress.dailyCompletedToday;
    return _DockIcon(
      icon: _emojiCircleIcon(
        completed ? '✅' : '🌌',
        background: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      label: t('home_dailyTitle'),
      badge: _countBadge('🔥${_progress.dailyStreak}',
          background: AppColors.warning, textColor: const Color(0xFF3A2400)),
      onTap: _openDaily,
    );
  }

  /// Emoji tabanlı basit dock ikonu (Mağaza, Kozmik Oda, Harita, Günlük
  /// Sinyal). `background` verilmezse cam/panel (tubeGlass) rengiyle
  /// notr bir daire olur.
  Widget _emojiCircleIcon(String emoji, {Gradient? background}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: background,
        color: background == null ? AppColors.tubeGlass : null,
        border: Border.all(color: AppColors.tubeGlassBorder, width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 20)),
    );
  }

  /// Gerçek kart görselini (UFO/kargo gemisi PNG'si — DEĞİŞTİRİLMEDİ,
  /// sadece daire içine küçültüldü) kullanan dock ikonu — Kozmik İkmal
  /// ve Görevler için.
  Widget _imageCircleIcon(String asset, {required Gradient background}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: background,
        border: Border.all(color: AppColors.tubeGlassBorder, width: 1.4),
      ),
      padding: const EdgeInsets.all(7),
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }

  /// Küçük yeşil "hazır" noktası (Kozmik İkmal hazır olduğunda).
  Widget _dotBadge() => Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.spaceTop, width: 2),
        ),
      );

  /// Sayı/metin rozeti (Görevler'de kaç ödül hazır, Harita'da mevcut
  /// bölüm no, Günlük Sinyal'de seri sayısı).
  Widget _countBadge(String text,
      {Color background = AppColors.danger, Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.spaceTop, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: textColor, fontWeight: FontWeight.w800, fontSize: 9)),
    );
  }
}

/// Sol/sağ kenarlardaki tek bir "dock" ikonu: yuvarlak görsel + altında
/// tek satır isim + (varsa) sağ üst köşede küçük bir durum rozeti.
/// Kozmik İkmal, Görevler, Harita, Mağaza, Kozmik Oda ve Günlük Sinyal
/// hepsi bu ortak kalıbı kullanıyor; içerideki `icon` değişiyor.
class _DockIcon extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  const _DockIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: icon),
                if (badge != null) Positioned(top: -4, right: -4, child: badge!),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 66,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kozmik İkmal ikonunun İÇİ — uzaylı-gemisi görseli (resupply_ufo_card.png,
/// DEĞİŞTİRİLMEDİ) artık küçük bir daire içinde. Hazır olduğunda önceki
/// karttaki gibi çok hafif bir "kalp atışı" (ölçek nefes alma) ve yeşilimsi
/// bir parlama (glow) ile dikkat çeker; hazır değilken sakin durur.
/// Durum METNİ artık YOK (ör. "Hazır! (1/3)") — bu bilgi artık dokununca
/// açılan ödül akışında / uzun basınca açılan "ihtimaller" penceresinde
/// görünüyor, ikonun altında sadece "Kozmik İkmal" ismi kalıyor.
class _ResupplyPulseIcon extends StatefulWidget {
  final bool ready;

  const _ResupplyPulseIcon({required this.ready});

  @override
  State<_ResupplyPulseIcon> createState() => _ResupplyPulseIconState();
}

class _ResupplyPulseIconState extends State<_ResupplyPulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final wave = widget.ready ? sin(_pulse.value * pi) : 0.0;
        final scale = 1.0 + wave * 0.06;
        final glowAlpha = (0.18 + wave * 0.35).clamp(0.0, 1.0);

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0B1640), Color(0xFF1A3A7A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.tubeGlassBorder, width: 1.4),
              boxShadow: widget.ready
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7EE06A)
                            .withValues(alpha: glowAlpha),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(7),
            child: Opacity(
              opacity: widget.ready ? 1.0 : 0.75,
              child: Image.asset(
                'assets/fx/resupply_ufo_card.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ana ekranın merkezindeki, boşlukta asılı duran Kozmik İstasyon.
/// Kullanıcının gönderdiği referans görsele göre hazırlanmış istasyon
/// çizimi (assets/fx/cosmic_station.png, arka planı temizlenmiş) bir
/// parlama/zemin halkasının üzerinde oturuyor; ikisi birlikte çok hafif,
/// yumuşak bir sinüs hareketiyle sağa-sola / yukarı-aşağı süzülüyor —
/// amaç "uzayda asılı durma" hissini vermek, dikkat dağıtacak kadar
/// belirgin olmamak. İstasyonun kendisi SABİT bir dekor: temaya göre
/// değişmiyor. Görsel "dönüşüm" hissi, bu ekranı zaten saran
/// CosmicThemes.buildActive arka planından (bkz. HomeScreen.build)
/// geliyor — Kozmik Oda'dan yeni bir tema aktif edildiğinde otomatik
/// olarak burada da görünür.
class _FloatingStation extends StatefulWidget {
  const _FloatingStation();

  @override
  State<_FloatingStation> createState() => _FloatingStationState();
}

class _FloatingStationState extends State<_FloatingStation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    // 7 saniyelik yavaş, surekli bir dongu - "cok yumusak" istegine
    // uygun olsun diye genlik kucuk tutuldu (bkz. asagidaki dx/dy).
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ekranin en kisa kenarina oranli, SABIT bir aralikta kalan hedef
    // boyut - "orta halli" istegine uygun, onceki sabit 220px'den
    // kucultuldu. Ayrica LayoutBuilder ile gercekten ayrilan alanin
    // (sol/sag dock ikonlari arasinda kalan bosluk) genisligini de
    // hesaba katip onu asmiyoruz - dar telefonlarda tasma olmasin diye.
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final target = (shortestSide * 0.30).clamp(110.0, 175.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth - 24
            : target;
        final stationWidth = target < available ? target : available.clamp(70.0, target);
        final glowWidth = stationWidth * 0.86;
        final glowHeight = stationWidth * 0.19;

        return AnimatedBuilder(
          animation: _drift,
          builder: (context, child) {
            final t = _drift.value * 2 * pi;
            final dx = sin(t) * 6;
            final dy = cos(t * 0.8) * 5;
            return Transform.translate(offset: Offset(dx, dy), child: child);
          },
          child: SizedBox(
            width: stationWidth + 24,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                // Istasyonun altindaki asili "zemin" - gercek bir platform
                // gorseli yerine, yumusak bir isik halkasi ile temsil
                // ediliyor; boylece hangi tema aktif olursa olsun uyumlu
                // kalıyor.
                Container(
                  width: glowWidth,
                  height: glowHeight,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.32),
                        AppColors.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image.asset(
                    'assets/fx/cosmic_station.png',
                    fit: BoxFit.contain,
                    width: stationWidth,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
