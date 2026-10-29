import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/localization.dart';
import '../theme/app_colors.dart';

/// Gizlilik Politikasi / Kullanim Sartlari gibi yasal sayfalari,
/// kullaniciyi oyundan/uygulamadan HIC CIKARMADAN, uygulama icinde
/// (in-app WebView) gosteren ekran. Geri tusu/AppBar geri oku sadece bu
/// ekrani kapatir, oyuna geri doner - harici tarayiciya gecis yapmaz.
class LegalWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const LegalWebViewScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<LegalWebViewScreen> createState() => _LegalWebViewScreenState();
}

class _LegalWebViewScreenState extends State<LegalWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.spaceTop)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _failed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.spaceTop,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.accentSoft),
              ),
            if (_failed && !_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: AppColors.textSecondary, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        t('legal_loadFailed'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                        ),
                        onPressed: () {
                          setState(() => _failed = false);
                          _controller.reload();
                        },
                        child: Text(t('legal_retry')),
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
