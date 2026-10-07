import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';
import '../services/game_fx.dart';
import '../services/inbox_service.dart';
import '../services/time_service.dart';
import '../widgets/ui_kit.dart';

/// GELEN KUTUSU: iki sekme - MESAJLAR (admin panelinden gelen mesaj + hediyeler)
/// ve DAVETLER (arkadas davet kademeleri). Koyu mavi tema.
class InboxScreen extends StatefulWidget {
  /// 0 = Mesajlar, 1 = Davetler
  final int initialTab;
  const InboxScreen({super.key, this.initialTab = 0});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

// ── renkler ──
const Color _kNavy = Color(0xFF14213A);
const Color _kCardTop = Color(0xFF35699B);
const Color _kCardBottom = Color(0xFF2A557F);
const Color _kCardBorder = Color(0xFF4B86B8);
const Color _kGold = Color(0xFFE0A93B);
const Color _kDark = Color(0xFF16233F);

bool get _tr => AppStrings.instance.language == AppLanguage.tr;

/// Turkce buyuk harf ("i" -> "İ", "ı" -> "I").
String _up(String s) {
  if (_tr) return s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
  return s.toUpperCase();
}

const List<Shadow> _kTextShadow = [
  Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 2)),
  Shadow(color: Colors.black54, blurRadius: 8),
];

String _expiryText(InboxMessage m) {
  final left = DateTime.fromMillisecondsSinceEpoch(m.expiresAt).difference(TimeService.instance.now());
  if (left.inDays >= 1) {
    return _tr ? '${left.inDays}g sonra sona eriyor' : 'Expires in ${left.inDays}d';
  }
  if (left.inHours >= 1) {
    return _tr ? '${left.inHours}s sonra sona eriyor' : 'Expires in ${left.inHours}h';
  }
  final min = left.inMinutes < 1 ? 1 : left.inMinutes;
  return _tr ? '${min}dk sonra sona eriyor' : 'Expires in ${min}m';
}

String _errText(String code, int level) {
  switch (code) {
    case 'invalid_code':
      return _tr ? 'Geçersiz davet kodu.' : 'Invalid invite code.';
    case 'already_redeemed':
      return _tr ? 'Zaten bir davet kodu girdin.' : 'You already entered a code.';
    case 'too_late':
      return _tr
          ? 'Kod girmek için çok geç: $level. seviyeye ulaşmadan girilmeli.'
          : 'Too late: the code must be entered before level $level.';
    case 'self_code':
      return _tr ? 'Kendi kodunu giremezsin.' : "You can't use your own code.";
    case 'mutual':
      return _tr ? 'Bu oyuncu senin kodunu girmiş.' : 'That player already used your code.';
    case 'inviter_full':
      return _tr ? 'Bu kodun davet sınırı dolmuş.' : 'This code has reached its invite limit.';
    case 'too_many_attempts':
      return _tr ? 'Çok fazla yanlış deneme yaptın.' : 'Too many wrong attempts.';
    case 'rate_limited':
      return _tr ? 'Çok fazla istek, biraz sonra tekrar dene.' : 'Too many requests, try again later.';
    default:
      return _tr ? 'Bağlantı kurulamadı. İnternetini kontrol et.' : 'Connection failed. Check your internet.';
  }
}

