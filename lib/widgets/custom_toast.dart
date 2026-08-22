import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Uygulama genelinde varsayilan Material `SnackBar` (sistem popup'i gibi
/// duran, alttan cikan gri/koyu kutu) yerine kullanilan, oyunun uzay
/// temasiyla uyumlu ozel bildirim penceresi. Bir `Overlay` uzerinden
/// calistigi icin (ScaffoldMessenger'a bagli olmadigi icin) hem normal
/// ekranlardan hem de acik bir `showDialog` icinden bile guvenle
/// cagrilabilir — orn. rihtim dolduğunda, meteor yetersiz kaldiginda,
/// bir halka kilitliyken vb.
class CustomToast {
  CustomToast._();

  static OverlayEntry? _currentEntry;

  /// [message] gosterilecek metin, [icon] basinda gorunecek kucuk emoji,
  /// [accentColor] kenarlik/govlge rengi (varsayilan olarak notr mor
  /// vurgu), [duration] ekranda kalma suresi.
  static void show(
    BuildContext context,
    String message, {
    String icon = 'ℹ️',
    Color accentColor = AppColors.accent,
    Duration duration = const Duration(milliseconds: 1700),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Ayni anda birden fazla bildirim ust uste binmesin diye onceki
    // gosterimi hemen (animasyonsuz) kaldiriyoruz.
    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastCard(
        message: message,
        icon: icon,
        accentColor: accentColor,
        duration: duration,
        onFinished: () {
          if (_currentEntry == entry) {
            entry.remove();
            _currentEntry = null;
          }
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  final String message;
  final String icon;
  final Color accentColor;
  final Duration duration;
  final VoidCallback onFinished;

  const _ToastCard({
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.duration,
    required this.onFinished,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _autoHideTimer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottomInset + 28,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Align(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.55)),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                      const BoxShadow(
                        color: Colors.black38,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
