import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/game_progress.dart';
import '../services/game_fx.dart';

/// Oyun genelinde ORTAK UI parcalari: tum ekranlar ayni dilde konussun diye
/// parlak buton, cam daire buton ve cam rozet burada tanimli.

enum CandyStyle { green, orange, blue }

/// Yatayda ESNEYEN gorsel cubuk (buton / rozet zemini): sol kapak + sag
/// kapak sabit, ortadaki ince serit gerilir. Boylece 2 kat genis butonlar da
/// kenarlari bozulmadan cizilir. [base] -> '<base>_l.webp', '_m.webp', '_r.webp'.
/// [capRatio]: kapak genisligi / yukseklik (asset uretilirken kullanilan oran).
class SlicedBar extends StatelessWidget {
  final String base;
  final double capRatio;
  final ColorFilter? filter;
  const SlicedBar({super.key, required this.base, this.capRatio = 0.62, this.filter});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight.isFinite ? box.maxHeight : 56.0;
      final cap = min(h * capRatio, box.maxWidth / 2);
      Widget bar = Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: cap - 1,
            right: cap - 1,
            top: 0,
            bottom: 0,
            child: Image.asset('${base}_m.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: cap,
            child: Image.asset('${base}_l.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: cap,
            child: Image.asset('${base}_r.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
        ],
      );
      if (filter != null) bar = ColorFiltered(colorFilter: filter!, child: bar);
      return bar;
    });
  }
}

/// Susleme kenarli krem panel (popup / alt sayfa zemini). 9 parcali: kose
/// susleri sabit, kenarlar ve orta gerilir. Icerik [padding] ile cerceve icine oturur.
class PanelFrame extends StatelessWidget {
  final Widget child;
  final double corner;
  final EdgeInsets padding;
  const PanelFrame({
    super.key,
    required this.child,
    this.corner = 54,
    this.padding = const EdgeInsets.fromLTRB(32, 28, 32, 28),
  });

  Widget _img(String n) =>
      Image.asset('assets/images/ui/panel_$n.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium);

  @override
  Widget build(BuildContext context) {
    final c = corner;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              Positioned(left: c - 1, right: c - 1, top: c - 1, bottom: c - 1, child: _img('c')),
              Positioned(left: c - 1, right: c - 1, top: 0, height: c, child: _img('t')),
              Positioned(left: c - 1, right: c - 1, bottom: 0, height: c, child: _img('b')),
              Positioned(left: 0, top: c - 1, bottom: c - 1, width: c, child: _img('l')),
              Positioned(right: 0, top: c - 1, bottom: c - 1, width: c, child: _img('r')),
              Positioned(left: 0, top: 0, width: c, height: c, child: _img('tl')),
              Positioned(right: 0, top: 0, width: c, height: c, child: _img('tr')),
              Positioned(left: 0, bottom: 0, width: c, height: c, child: _img('bl')),
              Positioned(right: 0, bottom: 0, width: c, height: c, child: _img('br')),
            ],
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }
}

/// Kirmizi kurdele baslik (ekran basliklari icin).
class RibbonTitle extends StatelessWidget {
  final String text;
  final double height;
  const RibbonTitle({super.key, required this.text, this.height = 60});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.asset('assets/images/ui/ribbon.webp', height: height, fit: BoxFit.contain),
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0, -0.12),
            child: FractionallySizedBox(
              widthFactor: 0.6,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: height * 0.3,
                    shadows: const [Shadow(color: Color(0xFF7A1A00), offset: Offset(0, 2), blurRadius: 2)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Parlak resimli "candy" buton (yesil/turuncu/mavi). [pulse] true ise nabiz
/// gibi atar. [onTap] null ise gri/pasif gorunur.
class CandyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? leading;
  final double? width;
  final CandyStyle style;
  final double height;
  final double fontSize;
  final bool pulse;

  const CandyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.width,
    this.style = CandyStyle.green,
    this.height = 60,
    this.fontSize = 22,
    this.pulse = false,
  });

  @override
  State<CandyButton> createState() => _CandyButtonState();
}

