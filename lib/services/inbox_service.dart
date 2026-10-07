import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/app_strings.dart';
import '../models/game_progress.dart';

/// Gelen kutusundaki tek mesaj (admin panelinden gonderilir). Hediyesiz mesajda
/// tum odul alanlari 0'dir.
class InboxMessage {
  final String id;
  final String title;
  final String body;
  final int gems;
  final int coins;
  final int energy; // 1 = enerji dolsun
  final int aim;
  final int joker;
  final int revive;
  final int createdAt; // ms
  final int expiresAt; // ms
  bool read;
  bool claimed;

  InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.gems,
    required this.coins,
    required this.energy,
    required this.aim,
    required this.joker,
    required this.revive,
    required this.createdAt,
    required this.expiresAt,
    required this.read,
    required this.claimed,
  });

  bool get hasGift => gems > 0 || coins > 0 || energy > 0 || aim > 0 || joker > 0 || revive > 0;

  factory InboxMessage.fromJson(Map<String, dynamic> j) {
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return InboxMessage(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      gems: i('gems'),
      coins: i('coins'),
      energy: i('energy'),
      aim: i('aim'),
      joker: i('joker'),
      revive: i('revive'),
      createdAt: i('createdAt'),
      expiresAt: i('expiresAt'),
      read: j['read'] == true,
      claimed: j['claimed'] == true,
    );
  }
}

/// Arkadas davet kademesi (1/3/5/10/15/25 arkadas).
class InviteTier {
  final int count;
  final int gems;
  final bool reached;
  bool claimed;
  InviteTier({required this.count, required this.gems, required this.reached, required this.claimed});
}

/// Sunucuda bekleyen (henuz onaylanmamis) davet odulu.
class InviteReward {
  final String id;
  final String kind; // 'tier' | 'invitee_bonus'
  final int tier;
  final int gems;
  const InviteReward({required this.id, required this.kind, required this.tier, required this.gems});
}

class InboxException implements Exception {
  final String code;
  final int status;
  const InboxException(this.code, this.status);
  @override
  String toString() => 'InboxException($code, $status)';
}

/// GELEN KUTUSU + ARKADAS DAVET istemcisi (Cloudflare Worker: merge-davet).
///
/// - Ilk senkronda sunucuya kayit olur; kimlik (playerId + token) SharedPreferences'ta
///   'invite_v1' anahtarinda saklanir ve bulut kaydina (save_merge.dart) dahildir,
///   boylece yeniden kurulumda ayni kimlik / davet kodu geri gelir.
/// - Oduller (davet + mesaj hediyeleri) ONCE oyuna yerel olarak verilir, "islendi"
///   listesine yazilir, SONRA sunucuya onaylanir (ack). Ag kesilirse onay sonraki
///   senkronda tekrar denenir; islendi listesi sayesinde odul iki kez verilmez.
/// - Worker adresi girilmemisse ([isConfigured] false) servis hic ag istegi yapmaz.
class InboxService extends ChangeNotifier {
  InboxService._();
  static final InboxService instance = InboxService._();

  /// TODO: `npx wrangler deploy` sonrasi verilen adresi buraya yaz (sonunda '/' olmasin).
  static const String baseUrl = 'https://merge-davet.HESAP.workers.dev';
  static bool get isConfigured => !baseUrl.contains('HESAP');

  static const String storeKey = 'invite_v1';
  // Bu cihazin push token'inin sunucuya hangi kimlikle gonderildigi ("playerId|token"). Cihaza ozeldir,
  // bulut kaydina GIRMEZ (yeniden kurulumda token degisir, kimlik ayni kalir -> tekrar gonderilir).
  static const String _pushSentKey = 'invite_push_sent';
  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _okInterval = Duration(minutes: 3);
  static const Duration _failInterval = Duration(minutes: 1);
  static const int _maxProcessed = 300;

  static const MethodChannel _shareChannel = MethodChannel('merge_dunyalari/share');

  /// Sunucuya hic ulasilamadiginda gosterilen varsayilan kademeler (worker TIERS ile ayni).
  static const List<List<int>> defaultTiers = [
    [1, 50],
    [3, 100],
    [5, 150],
    [10, 500],
    [15, 750],
    [25, 1500],
  ];

