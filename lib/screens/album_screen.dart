import '../widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/album.dart';
import '../models/game_progress.dart';
import '../models/game_theme.dart';
import '../services/game_fx.dart';

/// Koleksiyon albümü: 6 tema x 8 obje = 48 kart. Henüz üretilmemiş
/// objeler siluet olarak görünür, üretilince renklenir. Bir temanın
/// 8 kartı da açılınca set ödülü, 6 set de alınınca büyük ödül gelir.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  void _claimSet(String themeKey) {
    if (GameProgress.instance.claimAlbumSet(themeKey)) {
      GameFx.instance.reward();
      setState(() {});
    }
  }

  void _claimAll() {
    if (GameProgress.instance.claimAlbumComplete()) {
      GameFx.instance.reward();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final progress = GameProgress.instance;

    return GameScaffold(
      title: s.t('album_title'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _TotalCard(
            found: progress.totalDiscovered,
            total: progress.totalAlbumCards,
            ready: progress.albumCompleteReady,
            claimed: progress.albumCompleteClaimed,
            onClaim: _claimAll,
          ),
          const SizedBox(height: 12),
          for (final theme in AlbumCatalog.themes)
            _ThemeSection(
              theme: theme,
              onClaim: () => _claimSet(theme.themeNameKey),
            ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int found;
  final int total;
  final bool ready;
  final bool claimed;
  final VoidCallback onClaim;

  const _TotalCard({
    required this.found,
    required this.total,
    required this.ready,
    required this.claimed,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.brown.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.t('album_total'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Text('$found/$total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : found / total,
              minHeight: 10,
              backgroundColor: Colors.brown.shade100,
              valueColor: AlwaysStoppedAnimation(Colors.orange.shade600),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.t('album_all_reward')}: ${GameProgress.albumCompleteReward} + ${GameProgress.albumCompleteGems} 💎',
                  style: TextStyle(color: Colors.brown.shade700),
                ),
              ),
              _ClaimButton(ready: ready, claimed: claimed, onTap: onClaim),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  final GameTheme theme;
  final VoidCallback onClaim;

  const _ThemeSection({required this.theme, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    final progress = GameProgress.instance;
    final key = theme.themeNameKey;
    final found = progress.discoveredCount(key);
    final complete = progress.isSetComplete(key);
    final claimed = progress.isSetClaimed(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: claimed ? Colors.green.shade400 : Colors.brown.shade200,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.t(key),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Text('$found/${GameProgress.albumItemsPerTheme}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown.shade700)),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.72,
            children: [
              for (var lvl = 1; lvl <= GameProgress.albumItemsPerTheme; lvl++)
                _AlbumCard(
                  tier: theme.byLevel(lvl),
                  discovered: progress.isDiscovered(key, lvl),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.t('album_set_reward')}: ${GameProgress.albumSetReward} + ${GameProgress.albumSetGems} 💎',
                  style: TextStyle(color: Colors.brown.shade700),
                ),
              ),
              _ClaimButton(ready: complete && !claimed, claimed: claimed, onTap: onClaim),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final TierInfo tier;
  final bool discovered;

  const _AlbumCard({required this.tier, required this.discovered});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(tier.imagePath, fit: BoxFit.contain);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: discovered ? tier.color.withOpacity(0.15) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: discovered ? tier.color.withOpacity(0.7) : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (discovered)
                  image
                else ...[
                  ColorFiltered(
                    colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcIn),
                    child: image,
                  ),
                  Icon(Icons.lock, size: 18, color: Colors.grey.shade100),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            discovered ? tier.name : '???',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: discovered ? Colors.brown.shade800 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimButton extends StatelessWidget {
  final bool ready;
  final bool claimed;
  final VoidCallback onTap;

  const _ClaimButton({required this.ready, required this.claimed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.instance;
    return CandyButton(
      width: 92,
      height: 38,
      fontSize: 12.5,
      style: CandyStyle.orange,
      label: claimed ? s.t('mission_claimed') : s.t('mission_claim'),
      onTap: ready ? onTap : null,
    );
  }
}