class _CandyButtonState extends State<CandyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _down = false;

  static const ColorFilter _grey = ColorFilter.matrix(<double>[
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0,
    0.33, 0.33, 0.33, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _base {
    switch (widget.style) {
      case CandyStyle.orange:
        return 'assets/images/ui/btn_orange';
      case CandyStyle.blue:
        return 'assets/images/ui/btn_blue';
      case CandyStyle.green:
        return 'assets/images/ui/btn_green';
    }
  }

  Color get _shadowColor {
    switch (widget.style) {
      case CandyStyle.orange:
        return const Color(0xFF9A4A00);
      case CandyStyle.blue:
        return const Color(0xFF184C9A);
      case CandyStyle.green:
        return const Color(0xFF1B7A2A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        final scale = (_down ? 0.96 : 1.0) * (1.0 + 0.02 * t);
        return GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: widget.onTap,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: widget.width ?? double.infinity,
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height * 0.4),
                boxShadow: [
                  if (enabled && widget.pulse)
                    BoxShadow(color: _shadowColor.withOpacity(0.25 + 0.3 * t), blurRadius: 16 + 8 * t, spreadRadius: 1),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: SlicedBar(base: _base, filter: enabled ? null : _grey)),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: widget.height * 0.07, left: widget.height * 0.3, right: widget.height * 0.3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.leading != null) ...[
                            widget.leading!,
                            const SizedBox(width: 4),
                          ] else if (widget.icon != null) ...[
                            Icon(widget.icon, color: Colors.white, size: widget.fontSize * 1.4),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.fontSize,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.6,
                                shadows: [Shadow(color: _shadowColor, offset: const Offset(0, 2), blurRadius: 3)],
                              ),
                            ),
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
      },
    );
  }
}

/// Koyu cam zeminli yuvarlak ikon butonu (geri, ayar vb.).
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const GlassCircleButton({super.key, required this.icon, required this.onTap, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.4),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}

/// Koyu cam zeminli rozet (baslik, sayac, coin vb.).
class GlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.35), width: 1.4),
      ),
      child: child,
    );
  }
}

