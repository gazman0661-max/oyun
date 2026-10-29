import 'dart:async';

import 'package:flutter/material.dart';

import '../game/ranks.dart';
import '../services/cloud_progress_sync.dart';
import '../services/localization.dart';
import '../services/play_games_service.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import '../theme/cosmic_themes.dart';

/// "Galaktik Sıralama": Play Games'in HERKESE AÇIK skor tablolarını
/// (Dünya / Türkiye × Bugün / Bu hafta / Tüm zamanlar) oyunun kendi
/// tasarımıyla gösterir. Backend yok; veri Play Games'ten gelir, skor
/// etiketi (tag) ile her oyuncunun rütbe seviyesi de taşınır.
///
/// Tasarım: ilk üç oyuncu "yörünge podyumunda" parlayan gezegenler olarak,
/// geri kalanlar ise ilk sıradaki skora oranlı bir "meteor izi" çubuğuyla
/// listelenir. Altta sabit "Sen" kartı sıranı ve bir üst sıraya kalan
/// puanı gösterir.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  /// Skor tablosu ID'leri girilmemişse Google'ın eski ekranına düşer.
  static Future<void> open(BuildContext context) async {
    SoundService.instance.buttonTap();
    if (!PlayGamesService.leaderboardReady) {
      await PlayGamesService.instance.showLeaderboard();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
    );
  }

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _turkey = false;
  LeaderboardSpan _span = LeaderboardSpan.weekly;

  bool _loading = true;
  bool _failed = false;
  bool _needSignIn = false;
  List<LeaderboardEntry> _entries = const [];
  LeaderboardEntry? _me;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_requestId;
    setState(() {
      _loading = true;
      _failed = false;
      _needSignIn = false;
    });
    final pg = PlayGamesService.instance;
    if (!pg.isSignedIn) {
      await pg.signInSilently();
      if (!mounted || req != _requestId) return;
      if (!pg.isSignedIn) {
        setState(() {
          _loading = false;
          _needSignIn = true;
        });
        return;
      }
    }
    final listFuture = pg.loadLeaderboard(turkey: _turkey, span: _span);
    final meFuture = pg.loadMyLeaderboardEntry(turkey: _turkey, span: _span);
    final list = await listFuture;
    final me = await meFuture;
    if (!mounted || req != _requestId) return;
    setState(() {
      _loading = false;
      if (list == null) {
        _failed = true;
        _entries = const [];
        _me = null;
      } else {
        _entries = list;
        _me = me;
      }
    });
  }

  Future<void> _connect() async {
    SoundService.instance.buttonTap();
    final ok = await PlayGamesService.instance.signIn();
    if (!mounted) return;
    if (ok) unawaited(CloudProgressSync.instance.syncAfterSignIn());
    await _load();
  }

  void _setRegion(bool turkey) {
    if (_turkey == turkey) return;
    SoundService.instance.buttonTap();
    _turkey = turkey;
    _load();
  }

  void _setSpan(LeaderboardSpan span) {
    if (_span == span) return;
    SoundService.instance.buttonTap();
    _span = span;
    _load();
  }

  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CosmicThemes.buildActive(
        PlayerProgress.instance,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (PlayGamesService.turkeyBoardReady) _buildRegionTabs(),
              _buildSpanChips(),
              const SizedBox(height: 6),
              Expanded(child: _buildBody()),
              _buildMeBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🌌 ${t('lb_title')}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t('lb_subtitle'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegionTabs() {
    Widget seg(String label, bool turkey) {
      final selected = _turkey == turkey;
      return Expanded(
        child: GestureDetector(
          onTap: () => _setRegion(turkey),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppColors.accent, AppColors.accentSoft])
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.tubeGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.tubeGlassBorder),
        ),
        child: Row(
          children: [
            seg('🌍 ${t('lb_world')}', false),
            seg('🇹🇷 ${t('lb_turkey')}', true),
          ],
        ),
      ),
    );
  }

  Widget _buildSpanChips() {
    Widget chip(String label, LeaderboardSpan span) {
      final selected = _span == span;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => _setSpan(span),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppColors.tubeSelectedGlow
                    : AppColors.surfaceBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.tubeSelectedGlow
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(t('lb_daily'), LeaderboardSpan.daily),
            chip(t('lb_weekly'), LeaderboardSpan.weekly),
            chip(t('lb_allTime'), LeaderboardSpan.allTime),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentSoft),
      );
    }
    if (_needSignIn) {
      return _message(
        t('lb_needSignIn'),
        actionLabel: t('lb_connect'),
        onAction: _connect,
      );
    }
    if (_failed) {
      return _message(
        t('lb_loadFail'),
        actionLabel: t('lb_retry'),
        onAction: _load,
      );
    }
    if (_entries.isEmpty) {
      return _message(t('lb_empty'));
    }

    final topScore = _entries.first.score <= 0 ? 1 : _entries.first.score;
    final podium = _entries.take(3).toList();
    final rest = _entries.length > 3 ? _entries.sublist(3) : const <LeaderboardEntry>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      children: [
        _Podium(entries: podium, isMe: _isMe),
        const SizedBox(height: 14),
        for (final e in rest)
          _EntryRow(
            entry: e,
            topScore: topScore,
            isMe: _isMe(e),
          ),
      ],
    );
  }

  bool _isMe(LeaderboardEntry e) {
    final me = _me;
    return me != null && me.rank == e.rank && me.score == e.score;
  }

  Widget _message(String text, {String? actionLabel, VoidCallback? onAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🛰️', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5, height: 1.35),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Altta sabit duran "Sen" kartı.
  Widget _buildMeBar() {
    if (_loading || _needSignIn || _failed) return const SizedBox.shrink();
    final me = _me;
    String? gapText;
    if (me != null) {
      final idx = _entries.indexWhere((e) => e.rank == me.rank && e.score == me.score);
      if (me.rank == 1) {
        gapText = t('lb_leading');
      } else if (idx > 0) {
        final diff = _entries[idx - 1].score - me.score;
        if (diff > 0) gapText = t('lb_gap', {'n': _fmt(diff)});
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accentSoft, width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0x445CC8FF), blurRadius: 14),
        ],
      ),
      child: me == null
          ? Row(
              children: [
                const Text('🚀', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('lb_noScore'),
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _Orb(name: me.name, size: 42, ring: AppColors.accentSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t('lb_you')} · #${_fmt(me.rank)}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      if (gapText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          gapText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _fmt(me.score),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Binlik ayraçlı sayı (ayraç dile göre: tr '.', en ',', ru boşluk).
String _fmt(int n) {
  final sep = t('lb_sep');
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

String _rankBadge(LeaderboardEntry e) {
  final lvl = e.level;
  if (lvl == null || lvl <= 0) return '';
  return '${Ranks.forLevel(lvl).icon} $lvl';
}

// =======================================================================
// Gezegen avatar: isimden türetilen renkle parlayan küre + baş harf.
// =======================================================================
class _Orb extends StatelessWidget {
  final String name;
  final double size;
  final Color? ring;
  const _Orb({required this.name, required this.size, this.ring});

  Color _base() {
    var h = 7;
    for (final r in name.runes) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    return AppColors.palette[h % AppColors.palette.length].color;
  }

  @override
  Widget build(BuildContext context) {
    final base = _base();
    final hsl = HSLColor.fromColor(base);
    final light = hsl
        .withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0).toDouble())
        .toColor();
    final dark = hsl
        .withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0).toDouble())
        .toColor();
    final initial =
        name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.45),
          radius: 0.95,
          colors: [light, dark],
        ),
        border: Border.all(
          color: ring ?? const Color(0x55FFFFFF),
          width: ring == null ? 1 : 2.5,
        ),
        boxShadow: [
          BoxShadow(color: base.withAlpha(110), blurRadius: size * 0.32),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)],
        ),
      ),
    );
  }
}

