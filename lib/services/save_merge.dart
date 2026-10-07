import 'dart:convert';
import 'dart:math' as math;

typedef Json = Map<String, dynamic>;
typedef Stores = Map<String, Json>;

/// IKI CIHAZ BIRLESTIRME MANTIGI (saf Dart, Flutter'a bagimli degil -> test edilebilir).
///
/// Eski sistem tum kaydi "hangi bolum ileride" diye karsilastirip TEK PARCA
/// uzerine yaziyordu: A cihazinda harcanan/kazanilan mucevher, B cihazindaki
/// eski kayitla ezilebiliyordu. Burada 3'lu birlestirme (three-way merge) var:
///
///   base  = bu cihazin bulutla son BASARILI esitlendigi hali
///   local = su anki yerel hal
///   cloud = bulutta duran hal
///
/// Alan turune gore kural:
///  - Para/sayac (coins, gems, booster, sezon puani...):  cloud + (local - base)
///    -> A'da 100 mucevher harcandi, B'de 50 kazanildi => ikisi de korunur.
///  - Yalnizca artan seviyeler (bolum, yukseltme, bina seviyesi): max
///  - Tek seferlik satin almalar / alinmis oduller: VEYA / birlesim (asla kapanmaz)
///  - Gunluk/haftalik/aylik gruplar: ayni donemse birlestir, degilse yeni donem kazanir
///  - Ses/muzik/titresim: cihaza ozel, hic senkronlanmaz
///  - Diger: son degistiren kazanir (base'e gore degisen taraf)
class SaveMerge {
  SaveMerge._();

  static const String kProgress = 'game_progress_v1';
  static const String kSeason = 'season_v1';
  static const String kPiggy = 'piggy_v1';
  static const String kEvents = 'events_v1';
  static const String kEngage = 'engage_v1';
  static const String kInvite = 'invite_v1';

  static const List<String> keys = [kProgress, kSeason, kPiggy, kEvents, kEngage, kInvite];
  static const List<String> otherKeys = [kSeason, kPiggy, kEvents, kEngage, kInvite];

  /// Toplamsal (delta ile birlestirilen) alanlar.
  static const Map<String, List<String>> additive = {
    kProgress: ['coins', 'gems', 'boosterAim', 'boosterJoker', 'boosterRevive'],
    kSeason: ['points'],
    kPiggy: ['gems'],
    kEvents: ['points'],
  };

  /// Cihaza ozel ayarlar: bulutla tasinmaz.
  static const List<String> deviceLocal = ['soundEnabled', 'musicEnabled', 'hapticsEnabled'];

  // ------------------------------------------------------------ yardimcilar

  static int _n(Map? m, String k) {
    final v = m?[k];
    return v is num ? v.toInt() : 0;
  }

  static DateTime? _d(dynamic v) => v is String ? DateTime.tryParse(v) : null;

  static List<dynamic> _list(dynamic v) => v is List ? v : const <dynamic>[];

  static int _at(List<dynamic> l, int i) {
    if (i >= l.length) return 0;
    final v = l[i];
    return v is num ? v.toInt() : 0;
  }

  static dynamic _elem(List<dynamic> l, int i) => i < l.length ? l[i] : 0;