/// Tum "alt ekranlar" (magaza, sezon, gorevler...) icin ortak iskelet:
/// mor gradyan ust alan + geri butonu + kurdele baslik + coin/elmas rozeti,
/// altta yuvarlak koseli krem icerik alani.
class GameScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? bottom;
  final Color bodyColor;
  final bool showCurrency;

  /// Verilirse sag ustteki coin/elmas rozeti yerine bu widget gosterilir.
  final Widget? trailing;

  const GameScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottom,
    this.bodyColor = const Color(0xFFFFF3E0),
    this.showCurrency = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final gp = GameProgress.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF2A0F5C),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A0F5C), Color(0xFF51299B)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                child: Row(
                  children: [
                    GlassCircleButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () {
                        GameFx.instance.uiTap();
                        Navigator.of(context).maybePop();
                      },
                    ),
                    Expanded(child: Center(child: RibbonTitle(text: title, height: 58))),
                    trailing ?? (showCurrency ? _CurrencyBadge(coins: gp.coins, gems: gp.gems) : const SizedBox(width: 44)),
                  ],
                ),
              ),
              if (bottom != null) bottom!,
              const SizedBox(height: 4),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: bodyColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                    border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -2))],
                  ),
                  child: Material(type: MaterialType.transparency, child: body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  final int coins;
  final int gems;
  const _CurrencyBadge({required this.coins, required this.gems});

  Widget _row(String asset, int v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(asset, width: 15, height: 15),
          const SizedBox(width: 4),
          Text('$v', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 50),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: SlicedBar(base: 'assets/images/ui/pill', capRatio: 0.65)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('assets/images/coin_icon.webp', coins),
                const SizedBox(height: 1),
                _row('assets/images/ui/gem.webp', gems),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AlertDialog yerine gecen SUSLEMELI PANELLI diyalog. AlertDialog ile ayni
/// isimli parametreleri alir (shape / backgroundColor / actionsAlignment yok
/// sayilir), boylece mevcut diyaloglarda sadece sinif adi degistirilir.
/// FilledButton/ElevatedButton -> resimli yesil buton, TextButton -> kahverengi
/// yazi baglantisi olarak otomatik cizilir; baska widget verilirse aynen kalir.
class GameAlertDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final MainAxisAlignment? actionsAlignment;

  const GameAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.shape,
    this.backgroundColor,
    this.actionsAlignment,
  });

  static const Color _ink = Color(0xFF5D2E00);

  Widget _action(Widget a) {
    VoidCallback? onTap;
    Widget? child;
    if (a is FilledButton) {
      onTap = a.onPressed;
      child = a.child;
    } else if (a is ElevatedButton) {
      onTap = a.onPressed;
      child = a.child;
    } else {
      return a;
    }
    if (child is Text && child.data != null) {
      return CandyButton(label: child.data!, height: 50, fontSize: 17, onTap: onTap);
    }
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final acts = actions ?? const <Widget>[];
    final primary = <Widget>[];
    final secondary = <Widget>[];
    for (final a in acts) {
      final w = _action(a);
      if (w is CandyButton || a is FilledButton || a is ElevatedButton) {
        primary.add(w);
      } else {
        secondary.add(w);
      }
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: PanelFrame(
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 28),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF6B4A32), fontSize: 15, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: const TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                      child: title!,
                    ),
                  if (title != null && content != null) const SizedBox(height: 12),
                  if (content != null) content!,
                  if (primary.isNotEmpty || secondary.isNotEmpty) const SizedBox(height: 18),
                  for (var i = 0; i < primary.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    primary[i],
                  ],
                  if (secondary.isNotEmpty)
                    TextButtonTheme(
                      data: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6B4A32),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      child: Wrap(alignment: WrapAlignment.center, children: secondary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────
// ORTAK BILDIRIM POPUP'I: eski sistem SnackBar'larinin (alttaki seritlerin)
// yerine. Oyunun susleme panelli diyaloguyla acilir, [autoCloseMs] sonra
// kendiliginden kapanir ya da "Tamam"a basilinca kapanir. Yeni bir popup
// acilirsa eskisi kapanir (SnackBar'daki hideCurrentSnackBar gibi).
// ─────────────────────────────────────────────────────────────────────
VoidCallback? _dismissCurrentPopup;

Future<void> showGamePopup(
  BuildContext context,
  String message, {
  String? title,
  int autoCloseMs = 2200,
}) async {
  if (!context.mounted) return;
  _dismissCurrentPopup?.call();
  var closed = false;
  Timer? timer;
  ModalRoute<dynamic>? route;
  BuildContext? dialogCtx;

  void dismiss() {
    if (closed) return;
    final c = dialogCtx;
    final r = route;
    // Ustune baska bir diyalog acildiysa ona dokunma.
    if (c != null && c.mounted && r != null && r.isCurrent) {
      closed = true;
      timer?.cancel();
      Navigator.of(c).pop();
    }
  }

  _dismissCurrentPopup = dismiss;
  if (autoCloseMs > 0) timer = Timer(Duration(milliseconds: autoCloseMs), dismiss);

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black45,
    builder: (ctx) {
      dialogCtx = ctx;
      route = ModalRoute.of(ctx);
      return GameAlertDialog(
        title: title == null ? null : Text(title),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF6B4A32)),
        ),
        actions: [
          FilledButton(onPressed: dismiss, child: Text(AppStrings.instance.t('ok'))),
        ],
      );
    },
  ).whenComplete(() {
    closed = true;
    timer?.cancel();
    if (identical(_dismissCurrentPopup, dismiss)) _dismissCurrentPopup = null;
  });
}
