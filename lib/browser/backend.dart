import 'package:flutter/widgets.dart';

import 'webview_backend.dart';

/// Mini-brauzer dvigateli. Ekran faqat shu interfeysga tayanadi: telefonda WebView, testlarda soxta ob'ekt.
abstract class BrowserBackend {
  void Function(String url)? onPageStarted;
  void Function(String url)? onPageFinished;
  void Function(int percent)? onProgress;

  /// Sahifa skripti (detektor) yuborgan xabar
  void Function(String message)? onMessage;

  Widget view();
  Future<void> load(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<String?> currentUrl();

  /// Yuklashda ishlatiladigan sarlavhalar: Referer, Cookie, User-Agent
  Future<Map<String, String>> requestHeaders(Uri page);

  void dispose();
}

BrowserBackend Function() browserBackendFactory = () => WebViewBackend();
