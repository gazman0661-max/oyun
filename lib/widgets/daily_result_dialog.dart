import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ad_service.dart';
import '../services/localization.dart';
import '../services/player_progress.dart';
import '../services/sound_service.dart';
import '../theme/app_colors.dart';
import 'custom_toast.dart';

class DailyResultDialog extends StatefulWidget {
  final bool isReplay;
  const DailyResultDialog({super.key, required this.isReplay});

  @override
  State<DailyResultDialog> createState() => _DailyResultDialogState();
}

class _DailyResultDialogState extends State<DailyResultDialog> {
  bool _doubling = false;
  bool _sharing = false;
  final GlobalKey _shareCardKey = GlobalKey();

  String _shareText(DailyResult r) {
    final efficiency = (r.optimal / r.moves).clamp(0.0, 1.0);
    final filled = efficiency == 0
        ? 1
        : (efficiency * 5).round().clamp(1, 5).toInt();
    final grid = '🟩' * filled + '⬜' * (5 - filled);
    return '🚀 ${t('appName')} ${t('daily_signalNum', {'n': '${r.dailyNum}'})} '
        '${'⭐' * r.stars}\n'
        '$grid\n${r.moves} ${t('daily_moves').toLowerCase()} '
        '(par: ${r.optimal}) · 🔥'
        '${t('daily_streakLine', {'n': '${PlayerProgress.instance.dailyStreak}'})}'
        '\n\n${t('daily_shareChallenge')}';
  }

  String _countdownText() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final diff = midnight.difference(now);
    return t('daily_nextCountdown', {
      'h': '${diff.inHours}',
      'm': '${diff.inMinutes % 60}',
    });
  }

  /// Ekrandaki gorsel sonuc kartini bir PNG'e donusturup, cihazin
  /// yerlesik "Paylas" sayfasini (WhatsApp/Instagram/Facebook vb. hangi
  /// uygulama secilirse ona) acar. Bir sebeple basarisiz olursa (ornegin
  /// masaustu/web'de dosya paylasimi desteklenmiyorsa) sessizce metni
  /// panoya kopyalamaya geri duser.
  Future<void> _shareResult(DailyResult r) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    SoundService.instance.buttonTap();
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('kart henuz hazir degil');
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/gunluk_sinyal_${r.dailyNum}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: _shareText(r),
      );
    } catch (_) {
      // Gorsel paylasim basarisiz olursa (ornegin dosya sistemi/plugin
      // desteklenmiyorsa) en azindan metni panoya kopyala.
      await Clipboard.setData(ClipboardData(text: _shareText(r)));
      if (mounted) {
        CustomToast.show(context, t('daily_copied'),
            icon: '✅', accentColor: AppColors.success);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = PlayerProgress.instance;
    final r = progress.dailyLastResult;

    return Dialog(
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
            Text(
              (widget.isReplay ? '✅ ' : '🎉 ') +
                  t('daily_signalNum',
                      {'n': '${r?.dailyNum ?? PlayerProgress.dailyNumber()}'}),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            // --- Ekranda gorunen, aslinda paylasilacak PNG'nin ta kendisi ---
            if (r != null)
              RepaintBoundary(
                key: _shareCardKey,
                child: _ShareCard(result: r, streak: progress.dailyStreak),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.surfaceBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (r == null || _sharing) ? null : () => _shareResult(r),
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded,
                        size: 18, color: AppColors.textPrimary),
                label: Text(t('daily_share'),
                    style: const TextStyle(color: AppColors.textPrimary)),
              ),
            ),
            if (r != null && !r.doubled) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _doubling
                      ? null
                      : () async {
                          setState(() => _doubling = true);
                          final granted =
                              await AdService.instance.showRewardedAdFlow(
                            context,
                            icon: '🎬',
                            title: t('home_dailyTitle'),
                            placementId: 'daily_double',
                          );
                          if (granted == true) {
                            await progress.claimDailyDouble();
                            SoundService.instance.reward();
                          }
                          if (mounted) setState(() => _doubling = false);
                        },
                  icon: const Icon(Icons.movie_filter_rounded,
                      size: 18, color: Colors.black87),
                  label: Text(t('daily_doubleXp', {'n': '${r.xp}'}),
                      style: const TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              _countdownText(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('daily_close'),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gunluk sonucun hem ekranda gosterilen HEM DE paylasilan PNG olarak
/// yakalanan gorsel karti. Yildiz/hamle/sure ozetinin yaninda, paylasima
/// tesvik eden bir meydan okuma satiri barindirir.
class _ShareCard extends StatelessWidget {
  final DailyResult result;
  final int streak;
  const _ShareCard({required this.result, required this.streak});

  String _timeText(DailyResult r) =>
      '${r.timeSeconds ~/ 60}:${(r.timeSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final efficiency = (result.optimal / result.moves).clamp(0.0, 1.0);
    final filled =
        efficiency == 0 ? 1 : (efficiency * 5).round().clamp(1, 5).toInt();
    final grid = '🟩' * filled + '⬜' * (5 - filled);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B1035), Color(0xFF0B1E3D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tubeGlassBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🪐', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 6),
              Text(
                t('daily_shareCardTitle', {'n': '${result.dailyNum}'}),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final lit = i < result.stars;
              return Icon(
                lit ? Icons.star_rounded : Icons.star_border_rounded,
                color: lit ? AppColors.warning : Colors.white24,
                size: 26,
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(grid, style: const TextStyle(fontSize: 20, letterSpacing: 2)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statChip('🔄', '${result.moves}', t('daily_shareMoves')),
              _statChip('⏱️', _timeText(result), t('daily_shareTime')),
              _statChip('🔥', '$streak', t('daily_shareStreak')),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              t('daily_shareChallenge'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}