class _InboxScreenState extends State<InboxScreen> {
  final InboxService svc = InboxService.instance;
  late int _tab = widget.initialTab.clamp(0, 1).toInt();
  final TextEditingController _codeCtl = TextEditingController();
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    svc.addListener(_onChange);
    unawaited(svc.sync(force: true));
  }

  @override
  void dispose() {
    svc.removeListener(_onChange);
    _codeCtl.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ eylemler

  Future<void> _openMessage(InboxMessage m) async {
    GameFx.instance.uiTap();
    unawaited(svc.markRead(m));
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _MessageDialog(message: m),
    );
  }

  Future<void> _claimReward(InviteReward r) async {
    GameFx.instance.reward();
    await svc.claimReward(r);
    if (!mounted) return;
    showGamePopup(context, '+${r.gems} 💎', autoCloseMs: 1500);
  }

  Future<void> _redeem() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty || _redeeming) return;
    GameFx.instance.uiTap();
    setState(() => _redeeming = true);
    final err = await svc.redeem(code);
    if (!mounted) return;
    setState(() => _redeeming = false);
    if (err == null) {
      GameFx.instance.reward();
      _codeCtl.clear();
      showGamePopup(
        context,
        _tr
            ? 'Kod kabul edildi! ${svc.qualifyLevel}. seviyeye ulaşınca ${svc.inviteeBonus} 💎 kazanırsın.'
            : 'Code accepted! Reach level ${svc.qualifyLevel} to get ${svc.inviteeBonus} 💎.',
        autoCloseMs: 3200,
      );
    } else {
      GameFx.instance.denied();
      showGamePopup(context, _errText(err, svc.qualifyLevel), autoCloseMs: 3000);
    }
  }

  Future<void> _share() async {
    GameFx.instance.uiTap();
    final opened = await svc.shareInvite();
    if (!opened && mounted) {
      showGamePopup(context, _tr ? 'Davet mesajı panoya kopyalandı.' : 'Invite message copied.');
    }
  }

  Future<void> _copyCode() async {
    GameFx.instance.uiTap();
    await svc.copyCode();
    if (mounted) showGamePopup(context, _tr ? 'Kod kopyalandı.' : 'Code copied.', autoCloseMs: 1200);
  }

  void _showHelp() {
    GameFx.instance.uiTap();
    showDialog<void>(
      context: context,
      builder: (ctx) => GameAlertDialog(
        title: Text(_tr ? 'Arkadaş Davet Et' : 'Invite Friends'),
        content: Text(
          _tr
              ? 'Davet kodunu arkadaşınla paylaş. Arkadaşın kodu ${svc.qualifyLevel}. seviyeye ulaşmadan önce oyuna girerse ve '
                  '${svc.qualifyLevel}. seviyeye ulaşırsa davet başarılı olur.\n\n'
                  'Arkadaşın ${svc.inviteeBonus} 💎 kazanır, sen de başarılı davet sayına göre kademe ödülleri alırsın. '
                  'En fazla ${svc.maxInvites} arkadaş sayılır.'
              : 'Share your invite code. If your friend enters it before reaching level ${svc.qualifyLevel} and then reaches '
                  'level ${svc.qualifyLevel}, the invite counts.\n\n'
                  'Your friend gets ${svc.inviteeBonus} 💎 and you earn milestone rewards. '
                  'Up to ${svc.maxInvites} friends count.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppStrings.instance.t('ok')))],
      ),
    );
  }

  // ------------------------------------------------------------ iskelet

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavy,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2538), Color(0xFF1D3D5E), Color(0xFF10203A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabs(),
              Expanded(child: _tab == 0 ? _buildMessages() : _buildInvites()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _up(_tr ? 'Gelen Kutusu' : 'Inbox'),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, shadows: _kTextShadow),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                GameFx.instance.uiTap();
                Navigator.of(context).maybePop();
              },
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF5A52), Color(0xFFC42A2A)],
                  ),
                  border: Border.all(color: const Color(0xFFFFB3AD), width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF123A78),
        border: Border(top: BorderSide(color: Color(0xFF2E7BD6), width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: _up(_tr ? 'Mesajlar' : 'Messages'),
              selected: _tab == 0,
              badge: svc.hasMessagesBadge,
              onTap: () => setState(() => _tab = 0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TabButton(
              label: _up(_tr ? 'Davetler' : 'Invites'),
              selected: _tab == 1,
              badge: svc.hasInviteBadge,
              onTap: () => setState(() => _tab = 1),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ MESAJLAR

  Widget _notice(String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFB9D6FF)),
            ),
            if (retry) ...[
              const SizedBox(height: 16),
              CandyButton(
                label: _tr ? 'TEKRAR DENE' : 'RETRY',
                style: CandyStyle.blue,
                height: 52,
                fontSize: 18,
                width: 200,
                onTap: () => unawaited(svc.sync(force: true)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (!InboxService.isConfigured) {
      return _notice(_tr ? 'Gelen kutusu yakında açılıyor.' : 'The inbox is coming soon.');
    }
    final list = svc.messages;
    if (list.isEmpty) {
      if (!svc.loadedOnce) {
        if (svc.syncing) return const Center(child: CircularProgressIndicator(color: Colors.white));
        if (svc.lastError != null) return _notice(_errText(svc.lastError!, svc.qualifyLevel), retry: true);
      }
      return RefreshIndicator(
        onRefresh: () => svc.sync(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _tr ? 'Henüz mesajın yok.' : 'No messages yet.',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFB9D6FF)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => svc.sync(force: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _MessageCard(message: list[i], onTap: () => _openMessage(list[i])),
      ),
    );
  }

  // ------------------------------------------------------------ DAVETLER

  Widget _buildInvites() {
    if (!InboxService.isConfigured) {
      return _notice(_tr ? 'Arkadaş daveti yakında açılıyor.' : 'Friend invites are coming soon.');
    }
    final tiers = svc.tiers.isNotEmpty
        ? svc.tiers
        : <InviteTier>[
            for (final t in InboxService.defaultTiers)
              InviteTier(count: t[0], gems: t[1], reached: false, claimed: false),
          ];
    final bonus = svc.inviteeBonusReward;
    final showError = !svc.loadedOnce && !svc.syncing && svc.lastError != null;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => svc.sync(force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _inviteHeader(),
                _countBand(),
                if (showError)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _errText(svc.lastError!, svc.qualifyLevel),
                            style: const TextStyle(color: Color(0xFFFFB3AD), fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(svc.sync(force: true)),
                          child: Text(_tr ? 'Tekrar dene' : 'Retry'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  child: Column(
                    children: [
                      _codeCard(),
                      if (svc.canRedeem) _redeemCard(),
                      if (bonus != null) _bonusCard(bonus),
                      const SizedBox(height: 14),
                      Text(
                        _tr ? 'Dönüm noktalarına ulaştığın için aldığın ödüller:' : 'Rewards for reaching milestones:',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, shadows: _kTextShadow),
                      ),
                      const SizedBox(height: 12),
                      for (final t in tiers) _tierCard(t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(40, 10, 40, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0C1A33),
            border: Border(top: BorderSide(color: Color(0xFF2E7BD6), width: 2)),
          ),
          child: CandyButton(
            label: _tr ? 'DAVET' : 'INVITE',
            icon: Icons.share_rounded,
            style: CandyStyle.orange,
            height: 64,
            fontSize: 26,
            onTap: svc.inviteCode == null ? null : _share,
          ),
        ),
      ],
    );
  }

  Widget _inviteHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: const Color(0xFF1B4170),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset('assets/images/ui/dragon_1.webp', width: 74, height: 74, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _up(_tr ? 'Arkadaş Davet Et' : 'Invite Friends'),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, shadows: _kTextShadow),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _showHelp,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7BD6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white70, width: 1.5),
                        ),
                        child: const Text('?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, height: 1.0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _tr ? 'Kendin ve arkadaşların için ödüller kazan!' : 'Earn rewards for you and your friends!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF8FD0FF), height: 1.1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countBand() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: const Color(0xFF10294A),
      child: Column(
        children: [
          Text(
            '${_up(_tr ? 'Başarılı Davetler' : 'Successful Invites')}: ${svc.inviteCount}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFFE9A8), shadows: _kTextShadow),
          ),
          Text(
            _tr
                ? 'Arkadaşlarının ${svc.qualifyLevel}. seviyeye ulaşması itibarıyla davetler başarılı olur.'
                : 'Invites succeed once your friends reach level ${svc.qualifyLevel}.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFFD27A), height: 1.1),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDeco({Color border = _kCardBorder, double width = 2}) => BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kCardTop, _kCardBottom]),
        border: Border.all(color: border, width: width),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 4))],
      );

  Widget _codeCard() {
    final code = svc.inviteCode;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: _cardDeco(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _up(_tr ? 'Davet kodun' : 'Your code'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB9D6FF)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    code ?? (svc.syncing ? '...' : '— — —'),
                    style: const TextStyle(fontSize: 32, letterSpacing: 3, fontWeight: FontWeight.w900, color: Color(0xFFFFE2A0), shadows: _kTextShadow),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: code == null ? null : _copyCode,
            icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 28),
            tooltip: _tr ? 'Kopyala' : 'Copy',
          ),
        ],
      ),
    );
  }

  Widget _redeemCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr ? 'Davet kodun var mı?' : 'Have an invite code?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_UpperFormatter(), LengthLimitingTextInputFormatter(9)],
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: 'ABCD-EFGH',
                    hintStyle: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w800, letterSpacing: 2),
                    filled: true,
                    fillColor: _kDark,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CandyButton(
                label: _tr ? 'GİR' : 'GO',
                style: CandyStyle.blue,
                width: 84,
                height: 50,
                fontSize: 18,
                onTap: _redeeming ? null : _redeem,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _tr
                ? '${svc.qualifyLevel}. seviyeye ulaşmadan önce gir; ulaşınca ${svc.inviteeBonus} 💎 kazan.'
                : 'Enter it before level ${svc.qualifyLevel}; reach it to get ${svc.inviteeBonus} 💎.',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFB9D6FF), height: 1.1),
          ),
        ],
      ),
    );
  }

  Widget _bonusCard(InviteReward r) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: _cardDeco(border: _kGold, width: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _up(_tr ? 'Davet bonusun' : 'Invite bonus'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFFFE2A0), shadows: _kTextShadow),
            ),
          ),
          _GemPill(gems: r.gems),
          const SizedBox(width: 8),
          CandyButton(
            label: _tr ? 'AL' : 'GET',
            width: 78,
            height: 46,
            fontSize: 18,
            pulse: true,
            onTap: () => unawaited(_claimReward(r)),
          ),
        ],
      ),
    );
  }

  Widget _tierCard(InviteTier t) {
    final reward = svc.rewardForTier(t.count);
    final claimable = reward != null && !t.claimed;
    final label = _tr
        ? '${t.count} ARKADAŞ'
        : (t.count == 1 ? '1 FRIEND' : '${t.count} FRIENDS');
    final card = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      decoration: _cardDeco(border: _kGold, width: 3).copyWith(
        boxShadow: [
          const BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 4)),
          if (claimable) BoxShadow(color: _kGold.withOpacity(0.55), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFFFE2A0), shadows: _kTextShadow),
              ),
            ),
          ),
          _GemPill(gems: t.gems),
          const SizedBox(width: 8),
          if (claimable)
            CandyButton(
              label: _tr ? 'AL' : 'GET',
              width: 78,
              height: 46,
              fontSize: 18,
              pulse: true,
              onTap: () => unawaited(_claimReward(reward!)),
            )
          else if (t.claimed)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF7BE28F), size: 40)
          else
            const Icon(Icons.lock_rounded, color: Colors.white38, size: 34),
        ],
      ),
    );
    return t.claimed ? Opacity(opacity: 0.7, child: card) : card;
  }
}