  /// Sirasiz derin esitlik.
  static bool deepEq(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !deepEq(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!deepEq(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Toplamsal alan: base varsa cloud + (local - base); yoksa max (hicbir sey kaybolmaz).
  static int _add(Json? b, Json l, Json c, String k) {
    final lv = _n(l, k);
    final cv = _n(c, k);
    final r = b == null ? math.max(lv, cv) : cv + (lv - _n(b, k));
    return r < 0 ? 0 : r;
  }

  static List<dynamic> _union(dynamic a, dynamic b) {
    final s = <dynamic>{..._list(a), ..._list(b)};
    return s.toList();
  }

  static dynamic _scalar(dynamic a, dynamic b) {
    if (a is bool || b is bool) return a == true || b == true;
    if (a is num && b is num) return math.max(a, b);
    return b ?? a;
  }

  /// Tarihli grup: tarih ayniysa alanlar birlestirilir (VEYA / max); farkliysa
  /// daha yeni tarihli taraf komple kazanir.
  static void _dated(Json out, Set<String> handled, Json l, Json c, String dateKey, List<String> fields) {
    final all = <String>[dateKey, ...fields];
    handled.addAll(all);
    final ld = _d(l[dateKey]);
    final cd = _d(c[dateKey]);
    if (ld != null && cd != null && ld.isAtSameMomentAs(cd)) {
      out[dateKey] = c[dateKey];
      for (final f in fields) {
        if (l.containsKey(f) || c.containsKey(f)) out[f] = _scalar(l[f], c[f]);
      }
      return;
    }
    final localWins = ld != null && (cd == null || ld.isAfter(cd));
    final s = localWins ? l : c;
    for (final k in all) {
      if (s.containsKey(k)) out[k] = s[k];
    }
  }

  /// Son degistiren kazanir: base'e gore yerelde degisen grup yerelden, aksi halde buluttan.
  static void _lww(Json out, Set<String> handled, Json? b, Json l, Json c, List<String> ks) {
    handled.addAll(ks);
    final changed = b != null && ks.any((k) => !deepEq(b[k], l[k]));
    final s = changed ? l : c;
    for (final k in ks) {
      if (s.containsKey(k)) out[k] = s[k];
    }
  }

  // ------------------------------------------------------------ ana giris

  /// Tum depolari birlestirir. [base] null olabilir (bu cihaz hic esitlenmedi).
  static Stores all(Stores? base, Stores local, Stores cloud) {
    final out = <String, Json>{};
    for (final k in keys) {
      final Json? l = local[k];
      final Json? c = cloud[k];
      if (l == null && c == null) continue;
      if (c == null) {
        out[k] = l!;
        continue;
      }
      if (l == null) {
        out[k] = c;
        continue;
      }
      final Json? b = base?[k];
      switch (k) {
        case kProgress:
          out[k] = progress(b, l, c);
          break;
        case kSeason:
          out[k] = season(b, l, c);
          break;
        case kPiggy:
          out[k] = piggy(b, l, c);
          break;
        case kEvents:
          out[k] = events(b, l, c);
          break;
        case kInvite:
          out[k] = invite(b, l, c);
          break;
        default:
          out[k] = engage(b, l, c);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ ilerleme

  static Json progress(Json? b, Json l, Json c) {
    final out = <String, dynamic>{};
    final handled = <String>{};

    // Para / sayaclar: delta birlestirme.
    for (final k in additive[kProgress]!) {
      handled.add(k);
      if (l.containsKey(k) || c.containsKey(k)) out[k] = _add(b, l, c, k);
    }

    // Yalnizca artan seviyeler.
    for (final k in const [
      'maxUnlockedChapter',
      'throwCooldownLevel',
      'luckLevel',
      'extraOrderSlotLevel',
      'townMilestoneIdx',
      'builders',
    ]) {
      handled.add(k);
      if (l.containsKey(k) || c.containsKey(k)) out[k] = math.max(_n(l, k), _n(c, k));
    }

    // Sureli baslangic teklifi: iki cihazdan EN ERKEN baslangic gecerli (sure sifirlanmasin).
    handled.add('starterOfferStart');
    final ls = l['starterOfferStart'] as String?;
    final cs = c['starterOfferStart'] as String?;
    if (ls != null && cs != null) {
      out['starterOfferStart'] = ls.compareTo(cs) <= 0 ? ls : cs;
    } else if (ls != null || cs != null) {
      out['starterOfferStart'] = ls ?? cs;
    }

    // Tek seferlik satin almalar / tamamlanan oduller: asla geri kapanmaz.
    for (final k in const ['starterPackBought', 'albumCompleteClaimed']) {
      handled.add(k);
      if (l.containsKey(k) || c.containsKey(k)) out[k] = l[k] == true || c[k] == true;
    }
    for (final k in const ['albumDiscovered', 'albumClaimedSets', 'tutSeen']) {
      handled.add(k);
      if (l.containsKey(k) || c.containsKey(k)) out[k] = _union(l[k], c[k]);
    }

    // Bolum yildizlari: bolum bazinda max.
    handled.add('chapterStars');
    final lStars = l['chapterStars'];
    final cStars = c['chapterStars'];
    if (lStars is Map || cStars is Map) {
      final m = <String, dynamic>{};
      for (final src in [cStars, lStars]) {
        if (src is Map) {
          src.forEach((key, v) {
            final kk = '$key';
            final nv = v is num ? v.toInt() : 0;
            final old = m[kk] is int ? m[kk] as int : 0;
            m[kk] = math.max(old, nv);
          });
        }
      }
      out['chapterStars'] = m;
    }

    // Oyuncu seviyesi + XP: daha ileri olan taraf.
    handled.addAll(const ['playerLevel', 'playerXp']);
    final ll = _n(l, 'playerLevel');
    final cl = _n(c, 'playerLevel');
    final localHigher = ll > cl || (ll == cl && _n(l, 'playerXp') >= _n(c, 'playerXp'));
    final lv = localHigher ? l : c;
    if (lv.containsKey('playerLevel')) out['playerLevel'] = lv['playerLevel'];
    if (lv.containsKey('playerXp')) out['playerXp'] = lv['playerXp'];

    // Kasaba: bina seviyesi max; uretim/insaat verisi seviyesi yuksek taraftan,
    // esitse son degistirenden.
    handled.addAll(const ['townLevels', 'townStored', 'townLastMs', 'townUpgradeEnd']);
    final lt = _list(l['townLevels']);
    final ct = _list(c['townLevels']);
    final len = math.max(lt.length, ct.length);
    out['townLevels'] = List<dynamic>.generate(len, (i) => math.max(_at(lt, i), _at(ct, i)));
    for (final k in const ['townStored', 'townLastMs', 'townUpgradeEnd']) {
      final la = _list(l[k]);
      final ca = _list(c[k]);
      final ba = _list(b?[k]);
      out[k] = List<dynamic>.generate(len, (i) {
        final lvl = _at(lt, i);
        final cvl = _at(ct, i);
        if (lvl > cvl) return _elem(la, i);
        if (cvl > lvl) return _elem(ca, i);
        final localChanged = b != null && !deepEq(_elem(ba, i), _elem(la, i));
        return localChanged ? _elem(la, i) : _elem(ca, i);
      });
    }

    // Gunluk odul / gorevler / cark / reklam sayaclari: donem bazli.
    _dated(out, handled, l, c, 'lastDailyRewardClaim', const ['dailyStreak']);
    _dated(out, handled, l, c, 'missionsResetDate', const [
      'missionDeliverProgress',
      'missionMergeProgress',
      'missionCoinsProgress',
      'missionDeliverClaimed',
      'missionMergeClaimed',
      'missionCoinsClaimed',
    ]);
    _dated(out, handled, l, c, 'weeklyMissionsResetDate', const [
      'missionWeeklyDeliverProgress',
      'missionWeeklyMergeProgress',
      'missionWeeklyCoinsProgress',
      'missionWeeklyDeliverClaimed',
      'missionWeeklyMergeClaimed',
      'missionWeeklyCoinsClaimed',
    ]);
    _dated(out, handled, l, c, 'monthlyMissionsResetDate', const [
      'missionMonthlyDeliverProgress',
      'missionMonthlyMergeProgress',
      'missionMonthlyCoinsProgress',
      'missionMonthlyDeliverClaimed',
      'missionMonthlyMergeClaimed',
      'missionMonthlyCoinsClaimed',
    ]);
    _dated(out, handled, l, c, 'wheelDay', const ['wheelFreeUsed', 'wheelAdUsed']);
    _dated(out, handled, l, c, 'wheelLastFreeDay', const ['wheelStreak']);
    _dated(out, handled, l, c, 'adGemsCooldownStart', const ['adGemsUsed']);
    _dated(out, handled, l, c, 'energyAdCooldownStart', const ['energyAdWatchesUsed']);

    // Enerji: son degistiren kazanir.
    _lww(out, handled, b, l, c, const ['energy', 'energyRegenStart']);

    // Cihaza ozel ayarlar + yarim kalan cark: hep yerel.
    for (final k in [...deviceLocal, 'wheelPending']) {
      handled.add(k);
      if (l.containsKey(k)) out[k] = l[k];
    }

    // Bilinmeyen/yeni alanlar: son degistiren kazanir.
    for (final k in <String>{...l.keys, ...c.keys}) {
      if (!handled.contains(k)) _lww(out, handled, b, l, c, [k]);
    }
    return out;
  }

  // ------------------------------------------------------------ diger depolar

  static Json season(Json? b, Json l, Json c) {
    final ls = _n(l, 'season');
    final cs = _n(c, 'season');
    if (ls != cs) return Map<String, dynamic>.of(ls > cs ? l : c);
    final sameB = (b != null && _n(b, 'season') == ls) ? b : null;
    final out = Map<String, dynamic>.of(c);
    out['points'] = _add(sameB, l, c, 'points');
    out['premium'] = l['premium'] == true || c['premium'] == true;
    out['free'] = _union(l['free'], c['free']);
    out['prem'] = _union(l['prem'], c['prem']);
    return out;
  }

  static Json piggy(Json? b, Json l, Json c) {
    final out = Map<String, dynamic>.of(c);
    out['gems'] = _add(b, l, c, 'gems');
    return out;
  }

  static Json events(Json? b, Json l, Json c) {
    final lw = _n(l, 'week');
    final cw = _n(c, 'week');
    if (lw != cw) return Map<String, dynamic>.of(lw > cw ? l : c);
    final sameB = (b != null && _n(b, 'week') == lw) ? b : null;
    final out = Map<String, dynamic>.of(c);
    out['points'] = _add(sameB, l, c, 'points');
    out['claimed'] = _union(l['claimed'], c['claimed']);
    return out;
  }

  static Json engage(Json? b, Json l, Json c) {
    final out = Map<String, dynamic>.of(c);
    final ld = _d(l['lastSeen']);
    final cd = _d(c['lastSeen']);
    if (ld != null && (cd == null || ld.isAfter(cd))) out['lastSeen'] = l['lastSeen'];
    out['welcomeClaimed'] = l['welcomeClaimed'] == true || c['welcomeClaimed'] == true;
    out['pendingAwayDays'] = math.min(_n(l, 'pendingAwayDays'), _n(c, 'pendingAwayDays'));
    return out;
  }

  /// Gelen kutusu / davet kimligi (playerId + token + davet kodu). Iki farkli kimlik varsa
  /// daha ESKI olan (ilk kurulumdaki) kazanir: yeniden kurulumda otomatik acilan yeni kimlik
  /// bulutta duran asil kimligi ezmez. "Islendi" listesi (verilmis oduller) birlesir.
  static Json invite(Json? b, Json l, Json c) {
    bool has(Json m) => m['playerId'] is String && m['token'] is String && _n(m, 'createdAt') > 0;
    final Json pick;
    if (has(l) && has(c)) {
      pick = _n(l, 'createdAt') <= _n(c, 'createdAt') ? l : c;
    } else if (has(c)) {
      pick = c;
    } else {
      pick = l;
    }
    final out = Map<String, dynamic>.of(pick);
    out['processed'] = _union(l['processed'], c['processed']);
    return out;
  }

  // ------------------------------------------------------------ yeniden dayama

  /// Birlestirme sirasinda (ag turu ~1 sn) oyuncu bir sey kazandi/harcadiysa
  /// bu degisikligi birlestirilmis sonucun ustune ekler. [l1] birlestirmeye
  /// girdigimiz yerel hal, [l2] uygulama anindaki yerel hal.
  static Json rebase(String store, Json m, Json l1, Json l2) {
    final out = Map<String, dynamic>.of(m);
    final add = additive[store] ?? const <String>[];
    for (final k in l2.keys) {
      if (store == kProgress && deviceLocal.contains(k)) {
        out[k] = l2[k];
        continue;
      }
      if (deepEq(l1[k], l2[k])) continue;
      if (store == kInvite && k == 'processed') {
        out[k] = _union(m[k], l2[k]); // verilmis oduller asla geri alinmaz
        continue;
      }
      if (add.contains(k)) {
        final r = _n(m, k) + _n(l2, k) - _n(l1, k);
        out[k] = r < 0 ? 0 : r;
      } else {
        out[k] = l2[k];
      }
    }
    return out;
  }

  // ------------------------------------------------------------ JSON yardimcilari

  static Stores? storesFrom(dynamic raw) {
    try {
      final dynamic j = raw is String ? jsonDecode(raw) : raw;
      if (j is! Map) return null;
      final out = <String, Json>{};
      j.forEach((k, v) {
        if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
      });
      return out;
    } catch (_) {
      return null;
    }
  }
}