  // ---- kimlik (diske yazilir) ----
  String? _playerId;
  String? _token;
  String? inviteCode; // "ABCD-EFGH"
  int _createdAt = 0;
  final List<String> _processed = <String>[]; // odulu yerelde verilmis id'ler (sirali)

  // ---- sunucu durumu (bellek) ----
  List<InboxMessage> messages = <InboxMessage>[];
  List<InviteTier> tiers = <InviteTier>[];
  List<InviteReward> pendingRewards = <InviteReward>[];
  int inviteCount = 0;
  int qualifyLevel = 7;
  int inviteeBonus = 50;
  int maxInvites = 25;
  bool canRedeem = false;
  bool redeemed = false;
  bool qualified = false; // davet edilen olarak hedef seviyeye ulasti (sunucu onayladi)
  bool syncing = false;
  bool loadedOnce = false; // en az bir basarili senkron oldu
  String? lastError;

  DateTime _nextAllowed = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _registering;
  String? _pushToken; // FCM cihaz token'i (PushService verir)
  bool _pushSending = false;
  // Yerelde verilmis ama sunucuya onaylanamamis davet odulleri (sonraki senkronda tekrar onaylanir).
  final List<String> _rewardAckQueue = <String>[];
  final List<String> _msgAckQueue = <String>[];

  // ------------------------------------------------------------ gostergeler

  int get unreadCount => messages.where((m) => !m.read).length;
  int get claimableMessages => messages.where((m) => m.hasGift && !m.claimed).length;

  InviteReward? get inviteeBonusReward {
    for (final r in pendingRewards) {
      if (r.kind == 'invitee_bonus') return r;
    }
    return null;
  }

  InviteReward? rewardForTier(int count) {
    for (final r in pendingRewards) {
      if (r.kind == 'tier' && r.tier == count) return r;
    }
    return null;
  }

  int get claimableInvites => pendingRewards.length;

  bool get hasMessagesBadge => unreadCount > 0 || claimableMessages > 0;
  bool get hasInviteBadge => claimableInvites > 0;
  bool get hasBadge => hasMessagesBadge || hasInviteBadge;

  String get inviteLink => inviteCode == null ? baseUrl : '$baseUrl/i/$inviteCode';