// ═════════════════════════════════════════════════════════════════════
// Kucuk bilesenler
// ═════════════════════════════════════════════════════════════════════

class _UpperFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.selected, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        GameFx.instance.uiTap();
        onTap();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: selected ? const [Color(0xFF3FB4FF), Color(0xFF1B86E0)] : const [Color(0xFF1F3F7D), Color(0xFF142B58)],
              ),
              border: Border.all(color: selected ? const Color(0xFF9BE0FF) : const Color(0xFF3A66B5), width: 2),
              boxShadow: selected ? [BoxShadow(color: const Color(0xFF3FB4FF).withOpacity(0.5), blurRadius: 10)] : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : const Color(0xFFD5E4FF),
                  shadows: selected ? _kTextShadow : null,
                ),
              ),
            ),
          ),
          if (badge)
            Positioned(
              right: -4,
              top: -6,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE94F4F),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Text('!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, height: 1.0)),
              ),
            ),
        ],
      ),
    );
  }
}

class _GemPill extends StatelessWidget {
  final int gems;
  const _GemPill({required this.gems});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0C1730), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/ui/gem.webp', width: 34, height: 34),
          const SizedBox(width: 4),
          Text('x$gems', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, shadows: _kTextShadow)),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final InboxMessage message;
  final VoidCallback onTap;
  const _MessageCard({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final attention = !m.read || (m.hasGift && !m.claimed);
    final Widget icon;
    if (m.hasGift) {
      icon = Opacity(opacity: m.claimed ? 0.4 : 1.0, child: Image.asset('assets/images/ui/gift.webp', width: 64, height: 64));
    } else {
      icon = Icon(m.read ? Icons.drafts_rounded : Icons.mail_rounded, size: 52, color: const Color(0xFFB9D6FF));
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kCardTop, _kCardBottom]),
          border: Border.all(color: attention ? const Color(0xFF8FD0FF) : _kCardBorder, width: attention ? 2.5 : 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  decoration: BoxDecoration(
                    color: _kDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0C1730), width: 2),
                  ),
                  child: Column(
                    children: [
                      Expanded(child: Center(child: icon)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _expiryText(m),
                          maxLines: 1,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white, shadows: _kTextShadow),
                        ),
                      ),
                    ],
                  ),
                ),
                if (attention)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94F4F),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _up(m.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0, shadows: _kTextShadow),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        m.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFB9D6FF), height: 1.1),
                      ),
                    ),
                    Text(
                      _up(_tr ? 'Gönderen: Merge Dünyaları' : 'From: World Merge'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFFD5E4FF), shadows: _kTextShadow),
                    ),
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

