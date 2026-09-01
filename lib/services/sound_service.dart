import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Oyun genelindeki arka plan muzigini ve kisa ses efektlerini yoneten
/// servis. Efektler icin `AudioPool` kullanilir: her efekt kendine ait
/// kucuk bir player havuzuna sahiptir, boylece ayni efekt ust uste/hizli
/// tetiklendiginde onceki calan sesi kesmez ya da kaybolmaz. Kaynaklar
/// `init()` sirasinda arka planda onceden yuklenir; bir efekt henuz
/// hazir degilse ilk tetiklendiginde anlik olarak olusturulur.
class SoundService extends ChangeNotifier {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const _musicPrefsKey = 'cs_music_enabled_v1';
  static const _sfxPrefsKey = 'cs_sfx_enabled_v1';

  /// Arka plan muzigi acik mi. Profil ekranindaki "Muzigi Kapat" anahtari
  /// bunu kontrol eder ve SharedPreferences'a kalici olarak kaydedilir.
  bool musicEnabled = true;

  /// Kisa ses efektleri (tap/pour/win vb.) acik mi. Profil ekranindaki
  /// "Ses Efektlerini Kapat" anahtari bunu kontrol eder.
  bool sfxEnabled = true;

  /// Geriye donuk uyumluluk icin: eski `enabled` alanini okuyan/yazan kod
  /// varsa hem muzigi hem efektleri birden acar/kapatir.
  bool get enabled => musicEnabled || sfxEnabled;
  set enabled(bool value) {
    musicEnabled = value;
    sfxEnabled = value;
  }

  /// Her efekt anahtarinin, assets/audio/sfx/ altindaki .mp3 dosya adina
  /// karsilik gelen yolu.
  static const Map<String, String> _sfxAssets = {
    'tap': 'audio/sfx/tap.mp3',
    'select': 'audio/sfx/select.mp3',
    'pour': 'audio/sfx/pour.mp3',
    'warp': 'audio/sfx/warp.mp3',
    'land': 'audio/sfx/land.mp3',
    'invalid': 'audio/sfx/invalid.mp3',
    'undo': 'audio/sfx/undo.mp3',
    'button': 'audio/sfx/button.mp3',
    'orbit_rotate': 'audio/sfx/orbit_rotate.mp3',
    'orbit_deliver': 'audio/sfx/orbit_deliver.mp3',
    'orbit_dock': 'audio/sfx/orbit_dock.mp3',
    'reward': 'audio/sfx/reward.mp3',
    'win': 'audio/sfx/win.mp3',
    'starwin': 'audio/sfx/starwin.mp3',
    'levelup': 'audio/sfx/levelup.mp3',
    // DUZELTME (yeni VFX icin ses): 'ufo_flyby' tamamen sentetik olarak
    // (kod ile, dalga formu uretilerek) hazirlandi - hazir bir ses
    // kutuphanesinden alinmadi. 'flame_rise' artik kullanilmiyor (bkz.
    // asagidaki _flamePlayer / setFlameLevel - combo mesale sesi artik
    // seviyeye gore hacmi degisen SUREKLI bir loop, tek seferlik bir
    // AudioPool efekti degil).
    'firework_pop': 'audio/sfx/firework_pop.mp3',
    'ufo_flyby': 'audio/sfx/ufo_flyby.mp3',
  };

  /// Her efekt icin ayri, kucuk bir player havuzu.
  final Map<String, AudioPool> _sfxPools = {};
  bool _audioContextConfigured = false;

  /// Odak istemeyen (audioFocus: none / mixWithOthers) paylasilan ses
  /// baglami. Bu, muzik calarken efektlerin, efekt calarken de muzigin
  /// asla kesilmemesini saglar. Hem bgm player'ina hem her efekt havuzuna
  /// olusturuldugu anda ayrica uygulanir (global ayar, ONCEDEN olusmus
  /// player'lara geriye donuk etki etmez).
  static final AudioContext _noFocusContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      // `music` + `game`: sesi telefonun medya (STREAM_MUSIC) seviyesine
      // baglar, odak talep etmeden (audioFocus: none) digerleriyle karisir.
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      // ONEMLI: `mixWithOthers` secenegi SADECE `playback`, `playAndRecord`
      // veya `multiRoute` kategorileriyle birlikte kullanilabilir
      // (audioplayers bunu bir assert ile zorunlu kilar). `ambient`
      // kategorisiyle birlikte kullanmak bu assert'i tetikler ve ilgili
      // AudioPool/AudioPlayer'in kurulmasini BASTAN basarisiz kilar.
      category: AVAudioSessionCategory.playback,
      options: const {
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
  );