  // ------------------------------------------------------------ kalicilik

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storeKey);
      _playerId = null;
      _token = null;
      inviteCode = null;
      _createdAt = 0;
      _processed.clear();
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map) {
          _playerId = j['playerId'] as String?;
          _token = j['token'] as String?;
          inviteCode = j['inviteCode'] as String?;
          _createdAt = (j['createdAt'] as num?)?.toInt() ?? 0;
          final p = j['processed'];
          if (p is List) _processed.addAll(p.whereType<String>());
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Bulut kaydi baska bir kimlik getirdiyse: bellekteki eski durumu at, yeniden yukle, esitle.
  Future<void> reloadAfterCloudRestore() async {
    messages = <InboxMessage>[];
    tiers = <InviteTier>[];
    pendingRewards = <InviteReward>[];
    inviteCount = 0;
    qualified = false;
    loadedOnce = false;
    await load();
    _nextAllowed = DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(sync());
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storeKey,
        jsonEncode({
          'playerId': _playerId,
          'token': _token,
          'inviteCode': inviteCode,
          'createdAt': _createdAt,
          'processed': _processed,
        }),
      );
    } catch (_) {}
  }

  void _remember(String id) {
    if (_processed.contains(id)) return;
    _processed.add(id);
    if (_processed.length > _maxProcessed) {
      _processed.removeRange(0, _processed.length - _maxProcessed);
    }
  }

  // ------------------------------------------------------------ ag

  Future<Map<String, dynamic>> _call(String method, String path, {Object? body, bool auth = true}) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.openUrl(method, Uri.parse('$baseUrl$path')).timeout(_timeout);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (auth && _token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (method == 'POST') req.add(utf8.encode(jsonEncode(body ?? <String, dynamic>{})));
      final res = await req.close().timeout(_timeout);
      final text = await res.transform(utf8.decoder).join().timeout(_timeout);
      Map<String, dynamic> data = <String, dynamic>{};
      try {
        final d = jsonDecode(text);
        if (d is Map) data = Map<String, dynamic>.from(d);
      } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) return data;
      throw InboxException((data['error'] as String?) ?? 'http_${res.statusCode}', res.statusCode);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _ensureIdentity() {
    if (_playerId != null && _token != null) return Future<void>.value();
    return _registering ??= _register().whenComplete(() => _registering = null);
  }

  Future<void> _register() async {
    final r = await _call('POST', '/v1/register', auth: false);
    final id = r['playerId'] as String?;
    final tok = r['token'] as String?;
    if (id == null || tok == null) throw const InboxException('bad_response', 0);
    _playerId = id;
    _token = tok;
    inviteCode = r['inviteCode'] as String?;
    _createdAt = DateTime.now().millisecondsSinceEpoch;
    await save();
    GameProgress.onSaved?.call(); // kimligi bulut kaydina da yaz
  }

  int get _myLevel => GameProgress.instance.playerLevel.clamp(1, 200).toInt();

  // ------------------------------------------------------------ senkron

  /// Seviyeyi bildirir, davet durumunu ve gelen kutusunu yeniler (tek istek: POST /v1/sync).
  /// [force] false ise (menu zamanlayicisi vb.) en cok 3 dk'da bir calisir.
  Future<void> sync({bool force = false}) async {
    if (!isConfigured || syncing) return;
    final now = DateTime.now();
    if (!force && now.isBefore(_nextAllowed)) return;
    syncing = true;
    notifyListeners();
    var ok = false;
    try {
      try {
        await _syncOnce();
      } on InboxException catch (e) {
        if (e.status != 401) rethrow;
        // Token sunucuda yok (veritabani sifirlandi vb.): yeni kimlik al, bir kez daha dene.
        _playerId = null;
        _token = null;
        inviteCode = null;
        await save();
        await _syncOnce();
      }
      ok = true;
      lastError = null;
      loadedOnce = true;
    } on InboxException catch (e) {
      lastError = e.code;
    } catch (_) {
      lastError = 'network';
    } finally {
      syncing = false;
      _nextAllowed = DateTime.now().add(ok ? _okInterval : _failInterval);
      notifyListeners();
    }
  }

  /// Uygulama acilisinda / arka plandan donuste cagrilir; en cok 3 dk'da bir ag istegi yapar.
  /// (Periyodik zamanlayici YOK: baska tetikleyiciler [onPlayerLevelUp], push bildirimi ve gelen
  /// kutusu ekraninin kendi yenilemesidir.)
  void maybeSync() {
    if (!isConfigured || syncing) return;
    if (DateTime.now().isBefore(_nextAllowed)) return;
    unawaited(sync());
  }

  Future<void> _syncOnce() async {
    await _ensureIdentity();
    await _sendPushTokenIfNeeded();
    try {
      // TEK ISTEK: seviye bildirimi + davet durumu + gelen kutusu (worker: POST /v1/sync).
      final r = await _call('POST', '/v1/sync', body: {'level': _myLevel});
      final st = r['status'];
      final ib = r['inbox'];
      if (st is! Map || ib is! Map) throw const InboxException('bad_response', 0);
      _applyStatus(Map<String, dynamic>.from(st));
      _applyInbox(Map<String, dynamic>.from(ib));
    } on InboxException catch (e) {
      // Worker henuz guncellenmediyse (eski surum /v1/sync'i bilmez): eski 3 istekli yola dus.
      if (e.status != 404 || e.code != 'not_found') rethrow;
      await _call('POST', '/v1/progress', body: {'level': _myLevel});
      _applyStatus(await _call('GET', '/v1/status'));
      _applyInbox(await _call('GET', '/v1/inbox'));
    }
    unawaited(_retryAcks());
  }

  void _applyStatus(Map<String, dynamic> st) {
    int i(dynamic v) => v is num ? v.toInt() : 0;
    inviteCode = st['inviteCode'] as String? ?? inviteCode;
    canRedeem = st['canRedeem'] == true;
    redeemed = st['redeemed'] == true;
    qualified = st['qualified'] == true;
    inviteCount = i(st['count']);
    final cfg = st['config'];
    if (cfg is Map) {
      qualifyLevel = i(cfg['qualifyLevel']) > 0 ? i(cfg['qualifyLevel']) : qualifyLevel;
      inviteeBonus = i(cfg['inviteeBonus']) > 0 ? i(cfg['inviteeBonus']) : inviteeBonus;
      maxInvites = i(cfg['maxInvites']) > 0 ? i(cfg['maxInvites']) : maxInvites;
    }
    final t = st['tiers'];
    tiers = <InviteTier>[
      if (t is List)
        for (final x in t)
          if (x is Map)
            InviteTier(
              count: i(x['count']),
              gems: i(x['gems']),
              reached: x['reached'] == true,
              claimed: x['claimed'] == true,
            ),
    ];
    final r = st['rewards'];
    pendingRewards = <InviteReward>[
      if (r is List)
        for (final x in r)
          if (x is Map && x['id'] is String)
            InviteReward(
              id: x['id'] as String,
              kind: x['kind'] as String? ?? 'tier',
              tier: i(x['tier']),
              gems: i(x['gems']),
            ),
    ];
    // Yerelde zaten verilmis ama sunucuya onaylanamamis oduller: alinmis say.
    for (final tier in tiers) {
      final pr = rewardForTier(tier.count);
      if (pr != null && _processed.contains(pr.id)) tier.claimed = true;
    }
    for (final x in pendingRewards) {
      if (_processed.contains(x.id) && !_rewardAckQueue.contains(x.id)) _rewardAckQueue.add(x.id);
    }
    pendingRewards = pendingRewards.where((x) => !_processed.contains(x.id)).toList();
  }

  void _applyInbox(Map<String, dynamic> ib) {
    final list = ib['messages'];
    final out = <InboxMessage>[];
    if (list is List) {
      for (final x in list) {
        if (x is Map) {
          final m = InboxMessage.fromJson(Map<String, dynamic>.from(x));
          if (m.id.isEmpty) continue;
          if (m.hasGift && !m.claimed && _processed.contains(m.id)) {
            m.claimed = true; // yerelde verilmis, sunucu henuz bilmiyor
            if (!_msgAckQueue.contains(m.id)) _msgAckQueue.add(m.id);
          }
          out.add(m);
        }
      }
    }
    messages = out;
  }

  /// Yerelde verilip sunucuya onaylanamamis odulleri / mesajlari tekrar onaylar.
  Future<void> _retryAcks() async {
    try {
      if (_msgAckQueue.isNotEmpty) {
        await _call('POST', '/v1/inbox/ack', body: {'ids': List<String>.of(_msgAckQueue)});
        _msgAckQueue.clear();
      }
      if (_rewardAckQueue.isNotEmpty) {
        await _call('POST', '/v1/ack', body: {'ids': List<String>.of(_rewardAckQueue)});
        _rewardAckQueue.clear();
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------ push + seviye tetikleyicisi

  /// PushService, FCM cihaz token'ini (ilk kez ya da yenilenince) verir. Sunucuya yalnizca token
  /// degistiyse gonderilir; kimlik henuz yoksa ilk senkron kaydeder.
  Future<void> setPushToken(String token) async {
    if (token.isEmpty || token == _pushToken) return;
    _pushToken = token;
    if (isConfigured && _playerId != null) await _sendPushTokenIfNeeded();
  }

  Future<void> _sendPushTokenIfNeeded() async {
    final t = _pushToken;
    final id = _playerId;
    if (t == null || id == null || _token == null || _pushSending) return;
    _pushSending = true;
    try {
      final stamp = '$id|$t';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_pushSentKey) == stamp) return;
      await _call('POST', '/v1/push-token', body: {'token': t});
      await prefs.setString(_pushSentKey, stamp);
    } catch (_) {
      // Bir sonraki senkronda tekrar denenir; push yuzunden senkron bozulmaz.
    } finally {
      _pushSending = false;
    }
  }

  /// Oyuncu seviye atlayinca (GameProgress.onLevelUp) cagrilir. Sunucuya yalnizca DAVET EDILEN oyuncu
  /// hedef seviyeye (7) ulastiginda ve henuz onaylanmadiysa istek atar; baska durumda ag istegi yok.
  /// Kayittan 90 dk dolmadan 7'ye ulasirsa sunucu onaylamaz; sonraki seviye atlamasi ya da
  /// uygulama acilisi tekrar dener.
  void onPlayerLevelUp() {
    if (!isConfigured || _myLevel < qualifyLevel) return;
    // Durum bilinmiyorsa (ilk senkron olmadi) yine de bir kez sor; biliniyorsa sadece davet
    // edilmis + henuz onaylanmamis oyuncu icin.
    if (loadedOnce && (!redeemed || qualified)) return;
    // Mikro gorev: seviye atlama, bir cizim/yerlesim sirasinda tetiklenmis olsa bile dinleyiciler guvenle guncellenir.
    Future<void>.microtask(() => unawaited(sync(force: true)));
  }

  // ------------------------------------------------------------ eylemler

  Future<void> markRead(InboxMessage m) async {
    if (m.read) return;
    m.read = true;
    notifyListeners();
    try {
      await _call('POST', '/v1/inbox/read', body: {'ids': [m.id]});
    } catch (_) {}
  }

  /// Mesaj hediyesini oyuna verir ve sunucuya onaylar.
  Future<void> claimMessage(InboxMessage m) async {
    if (!m.hasGift || m.claimed) return;
    if (!_processed.contains(m.id)) {
      final gp = GameProgress.instance;
      gp.grantReward(
        coins: m.coins,
        gems: m.gems,
        energy: m.energy > 0,
        booster: m.aim > 0 ? BoosterType.aimGuide : null,
        boosterAmount: m.aim > 0 ? m.aim : 1,
      );
      if (m.joker > 0) gp.grantReward(booster: BoosterType.joker, boosterAmount: m.joker);
      if (m.revive > 0) gp.grantReward(booster: BoosterType.revive, boosterAmount: m.revive);
      _remember(m.id);
      await save();
      GameProgress.onSaved?.call();
    }
    m.claimed = true;
    m.read = true;
    notifyListeners();
    try {
      await _call('POST', '/v1/inbox/ack', body: {'ids': [m.id]});
    } catch (_) {} // sonraki senkronda tekrar denenir
  }

  /// Davet odulunu (kademe ya da davet bonusu) oyuna verir ve sunucuya onaylar.
  Future<void> claimReward(InviteReward r) async {
    if (!_processed.contains(r.id)) {
      GameProgress.instance.grantReward(gems: r.gems);
      _remember(r.id);
      await save();
      GameProgress.onSaved?.call();
    }
    pendingRewards = pendingRewards.where((x) => x.id != r.id).toList();
    for (final t in tiers) {
      if (r.kind == 'tier' && t.count == r.tier) t.claimed = true;
    }
    notifyListeners();
    try {
      await _call('POST', '/v1/ack', body: {'ids': [r.id]});
    } catch (_) {}
  }

  /// Arkadasin davet kodunu girer. null = basarili, aksi halde hata kodu.
  Future<String?> redeem(String code) async {
    if (!isConfigured) return 'network';
    try {
      await _ensureIdentity();
      await _call('POST', '/v1/redeem', body: {'code': code, 'level': _myLevel});
      await sync(force: true);
      return null;
    } on InboxException catch (e) {
      return e.code;
    } catch (_) {
      return 'network';
    }
  }

  // ------------------------------------------------------------ paylasim

  String shareText() {
    final tr = AppStrings.instance.language == AppLanguage.tr;
    final code = inviteCode ?? '';
    if (tr) {
      return 'Hadi, benimle Merge Dünyaları oyna! Davet kodum $code. '
          'Bu bağlantıyı kullan, $qualifyLevel. seviyeye ulaşınca $inviteeBonus💎 hediye kazan: $inviteLink';
    }
    return 'Come play World Merge with me! My invite code is $code. '
        'Use this link and get $inviteeBonus💎 when you reach level $qualifyLevel: $inviteLink';
  }

  /// Android paylasim menusunu acar. Acilamazsa metni panoya kopyalar ve false doner.
  Future<bool> shareInvite() async {
    final text = shareText();
    try {
      await _shareChannel.invokeMethod<void>('shareText', <String, dynamic>{'text': text});
      return true;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      return false;
    }
  }

  Future<void> copyCode() async {
    final c = inviteCode;
    if (c == null) return;
    await Clipboard.setData(ClipboardData(text: c));
  }
}