// =======================================================================
// İlk üç: yörünge podyumu.
// =======================================================================
class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final bool Function(LeaderboardEntry) isMe;
  const _Podium({required this.entries, required this.isMe});

  static const _gold = AppColors.warning;
  static const _silver = Color(0xFFCBD5E1);
  static const _bronze = Color(0xFFD08B5B);

  Widget _slot(int index, double orb, double pedestal, Color color) {
    if (index >= entries.length) return const Expanded(child: SizedBox());
    final e = entries[index];
    final me = isMe(e);
    final badge = _rankBadge(e);
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (index == 0) const Text('👑', style: TextStyle(fontSize: 22)),
          _Orb(name: e.name, size: orb, ring: me ? AppColors.accentSoft : color),
          const SizedBox(height: 6),
          Text(
            e.name.isEmpty ? '—' : e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: me ? AppColors.accentSoft : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          if (badge.isNotEmpty)
            Text(badge,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            _fmt(e.score),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: pedestal,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withAlpha(90), color.withAlpha(10)],
              ),
              border: Border.all(color: color.withAlpha(140)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _slot(1, 52, 54, _silver),
        _slot(0, 66, 76, _gold),
        _slot(2, 48, 42, _bronze),
      ],
    );
  }
}

// =======================================================================
// 4. sıradan itibaren satırlar: sıra çipi, avatar, isim + rütbe, skor ve
// ilk sıradaki skora oranlı "meteor izi" çubuğu.
// =======================================================================
class _EntryRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final int topScore;
  final bool isMe;
  const _EntryRow({
    required this.entry,
    required this.topScore,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (entry.score / topScore).clamp(0.0, 1.0).toDouble();
    final badge = _rankBadge(entry);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.surface : AppColors.tubeGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? AppColors.accentSoft : AppColors.tubeGlassBorder,
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.rank}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Orb(name: entry.name, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name.isEmpty ? '—' : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe ? AppColors.accentSoft : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.meteorTrail),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(entry.score),
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              if (badge.isNotEmpty)
                Text(badge,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}