  /// Uygulama baslarken cagrilir. Once tercihler (SharedPreferences) hizla
  /// okunur; ses baglami ayari ve efekt havuzunun onceden yuklenmesi
  /// (native ses eklentisiyle konusan adimlar) beklenmeden arka planda
  /// (fire-and-forget) baslatilir, boylece acilis bloklanmaz.
  Future<void> init() async {
    await _loadPrefs();
    unawaited(_configureAudioContext());
    unawaited(_preloadSfxPlayers());
  }

  Future<void> _configureAudioContext() async {
    if (_audioContextConfigured) return;
    _audioContextConfigured = true;
    try {
      // _bgmPlayer, SoundService.instance ilk erisildiginde (bu metod
      // cagrilmadan ONCE) zaten olusturulmus olabilir; bu yuzden baglami
      // ona ayrica burada uyguluyoruz.
      await _bgmPlayer.setAudioContext(_noFocusContext);
    } catch (_) {}
  }

  /// [key] icin, ONCEDEN YUKLENMIS bir `AudioPool` olusturup `_sfxPools`
  /// icine kaydeder ve geri dondurur.
  Future<AudioPool> _createSfxPool(String key, String asset) async {
    final existing = _sfxPools[key];
    if (existing != null) return existing;
    final pool = await AudioPool.create(
      source: AssetSource(asset),
      // Ayni efekt (orn. hizli "tap" dokunuslari) ust uste/aninda tekrar
      // tetiklenebilir; havuzda birden fazla player olmasi, bir onceki
      // sesin kesilmeden/kaybolmadan yenisinin baslamasini saglar.
      minPlayers: 1,
      maxPlayers: 2,
      playerMode: PlayerMode.mediaPlayer,
      audioContext: _noFocusContext,
    );
    _sfxPools[key] = pool;
    return pool;
  }