/// Mesaj detayi + hediye alma.
class _MessageDialog extends StatefulWidget {
  final InboxMessage message;
  const _MessageDialog({required this.message});

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  bool _busy = false;

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    GameFx.instance.reward();
    await InboxService.instance.claimMessage(widget.message);
    if (mounted) setState(() => _busy = false);
  }

  List<Widget> _giftChips(InboxMessage m) {
    Widget chip(Widget icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _kDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0C1730), width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 5),
              Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            ],
          ),
        );
    return [
      if (m.gems > 0) chip(Image.asset('assets/images/ui/gem.webp', width: 30, height: 30), 'x${m.gems}'),
      if (m.coins > 0) chip(Image.asset('assets/images/coin_icon.webp', width: 28, height: 28), 'x${m.coins}'),
      if (m.energy > 0) chip(Image.asset('assets/images/ui/bolt.webp', width: 28, height: 28), _tr ? 'Dolu' : 'Full'),
      if (m.aim > 0) chip(const Icon(Icons.gps_fixed_rounded, color: Color(0xFF9CF25B), size: 26), 'x${m.aim}'),
      if (m.joker > 0) chip(const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD27A), size: 26), 'x${m.joker}'),
      if (m.revive > 0) chip(const Icon(Icons.favorite_rounded, color: Color(0xFFFF7A7A), size: 26), 'x${m.revive}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final claimable = m.hasGift && !m.claimed;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kCardTop, Color(0xFF22456B)]),
            border: Border.all(color: const Color(0xFF8FD0FF), width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 16)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _up(m.title),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1.05, shadows: _kTextShadow),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    m.body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFE3EEFF), height: 1.15),
                  ),
                ),
              ),
              if (m.hasGift) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: _giftChips(m)),
              ],
              const SizedBox(height: 16),
              if (claimable)
                CandyButton(
                  label: _tr ? 'AL' : 'CLAIM',
                  height: 58,
                  fontSize: 22,
                  pulse: true,
                  onTap: _busy ? null : _claim,
                )
              else ...[
                if (m.hasGift)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _tr ? '✓ Ödül alındı' : '✓ Reward claimed',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF7BE28F)),
                    ),
                  ),
                CandyButton(
                  label: _tr ? 'KAPAT' : 'CLOSE',
                  style: CandyStyle.blue,
                  height: 52,
                  fontSize: 19,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