  Future<void> _preloadSfxPlayers() async {
    await Future.wait(
      _sfxAssets.entries.map((entry) async {
        try {
          await _createSfxPool(entry.key, entry.value);
        } catch (_) {
          // Bir efektin onceden yuklenmesi basarisiz olsa bile digerlerini
          // etkilemesin; o efekt yine de ilk tetiklendiginde yuklenmeye
          // calisilir (bkz. _playAsset).
        }
      }),
    );
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      musicEnabled = prefs.getBool(_musicPrefsKey) ?? true;
      sfxEnabled = prefs.getBool(_sfxPrefsKey) ?? true;
      notifyListeners();
    } catch (_) {
      // Tercihler okunamazsa varsayilan (acik) ile devam et.
    }
  }

  /// Profil ekranindaki anahtardan cagrilir: muzigi anlik olarak
  /// acar/kapatir ve tercihi kalici olarak kaydeder.
  Future<void> setMusicEnabled(bool value) async {
    if (musicEnabled == value) return;
    musicEnabled = value;
    notifyListeners();
    if (!value) {
      try {
        await _bgmPlayer.pause();
      } catch (_) {}
    } else if (_currentBgmAsset != null) {
      // Muzik kapaliyken playBgm() gercekten calmayi baslatmamis olabilir
      // (sadece hangi parca istendigini hatirlamistik); bu yuzden resume()
      // yerine dogrudan asset'i bastan calmayi deniyoruz. Eger zaten
      // (pause edilmis olarak) yuklenmisse bu bir sorun yaratmaz.
      final asset = _currentBgmAsset!;
      _currentBgmAsset = null;
      await playBgm(asset);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_musicPrefsKey, value);
    } catch (_) {}
  }

  /// Profil ekranindaki anahtardan cagrilir: ses efektlerini acar/kapatir
  /// ve tercihi kalici olarak kaydeder.
  Future<void> setSfxEnabled(bool value) async {
    if (sfxEnabled == value) return;
    sfxEnabled = value;
    notifyListeners();
    if (!value) {
      // Efektler kapatilirsa, o an calmakta olan surekli mesale loop'unu
      // da durdur (aksi halde sfxEnabled=false olsa bile arka planda
      // calmaya devam ederdi, cunku loop AudioPool degil ayri bir player).
      unawaited(stopFlameLoop());
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sfxPrefsKey, value);
    } catch (_) {}
  }

  // --- Arka plan muzigi (bgm) --------------------------------------------
  final AudioPlayer _bgmPlayer = AudioPlayer()
    ..setReleaseMode(ReleaseMode.loop);
  String? _currentBgmAsset;
  // Uygulama arka plana atildiginda/ekran kapandiginda muzigi pause
  // ediyoruz; bu bayrak sadece o an gercekten calmakta olan bir bgm
  // varsa true olur, boylece on plana donunce SADECE gercekten calmis
  // olani devam ettiririz (hicbir sey calmiyorken yanlislikla baslatmayiz).
  bool _bgmWasPlayingBeforePause = false;

  // --- Combo mesale (torch) ateşi loop'u -----------------------------
  // DUZELTME: mesale alevi artik combo degerine gore SUREKLI/KADEMELI
  // yanan-sonen gorsel bir efekt (bkz. OrbitBoard._flameLevelController,
  // 0..1 seviye). Buna karsilik gelen ses de tek seferlik bir "whoosh"
  // (eski 'flame_rise' AudioPool efekti) DEGIL, gorsel seviyeyle birebir
  // hacmi degisen SUREKLI bir loop (flame_loop.mp3, ~48sn kesintisiz
  // ates sesi) olmali - aksi halde her combo artisinda ust uste yeni bir
  // uzun kayit baslatilir ve sesler cirkin sekilde ust uste biner.
  final AudioPlayer _flamePlayer = AudioPlayer()
    ..setReleaseMode(ReleaseMode.loop);
  bool _flameLoopPlaying = false;
  double _flameTargetLevel = 0.0;

  /// [level] 0..1 araliginda mevcut combo/alev seviyesi (bkz.
  /// OrbitBoard._flameLevelController.value). 0'a yakinken loop
  /// durur/duraklar, ilk kez 0'in ustune ciktiginda loop bastan baslar,
  /// zaten calarken sadece hacmi guncellenir (bastan sarmadan) — boylece
  /// combo dalgalanirken ses kesintisiz/dogal kalir.
  Future<void> setFlameLevel(double level) async {
    final clamped = level.clamp(0.0, 1.0).toDouble();
    _flameTargetLevel = clamped;
    if (!sfxEnabled) return;
    try {
      if (clamped <= 0.02) {
        if (_flameLoopPlaying) {
          _flameLoopPlaying = false;
          await _flamePlayer.pause();
        }
        return;
      }
      if (!_flameLoopPlaying) {
        _flameLoopPlaying = true;
        await _flamePlayer.setAudioContext(_noFocusContext);
        await _flamePlayer.setVolume(clamped);
        // Duraklatilmisti/hic baslamamisti: resume genelde isi gorur,
        // ama hic calinmamissa resume no-op olabilir, o yuzden play ile
        // garanti altina aliyoruz.
        await _flamePlayer.play(
          AssetSource('audio/sfx/flame_loop.mp3'),
          volume: clamped,
        );
      } else {
        await _flamePlayer.setVolume(clamped);
      }
    } catch (_) {
      // Loop baslatilamazsa/hacim ayarlanamazsa oyunu asla bozmasin.
    }
  }

  /// Orbit ekranindan cikilirken (dispose) cagrilir: mesale loop'u hala
  /// caliyorsa tamamen durdurur (aksi halde bir sonraki ekranda arka
  /// planda calmaya devam ederdi).
  Future<void> stopFlameLoop() async {
    _flameTargetLevel = 0.0;
    _flameLoopPlaying = false;
    try {
      await _flamePlayer.stop();
    } catch (_) {}
  }

  /// Verilen asset'i (orn. "audio/where_the_gravity_bends.mp3") bastan
  /// sonsuz dongude calmaya baslar. Zaten calan track ile ayniysa hicbir
  /// sey yapmaz (baska bir ekrandan geri donuldugunde muzik yeniden
  /// basa sarmasin diye).
  Future<void> playBgm(String asset) async {
    if (!musicEnabled) {
      // Muzik kapaliyken de hangi parcanin "sirada" oldugunu hatirlariz;
      // kullanici profil ekranindan muzigi tekrar acarsa dogru parca
      // otomatik baslasin diye.
      _currentBgmAsset = asset;
      return;
    }
    if (_currentBgmAsset == asset) return;
    _currentBgmAsset = asset;
    try {
      await _bgmPlayer.stop();
      await _bgmPlayer.setVolume(0.35);
      await _bgmPlayer.play(AssetSource(asset));
    } catch (_) {
      // Muzik dosyasi calinamazsa oyunu asla bozmasin diye sessizce yut.
    }
  }

  Future<void> stopBgm() async {
    _currentBgmAsset = null;
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  /// Uygulama arka plana gittiginde (ekran kapandiginda, baska bir
  /// uygulamaya gecildiginde vb.) cagrilir: bir parca gercekten
  /// caliyorsa durdurur ve bunu hatirlar.
  Future<void> pauseBgm() async {
    if (_currentBgmAsset == null) return;
    _bgmWasPlayingBeforePause = true;
    try {
      await _bgmPlayer.pause();
    } catch (_) {}
  }

  /// Uygulama tekrar on plana geldiginde (ekran acildiginda) cagrilir:
  /// pauseBgm() ile durdurulmus bir parca varsa kaldigi yerden devam
  /// ettirir.
  Future<void> resumeBgm() async {
    if (!musicEnabled) return;
    if (!_bgmWasPlayingBeforePause || _currentBgmAsset == null) return;
    _bgmWasPlayingBeforePause = false;
    try {
      await _bgmPlayer.resume();
    } catch (_) {}
  }

  // --- Ses efektleri (sfx) ------------------------------------------------

  Future<void> _playAsset(String key) async {
    if (!sfxEnabled) return;
    final asset = _sfxAssets[key];
    if (asset == null) return;
    try {
      // Havuz henuz (arka planda) hazirlanmadiysa, bu efekti simdi, anlik
      // olarak olustur/yukle; boylece uygulama acilir acilmaz gelen ilk
      // dokunuslarda bile ses kaybolmaz.
      final pool = _sfxPools[key] ?? await _createSfxPool(key, asset);
      await pool.start();
    } catch (e) {
      // Release modda kullaniciya gozukmez, sadece `adb logcat`da gorulur;
      // efekt calinamadiginda oyunun sessizce devam etmesi icin.
      debugPrint('[SoundService] SFX "$key" calinamadi: $e');
      // Son care yedek yol: havuz herhangi bir sebeple kurulamadiysa veya
      // calistirilamadiysa, oyunun tamamen sessiz kalmasindansa tek
      // seferlik basit bir AudioPlayer ile dogrudan calmayi dener.
      try {
        final fallback = AudioPlayer()..setAudioContext(_noFocusContext);
        await fallback.play(AssetSource(asset));
        unawaited(
          fallback.onPlayerComplete.first.then((_) => fallback.dispose()),
        );
      } catch (e2) {
        debugPrint('[SoundService] SFX "$key" yedek yol da basarisiz: $e2');
      }
    }
  }

  // --- Genel efektler ---------------------------------------------------

  /// "Sifir Yercekimi" ters cevirme efekti.
  void warpFlip() => _playAsset('warp');

  void land() => _playAsset('land');

  void invalid() => _playAsset('invalid');

  void undo() => _playAsset('undo');

  void buttonTap() => _playAsset('button');

  // --- Yorunge Vardiyasi (Orbit Jam) efektleri --------------------------

  /// Bir halka basariyla dondugunde calinan kisa, yumusak "tik" sesi.
  void orbitRotate() => _playAsset('orbit_rotate');

  /// Kapiya gelen gezegen o anki hedefle eslesip teslim edildiginde
  /// calinan, tatmin edici kisa yukselen ikili nota.
  void orbitDeliver() => _playAsset('orbit_deliver');

  /// Kapiya gelen gezegen hedefle eslesmeyip rihtima (dock) konuldugunda
  /// calinan, daha notr/yumusak bir "yerlesme" sesi.
  void orbitDock() => _playAsset('orbit_dock');

  void reward() => _playAsset('reward');

  void win() => _playAsset('win');

  void starWin() => _playAsset('starwin');

  void levelUp() => _playAsset('levelup');

  // --- Yeni VFX sesleri (havai fisek / uzayli gecisi) --------------------
  // (Combo mesale sesi artik yukaridaki setFlameLevel/stopFlameLoop ile
  // yonetiliyor, tek seferlik bir metod degil.)

  /// Bolum sonu kutlamasindaki her havai fisek patlamasinda calinan
  /// "pop + sparkle" sesi.
  void fireworkPop() => _playAsset('firework_pop');

  /// Bolum sonu kutlamasinda ekrandan gecen her uzayli gemisi icin
  /// calinan sci-fi "whoosh" gecis sesi.
  void ufoFlyby() => _playAsset('ufo_flyby');
}
